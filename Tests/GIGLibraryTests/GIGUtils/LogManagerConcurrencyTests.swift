//
//  LogManagerConcurrencyTests.swift
//  GIGLibrary
//
//  Regression test for the LogManager data race: the computed setters
//  logLevel / appName / logStyle used to mutate the shared defaultSettings
//  without synchronization, while the log path read the same fields inside the
//  internal queue. Request.logRequest() drives those setters from the
//  @concurrent body of fetch(), so concurrent verbose requests produced a
//  Thread Sanitizer-confirmed data race on LogManagerSettings.logLevel.
//

import Testing
@testable import GIGLibrary

@Suite("LogManager concurrency", .serialized)
struct LogManagerConcurrencyTests {

    @Test("Given concurrent setters, getters and log reads, the shared manager serializes access")
    func concurrentAccessIsThreadSafe() async {
        let manager = LogManager.shared

        // Snapshot the global singleton state and restore it afterwards so the
        // test does not leak settings into the rest of the suite.
        let originalLevel = manager.logLevel
        let originalName = manager.appName
        let originalStyle = manager.logStyle
        defer {
            manager.logLevel = originalLevel
            manager.appName = originalName
            manager.logStyle = originalStyle
        }

        let iterations = 2_000
        let taskCount = 4

        // Each task returns the number of iterations it completed. Summing those
        // counts is a deterministic assertion that does not depend on the shared
        // singleton's final state (which other suites could otherwise perturb),
        // while Thread Sanitizer guards the actual data-race condition.
        let completed = await withTaskGroup(of: Int.self, returning: Int.self) { group in
            // Writer A — mirrors Request.logRequest() turning verbose logging on.
            group.addTask {
                for _ in 0..<iterations {
                    manager.logLevel = .debug
                    manager.appName = "GIGLibrary"
                    manager.logStyle = .funny
                }
                return iterations
            }
            // Writer B — concurrently resets the same fields.
            group.addTask {
                for _ in 0..<iterations {
                    manager.logLevel = .none
                    manager.appName = nil
                    manager.logStyle = .none
                }
                return iterations
            }
            // Reader via the public getters.
            group.addTask {
                for _ in 0..<iterations {
                    _ = manager.logLevel
                    _ = manager.appName
                    _ = manager.logStyle
                    _ = manager.defaultSettings
                }
                return iterations
            }
            // Reader via the log path: gigLogError(nil) reads the default settings'
            // log level inside the internal queue but prints nothing (error is nil),
            // reproducing the reported setter-vs-log-reader race without flooding the console.
            group.addTask {
                for _ in 0..<iterations {
                    gigLogError(nil)
                }
                return iterations
            }

            var total = 0
            for await partial in group {
                total += partial
            }
            return total
        }

        // Reaching here without Thread Sanitizer aborting proves access was
        // serialized behind the manager's queue; the count confirms every
        // concurrent task ran to completion.
        #expect(completed == iterations * taskCount)
    }

    @Test("Given a log handler that mutates the manager, when it runs inside a log call, then it does not deadlock")
    func logHandlerMutatingManagerDoesNotDeadlock() {
        let manager = LogManager.shared

        let originalLevel = manager.logLevel
        let originalName = manager.appName
        let originalStyle = manager.logStyle
        defer {
            manager.logLevel = originalLevel
            manager.appName = originalName
            manager.logStyle = originalStyle
        }

        manager.logLevel = .debug

        // The handler runs inside the log call, while the serial queue is held.
        // Mutating a synchronized accessor from it re-enters the queue; the
        // reentrancy-tolerant `sync` must run that mutation directly instead of
        // dead-locking. Reaching the assertion proves it does.
        var handlerRan = false
        gigLogDebug("reentrancy probe", handler: { _ in
            manager.logLevel = .error
            manager.appName = "Reentrant"
            _ = manager.defaultSettings
            handlerRan = true
        })

        #expect(handlerRan)
    }

    @Test("Given a module identifier that reads a synchronized accessor, when used in a log call, then it does not deadlock")
    func moduleIdentifierReadingAccessorDoesNotDeadlock() {
        let manager = LogManager.shared

        let originalLevel = manager.logLevel
        let originalName = manager.appName
        defer {
            manager.logLevel = originalLevel
            manager.appName = originalName
        }

        manager.logLevel = .debug
        // Clear the default module name so the `moduleName ?? module?.Identifier`
        // fallback actually evaluates `ReentrantIdentifierModule.Identifier`,
        // exercising the reentrant-accessor path this test protects.
        manager.appName = nil

        // logDebug evaluates `module.Identifier` while holding the serial queue,
        // and that identifier reads `logLevel` (a synchronized accessor). The
        // reentrancy-tolerant `sync` must run the read directly rather than
        // dead-lock. The handler confirms the log call ran to completion.
        var handlerRan = false
        gigLogDebug("identifier reentrancy probe", module: ReentrantIdentifierModule.self, handler: { _ in
            handlerRan = true
        })

        #expect(handlerRan)
    }

    @Test("Given the value set into or read from defaultSettings, when a caller mutates it, then the manager keeps its own copy")
    func defaultSettingsExchangesCopies() {
        let manager = LogManager.shared

        let originalLevel = manager.logLevel
        let originalStyle = manager.logStyle
        defer {
            manager.logLevel = originalLevel
            manager.logStyle = originalStyle
        }

        // Set path: mutating the object after assigning it must not leak into the
        // manager (the setter stores a copy).
        let incoming = LogManagerSettings(logLevel: .error, logStyle: .none)
        manager.defaultSettings = incoming
        incoming.logLevel = .debug
        #expect(manager.logLevel == .error)

        // Get path: mutating the returned object must not reach the manager's
        // internal storage (the getter returns a copy), so it cannot race the
        // synchronized log path.
        let outgoing = manager.defaultSettings
        outgoing.logLevel = .debug
        #expect(manager.logLevel == .error)
    }
}

/// A module whose identifier reaches back into a synchronized `LogManager`
/// accessor, used to exercise reentrant access from inside the log queue.
private enum ReentrantIdentifierModule: LoggableModule {
    static var Identifier: String {
        _ = LogManager.shared.logLevel
        return "ReentrantIdentifierModule"
    }
}
