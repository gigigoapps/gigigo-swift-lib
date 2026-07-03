---
description: Auto-fix the current branch's LOCAL changes in a review→fix→re-review loop. Each round a fresh `ios-pr-reviewer` subagent reviews the local diff (committed + uncommitted) in isolation; the main session applies the actionable fixes; then a brand-new subagent re-reviews the corrected tree — so it isn't anchored on the first findings and can surface new ones. Repeats until a clean review, then validates with the GIGLibrary test suite (xcodebuild) and SwiftLint. Nothing is pushed, published, or merged. Use when asked to "autofix", "corrige los cambios", "arregla la rama", or to clean up a branch before opening/updating a PR.
---

# Autofix

## Overview

Self-correction loop for the current branch's **local** changes, before opening or updating a PR. Each round spins up a **fresh** `ios-pr-reviewer` subagent that reviews the local diff (committed + uncommitted) in isolation — it doesn't see this conversation or the previous round's findings. The main session applies the actionable fixes, then a **new** subagent re-reviews the corrected tree.

The fresh-subagent-per-round design is the whole point: a reviewer that carried over its earlier findings would keep relitigating them and stay anchored on the first batch. A clean-context reviewer judges the current state from scratch, so fixes introduced this round (and any new issues they create) get caught. The loop ends when a fresh review finds nothing, then the test suite and SwiftLint confirm the fixes didn't break anything.

## When to use

- The user asks to "autofix", "corrige los cambios", "arregla la rama", or similar on the current branch.
- Before opening or updating a PR, to autonomously clear obvious issues with the same rigor a teammate would apply.

## Workflow

The loop is driven by **this** session with sequential `Agent` calls — each call is a fresh subagent with no carry-over. The reviewer is read-only; the main session applies every fix.

### 0. Pre-flight

Run the context script once to confirm the branch is valid and there are changes:

```bash
./.claude/commands/autofix/scripts/fetch_autofix_context.sh
```

The script anchors to the repo root, refuses protected branches (`develop|master|main|release/*|hotfix/*`), **auto-detects the base branch** the current branch forked from (the nearest fork point among `origin/{develop,master,release/*,hotfix/*}` — so a branch cut from `release/vX.Y.Z` is diffed against release, not develop), and emits a single block on stdout: branch metadata (including which base was chosen), local-state notes, the repo rules from `.claude/rules/*.md`, and the diff of `merge-base(<base>, HEAD)` against the **working tree** (so committed + staged + unstaged changes are all included). Override the base with a positional arg. It errors out clearly on a protected branch, an unresolvable base, or no local changes.

**On any non-zero exit, surface stderr to the user and stop** — do not launch a subagent with partial/empty stdout.

### 1. Review → fix loop (`MAX_ROUNDS = 6`)

For each round:

a. **Regenerate context.** Re-run `fetch_autofix_context.sh` so the diff reflects fixes already applied. Verify it exited 0; on failure, surface stderr and stop.

b. **Launch one fresh reviewer.** Make a single `Agent` call to `ios-pr-reviewer` (a new call = clean context, satisfying "subagente limpio"). Pass the script's stdout verbatim, prefixed with:

   > Review of LOCAL pre-PR changes (committed + uncommitted) on the author's working branch. The author wants issues found and fixed before opening/updating the PR.
   >
   > Adapt your standard PR-review heuristics to the file types in the diff (Swift 6 concurrency/architecture/style/tests, Bash correctness/quoting, Markdown/docs clarity, etc.). Report findings by severity (**blocker** / **nit**), each citing `file:line` against the diff, naming what is wrong and proposing a concrete fix.
   >
   > **Do NOT edit any files. Do NOT push, open a PR, or publish anything.** Return findings to me as text only — the calling session will apply the fixes.
   >
   > If there are no findings, say so explicitly.

c. **Clean review → exit the loop** and go to validation.

d. **Otherwise apply the actionable fixes** in this session (Edit/Write) on the working tree: blockers and concrete nits. Findings that are subjective, risky, or out of scope (behavior change beyond the diff's intent) — record them for the summary, do **not** apply them.

e. **Anti-loop guards:**
   - If a round applies **0 fixes** (only non-actionable findings remain) → exit the loop and report them.
   - If the same `file:line`/finding reappears after an attempted fix → mark it "unresolved", stop retrying it, and report it.
   - If `MAX_ROUNDS` is reached → stop and report the still-open findings.

### 2. Final validation

`swift build` / `swift test` do **not** work here (they pull in UIKit). Validate with xcodebuild against the iOS simulator and SwiftLint:

```bash
xcodebuild -scheme GIGLibrary -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' test
swiftlint
```

Also build **Release** once — some `StrictConcurrency` warnings only surface in Release, not in the incremental Debug build:

```bash
xcodebuild -scheme GIGLibrary -configuration Release -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' build
```

If tests, SwiftLint, or the Release build fail, triage and fix; after fixing, run **one** more fresh review round so the fix is itself reviewed, then re-run the checks. Report the final outcome.

### 3. Summary

Report to the user: number of rounds, fixes applied (with `file:line`), findings deferred and why, any unresolved findings, and the test / lint / Release-build result.

## Guarantees

- **Local only.** No push, no PR, no merge. All changes stay in the working tree for the user to commit.
- **Fresh subagent per round.** Each review is a new `Agent` call with no history — it judges the current tree from scratch, removing both author-bias and first-findings anchoring.
- **Reviewer is read-only.** The subagent only reports; this session applies every fix.
- **Protected branches are refused.** The script exits early on `develop`/`master`/`main`/`release/*`/`hotfix/*`.
- **Bounded.** At most `MAX_ROUNDS` review rounds, with 0-fix and recurring-finding guards to prevent infinite loops or oscillation.

## Notes

- Requires the project-scoped `ios-pr-reviewer` subagent (`.claude/agents/ios-pr-reviewer.md`). If it isn't resolvable in the current checkout/worktree, the loop can't run.
- The base branch is auto-detected (nearest fork point among `origin/{develop,master,release/*,hotfix/*}`), so it stays correct whether the branch was cut from develop, a release, or a hotfix. The chosen base is shown in the brief's metadata. For a **chained** branch targeting another feature, pass it explicitly: `fetch_autofix_context.sh origin/feature/parent`.
- The diff intentionally includes uncommitted changes — that's how each round sees the fixes just applied. The user commits when satisfied.
- The test suite is fast here (the whole `GIGLibraryTests` run is sub-second once built), so validating once after a clean review is cheap. The build itself dominates the time.
- CI (`.github/workflows/ci.yml`, `macos-latest`, Xcode ≥ 26, iPhone 17 Pro) runs the same test suite on push/PR to `main`/`master`/`develop`; SwiftLint with **0 warnings** is the expected gate, so clear lint warnings before pushing.
- If the diff exceeds ~5000 lines the script prints a warning on stderr but still emits the full diff and exits 0 (a warning, not a failure, so the loop continues). On that warning, review in chunks — re-run the script with an explicit narrower base, or split the work by directory/file — so the reviewer subagent's context budget isn't blown.
