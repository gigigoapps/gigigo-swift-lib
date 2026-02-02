# GIGLibrary iOS

----
![Language](https://img.shields.io/badge/Language-Swift-orange.svg)


Main library for Gigigo iOS projects.


## How to add it to my project

### Swift Package Manager

```swift
dependencies: [
.package(url: "https://github.com/gigigoapps/gigigo-swift-lib.git", .upToNextMajor(from: "0.1.0"))
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
