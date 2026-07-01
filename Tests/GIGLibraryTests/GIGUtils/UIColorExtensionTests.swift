//
//  UIColorExtensionTests.swift
//  GIGLibrary
//
//  Created by Alejandro Jiménez Agudo.
//  Copyright © 2026 Gigigo SL. All rights reserved.
//

import Testing
import UIKit
@testable import GIGLibrary

@Suite("UIColor+Extension")
struct UIColorExtensionTests {

    private let tolerance: CGFloat = 0.001

    private func components(of color: UIColor) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b, a)
    }

    // MARK: - Valid formats

    @Test("Given a 6-digit hex with '#', the RGB components match and alpha is 1")
    func sixDigitWithHash() throws {
        let color = try #require(UIColor(hex: "#FF0000"))
        let c = components(of: color)
        #expect(abs(c.r - 1.0) < tolerance)
        #expect(abs(c.g - 0.0) < tolerance)
        #expect(abs(c.b - 0.0) < tolerance)
        #expect(abs(c.a - 1.0) < tolerance)
    }

    @Test("Given a 6-digit hex without '#', the color is still parsed")
    func sixDigitWithoutHash() throws {
        let color = try #require(UIColor(hex: "00FF00"))
        let c = components(of: color)
        #expect(abs(c.r - 0.0) < tolerance)
        #expect(abs(c.g - 1.0) < tolerance)
        #expect(abs(c.b - 0.0) < tolerance)
        #expect(abs(c.a - 1.0) < tolerance)
    }

    @Test("Given a 3-digit shorthand, each nibble is duplicated (#F00 == #FF0000)")
    func threeDigitShorthand() throws {
        let color = try #require(UIColor(hex: "#F00"))
        let c = components(of: color)
        #expect(abs(c.r - 1.0) < tolerance)
        #expect(abs(c.g - 0.0) < tolerance)
        #expect(abs(c.b - 0.0) < tolerance)
        #expect(abs(c.a - 1.0) < tolerance)
    }

    @Test("Given an 8-digit hex, the last pair is parsed as the alpha channel")
    func eightDigitWithAlpha() throws {
        let color = try #require(UIColor(hex: "#0000FF80"))
        let c = components(of: color)
        #expect(abs(c.r - 0.0) < tolerance)
        #expect(abs(c.g - 0.0) < tolerance)
        #expect(abs(c.b - 1.0) < tolerance)
        #expect(abs(c.a - (128.0 / 255.0)) < tolerance)
    }

    // MARK: - Invalid input

    @Test("Given a string with non-hex characters, the initializer returns nil",
          arguments: ["#GG0000", "#12", "12345", "#FF00GG", ""])
    func invalidReturnsNil(hex: String) {
        #expect(UIColor(hex: hex) == nil)
    }
}
