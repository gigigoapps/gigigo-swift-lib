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
        if #available(iOS 13.0, *) {
            let activeScenes = connectedScenes
                .filter { $0.activationState == .foregroundActive }
                .compactMap { $0 as? UIWindowScene }
            let activeWindows = activeScenes.flatMap { $0.windows }
            if let window = activeWindows.first(where: { $0.isKeyWindow }) ?? activeWindows.first {
                return window
            }

            let windows = connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
            return windows.first { $0.isKeyWindow } ?? windows.first
        }

        return keyWindow
    }
}
