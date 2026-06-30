import UIKit

extension UIButton: Stylable {
    public func withStyle(_ style: ButtonStyle) {
        self.setAttributedTitle(self.currentTitle?.withStyle(style.textStyle), for: .normal)
        
        if let tintColor = style.tintColor {
            self.tintColor = tintColor
        }
        
        if let viewStyle = style.viewStyle {
            // `withViewStyle` assigns `backgroundColor` directly. Keeping the colour (rather
            // than rendering it into a 1×1 image) lets dynamic colours re-resolve on
            // light/dark trait changes — the same reason ViewStyle defaults to `.clear`.
            self.withViewStyle(viewStyle)
        }

        if let image = style.backgroundImage {
            setBackgroundImage(image, for: .normal)
        } else if let styled = self as? StyledButton {
            // `StyledButton` tracks `isEnabled` and swaps between the two dynamic colours, so
            // the disabled background is state-aware and re-resolves on trait changes. The
            // enabled colour comes from `viewStyle.backgroundColor` (already applied above).
            styled.setStatefulBackgroundColors(enabled: style.viewStyle?.backgroundColor,
                                               disabled: style.disabledBackgroundColor)
        }
        // For a plain `UIButton`, the enabled `backgroundColor` (set by `withViewStyle`) is the
        // only background: `backgroundColor` is not state-aware, so a disabled dim would either
        // stick after re-enabling (C027) or freeze a dynamic colour into an image. A text-only
        // restyle leaves any existing background untouched. Use `StyledButton` for a state-aware
        // disabled background via `ButtonStyle.disabledBackgroundColor`.
	}
}
