//
//  Selfie.swift
//  GIGLibrary
//
//  Created by Alejandro Jiménez Agudo on 28/6/16.
//  Copyright © 2016 Gigigo SL. All rights reserved.
//

import Foundation


public protocol Selfie: CustomStringConvertible {

	/// Property labels that `description` may print verbatim. Any child not in
	/// this set is emitted as `<redacted>` so reflection never dumps sensitive
	/// fields (auth headers, tokens, request/response bodies) into logs.
	///
	/// Returning `nil` (the default) exposes every property — the original,
	/// unfiltered behaviour. Only leave the default on types with no sensitive
	/// data; types that carry secrets (e.g. `Request`, `Response`) MUST override
	/// it with the whitelist of safe-to-log labels.
	var selfieExposedKeys: Set<String>? { get }
}

public extension Selfie {

	var selfieExposedKeys: Set<String>? { nil }

	var description: String {
		let mirror = Mirror(reflecting: self)
		let exposed = self.selfieExposedKeys
		let fields = mirror.children.map { child -> String in
			let label = child.label ?? "?"
			let value: String
			if let exposed, !exposed.contains(label) {
				value = "<redacted>"
			} else {
				value = "\(child.value)"
			}
			return "\(label): \(value) "
		}
		let body = fields.joined(separator: ", ")
		return "\(mirror.subjectType)( \(body))"
	}
}
