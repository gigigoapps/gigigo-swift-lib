import Foundation
import Testing
@testable import GIGLibrary

@Suite
struct RequestTests {
    @Test("Given a POST request with body params, when fetch is called, then URL, headers, and body are built correctly")
    func fetchBuildsRequestWithBodyParams() async throws {
        // Given
        let configuration = URLSessionConfiguration.testConfiguration()
        var capturedRequest: URLRequest?

        MockURLProtocol.respond(capture: { request in
            capturedRequest = request
        })

        let request = Request(
            method: HTTPMethod.post.rawValue,
            baseUrl: "https://example.com/api",
            endpoint: "/v1/test",
            headers: ["Accept": "application/json"],
            urlParams: ["foo": "bar", "page": 2],
            bodyParams: ["name": "Taylor", "count": 3],
            sessionConfiguration: configuration,
            reachability: MockReachabilityProvider(reachable: true)
        )

        // When
        _ = await withCheckedContinuation { continuation in
            request.fetch { _ in
                continuation.resume(returning: ())
            }
        }

        // Then
        let urlRequest = try #require(capturedRequest)
        let requestURL = try #require(urlRequest.url)
        let components = try #require(URLComponents(url: requestURL, resolvingAgainstBaseURL: false))
        let queryItems = components.queryItems ?? []
        let queryDictionary = Dictionary(uniqueKeysWithValues: queryItems.map { ($0.name, $0.value) })
        let bodyObject = try #require(urlRequest.httpBody)
        let bodyJson = try JSONSerialization.jsonObject(with: bodyObject) as? [String: Any]

        #expect(urlRequest.httpMethod == HTTPMethod.post.rawValue)
        #expect(urlRequest.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(urlRequest.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(components.host == "example.com")
        #expect(components.path == "/api/v1/test")
        #expect(queryDictionary["foo"] == "bar")
        #expect(queryDictionary["page"] == "2")
        #expect(bodyJson?["name"] as? String == "Taylor")
        #expect(bodyJson?["count"] as? Int == 3)
    }

    @Test("Given a POST request with a body params array, when fetch is called, then body and headers are built correctly")
    func fetchBuildsRequestWithBodyParamsArray() async throws {
        // Given
        let configuration = URLSessionConfiguration.testConfiguration()
        var capturedRequest: URLRequest?

        MockURLProtocol.respond(capture: { request in
            capturedRequest = request
        })

        let request = Request(
            method: HTTPMethod.post.rawValue,
            baseUrl: "https://example.com",
            endpoint: "/items",
            bodyParams: nil,
            timeout: nil,
            verbose: false,
            standard: .gigigo,
            sessionConfiguration: configuration,
            reachability: MockReachabilityProvider(reachable: true)
        )
        request.bodyParamsArray = [["id": 1], ["id": 2]]

        // When
        _ = await withCheckedContinuation { continuation in
            request.fetch { _ in
                continuation.resume(returning: ())
            }
        }

        // Then
        let urlRequest = try #require(capturedRequest)
        let bodyObject = try #require(urlRequest.httpBody)
        let bodyJson = try JSONSerialization.jsonObject(with: bodyObject) as? [[String: Any]]

        #expect(urlRequest.httpMethod == HTTPMethod.post.rawValue)
        #expect(urlRequest.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(bodyJson?.count == 2)
        #expect(bodyJson?.first?["id"] as? Int == 1)
        #expect(bodyJson?.last?["id"] as? Int == 2)
    }

    @Test("Given reachability is offline, when fetch is called, then it returns a no-internet response")
    func fetchReturnsNoInternetWhenOffline() async {
        // Given
        let configuration = URLSessionConfiguration.testConfiguration()
        var didReceiveRequest = false

        MockURLProtocol.respond(capture: { _ in
            didReceiveRequest = true
        })

        let request = Request(
            method: HTTPMethod.get.rawValue,
            baseUrl: "https://example.com",
            endpoint: "/offline",
            sessionConfiguration: configuration,
            reachability: MockReachabilityProvider(reachable: false)
        )

        // When
        let response = await withCheckedContinuation { continuation in
            request.fetch { response in
                continuation.resume(returning: response)
            }
        }

        // Then
        #expect(response.status == .noInternet)
        #expect(didReceiveRequest == false)
    }
}
