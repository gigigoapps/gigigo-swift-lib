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
            (.alwaysThisDeviceOnly, kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly)
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

    // MARK: - Other attributes

    @Test("The value data is always written")
    func valueDataIsWritten() throws {
        let data = Data("secret".utf8)
        let options = makeOptions(accessibility: .afterFirstUnlock)
        let (attributes, _) = options.attributes(key: "token", value: data)

        #expect(attributes[KeychainConstants.ValueData] as? Data == data)
    }
}
