//
//  Request.swift
//  MCDonald
//
//  Created by Alejandro Jiménez Agudo on 4/2/16.
//  Copyright © 2016 Gigigo SL. All rights reserved.
//

import Foundation

public enum StandardType {
    case gigigo
    case basic
}

/// See https://tools.ietf.org/html/rfc7231#section-4.3
public enum HTTPMethod: String {
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

    private var bodyParamsArray: [[String: Any]]?
    private var logInfo: RequestLogInfo?
    private var networkLogManager: NetworkLogManaging
    var cache: NSURLRequest.CachePolicy = NSURLRequest.CachePolicy.useProtocolCachePolicy
	
	private var request: URLRequest?
	private weak var task: URLSessionTask?
    private let reachability: ReachabilityInput
    private let sessionConfiguration: URLSessionConfiguration?
    private let session: URLSession?

    public typealias CompletionHandler = @MainActor @Sendable (Response) -> Void

    // Async APIs return Response and never throw; callers should inspect Response.status and Response.error.
    public func fetch() async -> Response {
        guard let request = self.buildRequest() else {
            return Response.invalidURL()
        }
        guard self.reachability.isReachable() else {
            return Response.noInternet()
        }
        self.request = request
        self.logRequest()
        self.cancel()

        let session = self.configuredSession(applyCache: true)
        defer {
            session.finishTasksAndInvalidate()
        }

        if Task.isCancelled {
            self.logRequestError(message: "Request cancelled before execution.")
            return Response.cancelled()
        }

        do {
            let (data, urlResponse) = try await session.data(for: request)
            let response = Response(
                successData: data,
                response: urlResponse,
                standardType: self.standardType,
                networkLogManager: self.networkLogManager
            )
            self.logIfVerbose(response)
            return response
        } catch is CancellationError {
            self.logRequestError(message: "Request cancelled during execution.")
            return Response.cancelled()
        } catch {
            self.logRequestError(message: error.localizedDescription)
            return Response(
                error: error,
                standardType: self.standardType,
                networkLogManager: self.networkLogManager
            )
        }
    }

    public func fetch(downloadTo fileURL: URL) async -> Response {
        guard let request = self.buildRequest() else {
            return Response.invalidURL()
        }
        guard self.reachability.isReachable() else {
            return Response.noInternet()
        }
        self.request = request
        self.logRequest()
        self.cancel()

        let session = self.configuredSession(applyCache: false)
        defer {
            session.finishTasksAndInvalidate()
        }

        if Task.isCancelled {
            self.logRequestError(message: "Request cancelled before execution.")
            return Response.cancelled()
        }

        do {
            let (location, urlResponse) = try await session.download(for: request)
            let response = Response(
                successData: nil,
                response: urlResponse,
                standardType: .basic,
                networkLogManager: self.networkLogManager
            )

            try self.replaceDownloadedFile(at: location, destination: fileURL)
            response.statusCode = 200

            self.logIfVerbose(response)
            return response
        } catch is CancellationError {
            self.logRequestError(message: "Request cancelled during execution.")
            return Response.cancelled()
        } catch {
            self.logRequestError(message: error.localizedDescription)
            return Response(
                error: error,
                standardType: .basic,
                networkLogManager: self.networkLogManager
            )
        }
    }

    public func upload(files: [FileUploadData], params: [String: Any]) async -> Response {
        guard var request = self.buildRequest(), let boundary = self.generateBoundary() else {
            return Response.invalidURL()
        }
        guard self.reachability.isReachable() else {
            return Response.noInternet()
        }

        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let bodyData = self.buildUploadData(files: files, params: params, boundary: boundary)
        var requestForLog = request
        requestForLog.httpBody = bodyData
        self.request = requestForLog
        self.logRequest()
        self.cancel()

        let session = self.configuredSession(applyCache: false)
        defer {
            session.finishTasksAndInvalidate()
        }

        if Task.isCancelled {
            self.logRequestError(message: "Request cancelled before execution.")
            return Response.cancelled()
        }

        do {
            let (data, urlResponse) = try await session.upload(for: request, from: bodyData)
            let response = Response(
                successData: data,
                response: urlResponse,
                standardType: self.standardType,
                networkLogManager: self.networkLogManager
            )
            self.logIfVerbose(response)
            return response
        } catch is CancellationError {
            self.logRequestError(message: "Request cancelled during execution.")
            return Response.cancelled()
        } catch {
            self.logRequestError(message: error.localizedDescription)
            return Response(
                error: error,
                standardType: self.standardType,
                networkLogManager: self.networkLogManager
            )
        }
    }
    
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
    
    public func fetch(completionHandler: @escaping CompletionHandler) {
		guard let request = self.buildRequest() else {
            Task { @MainActor in
                completionHandler(Response.invalidURL())
            }
            return
        }
        guard self.reachability.isReachable() else {
            let response = Response.noInternet()
            Task { @MainActor in
                completionHandler(response)
            }
            return
        }
		self.request = request
        self.logRequest()
		self.cancel()
        
        let session = self.configuredSession(applyCache: true)
        
		self.task = session.dataTask(with: request) { data, urlResponse, error in
            
            defer {
                session.finishTasksAndInvalidate()
            }
            
            let response = Response(data: data, response: urlResponse, error: error, standardType: self.standardType, networkLogManager: self.networkLogManager)
			
			if self.verbose {
				response.logResponse(self.logInfo)
			}
			
            Task { @MainActor in
                completionHandler(response)
            }
		}
		
		self.task?.resume()
	}
    
    public func fetch(withDownloadUrlFile: URL, completionHandler: @escaping CompletionHandler) {
        guard let request = self.buildRequest() else {
            Task { @MainActor in
                completionHandler(Response.invalidURL())
            }
            return
        }
        guard self.reachability.isReachable() else {
            let response = Response.noInternet()
            Task { @MainActor in
                completionHandler(response)
            }
            return
        }
        self.request = request
        self.logRequest()
        self.cancel()
        
        let session = self.configuredSession(applyCache: false)

        self.task = session.downloadTask(with: request) { location, response, error in
            guard let location = location else {
                LogWarn("Location of file is nil")
                Task { @MainActor in
                    completionHandler(Response(data: nil, response: nil, error: ErrorInstantiation.instantiateIntial))
                }
                return
            }
            
            let response = Response(data: nil, response: response, error: error, standardType: StandardType.basic, networkLogManager: self.networkLogManager)
            
            do {
                if FileManager.default.fileExists(atPath: withDownloadUrlFile.path) {
                    try FileManager.default.removeItem(at: withDownloadUrlFile)
                }
                try FileManager.default.moveItem(at: location, to: withDownloadUrlFile)
                response.statusCode = 200
            } catch let error {
                LogWarn(error.localizedDescription)
            }
            
            if self.verbose {
                response.logResponse(self.logInfo)
            }
            
            Task { @MainActor in
                completionHandler(response)
            }
        }
        
        self.task?.resume()
    }
    
    /**
    Upload a set of files with a `multipart` request
    
    - parameters:
        - files: Collection of `FileUploadData` with file information and data
        - params: The  rest of parameters that are not files
        - completionHandler: Completion closure for managing response
    
    - Author: Jerilyn Gonçalves
    - Since: 3.4.8
    */
    public func upload(files: [FileUploadData], params: [String: Any], completionHandler: @escaping CompletionHandler) {
        
        guard var request = self.buildRequest(), let boundary = self.generateBoundary() else {
            Task { @MainActor in
                completionHandler(Response.invalidURL())
            }
            return
        }
        guard self.reachability.isReachable() else {
            let response = Response.noInternet()
            Task { @MainActor in
                completionHandler(response)
            }
            return
        }
        
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let bodyData = self.buildUploadData(files: files, params: params, boundary: boundary)
        var requestForLog = request
        requestForLog.httpBody = bodyData
        self.request = requestForLog
        self.logRequest()
        self.cancel()
        
        let session = self.configuredSession(applyCache: false)
        
        self.task = session.uploadTask(with: request, from: bodyData, completionHandler: { data, urlResponse, error in
            
            let response = Response(data: data, response: urlResponse, error: error, standardType: self.standardType, networkLogManager: self.networkLogManager)

            if self.verbose {
                response.logResponse(self.logInfo)
            }
            
            Task { @MainActor in
                completionHandler(response)
            }
        })
        
        self.task?.resume()
    }
	
	public func cancel() {
		self.task?.cancel()
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

    private func configuredSession(applyCache: Bool) -> URLSession {
        if let session = self.session {
            return session
        }

        let configuration = self.sessionConfiguration ?? URLSessionConfiguration.default
        configuration.timeoutIntervalForResource = self.timeout
        configuration.waitsForConnectivity = true
        if applyCache {
            self.controlCache(config: configuration)
        }
        return URLSession(configuration: configuration, delegate: self as? URLSessionDelegate, delegateQueue: nil)
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

    private func replaceDownloadedFile(at sourceURL: URL, destination destinationURL: URL) throws {
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
    }
	
	fileprivate func buildRequest() -> URLRequest? {
        var finalURL: URL?

        // Compose URL
        if let urlString = self.buildURL() {
            finalURL = addParams(to: URLComponents(string: urlString))
        }
        
        guard let url = finalURL else { 
            if self.verbose {
                let error = "not a valid URL"
                self.networkLogManager.log(error, info: self.logInfo)
            }
            return nil
        }

        // Compose request
		var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: self.timeout)
		request.httpMethod = self.method.rawValue
		request.allHTTPHeaderFields = self.headers
        if request.allHTTPHeaderFields?.keys.contains(where: { $0.caseInsensitiveCompare("Accept") == .orderedSame }) != true {
            request.addValue("application/json", forHTTPHeaderField: "Accept")
        }
		
		// Set body is not GET
		if self.method != .get {
            if let bodyParamsArray = self.bodyParamsArray {
                request.httpBody = JSON(from: bodyParamsArray).toData()
            } else if let body = self.bodyParams {
                request.httpBody = JSON(from: body).toData()
            }
			
			// Add Content-Type if it wasn't set
			if request.allHTTPHeaderFields?.keys.contains(where: { $0.caseInsensitiveCompare("Content-Type") == .orderedSame }) != true {
				request.addValue("application/json", forHTTPHeaderField: "Content-Type")
			}
		}
		
		return request
	}
	
    fileprivate func addParams(to urlComponents: URLComponents?) -> URL? {
        guard var urlComponents = urlComponents else { return nil }
        
        if let urlParams = self.urlParams?.map({ key, value in
            URLQueryItem(name: key, value: String(describing: value))
        }) {
            let urlConcat = concat(urlComponents.queryItems, urlParams)
            urlComponents.queryItems = urlConcat
        }
        guard let string = urlComponents.string else { return nil }
        return URL(string: string)
    }
    
    fileprivate func buildURL() -> String? {
        var url = URLComponents(string: self.baseURL)
        url?.path += self.endpoint
        
        return url?.string
    }
	
	fileprivate func logRequest() {
        guard self.verbose else { return }
        
        if self.logInfo == nil {
            LogManager.shared.logLevel = .debug
            LogManager.shared.appName = "GIGLibrary"
        }
        
        let log = RequestLogFormatter.buildRequestLog(request: self.request)
        self.networkLogManager.log(log, info: self.logInfo)
	}
    
    fileprivate func generateBoundary() -> String? {

        let lowerCaseLettersInASCII = UInt8(ascii: "a")...UInt8(ascii: "z")
        let upperCaseLettersInASCII = UInt8(ascii: "A")...UInt8(ascii: "Z")
        let digitsInASCII = UInt8(ascii: "0")...UInt8(ascii: "9")
        
        let sequenceOfRanges = [lowerCaseLettersInASCII, upperCaseLettersInASCII, digitsInASCII].joined()
        guard let toString = String(data: Data(sequenceOfRanges), encoding: .utf8) else { return nil }
        
        var randomString = ""
        for _ in 0..<20 { randomString += String(toString.randomElement()!) }
        
        let boundary = randomString + "\(Int(Date.timeIntervalSinceReferenceDate))"
        
        return boundary
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

func concat(_ lhs: [URLQueryItem]?, _ rhs: [URLQueryItem]?) -> [URLQueryItem] {
	guard let left = lhs else {
		return rhs ?? []
	}
	
	guard let right = rhs else {
		return left
	}
	
	return left + right
}
