//
//  MultiDelegable.swift
//  GIGLibrary
//
//  Created by Jerilyn Goncalves on 16/11/2017.
//  Copyright © 2017 Gigigo SL. All rights reserved.
//

import Foundation

//// Protocol for enabling multiple delegation, forwarding delegate messages to multiple objects instead of being restricted to a single delegate object.
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
        let identifier = String(ObjectIdentifier(observer as AnyObject).hashValue)
        if !self.observers.contains(where: { $0.identifier() == identifier }) {
            self.observers.append(WeakWrapper(value: observer as AnyObject))
        } else {
            self.remove(observer: observer)
            self.observers.append(WeakWrapper(value: observer as AnyObject))
        }
    }
    
    /// Unsubscribes an object to the delegate messages.
    /// - parameters:
    ///     - observer: Delegate object to add as observer.
    func remove(observer: Observer) {
        let identifier = String(ObjectIdentifier(observer as AnyObject).hashValue)
        if let index = self.observers.firstIndex(where: { $0.identifier() == identifier }) {
            self.observers.remove(at: index)
        }
        self.observers = self.observers.compactMap({ $0.value != nil ? $0 : nil }) // Remove nil objects
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
    }
}

/// Class with workaround for declaring arramappys with `weak` references
public class WeakWrapper {
    public weak var value: AnyObject?
    
    init(value: AnyObject) {
        self.value = value
    }
    
    func identifier() -> String {
        if let value = self.value {
            return String(ObjectIdentifier(value).hashValue)
        }
        return ""
    }
}
