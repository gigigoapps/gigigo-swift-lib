//
//  RequestLogInfo.swift
//  GIGLibrary
//
//  Created by Pablo Viciano Negre on 07/09/2018.
//  Copyright © 2018 Gigigo SL. All rights reserved.
//

import Foundation

public protocol RequestLogInfo: Sendable {
    var filename: String { get }
    var line: Int { get }
    var funcname: String { get }
    var logLevel: LogLevel { get }
    var module: LoggableModule.Type { get }
    var handler: (@Sendable (String) -> Void)? { get }
}

public struct DefaultRequestLogInfo: RequestLogInfo {
    // `module` is a metatype (immutable type metadata), which is safe to share
    // across concurrency domains. `nonisolated(unsafe)` lets this struct satisfy
    // `Sendable` without forcing every `LoggableModule` conformer to be `Sendable`
    // (those are static-metadata type tags, often non-Sendable classes).
    public nonisolated(unsafe) let module: LoggableModule.Type
    public let filename: String
    public let line: Int
    public let funcname: String
    public let logLevel: LogLevel
    public let handler: (@Sendable (String) -> Void)?

    public init(module: LoggableModule.Type, logLevel: LogLevel = .none, filename: String = #file, line: Int = #line, funcname: String = #function, handler: (@Sendable (String) -> Void)? = nil) {
        self.module = module
        self.logLevel = logLevel
        self.filename = filename
        self.line = line
        self.funcname = funcname
        self.handler = handler
    }
}
