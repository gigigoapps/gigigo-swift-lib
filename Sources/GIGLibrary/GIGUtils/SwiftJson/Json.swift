//
//  Json.swift
//  AlwaysOn
//
//  Created by Alejandro Jiménez Agudo on 22/2/16.
//  Copyright © 2016 Gigigo S.L. All rights reserved.
//

import Foundation


public final class JSON: Sequence, CustomStringConvertible {
	
	private var json: Any
	
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
		guard var jsonDict = self.json as? [String: Any] else {
			return nil
		}
		
		var json = self.json
		let pathArray = path.components(separatedBy: ".")
		
		for key in pathArray {
			
			if let jsonObject = jsonDict[key] {
				json = jsonObject
				
				if let jsonDictNext = jsonObject as? [String: Any] {
					jsonDict = jsonDictNext
				}
			} else {
				return nil
			}
		}
		
		return JSON(from: json)
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
