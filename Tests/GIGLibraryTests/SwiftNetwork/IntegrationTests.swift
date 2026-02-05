import Foundation
import Testing
@testable import GIGLibrary

private final class SendableRequestBox: @unchecked Sendable {
    let request: Request

    init(_ request: Request) {
        self.request = request
    }
}

@Suite(.serialized)
struct SwiftNetworkIntegrationTests {
    private func assertThrowsNSError(
        _ block: () async throws -> Void,
        assertion: (NSError) -> Void
    ) async {
        var didThrow = false
        var didThrowUnexpected = false

        do {
            try await block()
        } catch let error as NSError {
            didThrow = true
            assertion(error)
        } catch {
            didThrow = true
            didThrowUnexpected = true
        }

        #expect(didThrow)
        #expect(!didThrowUnexpected)
    }

    @Test("Given a request and the success fixture, when fetch is called, then response matches fixture success")
    func fetchReturnsSuccessFixtureResponse() async throws {
        // Given
        MockURLProtocol.respond(path: "/success", fixture: "success", statusCode: 200)
        let request = Request.testRequest(
            baseUrl: "https://example.com",
            endpoint: "/success"
        )

        // When
        let response = await request.fetch()

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
            baseUrl: "https://example.com",
            endpoint: "/ok-status"
        )

        // When
        let response = await request.fetch()

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
            baseUrl: "https://example.com",
            endpoint: "/ko-status"
        )

        // When
        let response = await request.fetch()

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
            baseUrl: "https://example.com",
            endpoint: "/error"
        )

        // When
        let response = await request.fetch()

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
            baseUrl: "https://example.com",
            endpoint: "/basic",
            standard: .basic
        )

        // When
        let response = await request.fetch()

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
            baseUrl: "https://example.com",
            endpoint: "/no-content"
        )

        // When
        let response = await request.fetch()

        // Then
        #expect(response.status == .success)
        #expect(response.statusCode == 204)
        #expect(response.data == nil)
    }

    @Test("Given a 204 response with empty body, when fetchVoid is called, then it does not throw")
    func fetchVoidDoesNotThrowForNoContentSuccess() async throws {
        // Given
        let spy = NetworkLogManagerSpy()
        MockURLProtocol.respond(
            path: "/void-no-content",
            statusCode: 204,
            headers: ["Content-Type": "application/json"],
            data: nil
        )
        let request = Request.testRequest(
            baseUrl: "https://example.com",
            endpoint: "/void-no-content",
            verbose: true,
            networkLogManager: spy
        )

        // When
        try await request.fetchVoid()

        // Then
        #expect(spy.invocationCount == 2)
        let responseLog = try #require(spy.lastMessage)
        #expect(responseLog.contains("******** RESPONSE ********"))
        #expect(responseLog.contains(" - CODE:\t204"))
    }

    @Test("Given an api error fixture, when fetchVoid is called, then it throws the response error")
    func fetchVoidThrowsApiResponseError() async {
        // Given
        MockURLProtocol.respond(path: "/void-api-error", fixture: "api_error", statusCode: 400)
        let request = Request.testRequest(
            baseUrl: "https://example.com",
            endpoint: "/void-api-error"
        )

        // When/Then
        await assertThrowsNSError({
            try await request.fetchVoid()
        }, assertion: { error in
            #expect(error.domain == kGIGNetworkErrorDomain)
            #expect(error.code == 15000)
        })
    }

    @Test("Given reachability is offline, when fetchVoid is called, then it throws no internet error")
    func fetchVoidThrowsNoInternetErrorWhenOffline() async {
        // Given
        let request = Request.testRequest(
            baseUrl: "https://example.com",
            endpoint: "/void-offline",
            reachable: false
        )

        // When/Then
        await assertThrowsNSError({
            try await request.fetchVoid()
        }, assertion: { error in
            #expect(error.domain == NSURLErrorDomain)
            #expect(error.code == NSURLErrorNotConnectedToInternet)
        })
    }

    @Test("Given a 401 response without response error, when fetchVoid is called, then it throws fallback error with status code")
    func fetchVoidThrowsFallbackErrorWhenResponseHasNoError() async {
        // Given
        MockURLProtocol.respond(
            path: "/void-unauthorized-no-error",
            statusCode: 401,
            headers: ["Content-Type": "text/plain"],
            data: nil
        )
        let request = Request.testRequest(
            baseUrl: "https://example.com",
            endpoint: "/void-unauthorized-no-error"
        )

        // When/Then
        await assertThrowsNSError({
            try await request.fetchVoid()
        }, assertion: { error in
            #expect(error.domain == kGIGNetworkErrorDomain)
            #expect(error.code == 401)
        })
    }

    @Test("Given a request and an invalid JSON fixture, when fetch is called, then response is success with no data expected")
    func fetchReturnsInvalidJsonFixtureResponse() async throws {
        // Given
        MockURLProtocol.respond(path: "/invalid-json", fixture: "invalid_json", statusCode: 200)
        let request = Request.testRequest(
            baseUrl: "https://example.com",
            endpoint: "/invalid-json"
        )

        // When
        let response = await request.fetch()

        // Then
        #expect(response.status == .success)
        #expect(response.statusCode == 200)
        #expect(response.data == nil)
    }

    @Test("Given a base URL including full path and query params, when fetch is called, then it merges existing and new params without appending the endpoint")
    func fetchBuildsRequestWithBaseUrlIncludingQueryParams() async throws {
        // Given
        MockURLProtocol.respond(path: "/api/resource", fixture: "success", statusCode: 200)

        let request = Request.testRequest(
            baseUrl: "https://example.com/api/resource?existing=one&token=abc",
            endpoint: "",
            urlParams: ["foo": "bar", "page": 2]
        )

        // When
        let response = await request.fetch()

        // Then
        #expect(response.status == .success)
        #expect(response.statusCode == 200)
        #expect(response.error == nil)
        #expect(response.data?.toDictionary()?["id"] as? Int == 101)
        #expect(response.data?.toDictionary()?["name"] as? String == "Sample")
    }

    @Test("Given dynamic fixtures by path and query, when GET requests use base URL, endpoint, and params, then it returns the expected fixture")
    func fetchUsesFixtureBasedOnPathAndQuery() async throws {
        // Given
        MockURLProtocol.respond(
            path: "/api/v1/items",
            queryKey: "type",
            fixtureByQueryValue: ["ok": "ok_status"],
            defaultFixture: "success"
        )

        let okRequest = Request.testRequest(
            baseUrl: "https://example.com/api",
            endpoint: "/v1/items",
            urlParams: ["type": "ok"]
        )
        let successRequest = Request.testRequest(
            baseUrl: "https://example.com/api",
            endpoint: "/v1/items",
            urlParams: ["type": "full"]
        )

        // When
        let okResponse = await okRequest.fetch()
        let successResponse = await successRequest.fetch()

        // Then
        #expect(okResponse.status == .success)
        #expect(okResponse.data?.toDictionary()?["message"] as? String == "Done")
        #expect(successResponse.status == .success)
        #expect(successResponse.data?.toDictionary()?["id"] as? Int == 101)
    }

    @Test("Given dynamic fixtures, when POST uses base URL, endpoint, and params, then it returns the matching fixture")
    func fetchUsesFixtureBasedOnPostUrlParams() async throws {
        // Given
        MockURLProtocol.respond(
            method: .post,
            path: "/api/v1/items",
            queryKey: "status",
            fixtureByQueryValue: ["basic": "basic_success"],
            defaultFixture: "success"
        )

        let request = Request.testRequest(
            method: .post,
            baseUrl: "https://example.com/api",
            endpoint: "/v1/items",
            urlParams: ["status": "basic"],
            bodyParams: ["name": "Taylor"],
            standard: .basic
        )

        // When
        let response = await request.fetch()

        // Then
        #expect(response.status == .success)
        #expect(response.data?.toDictionary()?["message"] as? String == "Hello")
        #expect(response.data?.toDictionary()?["count"] as? Int == 2)
    }

    @Test("Given dynamic fixtures, when upload uses base URL, endpoint, and params, then it returns the matching fixture")
    func uploadUsesFixtureBasedOnPathAndQuery() async throws {
        // Given
        MockURLProtocol.respond(
            method: .post,
            path: "/api/v1/upload",
            queryKey: "upload",
            fixtureByQueryValue: ["ok": "success"],
            defaultFixture: "api_error"
        )

        let request = Request.testRequest(
            method: .post,
            baseUrl: "https://example.com/api",
            endpoint: "/v1/upload",
            urlParams: ["upload": "ok"]
        )

        let fileData = FileUploadData(
            data: Data("upload".utf8),
            mimeType: "text/plain",
            filename: "upload.txt",
            name: "file"
        )

        // When
        let response = await request.upload(files: [fileData], params: ["note": "ok"])

        // Then
        #expect(response.status == .success)
        #expect(response.data?.toDictionary()?["id"] as? Int == 101)
        #expect(response.data?.toDictionary()?["name"] as? String == "Sample")
    }

    @Test("Given a verbose GET request with headers and params, when fetch is called, then request and response logs include URL, method, and headers")
    func fetchLogsRequestAndResponseWithHeadersAndParams() async throws {
        // Given
        let spy = NetworkLogManagerSpy()
        MockURLProtocol.respond(
            path: "/log",
            statusCode: 200,
            headers: ["X-Response": "yes"],
            data: Data(),
            method: .get
        )
        let request = Request.testRequest(
            baseUrl: "https://example.com",
            endpoint: "/log",
            headers: ["Authorization": "Bearer 123"],
            urlParams: ["search": "swift", "page": 1],
            verbose: true,
            networkLogManager: spy
        )

        // When
        _ = await request.fetch()

        // Then
        let requestLog = try #require(spy.messages.first)
        let responseLog = try #require(spy.messages.last)

        #expect(requestLog.contains("******** REQUEST ********"))
        #expect(requestLog.contains(" - URL:\t\thttps://example.com/log?"))
        #expect(requestLog.contains("search=swift"))
        #expect(requestLog.contains("page=1"))
        #expect(requestLog.contains(" - METHOD:\tGET"))
        #expect(requestLog.contains(" - HEADERS:"))
        #expect(requestLog.contains("Authorization: Bearer 123"))

        #expect(responseLog.contains("******** RESPONSE ********"))
        #expect(responseLog.contains(" - URL:\thttps://example.com/log?"))
        #expect(responseLog.contains("search=swift"))
        #expect(responseLog.contains("page=1"))
        #expect(responseLog.contains(" - CODE:\t200"))
        #expect(responseLog.contains(" - HEADERS:"))
        #expect(responseLog.contains("X-Response: yes"))
    }

    @Test("Given a verbose POST request with JSON body, when fetch is called, then request log includes body JSON")
    func fetchLogsRequestBodyJson() async throws {
        // Given
        let spy = NetworkLogManagerSpy()
        MockURLProtocol.respond(path: "/body", statusCode: 200, data: Data())
        let request = Request.testRequest(
            method: .post,
            baseUrl: "https://example.com",
            endpoint: "/body",
            bodyParams: ["name": "Taylor", "count": 3],
            verbose: true,
            networkLogManager: spy
        )

        // When
        _ = await request.fetch()

        // Then
        let requestLog = try #require(spy.messages.first)
        #expect(requestLog.contains(" - BODY:\n"))
        #expect(requestLog.contains("\"name\" : \"Taylor\""))
        #expect(requestLog.contains("\"count\" : 3"))
    }

    @Test("Given a JSON response, when fetch is called, then response log includes JSON section")
    func fetchLogsResponseJson() async throws {
        // Given
        let spy = NetworkLogManagerSpy()
        MockURLProtocol.respond(path: "/json", fixture: "success", statusCode: 200)
        let request = Request.testRequest(
            baseUrl: "https://example.com",
            endpoint: "/json",
            verbose: true,
            networkLogManager: spy
        )

        // When
        _ = await request.fetch()

        // Then
        let responseLog = try #require(spy.messages.last)
        #expect(responseLog.contains(" - JSON:\n"))
        #expect(responseLog.contains("\"status\" : true"))
        #expect(responseLog.contains("\"name\" : \"Sample\""))
    }

    @Test("Given a plain text response, when fetch is called, then response log includes data section without JSON")
    func fetchLogsResponsePlainText() async throws {
        // Given
        let spy = NetworkLogManagerSpy()
        let data = try #require("plain text".data(using: .utf8))
        MockURLProtocol.respond(
            path: "/text",
            statusCode: 200,
            headers: ["Content-Type": "text/plain"],
            data: data
        )
        let request = Request.testRequest(
            baseUrl: "https://example.com",
            endpoint: "/text",
            verbose: true,
            networkLogManager: spy
        )

        // When
        _ = await request.fetch()

        // Then
        let responseLog = try #require(spy.messages.last)
        #expect(responseLog.contains(" - DATA:\nplain text"))
        #expect(responseLog.contains(" - JSON:") == false)
    }

    @Test("Given a 204 response without headers or body, when fetch is called, then response log omits headers and body sections")
    func fetchLogsResponseWithoutHeadersOrBody() async throws {
        // Given
        let spy = NetworkLogManagerSpy()
        MockURLProtocol.respond(path: "/no-body", statusCode: 204, headers: nil, data: nil)
        let request = Request.testRequest(
            baseUrl: "https://example.com",
            endpoint: "/no-body",
            verbose: true,
            networkLogManager: spy
        )

        // When
        _ = await request.fetch()

        // Then
        let responseLog = try #require(spy.messages.last)
        #expect(responseLog.contains(" - HEADERS:") == false)
        #expect(responseLog.contains(" - JSON:") == false)
        #expect(responseLog.contains(" - DATA:") == false)
    }

    @Test("Given offline reachability, when fetch is called, then it returns no internet and no logs are emitted")
    func fetchOfflineDoesNotLogAndReturnsNoInternet() async throws {
        // Given
        let spy = NetworkLogManagerSpy()
        let request = Request.testRequest(
            baseUrl: "https://example.com",
            endpoint: "/offline",
            verbose: true,
            reachable: false,
            networkLogManager: spy
        )

        // When
        let response = await request.fetch()

        // Then
        #expect(response.status == .noInternet)
        #expect(spy.messages.isEmpty)
    }

    @Test("Given a server error response, when fetch is called, then it returns the HTTP status code and unknown error status")
    func fetchHandlesHttpErrorStatus() async {
        // Given
        let errorBody = Data("Internal Server Error".utf8)
        MockURLProtocol.respond(
            path: "/server-error",
            statusCode: 500,
            headers: ["Content-Type": "text/plain"],
            data: errorBody
        )
        let request = Request.testRequest(
            baseUrl: "https://example.com",
            endpoint: "/server-error"
        )

        // When
        let response = await request.fetch()

        // Then
        #expect(response.status == .unknownError)
        #expect(response.statusCode == 500)
    }

    @Test("Given a cancelled task, when fetch starts, then it returns a cancelled response without calling the network")
    func fetchHandlesCancellation() async {
        // Given
        var didReceiveRequest = false
        MockURLProtocol.respond(path: "/cancel") { _ in
            didReceiveRequest = true
        }
        let request = Request.testRequest(
            baseUrl: "https://example.com",
            endpoint: "/cancel"
        )

        // When
        let task = Task {
            await Task.yield()
            return await request.fetch()
        }
        task.cancel()
        let response = await task.value

        // Then
        #expect(response.error?.code == URLError.cancelled.rawValue)
        #expect(response.statusCode == URLError.cancelled.rawValue)
        #expect(didReceiveRequest == false)
    }

    @Test("Given an in-flight fetch, when cancel is called, then it returns a cancelled response")
    func fetchReturnsCancelledWhenRequestIsCancelled() async {
        // Given
        MockURLProtocol.respond(
            path: "/cancel-in-flight",
            statusCode: 200,
            data: Data("ok".utf8),
            delay: 0.3
        )
        let request = Request.testRequest(
            baseUrl: "https://example.com",
            endpoint: "/cancel-in-flight"
        )
        let requestBox = SendableRequestBox(request)

        // When
        let task = Task {
            await requestBox.request.fetch()
        }
        try? await Task.sleep(nanoseconds: 50_000_000)
        requestBox.request.cancel()
        let response = await task.value

        // Then
        #expect(response.error?.code == URLError.cancelled.rawValue)
        #expect(response.statusCode == URLError.cancelled.rawValue)
    }

    @Test("Given consecutive fetch calls, when second starts, then first is cancelled")
    func fetchCancelsPreviousRequestWhenCalledAgain() async {
        // Given
        MockURLProtocol.respond(
            path: "/cancel-previous",
            statusCode: 200,
            data: Data("ok".utf8),
            delay: 0.3
        )
        let request = Request.testRequest(
            baseUrl: "https://example.com",
            endpoint: "/cancel-previous"
        )
        let requestBox = SendableRequestBox(request)

        // When
        let firstTask = Task {
            await requestBox.request.fetch()
        }
        try? await Task.sleep(nanoseconds: 50_000_000)
        let secondTask = Task {
            await requestBox.request.fetch()
        }
        let firstResponse = await firstTask.value
        let secondResponse = await secondTask.value

        // Then
        #expect(firstResponse.error?.code == URLError.cancelled.rawValue)
        #expect(firstResponse.statusCode == URLError.cancelled.rawValue)
        #expect(secondResponse.status == .success)
    }

    @Test("Given a completed fetch, when cancel is called, then it does not affect the response")
    func fetchCancelAfterCompletionDoesNotChangeResponse() async {
        // Given
        MockURLProtocol.respond(path: "/cancel-after", data: Data("ok".utf8))
        let request = Request.testRequest(
            baseUrl: "https://example.com",
            endpoint: "/cancel-after"
        )

        // When
        let response = await request.fetch()
        request.cancel()

        // Then
        #expect(response.status == .success)
        #expect(response.error == nil)
    }

    @Test("Given an in-flight download, when cancel is called, then it returns a cancelled response")
    func fetchDownloadReturnsCancelledWhenRequestIsCancelled() async {
        // Given
        let destinationURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        MockURLProtocol.respond(
            path: "/download-cancel",
            statusCode: 200,
            headers: ["Content-Type": "application/octet-stream"],
            data: Data("file".utf8),
            delay: 0.3
        )
        let request = Request.testRequest(
            baseUrl: "https://example.com",
            endpoint: "/download-cancel"
        )
        let requestBox = SendableRequestBox(request)

        // When
        let task = Task {
            await requestBox.request.fetch(downloadTo: destinationURL)
        }
        try? await Task.sleep(nanoseconds: 50_000_000)
        requestBox.request.cancel()
        let response = await task.value

        // Then
        #expect(response.error?.code == URLError.cancelled.rawValue)
        #expect(response.statusCode == URLError.cancelled.rawValue)
    }

    @Test("Given an in-flight upload, when cancel is called, then it returns a cancelled response")
    func uploadReturnsCancelledWhenRequestIsCancelled() async {
        // Given
        MockURLProtocol.respond(
            path: "/upload-cancel",
            statusCode: 200,
            data: Data("ok".utf8),
            delay: 0.3
        )
        let request = Request.testRequest(
            method: .post,
            baseUrl: "https://example.com",
            endpoint: "/upload-cancel"
        )
        let requestBox = SendableRequestBox(request)
        let fileData = FileUploadData(
            data: Data("file".utf8),
            mimeType: "text/plain",
            filename: "file.txt",
            name: "payload"
        )

        // When
        let task = Task {
            await requestBox.request.upload(files: [fileData], params: ["title": "Sample"])
        }
        try? await Task.sleep(nanoseconds: 50_000_000)
        requestBox.request.cancel()
        let response = await task.value

        // Then
        #expect(response.error?.code == URLError.cancelled.rawValue)
        #expect(response.statusCode == URLError.cancelled.rawValue)
    }

    @Test("Given reachability is offline, when upload is called, then it returns no-internet without sending the request")
    func uploadReturnsNoInternetWhenOffline() async {
        // Given
        var didReceiveRequest = false
        MockURLProtocol.respond(path: "/upload-offline") { _ in
            didReceiveRequest = true
        }
        let request = Request.testRequest(
            method: .post,
            baseUrl: "https://example.com",
            endpoint: "/upload-offline",
            reachable: false
        )
        let fileData = FileUploadData(
            data: Data("file".utf8),
            mimeType: "text/plain",
            filename: "file.txt",
            name: "payload"
        )

        // When
        let response = await request.upload(files: [fileData], params: ["title": "Sample"])

        // Then
        #expect(response.status == .noInternet)
        #expect(didReceiveRequest == false)
    }

    @Test("Given a download request, when fetch download completes, then it writes the file to disk")
    func fetchDownloadWritesFile() async throws {
        // Given
        let destinationURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let payload = Data("download".utf8)
        MockURLProtocol.respond(
            path: "/download",
            statusCode: 200,
            headers: ["Content-Type": "application/octet-stream"],
            data: payload
        )
        let request = Request.testRequest(
            baseUrl: "https://example.com",
            endpoint: "/download"
        )

        // When
        let response = await request.fetch(downloadTo: destinationURL)

        // Then
        defer { try? FileManager.default.removeItem(at: destinationURL) }
        let storedData = try Data(contentsOf: destinationURL)
        #expect(response.status == .success)
        #expect(response.statusCode == 200)
        #expect(storedData == payload)
    }
}
