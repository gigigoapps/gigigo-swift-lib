import Foundation
import Testing
@testable import GIGLibrary

@Suite("JSON serialization")
struct JSONSerializationTests {
    @Test("Given valid JSON, when serializing data and description, then both preserve the value",
          arguments: ["null", "true", "false", "42", "-1.25e3", "\"text\\n\\\"quoted\\\"\"", "[]", "{}", "[null,true,1,\"text\"]", "{\"data\":null}"])
    func validValuesRoundTrip(source: String) throws {
        let json = try JSON.dataToJson(Data(source.utf8))
        let data = try #require(json.toData())
        let expected = try JSONSerialization.jsonObject(with: Data(source.utf8), options: .fragmentsAllowed)
        for encoded in [data, Data(json.description.utf8)] {
            let actual = try JSONSerialization.jsonObject(with: encoded, options: .fragmentsAllowed)
            #expect((actual as AnyObject).isEqual(expected))
        }
    }

    @Test("Given deeply nested valid arrays, when serializing, then the writer retains its supported depth",
          arguments: [511, 512, 513])
    @MainActor
    func deepValuesRemainSerializable(depth: Int) throws {
        var value: Any = 0
        for _ in 0..<depth { value = [value] }
        let json = JSON(from: value)
        let expected = String(repeating: "[", count: depth) + "0" + String(repeating: "]", count: depth)
        #expect(json.toData() == Data(expected.utf8))
        let description = json.description
        #expect(description.filter { !$0.isWhitespace } == expected)
    }

    @Test("Given unsupported or non-finite values, when serializing, then data is nil and description uses its fallback")
    func invalidValuesFailSafely() {
        let invalid: [Any] = [Date(timeIntervalSince1970: 0), NSObject(), Double.nan, Double.infinity,
                              -Double.infinity, ["nested": Date()], [Double.nan], [1: "non-string key"]]
        for value in invalid {
            let json = JSON(from: value)
            #expect(json.toData() == nil)
            #expect(json.description == String(describing: value))
        }
    }

    @Test("Given mutable JSON, when its contents become invalid after initialization, then serialization rejects the current value")
    func mutableValuesAreValidatedAtUse() throws {
        let dictionary = NSMutableDictionary(dictionary: ["value": "valid"])
        let json = JSON(from: dictionary)
        #expect(json.toData() != nil)
        dictionary["value"] = Date()
        #expect(json.toData() == nil)
        #expect(json.description == String(describing: dictionary))
    }

    @Test("Given a scalar response body, when formatting a verbose log, then valid JSON is logged",
          arguments: ["null", "true", "42", "\"text\""])
    func scalarResponseLogging(source: String) {
        let log = ResponseLogFormatter.buildResponseLog(url: nil, statusCode: 200, headers: nil, body: Data(source.utf8))
        #expect(log.contains(" - JSON:\n" + source + "\n"))
    }
}
