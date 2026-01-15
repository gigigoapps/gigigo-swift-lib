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
    private static func requestBody(from request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }

        guard let stream = request.httpBodyStream else {
            return nil
        }

        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let bytesRead = stream.read(&buffer, maxLength: buffer.count)
            if bytesRead > 0 {
                data.append(buffer, count: bytesRead)
            } else {
                break
            }
        }
        return data
    }

    private static func prepareCapturedRequest(
        _ request: URLRequest,
        _ capture: ((URLRequest) -> Void)?
    ) -> URLRequest {
        var capturedRequest = request
        if capturedRequest.httpBody == nil, let body = requestBody(from: request) {
            capturedRequest.httpBody = body
        }
        capture?(capturedRequest)
        return capturedRequest
    }

    static func respond(
        statusCode: Int = 200,
        headers: [String: String]? = nil,
        data: Data? = nil,
        _ capture: ((URLRequest) -> Void)? = nil
    ) {
        requestHandler = { request in
            _ = prepareCapturedRequest(request, capture)
            let response = HTTPURLResponse.fake(url: request.url!, statusCode: statusCode, headers: headers)
            return (response, data)
        }
    }

    static func respond(
        fixture name: String,
        statusCode: Int = 200,
        headers: [String: String]? = ["Content-Type": "application/json"],
        _ capture: ((URLRequest) -> Void)? = nil
    ) {
        requestHandler = { request in
            _ = prepareCapturedRequest(request, capture)
            let data = try FixtureLoader.data(named: name)
            let response = HTTPURLResponse.fake(url: request.url!, statusCode: statusCode, headers: headers)
            return (response, data)
        }
    }

    static func respond(
        routes: [FixtureRoute],
        _ capture: ((URLRequest) -> Void)? = nil
    ) {
        requestHandler = { request in
            _ = prepareCapturedRequest(request, capture)

            guard let url = request.url else {
                throw FixtureRouteError.invalidRequest
            }

            let path = url.path
            let method = request.httpMethod ?? ""

            guard let route = routes.first(where: { route in
                let methodMatches = route.method.map { $0.caseInsensitiveCompare(method) == .orderedSame } ?? true
                return methodMatches && route.path == path
            }) else {
                throw FixtureRouteError.unmatchedRoute(method: method, path: path)
            }

            let data = try FixtureLoader.data(named: route.fixture)
            let response = HTTPURLResponse.fake(url: url, statusCode: route.statusCode, headers: route.headers)
            return (response, data)
        }
    }
}

enum FixtureRouteError: Error {
    case invalidRequest
    case unmatchedRoute(method: String, path: String)
}

struct FixtureRoute {
    let method: String?
    let path: String
    let fixture: String
    let statusCode: Int
    let headers: [String: String]?

    init(
        method: String? = nil,
        path: String,
        fixture: String,
        statusCode: Int = 200,
        headers: [String: String]? = ["Content-Type": "application/json"]
    ) {
        self.method = method
        self.path = path
        self.fixture = fixture
        self.statusCode = statusCode
        self.headers = headers
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
