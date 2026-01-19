import Foundation
import Testing
@testable import GIGLibrary

@Suite(.serialized)
struct ResponseTests {
    private func makeJSONResponse(
        body: [String: Any],
        standardType: StandardType = .gigigo
    ) throws -> Response {
        let data = try JSONSerialization.data(withJSONObject: body, options: [])
        let url = try #require(URL(string: "https://example.com"))
        let response = HTTPURLResponse.fake(
            url: url,
            statusCode: 200,
            headers: ["Content-Type": "application/json"]
        )
        return Response(data: data, response: response, error: nil, standardType: standardType)
    }

    @Test("Given JSON status true with data, when Response parses, then it is success and data points to the data node")
    func responseParsesSuccessWithDataNode() throws {
        // Given
        let body: [String: Any] = [
            "status": true,
            "data": [
                "id": 101,
                "name": "Sample"
            ]
        ]

        // When
        let response = try makeJSONResponse(body: body)

        // Then
        #expect(response.status == .success)
        #expect(response.data?.toDictionary()?["id"] as? Int == 101)
        #expect(response.data?.toDictionary()?["name"] as? String == "Sample")
    }

    @Test("Given JSON status OK with data, when Response parses, then it is success")
    func responseParsesSuccessWithOkStatusString() throws {
        // Given
        let body: [String: Any] = [
            "status": "OK",
            "data": [
                "message": "Done"
            ]
        ]

        // When
        let response = try makeJSONResponse(body: body)

        // Then
        #expect(response.status == .success)
        #expect(response.data?.toDictionary()?["message"] as? String == "Done")
    }

    @Test("Given JSON error code and message, when Response parses, then it creates an API error with expected domain")
    func responseParsesApiErrorWithDomain() throws {
        // Given
        let body: [String: Any] = [
            "error": [
                "code": 15000,
                "message": "Invalid token"
            ]
        ]

        // When
        let response = try makeJSONResponse(body: body)

        // Then
        #expect(response.status == .apiError)
        #expect(response.error?.domain == kGIGNetworkErrorDomain)
        #expect(response.error?.code == 15000)
        #expect(response.error?.userInfo[kGIGNetworkErrorMessage] as? String == "Invalid token")
    }

    @Test("Given a JSON response with basic standard type, when Response parses, then data keeps the full JSON and status is success")
    func responseParsesBasicJsonKeepingFullBody() throws {
        // Given
        let body: [String: Any] = [
            "message": "Hello",
            "count": 2
        ]
        // When
        let response = try makeJSONResponse(body: body, standardType: .basic)

        // Then
        #expect(response.status == .success)
        #expect(response.statusCode == 200)
        #expect(response.data?.toDictionary()?["message"] as? String == "Hello")
        #expect(response.data?.toDictionary()?["count"] as? Int == 2)
    }

    @Test("Given NSError codes without URL response, when Response parses, then it maps to expected ResponseStatus")
    func responseMapsNSErrorCodesToResponseStatus() {
        // Given
        let cases: [(Int, ResponseStatus)] = [
            (401, .sessionExpired),
            (-1001, .timeout),
            (-1009, .noInternet),
            (-1202, .untrustedCertificate),
            (42, .unknownError)
        ]

        for (code, expectedStatus) in cases {
            let error = NSError(domain: NSURLErrorDomain, code: code, message: "Test error")

            // When
            let response = Response(data: nil, response: nil, error: error)

            // Then
            #expect(response.status == expectedStatus)
        }
    }

    @Test("Given a 204 JSON response without body, when Response parses, then it is success with no data expected")
    func responseParsesSuccessWithNoContentBody() throws {
        // Given
        let url = try #require(URL(string: "https://example.com"))
        let httpResponse = HTTPURLResponse.fake(
            url: url,
            statusCode: 204,
            headers: ["Content-Type": "application/json"]
        )

        // When
        let response = Response(data: nil, response: httpResponse, error: nil)

        // Then
        #expect(response.status == .success)
        #expect(response.statusCode == 204)
        #expect(response.data == nil)
    }

    @Test("Given a 200 JSON response with empty body, when Response parses, then it is success with no data expected")
    func responseParsesSuccessWithEmptyBody() throws {
        // Given
        let url = try #require(URL(string: "https://example.com"))
        let httpResponse = HTTPURLResponse.fake(
            url: url,
            statusCode: 200,
            headers: ["Content-Type": "application/json"]
        )

        // When
        let response = Response(data: Data(), response: httpResponse, error: nil)

        // Then
        #expect(response.status == .success)
        #expect(response.statusCode == 200)
        #expect(response.data == nil)
    }

    @Test("Given a response with nil data, when accessing json, then it throws bodyNil")
    func responseJsonThrowsBodyNilWhenDataIsNil() {
        // Given
        let response = Response(data: nil, response: nil, error: nil)

        // When/Then
        do {
            _ = try response.json()
            #expect(false)
        } catch {
            #expect(error as? ResponseError == .bodyNil)
        }
    }

}
