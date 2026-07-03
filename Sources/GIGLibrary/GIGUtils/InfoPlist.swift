//
//  InfoPlist.swift
//  GIGLibrary
//
//  Created by Alejandro Jiménez Agudo on 26/7/16.
//  Copyright © 2016 Gigigo SL. All rights reserved.
//

import Foundation


/// Reads a `String` value from the main bundle's `Info.plist`.
///
/// - Returns: the value for `key`, or `nil` when the key is absent or not a
///   `String`. Callers can distinguish a genuine missing value from a real one
///   instead of receiving a sentinel string that could end up shown in the UI.
public func infoDictionary(_ key: String) -> String? {
	Bundle.main.infoDictionary?[key] as? String
}

/// Legacy accessor kept for source compatibility.
///
/// Returns the literal `"CONSTANT NOT FOUND"` when the key is missing, which
/// cannot be told apart from a real value — prefer `infoDictionary(_:)`, which
/// returns an optional.
@available(*, deprecated, renamed: "infoDictionary(_:)", message: "Use infoDictionary(_:) which returns String? so a missing key is representable.")
public func InfoDictionary(_ key: String) -> String {
	infoDictionary(key) ?? "CONSTANT NOT FOUND"
}
