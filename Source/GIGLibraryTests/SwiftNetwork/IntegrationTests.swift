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
}
