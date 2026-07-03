//
//  StringExtensionTests.swift
//  GIGLibrary
//
//  Coverage for String helpers in GIGUtils/String (C076).
//

import Testing
import Foundation
import GIGLibrary

@Suite("StringExtension")
struct StringExtensionTests {

    // MARK: - base64URLSafeToStandard

    @Test("Given a URL-safe base64 token, when converted to standard, then it decodes back to the original bytes")
    func base64URLSafeRoundTrip() throws {
        let original = "Hola, 世界! <<???>>~~"
        let standard = Data(original.utf8).base64EncodedString()

        // Build a URL-safe token: swap the alphabet and drop the padding.
        let urlSafe = standard
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        let restored = urlSafe.base64URLSafeToStandard()

        let decodedData = try #require(Data(base64Encoded: restored))
        let decoded = String(data: decodedData, encoding: .utf8)
        #expect(decoded == original)
    }

    @Test("Given a length 2 mod 4 (no padding), when converting, then two '=' are appended")
    func base64PaddingTwoMissing() {
        #expect("ab".base64URLSafeToStandard() == "ab==")
    }

    @Test("Given a length 3 mod 4 (no padding), when converting, then one '=' is appended")
    func base64PaddingOneMissing() {
        #expect("abc".base64URLSafeToStandard() == "abc=")
    }

    @Test("Given a length 0 mod 4, when converting, then no padding is added")
    func base64PaddingNoneMissing() {
        #expect("abcd".base64URLSafeToStandard() == "abcd")
    }

    @Test("Given URL-safe alphabet characters, when converting, then '-' and '_' map to '+' and '/'")
    func base64AlphabetMapping() {
        // "ab-_" → length 4, no padding; only the alphabet swap applies.
        #expect("ab-_".base64URLSafeToStandard() == "ab+/")
    }

    // MARK: - toBase64 / base64

    @Test("Given a string, when base64-encoded, then it round-trips back to the original")
    func toBase64RoundTrip() throws {
        let original = "hello world"
        let encoded = try #require(original.toBase64())
        #expect(encoded == Data(original.utf8).base64EncodedString())

        let decodedData = try #require(Data(base64Encoded: encoded))
        #expect(String(data: decodedData, encoding: .utf8) == original)
    }

    @Test("Given the static base64 factory, when encoding, then it matches Foundation's encoding")
    func staticBase64MatchesFoundation() throws {
        let encoded = try #require(String.base64("GIGLibrary"))
        #expect(encoded == Data("GIGLibrary".utf8).base64EncodedString())
    }

    // MARK: - swiftArgs

    @Test("Given C-style %s/$s placeholders, when mapped, then they become %@/$@")
    func swiftArgsMapsPlaceholders() {
        #expect("Hello %s, you have $s".swiftArgs() == "Hello %@, you have $@")
    }

    @Test("Given a positional %1$s placeholder, when mapped, then the trailing $s becomes $@")
    func swiftArgsMapsPositionalPlaceholder() {
        #expect("%1$s and %2$s".swiftArgs() == "%1$@ and %2$@")
    }

    @Test("Given no placeholders, when mapped, then the string is unchanged")
    func swiftArgsLeavesPlainTextUntouched() {
        #expect("plain text".swiftArgs() == "plain text")
    }

    // MARK: - removeWebTrash

    @Test("Given paragraph tags, when removed, then only the inner text remains")
    func removeWebTrashStripsParagraphTags() {
        #expect("<p>hello</p><p>world</p>".removeWebTrash() == "helloworld")
    }

    // MARK: - removeSpaces

    @Test("Given regular and non-breaking spaces, when removed, then no space characters remain")
    func removeSpacesStripsBothSpaceKinds() {
        let input = "a b\u{00A0}c"
        #expect(input.removeSpaces() == "abc")
    }

    // MARK: - capitalizingFirstLetter

    @Test("Given an empty string, when capitalizing the first letter, then it stays empty")
    func capitalizingFirstLetterEmpty() {
        #expect("".capitalizingFirstLetter().isEmpty)
    }

    @Test("Given a lowercase word, when capitalizing the first letter, then only the first is uppercased")
    func capitalizingFirstLetterBasic() {
        #expect("hola mundo".capitalizingFirstLetter() == "Hola mundo")
    }

    @Test("Given an accented first letter, when capitalizing, then the diacritic is preserved")
    func capitalizingFirstLetterAccented() {
        #expect("élan".capitalizingFirstLetter() == "Élan")
    }

    @Test("Given a leading multibyte grapheme, when capitalizing, then it is left intact without crashing")
    func capitalizingFirstLetterMultibyte() {
        #expect("🎉abc".capitalizingFirstLetter() == "🎉abc")
    }

    @Test("Given a mutable string, when capitalizeFirstLetter mutates it, then the first letter is uppercased")
    func capitalizeFirstLetterMutates() {
        var value = "swift"
        value.capitalizeFirstLetter()
        #expect(value == "Swift")
    }

    // MARK: - toDictionary

    @Test("Given a valid JSON object, when parsed, then a dictionary is returned")
    func toDictionaryValidObject() throws {
        let dictionary = try #require("{\"name\":\"GIG\",\"count\":3}".toDictionary())
        #expect(dictionary["name"] as? String == "GIG")
        #expect(dictionary["count"] as? Int == 3)
    }

    @Test("Given a JSON array, when parsed as a dictionary, then nil is returned without crashing")
    func toDictionaryArrayReturnsNil() {
        #expect("[1, 2, 3]".toDictionary() == nil)
    }

    @Test("Given a non-JSON string, when parsed, then nil is returned without crashing")
    func toDictionaryInvalidReturnsNil() {
        #expect("not json at all".toDictionary() == nil)
    }
}
