//
//  StyledStringFontResolutionTests.swift
//  GIGLibrary
//
//  Regression coverage for the single-pass font resolution (C069): combining
//  bold/italic with size/fontName must not drop traits regardless of order.
//

import Testing
import UIKit
import GIGLibrary

@Suite("StyledString font resolution")
@MainActor
struct StyledStringFontResolutionTests {

    private func font(for styled: StyledString, text: String) -> UIFont? {
        let label = UILabel(frame: .zero)
        label.styledString(styled)
        return label.attributedText?
            .attribute(named: NSAttributedString.Key.font.rawValue, forText: text) as? UIFont
    }

    @Test("Given .bold before .size, when styled, then bold is kept and the size is applied")
    func boldThenSizeKeepsBothTraits() throws {
        let resolved = try #require(font(for: "texto".style(.bold, .size(50)), text: "texto"))
        #expect(resolved.fontDescriptor.symbolicTraits.contains(.traitBold))
        #expect(resolved.pointSize == 50)
    }

    @Test("Given .size before .bold, when styled, then bold is kept and the size is applied")
    func sizeThenBoldKeepsBothTraits() throws {
        let resolved = try #require(font(for: "texto".style(.size(50), .bold), text: "texto"))
        #expect(resolved.fontDescriptor.symbolicTraits.contains(.traitBold))
        #expect(resolved.pointSize == 50)
    }

    @Test("Given .italic combined with .size, when styled, then italic is preserved at the new size")
    func italicWithSizeKeepsItalic() throws {
        let resolved = try #require(font(for: "texto".style(.italic, .size(30)), text: "texto"))
        #expect(resolved.fontDescriptor.symbolicTraits.contains(.traitItalic))
        #expect(resolved.pointSize == 30)
    }

    @Test("Given .fontName combined with .size, when styled, then the named font is used at the new size")
    func fontNameWithSizeUsesNamedFontAtSize() throws {
        let resolved = try #require(font(for: "texto".style(.fontName("ArialMT"), .size(40)), text: "texto"))
        #expect(resolved.fontName == "ArialMT")
        #expect(resolved.pointSize == 40)
    }

    @Test("Given .bold and .italic together, when styled, then both symbolic traits are present")
    func boldAndItalicAccumulateTraits() throws {
        let resolved = try #require(font(for: "texto".style(.bold, .italic), text: "texto"))
        #expect(resolved.fontDescriptor.symbolicTraits.contains(.traitBold))
        #expect(resolved.fontDescriptor.symbolicTraits.contains(.traitItalic))
    }

    @Test("Given .size then a later .font, when styled, then the explicit font's own size wins (source order)")
    func explicitFontAfterSizeUsesItsOwnSize() throws {
        let custom = try #require(UIFont(name: "ChalkboardSE-Light", size: 25))
        let resolved = try #require(font(for: "texto".style(.size(12), .font(custom)), text: "texto"))
        #expect(resolved.fontName == custom.fontName)
        #expect(resolved.pointSize == 25)
    }

    @Test("Given .font then a later .fontName, when styled, then the later named font wins (source order)")
    func fontNameAfterExplicitFontWins() throws {
        let custom = try #require(UIFont(name: "ChalkboardSE-Light", size: 25))
        let resolved = try #require(font(for: "texto".style(.font(custom), .fontName("ArialMT")), text: "texto"))
        #expect(resolved.fontName == "ArialMT")
    }
}
