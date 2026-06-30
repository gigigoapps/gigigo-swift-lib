import UIKit

public struct ButtonStyle {
    let textStyle: TextStyle
    let tintColor: UIColor?
    let viewStyle: ViewStyle?
    let backgroundImage: UIImage?
    
    /// It's possible to set attributed text and ViewStyle to a Button individually,
    /// or use this init.
    /// If set, backgroundImage takes precedence and backgroundColor from viewStyle is not applied.
    public init(
        textStyle: TextStyle,
        tintColor: UIColor? = nil,
        viewStyle: ViewStyle? = nil,
        backgroundImage: UIImage? = nil
    ) {
        self.textStyle = textStyle
        self.tintColor = tintColor
        self.viewStyle = viewStyle
        self.backgroundImage = backgroundImage
    }
}
