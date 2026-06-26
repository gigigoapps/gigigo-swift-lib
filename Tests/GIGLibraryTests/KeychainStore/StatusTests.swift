//
//  StatusTests.swift
//  GIGLibrary
//
//  Pure unit tests over `Status(status:)`, the OSStatus → Status mapping that
//  every KeychainStore method funnels its `SecItem*` return codes through. A
//  regression here (a mistyped raw value, or a known code no longer mapping to
//  its case) would silently change how the store reports success and failure.
//  These tests need no live keychain, so they always run — including in CI.
//

import Testing
import Foundation
import Security
@testable import GIGLibrary

@Suite("Status OSStatus mapping")
struct StatusTests {

    // MARK: - Known codes map to their case

    @Test("Each well-known OSStatus maps to its matching Status case")
    func knownStatusesMap() {
        // The raw values are pinned to Apple's `errSec*` constants. If any case's
        // raw value drifts, `Status(status:)` would fall through to `.unexpectedError`
        // and these equalities break.
        #expect(Status(status: errSecSuccess) == .success)
        #expect(Status(status: errSecItemNotFound) == .itemNotFound)
        #expect(Status(status: errSecDuplicateItem) == .duplicateItem)
        #expect(Status(status: errSecAuthFailed) == .authFailed)
        #expect(Status(status: errSecInteractionNotAllowed) == .interactionNotAllowed)
        #expect(Status(status: errSecUserCanceled) == .userCanceled)
        #expect(Status(status: errSecParam) == .param)
        #expect(Status(status: errSecMissingEntitlement) == .missingEntitlement)
    }

    @Test("errSecItemNotFound — the code KeychainStore treats as 'absent, not an error' — maps to .itemNotFound")
    func itemNotFoundMaps() {
        // This is the exact code `getData`/`contains` switch on to return nil/false
        // instead of throwing. Pin it explicitly.
        #expect(errSecItemNotFound == -25300)
        #expect(Status(status: errSecItemNotFound) == .itemNotFound)
        #expect(Status.itemNotFound.rawValue == errSecItemNotFound)
    }

    // MARK: - Unknown codes fall back to .unexpectedError

    @Test("An unmapped OSStatus falls back to .unexpectedError")
    func unknownStatusFallsBack() {
        // 1 is not a valid errSec code (success is 0; the enum has no positive cases).
        #expect(Status(status: 1) == .unexpectedError)
        #expect(Status(status: 123_456) == .unexpectedError)
        #expect(Status(status: OSStatus.max) == .unexpectedError)
    }

    @Test("The .unexpectedError sentinel itself round-trips through Status(status:)")
    func unexpectedErrorRoundTrips() {
        #expect(Status(status: Status.unexpectedError.rawValue) == .unexpectedError)
    }

    // MARK: - rawValue / init consistency

    @Test("Status(status:) agrees with Status(rawValue:) for mapped codes")
    func statusInitAgreesWithRawValueInit() {
        let codes: [OSStatus] = [
            errSecSuccess, errSecItemNotFound, errSecDuplicateItem,
            errSecAuthFailed, errSecInteractionNotAllowed, errSecMissingEntitlement
        ]
        for code in codes {
            #expect(Status(status: code) == Status(rawValue: code))
            // And the mapped case carries the same raw value back.
            #expect(Status(status: code).rawValue == code)
        }
    }

    // MARK: - Status is a usable Error

    @Test("Status conforms to Error and exposes a non-empty description")
    func statusIsAnErrorWithDescription() {
        let error: Error = Status(status: errSecItemNotFound)
        #expect(error is Status)
        #expect((error as? Status) == .itemNotFound)
        #expect(!Status.itemNotFound.description.isEmpty)
        #expect(!Status.missingEntitlement.description.isEmpty)
    }
}
