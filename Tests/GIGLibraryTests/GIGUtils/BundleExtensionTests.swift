//
//  BundleExtensionTests.swift
//  GIGLibrary
//
//  Created by Alejandro Jiménez Agudo.
//  Copyright © 2026 Gigigo SL. All rights reserved.
//

import Testing
import Foundation
@testable import GIGLibrary

@Suite("Bundle+Extension")
struct BundleExtensionTests {

    @Test("Given the app bundle, appVersion returns a non-empty string")
    func appVersionReturnsString() {
        #expect(!Bundle.appVersion().isEmpty)
    }

    @Test("Given the app bundle, buildVersion returns a non-empty string")
    func buildVersionReturnsString() {
        #expect(!Bundle.buildVersion().isEmpty)
    }
}
