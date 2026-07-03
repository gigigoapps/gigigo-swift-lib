import UIKit

// MARK: PUBLIC

// MARK: Extensions

public extension String {
    
    /**
     Apply styles to a String
     
     - returns:
     A StyledString
     
     - parameters:
     - styles: List of styles
     
     ````
     "Cool text".style(.Bold,
     .Underline,
     .Color(UIColor.redColor()))
     ````
     */
    
    func style(_ styles: Style...) -> StyledString {
        
        var styledString = StyledString()
        styledString.styledStringFractions.append(StyledStringFraction(string: self, styles: styles))
        return styledString
    }
}

public extension UILabel {
    
    /**
     Set a StyledString to a Label
     
     ````
     label.styledString("Cool text".style(.Bold,
     .Underline,
     .Color(UIColor.redColor())))
     ````
     */
    func styledString(_ styledString: StyledString) {
        self.attributedText = styledString.toAttributedString(defaultFont: self.font)
    }

    /**
     Set a HTML String to a Label

     ````
     label.html("<b>Important</b> text")
     ````
     */
    func html(_ html: String?) {
        self.attributedText = NSAttributedString(fromHTML: html ?? "", font: self.font, color: self.textColor, alignment: self.textAlignment)
    }
}

public extension UITextView {
    
    /**
     Set a StyledString to a UITextView
     
     ````
     textView.styledString("Cool text".style(.Bold,
     .Underline,
     .Color(UIColor.redColor())))
     ````
     */
    func styledString(_ styledString: StyledString) {
        if let font = self.font {
            self.attributedText = styledString.toAttributedString(defaultFont: font)
        } else {
            let defaultFont = UIFont.systemFont(ofSize: UIFont.systemFontSize)
            self.attributedText = styledString.toAttributedString(defaultFont: defaultFont)
        }
    }

    /**
     Set a HTML String to a UITextView

     ````
     textView.html("<b>Important</b> text")
     ````
     */
    func html(_ html: String?) {
        var font = UIFont.systemFont(ofSize: UIFont.systemFontSize)
        var textColor = UIColor.black
        
        if let currentFont = self.font {
            font = currentFont
        }
        
        if let currentTextColor = self.textColor {
            textColor = currentTextColor
        }
        
        self.attributedText = NSAttributedString(fromHTML: html ?? "", font: font, color: textColor, alignment: self.textAlignment)
    }
}

public extension NSAttributedString {

    // HTML parsing spins up WebKit, which Apple restricts to the main thread,
    // so these convenience initializers are isolated to @MainActor (C026).
    @MainActor
    convenience init?(fromHTML html: String) {

        let htmlData: Data
        if let data = html.data(using: String.Encoding.utf8) {
            htmlData = data
        } else {
            htmlData = Data()
            LogWarn("Could not convert to data from: " + html)
        }
        
        do {
            try self.init(
                data: htmlData,
                options: [
                    NSAttributedString.DocumentReadingOptionKey.documentType: NSAttributedString.DocumentType.html,
                    NSAttributedString.DocumentReadingOptionKey.characterEncoding: String.Encoding.utf8.rawValue
                ],
                documentAttributes: nil
            )
        } catch {
            return nil
        }
    }
    
    @MainActor
    convenience init?(fromHTML html: String, font: UIFont, color: UIColor, alignment: NSTextAlignment = .left) {
        self.init(fromHTML: NSAttributedString.createHtml(from: html, font: font, pointSize: font.pointSize, color: color, alignment: alignment))
    }

    @MainActor
    convenience init?(fromHTML html: String, pointSize: CGFloat, color: UIColor, alignment: NSTextAlignment = .left) {
        self.init(fromHTML: NSAttributedString.createHtml(from: html, font: UIFont.systemFont(ofSize: UIFont.systemFontSize), pointSize: pointSize, color: color, alignment: alignment))
    }

    private class func createHtml(from string: String, font: UIFont, pointSize: CGFloat, color: UIColor, alignment: NSTextAlignment) -> String {
        let fontName = font.isSystemFont() ? "-apple-system" : font.fontName
        let htmlFontWeight = font.isSystemFont() ? "font-weight:\(font.htmlWeight());" : ""
        let style = "<style>body{color:\(color.hexString(false)); font-family: '\(fontName)'; font-size: \(String(format: "%.0f", pointSize))px;\(htmlFontWeight)}</style>"
        return style + string
    }
}

extension Data {
    // HTML parsing spins up WebKit, restricted to the main thread by Apple (C026).
    @MainActor var attributedString: NSAttributedString? {
        do {
            return try NSAttributedString(
                data: self,
                options: [
                    NSAttributedString.DocumentReadingOptionKey.documentType: NSAttributedString.DocumentType.html,
                    NSAttributedString.DocumentReadingOptionKey.characterEncoding: String.Encoding.utf8.rawValue
                ],
                documentAttributes: nil)
        } catch let error as NSError {
            LogError(error)
        }
        return nil
    }
}

// MARK: Styled String

public struct StyledString {
    
    var styledStringFractions: [StyledStringFraction] = []
    
    // MARK: PUBLIC
    
    public func toAttributedString(defaultFont font: UIFont) -> NSAttributedString {
        
        return self.styledStringFractions.reduce(NSAttributedString()) { (currentAttributedString, singleStyledString) -> NSAttributedString in
            
            let attributedString = self.attributedStringFrom(styledStringFraction: singleStyledString, font: font)
            
            let finalAttributedString = NSMutableAttributedString(attributedString: currentAttributedString)
            finalAttributedString.append(attributedString)
            
            return finalAttributedString
        }
    }
    
    // MARK: PRIVATE
    
    func attributedStringFrom(styledStringFraction: StyledStringFraction, font: UIFont) -> NSAttributedString {

        let currentString = styledStringFraction.string
        let currentStyle = styledStringFraction.styles

        let tempAttributedString = NSMutableAttributedString(string: currentString)
        let fullRange = NSRange(location: 0, length: tempAttributedString.length)

        // Resolve font-related styles in source order, so a later `.font`/`.fontName`/`.size`
        // overrides an earlier one exactly as the previous reducer did. The single change vs.
        // that reducer is that `.size` resizes through the descriptor instead of rebuilding the
        // font by name, so a bold/italic trait already applied is not dropped by a later size (C069).
        var resolvedFont: UIFont?

        for style in currentStyle {
            switch style {
            case .none:
                // No attribute is emitted for `.none` so it does not pollute the range (C066).
                continue
            case .bold:
                resolvedFont = StyledString.font(byInserting: .traitBold, into: resolvedFont ?? font)
            case .italic:
                resolvedFont = StyledString.font(byInserting: .traitItalic, into: resolvedFont ?? font)
            case .size(let pointSize):
                let base = resolvedFont ?? font
                resolvedFont = UIFont(descriptor: base.fontDescriptor, size: pointSize)
            case .fontName(let name):
                let base = resolvedFont ?? font
                if let named = UIFont(name: name, size: base.pointSize) {
                    resolvedFont = named
                } else {
                    LogWarn("Could not find font with name: " + name)
                    resolvedFont = UIFont.systemFont(ofSize: base.pointSize)
                }
            case .font(let explicit):
                resolvedFont = explicit
            default:
                tempAttributedString.addAttribute(
                    NSAttributedString.Key(rawValue: style.key()),
                    value: style.value(forFont: font),
                    range: fullRange
                )
            }
        }

        if let resolvedFont {
            tempAttributedString.addAttribute(.font, value: resolvedFont, range: fullRange)
        }

        return tempAttributedString
    }

    /// Returns `font` with `trait` added to its existing symbolic traits, preserving the size.
    ///
    /// Uses `union` (not a plain `withSymbolicTraits`) so combining `.bold` and `.italic`
    /// keeps both, and resizing later through the descriptor never discards them (C069).
    private static func font(byInserting trait: UIFontDescriptor.SymbolicTraits, into font: UIFont) -> UIFont {
        let combined = font.fontDescriptor.symbolicTraits.union(trait)
        guard let descriptor = font.fontDescriptor.withSymbolicTraits(combined) else { return font }
        return UIFont(descriptor: descriptor, size: font.pointSize)
    }
}

// MARK: Styles

public enum Style {
    
    case none
    case bold
    case italic
    case color(UIColor)
    case backgroundColor(UIColor)
    case size(CGFloat)
    case fontName(String)
    case font(UIFont)
    case underline
    case underlineThick
    case underlineDouble
    case underlineColor(UIColor)
    case link(URL)
    case baseLineOffset(CGFloat)
    case letterSpacing(CGFloat)
    case centerAlignment
    case leftAlignment
    case rightAlignment
    case lineSpacing(CGFloat)
    
    // swiftlint:disable:next cyclomatic_complexity
    func key() -> String {
        
        switch self {
            
        case .none:
            return ""
        case .bold:
            return NSAttributedString.Key.font.rawValue
        case .italic:
            return NSAttributedString.Key.font.rawValue
        case .color:
            return NSAttributedString.Key.foregroundColor.rawValue
        case .backgroundColor:
            return NSAttributedString.Key.backgroundColor.rawValue
        case .size:
            return NSAttributedString.Key.font.rawValue
        case .fontName:
            return NSAttributedString.Key.font.rawValue
        case .font:
            return NSAttributedString.Key.font.rawValue
        case .underline:
            return NSAttributedString.Key.underlineStyle.rawValue
        case .underlineThick:
            return NSAttributedString.Key.underlineStyle.rawValue
        case .underlineDouble:
            return NSAttributedString.Key.underlineStyle.rawValue
        case .underlineColor:
            return NSAttributedString.Key.underlineColor.rawValue
        case .link:
            return NSAttributedString.Key.link.rawValue
        case .baseLineOffset:
            return NSAttributedString.Key.baselineOffset.rawValue
        case .letterSpacing:
            return NSAttributedString.Key.kern.rawValue
        case .centerAlignment:
            return NSAttributedString.Key.paragraphStyle.rawValue
        case .leftAlignment:
            return NSAttributedString.Key.paragraphStyle.rawValue
        case .rightAlignment:
            return NSAttributedString.Key.paragraphStyle.rawValue
        case .lineSpacing:
            return NSAttributedString.Key.paragraphStyle.rawValue
        }
    }
    
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    func value(forFont font: UIFont) -> AnyObject {
        
        switch self {
            
        case .none:
            return "" as AnyObject
        case .bold:
            if let fontDescriptor = font.fontDescriptor.withSymbolicTraits(.traitBold) {
                return UIFont(descriptor: fontDescriptor, size: 0.0)
            }
            return font
        case .italic:
            if let fontDescriptor = font.fontDescriptor.withSymbolicTraits(.traitItalic) {
                return UIFont(descriptor: fontDescriptor, size: 0.0)
            }
            return font
        case .color(let color):
            return color
        case .backgroundColor(let color):
            return color
        case .size(let pointSize):
            if let font = UIFont(name: font.fontName, size: pointSize) {
                return font
            }
            return UIFont.systemFont(ofSize: pointSize)
        case .fontName(let fontName):
            if let font = UIFont(name: fontName, size: font.pointSize) {
                return font
            }
            LogWarn("Could not find font with name: " + fontName)
            return UIFont.systemFont(ofSize: font.pointSize)
        case .font(let font):
            return font
        case .underline:
            return NSUnderlineStyle.single.rawValue as AnyObject
        case .underlineThick:
            return NSUnderlineStyle.thick.rawValue as AnyObject
        case .underlineDouble:
            return NSUnderlineStyle.double.rawValue as AnyObject
        case .underlineColor(let color):
            return color
        case .link(let link):
            return link as AnyObject
        case .baseLineOffset(let offset):
            return offset as AnyObject
        case .letterSpacing(let spacing):
            return spacing as AnyObject
        case .centerAlignment:
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center
            return paragraphStyle
        case .leftAlignment:
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .left
            return paragraphStyle
        case .rightAlignment:
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .right
            return paragraphStyle
        case .lineSpacing(let space):
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = space
            return paragraphStyle
        }
    }
}

// MARK: Overriden operators

/**
 Joins String with a StyledString
 
 - returns:
 A StyledString
 
 ````
 "Cool text".style(.Bold, .Underline, .Color(UIColor.redColor())) + " simple text"
 ````
 */
public func + (left: StyledString, right: String) -> StyledString {
    
    var styledText = left
    styledText.styledStringFractions.append(StyledStringFraction(string: right, styles: [Style.none]))
    
    return styledText
}

/**
 Joins String with a StyledString
 
 - returns:
 A StyledString
 
 ````
 "This is My " + "Cool text".style(.Bold,
 .Underline,
 .Color(UIColor.redColor()))
 ````
 */
public func + (left: String, right: StyledString) -> StyledString {
    
    var styledText = right
    styledText.styledStringFractions.insert(StyledStringFraction(string: left, styles: [Style.none]), at: 0)
    
    return styledText
}

/**
 Joins String with a StyledString
 
 - returns:
 A StyledString
 
 ````
 "This is My ".appleStyles(.Bold) + "Cool text".style(.Bold,
 .Underline,
 .Color(UIColor.redColor()))
 ````
 */
public func + (left: StyledString, right: StyledString) -> StyledString {
    
    var styledText = left
    styledText.styledStringFractions.append(contentsOf: right.styledStringFractions)
    
    return styledText
}

// MARK: PRIVATE

struct StyledStringFraction {
    
    let string: String
    var styles: [Style]
}

extension UIColor {
    
    public func hexString(_ includeAlpha: Bool) -> String {
        
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        
        self.getRed(&r, green: &g, blue: &b, alpha: &a)
        
        if includeAlpha {
            return String(format: "#%02X%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255), Int(a * 255))
        }
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}

extension UIFont {
    
    func isSystemFont() -> Bool {
        return self.familyName == UIFont.systemFont(ofSize: UIFont.systemFontSize).familyName
    }
    
    // swiftlint:disable:next cyclomatic_complexity
    func weight() -> UIFont.Weight {
        
        let fontAttributeKey = UIFontDescriptor.AttributeName(rawValue: "NSCTFontUIUsageAttribute")
        if let fontWeight = self.fontDescriptor.fontAttributes[fontAttributeKey] as? String {
            switch fontWeight {
                
            case "CTFontBoldUsage":
                return UIFont.Weight.bold
                
            case "CTFontBlackUsage":
                return UIFont.Weight.black
                
            case "CTFontHeavyUsage":
                return UIFont.Weight.heavy
                
            case "CTFontUltraLightUsage":
                return UIFont.Weight.ultraLight
                
            case "CTFontThinUsage":
                return UIFont.Weight.thin
                
            case "CTFontLightUsage":
                return UIFont.Weight.light
                
            case "CTFontMediumUsage":
                return UIFont.Weight.medium
                
            case "CTFontDemiUsage":
                return UIFont.Weight.semibold
                
            case "CTFontRegularUsage":
                return UIFont.Weight.regular
                
            default:
                return UIFont.Weight.regular
            }
        }
        
        return UIFont.Weight.regular
    }
    
    func htmlWeight() -> Int {
        switch self.weight() {
        case UIFont.Weight.thin:
            return 100
        case UIFont.Weight.ultraLight:
            return 200
        case UIFont.Weight.light:
            return 300
        case UIFont.Weight.regular:
            return 400
        case UIFont.Weight.medium:
            return 500
        case UIFont.Weight.semibold:
            return 600
        case UIFont.Weight.bold:
            return 700
        case UIFont.Weight.black, UIFont.Weight.heavy:
            return 900
        default:
            return 400
        }
    }
}
