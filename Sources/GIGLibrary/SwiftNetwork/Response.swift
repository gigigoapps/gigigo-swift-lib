//
//  Response.swift
//  MCDonald
//
//  Created by Alejandro Jiménez Agudo on 4/2/16.
//  Copyright © 2016 Gigigo SL. All rights reserved.
//

import Foundation
import UIKit


public let kGIGNetworkErrorDomain = "com.gigigo.network"
public let kGIGNetworkErrorMessage = "GIGNETWORK_ERROR_MESSAGE"


public enum ResponseStatus: Sendable {
	case success
	case errorParsingJson
	case sessionExpired
	case timeout
	case noInternet
	case apiError
	case unknownError
	case untrustedCertificate
}

public enum ResponseError: Error {
	case bodyNil
	case unexpectedDataType
}

/// `@unchecked Sendable` is sound by design under one invariant: a `Response` is fully populated
/// inside `init` (including the `parseJSON`/`parseError` it drives) and is never mutated afterwards.
/// `fetch()` constructs it, returns it, and hands ownership to the caller without retaining a
/// mutable reference — so although it crosses a concurrency boundary, only one context ever touches
/// it at a time. Every stored property is therefore exposed as `public private(set)`: consumers read
/// it, no one outside the type can mutate it post-init. `data` is a `JSON` (a mutable reference
/// type); it too is built during `init` and neither shared nor mutated afterwards. Hardening `JSON`
/// itself into a value/Sendable type is tracked separately (C048).
public class Response: Selfie, @unchecked Sendable {

	public private(set) var status: ResponseStatus
	public private(set) var statusCode: Int
	public private(set) var url: URL?
	public private(set) var headers: [AnyHashable: Any]?
	public private(set) var body: Data?
	public private(set) var data: JSON?
	public private(set) var error: NSError?

	private var networkLogManager: NetworkLogManaging
    private var standardType: StandardType = .gigigo
	
	
	// MARK: - Initializers
	
    init(data: Data?, response: URLResponse?, error: Error?, standardType: StandardType = .gigigo, networkLogManager: NetworkLogManaging = DefaultNetworkLogManager()) {
		self.status = .unknownError
		self.statusCode = 0
        self.networkLogManager = networkLogManager
        self.standardType = standardType
		self.error = error as NSError?
		if let response = response as? HTTPURLResponse {
			self.url = response.url
			self.headers = response.allHeaderFields
			self.body = data
			self.statusCode = response.statusCode
			
			if (200..<300).contains(self.statusCode) {
				self.status = .success
			}

            if self.shouldParseJSON(headers: self.headers, body: self.body) {
                self.parseJSON()
            }

            if !(200..<300).contains(self.statusCode), self.status == .unknownError {
                let fallbackError = NSError(
                    domain: kGIGNetworkErrorDomain,
                    code: self.statusCode,
                    message: "HTTP error \(self.statusCode)"
                )
                self.error = fallbackError
                self.status = self.parseError(error: fallbackError)
            }
		} else {
			self.statusCode = self.error?.code ?? -1
			self.status = self.parseError(error: self.error)
		}
	}

    convenience init(successData: Data?, response: URLResponse?, standardType: StandardType = .gigigo, networkLogManager: NetworkLogManaging = DefaultNetworkLogManager()) {
        self.init(data: successData, response: response, error: nil, standardType: standardType, networkLogManager: networkLogManager)
    }

    convenience init(error: Error?, standardType: StandardType = .gigigo, networkLogManager: NetworkLogManaging = DefaultNetworkLogManager()) {
        self.init(data: nil, response: nil, error: error, standardType: standardType, networkLogManager: networkLogManager)
    }
	
    // MARK: - Public API

    func json() throws -> JSON {
		guard let json = self.data else {
			throw ResponseError.bodyNil
		}
		
		return json
	}
	
    @MainActor
    func image() throws -> UIImage {
		guard let imageData = self.body else {
			throw ResponseError.bodyNil
		}

        // GIFs need the animated decoder: `UIImage(data:)` only yields the first frame, and the
        // previous code rejected them outright — so a managed download (e.g. `ImageDownloader`)
        // spent a network slot only to discard the result silently. Decode them properly here.
        if self.isGifURL() {
            guard let image = UIImage.gif(data: imageData) else {
                throw ResponseError.unexpectedDataType
            }
            return image
        }

        guard let image = UIImage(data: imageData, scale: UIScreen.main.scale) else {
            throw ResponseError.unexpectedDataType
        }
        return image
	}

    // MARK: - Internal API
    
    class func noInternet() -> Response {
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet, message: "No Internet")
        return Response(data: nil, response: nil, error: error)
    }

    class func invalidURL() -> Response {
        let error = URLError(.badURL)
        return Response(error: error)
    }

    class func cancelled() -> Response {
        let error = URLError(.cancelled)
        return Response(error: error)
    }

    class func cannotEncodeContentData() -> Response {
        let error = URLError(.cannotEncodeContentData)
        return Response(error: error)
    }
		
    func logResponse() {
        self.logResponse(nil)
    }
	
    func logResponse(_ logInfo: RequestLogInfo?) {
        let log = ResponseLogFormatter.buildResponseLog(url: self.url, statusCode: self.statusCode, headers: self.headers, body: self.body)
        self.networkLogManager.log(log, info: logInfo)
	}

    // MARK: - Private Helpers
    
    private func isGifURL() -> Bool {
        guard let url else {
            return false
        }
        return url.pathExtension.caseInsensitiveCompare("gif") == .orderedSame
    }

    private func shouldParseJSON(headers: [AnyHashable: Any]?, body: Data?) -> Bool {
        guard let body, !body.isEmpty else {
            return false
        }

        if let contentType = self.contentType(from: headers),
           contentType.localizedCaseInsensitiveContains("json") {
            return true
        }

        return self.bodyLooksLikeJSON(body)
    }

    private func contentType(from headers: [AnyHashable: Any]?) -> String? {
        guard let headers else { return nil }

        for (key, value) in headers {
            if let keyString = key as? String,
               keyString.caseInsensitiveCompare("Content-Type") == .orderedSame,
               let valueString = value as? String {
                return valueString
            }
        }

        return nil
    }

    private func bodyLooksLikeJSON(_ body: Data) -> Bool {
        guard let bodyString = String(data: body, encoding: .utf8) else {
            return false
        }

        let trimmed = bodyString.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("{") || trimmed.hasPrefix("[")
    }
		
	private func parseJSON() {
		guard
			let body = self.body,
			let json = try? JSON.dataToJson(body)
			else { return LogWarn("Response is not a JSON") }
		
        
        switch self.standardType {
        case .gigigo:
            let success = self.parseStatus(json: json)
            if success {
                self.status = .success
                self.data = json["data"]
            } else {
                self.status = self.parseError(json: json)
            }
        case .basic:
            self.data = json
        }
	}
	
	private func parseStatus(json: JSON) -> Bool {
		if let statusBool = json["status"]?.toBool() {
			return statusBool
		}
		if let statusString = json["status"]?.toString() {
			return statusString == "OK"
		}
			return false
	}
	
	private func parseError(json: JSON) -> ResponseStatus {
		let error = json["error"]
		
		guard
			let code = error?["code"]?.toInt(),
			let message = error?["message"]?.toString()
			else { return self.parseError(error: self.error) }
		
		let userInfo = [kGIGNetworkErrorMessage: message]
		self.error = NSError(domain: kGIGNetworkErrorDomain, code: code, userInfo: userInfo)
		
		return self.parseError(error: self.error)
	}
	
	fileprivate func parseError(error: NSError?) -> ResponseStatus {
		guard let err = error else { return .unknownError }
		
		self.statusCode = err.code
		
		switch err.code {
		case 401, 403:
			return .sessionExpired
		case -1001:
			return .timeout
		case -1009:
			return .noInternet
		case -1202:
			return .untrustedCertificate
		case 10000...20000:
			return .apiError
		default:
			return .unknownError
		}
	}
}
