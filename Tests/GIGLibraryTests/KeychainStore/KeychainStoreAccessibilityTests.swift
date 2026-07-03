//
//  KeychainStoreAccessibilityTests.swift
//  GIGLibrary
//
//  Live round-trip: store a value through `KeychainStore` with a given
//  accessibility and read `kSecAttrAccessible` straight back via
//  `SecItemCopyMatching`. Guarded by `.enabled(if:)` so it is skipped (not
//  failed) on hosts where the keychain is not usable for the test process.
//

import Testing
import Foundation
import Security
@testable import GIGLibrary

/// Probes whether the test process can actually add/read keychain items.
///
/// A bare SwiftPM test bundle run through `xcodebuild` (as CI does) has no
/// `keychain-access-groups` entitlement — there is no host app supplying an
/// `application-identifier` — so `SecItemAdd` fails with
/// `errSecMissingEntitlement` (`-34018`). When that happens this round-trip
/// suite is skipped (not failed); `KeychainOptionsTests` still proves the fix
/// deterministically. The suite runs wherever the keychain is reachable
/// (e.g. inside a host app with an entitlement).
enum KeychainTestEnvironment {
    static let isAvailable: Bool = {
        let service = "com.gigigo.tests.keychain.probe"
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "probe",
            kSecValueData as String: Data("1".utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemDelete(item as CFDictionary)
        let status = SecItemAdd(item as CFDictionary, nil)
        SecItemDelete(item as CFDictionary)
        return status == errSecSuccess
    }()
}

@Suite(.serialized, .enabled(if: KeychainTestEnvironment.isAvailable))
struct KeychainStoreAccessibilityTests {

    private static let service = "com.gigigo.tests.keychain.accessibility"

    private func readAccessible(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: key,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnAttributes as String: kCFBooleanTrue as Any
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let attributes = result as? [String: Any] else { return nil }
        return attributes[kSecAttrAccessible as String] as? String
    }

    @Test("Stored accessibility is persisted and read back as kSecAttrAccessible")
    func accessibilityRoundTrips() throws {
        // `.whenPasscodeSetThisDeviceOnly` is intentionally excluded: it can only
        // be written when the device has a passcode, so a live round-trip would be
        // environment-dependent. Its mapping is covered deterministically in
        // KeychainOptionsTests.
        let cases: [(KeychainAccessibility, CFString)] = [
            (.whenUnlocked, kSecAttrAccessibleWhenUnlocked),
            (.afterFirstUnlock, kSecAttrAccessibleAfterFirstUnlock),
            (.whenUnlockedThisDeviceOnly, kSecAttrAccessibleWhenUnlockedThisDeviceOnly),
            (.afterFirstUnlockThisDeviceOnly, kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly),
            (.always, kSecAttrAccessibleAfterFirstUnlock),
            (.alwaysThisDeviceOnly, kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly)
        ]

        for (accessibility, expected) in cases {
            let key = "round-trip-\(accessibility.description)"
            let store = KeychainStore(service: Self.service).accessibility(accessibility)

            try? store.remove(key)
            try store.set("value", key: key)
            defer { try? store.remove(key) }

            #expect(self.readAccessible(key: key) == expected as String)
            #expect(try store.get(key) == "value")
        }
    }

    @Test("Updating an existing item rewrites its accessibility")
    func accessibilityIsUpdatedOnRewrite() throws {
        let key = "round-trip-update"
        try? KeychainStore(service: Self.service).remove(key)
        defer { try? KeychainStore(service: Self.service).remove(key) }

        try KeychainStore(service: Self.service).accessibility(.whenUnlocked).set("first", key: key)
        #expect(self.readAccessible(key: key) == kSecAttrAccessibleWhenUnlocked as String)

        try KeychainStore(service: Self.service).accessibility(.afterFirstUnlockThisDeviceOnly).set("second", key: key)
        #expect(self.readAccessible(key: key) == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
        #expect(try KeychainStore(service: Self.service).get(key) == "second")
    }
}
