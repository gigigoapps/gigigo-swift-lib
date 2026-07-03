---
paths:
  - "Tests/**"
---

# Testing

## Framework

Use **Swift Testing** — not XCTest.

```swift
import Testing
@testable import GIGLibrary
```

## Structure

```swift
@Suite("FeatureName")
struct FeatureTests {

    @Test("Given X, when Y, then Z")
    func someScenario() async throws {
        // arrange
        // act
        // assert
        #expect(result == expected)
        #expect(throws: SomeError.self) { try riskyCall() }
    }
}
```

- Suite names: the feature or type under test
- Test names: full Given/When/Then sentence
- Use `@Suite(.serialized)` when tests share mutable state or network mocks

## BDD Style

Test observable behaviour, not implementation details:
- ✅ "Given a successful response, the status is .success"
- ❌ "parseJSON is called when Content-Type is JSON"

Cover: happy path, error cases, edge cases (empty body, no internet, cancellation).

## Dependency Injection

Inject via the internal designated `init` — never reach into private state:

```swift
// Session injection
let session = URLSession(configuration: mockConfig)
let request = Request(method: .get, baseUrl: "...", endpoint: "/",
                      session: session)

// Reachability injection
let request = Request(..., reachability: AlwaysReachableMock())

// Log manager injection
let spy = NetworkLogManagerSpy()
let request = Request(..., networkLogManager: spy)
```

## Fixtures

JSON fixtures live in `Tests/GIGLibraryTests/SwiftNetwork/Fakes/Fixtures/` and are bundled as an SPM resource:

```swift
// Load via FixtureLoader
let data = try FixtureLoader.load("success_response.json")
```

## Mocks & Fakes

| Type | Location | Purpose |
|------|----------|---------|
| `NetworkLogManagerSpy` | `Mocks/` | Captures log calls for assertion |
| `RequestMocks` | `Mocks/` | Pre-built URLProtocol stubs |
| `ResponseFakes` | `Fakes/` | Factory methods for Response objects |
| `MockURLProtocol` | inline in test files | Intercepts URLSession at protocol level |

## File Locations

- GIGUtils tests: `Tests/GIGLibraryTests/GIGUtils/`
- SwiftNetwork tests: `Tests/GIGLibraryTests/SwiftNetwork/`
- Tests are discovered automatically by SPM
