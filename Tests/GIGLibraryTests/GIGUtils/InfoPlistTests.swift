//
//  InfoPlistTests.swift
//  GIGLibrary
//
//  Created by Alejandro Jiménez Agudo.
//  Copyright © 2026 Gigigo SL. All rights reserved.
//

import Testing
import Foundation
@testable import GIGLibrary

@Suite("InfoPlist")
struct InfoPlistTests {

    @Test("Given an absent key, infoDictionary returns nil so absence is representable")
    func absentKeyReturnsNil() {
        let value = infoDictionary("com.gigigo.definitely.not.a.real.info.plist.key")
        #expect(value == nil)
    }

    @Test("Given a present String key, infoDictionary returns its value")
    func presentKeyReturnsValue() {
        // `CFBundleInfoDictionaryVersion` is present in every bundle's Info.plist,
        // including the xctest runner that backs `Bundle.main` during tests.
        let value = infoDictionary("CFBundleInfoDictionaryVersion")
        #expect(value != nil)
        #expect(value?.isEmpty == false)
    }
}
