//
//  ResponseLogFormatter.swift
//  GIGLibrary
//
//  Created by Alejandro Jiménez Agudo on 2026-01-20
//  Copyright © 2026 Gigigo SL. All rights reserved.
//

import Foundation

enum ResponseLogFormatter {
    public static func buildResponseLog(url: URL?, statusCode: Int, headers: [AnyHashable: Any]?, body: Data?) -> String {
        var log = "\n******** RESPONSE ********\n"
        log += " - URL:\t" + logURL(url) + "\n"
        log += " - CODE:\t" + "\(statusCode)\n"
        log += logHeaders(headers)
        log += logData(body)
        log += "*************************\n\n"

        return log
    }

    // Private Helpers
    
    private static func logURL(_ url: URL?) -> String {
        guard let url = url?.absoluteString else {
            return "NO URL"
        }

        return url
    }

    private static func logHeaders(_ headers: [AnyHashable: Any]?) -> String {
        guard let headers = headers, !headers.isEmpty else { return "" }

        var log = " - HEADERS: {"

        for key in headers.keys {
            if let value = headers[key] {
                log += "\n\t\t\(key): \(value)"
            }
        }

        return log + "\n}\n"
    }

    private static func logData(_ body: Data?) -> String {
        guard let body = body, !body.isEmpty else {
            return ""
        }

        if let json = try? JSON.dataToJson(body) {
            return " - JSON:\n\(json)\n"
        } else if let string = String(data: body, encoding: .utf8) {
            return " - DATA:\n\(string)\n"
        } else {
            return ""
        }
    }
}
