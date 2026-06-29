import Foundation
import Testing
@testable import GIGLibrary

/// Tests for `ReachabilityWrapper`.
///
/// The singleton's lifecycle is driven by a live `SCNetworkReachability`, which
/// is non-deterministic and unavailable on CI, so we don't exercise the shared
/// instance end-to-end. We cover two layers instead:
/// 1. The pure decision functions (`networkStatus(for:)`, `statusChange`).
/// 2. The debounce + delegate behaviour, driven single-threaded through
///    `apply(_:)` on an injected instance (no live notifier). These assert the
///    *logic* (transitions notify, repeats debounce, weak delegate handled);
///    thread-safety is provided by the `OSAllocatedUnfairLock` and the
///    strict-concurrency build, not by these tests. The only sliver left untested
///    is the 2-line notification→status extraction in `reachabilityChanged(_:)`,
///    which requires a live `Reachability` in the posted notification.
@Suite("ReachabilityWrapper")
struct ReachabilityWrapperTests {

    private final class DelegateSpy: ReachabilityWrapperDelegate {
        private(set) var received: [NetworkStatus] = []
        func reachabilityChanged(with status: NetworkStatus) {
            received.append(status)
        }
    }

    // MARK: - connection → NetworkStatus mapping

    @Test("Given a nil reachability, when mapping the connection, then the status is .notReachable")
    func mappingNilConnection() {
        #expect(ReachabilityWrapper.networkStatus(for: nil) == .notReachable)
    }

    @Test("Given a .none connection, when mapping, then the status is .notReachable")
    func mappingNoneConnection() {
        // `Reachability.Connection.none` must be spelled out: bare `.none` would
        // resolve to `Optional.none` (i.e. `nil`) against the optional parameter.
        #expect(ReachabilityWrapper.networkStatus(for: Reachability.Connection.none) == .notReachable)
    }

    @Test("Given a cellular connection, when mapping, then the status is .reachableViaMobileData")
    func mappingCellularConnection() {
        #expect(ReachabilityWrapper.networkStatus(for: .cellular) == .reachableViaMobileData)
    }

    @Test("Given a wifi connection, when mapping, then the status is .reachableViaWiFi")
    func mappingWiFiConnection() {
        #expect(ReachabilityWrapper.networkStatus(for: .wifi) == .reachableViaWiFi)
    }

    // MARK: - change debounce (pure)

    @Test("Given the status is unchanged, when computing the change, then nil is returned so the delegate is not notified")
    func debounceSuppressesUnchangedStatus() {
        #expect(ReachabilityWrapper.statusChange(current: .notReachable, new: .notReachable) == nil)
        #expect(ReachabilityWrapper.statusChange(current: .reachableViaWiFi, new: .reachableViaWiFi) == nil)
        #expect(ReachabilityWrapper.statusChange(current: .reachableViaMobileData, new: .reachableViaMobileData) == nil)
    }

    @Test("Given the status changed, when computing the change, then the new status is returned so the delegate is notified")
    func debounceForwardsChangedStatus() {
        #expect(ReachabilityWrapper.statusChange(current: .notReachable, new: .reachableViaWiFi) == .reachableViaWiFi)
        #expect(ReachabilityWrapper.statusChange(current: .reachableViaWiFi, new: .reachableViaMobileData) == .reachableViaMobileData)
        #expect(ReachabilityWrapper.statusChange(current: .reachableViaMobileData, new: .notReachable) == .notReachable)
    }

    @Test("Given two distinct cellular readings, when mapped, then they collapse to the same status and the change is debounced")
    func debounceCollapsesSameStatusClass() {
        // Different `Reachability.Connection` readings of the same class map to a
        // single `NetworkStatus`, so the delegate must not be re-notified.
        let previous = ReachabilityWrapper.networkStatus(for: .cellular)
        let current = ReachabilityWrapper.networkStatus(for: .cellular)
        #expect(ReachabilityWrapper.statusChange(current: previous, new: current) == nil)
    }

    // MARK: - lock-backed debounce + delegate (driven through apply)

    @Test("Given a freshly injected wrapper, when apply moves to a new status, then it returns the delegate; a repeat is debounced to nil")
    func applyReturnsDelegateOnChangeAndNilWhenDebounced() {
        let wrapper = ReachabilityWrapper(reachability: nil)
        let spy = DelegateSpy()
        wrapper.delegate = spy

        // Starts at .notReachable, so the first change yields the delegate.
        #expect(wrapper.apply(.reachableViaWiFi) === spy)
        // Same status again is debounced under the lock.
        #expect(wrapper.apply(.reachableViaWiFi) == nil)
        // A further change yields the delegate once more.
        #expect(wrapper.apply(.reachableViaMobileData) === spy)
    }

    @Test("Given a sequence of readings delivered as reachabilityChanged does, then the delegate is notified only on transitions")
    func deliveringReadingsNotifiesOnlyOnTransitions() {
        let wrapper = ReachabilityWrapper(reachability: nil)
        let spy = DelegateSpy()
        wrapper.delegate = spy

        let readings: [NetworkStatus] = [
            .reachableViaWiFi,        // notReachable -> wifi: notify
            .reachableViaWiFi,        // wifi -> wifi: debounced
            .reachableViaMobileData,  // wifi -> mobile: notify
            .reachableViaMobileData,  // mobile -> mobile: debounced
            .notReachable             // mobile -> notReachable: notify
        ]
        for reading in readings {
            // Mirror reachabilityChanged(_:): apply under the lock, notify outside it.
            wrapper.apply(reading)?.reachabilityChanged(with: reading)
        }

        #expect(spy.received == [.reachableViaWiFi, .reachableViaMobileData, .notReachable])
    }

    @Test("Given no delegate is set, when apply moves to a new status, then it returns nil but still advances currentStatus so future repeats are debounced")
    func applyWithoutDelegateStillTracksStatus() {
        let wrapper = ReachabilityWrapper(reachability: nil)
        // No delegate: a real change (.notReachable -> wifi) has nothing to notify.
        #expect(wrapper.apply(.reachableViaWiFi) == nil)
        // currentStatus advanced regardless, so attaching a delegate and replaying
        // the same status is debounced — status tracking is delegate-independent.
        let spy = DelegateSpy()
        wrapper.delegate = spy
        #expect(wrapper.apply(.reachableViaWiFi) == nil)
        // A genuine change now reaches the delegate.
        #expect(wrapper.apply(.notReachable) === spy)
    }

    @Test("Given the weak delegate has been released, when apply moves to a new status, then it returns nil and does not crash")
    func applyHandlesReleasedWeakDelegate() {
        let wrapper = ReachabilityWrapper(reachability: nil)
        do {
            let spy = DelegateSpy()
            wrapper.delegate = spy
            #expect(wrapper.apply(.reachableViaWiFi) === spy)
        }
        // `spy` is deallocated at the end of the scope; the weak delegate is now
        // nil, so a further change has no delegate to return.
        #expect(wrapper.apply(.reachableViaMobileData) == nil)
    }
}
