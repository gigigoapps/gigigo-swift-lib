import Foundation
import Testing
@testable import GIGLibrary

@Suite(.serialized)
struct RequestTests {
    @Test("Given a POST request with body params, when fetch is called, then URL, headers, and body are built correctly")
    func fetchBuildsRequestWithBodyParams() async throws {
        // Given
        var capturedRequest: URLRequest?

        MockURLProtocol.respond(path: "/api/v1/test") { request in
            capturedRequest = request
        }

        let request = Request.testRequest(
            method: HTTPMethod.post.rawValue,
            baseUrl: "https://example.com/api",
            endpoint: "/v1/test",
            headers: ["Accept": "application/json"],
            urlParams: ["foo": "bar", "page": 2],
            bodyParams: ["name": "Taylor", "count": 3]
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
        var capturedRequest: URLRequest?

        MockURLProtocol.respond(path: "/items") { request in
            capturedRequest = request
        }

        let request = Request.testRequest(
            method: HTTPMethod.post.rawValue,
            baseUrl: "https://example.com",
            endpoint: "/items",
            bodyParams: nil,
            timeout: nil,
            verbose: false,
            standard: .gigigo
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

    @Test("Given a POST request with a custom Content-Type header, when fetch is called, then it keeps the custom value and does not inject application/json")
    func fetchKeepsCustomContentTypeHeader() async throws {
        // Given
        var capturedRequest: URLRequest?

        MockURLProtocol.respond(path: "/custom-content-type") { request in
            capturedRequest = request
        }

        let request = Request.testRequest(
            method: HTTPMethod.post.rawValue,
            baseUrl: "https://example.com",
            endpoint: "/custom-content-type",
            headers: ["Content-Type": "application/custom"],
            urlParams: nil,
            bodyParams: ["status": "ok"]
        )

        // When
        _ = await withCheckedContinuation { continuation in
            request.fetch { _ in
                continuation.resume(returning: ())
            }
        }

        // Then
        let urlRequest = try #require(capturedRequest)

        #expect(urlRequest.value(forHTTPHeaderField: "Content-Type") == "application/custom")
        #expect(urlRequest.value(forHTTPHeaderField: "Content-Type") != "application/json")
    }

    @Test("Given a GET request with empty body params and headers, when fetch is called, then it does not add a body or Content-Type header")
    func fetchDoesNotSetBodyOrContentTypeForEmptyGet() async throws {
        // Given
        var capturedRequest: URLRequest?

        MockURLProtocol.respond(path: "/v1/empty") { request in
            capturedRequest = request
        }

        let request = Request.testRequest(
            method: HTTPMethod.get.rawValue,
            baseUrl: "https://example.com",
            endpoint: "/v1/empty",
            headers: [:],
            urlParams: nil,
            bodyParams: [:]
        )

        // When
        _ = await withCheckedContinuation { continuation in
            request.fetch { _ in
                continuation.resume(returning: ())
            }
        }

        // Then
        let urlRequest = try #require(capturedRequest)

        #expect(urlRequest.httpBody == nil)
        #expect(urlRequest.value(forHTTPHeaderField: "Content-Type") == nil)
    }

    @Test("Given reachability is offline, when fetch is called, then it returns a no-internet response")
    func fetchReturnsNoInternetWhenOffline() async {
        // Given
        var didReceiveRequest = false

        MockURLProtocol.respond(path: "/offline") { _ in
            didReceiveRequest = true
        }

        let request = Request.testRequest(
            method: HTTPMethod.get.rawValue,
            baseUrl: "https://example.com",
            endpoint: "/offline",
            reachable: false
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

    @Test("Given a download request while offline, when fetch is called, then it does not write a file and returns no-internet")
    func fetchDownloadReturnsNoInternetWhenOffline() async {
        // Given
        let destinationURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        var didReceiveRequest = false

        MockURLProtocol.respond(path: "/offline-download") { _ in
            didReceiveRequest = true
        }

        let request = Request.testRequest(
            method: HTTPMethod.get.rawValue,
            baseUrl: "https://example.com",
            endpoint: "/offline-download",
            reachable: false
        )

        // When
        let response = await withCheckedContinuation { continuation in
            request.fetch(withDownloadUrlFile: destinationURL) { response in
                continuation.resume(returning: response)
            }
        }

        // Then
        #expect(response.status == .noInternet)
        #expect(FileManager.default.fileExists(atPath: destinationURL.path) == false)
        #expect(didReceiveRequest == false)
    }

    @Test("Given a complete URL with query params, when fetch is called, then it merges existing and new params without appending the endpoint")
    func fetchBuildsRequestWithCompleteURLAndUrlParams() async throws {
        // Given
        var capturedRequest: URLRequest?

        MockURLProtocol.respond(path: "/api/resource") { request in
            capturedRequest = request
        }

        let completeURL = try #require(URL(string: "https://example.com/api/resource?existing=one&token=abc"))
        let request = Request(
            method: .get,
            completeURL: completeURL,
            headers: nil,
            urlParams: ["foo": "bar", "page": 2],
            bodyParams: nil,
            sessionConfiguration: .testConfiguration(),
            reachability: MockReachabilityProvider(reachable: true)
        )
        request.endpoint = "/should-not-append"

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
        let queryValue = { (name: String) in
            queryItems.first(where: { $0.name == name })?.value
        }

        #expect(components.path == "/api/resource")
        #expect(queryValue("existing") == "one")
        #expect(queryValue("token") == "abc")
        #expect(queryValue("foo") == "bar")
        #expect(queryValue("page") == "2")
    }

    @Test("Given an upload request, when upload is called, then it builds a multipart body with boundaries and fields")
    func uploadBuildsMultipartRequestWithFilesAndParams() async throws {
        // Given
        var capturedRequest: URLRequest?

        MockURLProtocol.respond(path: "/upload") { request in
            capturedRequest = request
        }

        let request = Request.testRequest(
            method: HTTPMethod.post.rawValue,
            baseUrl: "https://example.com",
            endpoint: "/upload",
            headers: nil,
            urlParams: nil,
            bodyParams: nil
        )

        let fileData = FileUploadData(
            data: Data("hello".utf8),
            mimeType: "text/plain",
            filename: "hello.txt",
            name: "file"
        )
        let params: [String: Any] = [
            "user": "tester",
            "count": 1
        ]

        // When
        _ = await withCheckedContinuation { continuation in
            request.upload(files: [fileData], params: params) { _ in
                continuation.resume(returning: ())
            }
        }

        // Then
        let urlRequest = try #require(capturedRequest)
        let contentType = try #require(urlRequest.value(forHTTPHeaderField: "Content-Type"))
        let body = try #require(urlRequest.httpBody)
        let bodyString = try #require(String(data: body, encoding: .utf8))
        let boundary = try #require(contentType.components(separatedBy: "boundary=").last)

        #expect(contentType.starts(with: "multipart/form-data; boundary="))
        #expect(bodyString.contains("filename=\"hello.txt\""))
        #expect(bodyString.contains("name=\"file\""))
        #expect(bodyString.contains("Content-Type: text/plain"))
        #expect(bodyString.contains("name=\"user\""))
        #expect(bodyString.contains("tester"))
        #expect(bodyString.contains("name=\"count\""))
        #expect(bodyString.contains("1"))
        #expect(bodyString.contains("--\(boundary)"))
    }

    @Test("Given reachability is offline, when upload is called, then it returns a no-internet response and does not send the request")
    func uploadReturnsNoInternetWhenOffline() async {
        // Given
        var didReceiveRequest = false

        MockURLProtocol.respond(path: "/upload-offline") { _ in
            didReceiveRequest = true
        }

        let request = Request.testRequest(
            method: HTTPMethod.post.rawValue,
            baseUrl: "https://example.com",
            endpoint: "/upload-offline",
            headers: nil,
            urlParams: nil,
            bodyParams: nil,
            reachable: false
        )

        let fileData = FileUploadData(
            data: Data("offline".utf8),
            mimeType: "text/plain",
            filename: "offline.txt",
            name: "file"
        )
        let params: [String: Any] = [
            "user": "tester"
        ]

        // When
        let response = await withCheckedContinuation { continuation in
            request.upload(files: [fileData], params: params) { response in
                continuation.resume(returning: response)
            }
        }

        // Then
        #expect(response.status == .noInternet)
        #expect(didReceiveRequest == false)
    }

    @Test("Given a download request with a temporary destination, when fetch is called, then it saves the file and returns status code 200")
    func fetchDownloadSavesFileToTemporaryDirectory() async throws {
        // Given
        let fileData = Data("downloaded content".utf8)
        let destinationURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        defer {
            try? FileManager.default.removeItem(at: destinationURL)
        }

        MockURLProtocol.respond(path: "/download", data: fileData)

        let request = Request.testRequest(
            method: HTTPMethod.get.rawValue,
            baseUrl: "https://example.com",
            endpoint: "/download"
        )

        // When
        let response = await withCheckedContinuation { continuation in
            request.fetch(withDownloadUrlFile: destinationURL) { response in
                continuation.resume(returning: response)
            }
        }

        // Then
        #expect(FileManager.default.fileExists(atPath: destinationURL.path))
        let savedData = try Data(contentsOf: destinationURL)
        #expect(savedData == fileData)
        #expect(response.statusCode == 200)
    }

    @Test("Given a download request with an existing destination file, when fetch is called, then it overwrites the file")
    func fetchDownloadOverwritesExistingFile() async throws {
        // Given
        let originalData = Data("original content".utf8)
        let updatedData = Data("updated content".utf8)
        let destinationURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        try originalData.write(to: destinationURL)
        defer {
            try? FileManager.default.removeItem(at: destinationURL)
        }

        MockURLProtocol.respond(path: "/download-overwrite", data: updatedData)

        let request = Request.testRequest(
            method: HTTPMethod.get.rawValue,
            baseUrl: "https://example.com",
            endpoint: "/download-overwrite"
        )

        // When
        let response = await withCheckedContinuation { continuation in
            request.fetch(withDownloadUrlFile: destinationURL) { response in
                continuation.resume(returning: response)
            }
        }

        // Then
        #expect(FileManager.default.fileExists(atPath: destinationURL.path))
        let savedData = try Data(contentsOf: destinationURL)
        #expect(savedData == updatedData)
        #expect(response.statusCode == 200)
    }

    @Test("Given cache policies that ignore local data, when fetch is called, then it clears the URL cache")
    func fetchClearsUrlCacheForIgnoringPolicies() async {
        // Given
        let policies: [NSURLRequest.CachePolicy] = [
            .reloadIgnoringLocalAndRemoteCacheData,
            .reloadRevalidatingCacheData,
            .reloadIgnoringLocalCacheData
        ]

        for policy in policies {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [MockURLProtocol.self]
            configuration.urlCache = URLCache(memoryCapacity: 1, diskCapacity: 1, diskPath: nil)

            MockURLProtocol.respond(path: "/cache-policy") { _ in }

            let request = Request.testRequest(
                method: HTTPMethod.get.rawValue,
                baseUrl: "https://example.com",
                endpoint: "/cache-policy",
                sessionConfiguration: configuration
            )
            request.cache = policy

            // When
            _ = await withCheckedContinuation { continuation in
                request.fetch { _ in
                    continuation.resume(returning: ())
                }
            }

            // Then
            #expect(configuration.requestCachePolicy == policy)
            #expect(configuration.urlCache == nil)
        }
    }
}
