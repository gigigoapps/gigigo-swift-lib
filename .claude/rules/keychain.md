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
- `.accessibility(.whenPasscodeSetThisDeviceOnly, ...)` requires a device passcode: `set` throws if none is set, and the item is deleted if the user later removes the passcode. It never migrates to another device.
- `.synchronizable(true)` is only honored for non-device-local protection classes without an `authenticationPolicy`. Policy-gated items and any `...ThisDeviceOnly` / `.whenPasscodeSetThisDeviceOnly` accessibility cannot be synced (iCloud Keychain rejects them with `errSecParam`), so they are stored non-synchronizable regardless of the flag — and strict (`ignoringAttributeSynchronizable: false`) lookups match that.
- `.always` / `.alwaysThisDeviceOnly` no longer grant before-first-unlock access: the deprecated `kSecAttrAccessibleAlways*` classes are rejected on iOS 16+, so they map to their `afterFirstUnlock` equivalents. Prefer `.afterFirstUnlock(ThisDeviceOnly)` explicitly.
- Changing an existing key's protection (adding or removing `kSecAttrAccessControl`) requires recreating the item (delete + add), because the access control is add-only for `SecItemUpdate`. `set` does this safely: it refuses (throws `Status.interactionNotAllowed`) rather than delete when the existing item is protected/locked and can't be backed up, and otherwise backs the value up and restores it if the re-add fails — so a failed protection change never drops the credential. A protected/locked key thus can't be re-protected in place; `remove` it (or retry while unlocked) first.
- `setLogValues(forModule:)` in `LogManager` throws if the module is registered twice — call `removeSettingsForModule` before re-registering (unrelated but often paired with Keychain setup)
