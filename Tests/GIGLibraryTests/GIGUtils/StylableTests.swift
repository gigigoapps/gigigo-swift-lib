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
        // C027: a button styled while disabled must not keep the 30% dim baked into
        // backgroundColor after it is re-enabled. The background is now state-aware.
        let sut = UIButton(frame: CGRect(x: 0, y: 0, width: 0, height: 0))
        sut.isEnabled = false
        let viewStyle = ViewStyle(backgroundColor: .red)
        let buttonStyle = ButtonStyle(textStyle: TextStyle(font: UIFont.systemFont(ofSize: 10)),
                                      viewStyle: viewStyle)
        sut.withStyle(buttonStyle)

        // backgroundColor is not used for the fill, so re-enabling cannot leave a stuck dim.
        XCTAssertNil(sut.backgroundColor)
        // Enabled and disabled appearances are provided as separate, state-specific images.
        XCTAssertNotNil(sut.backgroundImage(for: .normal))
        XCTAssertNotNil(sut.backgroundImage(for: .disabled))
        XCTAssertNotEqual(sut.backgroundImage(for: .normal), sut.backgroundImage(for: .disabled))
    }

    func test_restyling_Button_clears_stale_disabled_background() {
        // A reused button first styled by color sets a .disabled dim image. Restyling it
        // with an explicit backgroundImage must not leave that stale .disabled image behind.
        let sut = UIButton(frame: CGRect(x: 0, y: 0, width: 0, height: 0))
        let textStyle = TextStyle(font: UIFont.systemFont(ofSize: 10))
        sut.withStyle(ButtonStyle(textStyle: textStyle, viewStyle: ViewStyle(backgroundColor: .red)))
        XCTAssertNotNil(sut.backgroundImage(for: .disabled), "color style should install a disabled dim image")

        let explicitImage = UIImage.create(from: .blue)
        sut.withStyle(ButtonStyle(textStyle: textStyle, backgroundImage: explicitImage))
        XCTAssertEqual(sut.backgroundImage(for: .normal), explicitImage)
        // No explicit .disabled image now, so UIKit falls back to the new .normal image —
        // the stale color dim is gone (it would NOT equal the new image if it had leaked).
        XCTAssertEqual(sut.backgroundImage(for: .disabled), explicitImage,
                       "stale disabled dim must be cleared so the new style's image is used")
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
