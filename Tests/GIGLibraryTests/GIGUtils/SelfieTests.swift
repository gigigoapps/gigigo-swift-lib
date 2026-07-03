//
//  SelfieTests.swift
//  GIGLibrary
//
//  Created by Alejandro Jiménez Agudo.
//  Copyright © 2026 Gigigo SL. All rights reserved.
//

import Testing
import Foundation
@testable import GIGLibrary

@Suite("Selfie")
struct SelfieTests {

    private struct Sensitive: Selfie {
        let name: String
        let token: String
        var selfieExposedKeys: Set<String>? { ["name"] }
    }

    private struct Plain: Selfie {
        let a: Int
        let b: Int
    }

    @Test("Given an exposed-keys whitelist, only listed properties are printed and the rest are redacted")
    func whitelistRedactsUnlistedProperties() {
        let description = Sensitive(name: "public", token: "s3cr3t").description
        #expect(description.contains("name: public"))
        #expect(description.contains("token: <redacted>"))
        #expect(!description.contains("s3cr3t"))
    }

    @Test("Given the default (nil) exposed keys, every property is printed verbatim")
    func defaultExposesEverything() {
        let description = Plain(a: 1, b: 2).description
        #expect(description.contains("a: 1"))
        #expect(description.contains("b: 2"))
        #expect(!description.contains("<redacted>"))
    }

    @Test("Given a Request, its Selfie description redacts headers and body payloads")
    func requestRedactsSensitiveFields() {
        let request = Request(
            method: .post,
            baseUrl: "https://api.example.com",
            endpoint: "/login",
            headers: ["Authorization": "Bearer s3cr3t-token"],
            bodyParams: ["password": "hunter2"]
        )
        let description = request.description
        #expect(description.contains("baseURL: https://api.example.com"))
        #expect(description.contains("endpoint: /login"))
        #expect(description.contains("headers: <redacted>"))
        #expect(description.contains("bodyParams: <redacted>"))
        #expect(!description.contains("s3cr3t-token"))
        #expect(!description.contains("hunter2"))
    }

    @Test("Given a Request whose baseUrl or endpoint embeds a credential, Selfie redacts that field")
    func requestRedactsCredentialsInURLFields() {
        let request = Request(
            method: .get,
            baseUrl: "https://api.example.com?access_token=s3cr3t-token",
            endpoint: "/items?signature=s3cr3t-sig",
            bodyParams: nil
        )
        let description = request.description
        #expect(description.contains("baseURL: <redacted>"))
        #expect(description.contains("endpoint: <redacted>"))
        #expect(!description.contains("s3cr3t-token"))
        #expect(!description.contains("s3cr3t-sig"))
    }

    @Test("Given a Response carrying a server error message, its Selfie description redacts the error")
    func responseRedactsErrorMessage() {
        let response = Response(error: NSError(domain: "com.test", code: 42, message: "token=s3cr3t-in-message"))
        let description = response.description
        #expect(description.contains("error: <redacted>"))
        #expect(!description.contains("s3cr3t-in-message"))
    }

    @Test("Given a Response, its Selfie description redacts headers, body, data, url and error")
    func responseRedactsSensitiveFields() {
        let url = URL(string: "https://api.example.com/session?access_token=s3cr3t-token")!
        let httpResponse = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Set-Cookie": "session=s3cr3t-token"]
        )
        let response = Response(data: Data("{\"a\":1}".utf8), response: httpResponse, error: nil, standardType: .basic)
        let description = response.description
        #expect(description.contains("statusCode: 200"))
        #expect(description.contains("headers: <redacted>"))
        #expect(description.contains("body: <redacted>"))
        #expect(description.contains("data: <redacted>"))
        #expect(description.contains("url: <redacted>"))
        #expect(description.contains("error: <redacted>"))
        #expect(!description.contains("s3cr3t-token"))
    }
}
