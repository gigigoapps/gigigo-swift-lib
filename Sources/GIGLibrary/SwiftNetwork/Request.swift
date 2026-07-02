//
//  Request.swift
//  MCDonald
//
//  Created by Alejandro Jiménez Agudo on 4/2/16.
//  Copyright © 2016 Gigigo SL. All rights reserved.
//

import Foundation
import os

public enum StandardType: Sendable {
    case gigigo
    case basic
}

/// See https://tools.ietf.org/html/rfc7231#section-4.3
public enum HTTPMethod: String, Sendable {
    case get     = "GET"
    case post    = "POST"
    case put     = "PUT"
    case delete  = "DELETE"
    case options = "OPTIONS"
    case head    = "HEAD"
    case patch   = "PATCH"
    case trace   = "TRACE"
    case connect = "CONNECT"
}

public struct FileUploadData {
    var data: Data
    var mimeType: String
    var filename: String
    var name: String
    
    public init(data: Data, mimeType: String, filename: String, name: String) {
        self.data = data
        self.mimeType = mimeType
        self.filename = filename
        self.name = name
    }
}

// `internal` (not `private`) so `Request+URLBuilding.swift` can throw `.invalidURL` from the
// extracted URL-composition helpers.
enum RequestBuildError: Error {
    case invalidURL
    case bodyEncodingFailed
    case noInternet
    case cancelledBeforeExecution
}

extension URLError.Code {
    // Compatibility alias because this SDK does not expose `cannotEncodeContentData`.
    static var cannotEncodeContentData: URLError.Code { .cannotParseResponse }
}

/// `@unchecked Sendable` is sound by design under a single invariant: a `Request` is fully
/// configured before it is fetched and its configuration is never mutated across a concurrency
/// boundary. The only state mutated *while a fetch is in flight* is the cancellation handle, and
/// that handle is guarded by `inFlight` (an `OSAllocatedUnfairLock`). `cancel()` may therefore be
/// called safely from any thread/actor (e.g. `ImageDownloader` on the `MainActor`) concurrently
/// with the `@concurrent` fetch body that runs on a background executor.
public class Request: Selfie, @unchecked Sendable {

    public var method: HTTPMethod
    public var baseURL: String
    public var endpoint: String
    public var headers: [String: String]?
    public var urlParams: [String: Any]?
    public var bodyParams: [String: Any]?
    public var verbose = false
    public var standardType: StandardType = .gigigo
    public var timeout: TimeInterval = 15.0

    var cache = NSURLRequest.CachePolicy.useProtocolCachePolicy

    private var bodyParamsArray: [[String: Any]]?
    private var encodableBodyProvider: (() throws -> Data)?
    private var logInfo: RequestLogInfo?
    private var networkLogManager: NetworkLogManaging
	
    /// Lock-protected cancellation state for the in-flight network operation. Replaces the former
    /// unsynchronized `cancelInFlight` closure (read/written from the background fetch executor
    /// while `cancel()` could run from another thread — a genuine data race `@unchecked Sendable`
    /// hid). `internal` rather than `private` only so the cancellation machinery can live in
    /// `Request+Cancellation.swift`, which is where the generation scheme is documented.
    struct InFlightCancellation {
        var generation = 0
        var cancel: (@Sendable () -> Void)?
        var cancelRequestedGeneration: Int?
    }

    let inFlight = OSAllocatedUnfairLock(initialState: InFlightCancellation())

    private let reachability: ReachabilityInput
    private let sessionConfiguration: URLSessionConfiguration?
    private let session: URLSession?

    public convenience init(
        method: HTTPMethod = .get,
        baseUrl: String,
        endpoint: String,
        headers: [String: String]? = nil,
        urlParams: [String: Any]? = nil,
        bodyParams: [String: Any]? = nil,
        timeout: TimeInterval? = nil,
        verbose: Bool = false,
        standard: StandardType = .gigigo
    ) {
        self.init(
            method: method,
            baseUrl: baseUrl,
            endpoint: endpoint,
            headers: headers,
            urlParams: urlParams,
            bodyParams: bodyParams,
            bodyParamsArray: nil,
            encodableBodyProvider: nil,
            timeout: timeout,
            verbose: verbose,
            standard: standard,
            logInfo: nil,
            networkLogManager: DefaultNetworkLogManager(),
            sessionConfiguration: nil,
            session: nil,
            reachability: ReachabilityWrapper.shared
        )
    }

    public convenience init(
        method: HTTPMethod = .get,
        baseUrl: String,
        endpoint: String,
        headers: [String: String]? = nil,
        urlParams: [String: Any]? = nil,
        bodyParamsArray: [[String: Any]]? = nil,
        timeout: TimeInterval? = nil,
        verbose: Bool = false,
        standard: StandardType = .gigigo
    ) {
        self.init(
            method: method,
            baseUrl: baseUrl,
            endpoint: endpoint,
            headers: headers,
            urlParams: urlParams,
            bodyParams: nil,
            bodyParamsArray: bodyParamsArray,
            encodableBodyProvider: nil,
            timeout: timeout,
            verbose: verbose,
            standard: standard,
            logInfo: nil,
            networkLogManager: DefaultNetworkLogManager(),
            sessionConfiguration: nil,
            session: nil,
            reachability: ReachabilityWrapper.shared
        )
    }

    public convenience init<Body: Encodable>(
        method: HTTPMethod = .get,
        baseUrl: String,
        endpoint: String,
        headers: [String: String]? = nil,
        urlParams: [String: Any]? = nil,
        body: Body,
        timeout: TimeInterval? = nil,
        verbose: Bool = false,
        standard: StandardType = .gigigo
    ) {
        self.init(
            method: method,
            baseUrl: baseUrl,
            endpoint: endpoint,
            headers: headers,
            urlParams: urlParams,
            bodyParams: nil,
            bodyParamsArray: nil,
            encodableBodyProvider: { try JSONEncoder().encode(body) },
            timeout: timeout,
            verbose: verbose,
            standard: standard,
            logInfo: nil,
            networkLogManager: DefaultNetworkLogManager(),
            sessionConfiguration: nil,
            session: nil,
            reachability: ReachabilityWrapper.shared
        )
    }

    init(
        method: HTTPMethod = .get,
        baseUrl: String,
        endpoint: String,
        headers: [String: String]? = nil,
        urlParams: [String: Any]? = nil,
        bodyParams: [String: Any]? = nil,
        bodyParamsArray: [[String: Any]]? = nil,
        encodableBodyProvider: (() throws -> Data)? = nil,
        timeout: TimeInterval? = nil,
        verbose: Bool = false,
        standard: StandardType = .gigigo,
        logInfo: RequestLogInfo? = nil,
        networkLogManager: NetworkLogManaging = DefaultNetworkLogManager(),
        sessionConfiguration: URLSessionConfiguration? = nil,
        session: URLSession? = nil,
        reachability: ReachabilityInput = ReachabilityWrapper.shared
    ) {
        self.method = method
        self.headers = headers
        self.urlParams = urlParams
        self.bodyParams = bodyParams
        self.bodyParamsArray = bodyParamsArray
        self.encodableBodyProvider = encodableBodyProvider
        self.timeout = timeout ?? self.timeout
        self.verbose = verbose
        self.standardType = standard
        self.logInfo = logInfo
        self.networkLogManager = networkLogManager
        self.sessionConfiguration = sessionConfiguration
        self.session = session
        self.reachability = reachability

        self.baseURL = baseUrl
        self.endpoint = endpoint
    }
    
    // MARK: - Public API

    // Async APIs return Response and never throw; callers should inspect Response.status and Response.error.
    @concurrent
    public func fetch() async -> Response {
        do {
            try self.preChecks()
            let request = try self.buildRequest()
            let (session, generation, ownsSession) = try self.prepareSession(for: request, applyCache: true)
            defer {
                if ownsSession {
                    session.finishTasksAndInvalidate()
                }
            }

            let operation = Task { try await session.data(for: request) }
            self.installCanceller({ operation.cancel() }, generation: generation)
            defer {
                self.clearCanceller(generation: generation)
            }

            let (data, urlResponse) = try await withTaskCancellationHandler {
                try await operation.value
            } onCancel: {
                operation.cancel()
            }
            let response = Response(
                successData: data,
                response: urlResponse,
                standardType: self.standardType,
                networkLogManager: self.networkLogManager
            )
            self.logIfVerbose(response)
            return response
        } catch let buildError as RequestBuildError {
            return self.response(for: buildError)
        } catch is CancellationError {
            self.logRequestError(message: "Request cancelled during execution.")
            return Response.cancelled()
        } catch {
            self.logRequestError(message: error.localizedDescription)
            return Response(error: error)
        }
    }

    @concurrent
    public func fetchDecodable<ResponseData: Decodable>() async throws -> ResponseData {
        let response = await self.fetch()

        guard response.status == .success else {
            throw FetchDecodableError.requestFailed(
                status: response.status,
                statusCode: response.statusCode,
                underlying: response.error
            )
        }

        let payload = self.payloadDataForDecoding(from: response)
        let usedEmptyPayloadFallback = payload == nil || payload?.isEmpty == true
        let dataToDecode = payload ?? Data("{}".utf8)
        let decoder = JSONDecoder()

        do {
            return try decoder.decode(ResponseData.self, from: dataToDecode)
        } catch {
            if usedEmptyPayloadFallback {
                throw FetchDecodableError.emptyResponseBody(statusCode: response.statusCode)
            }

            throw FetchDecodableError.decodingFailed(underlying: error)
        }
    }

    @concurrent
    public func fetchVoid() async throws {
        let response = await self.fetch()

        guard response.status == .success else {
            if let error = response.error {
                throw error
            }

            let fallbackError = NSError(
                domain: kGIGNetworkErrorDomain,
                code: response.statusCode,
                message: "Request failed with status \(response.status)"
            )
            throw fallbackError
        }
    }

    @concurrent
    public func fetch(downloadTo fileURL: URL) async -> Response {
        do {
            try self.preChecks()
            let request = try self.buildRequest()
            let (session, generation, ownsSession) = try self.prepareSession(for: request, applyCache: false)
            defer {
                if ownsSession {
                    session.finishTasksAndInvalidate()
                }
            }

            let operation = Task { try await session.download(for: request) }
            self.installCanceller({ operation.cancel() }, generation: generation)
            defer {
                self.clearCanceller(generation: generation)
            }

            let (location, urlResponse) = try await withTaskCancellationHandler {
                try await operation.value
            } onCancel: {
                operation.cancel()
            }
            let response = Response(
                successData: nil,
                response: urlResponse,
                standardType: .basic,
                networkLogManager: self.networkLogManager
            )
            if response.status == .success {
                try self.replaceDownloadedFile(at: location, destination: fileURL)
            }
            self.logIfVerbose(response)
            return response
        } catch let buildError as RequestBuildError {
            return self.response(for: buildError)
        } catch is CancellationError {
            self.logRequestError(message: "Request cancelled during execution.")
            return Response.cancelled()
        } catch {
            self.logRequestError(message: error.localizedDescription)
            return Response(error: error)
        }
    }

    @concurrent
    public func upload(files: [FileUploadData], params: [String: Any]) async -> Response {
        do {
            try self.preChecks()
            let (request, bodyData) = try self.buildUploadRequest(files: files, params: params)
            let (session, generation, ownsSession) = try self.prepareSession(for: request, bodyForLog: bodyData, applyCache: false)
            defer {
                if ownsSession {
                    session.finishTasksAndInvalidate()
                }
            }

            let operation = Task { try await session.upload(for: request, from: bodyData) }
            self.installCanceller({ operation.cancel() }, generation: generation)
            defer {
                self.clearCanceller(generation: generation)
            }

            let (data, urlResponse) = try await withTaskCancellationHandler {
                try await operation.value
            } onCancel: {
                operation.cancel()
            }
            let response = Response(
                successData: data,
                response: urlResponse,
                standardType: self.standardType,
                networkLogManager: self.networkLogManager
            )
            self.logIfVerbose(response)
            return response
        } catch let buildError as RequestBuildError {
            return self.response(for: buildError)
        } catch is CancellationError {
            self.logRequestError(message: "Request cancelled during execution.")
            return Response.cancelled()
        } catch {
            self.logRequestError(message: error.localizedDescription)
            return Response(error: error)
        }
    }

	// MARK: - Private Helpers
    
    private func controlCache(config: URLSessionConfiguration) {
        config.requestCachePolicy = self.cache
        switch self.cache {
        case .reloadIgnoringLocalAndRemoteCacheData, .reloadRevalidatingCacheData, .reloadIgnoringLocalCacheData:
            config.urlCache = nil
        default:
            break
        }
    }

    /// Returns the session to use plus whether this instance *owns* it. An injected `self.session`
    /// is owned by the caller and may back other in-flight tasks, so the fetch flow must never
    /// invalidate it; only sessions created here are torn down with `finishTasksAndInvalidate()`.
    private func configuredSession(applyCache: Bool) -> (session: URLSession, ownsSession: Bool) {
        if let session = self.session {
            return (session, false)
        }

        let configuration = self.sessionConfiguration ?? URLSessionConfiguration.default
        configuration.timeoutIntervalForResource = self.timeout
        configuration.waitsForConnectivity = true
        if applyCache {
            self.controlCache(config: configuration)
        }
        let session = URLSession(configuration: configuration, delegate: self as? URLSessionDelegate, delegateQueue: nil)
        return (session, true)
    }

    private func logIfVerbose(_ response: Response) {
        if self.verbose {
            response.logResponse(self.logInfo)
        }
    }

    private func logRequestError(message: String) {
        guard self.verbose else { return }
        self.networkLogManager.log(message, info: self.logInfo)
    }

    // `internal` (not `private`) so `composeURL` in `Request+URLBuilding.swift` can report an
    // unbuildable URL; the logging state it touches (`networkLogManager`, `logInfo`) is private.
    func logInvalidURLBuildError() {
        guard self.verbose else { return }
        self.networkLogManager.log("not a valid URL", info: self.logInfo)
    }

    private func preChecks() throws {
        guard self.reachability.isReachable() else {
            throw RequestBuildError.noInternet
        }
    }

    private func payloadDataForDecoding(from response: Response) -> Data? {
        switch self.standardType {
        case .gigigo:
            return response.data?.toData()
        case .basic:
            return response.body
        }
    }

    private func response(for buildError: RequestBuildError) -> Response {
        switch buildError {
        case .invalidURL:
            return Response.invalidURL()
        case .bodyEncodingFailed:
            let response = Response.cannotEncodeContentData()
            self.logRequestError(message: response.error?.localizedDescription ?? "Cannot encode request body.")
            return response
        case .noInternet:
            return Response.noInternet()
        case .cancelledBeforeExecution:
            return Response.cancelled()
        }
    }

    private func replaceDownloadedFile(at sourceURL: URL, destination destinationURL: URL) throws {
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
    }

    private func prepareSession(
        for request: URLRequest,
        bodyForLog: Data? = nil,
        applyCache: Bool
    ) throws -> (session: URLSession, generation: Int, ownsSession: Bool) {
        var requestForLog = request
        if let bodyForLog {
            requestForLog.httpBody = bodyForLog
        }
        self.logRequest(requestForLog)
        // Opens this attempt's cancellation scope (and cancels any prior in-flight attempt on this
        // instance) at the same point the legacy synchronous `cancel()` ran, before the session is
        // configured — so a superseding `fetch()` tears the previous one down without a timing shift.
        let generation = self.beginCancellationScope()

        let (session, ownsSession) = self.configuredSession(applyCache: applyCache)
        if Task.isCancelled {
            // The caller installs `defer { session.finishTasksAndInvalidate() }` only on the
            // returned value, so invalidate here before throwing or this session (and the delegate
            // it retains) would leak until ARC reclaims it. Only sessions we created may be
            // invalidated — an injected session is the caller's to manage.
            if ownsSession {
                session.finishTasksAndInvalidate()
            }
            self.logRequestError(message: "Request cancelled before execution.")
            throw RequestBuildError.cancelledBeforeExecution
        }
        return (session, generation, ownsSession)
    }

    private func buildUploadRequest(
        files: [FileUploadData],
        params: [String: Any]
    ) throws -> (request: URLRequest, bodyData: Data) {
        guard let boundary = self.generateBoundary() else {
            throw RequestBuildError.invalidURL
        }

        var request = try self.buildRequest()
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let bodyData = self.buildUploadData(files: files, params: params, boundary: boundary)
        return (request, bodyData)
    }
	
    fileprivate func buildRequest() throws -> URLRequest {
        let url = try self.composeURL()
        var request = self.composeBaseRequest(url: url)
        try self.applyBodyAndContentTypeIfNeeded(to: &request)
        return request
    }

    private func composeBaseRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: self.timeout)
        request.httpMethod = self.method.rawValue
        request.allHTTPHeaderFields = self.headers
        self.addAcceptHeaderIfNeeded(to: &request)
        return request
    }

    private func applyBodyAndContentTypeIfNeeded(to request: inout URLRequest) throws {
        guard self.method != .get else {
            return
        }

        request.httpBody = try self.encodedBodyData()
        self.addContentTypeHeaderIfNeeded(to: &request)
    }

    private func encodedBodyData() throws -> Data? {
        try self.encodedBodyDataFromBodyParamsArray()
            ?? self.encodedBodyDataFromBodyParams()
            ?? self.encodedBodyDataFromEncodableProvider()
    }

    private func encodedBodyDataFromBodyParamsArray() throws -> Data? {
        guard let bodyParamsArray else { return nil }
        guard let bodyData = JSON(from: bodyParamsArray).toData() else {
            throw RequestBuildError.bodyEncodingFailed
        }
        return bodyData
    }

    private func encodedBodyDataFromBodyParams() throws -> Data? {
        guard let bodyParams else { return nil }
        guard let bodyData = JSON(from: bodyParams).toData() else {
            throw RequestBuildError.bodyEncodingFailed
        }
        return bodyData
    }

    private func encodedBodyDataFromEncodableProvider() throws -> Data? {
        guard self.encodableBodyProvider != nil else { return nil }
        guard let bodyData = try? self.encodableBodyProvider?() else {
            throw RequestBuildError.bodyEncodingFailed
        }
        return bodyData
    }

    private func addAcceptHeaderIfNeeded(to request: inout URLRequest) {
        if request.allHTTPHeaderFields?.keys.contains(where: { $0.caseInsensitiveCompare("Accept") == .orderedSame }) != true {
            request.addValue("application/json", forHTTPHeaderField: "Accept")
        }
    }

    private func addContentTypeHeaderIfNeeded(to request: inout URLRequest) {
        if request.allHTTPHeaderFields?.keys.contains(where: { $0.caseInsensitiveCompare("Content-Type") == .orderedSame }) != true {
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        }
    }

	fileprivate func logRequest(_ request: URLRequest) {
        guard self.verbose else { return }

        if self.logInfo == nil {
            LogManager.shared.logLevel = .debug
            LogManager.shared.appName = "GIGLibrary"
        }

        let log = RequestLogFormatter.buildRequestLog(request: request)
        self.networkLogManager.log(log, info: self.logInfo)
	}
    
    fileprivate func generateBoundary() -> String? {

        let lowerCaseLettersInASCII = UInt8(ascii: "a")...UInt8(ascii: "z")
        let upperCaseLettersInASCII = UInt8(ascii: "A")...UInt8(ascii: "Z")
        let digitsInASCII = UInt8(ascii: "0")...UInt8(ascii: "9")
        
        let sequenceOfRanges = [lowerCaseLettersInASCII, upperCaseLettersInASCII, digitsInASCII].joined()
        guard let toString = String(data: Data(sequenceOfRanges), encoding: .utf8) else { return nil }
        
        var randomString = ""
        // toString is non-empty by construction (3 ASCII ranges joined)
        for _ in 0..<20 {
            // swiftlint:disable:next force_unwrapping
            randomString += String(toString.randomElement()!)
        }
        
        
        return randomString + "\(Int(Date.timeIntervalSinceReferenceDate))"
    }
    
    fileprivate func buildUploadData(files: [FileUploadData], params: [String: Any], boundary: String) -> Data {
        var data = Data()
        let boundaryData = Data("\r\n--\(boundary)\r\n".utf8)

        for (key, value) in params {
            let keyData = Data("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".utf8)
            let valueData = Data("\(value)".utf8)
            data.append(boundaryData)
            data.append(keyData)
            data.append(valueData)
        }
        
        for file in files {
            let contentDispositionData = Data("Content-Disposition: form-data; name=\"\(file.name)\"; filename=\"\(file.filename)\"\r\n".utf8)
            let contentTypeData = Data("Content-Type: \(file.mimeType)\r\n\r\n".utf8)
            data.append(boundaryData)
            data.append(contentDispositionData)
            data.append(contentTypeData)
            data.append(file.data)
        }
        data.append(boundaryData)
        return data
    }
}

// MARK: - Selfie

extension Request {
    /// Only non-sensitive routing/config fields are printable via `Selfie`.
    /// Everything else — `headers` (auth tokens), `urlParams`/`bodyParams`/
    /// `bodyParamsArray`/`encodableBodyProvider` (request payloads) and internal
    /// collaborators — is redacted so reflection never leaks secrets into logs.
    ///
    /// `baseURL`/`endpoint` are exposed only when they carry no embedded
    /// credential. A caller may pass a query string or userinfo
    /// (`user:pass@host`, `?access_token=…`) inside `baseUrl`/`endpoint`, and the
    /// URL builder preserves it, so printing it verbatim would defeat the
    /// redaction of `urlParams`. When either contains userinfo, a query or a
    /// fragment it is redacted instead (fail-closed on unparseable input).
    public var selfieExposedKeys: Set<String>? {
        var keys: Set<String> = ["method", "verbose", "standardType", "timeout", "cache"]
        if Request.isCredentialFreeURLComponent(self.baseURL) { keys.insert("baseURL") }
        if Request.isCredentialFreeURLComponent(self.endpoint) { keys.insert("endpoint") }
        return keys
    }

    /// `true` when `string` parses as a URL (or URL fragment) with no userinfo,
    /// query or fragment — nowhere a secret could hide. Input that fails to parse
    /// (rare — `URLComponents` is lenient) is treated as unsafe and redacted.
    private static func isCredentialFreeURLComponent(_ string: String) -> Bool {
        guard let components = URLComponents(string: string) else { return false }
        return components.user == nil
            && components.password == nil
            && components.query == nil
            && components.fragment == nil
    }
}
