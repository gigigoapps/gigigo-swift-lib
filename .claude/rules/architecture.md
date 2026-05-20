# Architecture

## Source Tree

```
Sources/GIGLibrary/
├── SwiftNetwork/
│   ├── Request.swift
│   ├── Response.swift
│   ├── FetchDecodableError.swift
│   ├── ReachabilityWrapper.swift
│   └── Helpers/
│       ├── NetworkLogManaging.swift
│       ├── RequestLogFormatter.swift
│       └── ResponseLogFormatter.swift
├── KeychainStore/              # 7 files
├── GIGScanner/                 # 2 files
├── RequestLogInfo.swift
├── Libs/External/Reachability.swift
└── GIGUtils/
    ├── ActionSheet/
    ├── AlertController/
    ├── Application/            # UIApplication+Window.swift
    ├── Bundle/
    ├── Color/
    ├── CoreData/
    ├── Date/
    ├── Dispatch.swift
    ├── Error/
    ├── GIGIOSVersion.swift
    ├── Image/
    ├── InfoPlist.swift
    ├── Instantiator.swift
    ├── Keyboard/
    ├── Locale/
    ├── Log/
    ├── MultiDelegable.swift
    ├── QRGenerator/
    ├── Selfie.swift
    ├── Storyboard/
    ├── String/
    ├── Style/
    │   ├── Stylable.swift
    │   ├── StylableExtensions/   # UIButton, UILabel, UITextField, UITextView, UIView, UIString
    │   ├── Styles/               # ButtonStyle, LabelStyle, TextFieldStyle, TextViewStyle, ViewStyle, TextStyle
    │   └── UIKitExtensions/
    ├── SwiftJson/Json.swift
    ├── TextView/
    │   ├── ExpandableTextView/
    │   └── HyperlinkTextView/
    └── View/

Tests/GIGLibraryTests/
├── GIGUtils/                   # Date, JSON, Style, StyledString tests
└── SwiftNetwork/
    ├── Fakes/
    │   ├── Fixtures/            # JSON fixtures (SPM resource bundle)
    │   ├── FixtureLoader.swift
    │   └── ResponseFakes.swift
    ├── Mocks/
    │   ├── NetworkLogManagerSpy.swift
    │   └── RequestMocks.swift
    ├── IntegrationTests.swift
    ├── RequestTests.swift
    ├── ResponseTests.swift
    └── TestModels.swift
```

## Module Overview

| Module | Purpose |
|--------|---------|
| `SwiftNetwork` | Async HTTP client: Request, Response, multipart upload, file download |
| `KeychainStore` | Fluent API wrapper around Apple Security framework |
| `GIGScanner` | QR code scanning via AVCaptureSession |
| `GIGUtils/Log` | LogManager singleton with per-module levels and styles |
| `GIGUtils/SwiftJson` | JSON wrapper with dot-notation subscript traversal |
| `GIGUtils/Style` | Protocol-based UIKit styling (Stylable, ViewStylable) |

## Notable Utilities

| File | Purpose |
|------|---------|
| `Selfie.swift` | `description` via Mirror reflection; Request/Response conform |
| `Instantiator.swift` | `Instantiable` protocol for storyboard VC instantiation (`@MainActor`) |
| `MultiDelegable.swift` | Broadcast to multiple delegates |
| `Dispatch.swift` | GCD helpers (`@Sendable`-annotated) |
| `UIApplication+Window.swift` | Active window lookup helper |
| `ImageDownloader.swift` | Async image download with caching (`@MainActor`) |
| `QRGenerator.swift` | Generates UIImage QR codes from strings |
| `KeyboardAdaptable.swift` | Protocol for keyboard show/hide layout adjustment |
| `ExpandableTextView.swift` | Auto-expanding UITextView |
| `HyperlinkTextView.swift` | UITextView with tappable hyperlinks |

## Public API Constants

```swift
public let kGIGNetworkErrorDomain = "com.gigigo.network"
public let kGIGNetworkErrorMessage = "GIGNETWORK_ERROR_MESSAGE"
```

## Adding a New Utility

1. Create `Sources/GIGLibrary/GIGUtils/<FeatureName>/<FeatureName>.swift`
2. SPM auto-discovers sources — no `Package.swift` change needed
3. Add tests under `Tests/GIGLibraryTests/GIGUtils/`

## Adding a New Network Helper

1. Add source to `Sources/GIGLibrary/SwiftNetwork/Helpers/`
2. Keep formatters pure: static methods on enums, no state
3. Inject via `NetworkLogManaging` for logging in tests
