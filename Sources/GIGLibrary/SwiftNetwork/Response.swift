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


public enum ResponseStatus {
	case success
	case errorParsingJson
	case sessionExpired
	case timeout
	case noInternet
	case apiError
	case unknownError
	case untrustedCertificate
}

public class Response: Selfie {
	
	public var status: ResponseStatus
	public var statusCode: Int
	public var url: URL?
	public var headers: [AnyHashable: Any]?
	public var body: Data?
	public var data: JSON?
	public var error: NSError?

	private var networkLogManager: NetworkLogManaging
    private var standardType: StandardType = .gigigo
	
	
	// MARK: - Initializers
	
	init() {
		self.status = .unknownError
		self.statusCode = 0
        self.networkLogManager = DefaultNetworkLogManager()
	}
	
    convenience init(data: Data?, response: URLResponse?, error: Error?, standardType: StandardType = .gigigo, networkLogManager: NetworkLogManaging = DefaultNetworkLogManager()) {
		self.init()
		
        self.networkLogManager = networkLogManager
        self.standardType = standardType
		self.error = error as NSError?
		if let response = response as? HTTPURLResponse {
			self.url = response.url
			self.headers = response.allHeaderFields
			self.body = data
			self.statusCode = response.statusCode
			
			if (200...300).contains(self.statusCode) {
				self.status = .success
			}
			
			if let contentType = self.headers?["Content-Type"] as? String,
				contentType.contains("json") {
                self.parseJSON()
			}
		} else {
			self.statusCode = self.error?.code ?? -1
			self.status = self.parseError(error: self.error)
		}
	}
	
    // MARK: - Instance methods
    
    class func noInternet() -> Response {
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet, message: "No Internet")
        let response = Response(data: nil, response: nil, error: error)
        return response
    }
	
	// MARK: - Private Helpers
    
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
		} else if let statusString = json["status"]?.toString() {
			return statusString == "OK"
		} else {
			return false
		}
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
		case 401:
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
    
    func logResponse() {
        self.logResponse(nil)
    }
	
    func logResponse(_ logInfo: RequestLogInfo?) {
        let log = ResponseLogFormatter.buildResponseLog(url: self.url, statusCode: self.statusCode, headers: self.headers, body: self.body)
        self.networkLogManager.log(log, info: logInfo)
	}
}


public enum ResponseError: Error {
	case bodyNil
	case unexpectedDataType
}

public extension Response {
	
    func json() throws -> JSON {
		guard let json = self.data else {
			throw ResponseError.bodyNil
		}
		
		return json
	}
	
    func image() throws -> UIImage {
		guard let imageData = self.body else {
			throw ResponseError.bodyNil
		}
        guard !isGifData(), let image = UIImage(data: imageData, scale: UIScreen.main.scale) else {
            throw ResponseError.unexpectedDataType
        }
        return image
	}
    
    private func isGifData() -> Bool {
        guard let url = url else {
            return false
        }
        return url.pathExtension == "gif"
    }
}
