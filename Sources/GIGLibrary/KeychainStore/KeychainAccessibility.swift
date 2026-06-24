//
//  KeychainAccessibility.swift
//  GIGLibrary
//
//  Created by Jerilyn Gonçalves on 06/03/2020.
//  Copyright © 2020 Gigigo SL. All rights reserved.
//

import Foundation

public enum KeychainAccessibility {
    /**
     Item data can only be accessed
     while the device is unlocked. This is recommended for items that only
     need be accesible while the application is in the foreground. Items
     with this attribute will migrate to a new device when using encrypted
     backups.
     */
    case whenUnlocked

    /**
     Item data can only be
     accessed once the device has been unlocked after a restart. This is
     recommended for items that need to be accesible by background
     applications. Items with this attribute will migrate to a new device
     when using encrypted backups.
     */
    case afterFirstUnlock

    /**
     Item data can always be accessed
     regardless of the lock state of the device. This is not recommended
     for anything except system use. Items with this attribute will migrate
     to a new device when using encrypted backups.
     */
    case always

    /**
     Item data can only
     be accessed while the device is unlocked. This is recommended for items
     that only need be accesible while the application is in the foreground.
     Items with this attribute will never migrate to a new device, so after
     a backup is restored to a new device, these items will be missing.
     */
    case whenUnlockedThisDeviceOnly

    /**
     Item data can
     only be accessed once the device has been unlocked after a restart.
     This is recommended for items that need to be accessible by background
     applications. Items with this attribute will never migrate to a new
     device, so after a backup is restored to a new device these items will
     be missing.
     */
    case afterFirstUnlockThisDeviceOnly

    /**
     Item data can always
     be accessed regardless of the lock state of the device. This option
     is not recommended for anything except system use. Items with this
     attribute will never migrate to a new device, so after a backup is
     restored to a new device, these items will be missing.
     */
    case alwaysThisDeviceOnly

    /**
     Item data can only be accessed while the device is unlocked. Available only
     when a passcode is set on the device. This is the highest-security option,
     recommended for items that need protection by the device passcode (and,
     combined with an `authenticationPolicy`, by biometrics).

     - Important: This accessibility requires a device passcode. Writing an item
       with it while no passcode is set fails (the Security framework returns an
       error). The item never migrates to another device, and it is **deleted**
       if the user removes the device passcode.
     */
    case whenPasscodeSetThisDeviceOnly
}

extension KeychainAccessibility: RawRepresentable, CustomStringConvertible {

    private static let accessibleAlwaysValue = "dk"
    private static let accessibleAlwaysThisDeviceOnlyValue = "dku"
    
    public init?(rawValue: String) {
        switch rawValue {
        case String(kSecAttrAccessibleWhenUnlocked):
            self = .whenUnlocked
        case String(kSecAttrAccessibleAfterFirstUnlock):
            self = .afterFirstUnlock
        case KeychainAccessibility.accessibleAlwaysValue:
            self = .always
        case String(kSecAttrAccessibleWhenUnlockedThisDeviceOnly):
            self = .whenUnlockedThisDeviceOnly
        case String(kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly):
            self = .afterFirstUnlockThisDeviceOnly
        case KeychainAccessibility.accessibleAlwaysThisDeviceOnlyValue:
            self = .alwaysThisDeviceOnly
        case String(kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly):
            self = .whenPasscodeSetThisDeviceOnly
        default:
            return nil
        }
    }

    public var rawValue: String {
        switch self {
        case .whenUnlocked:
            return String(kSecAttrAccessibleWhenUnlocked)
        case .afterFirstUnlock:
            return String(kSecAttrAccessibleAfterFirstUnlock)
        case .always:
            return KeychainAccessibility.accessibleAlwaysValue
        case .whenUnlockedThisDeviceOnly:
            return String(kSecAttrAccessibleWhenUnlockedThisDeviceOnly)
        case .afterFirstUnlockThisDeviceOnly:
            return String(kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly)
        case .alwaysThisDeviceOnly:
            return KeychainAccessibility.accessibleAlwaysThisDeviceOnlyValue
        case .whenPasscodeSetThisDeviceOnly:
            return String(kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly)
        }
    }

    public var description: String {
        switch self {
        case .whenUnlocked:
            return "WhenUnlocked"
        case .afterFirstUnlock:
            return "AfterFirstUnlock"
        case .always:
            return "Always"
        case .whenUnlockedThisDeviceOnly:
            return "WhenUnlockedThisDeviceOnly"
        case .afterFirstUnlockThisDeviceOnly:
            return "AfterFirstUnlockThisDeviceOnly"
        case .alwaysThisDeviceOnly:
            return "AlwaysThisDeviceOnly"
        case .whenPasscodeSetThisDeviceOnly:
            return "WhenPasscodeSetThisDeviceOnly"
        }
    }
}

extension KeychainAccessibility {

    /// The `kSecAttrAccessible` value to hand to the Security framework when
    /// writing an item (either directly as `kSecAttrAccessible` or as the
    /// protection class of a `SecAccessControl`).
    ///
    /// This is intentionally separate from `rawValue`: `rawValue` is a stable
    /// identifier used for round-tripping and `description`, whereas this is the
    /// concrete `CFString` the keychain accepts.
    ///
    /// - Note: `.always` and `.alwaysThisDeviceOnly` map to their
    ///   `afterFirstUnlock` equivalents. The `kSecAttrAccessibleAlways` /
    ///   `kSecAttrAccessibleAlwaysThisDeviceOnly` constants have been deprecated
    ///   since iOS 12 and are rejected by the keychain on this library's
    ///   minimum target (iOS 16) — their `rawValue`s (`"dk"` / `"dku"`) are not
    ///   even valid `kSecAttrAccessible` values. `afterFirstUnlock` is Apple's
    ///   recommended replacement (data is available for background use after the
    ///   first unlock following a restart).
    var secAttrAccessibleValue: CFString {
        switch self {
        case .whenUnlocked:
            return kSecAttrAccessibleWhenUnlocked
        case .afterFirstUnlock, .always:
            return kSecAttrAccessibleAfterFirstUnlock
        case .whenUnlockedThisDeviceOnly:
            return kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        case .afterFirstUnlockThisDeviceOnly, .alwaysThisDeviceOnly:
            return kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        case .whenPasscodeSetThisDeviceOnly:
            return kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly
        }
    }
}
