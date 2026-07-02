//
//  Keyboard.swift
//  AppliverySDK
//
//  Created by Alejandro Jiménez on 6/3/16.
//  Copyright © 2016 Applivery S.L. All rights reserved.
//

import UIKit
import ObjectiveC.runtime

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
        // Unregister any observers from a previous startKeyboard() that was not paired
        // with a stopKeyboard(); otherwise the old tokens would be overwritten without
        // being removed, leaking those observers (and retaining self via their blocks).
        self.stopKeyboard()
        // Observers are tied to *this* instance. Previously they lived in a single
        // static array shared by every KeyboardAdaptable VC, so one screen's
        // stopKeyboard() tore down the observers of any other live screen (C036).
        self.keyboardObserverTokens = [
            self.manageKeyboardShowEvent(),
            self.manageKeyboardHideEvent(),
            self.manageKeyboardChangeFrameEvent()
        ]
	}

	/// Must call this method on viewWillDisappear
    func stopKeyboard() {
        for token in self.keyboardObserverTokens {
            NotificationCenter.default.removeObserver(token)
        }
        self.keyboardObserverTokens = []
	}
	
	// MARK: - Optional Public Methods
	func keyboardWillShow() { /* optional override */ }
	func keyboardDidShow() { /* optional override */ }
	func keyboardWillHide() { /* optional override */ }
	func keyboardDidHide() { /* optional override */ }
    func keyboardChangeFrame(_ size: CGSize) { /* optional override */ }
	
	
	// MARK: - Private Helpers

    fileprivate func manageKeyboardChangeFrameEvent() -> NSObjectProtocol {
        Keyboard.willChange { context in
            guard let size = context.size else {
                return LogWarn("Couldn't get keyboard size")
            }

            self.keyboardChangeFrame(size)
        }
    }

	fileprivate func manageKeyboardShowEvent() -> NSObjectProtocol {
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
                        // Capture the pre-keyboard height once so hide can restore it
                        // exactly, keeping show/hide symmetric across repeated cycles (C037).
                        // Assumes the view height is not changed by anything else while the
                        // keyboard is visible; a rotation / split-view resize with the keyboard
                        // up would restore the stale pre-rotation height. That is an accepted
                        // limitation for the common portrait, no-rotation-while-editing case.
                        if self.keyboardOriginalHeight == nil {
                            self.keyboardOriginalHeight = self.view.frame.size.height
                        }
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

	fileprivate func manageKeyboardHideEvent() -> NSObjectProtocol {
		Keyboard.willHide { context in
            self.keyboardWillHide()
            self.animateKeyboardChanges(
                duration: context.duration,
                curve: context.curve,
                changes: {
                    // Restore the exact height captured when the keyboard first
                    // appeared, instead of recomputing an approximation that drifts (C037).
                    if let originalHeight = self.keyboardOriginalHeight {
                        self.view.frame.size.height = originalHeight
                        self.keyboardOriginalHeight = nil
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

    // MARK: - Per-instance state (associated objects)

    private var keyboardObserverTokens: [NSObjectProtocol] {
        get { objc_getAssociatedObject(self, &KeyboardAssociatedKeys.tokens) as? [NSObjectProtocol] ?? [] }
        set { objc_setAssociatedObject(self, &KeyboardAssociatedKeys.tokens, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    private var keyboardOriginalHeight: CGFloat? {
        get { (objc_getAssociatedObject(self, &KeyboardAssociatedKeys.originalHeight) as? NSNumber).map { CGFloat($0.doubleValue) } }
        set { objc_setAssociatedObject(self, &KeyboardAssociatedKeys.originalHeight, newValue.map { NSNumber(value: Double($0)) }, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
}

private enum KeyboardAssociatedKeys {
    // Only the addresses of these statics are used, as opaque associated-object keys;
    // their values are never read or written, so `nonisolated(unsafe)` is safe.
    nonisolated(unsafe) static var tokens: UInt8 = 0
    nonisolated(unsafe) static var originalHeight: UInt8 = 0
}


@MainActor
class Keyboard {

    struct KeyboardEventContext {
        let size: CGSize?
        let duration: TimeInterval
        let curve: UIView.AnimationOptions
    }
	
	@discardableResult
	class func willShow(_ notificationHandler: @escaping @Sendable @MainActor (KeyboardEventContext) -> Void) -> NSObjectProtocol {
		self.keyboardEvent(UIResponder.keyboardWillShowNotification.rawValue, notificationHandler: notificationHandler)
	}

	@discardableResult
	class func didShow(_ notificationHandler: @escaping @Sendable @MainActor (KeyboardEventContext) -> Void) -> NSObjectProtocol {
		self.keyboardEvent(UIResponder.keyboardDidShowNotification.rawValue, notificationHandler: notificationHandler)
	}

	@discardableResult
	class func willHide(_ notificationHandler: @escaping @Sendable @MainActor (KeyboardEventContext) -> Void) -> NSObjectProtocol {
		self.keyboardEvent(UIResponder.keyboardWillHideNotification.rawValue, notificationHandler: notificationHandler)
	}

	@discardableResult
    class func willChange(_ notificationHandler: @escaping @Sendable @MainActor (KeyboardEventContext) -> Void) -> NSObjectProtocol {
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
	
	fileprivate class func keyboardEvent(_ event: String, notificationHandler: @escaping @Sendable @MainActor (KeyboardEventContext) -> Void) -> NSObjectProtocol {
		return NotificationCenter.default
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
	}
	
}

extension UIView.AnimationCurve {
    func toOptions() -> UIView.AnimationOptions {
        return UIView.AnimationOptions(rawValue: UInt(rawValue << 16))
	}
}
