//
//  ErrorExtensionTests.swift
//  GIGLibrary
//
//  Created by Alejandro Jiménez Agudo.
//  Copyright © 2026 Gigigo SL. All rights reserved.
//

import Testing
import Foundation
@testable import GIGLibrary

@Suite("NSError+Extension")
struct ErrorExtensionTests {

    @Test("Given a nil message, no localized description key is added to userInfo")
    func nilMessageOmitsLocalizedDescription() {
        let error = NSError(domain: "com.test", code: 42, message: nil)
        #expect(error.domain == "com.test")
        #expect(error.code == 42)
        #expect(error.userInfo[NSLocalizedDescriptionKey] == nil)
    }

    @Test("Given a message, it becomes the localized description")
    func messageBecomesLocalizedDescription() {
        let error = NSError(domain: "com.test", code: 0, message: "Something failed")
        #expect(error.localizedDescription == "Something failed")
        #expect(error.userInfo[NSLocalizedDescriptionKey] as? String == "Something failed")
    }

    @Test("Given the errorWith factory, it builds an equivalent error")
    func errorWithFactoryBuildsError() {
        let error = NSError.errorWith(domain: "com.test", code: 7, message: "Boom")
        #expect(error.domain == "com.test")
        #expect(error.code == 7)
        #expect(error.localizedDescription == "Boom")
    }
}
