//
//  UIApplication+Window.swift
//  GIGLibrary
//
//  Created by Alejandro Jiménez Agudo on 2025-09-14
//  Copyright © 2025 Gigigo. All rights reserved.
//

import UIKit

extension UIApplication {
    var activeWindow: UIWindow? {
        let activeScenes = connectedScenes
            .filter { $0.activationState == .foregroundActive }
            .compactMap { $0 as? UIWindowScene }
        let activeWindows = activeScenes.flatMap(\.windows)
        if let window = activeWindows.first(where: \.isKeyWindow) ?? activeWindows.first {
            return window
        }

        let windows = connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        return windows.first(where: \.isKeyWindow) ?? windows.first
    }
}
