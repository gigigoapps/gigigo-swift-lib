import UIKit

public enum Border: Int {
    case left
    case right
    case top
    case bottom
}

private final class BorderView: UIView { }

/// Draws a dashed border that tracks the host view's bounds and corner radius.
///
/// Implemented as a pinned subview (instead of a bare `CAShapeLayer` on the host's
/// layer) so the path is recomputed in `layoutSubviews` — staying correct across
/// rotation and resize rather than being captured pre-layout. Isolating the dashed
/// border in its own view also lets `resetBorders()` remove only this overlay,
/// without touching unrelated `CAShapeLayer`s added by callers.
private final class DottedBorderView: UIView {
    private let shapeLayer = CAShapeLayer()

    init(weight: CGFloat, color: UIColor) {
        super.init(frame: .zero)
        self.isUserInteractionEnabled = false
        self.backgroundColor = .clear
        shapeLayer.fillColor = UIColor.clear.cgColor
        shapeLayer.strokeColor = color.cgColor
        shapeLayer.lineWidth = weight
        shapeLayer.lineDashPattern = [4, 2]
        self.layer.addSublayer(shapeLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Inherit the host's corner radius; it may be set after the border is attached.
        // The rounding comes from the bezier path itself — the layer's own `cornerRadius`
        // has no effect on a path-stroked CAShapeLayer, so it is not set here.
        let radius = superview?.layer.cornerRadius ?? 0
        shapeLayer.frame = bounds
        shapeLayer.path = UIBezierPath(roundedRect: bounds, cornerRadius: radius).cgPath
    }
}

public extension UIView {
    
    func addSomeBorders(_ border: Border, weight: CGFloat, color: UIColor) {
		
		resetBorder(border)
        
        let lineView = BorderView()
		lineView.tag = border.rawValue
        addSubview(lineView)
        lineView.backgroundColor = color
        lineView.translatesAutoresizingMaskIntoConstraints = false
        
        switch border {
            
        case .left:
            lineView.leftAnchor.constraint(equalTo: leftAnchor).isActive = true
            lineView.topAnchor.constraint(equalTo: topAnchor).isActive = true
            lineView.bottomAnchor.constraint(equalTo: bottomAnchor).isActive = true
            lineView.widthAnchor.constraint(equalToConstant: weight).isActive = true
            
        case .right:
            lineView.rightAnchor.constraint(equalTo: rightAnchor).isActive = true
            lineView.topAnchor.constraint(equalTo: topAnchor).isActive = true
            lineView.bottomAnchor.constraint(equalTo: bottomAnchor).isActive = true
            lineView.widthAnchor.constraint(equalToConstant: weight).isActive = true
            
        case .top:
            lineView.topAnchor.constraint(equalTo: topAnchor).isActive = true
            lineView.leftAnchor.constraint(equalTo: leftAnchor).isActive = true
            lineView.rightAnchor.constraint(equalTo: rightAnchor).isActive = true
            lineView.heightAnchor.constraint(equalToConstant: weight).isActive = true
            
        case .bottom:
            lineView.bottomAnchor.constraint(equalTo: bottomAnchor).isActive = true
            lineView.leftAnchor.constraint(equalTo: leftAnchor).isActive = true
            lineView.rightAnchor.constraint(equalTo: rightAnchor).isActive = true
            lineView.heightAnchor.constraint(equalToConstant: weight).isActive = true
        }
    }
    
    func addBorder(weight: CGFloat, color: UIColor) {
        self.layer.borderWidth = weight
        self.layer.borderColor = color.cgColor
    }
	
    func addDottedBorder(weight: CGFloat, color: UIColor) {
        let borderView = DottedBorderView(weight: weight, color: color)
        borderView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(borderView)
        NSLayoutConstraint.activate([
            borderView.leadingAnchor.constraint(equalTo: leadingAnchor),
            borderView.trailingAnchor.constraint(equalTo: trailingAnchor),
            borderView.topAnchor.constraint(equalTo: topAnchor),
            borderView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
	
	func resetBorder(_ border: Border) {
		self.subviews.filter { $0 is BorderView && $0.tag == border.rawValue }.forEach { $0.removeFromSuperview() }
	}
	
	func resetBorders() {
		// Remove the border overlays we added: solid `BorderView`s and the dashed
		// `DottedBorderView`. Unrelated subviews and layers are left untouched.
		self.subviews.filter { $0 is BorderView || $0 is DottedBorderView }.forEach { $0.removeFromSuperview() }
    }
}
