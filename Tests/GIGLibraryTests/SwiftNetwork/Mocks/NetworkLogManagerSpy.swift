import Foundation
import os
@testable import GIGLibrary

/// Captures log calls for assertion. Its mutable storage lives behind an
/// `OSAllocatedUnfairLock` so the spy is `Sendable` and safe to share with the
/// `@concurrent` `Request`/`Response` flow it is injected into.
final class NetworkLogManagerSpy: NetworkLogManaging {
    private struct Storage {
        var messages: [String] = []
        var infos: [RequestLogInfo?] = []
    }

    private let storage = OSAllocatedUnfairLock(initialState: Storage())

    var messages: [String] {
        return storage.withLock { $0.messages }
    }

    var infos: [RequestLogInfo?] {
        return storage.withLock { $0.infos }
    }

    var lastMessage: String? {
        return storage.withLock { $0.messages.last }
    }

    var invocationCount: Int {
        return storage.withLock { $0.messages.count }
    }

    func log(_ message: String, info: RequestLogInfo?) {
        storage.withLock { storage in
            storage.messages.append(message)
            storage.infos.append(info)
        }
    }
}
