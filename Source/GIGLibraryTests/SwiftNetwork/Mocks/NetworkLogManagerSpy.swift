import Foundation
@testable import GIGLibrary

final class NetworkLogManagerSpy: NetworkLogManaging {
    private(set) var messages: [String] = []
    private(set) var infos: [RequestLogInfo?] = []

    var lastMessage: String? {
        return messages.last
    }

    var invocationCount: Int {
        return messages.count
    }

    func log(_ message: String, info: RequestLogInfo?) {
        messages.append(message)
        infos.append(info)
    }
}
