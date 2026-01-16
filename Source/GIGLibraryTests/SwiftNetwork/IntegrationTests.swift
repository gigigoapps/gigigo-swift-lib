import Foundation
import Testing
@testable import GIGLibrary

@Suite(.serialized)
struct SwiftNetworkIntegrationTests {
    @Test("Given a request and the success fixture, when fetch is called, then response matches fixture success")
    func fetchReturnsSuccessFixtureResponse() async throws {
        // Given
        MockURLProtocol.respond(path: "/success", fixture: "success", statusCode: 200)
        let request = Request.testRequest(
            method: HTTPMethod.get.rawValue,
            baseUrl: "https://example.com",
            endpoint: "/success"
        )

        // When
        let response = await withCheckedContinuation { continuation in
            request.fetch { response in
                continuation.resume(returning: response)
            }
        }

        // Then
        #expect(response.status == .success)
        #expect(response.statusCode == 200)
        #expect(response.error == nil)
        #expect(response.data?.toDictionary()?["id"] as? Int == 101)
        #expect(response.data?.toDictionary()?["name"] as? String == "Sample")
    }

    @Test("Given a request and the OK status fixture, when fetch is called, then response matches fixture success")
    func fetchReturnsOkStatusFixtureResponse() async throws {
        // Given
        MockURLProtocol.respond(path: "/ok-status", fixture: "ok_status", statusCode: 200)
        let request = Request.testRequest(
            method: HTTPMethod.get.rawValue,
            baseUrl: "https://example.com",
            endpoint: "/ok-status"
        )

        // When
        let response = await withCheckedContinuation { continuation in
            request.fetch { response in
                continuation.resume(returning: response)
            }
        }

        // Then
        #expect(response.status == .success)
        #expect(response.statusCode == 200)
        #expect(response.error == nil)
        #expect(response.data?.toDictionary()?["message"] as? String == "Done")
    }

    @Test("Given a request and the KO status fixture, when fetch is called, then response matches fixture error")
    func fetchReturnsKoStatusFixtureResponse() async throws {
        // Given
        MockURLProtocol.respond(path: "/ko-status", fixture: "ko_status", statusCode: 400)
        let request = Request.testRequest(
            method: HTTPMethod.get.rawValue,
            baseUrl: "https://example.com",
            endpoint: "/ko-status"
        )

        // When
        let response = await withCheckedContinuation { continuation in
            request.fetch { response in
                continuation.resume(returning: response)
            }
        }

        // Then
        #expect(response.status == .apiError)
        #expect(response.statusCode == 15001)
        #expect(response.data == nil)
        #expect(response.error?.domain == kGIGNetworkErrorDomain)
        #expect(response.error?.code == 15001)
        #expect(response.error?.userInfo[kGIGNetworkErrorMessage] as? String == "Invalid request")
    }

    @Test("Given a request and the api error fixture, when fetch is called, then response matches fixture error")
    func fetchReturnsApiErrorFixtureResponse() async throws {
        // Given
        MockURLProtocol.respond(path: "/error", fixture: "api_error", statusCode: 400)
        let request = Request.testRequest(
            method: HTTPMethod.get.rawValue,
            baseUrl: "https://example.com",
            endpoint: "/error"
        )

        // When
        let response = await withCheckedContinuation { continuation in
            request.fetch { response in
                continuation.resume(returning: response)
            }
        }

        // Then
        #expect(response.status == .apiError)
        #expect(response.statusCode == 15000)
        #expect(response.data == nil)
        #expect(response.error?.domain == kGIGNetworkErrorDomain)
        #expect(response.error?.code == 15000)
        #expect(response.error?.userInfo[kGIGNetworkErrorMessage] as? String == "Invalid token")
    }

    @Test("Given a request and the basic fixture, when fetch is called, then response is success with full data")
    func fetchReturnsBasicFixtureResponse() async throws {
        // Given
        MockURLProtocol.respond(path: "/basic", fixture: "basic_success", statusCode: 200)
        let request = Request.testRequest(
            method: HTTPMethod.get.rawValue,
            baseUrl: "https://example.com",
            endpoint: "/basic",
            standard: .basic
        )

        // When
        let response = await withCheckedContinuation { continuation in
            request.fetch { response in
                continuation.resume(returning: response)
            }
        }

        // Then
        #expect(response.status == .success)
        #expect(response.statusCode == 200)
        #expect(response.data?.toDictionary()?["message"] as? String == "Hello")
        #expect(response.data?.toDictionary()?["count"] as? Int == 2)
    }

    @Test("Given a request with 204 response and empty body, when fetch is called, then response is success with no data expected")
    func fetchReturnsNoContentResponse() async throws {
        // Given
        MockURLProtocol.respond(
            path: "/no-content",
            statusCode: 204,
            headers: ["Content-Type": "application/json"],
            data: nil
        )
        let request = Request.testRequest(
            method: HTTPMethod.get.rawValue,
            baseUrl: "https://example.com",
            endpoint: "/no-content"
        )

        // When
        let response = await withCheckedContinuation { continuation in
            request.fetch { response in
                continuation.resume(returning: response)
            }
        }

        // Then
        #expect(response.status == .success)
        #expect(response.statusCode == 204)
        #expect(response.data == nil)
    }

    @Test("Given a request and an invalid JSON fixture, when fetch is called, then response is success with no data expected")
    func fetchReturnsInvalidJsonFixtureResponse() async throws {
        // Given
        MockURLProtocol.respond(path: "/invalid-json", fixture: "invalid_json", statusCode: 200)
        let request = Request.testRequest(
            method: HTTPMethod.get.rawValue,
            baseUrl: "https://example.com",
            endpoint: "/invalid-json"
        )

        // When
        let response = await withCheckedContinuation { continuation in
            request.fetch { response in
                continuation.resume(returning: response)
            }
        }

        // Then
        #expect(response.status == .success)
        #expect(response.statusCode == 200)
        #expect(response.data == nil)
    }
}
