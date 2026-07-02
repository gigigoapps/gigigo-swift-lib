//
//  Json.swift
//  AlwaysOn
//
//  Created by Alejandro Jiménez Agudo on 22/2/16.
//  Copyright © 2016 Gigigo S.L. All rights reserved.
//

import Foundation


/// `@unchecked Sendable` is sound by design under one invariant: `json` is a `let` populated once in
/// `init(from:)` and never reassigned or mutated afterwards. Every other method is read-only — they
/// cast or serialize `json` without writing to it — so although a `JSON` can cross a concurrency
/// boundary (it is stored in `Response.data`), only immutable reads ever touch its state. The backing
/// store is `Any` (JSON parsed via `JSONSerialization`, i.e. Foundation value/immutable types), which
/// the compiler cannot prove `Sendable`; the `@unchecked` annotation asserts the immutability
/// invariant above in its place, consistent with `Request`/`Response`/`LogManager`.
public final class JSON: Sequence, CustomStringConvertible, @unchecked Sendable {

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
