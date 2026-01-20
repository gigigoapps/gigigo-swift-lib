//
//  RequestLogFormatter.swift
//  GIGLibrary
//
//  Created by Alejandro Jiménez Agudo on 2026-01-20
//  Copyright © 2026 Gigigo SL. All rights reserved.
//

import Foundation

public enum RequestLogFormatter {
    public static func buildRequestLog(request: URLRequest?) -> String {
        let url = request?.url?.absoluteString ?? "no url set"
        let method = request?.httpMethod ?? "no method set"

        var log = "\n******** REQUEST ********\n"
        log += " - URL:\t\t\(url)\n"
        log += " - METHOD:\t\(method)\n"
        log += logBody(request: request)
        log += logHeaders(request: request)
        log += "*************************\n\n"

        return log
    }

    private static func logBody(request: URLRequest?) -> String {
        guard
            let body = request?.httpBody,
            let json = try? JSON.dataToJson(body)
        else { return "" }

        return " - BODY:\n\(json)\n"
    }

    private static func logHeaders(request: URLRequest?) -> String {
        guard let headers = request?.allHTTPHeaderFields, !headers.isEmpty else { return "" }

        var logString = " - HEADERS: {"

        for key in headers.keys {
            if let value = headers[key] {
                logString += "\n\t\t\(key): \(value)"
            }
        }

        return logString + "\n}\n"
    }
}
