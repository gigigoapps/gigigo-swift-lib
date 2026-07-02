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
/// type); it too is built during `init` and neither shared nor mutated afterwards. `JSON` is itself
/// `@unchecked Sendable` with an immutable (`let`) backing store (see `Json.swift`), so it upholds
/// the same write-once invariant this type relies on.
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

            // The HTTP status is authoritative: a non-2xx response must never be reported as
            // `.success`, even when a Gigigo envelope claims `status: true`/`"OK"` (which
            // `parseJSON()` would otherwise honour). If body parsing already mapped a specific
            // error (`.apiError`, `.sessionExpired`, …) keep it; only override a still-unknown or
            // wrongly-successful status with a synthesized HTTP error. Use the transport code from
            // `response` directly — `parseError(json:)` may have overwritten `self.statusCode` with
            // the envelope's application error code, which would lose the real HTTP status here.
            if !(200..<300).contains(response.statusCode), self.status == .unknownError || self.status == .success {
                let fallbackError = NSError(
                    domain: kGIGNetworkErrorDomain,
                    code: response.statusCode,
                    message: "HTTP error \(response.statusCode)"
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
	
    /// Decodes the response body into a `UIImage`. `nonisolated` and scale-injected on purpose: a
    /// `.gif` body can carry many/large frames and is network-controlled, so the (potentially heavy)
    /// decode must run off the main actor — `ImageDownloader` reads the scale on the main actor and
    /// then calls this from a detached task. GIFs decode as animated images; everything else as a
    /// single frame at `scale`. A GIF is recognised by the response URL's `.gif` extension OR the
    /// body's `GIF8` signature, so a GIF served from a URL without a `.gif` path still animates.
    func image(scale: CGFloat) throws -> UIImage {
		guard let imageData = self.body else {
			throw ResponseError.bodyNil
		}

        // GIFs need the animated decoder: `UIImage(data:)` only yields the first frame, and the
        // previous code rejected them outright — so a managed download (e.g. `ImageDownloader`)
        // spent a network slot only to discard the result silently. Decode them properly here.
        // Detect GIFs by the URL extension OR the raw bytes' signature: a GIF served from a URL
        // without a `.gif` path (e.g. a CDN endpoint) would otherwise be flattened to a single frame.
        if self.isGifURL() || Response.dataHasGIFHeader(imageData) {
            guard let image = UIImage.gif(data: imageData) else {
                throw ResponseError.unexpectedDataType
            }
            return image
        }

        guard let image = UIImage(data: imageData, scale: scale) else {
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

    /// True when the raw bytes begin with a GIF signature (`GIF87a`/`GIF89a`, both sharing the
    /// `GIF8` prefix). Used alongside the URL extension so a GIF whose URL has no `.gif` path is
    /// still decoded as animated rather than flattened to a single frame. No other common image
    /// format starts with these bytes, so PNG/JPEG bodies fall through to the single-frame decode.
    /// Indexed from `startIndex` so it is correct even when `data` is a slice.
    private static func dataHasGIFHeader(_ data: Data) -> Bool {
        guard data.count >= 4 else { return false }
        let start = data.startIndex
        return data[start] == 0x47      // G
            && data[start + 1] == 0x49  // I
            && data[start + 2] == 0x46  // F
            && data[start + 3] == 0x38  // 8
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
