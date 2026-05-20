# CLAUDE.md — GIGLibrary iOS

**GIGLibrary** is the core iOS utility library for Gigigo projects: networking, secure storage, UI helpers, styling, logging, and Foundation/UIKit extensions. SPM only; no CocoaPods or Carthage.

- **Language**: Swift 6.2 (`swiftLanguageMode(.v6)`)
- **Minimum platform**: iOS 16.0
- **No external dependencies**
- **Concurrency**: `StrictConcurrency` + `ApproachableConcurrency` enabled

## Repository Layout

```
gigigo-swift-lib/
├── Package.swift
├── AGENTS.md
├── .swiftlint.yml
├── Sources/GIGLibrary/
│   ├── SwiftNetwork/      # Async HTTP client
│   ├── KeychainStore/     # Secure Keychain wrapper
│   ├── GIGScanner/        # QR code scanner (AVCapture)
│   ├── GIGUtils/          # Extensions and helpers
│   └── Libs/External/     # Vendored third-party code (do not modify)
└── Tests/GIGLibraryTests/
    ├── GIGUtils/
    └── SwiftNetwork/
```

## Commands

```bash
# Tests (macOS only — do not run on Linux)
swift test
xcodebuild -scheme GIGLibrary \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' test

# Lint
swiftlint          # check
swiftlint --fix    # auto-fix

# Open in Xcode (no .xcodeproj)
xed .
```

## CI

File: `.github/workflows/ci.yml` — triggers on push/PR to `main`, `master`, `develop`.
Runner: `macos-latest`, Xcode `>= 26`, iPhone 17 Pro simulator.

## Branching

- `main` / `master` — stable releases
- `develop` — integration branch (most up to date)
- `feature/<name>` / `claude/<name>` — feature branches
