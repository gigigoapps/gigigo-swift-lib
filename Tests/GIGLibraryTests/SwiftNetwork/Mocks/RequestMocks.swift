import Foundation
@testable import GIGLibrary

final class MockURLProtocol: URLProtocol {
    private struct RouteHandler {
        let method: HTTPMethod?
        let path: String?
        let matcher: ((URLRequest) -> Bool)?
        let handler: (URLRequest) throws -> (HTTPURLResponse, Data?)
    }

    private static let handlerQueue = DispatchQueue(label: "MockURLProtocol.handlers")
    private nonisolated(unsafe) static var handlers: [RouteHandler] = []

    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        guard let handler = MockURLProtocol.handler(for: request) else {
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

    private static func handler(for request: URLRequest) -> ((URLRequest) throws -> (HTTPURLResponse, Data?))? {
        let methodString = request.httpMethod ?? HTTPMethod.get.rawValue
        let method = HTTPMethod(rawValue: methodString) ?? .get

        return handlerQueue.sync {
            handlers.last(where: { route in
                if let matcher = route.matcher {
                    return matcher(request)
                }

                guard let url = request.url else {
                    return false
                }

                let methodMatches = route.method.map { $0 == method } ?? true
                return methodMatches && route.path == url.path
            })?.handler
        }
    }

    private static func registerHandler(
        method: HTTPMethod?,
        path: String,
        handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data?)
    ) {
        handlerQueue.sync {
            handlers.append(RouteHandler(method: method, path: path, matcher: nil, handler: handler))
        }
    }

    private static func registerHandler(
        matcher: @escaping (URLRequest) -> Bool,
        handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data?)
    ) {
        handlerQueue.sync {
            handlers.append(RouteHandler(method: nil, path: nil, matcher: matcher, handler: handler))
        }
    }
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
        path: String,
        statusCode: Int = 200,
        headers: [String: String]? = nil,
        data: Data? = nil,
        method: HTTPMethod? = nil,
        _ capture: ((URLRequest) -> Void)? = nil
    ) {
        registerHandler(method: method, path: path) { request in
            _ = prepareCapturedRequest(request, capture)
            let response = HTTPURLResponse.fake(url: request.url!, statusCode: statusCode, headers: headers)
            return (response, data)
        }
    }

    static func respond(
        path: String,
        fixture name: String,
        statusCode: Int = 200,
        headers: [String: String]? = ["Content-Type": "application/json"],
        method: HTTPMethod? = nil,
        _ capture: ((URLRequest) -> Void)? = nil
    ) {
        registerHandler(method: method, path: path) { request in
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
        for route in routes {
            registerHandler(method: route.method, path: route.path) { request in
                _ = prepareCapturedRequest(request, capture)

                guard let url = request.url else {
                    throw FixtureRouteError.invalidRequest
                }

                let data = try FixtureLoader.data(named: route.fixture)
                let response = HTTPURLResponse.fake(url: url, statusCode: route.statusCode, headers: route.headers)
                return (response, data)
            }
        }
    }

    static func respond(
        matcher: @escaping (URLRequest) -> Bool,
        fixtureForRequest: @escaping (URLRequest) throws -> String,
        statusCode: Int = 200,
        headers: [String: String]? = ["Content-Type": "application/json"],
        _ capture: ((URLRequest) -> Void)? = nil
    ) {
        registerHandler(matcher: matcher) { request in
            _ = prepareCapturedRequest(request, capture)

            guard let url = request.url else {
                throw FixtureRouteError.invalidRequest
            }

            let fixtureName = try fixtureForRequest(request)
            let data = try FixtureLoader.data(named: fixtureName)
            let response = HTTPURLResponse.fake(url: url, statusCode: statusCode, headers: headers)
            return (response, data)
        }
    }

    static func respond(
        method: HTTPMethod? = nil,
        path: String,
        queryKey: String,
        fixtureByQueryValue: [String: String],
        defaultFixture: String,
        statusCode: Int = 200,
        headers: [String: String]? = ["Content-Type": "application/json"],
        _ capture: ((URLRequest) -> Void)? = nil
    ) {
        respond(
            matcher: { request in
                guard let url = request.url else {
                    return false
                }
                let methodString = request.httpMethod ?? HTTPMethod.get.rawValue
                let requestMethod = HTTPMethod(rawValue: methodString) ?? .get
                let methodMatches = method.map { $0 == requestMethod } ?? true
                return methodMatches && url.path == path
            },
            fixtureForRequest: { request in
                guard let url = request.url,
                      let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                    return defaultFixture
                }
                let queryValue = components.queryItems?.first(where: { $0.name == queryKey })?.value
                return queryValue.flatMap { fixtureByQueryValue[$0] } ?? defaultFixture
            },
            statusCode: statusCode,
            headers: headers,
            capture
        )
    }
}

enum FixtureRouteError: Error {
    case invalidRequest
    case unmatchedRoute(method: String, path: String)
}

struct FixtureRoute {
    let method: HTTPMethod?
    let path: String
    let fixture: String
    let statusCode: Int
    let headers: [String: String]?

    init(
        method: HTTPMethod? = nil,
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
        method: HTTPMethod = .get,
        baseUrl: String,
        endpoint: String,
        headers: [String: String]? = nil,
        urlParams: [String: Any]? = nil,
        bodyParams: [String: Any]? = nil,
        bodyParamsArray: [[String: Any]]? = nil,
        timeout: TimeInterval? = nil,
        verbose: Bool = false,
        standard: StandardType = .gigigo,
        sessionConfiguration: URLSessionConfiguration? = nil,
        reachable: Bool = true,
        networkLogManager: NetworkLogManaging = DefaultNetworkLogManager()
    ) -> Request {
        let configuration = sessionConfiguration ?? .testConfiguration()
        return Request(
            method: method,
            baseUrl: baseUrl,
            endpoint: endpoint,
            headers: headers,
            urlParams: urlParams,
            bodyParams: bodyParams,
            bodyParamsArray: bodyParamsArray,
            timeout: timeout,
            verbose: verbose,
            standard: standard,
            networkLogManager: networkLogManager,
            sessionConfiguration: configuration,
            reachability: MockReachabilityProvider(reachable: reachable)
        )
    }
}

func makeImageResponse(body: Data?, url: URL) -> Response {
    let response = HTTPURLResponse.fake(url: url, statusCode: 200, headers: nil)
    return Response(data: body, response: response, error: nil)
}
