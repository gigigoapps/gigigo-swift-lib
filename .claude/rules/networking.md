---
paths:
  - "Sources/GIGLibrary/SwiftNetwork/**"
  - "Tests/GIGLibraryTests/SwiftNetwork/**"
---

# SwiftNetwork

## Request

`public class Request` — builds and fires HTTP requests. All methods are async; no callbacks.

### Public Properties

| Property | Type | Default |
|----------|------|---------|
| `method` | `HTTPMethod` | `.get` |
| `baseURL` | `String` | — |
| `endpoint` | `String` | — |
| `headers` | `[String: String]?` | `nil` |
| `urlParams` | `[String: Any]?` | `nil` |
| `bodyParams` | `[String: Any]?` | `nil` |
| `verbose` | `Bool` | `false` |
| `standardType` | `StandardType` | `.gigigo` |
| `timeout` | `TimeInterval` | `15.0` |

### Async API

```swift
// Never throws — check Response.status
func fetch() async -> Response

// Throws FetchDecodableError
func fetchDecodable<T: Decodable>() async throws -> T

// Throws NSError on failure
func fetchVoid() async throws

// Never throws — downloads to disk
func fetch(downloadTo fileURL: URL) async -> Response

// Never throws — multipart upload
func upload(files: [FileUploadData], params: [String: Any]) async -> Response

func cancel()
```

### Initializers

```swift
// Dictionary body
Request(method: .post, baseUrl: "https://api.example.com", endpoint: "/items",
        bodyParams: ["key": "value"])

// Array body
Request(method: .post, baseUrl: "...", endpoint: "/items",
        bodyParamsArray: [["id": 1], ["id": 2]])

// Encodable body (type-safe, uses JSONEncoder)
Request(method: .post, baseUrl: "...", endpoint: "/items", body: myEncodable)
```

### Automatic Headers

Added unless already present (case-insensitive check):
- `Accept: application/json` — every request
- `Content-Type: application/json` — non-GET requests

### StandardType

- `.gigigo` (default): expects `{ "status": true/"OK", "data": {...} }` wrapper; parses `data` field
- `.basic`: returns the raw JSON directly into `Response.data`

### HTTPMethod

`.get` `.post` `.put` `.delete` `.patch` `.options` `.head` `.trace` `.connect`

### FileUploadData

```swift
FileUploadData(data: Data, mimeType: String, filename: String, name: String)
```

---

## Response

`public class Response: @unchecked Sendable`

| Property | Type |
|----------|------|
| `status` | `ResponseStatus` |
| `statusCode` | `Int` |
| `data` | `JSON?` — parsed body |
| `body` | `Data?` — raw bytes |
| `error` | `NSError?` |
| `url` | `URL?` |
| `headers` | `[AnyHashable: Any]?` |

Helper methods:
- `json() throws -> JSON`
- `image() throws -> UIImage` — **requires `@MainActor`**

Internal factory methods: `noInternet()`, `invalidURL()`, `cancelled()`, `cannotEncodeContentData()`

### ResponseStatus (Sendable)

`.success` `.errorParsingJson` `.sessionExpired` `.timeout` `.noInternet` `.apiError` `.unknownError` `.untrustedCertificate`

### Error Code Mapping

| Code | Status |
|------|--------|
| 401, 403 | `.sessionExpired` |
| -1001 | `.timeout` |
| -1009 | `.noInternet` |
| -1202 | `.untrustedCertificate` |
| 10000–20000 | `.apiError` |

### Gigigo JSON Format

```json
{ "status": true,  "data": { ... } }
{ "status": "OK",  "data": { ... } }
{ "status": false, "error": { "code": 1001, "message": "..." } }
```

---

## FetchDecodableError

```swift
case requestFailed(status: ResponseStatus, statusCode: Int, underlying: NSError?)
case emptyResponseBody(statusCode: Int)
case decodingFailed(underlying: Error)
```

---

## NetworkLogManaging

Internal protocol for injectable logging:

```swift
protocol NetworkLogManaging {
    func log(_ message: String, info: RequestLogInfo?)
}
```

Default: `DefaultNetworkLogManager` (prints or routes to `gigLog*`).
In tests: inject `NetworkLogManagerSpy` via the designated `init` to capture log calls.

---

## Pitfalls

- `fetch()` **never throws** — always check `Response.status` before using `Response.data`
- `fetchDecodable` and `fetchVoid` **do** throw — wrap in `do/catch`
- `Response.image()` requires `@MainActor` — call inside `await MainActor.run { }` if not already on main
- `Response.image()` decodes `.gif` URLs as animated images (via `UIImage.gif(data:)`); other URLs decode as a single `UIImage`
- `.gigigo` standard type marks the response as failed on `{ "status": false }` even with HTTP 200 — intentional
- `fetch()` silently returns a `.noInternet` response if reachability check fails — no exception is raised
- Only HTTP `200..<300` is `.success`; `300`+ map to an error status
- `baseURL` must be an **absolute URL with a scheme** — a missing/invalid scheme yields an `.invalidURL` response
- `endpoint` is **path-only**, joined to `baseURL` with exactly one `/` (no `//`, no missing slash). A `?query`/`#fragment` in `endpoint` is percent-encoded into the path; pass query items via `urlParams` or include them in `baseURL`
- `urlParams` values are encoded by type (`String`/`Int`/`Double`/`Bool`→`true`/`false`/`NSNumber`); an array value expands to one item per element under the same name; `NSNull` yields a valueless item
