import UIKit

public struct ButtonStyle {
    let textStyle: TextStyle
    let tintColor: UIColor?
    let viewStyle: ViewStyle?
    let backgroundImage: UIImage?
    let disabledBackgroundColor: UIColor?

    /// It's possible to set attributed text and ViewStyle to a Button individually,
    /// or use this init.
    /// If set, backgroundImage takes precedence and backgroundColor from viewStyle is not applied.
    /// `disabledBackgroundColor` provides a state-aware background for the disabled state; it is
    /// only honoured by `StyledButton` (a plain `UIButton` is not state-aware — see `StyledButton`).
    public init(
        textStyle: TextStyle,
        tintColor: UIColor? = nil,
        viewStyle: ViewStyle? = nil,
        backgroundImage: UIImage? = nil,
        disabledBackgroundColor: UIColor? = nil
    ) {
        self.textStyle = textStyle
        self.tintColor = tintColor
        self.viewStyle = viewStyle
        self.backgroundImage = backgroundImage
        self.disabledBackgroundColor = disabledBackgroundColor
    }
}
