//
//  Application.swift
//  GIGLibrary
//
//  Created by Alejandro Jiménez Agudo on 9/3/16.
//  Copyright © 2016 Gigigo SL. All rights reserved.
//

import Foundation
import UIKit

@MainActor
open class Application {
	
	public init() {
		// no-op
	}
	
	
	// MARK: - App Info
	
	/// Returns the application short version
	public var appVersion: String {
		guard let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else {
			return "0.0"
		}
		
		return version
	}
	
	
	// MARK: - App Actions
	
	public func openUrl(url urlString: String) {
		guard let url = URL(string: urlString), UIApplication.shared.canOpenURL(url) else {
			return LogWarn("Can not open url: \(urlString)")
		}
		
		UIApplication.shared.open(url)
	}
	
	public func presentModal(_ viewController: UIViewController) {
		let topVC = self.topViewController()
		// Defer presentation to the next main-actor turn so callers that invoke this from
		// within a UIKit transition don't hit "present while a presentation is in progress"
		// (the original code deferred via DispatchQueue.main.async). A Task is used instead
		// of DispatchQueue.main.async so the non-Sendable view captures stay inside the
		// main-actor isolation domain and avoid a @Sendable capture warning.
		Task { @MainActor in
			topVC?.present(viewController, animated: true, completion: nil)
		}
	}
	
	
	// MARK: - Private Helpers
	
	private func topViewController() -> UIViewController? {
		let app = UIApplication.shared
		let window = app.activeWindow
		var rootVC = window?.rootViewController
		while let presentedController = rootVC?.presentedViewController {
			rootVC = presentedController
		}
		
		return rootVC
	}
	
}
