//
//  KeychainStoreTests.swift
//  GIGLibrary
//
//  Behavioural round-trip tests for the public KeychainStore CRUD and
//  enumeration surface (get/set/remove/removeAll/contains/allKeys/allItems and
//  the non-throwing subscripts). These exercise the real `SecItem*` calls, so —
//  exactly like `KeychainStoreAccessibilityTests` — they are guarded by
//  `KeychainTestEnvironment.isAvailable` and SKIP (not fail) on a bare SwiftPM
//  test bundle that has no keychain entitlement (the CI case). They run wherever
//  the keychain is reachable for the test process (e.g. inside a host app). The
//  always-on, keychain-free coverage lives in `StatusTests` and
//  `KeychainOptionsTests`.
//
//  `KeychainTestEnvironment` is defined in `KeychainStoreAccessibilityTests.swift`
//  and shared across the suite to avoid duplicating the probe.
//

import Testing
import Foundation
import Security
@testable import GIGLibrary

@Suite(.serialized, .enabled(if: KeychainTestEnvironment.isAvailable))
struct KeychainStoreTests {

    /// A store on a service unique to each test, so concurrent or repeated runs
    /// never see each other's items and `removeAll()` only affects this test.
    private func makeStore() -> KeychainStore {
        KeychainStore(service: "com.gigigo.tests.keychainstore.\(UUID().uuidString)")
    }

    // MARK: - set / get round-trip

    @Test("Given a stored string, when read back, then it round-trips")
    func stringRoundTrips() throws {
        let store = makeStore()
        defer { try? store.removeAll() }

        try store.set("session-token", key: "token")

        #expect(try store.get("token") == "session-token")
        #expect(try store.getString("token") == "session-token")
    }

    @Test("Given stored data, when read back, then the bytes round-trip")
    func dataRoundTrips() throws {
        let store = makeStore()
        defer { try? store.removeAll() }
        let payload = Data([0x00, 0x01, 0x02, 0xFF, 0xFE])

        try store.set(payload, key: "blob")

        #expect(try store.getData("blob") == payload)
    }

    // MARK: - Overwrite (update path)

    @Test("Given an existing key, when set again, then the value is overwritten and no duplicate is created")
    func settingTwiceOverwrites() throws {
        let store = makeStore()
        defer { try? store.removeAll() }

        try store.set("first", key: "token")
        try store.set("second", key: "token")   // takes the errSecSuccess → update branch

        #expect(try store.get("token") == "second")
        // An update, not a second add: the service holds exactly one key.
        #expect(store.allKeys() == ["token"])
    }

    // MARK: - Missing keys return nil (never throw)

    @Test("Given a key that was never stored, when get is called, then it returns nil without throwing")
    func getMissingReturnsNil() throws {
        let store = makeStore()
        defer { try? store.removeAll() }

        #expect(try store.get("does-not-exist") == nil)
        #expect(try store.getData("does-not-exist") == nil)
    }

    // MARK: - Deletion

    @Test("Given a stored key, when removed, then it is gone")
    func removeDeletesKey() throws {
        let store = makeStore()
        defer { try? store.removeAll() }

        try store.set("value", key: "token")
        #expect(try store.contains("token"))

        try store.remove("token")

        #expect(try store.get("token") == nil)
        #expect(try store.contains("token") == false)
    }

    @Test("Given a key that does not exist, when removed, then it does not throw")
    func removeMissingDoesNotThrow() throws {
        let store = makeStore()
        defer { try? store.removeAll() }

        // errSecItemNotFound must be treated as a no-op, not an error.
        try store.remove("never-stored")
        #expect(try store.contains("never-stored") == false)
    }

    @Test("Given several stored keys, when removeAll is called, then every key for the service is cleared")
    func removeAllClearsService() throws {
        let store = makeStore()
        defer { try? store.removeAll() }

        try store.set("a", key: "k1")
        try store.set("b", key: "k2")
        try store.set("c", key: "k3")
        #expect(store.allKeys().count == 3)

        try store.removeAll()

        #expect(store.allKeys().isEmpty)
        #expect(try store.contains("k1") == false)
        #expect(try store.contains("k2") == false)
    }

    // MARK: - Contains

    @Test("Given a stored key and an absent one, then contains reports true and false respectively")
    func containsReflectsPresence() throws {
        let store = makeStore()
        defer { try? store.removeAll() }

        try store.set("value", key: "present")

        #expect(try store.contains("present"))
        #expect(try store.contains("absent") == false)
    }

    // MARK: - Enumeration filtered by service

    @Test("Given keys in two services, when allKeys is read, then only the receiver's service keys are returned")
    func allKeysIsScopedToService() throws {
        let store = makeStore()
        let otherStore = makeStore()
        defer {
            try? store.removeAll()
            try? otherStore.removeAll()
        }

        try store.set("a", key: "alpha")
        try store.set("b", key: "beta")
        try otherStore.set("c", key: "gamma")

        #expect(Set(store.allKeys()) == ["alpha", "beta"])
        #expect(store.allKeys().contains("gamma") == false)
        #expect(otherStore.allKeys() == ["gamma"])
    }

    @Test("Given a stored key, when allItems is read, then it surfaces the value scoped to this service")
    func allItemsExposesValueForService() throws {
        let store = makeStore()
        defer { try? store.removeAll() }
        try? store.removeAll()   // defensive: guarantee the `count == 1` assertion sees only our item

        try store.set("payload", key: "token")

        // The instance enumeration is scoped to this service: only the single item
        // we just stored shows up.
        let items = store.allItems()
        #expect(items.count == 1)
        let item = try #require(items.first)
        #expect(item["key"] as? String == "token")
        #expect(item["value"] as? String == "payload")
        #expect(item["service"] as? String == store.service)
    }

    // MARK: - Subscript: never throws, swallows errors

    @Test("Given a missing key, when read through the subscript, then it returns nil instead of throwing")
    func subscriptMissingReturnsNil() throws {
        let store = makeStore()
        defer { try? store.removeAll() }

        #expect(store["never-stored"] == nil)
        #expect(store[data: "never-stored"] == nil)
    }

    @Test("Given the string subscript, when set and read, then it round-trips and agrees with the throwing API")
    func stringSubscriptRoundTrips() throws {
        let store = makeStore()
        defer { try? store.removeAll() }

        store["token"] = "value"

        #expect(store["token"] == "value")
        #expect(try store.get("token") == "value")
    }

    @Test("Given a key set via the subscript, when assigned nil, then the key is removed")
    func subscriptNilRemovesKey() throws {
        let store = makeStore()
        defer { try? store.removeAll() }

        store["token"] = "value"
        #expect(try store.contains("token"))

        store["token"] = nil

        #expect(try store.get("token") == nil)
        #expect(try store.contains("token") == false)
    }

    @Test("Given the data subscript, when set and read, then the bytes round-trip")
    func dataSubscriptRoundTrips() throws {
        let store = makeStore()
        defer { try? store.removeAll() }
        let payload = Data([0xDE, 0xAD, 0xBE, 0xEF])

        store[data: "blob"] = payload

        #expect(store[data: "blob"] == payload)
    }

    @Test("Given the labeled string subscript, when set and read, then it round-trips and agrees with the default subscript")
    func labeledStringSubscriptRoundTrips() throws {
        let store = makeStore()
        defer { try? store.removeAll() }

        store[string: "token"] = "value"

        #expect(store[string: "token"] == "value")
        #expect(store["token"] == "value")          // the labeled subscript delegates to the default one
        #expect(try store.get("token") == "value")
    }

    @Test("Given a stored key, when read through the attributes subscript, then it exposes the value, account and service")
    func attributesSubscriptExposesItem() throws {
        let store = makeStore()
        defer { try? store.removeAll() }
        let payload = Data("secret".utf8)
        try store.set(payload, key: "token")

        let attributes = try #require(store[attributes: "token"])
        #expect(attributes.data == payload)
        #expect(attributes.account == "token")
        #expect(attributes.service == store.service)

        // A missing key yields nil rather than throwing.
        #expect(store[attributes: "missing"] == nil)
    }

    @Test("Given a value the throwing getter rejects, when read through the subscript, then the error is swallowed and nil is returned")
    func subscriptSwallowsGenuineError() throws {
        let store = makeStore()
        defer { try? store.removeAll() }
        // Bytes that are not valid UTF-8: getString cannot decode them.
        let nonUTF8 = Data([0xFF, 0xFE, 0xFF])
        try store.set(nonUTF8, key: "binary")

        // The throwing API surfaces the failure as a Status error (the precise case
        // is an implementation detail; the contract under test is that the subscript
        // swallows it).
        #expect(throws: Status.self) {
            _ = try store.get("binary")
        }
        // ...but the string subscript swallows it and yields nil rather than crashing.
        #expect(store["binary"] == nil)
        // The data subscript still returns the raw bytes (no decoding involved).
        #expect(store[data: "binary"] == nonUTF8)
    }
}
