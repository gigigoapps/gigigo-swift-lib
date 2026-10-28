//
//  JSONSubscriptTests.swift
//  GIGLibraryTests
//
//  Covers the dot-notation path subscript of `JSON` (C016).
//

import Testing
@testable import GIGLibrary

@Suite("JSON dot-notation subscript")
struct JSONSubscriptTests {

	private let json = JSON(from: [
		"level1": [
			"level2": [
				"leaf": "value"
			],
			"scalar": "iAmAString"
		]
	] as [String: Any])

	@Test("Given a valid nested path, the leaf value is resolved")
	func nestedPathResolvesLeaf() throws {
		let leaf = try #require(json["level1.level2.leaf"])
		#expect(leaf.toString() == "value")
	}

	@Test("Given a single existing key, the intermediate node is resolved")
	func singleKeyResolvesNode() throws {
		let node = try #require(json["level1"])
		#expect(node.toDictionary()?["scalar"] as? String == "iAmAString")
	}

	@Test("Given an intermediate key that resolves to a scalar with path remaining, returns nil")
	func scalarIntermediateWithRemainingPathReturnsNil() {
		// `level1.scalar` is a String; asking for `.deeper` beyond it must not silently
		// fall back to a previous level's dictionary — it must fail.
		#expect(json["level1.scalar.deeper"] == nil)
	}

	@Test("Given a non-existent key, returns nil")
	func missingKeyReturnsNil() {
		#expect(json["level1.nope"] == nil)
	}

	@Test("Given an empty path, returns nil (the empty key does not exist)")
	func emptyPathReturnsNil() {
		// `"".components(separatedBy: ".")` yields `[""]`, so the traversal looks up the
		// empty-string key, which is absent — pinning the current behavior.
		#expect(json[""] == nil)
	}

	@Test("Given a path applied to a non-dictionary root, returns nil")
	func nonDictionaryRootReturnsNil() {
		let arrayJSON = JSON(from: [1, 2, 3] as [Any])
		#expect(arrayJSON["anything"] == nil)
	}
}

@Suite("JSON integer subscript")
struct JSONIntegerSubscriptTests {
    @Test("Given an invalid index, when accessing an array, then returns nil",
          arguments: [Int.min, -1, 0, 1, 2, Int.max])
    func invalidIndicesReturnNil(index: Int) {
        let empty = JSON(from: [Int]())
        #expect(empty[index] == nil)
        if index < 0 || index >= 2 {
            #expect(JSON(from: [10, 20])[index] == nil)
        }
    }

    @Test("Given a valid index, when accessing an array, then returns its value",
          arguments: [0, 1])
    func validIndicesReturnValues(index: Int) {
        #expect(JSON(from: [10, 20])[index]?.toInt() == [10, 20][index])
    }

    @Test("Given a non-array root, when accessing an index, then returns nil",
          arguments: [Int.min, -1, 0, Int.max])
    func nonArrayRootReturnsNil(index: Int) {
        #expect(JSON(from: ["key": "value"])[index] == nil)
        #expect(JSON(from: "value")[index] == nil)
    }
}
