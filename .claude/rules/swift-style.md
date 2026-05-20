# Swift Style

## Access Control

- `public` for library API surface
- `internal` (default) for helpers — omit the keyword
- `private` within types
- Do not use `open` — the library no longer exposes open classes

## Class vs Struct

- `Request` and `Response` are `public class` — keep them as classes
- Prefer structs for value types: `FileUploadData`, `KeychainOptions`, formatters
- Formatters are stateless enums with static methods (`RequestLogFormatter`, `ResponseLogFormatter`)

## MARK Comments

Group methods with `// MARK: - Section Name`:

```swift
// MARK: - Public API
// MARK: - Private Helpers
// MARK: - Initializers
```

## Naming

- Types: `UpperCamelCase`
- Functions, variables, parameters: `lowerCamelCase`
- Legacy public constants keep the `k` prefix (`kGIGNetworkErrorDomain`) — do not add new ones in this style
- Protocol conformances in a separate `extension` block at the bottom of the file, or in a dedicated file

## Error Handling

- Throw typed errors at API boundaries: `FetchDecodableError`, `Status` (keychain)
- Surface errors via `Response.error: NSError?` for non-throwing paths
- Do not use `fatalError` except for programmer-error invariants that are truly unreachable

## No External Dependencies

Do not add packages to `Package.swift`. Vendor third-party code into `Sources/GIGLibrary/Libs/External/` and do not modify vendored files.
