import Foundation
import Testing
@testable import GIGLibrary

@MainActor
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

    private func assertThrowsResponseError(_ expected: ResponseError, _ block: () throws -> Void) {
        var didThrow = false
        var didThrowUnexpected = false
        do {
            try block()
        } catch let error as ResponseError {
            didThrow = true
            #expect(error == expected)
        } catch {
            didThrow = true
            didThrowUnexpected = true
        }

        #expect(didThrow)
        #expect(!didThrowUnexpected)
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

    @Test("Given nil response and nil error, when Response initializes, then status is unknownError and statusCode is -1")
    func responseInitializesWithNilResponseAndError() {
        // When
        let response = Response(data: nil, response: nil, error: nil)

        // Then
        #expect(response.status == .unknownError)
        #expect(response.statusCode == -1)
    }

    @Test("Given nil response and nil error, when Response initializes, then it clears response-related properties")
    func responseInitializesClearingResponseProperties() {
        // When
        let response = Response(data: nil, response: nil, error: nil)

        // Then
        #expect(response.body == nil)
        #expect(response.data == nil)
        #expect(response.error == nil)
        #expect(response.url == nil)
        #expect(response.headers == nil)
    }

    @Test("Given a response with nil data, when accessing json, then it throws bodyNil")
    func responseJsonThrowsBodyNilWhenDataIsNil() {
        // Given
        let response = Response(data: nil, response: nil, error: nil)

        // When/Then
        assertThrowsResponseError(.bodyNil) {
            _ = try response.json()
        }
    }

    @Test("Given image body is nil, when image is requested, then it throws bodyNil")
    func imageThrowsWhenBodyIsNil() throws {
        // Given
        let url = try #require(URL(string: "https://example.com/image.png"))
        let response = makeImageResponse(body: nil, url: url)

        // When/Then
        assertThrowsResponseError(.bodyNil) {
            _ = try response.image(scale: 1)
        }
    }

    @Test("Given a GIF URL with undecodable data, when image is requested, then it throws unexpectedDataType")
    func imageThrowsWhenGifDataIsInvalid() throws {
        // Given
        let url = try #require(URL(string: "https://example.com/animated.gif"))
        let response = makeImageResponse(body: Data([0x00, 0x01, 0x02]), url: url)

        // When/Then
        assertThrowsResponseError(.unexpectedDataType) {
            _ = try response.image(scale: 1)
        }
    }

    @Test("Given a GIF URL with valid GIF data, when image is requested, then it returns a decoded image")
    func imageDecodesValidGifData() throws {
        // Given a minimal 1x1 transparent GIF89a
        let gifData = try #require(Data(base64Encoded: "R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7"))
        let url = try #require(URL(string: "https://example.com/animated.gif"))
        let response = makeImageResponse(body: gifData, url: url)

        // When
        let image = try response.image(scale: 1)

        // Then it went through the animated GIF decoder (UIImage.gif), not the single-frame fallback
        #expect(image.images != nil)
        #expect(image.size.width > 0)
        #expect(image.size.height > 0)
    }

    @Test("Given HTTP status codes around the 2xx boundary, when Response parses, then only 200..<300 are success")
    func responseTreatsOnly2xxAsSuccess() throws {
        // Given
        let url = try #require(URL(string: "https://example.com"))
        let cases: [(code: Int, isSuccess: Bool)] = [
            (199, false),
            (200, true),
            (204, true),
            (299, true),
            (300, false),
            (301, false)
        ]

        for testCase in cases {
            let httpResponse = HTTPURLResponse.fake(url: url, statusCode: testCase.code, headers: nil)

            // When
            let response = Response(data: nil, response: httpResponse, error: nil)

            // Then
            #expect((response.status == .success) == testCase.isSuccess)
            #expect(response.statusCode == testCase.code)
        }
    }

    @Test("Given a non-2xx response carrying a Gigigo success envelope, when Response parses, then the HTTP status wins and it is not success")
    func responseNon2xxWithSuccessEnvelopeIsNotSuccess() throws {
        // Given a 400 whose body still claims success the Gigigo way
        let url = try #require(URL(string: "https://example.com"))
        let body: [String: Any] = ["status": true, "data": ["id": 1]]
        let data = try JSONSerialization.data(withJSONObject: body, options: [])
        let httpResponse = HTTPURLResponse.fake(
            url: url,
            statusCode: 400,
            headers: ["Content-Type": "application/json"]
        )

        // When
        let response = Response(data: data, response: httpResponse, error: nil, standardType: .gigigo)

        // Then the non-2xx HTTP status is authoritative
        #expect(response.status != .success)
        #expect(response.statusCode == 400)
        #expect(response.error?.domain == kGIGNetworkErrorDomain)
    }

    @Test("Given a non-2xx response with a Gigigo error envelope, when Response parses, then the specific API error is preserved")
    func responseNon2xxWithErrorEnvelopeKeepsApiError() throws {
        // Given a 400 carrying a Gigigo error envelope: the specific error must not be clobbered
        let url = try #require(URL(string: "https://example.com"))
        let body: [String: Any] = ["status": false, "error": ["code": 15001, "message": "Bad"]]
        let data = try JSONSerialization.data(withJSONObject: body, options: [])
        let httpResponse = HTTPURLResponse.fake(
            url: url,
            statusCode: 400,
            headers: ["Content-Type": "application/json"]
        )

        // When
        let response = Response(data: data, response: httpResponse, error: nil, standardType: .gigigo)

        // Then
        #expect(response.status == .apiError)
        #expect(response.statusCode == 15001)
        #expect(response.error?.code == 15001)
    }

    @Test("Given a non-2xx Gigigo error envelope whose code does not map to a status, when Response parses, then the synthesized error uses the real HTTP code")
    func responseNon2xxUnmappedErrorEnvelopeUsesHttpCode() throws {
        // Given HTTP 400 with an application error code (1001) that maps to no specific status
        let url = try #require(URL(string: "https://example.com"))
        let body: [String: Any] = ["status": false, "error": ["code": 1001, "message": "Bad request"]]
        let data = try JSONSerialization.data(withJSONObject: body, options: [])
        let httpResponse = HTTPURLResponse.fake(
            url: url,
            statusCode: 400,
            headers: ["Content-Type": "application/json"]
        )

        // When
        let response = Response(data: data, response: httpResponse, error: nil, standardType: .gigigo)

        // Then the transport status (400) is preserved, not the envelope code (1001)
        #expect(response.status != .success)
        #expect(response.statusCode == 400)
        #expect(response.error?.code == 400)
    }

    @Test("Given a non-2xx response carrying a Gigigo envelope with status OK string, when Response parses, then the HTTP status wins and it is not success")
    func responseNon2xxWithOkStringEnvelopeIsNotSuccess() throws {
        // Given a 400 whose envelope claims success via the string form ("OK", not boolean true)
        let url = try #require(URL(string: "https://example.com"))
        let body: [String: Any] = ["status": "OK", "data": ["id": 1]]
        let data = try JSONSerialization.data(withJSONObject: body, options: [])
        let httpResponse = HTTPURLResponse.fake(
            url: url,
            statusCode: 400,
            headers: ["Content-Type": "application/json"]
        )

        // When
        let response = Response(data: data, response: httpResponse, error: nil, standardType: .gigigo)

        // Then
        #expect(response.status != .success)
        #expect(response.statusCode == 400)
    }

    @Test("Given a non-2xx basic-standard JSON response, when Response parses, then it is not success even though the body parsed")
    func responseNon2xxBasicJsonIsNotSuccess() throws {
        // Given a 400 with a plain JSON body parsed under the basic standard type
        let url = try #require(URL(string: "https://example.com"))
        let body: [String: Any] = ["message": "nope"]
        let data = try JSONSerialization.data(withJSONObject: body, options: [])
        let httpResponse = HTTPURLResponse.fake(
            url: url,
            statusCode: 400,
            headers: ["Content-Type": "application/json"]
        )

        // When
        let response = Response(data: data, response: httpResponse, error: nil, standardType: .basic)

        // Then the HTTP error wins; the parsed body remains available behind the error status
        #expect(response.status != .success)
        #expect(response.statusCode == 400)
        #expect(response.data?.toDictionary()?["message"] as? String == "nope")
    }

    @Test("Given invalid image data, when image is requested, then it throws unexpectedDataType")
    func imageThrowsWhenDataIsInvalid() throws {
        // Given
        let url = try #require(URL(string: "https://example.com/image.png"))
        let response = makeImageResponse(body: Data([0x00, 0x01, 0x02]), url: url)

        // When/Then
        assertThrowsResponseError(.unexpectedDataType) {
            _ = try response.image(scale: 1)
        }
    }

    @Test("Given a response, when logging, then it includes URL and status code")
    func responseLogIncludesUrlAndCode() throws {
        // Given
        let spy = NetworkLogManagerSpy()
        let url = try #require(URL(string: "https://example.com/resource"))
        let httpResponse = HTTPURLResponse.fake(url: url, statusCode: 201, headers: nil)
        let response = Response(data: nil, response: httpResponse, error: nil, networkLogManager: spy)

        // When
        response.logResponse()

        // Then
        let message = try #require(spy.lastMessage)
        #expect(message.contains("******** RESPONSE ********"))
        #expect(message.contains(" - URL:\thttps://example.com/resource"))
        #expect(message.contains(" - CODE:\t201"))
    }

    @Test("Given a JSON response body, when logging, then it includes the JSON section")
    func responseLogIncludesJsonBody() throws {
        // Given
        let spy = NetworkLogManagerSpy()
        let url = try #require(URL(string: "https://example.com/json"))
        let body: [String: Any] = ["name": "Taylor", "count": 2]
        let data = try JSONSerialization.data(withJSONObject: body, options: [])
        let httpResponse = HTTPURLResponse.fake(url: url, statusCode: 200, headers: ["Content-Type": "application/json"])
        let response = Response(data: data, response: httpResponse, error: nil, networkLogManager: spy)

        // When
        response.logResponse()

        // Then
        let message = try #require(spy.lastMessage)
        #expect(message.contains(" - JSON:\n"))
        #expect(message.contains("\"name\" : \"Taylor\""))
        #expect(message.contains("\"count\" : 2"))
    }

    @Test("Given a non-JSON string body, when logging, then it includes the data section")
    func responseLogIncludesStringBodyAsData() throws {
        // Given
        let spy = NetworkLogManagerSpy()
        let url = try #require(URL(string: "https://example.com/text"))
        let data = try #require("plain text".data(using: .utf8))
        let httpResponse = HTTPURLResponse.fake(url: url, statusCode: 200, headers: nil)
        let response = Response(data: data, response: httpResponse, error: nil, networkLogManager: spy)

        // When
        response.logResponse()

        // Then
        let message = try #require(spy.lastMessage)
        #expect(message.contains(" - DATA:\nplain text"))
    }

    @Test("Given a response without headers or body, when logging, then it omits those sections")
    func responseLogOmitsHeadersAndBodyWhenEmpty() throws {
        // Given
        let spy = NetworkLogManagerSpy()
        let url = try #require(URL(string: "https://example.com/empty"))
        let httpResponse = HTTPURLResponse.fake(url: url, statusCode: 204, headers: nil)
        let response = Response(data: nil, response: httpResponse, error: nil, networkLogManager: spy)

        // When
        response.logResponse()

        // Then
        let message = try #require(spy.lastMessage)
        #expect(message.contains(" - HEADERS:") == false)
        #expect(message.contains(" - JSON:") == false)
        #expect(message.contains(" - DATA:") == false)
    }
}
