//
//  KeyboardAdaptableTests.swift
//  GIGLibrary
//
//  Regression test for C036: keyboard observers used to live in a single static
//  array shared by every KeyboardAdaptable view controller, so one screen calling
//  stopKeyboard() removed the observers of every other live screen. Observers are
//  now tied to the instance that registered them, so stopKeyboard() is selective.
//
//  Keyboard notifications are process-global, so this suite is `.serialized` to
//  avoid cross-talk with any other suite that posts keyboard notifications.
//

import UIKit
import Testing
@testable import GIGLibrary

@MainActor
final class KeyboardAdaptableTestVC: UIViewController, KeyboardAdaptable {
    private(set) var willShowCount = 0
    func keyboardWillShow() { self.willShowCount += 1 }
}

@Suite("KeyboardAdaptable", .serialized)
@MainActor
struct KeyboardAdaptableTests {

    private func postKeyboardWillShow() {
        NotificationCenter.default.post(
            name: UIResponder.keyboardWillShowNotification,
            object: nil,
            userInfo: [
                UIResponder.keyboardFrameEndUserInfoKey: NSValue(cgRect: CGRect(x: 0, y: 0, width: 320, height: 260)),
                UIResponder.keyboardAnimationDurationUserInfoKey: NSNumber(value: 0.01),
                UIResponder.keyboardAnimationCurveUserInfoKey: NSNumber(value: 0)
            ]
        )
    }

    /// Drains the main queue so notifications delivered on `OperationQueue.main`
    /// are processed before assertions run.
    private func pumpMainQueue() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }

    @Test("Given two adaptable screens, when one stops, then the other keeps receiving keyboard events")
    func stoppingOneScreenDoesNotSilenceTheOther() {
        let bottomScreen = KeyboardAdaptableTestVC()
        let topScreen = KeyboardAdaptableTestVC()
        bottomScreen.startKeyboard()
        topScreen.startKeyboard()
        defer {
            bottomScreen.stopKeyboard()
            topScreen.stopKeyboard()
        }

        self.postKeyboardWillShow()
        self.pumpMainQueue()
        #expect(bottomScreen.willShowCount == 1)
        #expect(topScreen.willShowCount == 1)

        // The top screen disappears and tears down *its* observers only.
        topScreen.stopKeyboard()

        self.postKeyboardWillShow()
        self.pumpMainQueue()
        #expect(topScreen.willShowCount == 1)      // no longer notified
        #expect(bottomScreen.willShowCount == 2)   // still notified (C036 regression)
    }

    @Test("Given a screen that stopped, when a keyboard event fires, then it is not notified")
    func stopKeyboardRemovesOwnObservers() {
        let screen = KeyboardAdaptableTestVC()
        screen.startKeyboard()

        self.postKeyboardWillShow()
        self.pumpMainQueue()
        #expect(screen.willShowCount == 1)

        screen.stopKeyboard()

        self.postKeyboardWillShow()
        self.pumpMainQueue()
        #expect(screen.willShowCount == 1)
    }
}
