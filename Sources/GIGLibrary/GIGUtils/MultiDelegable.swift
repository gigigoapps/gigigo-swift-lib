//
//  MultiDelegable.swift
//  GIGLibrary
//
//  Created by Jerilyn Goncalves on 16/11/2017.
//  Copyright © 2017 Gigigo SL. All rights reserved.
//

import Foundation

/// Protocol for enabling multiple delegation, forwarding delegate messages to
/// multiple objects instead of being restricted to a single delegate object.
///
/// - Important: This protocol is `@MainActor`-isolated. All observer bookkeeping
///   (`add`/`remove`/`execute`) and the backing `observers` array are confined to
///   the main actor, which removes the data race that a shared, unsynchronised
///   array would otherwise expose (C022). Conform from main-actor types (typically
///   UI delegates). This is source-breaking for conformers that previously mutated
///   observers off the main thread.
@MainActor
public protocol MultiDelegable: AnyObject {

    /// Delegate type
    associatedtype Observer
    /// Subscribed delegate objects
    var observers: [WeakWrapper] { get set }
}

public extension MultiDelegable {

    /// Subscribes an object to the delegate messages.
    /// - parameters:
    ///     - observer: Delegate object to add as observer.
    func add(observer: Observer) {
        let object = observer as AnyObject
        let identifier = ObjectIdentifier(object)
        // Drop any dead wrappers and any existing wrapper for this exact object,
        // then append. Identity is compared via `ObjectIdentifier`, which is unique
        // and stable per object — unlike `hashValue`, which can collide and is
        // randomised per process run (C058).
        self.observers.removeAll { $0.value == nil || $0.objectIdentifier == identifier }
        self.observers.append(WeakWrapper(value: object))
    }

    /// Unsubscribes an object to the delegate messages.
    /// - parameters:
    ///     - observer: Delegate object to remove as observer.
    func remove(observer: Observer) {
        let identifier = ObjectIdentifier(observer as AnyObject)
        // Remove the wrapper matching this object's identity, and purge dead ones.
        self.observers.removeAll { $0.value == nil || $0.objectIdentifier == identifier }
    }

    /// Executes a delegate method.
    /// - parameters:
    ///     - selector: Selector reference to delegate method.
    func execute(_ selector: (Observer) -> Void) {
        for observer in self.observers {
            if let weak = observer.value as? Observer {
                selector(weak)
            }
        }
        // Purge wrappers whose referent has been deallocated so the array does not
        // grow unbounded with dead entries (C022).
        self.observers.removeAll { $0.value == nil }
    }
}

/// Class with workaround for declaring arrays with `weak` references.
public class WeakWrapper {
    public weak var value: AnyObject?
    /// Identity captured at construction time. Kept even after `value` is
    /// deallocated so it can never resolve to a bogus/empty identifier (C058).
    let objectIdentifier: ObjectIdentifier

    init(value: AnyObject) {
        self.value = value
        self.objectIdentifier = ObjectIdentifier(value)
    }
}
