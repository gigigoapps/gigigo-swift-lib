//
//  KeychainOptions.swift
//  GIGLibrary
//
//  Created by Jerilyn Gonçalves on 06/03/2020.
//  Copyright © 2020 Gigigo SL. All rights reserved.
//

import Foundation
import Security

struct KeychainOptions {
    
    var service: String = ""
    var accessGroup: String?

    var accessibility: KeychainAccessibility = .afterFirstUnlock
    var authenticationPolicy: KeychainAuthenticationPolicy?

    var synchronizable: Bool = false

    var label: String?
    var comment: String?

    var authenticationPrompt: String?
    var authenticationContext: AnyObject?

    var attributes = [String: Any]()
}


extension KeychainOptions {
    
    func query(ignoringAttributeSynchronizable: Bool = true) -> [String: Any] {
        var query = [String: Any]()

        query[KeychainConstants.Class] = KeychainConstants.ClassGenericPassword
        query[KeychainConstants.AttributeService] = self.service

        if let accessGroup = self.accessGroup {
            query[KeychainConstants.AttributeAccessGroup] = accessGroup
        }
        if ignoringAttributeSynchronizable {
            query[KeychainConstants.AttributeSynchronizable] = KeychainConstants.SynchronizableAny
        } else {
            query[KeychainConstants.AttributeSynchronizable] = self.synchronizable ? kCFBooleanTrue : kCFBooleanFalse
        }

        if let authenticationContext = self.authenticationContext {
            query[KeychainConstants.UseAuthenticationContext] = authenticationContext
        }
        return query
    }

    func attributes(key: String?, value: Data) -> ([String: Any], Error?) {
        var attributes: [String: Any]

        if key != nil {
            attributes = self.query()
            attributes[KeychainConstants.AttributeAccount] = key
        } else {
            attributes = [String: Any]()
        }

        attributes[KeychainConstants.ValueData] = value

        if let label = self.label {
            attributes[KeychainConstants.AttributeLabel] = label
        }
        if let comment = self.comment {
            attributes[KeychainConstants.AttributeComment] = comment
        }

        // Protection class. When an authentication policy is requested we build a
        // `SecAccessControl` (`kSecAttrAccessControl`); otherwise we write the
        // plain `kSecAttrAccessible` value. The two are mutually exclusive — the
        // keychain rejects an item that carries both — so we never set them
        // together.
        if let authenticationPolicy = self.authenticationPolicy {
            var accessControlError: Unmanaged<CFError>?
            let flags = SecAccessControlCreateFlags(rawValue: authenticationPolicy.rawValue)
            guard let accessControl = SecAccessControlCreateWithFlags(
                nil,
                self.accessibility.secAttrAccessibleValue,
                flags,
                &accessControlError
            ) else {
                let error: Error = (accessControlError?.takeRetainedValue().error as Error?) ?? Status.unexpectedError
                return (attributes, error)
            }
            attributes[KeychainConstants.AttributeAccessControl] = accessControl
        } else {
            attributes[KeychainConstants.AttributeAccessible] = self.accessibility.secAttrAccessibleValue
        }

        attributes[KeychainConstants.AttributeSynchronizable] = self.synchronizable ? kCFBooleanTrue : kCFBooleanFalse
        return (attributes, nil)
    }
}
