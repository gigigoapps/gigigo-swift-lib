//
//  Locale+GIGExtension.swift
//  GIGLibrary
//
//  Created by Alejandro Jiménez Agudo on 24/2/16.
//  Copyright © 2016 Gigigo SL. All rights reserved.
//

import Foundation


public extension Locale {

	/// Returns the preferred language tag (BCP-47). Example on a US device: `en-US` (iOS often returns just `en`).
	static func currentLanguage() -> String {
		return self.preferredLanguages.first ?? "en"
	}

	/// Returns only the language code of the current locale. Example: `es`
	static func currentLanguageCode() -> String {
		return Locale.current.language.languageCode?.identifier ?? "en"
	}

	/// Returns only the region code of the current locale. Example: `US`
	///
	/// The region is read from `Locale.current.region`, which is independent of the
	/// preferred-languages order, so it is not affected by language tags without a region.
	static func currentRegionCode() -> String {
		return Locale.current.region?.identifier ?? "US"
	}

}

// MARK: - Pure, testable parsers

extension Locale {

	/// Extracts the language code from a BCP-47 identifier, using the typed locale API instead of string-splitting.
	///
	/// - `"en-US"` -> `"en"`, `"zh-Hant"` -> `"zh"`, `"pt-BR"` -> `"pt"`
	static func languageCode(from identifier: String) -> String? {
		return Locale.Language(identifier: identifier).languageCode?.identifier
	}

	/// Extracts the region code from a BCP-47 identifier, using the typed locale API instead of string-splitting.
	///
	/// Returns `nil` when the identifier carries no region (e.g. `"es"` or `"zh-Hant"`, where `Hant` is a script).
	/// - `"en-US"` -> `"US"`, `"zh-Hans-CN"` -> `"CN"`, `"zh-Hant"` -> `nil`
	static func regionCode(from identifier: String) -> String? {
		return Locale(identifier: identifier).region?.identifier
	}

}
