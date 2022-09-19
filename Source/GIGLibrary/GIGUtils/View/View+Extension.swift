//
//  UIView+Extension.swift
//  wally
//
//  Created by Jerilyn Gonçalves on 13/03/2020.
//  Copyright © 2020 Gigigo. All rights reserved.
//

import UIKit

extension UIView {
    
    func setCornerRadius(to radius: CGFloat = 8) {
        self.layer.cornerRadius = radius
        if #available(iOS 13.0, *) {
            self.layer.cornerCurve = .continuous
        }
    }
    
    func layout(using constraints: [NSLayoutConstraint]) {
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate(constraints)
    }
    
    func addBlur() {
        self.backgroundColor = .clear
        let blurEffect = UIBlurEffect(style: .regular)
        let blurView = UIVisualEffectView(effect: blurEffect)
        self.insertSubview(blurView, at: 0)
        blurView.layout(using: [
            blurView.heightAnchor.constraint(equalTo: self.heightAnchor),
            blurView.widthAnchor.constraint(equalTo: self.widthAnchor)])
    }
    
    func rotate(degrees: CGFloat) {
        let radians = (degrees * .pi) / 180
        self.transform = CGAffineTransform(rotationAngle: radians)
    }
    
    func width() -> CGFloat {
        self.frame.width
    }
    
    func height() -> CGFloat {
        self.frame.height
    }
    
    func set(height: CGFloat) {
        let size = CGSize(width: self.width(), height: height)
        self.frame.size = size
    }
    
    func roundCorners(_ corners: UIRectCorner, radius: CGFloat) {
        let path = UIBezierPath(roundedRect: self.bounds, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        let mask = CAShapeLayer()
        mask.path = path.cgPath
        self.layer.mask = mask
    }
    
    func show(alertContainerView: UIView, blurEffectView: UIVisualEffectView) {
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
}
