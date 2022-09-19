//
//  UIColor+Extension.swift
//  wally
//
//  Created by Alejandro Jiménez Agudo on 25/06/2020.
//  Copyright © 2020 Gigigo. All rights reserved.
//

import UIKit

extension UIColor {
    
    public convenience init?(hex: String) {
        let r: CGFloat
        let g: CGFloat
        let b: CGFloat
        if hex.hasPrefix("#") {
            let start = hex.index(hex.startIndex, offsetBy: 1)
            let hexColor = String(hex[start...])
            if hexColor.count == 6 {
                let scanner = Scanner(string: hexColor)
                var hexNumber: UInt64 = 0
                if scanner.scanHexInt64(&hexNumber) {
                    r = CGFloat((hexNumber & 0xff0000) >> 16) / 255
                    g = CGFloat((hexNumber & 0x00ff00) >> 8) / 255
                    b = CGFloat((hexNumber & 0x0000ff) >> 0) / 255
                    self.init(red: r, green: g, blue: b, alpha: 1.0)
                    return
                }
            }
        }
        
        return nil
    }
    
}
