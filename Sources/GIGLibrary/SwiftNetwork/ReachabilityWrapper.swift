//
//  ReachabilityWrapper.swift
//  WOAH
//
//  Created by Jerilyn Goncalves on 26/06/2017.
//  Copyright © 2017 Gigigo SL. All rights reserved.
//

import Foundation
import os

public enum NetworkStatus: Sendable {
    case notReachable
    case reachableViaWiFi
    case reachableViaMobileData
}

public protocol ReachabilityWrapperDelegate: AnyObject {
     func reachabilityChanged(with status: NetworkStatus)
}

public protocol ReachabilityInput {
    func isReachable() -> Bool
    func isReachableViaWiFi() -> Bool
}

/// Global reachability monitor.
///
/// `@unchecked Sendable` is justified by design and holds for *any* instance,
/// not just `shared`: every piece of *mutable* state (`delegate`,
/// `currentStatus`, `isRunning`) lives inside `state`, a per-instance
/// `OSAllocatedUnfairLock` (the same primitive that guards `Request.inFlight`),
/// and is only ever read or written while holding that lock. The `delegate`
/// accessors use `withLockUnchecked` because `ReachabilityWrapperDelegate` is
/// not `Sendable`; the lock provides the exclusion the compiler cannot verify on
/// its own. `reachability` is an immutable `let` read lock-free; the vendored
/// `Reachability.connection` getter is not synchronized (it reads a mutable
/// `allowsCellularConnection` alongside a thread-safe `SCNetworkReachabilityGetFlags`
/// query), so those reads are racy-but-benign — behaviour unchanged from before
/// this lock was introduced, and out of scope here since it is vendored code.
public class ReachabilityWrapper: ReachabilityInput, @unchecked Sendable {
    // MARK: Singleton
    public static let shared = ReachabilityWrapper()

    // MARK: Public properties

    /// The delegate notified when the network status changes. Stored behind
    /// `state`, so reads and writes are serialized across threads.
    public var delegate: ReachabilityWrapperDelegate? {
        get { state.withLockUnchecked { $0.delegate } }
        set { state.withLockUnchecked { $0.delegate = newValue } }
    }

    // MARK: Private properties

    /// All mutable state, guarded by a single lock. `delegate` is `weak` so the
    /// wrapper never keeps its observer alive.
    private struct State {
        weak var delegate: ReachabilityWrapperDelegate?
        var currentStatus: NetworkStatus = .notReachable
        var isRunning = false
    }

    private let state = OSAllocatedUnfairLock(uncheckedState: State())
    private let reachability: Reachability?

    // MARK: - Life cycle
    private init() {
        self.reachability = Reachability()
        self.startNotifier()
    }

    /// Dependency-injection seam (internal): builds an instance that does **not**
    /// start the live notifier, so the lock-backed status/delegate/debounce logic
    /// can be exercised in isolation. The shared singleton always uses `init()`.
    /// `currentStatus` deliberately starts at `.notReachable` here (unlike `init()`,
    /// which seeds it from the live connection via `startNotifier()`), giving tests
    /// a known initial state.
    init(reachability: Reachability?) {
        self.reachability = reachability
    }

    deinit {
        // Acquiring `state` here is safe: an object being deallocated has no
        // remaining references, so no other thread can contend for the lock.
        self.stopNotifier()
    }

    // MARK: - Reachability methods

    public func isReachable() -> Bool {
        return self.reachability?.connection != Reachability.Connection.none
    }

    public func isReachableViaWiFi() -> Bool {
        return self.reachability?.connection == .wifi
    }

    /// Starts (or resumes) reachability monitoring. Idempotent: a second call
    /// while already running is a no-op, so it never registers a duplicate
    /// `NotificationCenter` observer (which would double-fire `reachabilityChanged`).
    /// `init` calls this on creation; it stays `public` so callers can pause and
    /// resume monitoring (e.g. around logout/background) via `stopNotifier()` then
    /// `startNotifier()`.
    public func startNotifier() {
        // The state transition AND the observer/notifier side effects run inside a
        // single critical section, so `isRunning` can never desync from the real
        // lifecycle under concurrent start/stop calls from different queues.
        // Deadlock-safe: `Reachability` posts its notifications asynchronously (on
        // the main queue), so `reachabilityChanged(_:)` cannot re-enter this lock
        // synchronously while we hold it. These are system calls, not user code.
        state.withLockUnchecked { state in
            guard !state.isRunning else { return }
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(reachabilityChanged(_:)),
                name: .reachabilityChanged,
                object: reachability
            )
            do {
                try self.reachability?.startNotifier()
            } catch {
                // Startup failed (callback/dispatch-queue install): undo the
                // observer and stay "not running" so a later startNotifier() can
                // retry, instead of believing monitoring is live.
                NotificationCenter.default.removeObserver(self, name: .reachabilityChanged, object: reachability)
                return
            }
            state.currentStatus = self.currentNetworkStatus()
            state.isRunning = true
        }
    }

    /// Stops reachability monitoring. Idempotent counterpart to `startNotifier`;
    /// safe to call when already stopped.
    public func stopNotifier() {
        // Same single-critical-section discipline as `startNotifier`: tear down the
        // observer/notifier and flip the flag atomically.
        state.withLockUnchecked { state in
            guard state.isRunning else { return }
            NotificationCenter.default.removeObserver(
                self,
                name: .reachabilityChanged,
                object: reachability
            )
            self.reachability?.stopNotifier()
            state.isRunning = false
        }
    }

    // MARK: - Private helpers

    private func currentNetworkStatus() -> NetworkStatus {
        return Self.networkStatus(for: self.reachability?.connection)
    }

    /// Pure mapping from a `Reachability.Connection` to `NetworkStatus`.
    /// Extracted as a static, side-effect-free function so it can be unit tested
    /// without a live `SCNetworkReachability` instance.
    static func networkStatus(for connection: Reachability.Connection?) -> NetworkStatus {
        switch connection {
        case .cellular:
            return .reachableViaMobileData
        case .wifi:
            return .reachableViaWiFi
        case .some(.none), nil:
            return .notReachable
        }
    }

    /// Debounce decision: the status to broadcast when moving to `new`, or `nil`
    /// when it equals `current` (no observable change, so the delegate is not
    /// notified). Pure, so the debounce contract is unit testable on its own.
    static func statusChange(current: NetworkStatus, new: NetworkStatus) -> NetworkStatus? {
        return current == new ? nil : new
    }

    /// Applies `newStatus` under the lock and returns the delegate to notify, or
    /// `nil` when the status is unchanged (debounced). The debounce read, the
    /// `currentStatus` update and the `delegate` read happen atomically; the
    /// caller invokes the delegate *outside* the lock. Split from the
    /// notification plumbing so the lock-backed contract is unit testable without
    /// a live `Reachability`. `withLockUnchecked` because
    /// `ReachabilityWrapperDelegate` is not `Sendable`.
    func apply(_ newStatus: NetworkStatus) -> ReachabilityWrapperDelegate? {
        return state.withLockUnchecked { state -> ReachabilityWrapperDelegate? in
            guard let broadcast = Self.statusChange(current: state.currentStatus, new: newStatus) else { return nil }
            state.currentStatus = broadcast
            return state.delegate
        }
    }

    // MARK: - Reachability Change
    @objc
    func reachabilityChanged(_ notification: NSNotification) {
        guard let reachability = notification.object as? Reachability else { return }
        // `newStatus` is a snapshot of the connection at notification time. The
        // vendored `Reachability.connection` getter is unsynchronized, so we read
        // it once and debounce/broadcast against that single value rather than
        // re-reading it (which could yield a different result mid-method).
        let newStatus = Self.networkStatus(for: reachability.connection)
        self.apply(newStatus)?.reachabilityChanged(with: newStatus)
    }
}
