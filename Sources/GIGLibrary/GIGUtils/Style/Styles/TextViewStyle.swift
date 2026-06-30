import UIKit

public struct TextViewStyle {
    let font: UIFont
    let tintColor: UIColor
    let textColor: UIColor
    let viewStyle: ViewStyle?

    public init(
        font: UIFont,
        tintColor: UIColor = .blue,
        textColor: UIColor = .black,
        viewStyle: ViewStyle? = nil
    ) {
        self.font = font
        self.tintColor = tintColor
        self.textColor = textColor
        self.viewStyle = viewStyle
    }
}
