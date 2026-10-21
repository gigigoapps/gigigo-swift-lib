//
//  Request+ResponseLoading.swift
//  GIGLibrary
//

import Foundation

extension Request {
    /// Image requests opt into a byte budget; generic requests retain their existing transport.
    func responseData(for request: URLRequest, session: URLSession) async throws -> (Data, URLResponse) {
        guard let limit = self.maximumResponseBytes else {
            return try await session.data(for: request)
        }
        let (bytes, response) = try await session.bytes(for: request)
        // Cancel on early length rejection, byte overflow, or caller cancellation.
        defer { bytes.task.cancel() }
        return try await withTaskCancellationHandler {
            guard limit > 0, response.expectedContentLength <= Int64(limit) else {
                throw URLError(.dataLengthExceedsMaximum)
            }
            var data = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < limit else {
                    throw URLError(.dataLengthExceedsMaximum)
                }
                data.append(byte)
            }
            return (data, response)
        } onCancel: {
            bytes.task.cancel()
        }
    }
}
