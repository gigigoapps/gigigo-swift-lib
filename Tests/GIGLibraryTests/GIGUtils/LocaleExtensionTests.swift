//
//  LocaleExtensionTests.swift
//  GIGLibrary
//
//  Created by Alejandro Jiménez Agudo.
//  Copyright © 2026 Gigigo SL. All rights reserved.
//

import Testing
import Foundation
@testable import GIGLibrary

@Suite("Locale+GIGExtension")
struct LocaleExtensionTests {

    // MARK: - languageCode(from:)

    @Test("Given a BCP-47 identifier, the language code is parsed without depending on the system locale",
          arguments: [
            ("en-US", "en"),
            ("es", "es"),
            ("zh-Hans-CN", "zh"),
            ("zh-Hant", "zh"),
            ("pt-BR", "pt")
          ])
    func languageCodeIsParsedFromIdentifier(identifier: String, expected: String) {
        #expect(Locale.languageCode(from: identifier) == expected)
    }

    // MARK: - regionCode(from:)

    @Test("Given a BCP-47 identifier, the region code comes from the region subtag, not the last component",
          arguments: [
            ("en-US", "US"),
            ("es", nil),
            ("zh-Hans-CN", "CN"),
            ("zh-Hant", nil),
            ("pt-BR", "BR")
          ])
    func regionCodeIsParsedFromIdentifier(identifier: String, expected: String?) {
        #expect(Locale.regionCode(from: identifier) == expected)
    }

    // MARK: - Current locale accessors (smoke)

    @Test("Given the current locale, currentLanguageCode returns a non-empty code")
    func currentLanguageCodeIsNotEmpty() {
        #expect(!Locale.currentLanguageCode().isEmpty)
    }

    @Test("Given the current locale, currentRegionCode returns a non-empty code")
    func currentRegionCodeIsNotEmpty() {
        #expect(!Locale.currentRegionCode().isEmpty)
    }

    @Test("Given the current locale, currentLanguageCode stays consistent with currentLanguage")
    func currentLanguageCodeMatchesPreferredLanguage() {
        // The language code must be derived from the preferred language tag, not the device region,
        // so an app forced to a language different from the region still reports that language.
        #expect(Locale.currentLanguageCode() == (Locale.languageCode(from: Locale.currentLanguage()) ?? "en"))
    }

    @Test("Given the current locale, currentLanguage returns a non-empty tag")
    func currentLanguageIsNotEmpty() {
        #expect(!Locale.currentLanguage().isEmpty)
    }
}
