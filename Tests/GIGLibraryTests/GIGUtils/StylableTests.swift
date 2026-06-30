import XCTest
import GIGLibrary

@MainActor
class StylableTests: XCTestCase {

    override func setUp() {
        super.setUp()
    }

    func test_applyStyle_to_String() {
        let stringToTest: String = "Test"
        let textStyle = TextStyle(font: UIFont.systemFont(ofSize: 10),
                                  foregroundColor: .blue,
                                  backgroundColor: .green,
                                  isStrikedThrough: true,
                                  isUnderlined: true,
                                  letterSpacing: 3)
        let attrString = stringToTest.withStyle(textStyle)
        XCTAssertEqual(attrString.attribute(named: NSAttributedString.Key.font.rawValue, forText: stringToTest)as! UIFont, UIFont.systemFont(ofSize: 10))
        XCTAssertEqual(attrString.attribute(named: NSAttributedString.Key.foregroundColor.rawValue, forText: stringToTest)as! UIColor, .blue)
        XCTAssertEqual(attrString.attribute(named: NSAttributedString.Key.backgroundColor.rawValue, forText: stringToTest)as! UIColor, .green)
        XCTAssertNotNil(attrString.attribute(named: NSAttributedString.Key.underlineStyle.rawValue, forText: stringToTest))
        // C070: strikethrough uses NSUnderlineStyle.single, not the magic literal 2 (.thick).
        XCTAssertEqual(attrString.attribute(named: NSAttributedString.Key.strikethroughStyle.rawValue, forText: stringToTest) as? Int,
                       NSUnderlineStyle.single.rawValue)
        // C028: letterSpacing (kern) is applied even when isStrikedThrough is true.
        XCTAssertEqual(attrString.attribute(named: NSAttributedString.Key.kern.rawValue, forText: stringToTest) as? CGFloat, 3)
    }
    
    func test_applyStyle_to_View() {
        let viewStyle = ViewStyle(borderColor: .blue,
                                  borderWidth: 2,
                                  someBorders: [],
                                  dottedBorders: false,
                                  shadowColor: .gray,
                                  shadowOffset: CGSize(width: 3, height: 3),
                                  shadowOpacity: 3.3,
                                  shadowRadius: 4.5,
                                  cornerRadius: 3.2,
                                  backgroundColor: .red)
        let sut = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: 0))
        sut.withViewStyle(viewStyle)
        
        XCTAssertEqual(sut.layer.borderColor, UIColor.blue.cgColor)
        XCTAssertEqual(sut.layer.borderWidth, 2)
        //some borders
        //dotted borders
        XCTAssertEqual(sut.layer.shadowColor, UIColor.gray.cgColor)
        XCTAssertEqual(sut.layer.shadowOffset, CGSize(width: 3, height: 3))
        XCTAssertEqual(sut.layer.shadowOpacity, 3.3)
        XCTAssertEqual(sut.layer.shadowRadius, 4.5)
        XCTAssertEqual(sut.layer.cornerRadius, 3.2)
        XCTAssertEqual(sut.backgroundColor, .red)
    }
    
    func test_applyStyle_to_TextField() {
        let sut = UITextField(frame: CGRect(x: 0, y: 0, width: 0, height: 0))
        let viewStyle = ViewStyle(backgroundColor: .red)
        let textFieldStyle = TextFieldStyle(font: UIFont.systemFont(ofSize: 10),
                                            tintColor: .blue,
                                            textColor: .green,
                                            borderStyle: .bezel,
                                            viewStyle: viewStyle)
        sut.withStyle(textFieldStyle)
        XCTAssertEqual(sut.font, UIFont.systemFont(ofSize: 10))
        XCTAssertEqual(sut.tintColor, .blue)
        XCTAssertEqual(sut.textColor, .green)
        XCTAssertEqual(sut.borderStyle, .bezel)
        XCTAssertEqual(sut.backgroundColor, .red)
    }
    
    func test_applyStyle_to_TextView() {
        let sut = UITextView(frame: CGRect(x: 0, y: 0, width: 0, height: 0))
        let viewStyle = ViewStyle(backgroundColor: .red)
        let textViewStyle = TextViewStyle(font: UIFont.systemFont(ofSize: 10),
                                          tintColor: .blue,
                                          textColor: .green,
                                          viewStyle: viewStyle)
        sut.withStyle(textViewStyle)
        XCTAssertEqual(sut.font, UIFont.systemFont(ofSize: 10))
        XCTAssertEqual(sut.tintColor, .blue)
        XCTAssertEqual(sut.textColor, .green)
        XCTAssertEqual(sut.backgroundColor, .red)
    }
    
    func test_applyStyle_to_Label_without_Text() {
        let sut = UILabel(frame: CGRect(x: 0, y: 0, width: 0, height: 0))
        let textStyle = TextStyle(font: UIFont.boldSystemFont(ofSize: 12))
        let viewStyle = ViewStyle(borderColor: .red)
        let labelStyle = LabelStyle(textStyle: textStyle, viewStyle: viewStyle)
        sut.withStyle(labelStyle)
        
        XCTAssertEqual(sut.font, UIFont.boldSystemFont(ofSize: 12))
        XCTAssertEqual(sut.layer.borderColor, UIColor.red.cgColor)
    }
    
    func test_applyStyle_to_Label_with_Text() {
        let sut = UILabel(frame: CGRect(x: 0, y: 0, width: 0, height: 0))
        let textStyle = TextStyle(font: UIFont.boldSystemFont(ofSize: 12))
        let viewStyle = ViewStyle(borderColor: .red)
        let labelStyle = LabelStyle(textStyle: textStyle, viewStyle: viewStyle)
        sut.text = "Test"
        sut.withStyle(labelStyle)
        
        XCTAssertEqual(sut.font, UIFont.boldSystemFont(ofSize: 12))
        XCTAssertEqual(sut.layer.borderColor, UIColor.red.cgColor)
    }
    
    func test_applyStyle_to_Button_with_text() {
        let sut = UIButton(frame: CGRect(x: 0, y: 0, width: 0, height: 0))
        let textStyle = TextStyle(font: UIFont.boldSystemFont(ofSize: 12))
        let viewStyle = ViewStyle(borderColor: .red)
        let buttonStyle = ButtonStyle(textStyle: textStyle,
                                      viewStyle: viewStyle,
                                      backgroundImage: nil)
        sut.setTitle("TEST", for: .normal)
        sut.withStyle(buttonStyle)
        
        XCTAssertEqual(sut.titleLabel?.font, UIFont.boldSystemFont(ofSize: 12))
        XCTAssertEqual(sut.layer.borderColor, UIColor.red.cgColor)
    }

    func test_applyStyle_to_disabled_Button_does_not_persist_dim() {
        // C027: a button styled while disabled must not get a 30% dim baked into
        // backgroundColor (which is not state-aware and would stick after re-enabling).
        // The background colour is applied at full opacity, with no per-state image.
        let sut = UIButton(frame: CGRect(x: 0, y: 0, width: 0, height: 0))
        sut.isEnabled = false
        let viewStyle = ViewStyle(backgroundColor: .red)
        let buttonStyle = ButtonStyle(textStyle: TextStyle(font: UIFont.systemFont(ofSize: 10)),
                                      viewStyle: viewStyle)
        sut.withStyle(buttonStyle)

        XCTAssertEqual(sut.backgroundColor, .red, "background must be the full colour, not a dimmed variant")
        XCTAssertNil(sut.backgroundImage(for: .normal))
    }

    func test_colorStyle_keeps_dynamic_backgroundColor() {
        // The background colour is assigned directly (not rendered into a 1×1 image), so a
        // dynamic UIColor is preserved as-is and re-resolves on light/dark trait changes.
        let sut = UIButton(frame: CGRect(x: 0, y: 0, width: 0, height: 0))
        let buttonStyle = ButtonStyle(textStyle: TextStyle(font: UIFont.systemFont(ofSize: 10)),
                                      viewStyle: ViewStyle(backgroundColor: .systemBackground))
        sut.withStyle(buttonStyle)

        XCTAssertEqual(sut.backgroundColor, .systemBackground, "dynamic colour must be stored as-is, not frozen")
        XCTAssertNil(sut.backgroundImage(for: .normal))
    }

    func test_StyledButton_disabledBackgroundColor_is_state_aware_and_dynamic() {
        // C027 follow-up: StyledButton applies a state-aware disabled background by swapping
        // backgroundColor on isEnabled changes. Colours are stored as dynamic UIColors (not
        // frozen images), so they re-resolve on light/dark trait changes.
        let sut = StyledButton(frame: CGRect(x: 0, y: 0, width: 0, height: 0))
        let style = ButtonStyle(textStyle: TextStyle(font: UIFont.systemFont(ofSize: 10)),
                                viewStyle: ViewStyle(backgroundColor: .systemBackground),
                                disabledBackgroundColor: .systemGray)
        sut.withStyle(style)

        XCTAssertEqual(sut.backgroundColor, .systemBackground, "enabled uses the enabled dynamic colour")
        XCTAssertNil(sut.backgroundImage(for: .normal), "no frozen image is used")

        sut.isEnabled = false
        XCTAssertEqual(sut.backgroundColor, .systemGray, "disabling swaps to the disabled dynamic colour")

        sut.isEnabled = true
        XCTAssertEqual(sut.backgroundColor, .systemBackground, "re-enabling restores the enabled colour — no stuck state")
    }

    func test_StyledButton_without_disabledColor_keeps_enabled_color_when_disabled() {
        // When no disabledBackgroundColor is provided, the enabled colour is used for both
        // states (no dimming), so the behaviour matches a plain styled button.
        let sut = StyledButton(frame: CGRect(x: 0, y: 0, width: 0, height: 0))
        sut.withStyle(ButtonStyle(textStyle: TextStyle(font: UIFont.systemFont(ofSize: 10)),
                                  viewStyle: ViewStyle(backgroundColor: .red)))
        sut.isEnabled = false
        XCTAssertEqual(sut.backgroundColor, .red)
    }

    func test_plain_UIButton_ignores_disabledBackgroundColor() {
        // A plain UIButton is not state-aware: disabledBackgroundColor is documented as
        // StyledButton-only, so the background stays the enabled colour.
        let sut = UIButton(frame: CGRect(x: 0, y: 0, width: 0, height: 0))
        sut.isEnabled = false
        sut.withStyle(ButtonStyle(textStyle: TextStyle(font: UIFont.systemFont(ofSize: 10)),
                                  viewStyle: ViewStyle(backgroundColor: .red),
                                  disabledBackgroundColor: .gray))
        XCTAssertEqual(sut.backgroundColor, .red)
    }

    func test_textOnly_restyle_preserves_existing_background_image() {
        // Re-styling an image-backed button with a text-only ButtonStyle (typography update)
        // must not wipe the existing background image.
        let sut = UIButton(frame: CGRect(x: 0, y: 0, width: 0, height: 0))
        let explicitImage = UIImage.create(from: .blue)
        sut.withStyle(ButtonStyle(textStyle: TextStyle(font: UIFont.systemFont(ofSize: 10)),
                                  backgroundImage: explicitImage))
        XCTAssertEqual(sut.backgroundImage(for: .normal), explicitImage)

        sut.withStyle(ButtonStyle(textStyle: TextStyle(font: UIFont.boldSystemFont(ofSize: 14))))
        XCTAssertEqual(sut.backgroundImage(for: .normal), explicitImage,
                       "text-only restyle must preserve the existing background image")
    }

    func test_dottedBorder_addsSingleOverlay_and_resetRemovesItOnly() {
        // C030/C031: the dashed border is a dedicated overlay subview. Applying it must add
        // exactly one overlay (no accumulation on re-style), resetBorders must remove that
        // overlay, and neither operation may touch foreign subviews or foreign layers.
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 40))
        let foreignSubview = UIView()
        host.addSubview(foreignSubview)
        let foreignLayer = CAShapeLayer()
        host.layer.addSublayer(foreignLayer)
        let baseSubviews = host.subviews.count

        let style = ViewStyle(borderColor: .red, borderWidth: 2, dottedBorders: true)
        host.withViewStyle(style)
        XCTAssertEqual(host.subviews.count, baseSubviews + 1, "Expected exactly one dashed-border overlay")

        // Re-styling resets first, so overlays must not accumulate.
        host.withViewStyle(style)
        XCTAssertEqual(host.subviews.count, baseSubviews + 1, "Re-styling must not accumulate overlays")

        host.resetBorders()
        XCTAssertEqual(host.subviews.count, baseSubviews, "resetBorders must remove the dashed-border overlay")
        XCTAssertTrue(host.subviews.contains(foreignSubview), "resetBorders must not remove foreign subviews")
        XCTAssertEqual(host.layer.sublayers?.contains(foreignLayer), true, "resetBorders must not remove foreign layers")
    }
}
