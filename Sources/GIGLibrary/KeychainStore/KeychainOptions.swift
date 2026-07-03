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

    /// Whether the item is actually stored as synchronizable.
    ///
    /// iCloud Keychain cannot synchronize access-control (policy-gated) items
    /// nor any device-local (`...ThisDeviceOnly`) protection class — combining
    /// either with `kSecAttrSynchronizable = true` is rejected by the keychain
    /// with `errSecParam`. So a requested `synchronizable` is honored only when
    /// neither constraint applies. This is the single source of truth used for
    /// both the stored attribute (`attributes`) and strict
    /// (`ignoringAttributeSynchronizable: false`) lookups (`query`), so writes
    /// and matches stay consistent.
    var effectiveSynchronizable: Bool {
        guard self.synchronizable else { return false }
        return self.authenticationPolicy == nil && !self.accessibility.isThisDeviceOnly
    }

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
            query[KeychainConstants.AttributeSynchronizable] = self.effectiveSynchronizable ? kCFBooleanTrue : kCFBooleanFalse
        }

        if let authenticationContext = self.authenticationContext {
            query[KeychainConstants.UseAuthenticationContext] = authenticationContext
        }
        return query
    }

    func attributes(key: String?, value: Data) -> ([String: Any], Error?) {
        // `key != nil` is the add path (`SecItemAdd`): build the full item, query
        // base + account included. `key == nil` is the update path
        // (`SecItemUpdate`): build only the mutable attributes to change.
        let isAdding = key != nil

        var attributes: [String: Any]
        if isAdding {
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

        // Protection class.
        //
        // `kSecAttrAccessible` is mutable, so it is (re)written on both add and
        // update. `kSecAttrAccessControl` is add-only — `SecItemUpdate` rejects it
        // (errSecParam) — and the two are mutually exclusive, so the access control
        // is built and attached only when adding. On update the existing item's
        // access control is left in place; changing the protection policy of an
        // existing key therefore requires remove() + set().
        if let authenticationPolicy = self.authenticationPolicy {
            if isAdding {
                var accessControlError: Unmanaged<CFError>?
                let flags = SecAccessControlCreateFlags(rawValue: authenticationPolicy.rawValue)
                guard let accessControl = SecAccessControlCreateWithFlags(
                    nil,
                    self.accessibility.secAttrAccessibleValue,
                    flags,
                    &accessControlError
                ) else {
                    // Defensive: `SecAccessControlCreateWithFlags` only fails when the
                    // protection class is not a valid `kSecAttrAccessible` value, which
                    // `secAttrAccessibleValue` never produces today. Surface the
                    // `CFError` rather than silently dropping the access control if a
                    // future accessibility ever maps to an invalid value.
                    let error: Error = (accessControlError?.takeRetainedValue().error as Error?) ?? Status.unexpectedError
                    return (attributes, error)
                }
                attributes[KeychainConstants.AttributeAccessControl] = accessControl
            }
        } else {
            attributes[KeychainConstants.AttributeAccessible] = self.accessibility.secAttrAccessibleValue
        }

        // `effectiveSynchronizable` forces non-synchronizable for access-control
        // and device-local items, which the keychain refuses to synchronize
        // (errSecParam). Written here for both branches so it matches the strict
        // lookup in `query(ignoringAttributeSynchronizable: false)`.
        attributes[KeychainConstants.AttributeSynchronizable] = self.effectiveSynchronizable ? kCFBooleanTrue : kCFBooleanFalse

        return (attributes, nil)
    }
}
