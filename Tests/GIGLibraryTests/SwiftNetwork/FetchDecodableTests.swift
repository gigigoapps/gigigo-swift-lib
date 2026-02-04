import Foundation
import Testing
@testable import GIGLibrary

@Suite(.serialized)
struct FetchDecodableTests {
    private struct Profile: Decodable, Equatable {
        let id: Int
        let name: String
    }

    private struct BasicPayload: Decodable, Equatable {
        let message: String
        let count: Int
    }

    private struct RequiresAge: Decodable {
        let age: Int
    }

    private struct EmptyPayload: Decodable, Equatable {}

    private func assertThrowsFetchDecodableError<T>(
        _ block: () async throws -> T,
        assertion: (FetchDecodableError) -> Void
    ) async {
        var didThrow = false
        var didThrowUnexpected = false

        do {
            _ = try await block()
        } catch let error as FetchDecodableError {
            didThrow = true
            assertion(error)
        } catch {
            didThrow = true
            didThrowUnexpected = true
        }

        #expect(didThrow)
        #expect(!didThrowUnexpected)
    }

    @Test("Given a gigigo success fixture, when fetchDecodable is called with inferred type, then it decodes data payload")
    func fetchDecodableDecodesGigigoDataPayload() async throws {
        // Given
        MockURLProtocol.respond(path: "/decodable-success", fixture: "success", statusCode: 200)
        let request = Request.testRequest(
            baseUrl: "https://example.com",
            endpoint: "/decodable-success"
        )

        // When
        let profile: Profile = try await request.fetchDecodable()

        // Then
        #expect(profile == Profile(id: 101, name: "Sample"))
    }

    @Test("Given a basic success fixture, when fetchDecodable is called, then it decodes from root body")
    func fetchDecodableDecodesBasicPayload() async throws {
        // Given
        MockURLProtocol.respond(path: "/decodable-basic", fixture: "basic_success", statusCode: 200)
        let request = Request.testRequest(
            baseUrl: "https://example.com",
            endpoint: "/decodable-basic",
            standard: .basic
        )

        // When
        let payload: BasicPayload = try await request.fetchDecodable()

        // Then
        #expect(payload == BasicPayload(message: "Hello", count: 2))
    }

    @Test("Given a non-success response, when fetchDecodable is called, then it throws requestFailed with status information")
    func fetchDecodableThrowsRequestFailedForApiError() async {
        // Given
        MockURLProtocol.respond(path: "/decodable-api-error", fixture: "api_error", statusCode: 400)
        let request = Request.testRequest(
            baseUrl: "https://example.com",
            endpoint: "/decodable-api-error"
        )

        // When/Then
        await assertThrowsFetchDecodableError({
            let _: Profile = try await request.fetchDecodable()
        }, assertion: { error in
            guard case let .requestFailed(status, statusCode, underlying) = error else {
                return #expect(Bool(false))
            }

            #expect(status == .apiError)
            #expect(statusCode == 15000)
            #expect(underlying?.code == 15000)
        })
    }

    @Test("Given a successful response with incompatible model, when fetchDecodable is called, then it throws decodingFailed")
    func fetchDecodableThrowsDecodingFailedWhenModelIsIncompatible() async {
        // Given
        MockURLProtocol.respond(path: "/decodable-incompatible", fixture: "success", statusCode: 200)
        let request = Request.testRequest(
            baseUrl: "https://example.com",
            endpoint: "/decodable-incompatible"
        )

        // When/Then
        await assertThrowsFetchDecodableError({
            let _: RequiresAge = try await request.fetchDecodable()
        }, assertion: { error in
            guard case .decodingFailed = error else {
                return #expect(Bool(false))
            }
        })
    }

    @Test("Given a 204 JSON response with empty body and an empty model, when fetchDecodable is called, then it uses fallback {} and decodes")
    func fetchDecodableDecodesEmptyModelWithFallbackObject() async throws {
        // Given
        MockURLProtocol.respond(
            path: "/decodable-empty-compatible",
            statusCode: 204,
            headers: ["Content-Type": "application/json"],
            data: nil
        )
        let request = Request.testRequest(
            baseUrl: "https://example.com",
            endpoint: "/decodable-empty-compatible"
        )

        // When
        let payload: EmptyPayload = try await request.fetchDecodable()

        // Then
        #expect(payload == EmptyPayload())
    }

    @Test("Given a 204 JSON response with empty body and an incompatible model, when fetchDecodable is called, then it throws emptyResponseBody")
    func fetchDecodableThrowsEmptyResponseBodyWhenFallbackCannotDecodeModel() async {
        // Given
        MockURLProtocol.respond(
            path: "/decodable-empty-incompatible",
            statusCode: 204,
            headers: ["Content-Type": "application/json"],
            data: nil
        )
        let request = Request.testRequest(
            baseUrl: "https://example.com",
            endpoint: "/decodable-empty-incompatible"
        )

        // When/Then
        await assertThrowsFetchDecodableError({
            let _: Profile = try await request.fetchDecodable()
        }, assertion: { error in
            guard case let .emptyResponseBody(statusCode) = error else {
                return #expect(Bool(false))
            }

            #expect(statusCode == 204)
        })
    }
}
