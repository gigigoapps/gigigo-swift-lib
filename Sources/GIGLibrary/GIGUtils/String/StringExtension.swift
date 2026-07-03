//
//  StringExtension.swift
//  GIGLibrary
//
//  Created by Alejandro Jiménez Agudo on 23/11/16.
//  Copyright © 2016 Gigigo SL. All rights reserved.
//

import Foundation


public extension String {
	
    static func base64(_ string: String) -> String? {
		return string.data(using: .utf8).map { $0.base64EncodedString() }
	}
    
    /// Converts a base64url-safe encoded string (RFC 4648 §5) into the standard
    /// base64 alphabet, restoring `+`/`/` characters and the `=` padding.
    ///
    /// This does **not** decode the value: the result is still a base64 string,
    /// ready to be passed to `Data(base64Encoded:)`.
    ///
    /// Adapted from https://stackoverflow.com/a/43500088
    func base64URLSafeToStandard() -> String {
        var base64 = self.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        if !base64.count.isMultiple(of: 4) {
            base64.append(String(repeating: "=", count: 4 - base64.count % 4))
        }

        return base64
    }

    @available(*, deprecated, renamed: "base64URLSafeToStandard()")
    func base64URLSafeDecode() -> String {
        self.base64URLSafeToStandard()
    }
	
    func toBase64() -> String? {
		String.base64(self)
	}
    
    func swiftArgs() -> String {
        self.replacingOccurrences(of: "%s", with: "%@").replacingOccurrences(of: "$s", with: "$@")
    }
    
    func removeWebTrash() -> String {
        self.replacingOccurrences(of: "<p>", with: "").replacingOccurrences(of: "</p>", with: "")
    }
    
    func removeSpaces() -> String {
        // This is not a bug, they are different space characters
        self.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: " ", with: "")
    }
    
    func html() -> String {
        self.replacingOccurrences(of: "\n", with: "<br>")
    }
	
    func capitalizingFirstLetter() -> String {
        return prefix(1).capitalized + dropFirst()
    }
    
    mutating func capitalizeFirstLetter() {
        self = self.capitalizingFirstLetter()
    }
    
    /// JSON string representation to Dictionary
    func toDictionary() -> [String: AnyObject]? {
        guard let data = self.data(using: .utf8) else {
            return nil
        }
        return try? JSONSerialization.jsonObject(with: data, options: []) as? [String: AnyObject]
    }
    
}
