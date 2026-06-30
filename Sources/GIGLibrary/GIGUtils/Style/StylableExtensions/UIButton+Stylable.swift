import UIKit

extension UIButton: Stylable {
    public func withStyle(_ style: ButtonStyle) {
        self.setAttributedTitle(self.currentTitle?.withStyle(style.textStyle), for: .normal)
        
        if let tintColor = style.tintColor {
            self.tintColor = tintColor
        }
        
        if let viewStyle = style.viewStyle {
            self.withViewStyle(viewStyle)
        }
        
        if let image = style.backgroundImage {
            setBackgroundImage(image, for: .normal)
        } else if let backgroundColor = style.viewStyle?.backgroundColor {
            // `backgroundColor` is not state-aware: deriving the disabled dim from it
            // (alpha 0.3) would stick after the button is re-enabled. Drive the appearance
            // through per-state background images instead, so UIKit restores the enabled
            // look automatically when `isEnabled` changes.
            self.backgroundColor = nil
            setBackgroundImage(UIImage.create(from: backgroundColor), for: .normal)
            setBackgroundImage(UIImage.create(from: backgroundColor.withAlphaComponent(0.3)), for: .disabled)
        }
	}
}
