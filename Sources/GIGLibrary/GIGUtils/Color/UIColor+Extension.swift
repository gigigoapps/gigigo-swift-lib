//
//  UIColor+Extension.swift
//  wally
//
//  Created by Alejandro Jiménez Agudo on 25/06/2020.
//  Copyright © 2020 Gigigo. All rights reserved.
//

import UIKit

extension UIColor {

    /// Creates a color from a hex string.
    ///
    /// Accepted formats (with an optional leading `#`, case-insensitive):
    /// * 3 digits — `RGB` shorthand (each digit is duplicated, e.g. `#F00` == `#FF0000`)
    /// * 6 digits — `RRGGBB` (alpha defaults to `1.0`)
    /// * 8 digits — `RRGGBBAA` (the last pair is the alpha channel)
    ///
    /// Returns `nil` when the string is not one of the accepted lengths or contains non-hex characters.
    public convenience init?(hex: String) {
        var normalized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.hasPrefix("#") {
            normalized.removeFirst()
        }

        let length = normalized.count
        guard length == 3 || length == 6 || length == 8 else { return nil }

        let scanner = Scanner(string: normalized)
        var value: UInt64 = 0
        guard scanner.scanHexInt64(&value), scanner.isAtEnd else { return nil }

        let r: CGFloat
        let g: CGFloat
        let b: CGFloat
        let a: CGFloat
        switch length {
        case 3:
            // Each 4-bit nibble is duplicated: 0xF -> 0xFF, so dividing by 15 maps 0...15 to 0...1.
            r = CGFloat((value & 0xF00) >> 8) / 15
            g = CGFloat((value & 0x0F0) >> 4) / 15
            b = CGFloat(value & 0x00F) / 15
            a = 1.0
        case 6:
            r = CGFloat((value & 0xFF0000) >> 16) / 255
            g = CGFloat((value & 0x00FF00) >> 8) / 255
            b = CGFloat(value & 0x0000FF) / 255
            a = 1.0
        default: // 8
            r = CGFloat((value & 0xFF000000) >> 24) / 255
            g = CGFloat((value & 0x00FF0000) >> 16) / 255
            b = CGFloat((value & 0x0000FF00) >> 8) / 255
            a = CGFloat(value & 0x000000FF) / 255
        }

        self.init(red: r, green: g, blue: b, alpha: a)
    }

}
