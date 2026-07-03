//
//  KeychainStore.swift
//  GIGLibrary
//
//  Created by Jerilyn Gonçalves on 05/03/2020.
//  Copyright © 2020 Gigigo SL. All rights reserved.
//

import Foundation
import Security
import LocalAuthentication

public final class KeychainStore {

    public var service: String {
        return self.options.service
    }

    // This attribute (kSecAttrAccessGroup) applies to macOS keychain items only if you also set a value of true for the
    // kSecUseDataProtectionKeychain key, the kSecAttrSynchronizable key, or both.
    public var accessGroup: String? {
        return self.options.accessGroup
    }

    public var accessibility: KeychainAccessibility {
        return self.options.accessibility
    }

    public var authenticationPolicy: KeychainAuthenticationPolicy? {
        return self.options.authenticationPolicy
    }

    public var synchronizable: Bool {
        return self.options.synchronizable
    }

    public var label: String? {
        return self.options.label
    }

    public var comment: String? {
        return self.options.comment
    }

    public var authenticationPrompt: String? {
        return self.options.authenticationPrompt
    }

    public var authenticationContext: LAContext? {
        return self.options.authenticationContext as? LAContext
    }

    fileprivate let options: KeychainOptions

    // MARK: Initializers

    public convenience init() {
        var options = KeychainOptions()
        if let bundleIdentifier = Bundle.main.bundleIdentifier {
            options.service = bundleIdentifier
        }
        self.init(options)
    }

    public convenience init(service: String) {
        var options = KeychainOptions()
        options.service = service
        self.init(options)
    }

    public convenience init(accessGroup: String) {
        var options = KeychainOptions()
        if let bundleIdentifier = Bundle.main.bundleIdentifier {
            options.service = bundleIdentifier
        }
        options.accessGroup = accessGroup
        self.init(options)
    }

    public convenience init(service: String, accessGroup: String) {
        var options = KeychainOptions()
        options.service = service
        options.accessGroup = accessGroup
        self.init(options)
    }

    fileprivate init(_ options: KeychainOptions) {
        self.options = options
    }

    // MARK: Accessibility

    public func accessibility(_ accessibility: KeychainAccessibility) -> KeychainStore {
        var options = self.options
        options.accessibility = accessibility
        return KeychainStore(options)
    }

    public func accessibility(_ accessibility: KeychainAccessibility, authenticationPolicy: KeychainAuthenticationPolicy) -> KeychainStore {
        var options = self.options
        options.accessibility = accessibility
        options.authenticationPolicy = authenticationPolicy
        return KeychainStore(options)
    }

    public func synchronizable(_ synchronizable: Bool) -> KeychainStore {
        var options = self.options
        options.synchronizable = synchronizable
        return KeychainStore(options)
    }

    public func label(_ label: String) -> KeychainStore {
        var options = self.options
        options.label = label
        return KeychainStore(options)
    }

    public func comment(_ comment: String) -> KeychainStore {
        var options = self.options
        options.comment = comment
        return KeychainStore(options)
    }

    public func attributes(_ attributes: [String: Any]) -> KeychainStore {
        var options = self.options
        attributes.forEach { options.attributes.updateValue($1, forKey: $0) }
        return KeychainStore(options)
    }

    public func authenticationPrompt(_ authenticationPrompt: String) -> KeychainStore {
        var options = self.options
        options.authenticationPrompt = authenticationPrompt
        return KeychainStore(options)
    }

    public func authenticationContext(_ authenticationContext: LAContext) -> KeychainStore {
        var options = self.options
        options.authenticationContext = authenticationContext
        return KeychainStore(options)
    }

    // MARK: Getters

    public func get(_ key: String, ignoringAttributeSynchronizable: Bool = true) throws -> String? {
        return try getString(key, ignoringAttributeSynchronizable: ignoringAttributeSynchronizable)
    }

    public func getString(_ key: String, ignoringAttributeSynchronizable: Bool = true) throws -> String? {
        guard let data = try getData(key, ignoringAttributeSynchronizable: ignoringAttributeSynchronizable) else { return nil }
        guard let string = String(data: data, encoding: .utf8) else {
            throw Status.conversionError
        }
        return string
    }

    public func getData(_ key: String, ignoringAttributeSynchronizable: Bool = true) throws -> Data? {
        var query = self.options.query(ignoringAttributeSynchronizable: ignoringAttributeSynchronizable)

        query[KeychainConstants.MatchLimit] = KeychainConstants.MatchLimitOne
        query[KeychainConstants.ReturnData] = kCFBooleanTrue

        query[KeychainConstants.AttributeAccount] = key

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { throw Status.unexpectedError }
            return data
        case errSecItemNotFound:
            return nil
        default:
            throw self.securityError(status: status)
        }
    }

    public func get<T>(_ key: String, ignoringAttributeSynchronizable: Bool = true, handler: (Attributes?) -> T) throws -> T {
        var query = options.query(ignoringAttributeSynchronizable: ignoringAttributeSynchronizable)

        query[KeychainConstants.MatchLimit] = KeychainConstants.MatchLimitOne

        query[KeychainConstants.ReturnData] = kCFBooleanTrue
        query[KeychainConstants.ReturnAttributes] = kCFBooleanTrue
        query[KeychainConstants.ReturnRef] = kCFBooleanTrue
        query[KeychainConstants.ReturnPersistentRef] = kCFBooleanTrue

        query[KeychainConstants.AttributeAccount] = key

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let attributes = result as? [String: Any] else { throw Status.unexpectedError }
            return handler(Attributes(attributes: attributes))
        case errSecItemNotFound:
            return handler(nil)
        default:
            throw self.securityError(status: status)
        }
    }

    // MARK: Setters
    private func interactionNotAllowedContext() -> LAContext {
        let context = LAContext()
        context.interactionNotAllowed = true
        return context
    }

    public func set(_ value: String, key: String, ignoringAttributeSynchronizable: Bool = true) throws {
        guard let data = value.data(using: .utf8, allowLossyConversion: false) else { throw Status.conversionError }
        try self.set(data, key: key, ignoringAttributeSynchronizable: ignoringAttributeSynchronizable)
    }

    public func set(_ value: Data, key: String, ignoringAttributeSynchronizable: Bool = true) throws {
        var query = self.options.query(ignoringAttributeSynchronizable: ignoringAttributeSynchronizable)
        query[KeychainConstants.AttributeAccount] = key
        query[KeychainConstants.UseAuthenticationContext] = interactionNotAllowedContext()

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        switch status {
        case errSecSuccess, errSecInteractionNotAllowed:
            if self.options.authenticationPolicy != nil && status == errSecSuccess {
                // The existing item is readable — it carries no access control — but the
                // store wants a policy. `kSecAttrAccessControl` is add-only for
                // `SecItemUpdate`, so the access control is applied by recreating the item.
                // `recreate` backs up the readable value first, so this is safe. (An item
                // that is already gated probes as `errSecInteractionNotAllowed` and falls
                // through to the in-place update below, so refreshing a protected credential
                // is NOT turned into a recreate.)
                try self.recreate(value, key: key, ignoringAttributeSynchronizable: ignoringAttributeSynchronizable)
            } else {
                // No policy, or the item is already access-control-gated
                // (`errSecInteractionNotAllowed`): update the value in place. The update
                // never carries `kSecAttrAccessControl` (it is add-only), so an existing gate
                // is preserved — refreshing a protected credential just updates its value
                // (which triggers the gate's own authentication, as it should). A plain store
                // overwriting a still-gated key can't reconcile `kSecAttrAccessible` with the
                // existing access control and surfaces the failure; drop protection with an
                // explicit `remove` + `set` (we don't auto-recreate: `SecItemUpdate` can also
                // fail with `errSecParam` for unrelated reasons, and a blind delete+add could
                // drop the credential).
                var updateQuery = self.options.query()
                updateQuery[KeychainConstants.AttributeAccount] = key

                var (attributes, error) = self.options.attributes(key: nil, value: value)
                if let error { throw error }

                self.options.attributes.forEach { attributes.updateValue($1, forKey: $0) }

                let updateStatus = SecItemUpdate(updateQuery as CFDictionary, attributes as CFDictionary)
                if updateStatus != errSecSuccess {
                    throw self.securityError(status: updateStatus)
                }
            }
        case errSecItemNotFound:
            try self.add(value, key: key)
        default:
            throw self.securityError(status: status)
        }
    }

    /// Recreates an item (delete + add) to add an access control that `SecItemUpdate`
    /// cannot apply. Only called when the existing item is readable (it has no access
    /// control yet), so its value can be backed up first.
    ///
    /// Done defensively: if the value can't be read back (the item vanished or became
    /// protected) it refuses to delete and throws `Status.interactionNotAllowed`. After
    /// deleting and re-adding, a failed re-add restores the backup with the item's
    /// ORIGINAL accessibility and synchronizable flag (and no access control, since it
    /// had none) — so a failed upgrade never leaves the credential more exposed than it
    /// was, nor lost. Custom attributes are dropped on restore so it can't fail on them.
    private func recreate(_ value: Data, key: String, ignoringAttributeSynchronizable: Bool) throws {
        guard let backup = self.backupWithoutInteraction(key, ignoringAttributeSynchronizable: ignoringAttributeSynchronizable) else {
            // Can't capture a backup (became protected/locked, or vanished) → don't delete.
            throw Status.interactionNotAllowed
        }

        try self.remove(key, ignoringAttributeSynchronizable: ignoringAttributeSynchronizable)
        do {
            try self.add(value, key: key)
        } catch {
            var restore = self.options
            restore.authenticationPolicy = nil
            restore.accessibility = backup.accessibility
            restore.synchronizable = backup.synchronizable
            restore.attributes = [:]   // drop custom attributes so the restore can't fail on them
            try? self.add(backup.data, key: key, options: restore)
            throw error
        }
    }

    /// A value plus the protection attributes needed to faithfully restore it.
    private struct ItemBackup {
        let data: Data
        let accessibility: KeychainAccessibility
        let synchronizable: Bool
    }

    /// Reads an item's data and protection attributes with a non-interactive `LAContext`,
    /// so it never surfaces an authentication UI. Returns `nil` if the item is absent or
    /// can't be read without interaction (i.e. it is access-control-gated). Used to back
    /// up a value, with its original protection, before recreating it.
    private func backupWithoutInteraction(_ key: String, ignoringAttributeSynchronizable: Bool) -> ItemBackup? {
        var query = self.options.query(ignoringAttributeSynchronizable: ignoringAttributeSynchronizable)
        query[KeychainConstants.MatchLimit] = KeychainConstants.MatchLimitOne
        query[KeychainConstants.ReturnData] = kCFBooleanTrue
        query[KeychainConstants.ReturnAttributes] = kCFBooleanTrue
        query[KeychainConstants.AttributeAccount] = key
        query[KeychainConstants.UseAuthenticationContext] = interactionNotAllowedContext()

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let attributes = result as? [String: Any],
              let data = attributes[KeychainConstants.ValueData] as? Data else { return nil }

        let accessibility = (attributes[KeychainConstants.AttributeAccessible] as? String)
            .flatMap(KeychainAccessibility.init(rawValue:)) ?? .afterFirstUnlock
        let synchronizable = (attributes[KeychainConstants.AttributeSynchronizable] as? Bool) ?? false
        return ItemBackup(data: data, accessibility: accessibility, synchronizable: synchronizable)
    }

    /// Builds the full item attributes and inserts it with `SecItemAdd`. Used for a
    /// brand-new key and to recreate an item whose protection must be (re)applied
    /// (see `recreate`), since `kSecAttrAccessControl` cannot be set via `SecItemUpdate`.
    private func add(_ value: Data, key: String) throws {
        try self.add(value, key: key, options: self.options)
    }

    private func add(_ value: Data, key: String, options: KeychainOptions) throws {
        var (attributes, error) = options.attributes(key: key, value: value)
        if let error { throw error }

        options.attributes.forEach { attributes.updateValue($1, forKey: $0) }

        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status != errSecSuccess {
            throw self.securityError(status: status)
        }
    }

    public subscript(key: String) -> String? {
        get {
            return try? self.get(key)
        }

        set {
            if let value = newValue {
                do { try self.set(value, key: key) } catch { /* subscript swallows errors */ }
            } else {
                do { try self.remove(key) } catch { /* subscript swallows errors */ }
            }
        }
    }

    public subscript(string key: String) -> String? {
        get {
            return self[key]
        }

        set {
            self[key] = newValue
        }
    }

    public subscript(data key: String) -> Data? {
        get {
            return try? self.getData(key)
        }

        set {
            if let value = newValue {
                do { try self.set(value, key: key) } catch { /* subscript swallows errors */ }
            } else {
                do { try self.remove(key) } catch { /* subscript swallows errors */ }
            }
        }
    }

    public subscript(attributes key: String) -> Attributes? {
        return try? self.get(key) { $0 }
    }

    // MARK: Deletion

    public func remove(_ key: String, ignoringAttributeSynchronizable: Bool = true) throws {
        var query = self.options.query(ignoringAttributeSynchronizable: ignoringAttributeSynchronizable)
        query[KeychainConstants.AttributeAccount] = key

        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw self.securityError(status: status)
        }
    }

    public func removeAll() throws {
        let status = SecItemDelete(self.options.query() as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw self.securityError(status: status)
        }
    }

    // MARK: Contains

    public func contains(_ key: String, withoutAuthenticationUI: Bool = false) throws -> Bool {
        var query = self.options.query()
        query[KeychainConstants.AttributeAccount] = key

        if withoutAuthenticationUI {
            query[KeychainConstants.UseAuthenticationContext] = interactionNotAllowedContext()
        }
        
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        switch status {
        case errSecSuccess:
                return true
        case errSecInteractionNotAllowed:
            if withoutAuthenticationUI {
                return true
            }
            return false
        case errSecItemNotFound:
            return false
        default:
            throw securityError(status: status)
        }
    }

    // MARK: Items

    public static func allKeys() -> [(String, String)] {
        var query = [String: Any]()
        query[KeychainConstants.Class] = KeychainConstants.ClassGenericPassword
        query[KeychainConstants.AttributeSynchronizable] = KeychainConstants.SynchronizableAny
        query[KeychainConstants.MatchLimit] = KeychainConstants.MatchLimitAll
        query[KeychainConstants.ReturnAttributes] = kCFBooleanTrue

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            if let items = result as? [[String: Any]] {
                return self.prettify(items: items).map {
                    let service = $0["service"] as? String ?? ""
                    let key = $0["key"] as? String ?? ""
                    return (service, key)
                }
            }
        case errSecItemNotFound:
            return []
        default: ()
        }

        self.securityError(status: status)
        return []
    }

    public func allKeys() -> [String] {
        let allItems = Self.prettify(items: self.items())
        let filter: ([String: Any]) -> String? = { $0["key"] as? String }

        return allItems.compactMap(filter)
    }

    public static func allItems() -> [[String: Any]] {
        var query = [String: Any]()
        query[KeychainConstants.Class] = KeychainConstants.ClassGenericPassword
        query[KeychainConstants.MatchLimit] = KeychainConstants.MatchLimitAll
        query[KeychainConstants.ReturnAttributes] = kCFBooleanTrue
        query[KeychainConstants.ReturnData] = kCFBooleanTrue

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            if let items = result as? [[String: Any]] {
                return self.prettify(items: items)
            }
        case errSecItemNotFound:
            return []
        default: ()
        }

        securityError(status: status)
        return []
    }

    public func allItems() -> [[String: Any]] {
        return Self.prettify(items: items())
    }

    // MARK: Private helpers

    fileprivate func items() -> [[String: Any]] {
        var query = self.options.query()
        query[KeychainConstants.MatchLimit] = KeychainConstants.MatchLimitAll
        query[KeychainConstants.ReturnAttributes] = kCFBooleanTrue
        query[KeychainConstants.ReturnData] = kCFBooleanTrue

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            if let items = result as? [[String: Any]] {
                return items
            }
        case errSecItemNotFound:
            return []
        default: ()
        }

        self.securityError(status: status)
        return []
    }

    fileprivate static func prettify(items: [[String: Any]]) -> [[String: Any]] {
        return items.map { attributes -> [String: Any] in
            var item = [String: Any]()

            item["class"] = KeychainConstants.ClassGenericPassword
            
            if let accessGroup = attributes[KeychainConstants.AttributeAccessGroup] as? String {
                item["accessGroup"] = accessGroup
            }

            if let service = attributes[KeychainConstants.AttributeService] as? String {
                item["service"] = service
            }

            if let key = attributes[KeychainConstants.AttributeAccount] as? String {
                item["key"] = key
            }
            if let data = attributes[KeychainConstants.ValueData] as? Data {
                if let text = String(data: data, encoding: .utf8) {
                    item["value"] = text
                } else {
                    item["value"] = data
                }
            }

            if let accessible = attributes[KeychainConstants.AttributeAccessible] as? String {
                if let accessibility = KeychainAccessibility(rawValue: accessible) {
                    item["accessibility"] = accessibility.description
                }
            }
            if let synchronizable = attributes[KeychainConstants.AttributeSynchronizable] as? Bool {
                item["synchronizable"] = synchronizable ? "true" : "false"
            }

            return item
        }
    }

    @discardableResult
    fileprivate static func securityError(status: OSStatus) -> Error {
        return Status(status: status)
    }

    @discardableResult
    fileprivate func securityError(status: OSStatus) -> Error {
        return Self.securityError(status: status)
    }
}

extension KeychainStore: CustomStringConvertible, CustomDebugStringConvertible {
    
    public var description: String {
        let items = allItems()
        if items.isEmpty {
            return "[]"
        }
        var description = "[\n"
        for item in items {
            description += "  "
            description += "\(item)\n"
        }
        description += "]"
        return description
    }

    public var debugDescription: String {
        return "\(items())"
    }
}

extension CFError {
    
    var error: NSError {
        let domain = CFErrorGetDomain(self) as String
        let code = CFErrorGetCode(self)
        let userInfo = CFErrorCopyUserInfo(self) as? [String: Any] ?? [:]

        return NSError(domain: domain, code: code, userInfo: userInfo)
    }
}
