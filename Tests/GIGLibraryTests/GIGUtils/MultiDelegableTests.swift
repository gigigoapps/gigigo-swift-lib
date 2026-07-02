//
//  MultiDelegableTests.swift
//  GIGLibrary
//
//  Regression tests for C058/C022: observer identity used to rely on
//  `String(ObjectIdentifier(...).hashValue)`, which can collide and is randomised
//  per run, and dead wrappers were only purged on `remove`. The fix stores a
//  captured `ObjectIdentifier` per wrapper and purges dead entries on `execute`.
//

import Testing
@testable import GIGLibrary

protocol MultiDelegableTestObserver: AnyObject {
    func ping()
}

@MainActor
final class MultiDelegableTestBroadcaster: MultiDelegable {
    typealias Observer = MultiDelegableTestObserver
    var observers: [WeakWrapper] = []
}

@MainActor
final class MultiDelegableTestSpy: MultiDelegableTestObserver {
    private(set) var pingCount = 0
    func ping() { self.pingCount += 1 }
}

@Suite("MultiDelegable")
@MainActor
struct MultiDelegableTests {

    @Test("Given two distinct observers, when executing, then both receive the message")
    func executeReachesAllObservers() {
        let broadcaster = MultiDelegableTestBroadcaster()
        let first = MultiDelegableTestSpy()
        let second = MultiDelegableTestSpy()

        broadcaster.add(observer: first)
        broadcaster.add(observer: second)
        broadcaster.execute { $0.ping() }

        #expect(first.pingCount == 1)
        #expect(second.pingCount == 1)
    }

    @Test("Given the same observer added twice, when executing, then it is not duplicated")
    func addingSameObserverTwiceDoesNotDuplicate() {
        let broadcaster = MultiDelegableTestBroadcaster()
        let observer = MultiDelegableTestSpy()

        broadcaster.add(observer: observer)
        broadcaster.add(observer: observer)

        #expect(broadcaster.observers.count == 1)
        broadcaster.execute { $0.ping() }
        #expect(observer.pingCount == 1)
    }

    @Test("Given two observers, when removing one, then only the target stops receiving messages")
    func removeRemovesOnlyTheTargetObserver() {
        let broadcaster = MultiDelegableTestBroadcaster()
        let kept = MultiDelegableTestSpy()
        let removed = MultiDelegableTestSpy()

        broadcaster.add(observer: kept)
        broadcaster.add(observer: removed)
        broadcaster.remove(observer: removed)
        broadcaster.execute { $0.ping() }

        #expect(kept.pingCount == 1)
        #expect(removed.pingCount == 0)
    }

    @Test("Given a deallocated observer, when executing, then its dead wrapper is purged")
    func deallocatedObserverIsPurgedOnExecute() {
        let broadcaster = MultiDelegableTestBroadcaster()
        let survivor = MultiDelegableTestSpy()

        do {
            let temporary = MultiDelegableTestSpy()
            broadcaster.add(observer: temporary)
            broadcaster.add(observer: survivor)
        }
        // `temporary` is deallocated here; its wrapper is still present until execute purges it.
        #expect(broadcaster.observers.count == 2)

        broadcaster.execute { $0.ping() }

        #expect(survivor.pingCount == 1)
        #expect(broadcaster.observers.count == 1)
    }
}
