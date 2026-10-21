//
//  Request+ResponseLoading.swift
//  GIGLibrary
//

import Foundation
import os

extension Request {
    /// Image requests opt into a byte budget; generic requests retain their existing transport.
    func responseData(for request: URLRequest, session: URLSession) async throws -> (Data, URLResponse) {
        guard let limit = self.maximumResponseBytes else {
            return try await session.data(for: request)
        }
        return try await BoundedResponseLoader(limit: limit).load(request, session: session)
    }
}

/// Per-task delegate: checks decoded transport bytes before appending them to the retained body.
/// The lock serializes delegate completion with cancellation from any executor.
private final class BoundedResponseLoader: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private struct State {
        var task: URLSessionDataTask?
        var continuation: CheckedContinuation<(Data, URLResponse), any Error>?
        var response: URLResponse?
        var data = Data()
        var finished = false
    }

    private let limit: Int
    private let state = OSAllocatedUnfairLock(initialState: State())

    init(limit: Int) { self.limit = limit }

    func load(_ request: URLRequest, session: URLSession) async throws -> (Data, URLResponse) {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let task = session.dataTask(with: request)
                task.delegate = self
                let cancelled = state.withLock { state in
                    guard !state.finished else { return true }
                    state.task = task
                    state.continuation = continuation
                    return false
                }
                if cancelled {
                    task.cancel()
                    continuation.resume(throwing: CancellationError())
                } else {
                    task.resume()
                }
            }
        } onCancel: {
            self.finish(error: CancellationError())
        }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard limit > 0, response.expectedContentLength <= Int64(limit) else {
            finish(error: URLError(.dataLengthExceedsMaximum))
            completionHandler(.cancel)
            return
        }
        let accepted = state.withLock { state in
            guard !state.finished else { return false }
            state.response = response
            return true
        }
        completionHandler(accepted ? .allow : .cancel)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let overflow = state.withLock { state in
            guard !state.finished else { return false }
            guard data.count <= limit - state.data.count else { return true }
            state.data.append(data)
            return false
        }
        if overflow { finish(error: URLError(.dataLengthExceedsMaximum)) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        finish(error: error)
    }

    private func finish(error: (any Error)?) {
        let completion = state.withLock { state -> (URLSessionDataTask?, CheckedContinuation<(Data, URLResponse), any Error>?, Result<(Data, URLResponse), any Error>)? in
            guard !state.finished else { return nil }
            state.finished = true
            let result: Result<(Data, URLResponse), any Error>
            if let error {
                result = .failure(error)
            } else if let response = state.response {
                result = .success((state.data, response))
            } else {
                result = .failure(URLError(.badServerResponse))
            }
            let completion = (state.task, state.continuation, result)
            state.task = nil
            state.continuation = nil
            state.data = Data()
            return completion
        }
        guard let (task, continuation, result) = completion else { return }
        task?.cancel()
        continuation?.resume(with: result)
    }
}
