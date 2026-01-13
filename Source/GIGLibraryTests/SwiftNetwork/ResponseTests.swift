import Foundation
import Testing
@testable import GIGLibrary

@Suite(.serialized)
struct ResponseTests {
    private func makeJSONResponse(body: [String: Any]) throws -> Response {
        let data = try JSONSerialization.data(withJSONObject: body, options: [])
        let url = try #require(URL(string: "https://example.com"))
        let response = HTTPURLResponse.fake(
            url: url,
            statusCode: 200,
            headers: ["Content-Type": "application/json"]
        )
        return Response(data: data, response: response, error: nil, standardType: .gigigo)
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
}
