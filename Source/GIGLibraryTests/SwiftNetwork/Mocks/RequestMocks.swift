import Foundation
@testable import GIGLibrary

final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data?))?

    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            preconditionFailure("Request handler is missing.")
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if let data = data {
                client?.urlProtocol(self, didLoad: data)
            }
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

extension MockURLProtocol {
    static func respond(
        statusCode: Int = 200,
        headers: [String: String]? = nil,
        data: Data? = nil,
        _ capture: ((URLRequest) -> Void)? = nil
    ) {
        requestHandler = { request in
            capture?(request)
            let response = HTTPURLResponse.fake(url: request.url!, statusCode: statusCode, headers: headers)
            return (response, data)
        }
    }
}

struct MockReachabilityProvider: ReachabilityInput {
    let reachable: Bool

    func isReachable() -> Bool {
        return reachable
    }

    func isReachableViaWiFi() -> Bool {
        return reachable
    }
}

extension URLSessionConfiguration {
    static func testConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return configuration
    }
}

extension Request {
    static func testRequest(
        method: String,
        baseUrl: String,
        endpoint: String,
        headers: [String: String]? = nil,
        urlParams: [String: Any]? = nil,
        bodyParams: [String: Any]? = nil,
        timeout: TimeInterval? = nil,
        verbose: Bool = false,
        standard: StandardType = .gigigo,
        sessionConfiguration: URLSessionConfiguration,
        reachability: ReachabilityInput
    ) -> Request {
        return Request(
            method: method,
            baseUrl: baseUrl,
            endpoint: endpoint,
            headers: headers,
            urlParams: urlParams,
            bodyParams: bodyParams,
            timeout: timeout,
            verbose: verbose,
            standard: standard,
            sessionConfiguration: sessionConfiguration,
            reachability: reachability
        )
    }
}
