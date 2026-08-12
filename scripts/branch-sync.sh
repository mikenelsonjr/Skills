#!/usr/bin/env bash
# branch-sync.sh — deterministic epic-branch bring-up across repos.
#
# Collapses generate-task Step 9 into one call: for each repo, sync the base
# branch (dev) to origin, then create or check out the epic feature branch from
# the now-current base. Never branches from a stale or diverged base — a diverged
# base is a hard STOP (exit 3), because cutting from it is this project's single
# biggest source of regressions.
#
# Usage:
#   branch-sync.sh <epic-key-slug> <repo> [repo ...]
#   e.g. branch-sync.sh feature/el-445-renewal-aptly core-api RentManagerSyncSerivce
#
# The branch name is passed verbatim (must already include the `feature/` prefix,
# matching the naming convention). Base branch is `dev` for all code repos.
#
# Output: one status line per repo, machine-parseable:
#   {repo}\tSYNCED_FF|CURRENT\tbranch=CREATED|EXISTS|BEHIND_N\t{detail}
# Exit codes:
#   0  all repos ready
#   3  at least one repo has a DIVERGED base — human must resolve; NOTHING was
#      branched for that repo. Other repos may still have succeeded (see output).
#   4  a git operation failed unexpectedly (not divergence) — see stderr.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BASE="dev"

if [ "$#" -lt 2 ]; then
  echo "usage: branch-sync.sh <epic-key-slug> <repo> [repo ...]" >&2
  exit 2
fi

BRANCH="$1"; shift
REPOS=("$@")

overall=0

for repo in "${REPOS[@]}"; do
  path="$ROOT/$repo"
  if [ ! -d "$path/.git" ]; then
    printf '%s\tERROR\tbranch=NONE\tno .git at %s\n' "$repo" "$path"
    overall=4
    continue
  fi

  # 1. Sync base to origin.
  if ! git -C "$path" fetch origin --quiet 2>/dev/null; then
    printf '%s\tERROR\tbranch=NONE\tfetch failed\n' "$repo"
    overall=4
    continue
  fi

  behind="$(git -C "$path" rev-list --count "${BASE}..origin/${BASE}" 2>/dev/null || echo ERR)"
  ahead="$(git -C "$path" rev-list --count "origin/${BASE}..${BASE}" 2>/dev/null || echo ERR)"
  if [ "$behind" = "ERR" ] || [ "$ahead" = "ERR" ]; then
    printf '%s\tERROR\tbranch=NONE\tcannot compare %s to origin/%s\n' "$repo" "$BASE" "$BASE"
    overall=4
    continue
  fi

  if [ "$behind" -gt 0 ] && [ "$ahead" -gt 0 ]; then
    # Diverged base — hard STOP for this repo. Do not branch.
    printf '%s\tDIVERGED\tbranch=SKIPPED\tlocal %s is %s behind and %s ahead of origin/%s — resolve manually before branching\n' \
      "$repo" "$BASE" "$behind" "$ahead" "$BASE"
    overall=3
    continue
  fi

  sync="CURRENT"
  if [ "$behind" -gt 0 ]; then
    if ! git -C "$path" checkout "$BASE" --quiet 2>/dev/null || \
       ! git -C "$path" merge --ff-only "origin/${BASE}" --quiet 2>/dev/null; then
      printf '%s\tERROR\tbranch=NONE\tff-only merge of origin/%s failed\n' "$repo" "$BASE"
      overall=4
      continue
    fi
    sync="SYNCED_FF($behind)"
  fi

  # 2. Create or check out the epic branch from the now-current base.
  if git -C "$path" show-ref --verify --quiet "refs/heads/${BRANCH}"; then
    if ! git -C "$path" checkout "$BRANCH" --quiet 2>/dev/null; then
      printf '%s\t%s\tbranch=ERROR\tcheckout of existing %s failed\n' "$repo" "$sync" "$BRANCH"
      overall=4
      continue
    fi
    b_behind="$(git -C "$path" rev-list --count "${BRANCH}..${BASE}" 2>/dev/null || echo 0)"
    if [ "$b_behind" -gt 0 ]; then
      printf '%s\t%s\tbranch=BEHIND_%s\texisting branch is %s commits behind %s — consider merge/rebase before stacking\n' \
        "$repo" "$sync" "$b_behind" "$b_behind" "$BASE"
    else
      printf '%s\t%s\tbranch=EXISTS\tup to date with %s\n' "$repo" "$sync" "$BASE"
    fi
  else
    if ! git -C "$path" checkout -b "$BRANCH" "$BASE" --quiet 2>/dev/null; then
      printf '%s\t%s\tbranch=ERROR\tcheckout -b %s from %s failed\n' "$repo" "$sync" "$BRANCH" "$BASE"
      overall=4
      continue
    fi
    printf '%s\t%s\tbranch=CREATED\tcut from %s @ origin/%s\n' "$repo" "$sync" "$BASE" "$BASE"
  fi
done

exit "$overall"
