//
//  KeychainOptionsTests.swift
//  GIGLibrary
//
//  Verifies that the protection class requested through the fluent API
//  (`accessibility` / `authenticationPolicy`) actually reaches the dictionary
//  handed to `SecItemAdd` / `SecItemUpdate`. These are pure unit tests over
//  `KeychainOptions.attributes(key:value:)` and need no live keychain.
//

import Testing
import Foundation
import Security
@testable import GIGLibrary

@Suite("KeychainOptions attribute building")
struct KeychainOptionsTests {

    private func makeOptions(
        accessibility: KeychainAccessibility,
        authenticationPolicy: KeychainAuthenticationPolicy? = nil,
        synchronizable: Bool = false
    ) -> KeychainOptions {
        var options = KeychainOptions()
        options.service = "com.gigigo.tests.keychainoptions"
        options.accessibility = accessibility
        options.authenticationPolicy = authenticationPolicy
        options.synchronizable = synchronizable
        return options
    }

    // MARK: - Accessibility without an authentication policy

    @Test("Each accessibility is written as the matching kSecAttrAccessible value")
    func accessibilityIsWritten() throws {
        // `.always` / `.alwaysThisDeviceOnly` intentionally map to their
        // `afterFirstUnlock` equivalents (the kSecAttrAccessibleAlways* constants
        // are deprecated and rejected on iOS 16+).
        let cases: [(KeychainAccessibility, CFString)] = [
            (.whenUnlocked, kSecAttrAccessibleWhenUnlocked),
            (.afterFirstUnlock, kSecAttrAccessibleAfterFirstUnlock),
            (.whenUnlockedThisDeviceOnly, kSecAttrAccessibleWhenUnlockedThisDeviceOnly),
            (.afterFirstUnlockThisDeviceOnly, kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly),
            (.always, kSecAttrAccessibleAfterFirstUnlock),
            (.alwaysThisDeviceOnly, kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly),
            (.whenPasscodeSetThisDeviceOnly, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly)
        ]

        for (accessibility, expected) in cases {
            let options = makeOptions(accessibility: accessibility)
            let (attributes, error) = options.attributes(key: "token", value: Data("v".utf8))

            #expect(error == nil)
            #expect(attributes[KeychainConstants.AttributeAccessible] as? String == expected as String)
            // Plain accessibility and access control are mutually exclusive.
            #expect(attributes[KeychainConstants.AttributeAccessControl] == nil)
        }
    }

    @Test("whenPasscodeSetThisDeviceOnly round-trips through rawValue / init / description")
    func passcodeSetAccessibilityRoundTrips() throws {
        let accessibility = KeychainAccessibility.whenPasscodeSetThisDeviceOnly

        #expect(accessibility.rawValue == kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly as String)
        #expect(KeychainAccessibility(rawValue: accessibility.rawValue) == accessibility)
        #expect(accessibility.description == "WhenPasscodeSetThisDeviceOnly")
    }

    @Test("The default accessibility (.afterFirstUnlock) is no longer silently dropped")
    func defaultAccessibilityIsWritten() throws {
        let options = makeOptions(accessibility: KeychainOptions().accessibility)
        let (attributes, error) = options.attributes(key: "token", value: Data("v".utf8))

        #expect(error == nil)
        #expect(attributes[KeychainConstants.AttributeAccessible] as? String == kSecAttrAccessibleAfterFirstUnlock as String)
    }

    // MARK: - Authentication policy → SecAccessControl

    @Test("An authentication policy produces a SecAccessControl, not a plain accessibility value")
    func authenticationPolicyProducesAccessControl() throws {
        let options = makeOptions(accessibility: .whenUnlockedThisDeviceOnly, authenticationPolicy: .biometryAny)
        let (attributes, error) = options.attributes(key: "token", value: Data("v".utf8))

        #expect(error == nil)
        // Access control replaces the plain accessibility attribute.
        #expect(attributes[KeychainConstants.AttributeAccessible] == nil)

        let accessControl = try #require(attributes[KeychainConstants.AttributeAccessControl])
        #expect(CFGetTypeID(accessControl as CFTypeRef) == SecAccessControlGetTypeID())
    }

    @Test("Combined authentication policy flags still produce a SecAccessControl")
    func combinedAuthenticationPolicyProducesAccessControl() throws {
        let policy: KeychainAuthenticationPolicy = [.biometryCurrentSet, .or, .devicePasscode]
        let options = makeOptions(accessibility: .whenUnlockedThisDeviceOnly, authenticationPolicy: policy)
        let (attributes, error) = options.attributes(key: "token", value: Data("v".utf8))

        #expect(error == nil)
        let accessControl = try #require(attributes[KeychainConstants.AttributeAccessControl])
        #expect(CFGetTypeID(accessControl as CFTypeRef) == SecAccessControlGetTypeID())
    }

    // MARK: - Synchronizable

    @Test("Without an authentication policy, synchronizable reflects the configured flag")
    func synchronizableReflectsFlagWithoutPolicy() throws {
        let syncable = makeOptions(accessibility: .afterFirstUnlock, synchronizable: true)
        let (syncAttributes, _) = syncable.attributes(key: "token", value: Data("v".utf8))
        #expect((syncAttributes[KeychainConstants.AttributeSynchronizable] as? Bool) == true)

        let nonSyncable = makeOptions(accessibility: .afterFirstUnlock, synchronizable: false)
        let (nonSyncAttributes, _) = nonSyncable.attributes(key: "token", value: Data("v".utf8))
        #expect((nonSyncAttributes[KeychainConstants.AttributeSynchronizable] as? Bool) == false)
    }

    @Test("An authentication policy forces the item non-synchronizable even if synchronizable was requested")
    func authenticationPolicyForcesNonSynchronizable() throws {
        let options = makeOptions(
            accessibility: .whenUnlockedThisDeviceOnly,
            authenticationPolicy: .biometryAny,
            synchronizable: true
        )
        let (attributes, error) = options.attributes(key: "token", value: Data("v".utf8))

        #expect(error == nil)
        #expect(attributes[KeychainConstants.AttributeAccessControl] != nil)
        // Access-control items cannot be synced; the requested `true` is overridden.
        #expect((attributes[KeychainConstants.AttributeSynchronizable] as? Bool) == false)
    }

    @Test("Device-local accessibility forces the item non-synchronizable even if synchronizable was requested")
    func deviceOnlyAccessibilityForcesNonSynchronizable() throws {
        // iCloud Keychain rejects synchronizing any ...ThisDeviceOnly protection class.
        let deviceOnly: [KeychainAccessibility] = [
            .whenUnlockedThisDeviceOnly,
            .afterFirstUnlockThisDeviceOnly,
            .alwaysThisDeviceOnly,
            .whenPasscodeSetThisDeviceOnly
        ]
        for accessibility in deviceOnly {
            let options = makeOptions(accessibility: accessibility, synchronizable: true)
            let (attributes, _) = options.attributes(key: "token", value: Data("v".utf8))
            #expect((attributes[KeychainConstants.AttributeSynchronizable] as? Bool) == false)
        }

        // A non-device-local class still honors the flag.
        let syncable = makeOptions(accessibility: .whenUnlocked, synchronizable: true)
        let (syncAttributes, _) = syncable.attributes(key: "token", value: Data("v".utf8))
        #expect((syncAttributes[KeychainConstants.AttributeSynchronizable] as? Bool) == true)
    }

    @Test("Strict query synchronizable matches what attributes() writes")
    func strictQuerySynchronizableMatchesWrite() throws {
        // (accessibility, authenticationPolicy, requested-synchronizable) -> expected stored synchronizable
        func assertConsistent(
            _ accessibility: KeychainAccessibility,
            policy: KeychainAuthenticationPolicy?,
            requested: Bool,
            expected: Bool
        ) {
            let options = makeOptions(accessibility: accessibility, authenticationPolicy: policy, synchronizable: requested)
            let (attributes, _) = options.attributes(key: "token", value: Data("v".utf8))
            let strictQuery = options.query(ignoringAttributeSynchronizable: false)

            #expect((attributes[KeychainConstants.AttributeSynchronizable] as? Bool) == expected)
            #expect((strictQuery[KeychainConstants.AttributeSynchronizable] as? Bool) == expected)
        }

        assertConsistent(.whenUnlocked, policy: nil, requested: true, expected: true)
        assertConsistent(.whenUnlocked, policy: nil, requested: false, expected: false)
        assertConsistent(.whenUnlockedThisDeviceOnly, policy: nil, requested: true, expected: false)
        assertConsistent(.whenUnlockedThisDeviceOnly, policy: .biometryAny, requested: true, expected: false)
    }

    // MARK: - Other attributes

    @Test("The value data is always written")
    func valueDataIsWritten() throws {
        let data = Data("secret".utf8)
        let options = makeOptions(accessibility: .afterFirstUnlock)
        let (attributes, _) = options.attributes(key: "token", value: data)

        #expect(attributes[KeychainConstants.ValueData] as? Data == data)
    }

    // MARK: - Error surfacing

    /// The access-control failure branch surfaces a `CFError` bridged through the
    /// `CFError.error` helper. The branch itself is unreachable with valid inputs
    /// (see `KeychainOptions`), so we verify the bridging helper that carries the
    /// error to the caller preserves the domain, code, and user info.
    @Test("CFError is bridged to an NSError preserving domain, code and user info")
    func cfErrorBridgesToNSError() throws {
        let userInfo = ["reason": "boom"] as CFDictionary
        let cfError = CFErrorCreate(nil, "com.gigigo.tests.keychain" as CFString, 42, userInfo)
        let nsError = try #require(cfError).error

        #expect(nsError.domain == "com.gigigo.tests.keychain")
        #expect(nsError.code == 42)
        #expect(nsError.userInfo["reason"] as? String == "boom")
    }
}
