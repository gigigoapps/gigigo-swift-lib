# Changelog

All notable changes to **GIGLibrary** are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [3.0.0] - 2026-07-03

Major modernization release covering everything since 2.0.0 (Nov 2024): the
networking layer migrated from completion handlers to **async/await**, the
project adopted **Swift 6.2 with strict concurrency** (clean Release build) and
an **iOS 16** floor, and a full release audit closed a silent Keychain
protection failure, every data race, and dozens of UIKit/networking bugs.
**Contains extensive source-breaking changes** — see *Changed* and *Removed*.

### Requirements

- **iOS 16.0+** (was iOS 12).
- **Swift 6.2** toolchain; the package builds in Swift 6 language mode with
  `StrictConcurrency` and `ApproachableConcurrency` enabled, warning-free
  (including Release).
- **SPM only.** Project restructured to the standard SPM layout.

### Security

- **Keychain protection is now actually applied.** The fluent security API
  (`.accessibility(...)`, `.accessibility(_:authenticationPolicy:)`) was a
  silent no-op: every item was stored with the OS default accessibility,
  ignoring `whenPasscodeSetThisDeviceOnly`, `biometryAny`, etc. Items are now
  stored with the configured `kSecAttrAccessible` value, and an authentication
  policy produces a proper `SecAccessControl`. Changing the protection of an
  existing key safely recreates the item without data loss.
  **Action required:** if you stored sensitive data relying on those options,
  verify the effective protection after upgrading.
- **Logs no longer leak sensitive data in production.** Logging migrated from
  `print` to `os.Logger` with `privacy: .private` (payloads are redacted in
  Release builds, with per-module categories). `Selfie.description` — used by
  `Request`/`Response` — now redacts private fields (auth headers, tokens,
  bodies) instead of dumping every property via reflection; URLs carrying
  userinfo/query/fragment are redacted fail-closed.
- **Core Data predicate injection removed.** Fetch helpers no longer accept a
  raw format string; they take a pre-built `NSPredicate` (see *Changed*).

### Changed

**Breaking — networking is now async/await only:**

- The completion-handler APIs were removed and replaced by async equivalents:

  | 2.x | 3.0 |
  |-----|-----|
  | `fetch(completionHandler:)` | `await fetch() -> Response` |
  | `fetch(withDownloadUrlFile:completionHandler:)` | `await fetch(downloadTo:) -> Response` |
  | `upload(files:params:completionHandler:)` | `await upload(files:params:) -> Response` |

  Public async methods are annotated `@concurrent` and support cooperative
  cancellation (`Task` cancellation and `Request.cancel()`).
- `Request.method` is now the `HTTPMethod` enum (`.get`, `.post`, …) instead of
  a raw `String`.

**Breaking — API surface:**

- All `open` classes and members are now `public` / `public final`. Library
  types can no longer be subclassed from outside the module.
- `MultiDelegable` is now `@MainActor`-isolated. Conform from main-actor types;
  observer bookkeeping off the main actor is no longer allowed.
- `GIGScannerVC` is now `@MainActor`, `scannerOutput` is `weak`, and
  `GIGScannerOutput` requires `AnyObject`. Scanner outputs must be reference
  types used on the main actor.
- `NSManagedObjectContext.fetchFirst(_:predicate:)` and
  `fetchList(_:predicate:)` now `throw` (Core Data errors are propagated
  instead of swallowed) and take an `NSPredicate?` instead of a format
  `String`. All context work runs on the context's queue via `performAndWait`.
- `Style` enum cases renamed: `centerAligment`/`leftAligment`/`rightAligment` →
  `centerAlignment`/`leftAlignment`/`rightAlignment`; the `aligment:` parameter
  of `NSAttributedString(fromHTML:...)` is now `alignment:`.
- `RequestLogInfo.filename` and `DefaultRequestLogInfo.filename` (and its
  `init`) changed from `NSString` to `String` (required for `Sendable`).

**Behavioral:**

- Requests automatically add an `Accept: application/json` header (and
  `Content-Type: application/json` on non-GET requests) unless already present.
- HTTP status `300` (Multiple Choices) is no longer treated as `.success`;
  the success range is `200..<300`. On non-2xx responses the HTTP status takes
  precedence over the Gigigo envelope.
- `Request` URL building is normalized: `baseURL` and `endpoint` are joined
  with exactly one `/` (no more `/v1items` or `//`), and query parameters are
  encoded by type — arrays expand to repeated items, booleans render as
  `true`/`false`, numbers keep canonical form, and `Optional(...)`/`[1, 2]`
  artifacts can no longer leak into the URL.
- An injected/shared `URLSession` is no longer invalidated when a request
  finishes; only sessions the library creates internally are.
- `Response` is now effectively immutable after construction
  (`public private(set)` properties).
- `Response.image()` decodes animated GIFs (previously rejected); GIFs are
  detected by URL extension **or** by the `GIF8` byte signature, so a GIF
  served from an extensionless URL still animates.
- `UIImageView.loadGif(urlString:)` now routes remote URLs through the managed
  async downloader (cancellable, bounded concurrency, cached) instead of
  performing synchronous network I/O on a background queue; `file://` URLs are
  decoded locally off-main. A failed load preserves the current image instead
  of blanking the view.
- `ViewStyle.backgroundColor` defaults to `.clear` instead of `.white`, and all
  `ViewStyle` properties are now immutable (`let`).
- HTML parsing APIs (`NSAttributedString(fromHTML:...)`, `Data.attributedString`)
  are annotated `@MainActor`, matching WebKit's main-thread requirement.
- Date parsing/formatting is deterministic across devices: cached formatters
  use `en_US_POSIX` and a fixed GMT time zone for zone-less formats.
- `Locale.currentRegionCode()` reads `Locale.current.region` (the user's actual
  region) instead of string-splitting `preferredLanguages`, fixing wrong values
  for language tags without a region or with script subtags (e.g. `zh-Hant`).
- File/type modernization: `NSDate+GIGExtension.swift` → `Date+GIGExtension.swift`,
  `NSLocale+GIGExtension.swift` → `Locale+GIGExtension.swift`; `setHour` uses
  value-typed `Calendar` APIs (no `NSCalendar` bridging).

### Deprecated

- `String.base64URLSafeDecode()` → renamed `base64URLSafeToStandard()`.
  ⚠️ Note: this method never decoded — it converts the URL-safe alphabet to
  standard Base64 and restores padding. Use `Data(base64Encoded:)` on the
  result to actually decode.
- `InfoDictionary(_:)` (returns the `"CONSTANT NOT FOUND"` sentinel) → use the
  new `infoDictionary(_:) -> String?`, which makes a missing key representable.
- `UIImage.gif(url:)` (blocking network I/O) → use
  `UIImageView.loadGif(urlString:)` (managed, async, cancellable) for remote
  GIFs, or `UIImage.gif(data:)` when you already hold the bytes.

### Removed

**Breaking:**

- **`UIComponents` module** (`ProgressPageControl`) — removed entirely.
- **`ScreenRecord`** utility — removed.
- **`GIGScannerViewController`** — removed (dead duplicate of `GIGScannerVC`).
- `UILabel.styledString` / `UILabel.html` and `UITextView.styledString` /
  `UITextView.html` **properties** (their getters always returned `nil`).
  Use the `styledString(_:)` / `html(_:)` methods.
- `TextViewStyle.borderStyle` (and its `init` parameter) — `UITextView` has no
  border style; it never had any effect. Use `viewStyle` for borders.
- `UIStoryboard.GIGStoryboard(_:)` and `GIGInitialVC(_:)` — broken when the
  library is consumed via SPM (`Bundle(identifier:)` is always `nil`). Load
  storyboards from your app's bundle directly.
- `GIGIOSVersion.swift` globals (`Device`, `iosVersion`, `MAJORTHANIOS8`,
  `iOS7`) — dead code with an iOS 16 floor. Use `#available` checks.
- Obsolete `@available` annotations and iOS < 16 compatibility paths across the
  library (Keychain constants, authentication context, window lookup).
- Internal dead code: `aligmentString(fromAligment:)`, duplicate
  `roundCorners(corners:radius:)` in `UIView+Borders`.

### Added

- **Typed async networking APIs**:
  - `fetchDecodable<T: Decodable>() async throws -> T` — decodes the response
    body directly into your model, throwing the typed `FetchDecodableError`
    (`requestFailed` / `emptyResponseBody` / `decodingFailed`).
  - `fetchVoid() async throws` — for endpoints with no meaningful body.
- `Request` improvements: `Encodable` body support
  (`init(method:baseUrl:endpoint:body:)` using `JSONEncoder`), JSON-array
  bodies via `bodyParamsArray`, and the `HTTPMethod` enum.
- Injectable network logging: the `NetworkLogManaging` protocol (with
  `RequestLogFormatter`/`ResponseLogFormatter`) lets tests and consumers
  capture or route request/response logs; both protocols are `Sendable`.
- `ImageDownloader` configuration: `maxConcurrentDownloads` (bounded parallel
  downloads with a pending queue) and `maxCachedImages` (cache bound).
- `StyledButton` — a `UIButton` subclass with a state-aware disabled background
  color that swaps on `isEnabled` and keeps dynamic (light/dark) colors
  resolving. Configure via the new `ButtonStyle.disabledBackgroundColor`.
- `KeychainAccessibility.whenPasscodeSetThisDeviceOnly`.
- `infoDictionary(_:) -> String?` — optional-returning Info.plist accessor.
- `Selfie.selfieExposedKeys` — opt-in whitelist controlling which properties
  `description` prints verbatim; everything else renders as `<redacted>`.
- `UIColor(hex:)` now accepts 3-digit shorthand and 8-digit `RRGGBBAA` (alpha)
  values, with or without a leading `#`.
- `ErrorDate.invalidDate` case (thrown when a date cannot be rebuilt);
  `ErrorDate` is now `Equatable`.
- `Locale.languageCode(from:)` / `Locale.regionCode(from:)` — pure, testable
  BCP-47 parsers backed by the typed `Locale` API.
- Tooling: GitHub Actions CI (build + tests on iOS Simulator) and a strict
  SwiftLint configuration (0 violations).
- Extensive new test coverage (Swift Testing + integration tests over a mocked
  `URLSession`): SwiftNetwork request/response/upload/download/cache flows,
  KeychainStore CRUD/enumeration, `Status` mapping, ReachabilityWrapper,
  URL building/query encoding, Style system, StyledString font resolution,
  String helpers, Date/Locale/Color/Bundle/Error extensions, JSON subscript
  traversal, Core Data helpers, HyperlinkTextView caching, QRGenerator, and
  ImageDownloader (including cell-reuse races and memory-warning purge).

### Fixed

- **Scanner**: no longer crashes on the Simulator or camera-less devices
  (`captureDevice` is a real optional); the capture session is only configured
  after camera authorization is granted (fail-closed); fixed a configuration
  lock leak in `focusCamera`.
- **Networking**: cancellation state in `Request` is guarded by a lock —
  cancelling from another thread while a fetch is in flight is now safe;
  `ReachabilityWrapper` state is lock-protected and `startNotifier`/
  `stopNotifier` are idempotent (no duplicate NotificationCenter observers).
- **Logging**: `LogManager` accessors are fully synchronized (settings are a
  value type now); log handlers run outside the internal queue, removing a
  reentrancy deadlock; changing settings while logging from another thread is
  safe.
- **Images**: download slots are released when the network finishes (not after
  resizing) and when a view is reused before its task starts — the concurrency
  limit and cache survive memory pressure; reused cells always show the *last
  requested* image/GIF, never the one that happened to finish last — across all
  combinations of `image(from:)`, `loadGif(name:)` and `loadGif(urlString:)`;
  the cache key can no longer diverge between store and lookup;
  `imageProportionally` no longer traps on zero/degenerate sizes; animated GIFs
  are not flattened by the resize step.
- **Styles**: `resetBorders()` no longer deletes unrelated `CAShapeLayer`s
  (e.g. gradients or progress layers added by the app); dashed borders track
  the view's bounds and corner radius across layout/rotation; `letterSpacing`
  is applied even when `isStrikedThrough` is set; strikethrough uses
  `.single` (was a magic `2` = `.thick`); disabled buttons no longer keep a
  permanently dimmed background.
- **Keyboard**: `KeyboardAdaptable` observers are per-instance — a disappearing
  screen no longer silences keyboard events for screens beneath it; show/hide
  height math is symmetric (captured once, restored exactly).
- **JSON**: dot-path subscript (`json["a.b.c"]`) returns `nil` when an
  intermediate key is not a dictionary, instead of silently resolving a node
  from the wrong nesting level.
- **MultiDelegable**: observers are identified by stable object identity
  (`ObjectIdentifier`), not `hashValue` — no more hash-collision mis-removal;
  deallocated observers are purged on `execute`.
- **Strings/HTML**: concatenating styled strings no longer injects an empty
  attribute key; bold/italic traits survive a later `.size` style (font styles
  resolve in source order); HTML string encoding failures are handled.
- **Application**: `presentModal` restores deferred presentation (regression in
  the Swift 6 migration).

### Performance

- Image cache is an `NSCache` with a configurable count limit — bounded memory,
  automatic eviction under pressure (was an unbounded dictionary only cleared
  on memory warnings).
- `DateFormatter` instances are cached per format string (formatter creation is
  one of Foundation's most expensive operations; they were rebuilt per call).
- `HyperlinkTextView` caches parsed HTML attributed strings (bounded, FIFO) —
  expanding/collapsing no longer re-parses the HTML each time.
- Heavy GIF decodes and image resizes run off the main actor.

[3.0.0]: https://github.com/gigigoapps/gigigo-swift-lib/compare/v2.0.0...v3.0.0
