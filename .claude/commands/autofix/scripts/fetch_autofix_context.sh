#!/usr/bin/env bash
# Fetch auto-fix context for the current branch's LOCAL changes.
#
# Emits the diff of LOCAL work — committed AND uncommitted — against the
# merge-base with the destination branch. That is what lets the /autofix loop
# re-review after applying fixes without pushing.
#
# Resolves: current branch → base branch → merge-base(<base>, HEAD) →
# diff(merge-base .. working tree) + repo rules. Emits one block on stdout that
# the caller pastes into the ios-pr-reviewer subagent brief.
#
# - No remote/PR dependency: /autofix must work before a PR even exists.
# - Refuses to run on protected branches (develop/master/main/release/*/hotfix/*).
# - Auto-detects the base branch the current branch forked from (develop, master,
#   release/* or hotfix/*) instead of assuming develop — during a release, feature
#   branches are often cut from release/vX.Y.Z, and develop can be 90+ commits
#   ahead, which would otherwise inflate the diff. Override with an explicit arg.
# - Errors out clearly when there are no local changes to review.
# - Captures uncommitted changes (staged + unstaged) so each loop round sees the
#   fixes the main session just applied.
#
# Usage: fetch_autofix_context.sh [base-ref]
#   base-ref: optional. When omitted, the nearest fork point among
#             origin/{develop,master,release/*,hotfix/*} is chosen automatically.

set -euo pipefail

# Anchor to the repo root so the `.claude/rules/` glob and git invocations work
# regardless of the caller's current working directory.
REPO_ROOT=$(git rev-parse --show-toplevel)
cd "$REPO_ROOT"

EXPLICIT_BASE="${1:-}"

CURRENT=$(git rev-parse --abbrev-ref HEAD)
PROTECTED='^(develop|master|main|release/.*|hotfix/.*)$'
if [[ "$CURRENT" =~ $PROTECTED ]]; then
  echo "ERROR: current branch '$CURRENT' is protected; refusing to autofix." >&2
  echo "Check out a feature/* or bugfix/* branch with local changes." >&2
  exit 1
fi

# Refresh remote refs so base branches reflect the truth. Don't abort on failure —
# a stale base still allows reviewing local work; we surface the staleness instead.
# The http.lowSpeed* bounds turn a stalled connection (dead/blocked network) into a
# fast non-zero exit instead of an indefinite hang, so the `|| WARNING` path can
# actually kick in and the autofix loop never blocks on the network.
if ! git -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=15 fetch --prune origin >/dev/null 2>&1; then
  echo "WARNING: 'git fetch origin' failed or timed out; base refs may be stale." >&2
fi

# Resolve the base ref. An explicit arg wins; otherwise auto-detect the base
# branch the current branch forked from by picking the candidate whose fork point
# (merge-base) is closest to HEAD — i.e. the one HEAD diverged from most recently.
# This distinguishes a develop-based branch from a release/hotfix-based one even
# when develop and release have diverged.
BASE_REF=""
BASE_SOURCE=""
if [[ -n "$EXPLICIT_BASE" ]]; then
  BASE_REF="$EXPLICIT_BASE"
  BASE_SOURCE="explicit argument"
  if ! git rev-parse --verify --quiet "$BASE_REF" >/dev/null; then
    echo "ERROR: base ref '$BASE_REF' not found locally; run 'git fetch origin' and retry." >&2
    exit 1
  fi
else
  # Candidate base branches in priority order (develop/master first so they win
  # ties at a shared fork point), then every release/* and hotfix/* train.
  CANDIDATES=$(
    {
      for r in origin/develop origin/master; do
        git rev-parse --verify --quiet "$r" >/dev/null 2>&1 && printf '%s\n' "$r"
      done
      git for-each-ref --format='%(refname:short)' \
        'refs/remotes/origin/release/*' 'refs/remotes/origin/hotfix/*' 2>/dev/null
    }
  )
  BEST_AHEAD=""
  for cand in $CANDIDATES; do
    mb=$(git merge-base "$cand" HEAD 2>/dev/null) || continue
    ahead=$(git rev-list --count "$mb..HEAD" 2>/dev/null) || continue
    if [[ -z "$BEST_AHEAD" ]] || (( ahead < BEST_AHEAD )); then
      BEST_AHEAD="$ahead"
      BASE_REF="$cand"
    fi
  done
  if [[ -z "$BASE_REF" ]]; then
    echo "ERROR: could not auto-detect a base branch." >&2
    echo "No origin/develop, origin/master, origin/release/* or origin/hotfix/* found." >&2
    echo "Pass an explicit base: fetch_autofix_context.sh <base-ref>" >&2
    exit 1
  fi
  BASE_SOURCE="auto-detected (fork point ${BEST_AHEAD:-?} commits ahead of base)"
fi

MERGE_BASE=$(git merge-base "$BASE_REF" HEAD) || {
  echo "ERROR: could not compute merge-base between '$BASE_REF' and HEAD." >&2
  exit 1
}

# Diff the merge-base against the WORKING TREE (no '..HEAD'), so committed,
# staged and unstaged changes of tracked files are all captured. This is the
# bulk of "estos cambios".
DIFF=$(git diff "$MERGE_BASE")

# Untracked new files don't appear in `git diff`, but on a pre-PR branch they're
# often the most important thing to review. Append each as an additions-only
# diff via `git diff --no-index` — this is read-only (it never touches the
# index, so the user's staging area is left untouched). `--no-index` exits 1
# when a difference exists (the normal case); a status >1 is a genuine error
# (unreadable file, etc.), which we surface on stderr instead of swallowing.
UNTRACKED=$(git ls-files --others --exclude-standard)
if [[ -n "$UNTRACKED" ]]; then
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    if out=$(git diff --no-index -- /dev/null "$f" 2>/dev/null); then
      rc=0
    else
      rc=$?
    fi
    if (( rc > 1 )); then
      echo "WARNING: could not diff untracked file '$f' (git exit $rc); omitted from brief." >&2
    fi
    DIFF+=$'\n'"$out"
  done <<< "$UNTRACKED"
fi

if [[ -z "${DIFF//[$'\n\t ']/}" ]]; then
  echo "ERROR: no local changes to review against '$BASE_REF' (merge-base ${MERGE_BASE:0:12})." >&2
  echo "Make changes on a feature/bugfix branch before running /autofix." >&2
  exit 1
fi

# Diagnostic counts for the brief header. Uncommitted state is expected and
# desirable here (the loop fixes locally before any push), so it's informational.
COMMITS=$(git log --oneline "$MERGE_BASE..HEAD" 2>/dev/null || true)
DIRTY=$(git status --short)

# Emit the brief on stdout. The caller (the skill) feeds this verbatim into the
# ios-pr-reviewer subagent prompt.
cat <<'EOF'
# Autofix Context

## Metadata
EOF
printf -- '- Current branch: %s\n- Base ref: %s (%s)\n- Merge-base: %s\n' \
    "$CURRENT" "$BASE_REF" "$BASE_SOURCE" "$MERGE_BASE"
echo ""
echo "## Local state"
echo ""
if [[ -n "$COMMITS" ]]; then
  echo "Commits on this branch since the base:"
  printf '%s\n' "$COMMITS" | sed 's/^/    /'
else
  echo "No commits since the base — all changes are uncommitted."
fi
if [[ -n "$DIRTY" ]]; then
  echo "Uncommitted working-tree changes (included in the diff below):"
  printf '%s\n' "$DIRTY" | sed 's/^/    /'
else
  echo "Working tree is clean — the diff below is committed work only."
fi

echo ""
echo "## Repo rules"
echo ""
for f in .claude/rules/*.md; do
  [[ -f "$f" ]] || continue
  echo "### $(basename "$f")"
  echo ""
  cat "$f"
  echo ""
done

echo ""
echo "## Diff (merge-base of $BASE_REF..HEAD → working tree)"
echo ""
DIFF_LINES=$(printf '%s\n' "$DIFF" | wc -l | tr -d ' ')
if (( DIFF_LINES > 5000 )); then
  echo "WARNING: diff is $DIFF_LINES lines — may exceed the subagent context budget; consider chunked review." >&2
fi
printf '%s\n' "$DIFF"
