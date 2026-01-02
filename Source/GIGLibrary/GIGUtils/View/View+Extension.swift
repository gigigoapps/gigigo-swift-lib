//
//  UIView+Extension.swift
//  wally
//
//  Created by Jerilyn Gonçalves on 13/03/2020.
//  Copyright © 2020 Gigigo. All rights reserved.
//

import UIKit

extension UIView {
    
    public func width() -> CGFloat {
        self.frame.width
    }
    
    public func height() -> CGFloat {
        self.frame.height
    }
    
    public func set(width: CGFloat) {
        let size = CGSize(width: width, height: self.height())
        self.frame.size = size
    }
    
    public func set(height: CGFloat) {
        let size = CGSize(width: self.width(), height: height)
        self.frame.size = size
    }
    
    public func x() -> CGFloat {
        self.frame.origin.x
    }
    
    public func y() -> CGFloat {
        self.frame.origin.y
    }
    
    public func set(x: CGFloat) {
        self.frame.origin = CGPoint(x: x, y: self.y())
    }
    
    public func set(y: CGFloat) {
        self.frame.origin = CGPoint(x: self.x(), y: y)
    }
    
    public func setCornerRadius(to radius: CGFloat = 8) {
        self.layer.cornerRadius = radius
        if #available(iOS 13.0, *) {
            self.layer.cornerCurve = .continuous
        }
    }
    
    public func layout(using constraints: [NSLayoutConstraint]) {
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate(constraints)
    }
    
    public func addBlur() {
        self.backgroundColor = .clear
        let blurEffect = UIBlurEffect(style: .regular)
        let blurView = UIVisualEffectView(effect: blurEffect)
        self.insertSubview(blurView, at: 0)
        blurView.layout(using: [
            blurView.heightAnchor.constraint(equalTo: self.heightAnchor),
            blurView.widthAnchor.constraint(equalTo: self.widthAnchor)])
    }
    
    public func rotate(degrees: CGFloat) {
        let radians = (degrees * .pi) / 180
        self.transform = CGAffineTransform(rotationAngle: radians)
    }
    
    public func roundCorners(_ corners: UIRectCorner, radius: CGFloat) {
        let path = UIBezierPath(roundedRect: self.bounds, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        let mask = CAShapeLayer()
        mask.path = path.cgPath
        self.layer.mask = mask
    }
    
    public func show(alertContainerView: UIView, blurEffectView: UIVisualEffectView) {
        self.isHidden = true
        guard let window = UIApplication.shared.keyWindow else { return }
        window.endEditing(true)
        window.addSubview(self)
        self.layout(using: [
            self.topAnchor.constraint(equalTo: window.topAnchor),
            self.bottomAnchor.constraint(equalTo: window.bottomAnchor),
            self.leadingAnchor.constraint(equalTo: window.leadingAnchor),
            self.trailingAnchor.constraint(equalTo: window.trailingAnchor)
        ])
        
        alertContainerView.alpha = 0
        blurEffectView.effect = nil
        self.isHidden = false
        
        UIView.animate(withDuration: 0.5) {
            alertContainerView.alpha = 1
            blurEffectView.effect = UIBlurEffect(style: .dark)
        }
    }
    
    public func removeSubviews() {
        self.subviews.forEach { $0.removeFromSuperview() }
    }
}
