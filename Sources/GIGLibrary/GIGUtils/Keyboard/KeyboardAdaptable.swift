//
//  Keyboard.swift
//  AppliverySDK
//
//  Created by Alejandro Jiménez on 6/3/16.
//  Copyright © 2016 Applivery S.L. All rights reserved.
//

import UIKit

@MainActor
public protocol KeyboardAdaptable {
	
	func keyboardWillShow()
	func keyboardDidShow()
	
	func keyboardWillHide()
	func keyboardDidHide()
    func keyboardChangeFrame(_ size: CGSize)
}

typealias KeyboardEventContext = Keyboard.KeyboardEventContext


@MainActor
public extension KeyboardAdaptable where Self: UIViewController {
	
	// MARK: - Public Methods
	
	/// Must call this method on viewWillAppear
    func startKeyboard() {
		self.manageKeyboardShowEvent()
		self.manageKeyboardHideEvent()
        self.manageKeyboardChangeFrameEvent()
	}
	
	/// Must call this method on viewWillDisappear
    func stopKeyboard() {
		Keyboard.removeObservers()
	}
	
	// MARK: - Optional Public Methods
	func keyboardWillShow() {}
	func keyboardDidShow() {}
	func keyboardWillHide() {}
	func keyboardDidHide() {}
    func keyboardChangeFrame(_ size: CGSize) {}
	
	
	// MARK: - Private Helpers
    
    fileprivate func manageKeyboardChangeFrameEvent() {
        Keyboard.willChange { context in
            guard let size = context.size else {
                return LogWarn("Couldn't get keyboard size")
            }

            self.keyboardChangeFrame(size)
        }
    }
	
	fileprivate func manageKeyboardShowEvent() {
		Keyboard.willShow { context in
            guard let size = context.size else {
                return LogWarn("Couldn't get keyboard size")
            }

            self.keyboardWillShow()
            self.animateKeyboardChanges(
                duration: context.duration,
                curve: context.curve,
                changes: {
                    if let window = UIApplication.shared.activeWindow {
                        var appHeight = window.frame.height
                        if self.navigationController != nil {
                            appHeight -= self.navigationController?.navigationBar.frame.size.height ?? 0
                        }
                        let safeAreaInsetsBottomHeight = window.safeAreaInsets.bottom
                        let safeAreaInsetsTopHeight = window.safeAreaInsets.top
                        let statusBarHeight = window.windowScene?.statusBarManager?.statusBarFrame.height ?? 0
                        self.view.frame.size.height = appHeight - safeAreaInsetsBottomHeight + safeAreaInsetsTopHeight - statusBarHeight - size.height
                    }
                },
                onCompletion: {
                    self.keyboardDidShow()
                }
            )
		}
	}
	
	fileprivate func manageKeyboardHideEvent() {
		Keyboard.willHide { context in
            self.keyboardWillHide()
            self.animateKeyboardChanges(
                duration: context.duration,
                curve: context.curve,
                changes: {
                    if let window = UIApplication.shared.activeWindow {
                        var appHeight = window.frame.height
                        if self.navigationController != nil {
                            appHeight -= self.navigationController?.navigationBar.frame.size.height ?? 0
                        }
                        let statusBarHeight = window.windowScene?.statusBarManager?.statusBarFrame.height ?? 0
                        self.view.frame.size.height = appHeight - statusBarHeight
                    }
                },
                onCompletion: {
                    self.keyboardDidHide()
                }
            )
		}
	}
	
	fileprivate func animateKeyboardChanges(duration: TimeInterval, curve: UIView.AnimationOptions, changes: @escaping () -> Void, onCompletion: @escaping () -> Void) {
		UIView.animate(
			withDuration: duration,
			delay: 0,
			options: curve,
			animations: {
				changes()
				self.view.layoutIfNeeded()
			},
			completion: { _ in
				onCompletion()
			}
		)
	}
}


@MainActor
class Keyboard {

    struct KeyboardEventContext {
        let size: CGSize?
        let duration: TimeInterval
        let curve: UIView.AnimationOptions
    }
	
	fileprivate static var observers: [AnyObject] = []
	
	class func removeObservers() {
		for observer in self.observers {
			NotificationCenter.default.removeObserver(observer)
		}
		
		self.observers.removeAll()
	}
	
	class func willShow(_ notificationHandler: @escaping @Sendable @MainActor (KeyboardEventContext) -> Void) {
		self.keyboardEvent(UIResponder.keyboardWillShowNotification.rawValue, notificationHandler: notificationHandler)
	}
	
	class func didShow(_ notificationHandler: @escaping @Sendable @MainActor (KeyboardEventContext) -> Void) {
		self.keyboardEvent(UIResponder.keyboardDidShowNotification.rawValue, notificationHandler: notificationHandler)
	}
	
	class func willHide(_ notificationHandler: @escaping @Sendable @MainActor (KeyboardEventContext) -> Void) {
		self.keyboardEvent(UIResponder.keyboardWillHideNotification.rawValue, notificationHandler: notificationHandler)
	}

    class func willChange(_ notificationHandler: @escaping @Sendable @MainActor (KeyboardEventContext) -> Void) {
        self.keyboardEvent(UIResponder.keyboardWillChangeFrameNotification.rawValue, notificationHandler: notificationHandler)
    }
	
    nonisolated class func size(_ notification: Notification) -> CGSize? {
		guard
			let info = (notification as NSNotification).userInfo,
			let frame = info[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue
			else { return nil }
		
		return frame.cgRectValue.size
	}
	
	nonisolated class func animationDuration(_ notification: Notification) -> TimeInterval {
		guard
			let info = (notification as NSNotification).userInfo,
			let value = info[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber
			else {
				LogWarn("Couldn't get keyboard animation duration")
				return 0
		}
		
		return value.doubleValue
	}
	
    nonisolated class func animationCurve(_ notification: Notification) -> UIView.AnimationOptions {
		guard
			let info = (notification as NSNotification).userInfo,
            let curveInt = info[UIResponder.keyboardAnimationCurveUserInfoKey] as? Int,
            let curve = UIView.AnimationCurve(rawValue: curveInt)
			else {
				LogWarn("Couldn't get keyboard animation curve")
				return .curveEaseIn
		}
		
		return curve.toOptions()
	}
	
	
	// MARK: - Private Helpers
	
	fileprivate class func keyboardEvent(_ event: String, notificationHandler: @escaping @Sendable @MainActor (KeyboardEventContext) -> Void) {
		let observer = NotificationCenter.default
			.addObserver(
				forName: NSNotification.Name(rawValue: event),
				object: nil,
				queue: OperationQueue.main,
				using: { notification in
                    let context = KeyboardEventContext(
                        size: Keyboard.size(notification),
                        duration: Keyboard.animationDuration(notification),
                        curve: Keyboard.animationCurve(notification)
                    )
                    MainActor.assumeIsolated {
                        notificationHandler(context)
                    }
                }
		)
        
		self.observers.append(observer)
	}
	
}

extension UIView.AnimationCurve {
    func toOptions() -> UIView.AnimationOptions {
        return UIView.AnimationOptions(rawValue: UInt(rawValue << 16))
	}
}
