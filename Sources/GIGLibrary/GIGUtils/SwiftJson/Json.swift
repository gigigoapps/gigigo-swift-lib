//
//  Json.swift
//  AlwaysOn
//
//  Created by Alejandro Jiménez Agudo on 22/2/16.
//  Copyright © 2016 Gigigo S.L. All rights reserved.
//

import Foundation


/// `JSON` is intentionally **not** `Sendable`. `json` is a `let`, so the reference is never
/// reassigned, but `init(from:)` is public and stores the value verbatim: a caller can wrap a
/// mutable reference type (e.g. `NSMutableDictionary`/`NSMutableArray`) and mutate it externally
/// while `subscript`/`toData()` read it. Claiming `@unchecked Sendable` would only suppress that
/// data-race warning without making the payload safe, so we don't. `Response` does store a `JSON`
/// in its `data` and is itself `@unchecked Sendable`, but that is sound because of `Response`'s own
/// write-once invariant — it builds the `JSON` during `init` and never shares or mutates it
/// afterwards (see `Response.swift`) — not because `JSON` is thread-safe on its own.
public final class JSON: Sequence, CustomStringConvertible {

	private let json: Any
	
	public var description: String {
		if let data = try? JSONSerialization.data(withJSONObject: self.json, options: .prettyPrinted) as Data {
			if let description = String(data: data, encoding: String.Encoding.utf8) {
				return description
			}
				return String(describing: self.json)
		}
			return String(describing: self.json)
	}
	
	
	// MARK: - Initializers
	
	public init(from any: Any) {
		self.json = any
	}
	
	public subscript(path: String) -> JSON? {
		var current: Any = self.json
		let pathArray = path.components(separatedBy: ".")

		for key in pathArray {
			// Traverse from the *current* node: if an intermediate key resolves to a
			// non-dictionary while path components remain, the cast fails and we return
			// `nil` instead of silently querying the previous level's dictionary.
			guard let dict = current as? [String: Any], let next = dict[key] else {
				return nil
			}
			current = next
		}

		return JSON(from: current)
	}
    
    public subscript(index: Int) -> JSON? {
        guard let array = self.json as? [Any], array.count > index else { return nil }
        
        return JSON(from: array[index])
    }
	
	public static func dataToJson(_ data: Data) throws -> JSON {
		let jsonObject = try JSONSerialization.jsonObject(with: data, options: .allowFragments)
		
		return JSON(from: jsonObject)
	}
	
	
	// MARK: - Public methods
	
	public func toData() -> Data? {
		do {
			return try JSONSerialization.data(withJSONObject: self.json)
		} catch let error as NSError {
			LogError(error)
			return nil
		}
	}
	
	public func toBool() -> Bool? {
		return self.json as? Bool
	}
		
	public func toInt() -> Int? {
		if let value = self.json as? Int {
			return value
		}
		if let value = self.toString() {
			return Int(value)
		}
		
		return nil
	}
		
	public func toString() -> String? {
		return self.json as? String
	}
	
	public func toDate(_ format: String = DateISOFormat) -> Date? {
		guard let dateString = self.json as? String else {
			return nil
		}
		
		return Date.dateFromString(dateString, format: format)
	}
    
    public func toDouble() -> Double? {
        return self.json as? Double
    }
    
    public func toDictionary() -> [String: Any]? {
        
        guard let dic = self.json as? [String: Any] else {
            return [:]
        }
        
        return dic
    }
    
    public func toArray() -> [Any]? {
        guard let array = self.json as? [Any] else {
            return []
        }
        
        return array
    }
	
	// MARK: - Sequence Methods
	
	public func makeIterator() -> AnyIterator<JSON> {
		var index = 0
		
		return AnyIterator { () -> JSON? in
			guard let array = self.json as? [Any] else { return nil }
			guard array.count > index else { return nil }
			
			let item = array[index]
			let json = JSON(from: item)
			index += 1
			
			return json
		}
	}
}
