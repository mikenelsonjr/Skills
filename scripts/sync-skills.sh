#!/usr/bin/env bash
#
# sync-skills.sh — install/update the bound engineering-loop skills into a project.
#
# MODEL (see HARNESS.md): the Skills repo is the upstream source of truth. Each
# project vendors a COMMITTED copy of the bound skills, configured by its own
# PROJECT_HARNESS block in CLAUDE.md, and pulls updates explicitly. This script is
# PULL-ONLY (upstream -> project). It never pushes project edits back upstream and
# never touches CLAUDE.md / PROJECT_HARNESS.
#
# It flattens the Skills-repo category layout into the flat shape Claude Code needs:
#   Skills/engineering/run-story/SKILL.md  ->  <project>/.claude/skills/run-story/SKILL.md
#   Skills/agents/scout.md                 ->  <project>/.claude/agents/scout.md
#   Skills/scripts/branch-sync.sh          ->  <project>/.claude/scripts/branch-sync.sh
#
# USAGE
#   cd <your-project>
#   sync-skills.sh                 # dry-run: show what WOULD change (default, safe)
#   sync-skills.sh --apply         # write the changes into ./.claude
#   sync-skills.sh --apply --force # overwrite even locally-modified vendored files
#
# ENV
#   SKILLS_REPO   path to the Skills repo (default: sibling ../Skills of the project,
#                 then ~/SoftwareProjects/Skills)
#   PROJECT_DIR   target project root (default: current directory)
#
# After a successful --apply the changes are left UNSTAGED so you review the diff
# and commit them into the project yourself. A .claude/SKILLS_VERSION marker records
# which upstream commit was vendored.

set -euo pipefail

# ---- resolve source (Skills repo) --------------------------------------------
PROJECT_DIR="${PROJECT_DIR:-$(pwd)}"
if [ -z "${SKILLS_REPO:-}" ]; then
  for cand in "$PROJECT_DIR/../Skills" "$HOME/SoftwareProjects/Skills"; do
    if [ -d "$cand/engineering" ] && [ -d "$cand/agents" ]; then SKILLS_REPO="$cand"; break; fi
  done
fi
if [ -z "${SKILLS_REPO:-}" ] || [ ! -d "$SKILLS_REPO/engineering" ]; then
  echo "ERROR: could not locate the Skills repo. Set SKILLS_REPO=/path/to/Skills." >&2
  exit 1
fi
SKILLS_REPO="$(cd "$SKILLS_REPO" && pwd)"

# ---- args --------------------------------------------------------------------
APPLY=0; FORCE=0
for a in "$@"; do
  case "$a" in
    --apply) APPLY=1 ;;
    --force) FORCE=1 ;;
    -h|--help) sed -n '2,40p' "$0"; exit 0 ;;
    *) echo "unknown arg: $a" >&2; exit 2 ;;
  esac
done

CLAUDE_DIR="$PROJECT_DIR/.claude"
echo "Source (upstream): $SKILLS_REPO"
echo "Target (project):  $CLAUDE_DIR"
echo "Mode:              $([ $APPLY -eq 1 ] && echo APPLY || echo 'DRY-RUN (use --apply to write)')"
echo

# ---- build the source manifest: flattened src -> dest ------------------------
# skills: category-dir/<name>/*  ->  .claude/skills/<name>/*
# agents: agents/*.md             ->  .claude/agents/*.md
# scripts: scripts/* (excl. this script) -> .claude/scripts/*
tmp_manifest="$(mktemp)"; trap 'rm -f "$tmp_manifest"' EXIT

for cat in engineering product-management notifications; do
  [ -d "$SKILLS_REPO/$cat" ] || continue
  while IFS= read -r skill_dir; do
    name="$(basename "$skill_dir")"
    while IFS= read -r f; do
      rel="${f#"$skill_dir"/}"
      echo "$f|$CLAUDE_DIR/skills/$name/$rel" >> "$tmp_manifest"
    done < <(find "$skill_dir" -type f)
  done < <(find "$SKILLS_REPO/$cat" -mindepth 1 -maxdepth 1 -type d)
done

for f in "$SKILLS_REPO"/agents/*.md; do
  [ -e "$f" ] || continue
  echo "$f|$CLAUDE_DIR/agents/$(basename "$f")" >> "$tmp_manifest"
done

for f in "$SKILLS_REPO"/scripts/*; do
  [ -e "$f" ] || continue
  base="$(basename "$f")"
  [ "$base" = "sync-skills.sh" ] && continue   # don't vendor the installer itself
  echo "$f|$CLAUDE_DIR/scripts/$base" >> "$tmp_manifest"
done

# ---- classify each file: NEW / UPDATE / SAME, and flag local modifications ----
new=0; upd=0; same=0; conflict=0
declare -a to_write conflicts
while IFS='|' read -r src dst; do
  if [ ! -f "$dst" ]; then
    echo "  NEW     ${dst#"$PROJECT_DIR"/}"
    new=$((new+1)); to_write+=("$src|$dst")
  elif diff -q "$src" "$dst" >/dev/null 2>&1; then
    same=$((same+1))
  else
    # target differs from upstream. Is the target a locally-MODIFIED vendored file,
    # or just an older upstream version? We can't know intent, so warn and require
    # --force to clobber, protecting against silently losing an in-project edit.
    echo "  UPDATE  ${dst#"$PROJECT_DIR"/}"
    upd=$((upd+1))
    # Heuristic: if the project git repo has uncommitted changes to dst, it's a
    # local edit -> conflict unless --force.
    if git -C "$PROJECT_DIR" status --porcelain -- "$dst" 2>/dev/null | grep -q .; then
      echo "          ^ locally modified in project (uncommitted) — needs --force to overwrite"
      conflict=$((conflict+1)); conflicts+=("$dst")
    fi
    to_write+=("$src|$dst")
  fi
done < "$tmp_manifest"

echo
echo "Summary: $new new · $upd update · $same unchanged · $conflict locally-modified"

if [ "$conflict" -gt 0 ] && [ "$FORCE" -ne 1 ]; then
  echo
  echo "⚠️  $conflict vendored file(s) have uncommitted local edits in this project."
  echo "    Per the vendored-skills model, STRUCTURAL fixes belong upstream in the"
  echo "    Skills repo, then pull down. If these are stray in-project edits, either"
  echo "    commit/stash them first, or re-run with --force to overwrite them."
  [ $APPLY -eq 1 ] && { echo "    Refusing to APPLY with unresolved conflicts."; exit 3; }
fi

if [ $APPLY -ne 1 ]; then
  echo
  echo "Dry-run only. Re-run with --apply to write these changes."
  exit 0
fi

# ---- apply -------------------------------------------------------------------
for pair in "${to_write[@]:-}"; do
  [ -z "$pair" ] && continue
  src="${pair%%|*}"; dst="${pair#*|}"
  mkdir -p "$(dirname "$dst")"
  cp "$src" "$dst"
  # preserve executable bit for scripts
  [ -x "$src" ] && chmod +x "$dst"
done

# ---- version marker ----------------------------------------------------------
ver="$(git -C "$SKILLS_REPO" rev-parse --short HEAD 2>/dev/null || echo unknown)"
{
  echo "# vendored from the Skills repo by sync-skills.sh — do not edit skill files here;"
  echo "# make structural changes upstream in the Skills repo and re-pull."
  echo "skills_repo_commit: $ver"
} > "$CLAUDE_DIR/SKILLS_VERSION"
echo "  WROTE   .claude/SKILLS_VERSION (upstream $ver)"

echo
echo "✅ Applied. Changes are UNSTAGED — review the diff and commit into this project:"
echo "     git -C \"$PROJECT_DIR\" diff -- .claude"
echo "     git -C \"$PROJECT_DIR\" add .claude && git commit -m 'chore: sync skills to $ver'"
