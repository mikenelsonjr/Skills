#!/usr/bin/env bash
# commit-archive.sh — deterministic story close-out mechanics.
#
# Given a commit message (the model authored it — that part is judgment), do the
# deterministic parts of close-story: stage + commit changes in each named repo,
# optionally push the epic branch, and move the story's task/completion files to
# tasks/archive/. The commit message is NEVER generated here.
#
# The root workspace repo (SpyglassDevWorkspace) is committed separately by the
# caller if desired — this script only touches the code repos you name and the
# archive move, so task-file history stays a deliberate caller decision.
#
# Usage:
#   commit-archive.sh --key EL-101 --slug some-slug --msg-file <path> \
#       --repos "core-api core-webui" [--branch feature/el-50-slug --push] \
#       [--no-archive]
#
#   --key       Jira key (for locating task files)
#   --slug      task-file slug
#   --msg-file  path to a file holding the full commit message (multi-line ok)
#   --repos     space-separated repo names to commit in (only repos with staged
#               changes are committed; a clean repo is reported CLEAN, not failed)
#   --branch    epic branch name (required with --push)
#   --push      push --branch to origin for each repo (last-story-of-epic only)
#   --no-archive  skip the task-file archive move
#
# Output: tab-separated status lines. Exit 0 on success, 4 on any git failure,
# 2 on bad args.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

KEY="" SLUG="" MSG_FILE="" REPOS="" BRANCH="" PUSH=0 ARCHIVE=1
while [ "$#" -gt 0 ]; do
  case "$1" in
    --key)       KEY="$2"; shift 2;;
    --slug)      SLUG="$2"; shift 2;;
    --msg-file)  MSG_FILE="$2"; shift 2;;
    --repos)     REPOS="$2"; shift 2;;
    --branch)    BRANCH="$2"; shift 2;;
    --push)      PUSH=1; shift;;
    --no-archive) ARCHIVE=0; shift;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done

if [ -z "$KEY" ] || [ -z "$MSG_FILE" ] || [ -z "$REPOS" ]; then
  echo "usage: commit-archive.sh --key KEY --msg-file PATH --repos \"r1 r2\" [--slug S] [--branch B --push] [--no-archive]" >&2
  exit 2
fi
if [ ! -f "$MSG_FILE" ]; then
  echo "commit message file not found: $MSG_FILE" >&2
  exit 2
fi
if [ "$PUSH" -eq 1 ] && [ -z "$BRANCH" ]; then
  echo "--push requires --branch" >&2
  exit 2
fi

overall=0

for repo in $REPOS; do
  path="$ROOT/$repo"
  if [ ! -d "$path/.git" ]; then
    printf '%s\tERROR\tno .git\n' "$repo"; overall=4; continue
  fi

  git -C "$path" add -A 2>/dev/null
  if git -C "$path" diff --cached --quiet 2>/dev/null; then
    printf '%s\tCLEAN\tnothing staged\n' "$repo"
  else
    if git -C "$path" commit -F "$MSG_FILE" --quiet 2>/dev/null; then
      sha="$(git -C "$path" rev-parse --short HEAD)"
      printf '%s\tCOMMITTED\t%s\n' "$repo" "$sha"
    else
      printf '%s\tERROR\tcommit failed\n' "$repo"; overall=4; continue
    fi
  fi

  if [ "$PUSH" -eq 1 ]; then
    if git -C "$path" push -u origin "$BRANCH" --quiet 2>/dev/null; then
      printf '%s\tPUSHED\t%s\n' "$repo" "$BRANCH"
    else
      printf '%s\tERROR\tpush of %s failed\n' "$repo" "$BRANCH"; overall=4
    fi
  fi
done

# Archive the story's task + completion files (workflow files, not code history).
if [ "$ARCHIVE" -eq 1 ]; then
  mkdir -p "$ROOT/tasks/archive"
  moved=0
  for prefix in task completion; do
    for f in "$ROOT"/tasks/${prefix}-${KEY}-*.md; do
      [ -e "$f" ] || continue
      mv "$f" "$ROOT/tasks/archive/" && { printf 'archive\tMOVED\t%s\n' "$(basename "$f")"; moved=1; }
    done
  done
  [ "$moved" -eq 0 ] && printf 'archive\tNONE\tno task/completion files for %s in tasks/\n' "$KEY"
fi

exit "$overall"
