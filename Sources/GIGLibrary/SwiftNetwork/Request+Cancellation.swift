//
//  Request+Cancellation.swift
//  GIGLibrary
//
//  Cancellation machinery for `Request`. The in-flight canceller is guarded by `Request.inFlight`
//  (an `OSAllocatedUnfairLock`), so `cancel()` is safe to call from any thread/actor concurrently
//  with the `@concurrent` fetch body that installs and clears it on a background executor.
//
//  Each fetch attempt runs inside a generation scope:
//    1. `beginCancellationScope()` opens a new generation (and cancels any still-installed prior
//       attempt, e.g. a second `fetch()` on the same instance superseding the first).
//    2. `installCanceller(_:generation:)` stores the canceller for that generation.
//    3. `clearCanceller(generation:)` clears it on completion, but only if still current.
//
//  The generation token closes two races at the root:
//    - a `cancel()` arriving *before* the canceller is installed is latched and fired on install
//      (no lost cancel across the create-Task / assign-canceller window);
//    - a stale attempt unwinding can neither clear nor be cancelled in place of a newer attempt.
//

import Foundation
import os

extension Request {

    // MARK: - Public API

    /// Cancels the in-flight network operation, if any. Safe to call from any thread/actor. If a
    /// fetch has opened its cancellation scope but not yet installed its canceller, the request is
    /// latched so the canceller fires the instant it is installed.
    public func cancel() {
        let cancel = self.inFlight.withLock { state -> (@Sendable () -> Void)? in
            state.cancelRequestedGeneration = state.generation
            let cancel = state.cancel
            state.cancel = nil
            return cancel
        }
        cancel?()
    }

    // MARK: - In-flight scope

    /// Opens a fresh cancellation scope for a new fetch attempt and returns its generation token.
    /// Cancels any canceller still installed from a previous attempt and clears the early-cancel
    /// latch so it cannot bleed into the new attempt.
    func beginCancellationScope() -> Int {
        let (prior, generation) = self.inFlight.withLock { state -> ((@Sendable () -> Void)?, Int) in
            let prior = state.cancel
            state.generation += 1
            state.cancel = nil
            state.cancelRequestedGeneration = nil
            return (prior, state.generation)
        }
        prior?()
        return generation
    }

    /// Installs the canceller for the attempt identified by `generation`. Fires it immediately
    /// instead of storing it when the attempt was already cancelled or has been superseded by a
    /// newer attempt, so neither an early `cancel()` nor an overtaken operation can leak.
    func installCanceller(_ cancel: @escaping @Sendable () -> Void, generation: Int) {
        let fireNow = self.inFlight.withLock { state -> Bool in
            guard state.generation == generation, state.cancelRequestedGeneration != generation else {
                return true
            }
            state.cancel = cancel
            return false
        }
        if fireNow { cancel() }
    }

    /// Clears the canceller once an attempt finishes, but only if it is still the current attempt.
    /// A stale attempt unwinding must never wipe a newer attempt's canceller.
    func clearCanceller(generation: Int) {
        self.inFlight.withLock { state in
            if state.generation == generation {
                state.cancel = nil
            }
        }
    }
}
