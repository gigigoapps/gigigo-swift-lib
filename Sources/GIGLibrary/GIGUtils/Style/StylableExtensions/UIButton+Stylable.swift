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
        }
        // No disabled-state background dimming: `backgroundColor` is not state-aware, so
        // dimming it for the disabled state (the old alpha-0.3 path) stuck after the button
        // was re-enabled (C027). A reused text-only restyle is also left untouched here, so
        // an existing background image/colour is preserved. A proper state-aware disabled
        // background would need an explicit colour on `ButtonStyle` rather than mutating this.
	}
}
