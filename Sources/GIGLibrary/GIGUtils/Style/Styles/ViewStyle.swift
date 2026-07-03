import UIKit

public struct ViewStyle {
    let borderColor: UIColor
    let borderWidth: CGFloat
    let someBorders: [Border]
    let dottedBorders: Bool
    let cornerRadius: CGFloat?
    let shadowColor: UIColor
    let shadowOffset: CGSize
    let shadowOpacity: Float
    let shadowRadius: CGFloat
    let backgroundColor: UIColor

    /// If set, dottedBorders takes precedence and someBorders is not applied.
    public init(
        borderColor: UIColor = .clear,
        borderWidth: CGFloat = 0.0,
        someBorders: [Border] = [],
        dottedBorders: Bool = false,
        shadowColor: UIColor = .clear,
        shadowOffset: CGSize = CGSize.zero,
        shadowOpacity: Float = 0.0,
        shadowRadius: CGFloat = 0.0,
        cornerRadius: CGFloat? = nil,
        backgroundColor: UIColor = .clear
    ) {
        
        self.borderColor = borderColor
        self.borderWidth = borderWidth
        self.someBorders = someBorders
        self.dottedBorders = dottedBorders
        self.shadowColor = shadowColor
        self.shadowOffset = shadowOffset
        self.shadowOpacity = shadowOpacity
        self.shadowRadius = shadowRadius
        self.cornerRadius = cornerRadius
        self.backgroundColor = backgroundColor
    }
}
