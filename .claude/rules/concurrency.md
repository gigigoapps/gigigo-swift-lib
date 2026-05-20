# Concurrency

Swift 6.2 with `StrictConcurrency` and `ApproachableConcurrency` enabled. All new code must compile warning-free under these settings.

## Rules

- **Prefer `async/await`** over completion handlers for all new code
- Use `@MainActor` for any code accessing UI state, `UIScreen`, or UIKit components
- Annotate closures and types with `@Sendable` / `Sendable` when crossing concurrency boundaries
- Limit unstructured `Task { }` usage; document any that exist with a comment explaining why structured concurrency is not possible
- Do not use `@unchecked Sendable` lightly — only where isolation is guaranteed by design (e.g., `Response` which is always written before crossing a boundary)

## Async method annotation

Public async methods use `@concurrent` to opt into unstructured execution:

```swift
@concurrent
public func fetch() async -> Response { ... }
```

## Cancellation

Support `Task` cancellation via `withTaskCancellationHandler`. Check `Task.isCancelled` before starting expensive work.

## GCD

GCD helpers in `Dispatch.swift` are annotated `@Sendable`. Prefer `async/await` over `DispatchQueue.async` in new code.
