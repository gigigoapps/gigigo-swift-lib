# AGENTS

## Minimum platform
- iOS 16+.

## Swift version
- Swift 6.2.

## Concurrency approach (Approachable Concurrency)
- Prioritize modern APIs with `async/await` and concurrency-safe types.
- Avoid blocking threads; use structured tasks and proper isolation.
- Keep compatibility with iOS 16+ and document any concurrency-impacting decisions.

### Practical rules
- Prefer `async` over callbacks whenever possible.
- Use `@MainActor` when UI state or dependencies require it.
- Limit the scope of `Task` and document the reason for unstructured tasks.

## Testing style
- Apply BDD: test observable behavior rather than implementation details.
- Keep comprehensive tests that cover happy paths, errors, and relevant edges.
- Use the `Testing` framework with suites and descriptive names, following Given/When/Then.

## Code conventions
- Keep names clear, consistent, and specific.
- Prioritize readability and avoid unnecessary abbreviations.
- Document non-obvious decisions with brief, precise comments.

## Workflow (tests, commits/PRs)
- Run relevant tests before finishing changes. 
- Run tests validations only on macOS environments
- Create atomic commits with clear, descriptive messages.
- Open PRs with a concise summary and sufficient context.
