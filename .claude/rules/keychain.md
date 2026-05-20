---
paths:
  - "Sources/GIGLibrary/KeychainStore/**"
---

# KeychainStore

Fluent-API wrapper around Apple's Security framework. All throwing methods surface `Status` errors.

## Initializers

```swift
KeychainStore()                            // uses bundle identifier as service
KeychainStore(service: "com.example.app")
KeychainStore(accessGroup: "group.id")
KeychainStore(service: "...", accessGroup: "...")
```

## Builder Pattern (returns a new configured instance)

```swift
let store = KeychainStore()
    .accessibility(.afterFirstUnlock)
    .accessibility(.whenPasscodeSetThisDeviceOnly, authenticationPolicy: .biometryAny)
    .synchronizable(true)
    .label("My Token")
    .comment("Auth token")
    .authenticationPrompt("Confirm identity")
    .authenticationContext(laContext)
```

## Read / Write

```swift
// Throwing API
try store.set("value", key: "myKey")
let value: String? = try store.get("myKey")
let raw: Data?     = try store.getData("myKey")
try store.remove("myKey")
try store.removeAll()
let exists = try store.contains("myKey")

// Non-throwing subscript (swallows errors silently)
store["myKey"] = "value"
let s: String? = store["myKey"]
let d: Data?   = store[data: "myKey"]
```

## Enumeration

```swift
store.allKeys()                        // [String] for this service
KeychainStore.allKeys()                // [(service, key)] across all services
store.allItems()                       // [[String: Any]]
KeychainStore.allItems()               // [[String: Any]] across all
```

## Key Files

`KeychainStore.swift`, `KeychainAccessibility.swift`, `KeychainAuthenticationPolicy.swift`, `KeychainOptions.swift`, `KeychainAttributes.swift`, `KeychainConstants.swift`, `Status.swift`

## Pitfalls

- Throwing methods must be wrapped in `try`/`do-catch`; use subscript accessors when error handling is not critical
- `setLogValues(forModule:)` in `LogManager` throws if the module is registered twice — call `removeSettingsForModule` before re-registering (unrelated but often paired with Keychain setup)
