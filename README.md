# GIGLibrary iOS

----
![Swift](https://img.shields.io/badge/Swift-6.2-orange.svg)
![Platform](https://img.shields.io/badge/Platform-iOS%2016%2B-blue.svg)
![SPM](https://img.shields.io/badge/SPM-compatible-brightgreen.svg)


Main library for Gigigo iOS projects.

## Requirements

- iOS 16.0+
- Swift 6.2 (the package builds in Swift 6 language mode with strict concurrency)
- Swift Package Manager (CocoaPods and Carthage are not supported)

See [CHANGELOG.md](CHANGELOG.md) for release history and migration notes.


## How to add it to my project

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/gigigoapps/gigigo-swift-lib.git", .upToNextMajor(from: "3.0.0"))
]
```


## What is included

- Core:
	- SwiftNetwork: Swift classes to manage gigigo's requestst. Standard Gigigo JSON is parsed by default.
	- GIGUtils: a lot of extensions on foundation classes.
	- GIGScanner: QR scanner using native iOS API

## Async usage examples

### Simple fetch

```swift
let request = Request(
    method: .get,
    baseUrl: "https://api.example.com",
    endpoint: "/v1/profile",
    headers: ["Authorization": "Bearer token"]
)

let response = await request.fetch()
if response.status == .success {
    let profile = try? response.json()
    print("Profile JSON: \(String(describing: profile))")
} else {
    print("Request failed with status: \(response.status)")
}
```

### Typed decodable fetch

```swift
struct Profile: Decodable {
    let id: Int
    let name: String
}

let request = Request(
    method: .get,
    baseUrl: "https://api.example.com",
    endpoint: "/v1/profile"
)

do {
    let profile: Profile = try await request.fetchDecodable()
    print("Profile: \(profile)")
} catch let error as FetchDecodableError {
    print("Decodable fetch failed: \(error)")
} catch {
    print("Unexpected error: \(error)")
}
```

Type inference also works naturally from function return types:

```swift
func myRequest() async throws -> Profile {
    try await Request(
        baseUrl: "https://api.example.com",
        endpoint: "/v1/profile"
    )
    .fetchDecodable()
}
```

`fetchDecodable()` throws `FetchDecodableError` to distinguish failure reasons:

- `requestFailed(status:statusCode:underlying:)`: transport/API status was not successful.
- `emptyResponseBody(statusCode:)`: response had no decodable payload (after empty body fallback).
- `decodingFailed(underlying:)`: payload exists but does not match your `Decodable` model.

Example handling by case:

```swift
do {
    let profile: Profile = try await request.fetchDecodable()
    print(profile)
} catch let FetchDecodableError.requestFailed(status, code, _) {
    print("Request failed: \(status) (\(code))")
} catch let FetchDecodableError.emptyResponseBody(code) {
    print("Empty body for status code \(code)")
} catch let FetchDecodableError.decodingFailed(error) {
    print("Decoding mismatch: \(error)")
}
```

### Void fetch (no response payload expected)

```swift
let request = Request(
    method: .post,
    baseUrl: "https://api.example.com",
    endpoint: "/v1/logout"
)

do {
    try await request.fetchVoid()
    print("Request completed successfully")
} catch {
    print("Request failed: \(error)")
}
```

`fetchVoid()` throws the underlying request/response error when available. If the request fails without an underlying error, it throws a fallback `NSError` with `kGIGNetworkErrorDomain` and the response status code.

### Download to file

```swift
let request = Request(
    method: .get,
    baseUrl: "https://cdn.example.com",
    endpoint: "/files/report.pdf"
)

let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
let destinationURL = documentsURL.appendingPathComponent("report.pdf")

let response = await request.fetch(downloadTo: destinationURL)
if response.status == .success {
    print("File downloaded to: \(destinationURL.path)")
} else {
    print("Download failed with status: \(response.status)")
}
```

### Multipart upload

```swift
let imageData = Data() // Provide real file data.
let file = FileUploadData(
    data: imageData,
    mimeType: "image/jpeg",
    filename: "avatar.jpg",
    name: "avatar"
)

let request = Request(
    method: .post,
    baseUrl: "https://api.example.com",
    endpoint: "/v1/uploads"
)

let response = await request.upload(
    files: [file],
    params: ["userId": "12345"]
)

if response.status == .success {
    print("Upload completed")
} else {
    print("Upload failed with status: \(response.status)")
}
```
