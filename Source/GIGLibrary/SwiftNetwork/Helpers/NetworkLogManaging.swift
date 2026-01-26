//
//  NetworkLogManaging.swift
//  GIGLibrary
//
//  Created by Alejandro Jiménez Agudo on 2026-01-20
//  Copyright © 2026 Gigigo SL. All rights reserved.
//

import Foundation

protocol NetworkLogManaging {
    func log(_ message: String, info: RequestLogInfo?)
}

struct DefaultNetworkLogManager: NetworkLogManaging {
    func log(_ message: String, info: RequestLogInfo?) {
        guard let info else {
            print(message)
            return
        }

        switch info.logLevel {
        case .debug:
            gigLogDebug(message, module: info.module, filename: info.filename, line: info.line, funcname: info.funcname, handler: info.handler)
        case .error:
            gigLogError(NSError(code: 0, message: message), module: info.module, filename: info.filename, line: info.line, funcname: info.funcname, handler: info.handler)
        case .info:
            gigLogInfo(message, module: info.module, filename: info.filename, line: info.line, funcname: info.funcname, handler: info.handler)
        default:
            break
        }
    }
}
