//
//  Log.swift
//  OrchextraApp
//
//  Created by Alejandro Jiménez Agudo on 19/10/15.
//  Copyright © 2015 Gigigo. All rights reserved.
//

import Foundation


public enum LogLevel: Int, Sendable {
    /// No log will be shown.
    case none = 0
    
    /// Only warnings and errors.
    case error = 1
    
    /// Errors and relevant information.
    case info = 2
    
    /// Request and Responses will be displayed.
    case debug = 3
}

public enum LogStyle: Int, Sendable {
    
    /// Profesional style no emojis
    case  none = 0
    
    /// Funny style with emojis
    case funny = 1
}


public func >= (levelA: LogLevel, levelB: LogLevel) -> Bool {
    return levelA.rawValue >= levelB.rawValue
}

public protocol LoggableModule {
    static var Identifier: String { get }
}

public extension LoggableModule {
    static var Identifier: String {
        return String(describing: self)
    }
}

public struct LogManagerSettings: Sendable {
    public var logLevel: LogLevel
    public var logStyle: LogStyle
    public var moduleName: String?

    public init(moduleName: String? = nil, logLevel: LogLevel = .none, logStyle: LogStyle = .none) {
        self.moduleName = moduleName
        self.logLevel = logLevel
        self.logStyle = logStyle
    }
}

/// Thread-safe logging singleton. Its mutable storage (`_defaultSettings`,
/// `settingsById`, `modules`) is only ever read or written inside `queue`. All
/// public accessors and methods funnel through `sync(_:)`, a reentrancy-tolerant
/// wrapper around `queue.sync`: when the caller already runs on `queue` (a log
/// `handler`, or a custom `LoggableModule.Identifier` that reaches back into an
/// accessor) the work runs directly instead of dead-locking on the non-reentrant
/// serial queue. `LogManagerSettings` is a value type, so the accessors exchange
/// copies and never share the internal instance; every read and write the
/// library performs on it is serialized on `queue`. That isolation — which the
/// compiler cannot verify on its own — is what justifies the `@unchecked
/// Sendable` conformance.
public class LogManager: @unchecked Sendable {
    public static let shared = LogManager()

    private var _defaultSettings: LogManagerSettings
    private var settingsById: [String: LogManagerSettings]
    private var modules: [LoggableModule.Type]
    private let queue: DispatchQueue
    private let queueKey = DispatchSpecificKey<UInt8>()

    private init() {
        self._defaultSettings = LogManagerSettings()
        self.settingsById = [String: LogManagerSettings]()
        self.modules = [LoggableModule.Type]()
        self.queue = DispatchQueue(label: "com.gigigo.log", qos: .utility)
        self.queue.setSpecific(key: self.queueKey, value: 1)
    }

    /// Runs `work` on the serial `queue`, executing it directly when the caller
    /// is already on the queue. Without this, a log `handler` or a custom
    /// `LoggableModule.Identifier` that reaches back into a synchronized accessor
    /// would re-enter the non-reentrant queue and deadlock.
    private func sync<T>(_ work: () throws -> T) rethrows -> T {
        if DispatchQueue.getSpecific(key: self.queueKey) != nil {
            return try work()
        }
        return try self.queue.sync(execute: work)
    }

    // MARK: - Default log settings

    /// The default settings. As `LogManagerSettings` is a value type, the getter
    /// hands out a copy and the setter stores one, so the internal instance is
    /// never aliased. `defaultSettings.logLevel = .debug` works as a synchronized
    /// get-modify-set through this property. For a single field under concurrency
    /// prefer the atomic `logLevel`/`appName`/`logStyle` setters: a whole-value
    /// get-modify-set spans two `sync` regions, so racing field writes through
    /// `defaultSettings` could lose one of the updates (never a memory race).
    public var defaultSettings: LogManagerSettings {
        get {
            return self.sync { self._defaultSettings }
        }
        set {
            self.sync { self._defaultSettings = newValue }
        }
    }

    public var logLevel: LogLevel {
        get {
            return self.sync { self._defaultSettings.logLevel }
        }
        set {
            self.sync { self._defaultSettings.logLevel = newValue }
        }
    }

    public var appName: String? {
        get {
            return self.sync { self._defaultSettings.moduleName }
        }
        set {
            self.sync { self._defaultSettings.moduleName = newValue }
        }
    }

    public var logStyle: LogStyle {
        get {
            return self.sync { self._defaultSettings.logStyle }
        }
        set {
            self.sync { self._defaultSettings.logStyle = newValue }
        }
    }

    // MARK: - Per-module settings

    public func setLogValues(logLevel: LogLevel = .none, logStyle: LogStyle = .none, forModule module: LoggableModule.Type) throws {
        try self.sync {
            try self.setLogValuesNonSynchronized(logLevel: logLevel, logStyle: logStyle, forModule: module)
        }
    }
    
    public func setLogLevel(_ logLevel: LogLevel = .none, forModule module: LoggableModule.Type) throws {
        try self.sync {
            guard let settings = self.settingsForModuleNonSynchronized(module) else {
                try self.setLogValuesNonSynchronized(logLevel: logLevel, forModule: module)
                return
            }
            try self.setLogValuesNonSynchronized(logLevel: logLevel, logStyle: settings.logStyle, forModule: module)
        }
    }
    
    public func logLevel(forModule module: LoggableModule.Type) -> LogLevel? {
        return self.sync {
            return self.settingsForModuleNonSynchronized(module)?.logLevel
        }
    }
    
    public func setLogStyle(_ logStyle: LogStyle = .none, forModule module: LoggableModule.Type) throws {
        try self.sync {
            guard let settings = self.settingsForModuleNonSynchronized(module) else {
                try self.setLogValuesNonSynchronized(logStyle: logStyle, forModule: module)
                return
            }
            try self.setLogValuesNonSynchronized(logLevel: settings.logLevel, logStyle: logStyle, forModule: module)
        }
    }
    
    public func logStyle(forModule module: LoggableModule.Type) -> LogStyle? {
        return self.sync {
            return self.settingsForModuleNonSynchronized(module)?.logStyle
        }
    }
    
    public func settingsForModule(_ module: LoggableModule.Type) -> LogManagerSettings? {
        return self.sync {
            return self.settingsForModuleNonSynchronized(module)
        }
    }
    
    public func removeSettingsForModule(_ module: LoggableModule.Type) {
        self.sync {
            self.removeSettingsNonSynchronized(module)
        }
    }
    
    public var currentModules: [LoggableModule.Type] {
        return self.sync {
            return self.modules.map(\.self)
        }
    }
    
    public func addSettings(_ settings: LogManagerSettings, forModule module: LoggableModule.Type) throws {
        try self.sync {
            try self.addSettignsNonSynchonized(settings, forModule: module)
        }
    }
    
    // MARK: - Logging

    // Building the line, printing it, and invoking the optional `handler` all run
    // inside `sync`, so handlers stay serialized with each other and with
    // configuration changes. `sync` is reentrancy-tolerant, so a handler (or a
    // custom `module.Identifier`) may safely read or set the synchronized
    // accessors without dead-locking on the serial queue.

    public func log(_ module: LoggableModule.Type?, message: String, filename: NSString = #file, line: Int = #line, funcname: String = #function, handler: ((String) -> Void)? = nil) {
        self.sync {
            let settings = self.getSettingsForModuleNonSynchronized(module)
            guard settings.logLevel != .none else { return }
            let moduleName = settings.moduleName ?? module?.Identifier ?? "Gigigo Log Manager"
            let debugMessage = "[\(moduleName)]::" + message
            print(debugMessage)
            handler?(debugMessage)
        }
    }

    public func logInfo(_ module: LoggableModule.Type?, message: String, filename: NSString = #file, line: Int = #line, funcname: String = #function, handler: ((String) -> Void)? = nil) {
        self.sync {
            let settings = self.getSettingsForModuleNonSynchronized(module)
            guard settings.logLevel >= .info else { return }
            let moduleName = settings.moduleName ?? module?.Identifier ?? "Gigigo Log Manager"
            let className = filename.lastPathComponent.components(separatedBy: ".").first ?? filename.lastPathComponent
            let emoji = (settings.logStyle == .funny) ? " ⓘ" : ""
            let caller = "[Info\(emoji)] \(className)(\(line)) - \(funcname): "
            let debugMessage = "[\(moduleName)]::\(caller)::" + message
            print(debugMessage)
            handler?(debugMessage)
        }
    }

    public func logDebug(_ module: LoggableModule.Type?, message: String, filename: NSString = #file, line: Int = #line, funcname: String = #function, handler: ((String) -> Void)? = nil) {
        self.sync {
            let settings = self.getSettingsForModuleNonSynchronized(module)
            guard settings.logLevel >= .debug else { return }
            let moduleName = settings.moduleName ?? module?.Identifier ?? "Gigigo Log Manager"
            let className = filename.lastPathComponent.components(separatedBy: ".").first ?? filename.lastPathComponent
            let emoji = (settings.logStyle == .funny) ? " 🐛" : ""
            let caller = "[Debug\(emoji)] \(className)(\(line)) - \(funcname): "
            let debugMessage = "[\(moduleName)]::\(caller)::" + message
            print(debugMessage)
            handler?(debugMessage)
        }
    }

    public func logError(_ module: LoggableModule.Type?, error: Error?, filename: NSString = #file, line: Int = #line, funcname: String = #function, handler: ((String) -> Void)? = nil) {
        self.sync {
            let settings = self.getSettingsForModuleNonSynchronized(module)
            guard settings.logLevel >= .error,
                let err = error
                else { return }
            let moduleName = settings.moduleName ?? module?.Identifier ?? "Gigigo Log Manager"
            let className = filename.lastPathComponent.components(separatedBy: ".").first ?? filename.lastPathComponent
            let emoji = (settings.logStyle == .funny) ? " 🔥" : ""
            let caller = "[Error\(emoji)] \(className)(\(line)) - \(funcname): \(err.localizedDescription)"
            let debugMessage = "[\(moduleName)]::\(caller)"
            print(debugMessage)
            handler?(debugMessage)
        }
    }

    public func logWarn(_ module: LoggableModule.Type?, message: String, filename: NSString = #file, line: Int = #line, funcname: String = #function, handler: ((String) -> Void)? = nil) {
        self.sync {
            let settings = self.getSettingsForModuleNonSynchronized(module)
            guard settings.logLevel >= .error else { return }
            let moduleName = settings.moduleName ?? module?.Identifier ?? "Gigigo Log Manager"
            let className = filename.lastPathComponent.components(separatedBy: ".").first ?? filename.lastPathComponent
            let emoji = (settings.logStyle == .funny) ? " 🔥" : ""
            let caller = "[Warn\(emoji)] \(className)(\(line)) - \(funcname): "
            let debugMessage = "[\(moduleName)]::\(caller)::" + message
            print(debugMessage)
            handler?(debugMessage)
        }
    }
    
    // MARK: - Private helpers

    private func getSettingsForModuleNonSynchronized(_ module: LoggableModule.Type?) -> LogManagerSettings {
        if let module, let moduleSettings = self.settingsForModuleNonSynchronized(module) {
            return moduleSettings
        }
        return self._defaultSettings
    }
    
    private func settingsForModuleNonSynchronized(_ module: LoggableModule.Type) -> LogManagerSettings? {
        return self.settingsById[module.Identifier]
    }
    
    private func removeSettingsNonSynchronized(_ module: LoggableModule.Type) {
        guard let index = self.modules.firstIndex(where: { $0.Identifier == module.Identifier }) else { return }
        self.modules.remove(at: index)
        self.settingsById.removeValue(forKey: module.Identifier)
    }
    
    private func addSettignsNonSynchonized(_ settings: LogManagerSettings, forModule module: LoggableModule.Type) throws {
        guard self.settingsForModuleNonSynchronized(module) == nil else {
			throw NSError.errorWith(code: 200, message: "Repeated module \(String(describing: module)) with identifier  \(module.Identifier)")
        }
        self.modules.append(module)
        self.settingsById.updateValue(settings, forKey: module.Identifier)
    }
    
    private func setLogValuesNonSynchronized(logLevel: LogLevel = .none, logStyle: LogStyle = .none, forModule module: LoggableModule.Type) throws {
        guard var settings = self.settingsForModuleNonSynchronized(module) else {
            let settings = LogManagerSettings(logLevel: logLevel, logStyle: logStyle)
            try self.addSettignsNonSynchonized(settings, forModule: module)
            return
        }
        settings.logLevel = logLevel
        settings.logStyle = logStyle
        self.removeSettingsNonSynchronized(module)
        try self.addSettignsNonSynchonized(settings, forModule: module)
    }
}

// MARK: - Compatibility log functions

public func Log(_ log: String, filename: NSString = #file, line: Int = #line, funcname: String = #function) {
    gigLog(log, module: nil, filename: filename, line: line, funcname: funcname)
}

public func LogInfo(_ log: String, filename: NSString = #file, line: Int = #line, funcname: String = #function) {
    gigLogInfo(log, module: nil, filename: filename, line: line, funcname: funcname)
}

public func LogDebug(_ log: String, filename: NSString = #file, line: Int = #line, funcname: String = #function) {
    gigLogDebug(log, module: nil, filename: filename, line: line, funcname: funcname)
}

public func LogWarn(_ log: String, filename: NSString = #file, line: Int = #line, funcname: String = #function) {
    gigLogWarn(log, module: nil, filename: filename, line: line, funcname: funcname)
}

public func LogError(_ error: NSError?, filename: NSString = #file, line: Int = #line, funcname: String = #function) {
    gigLogError(error, module: nil, filename: filename, line: line, funcname: funcname)
}

// MARK: - Log functions

public func gigLog(_ log: String, module: LoggableModule.Type? = nil, filename: NSString = #file, line: Int = #line, funcname: String = #function, handler: ((String) -> Void)? = nil) {
    LogManager.shared.log(module, message: log, filename: filename, line: line, funcname: funcname, handler: handler)
}

public func gigLogInfo(_ log: String, module: LoggableModule.Type? = nil, filename: NSString = #file, line: Int = #line, funcname: String = #function, handler: ((String) -> Void)? = nil) {
    LogManager.shared.logInfo(module, message: log, filename: filename, line: line, funcname: funcname, handler: handler)
}

public func gigLogDebug(_ log: String, module: LoggableModule.Type? = nil, filename: NSString = #file, line: Int = #line, funcname: String = #function, handler: ((String) -> Void)? = nil) {
    LogManager.shared.logDebug(module, message: log, filename: filename, line: line, funcname: funcname, handler: handler)
}   

public func gigLogWarn(_ message: String, module: LoggableModule.Type? = nil, filename: NSString = #file, line: Int = #line, funcname: String = #function, handler: ((String) -> Void)? = nil) {
    LogManager.shared.logWarn(module, message: message, filename: filename, line: line, funcname: funcname, handler: handler)
}

public func gigLogError(_ error: Error?, module: LoggableModule.Type? = nil, filename: NSString = #file, line: Int = #line, funcname: String = #function, handler: ((String) -> Void)? = nil) {
    LogManager.shared.logError(module, error: error, filename: filename, line: line, funcname: funcname, handler: handler)
}
