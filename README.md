# Claude Code Skills

Reusable Claude Code skills, agents, and scripts organized by function. Import into any project as a git submodule.

> **Porting the engineering loop to a new project?** See **[HARNESS.md](HARNESS.md)** — it separates the universal pipeline (the `run-story` loop, which works anywhere) from the ~9 project-specific bindings (tracker, repos, test runner, run harness). Each project configures those bindings in its own `CLAUDE.md` via a `## PROJECT_HARNESS` block at install time.

## Structure

```
Skills/
├── engineering/          # Dev workflow — TDD, story execution, security
├── notifications/        # Email and messaging via Gmail MCP
├── product-management/   # Jira/Confluence — epics, stories, intent briefs
├── agents/               # Subagent definitions — recon, verify, smoke
└── scripts/              # Shared helper scripts + recipe references
```

## Skills

### Product Management

| Skill | Command | Description |
|---|---|---|
| write-intent | `/write-intent "idea"` | Interactively draft a product intent brief for a new Epic |
| epic-smith | `/epic-smith intent-{slug}.md` | Turn an intent brief into a delivery-ready Jira Epic |
| refine-epic | `/refine-epic EL-50` | Score and refine all stories in an epic |
| refine-story | `/refine-story EL-101` | Refine a poorly specified Jira story |
| sync-docs | `/sync-docs` | Refresh local context files from Confluence |

### Engineering

| Skill | Command | Description |
|---|---|---|
| generate-task | `/generate-task EL-101` | Jira story → TASK.md work order, transitions ticket to In Progress |
| tdd-start | `/tdd-start task-EL-101-slug.md` | Write tests first, implement until green |
| eval-ui | `/eval-ui task-EL-101-slug.md` | Screenshot vs Figma visual comparison |
| to-stories | `/to-stories` | Break a plan/PRD into tracer-bullet issues on the tracker |
| run-story | `/run-story EL-101` | Orchestrate full story pipeline (generate → TDD → smoke test → close) |
| run-epic | `/run-epic EL-50` | Orchestrate full epic pipeline, story by story |
| close-story | `/close-story EL-101` | Commit → Jira Done → archive → PR if last story |
| security-audit | `/security-audit [repo]` | Full-codebase security + architecture review |

### Notifications

| Skill | Command | Description |
|---|---|---|
| notify-skill | `/notify complete EL-101` | Send Gmail notification (story complete or queue empty) |

## Agents

Subagent definitions used by the story pipeline. Copy into a project's `.claude/agents/` so Claude Code loads them at session start.

| Agent | Role |
|---|---|
| scout | Reconnaissance — reads the codebase for a story and returns ground truth (what exists, conventions, cross-repo blast radius) as a structured Recon Report. Read-only. |
| verify-task | Adversarial task check — reads a TASK.md against scout's report and surfaces "Jira-correct, object-shape-wrong" contradictions + open questions before any code exists. Read-only. |
| smoke-runner | Smoke-test pre-flight — drives the running app through the mechanically-executable smoke rows and returns per-row PASS / FAIL / NEEDS-HUMAN verdicts with real request+response evidence. Never approves the story. |

## Scripts

Shared helpers referenced by the skills. Copy into a project's `.claude/scripts/`.

| File | Purpose |
|---|---|
| JIRA_RECIPES.md | Reusable JQL / Jira transition recipes referenced by the story and epic skills |
| branch-sync.sh | Sync epic branches across the multi-repo workspace |
| commit-archive.sh | Commit story task files and archive completion reports |

## Usage — install into a project

The install model is **vendored + committed**: the Skills repo is the upstream
source of truth; each project keeps its own committed copy of the bound skills,
configured by that project's `PROJECT_HARNESS` block (see [HARNESS.md](HARNESS.md)),
and pulls updates explicitly. Universal, binding-free skills (`graphify`,
`notify-skill`) can instead live global in `~/.claude/skills/`.

Use [`scripts/sync-skills.sh`](scripts/sync-skills.sh) to install/update the bound
skills into a project. It flattens the category layout here into the flat shape
Claude Code needs (`engineering/run-story/` → `.claude/skills/run-story/`), copies
`agents/` → `.claude/agents/` and `scripts/` → `.claude/scripts/`, and writes a
`.claude/SKILLS_VERSION` marker recording the upstream commit.

```bash
cd <your-project>

# 1. Dry-run (default, safe) — shows NEW / UPDATE / SAME per file
SKILLS_REPO=/path/to/Skills /path/to/Skills/scripts/sync-skills.sh

# 2. Apply — writes into ./.claude, leaves changes UNSTAGED for your review
SKILLS_REPO=/path/to/Skills /path/to/Skills/scripts/sync-skills.sh --apply

# 3. Review + commit into the project
git diff -- .claude
git add .claude && git commit -m "chore: sync skills"
```

- **Pull-only.** Never pushes project edits back upstream; never touches
  `CLAUDE.md` / `PROJECT_HARNESS`.
- **Clobber guard.** If a vendored skill has uncommitted local edits in the
  project, `--apply` refuses (exit 3) rather than silently overwriting. Structural
  fixes belong upstream, then re-pull; use `--force` only to intentionally discard
  a local edit.
- `SKILLS_REPO` defaults to a sibling `../Skills`, then `~/SoftwareProjects/Skills`.

After installing, add the project's `## PROJECT_HARNESS` block to its `CLAUDE.md`
(template in [HARNESS.md](HARNESS.md) Part 3) so the skills bind to that project's
tracker, repos, and run harness.

## Notes

- Skills live at `.claude/skills/` so Claude Code picks them up automatically
- Agents live at `.claude/agents/` and load at session start; scripts at `.claude/scripts/`
- Project-specific values (Jira keys, Confluence URLs, repo paths) are configured in each project's `CLAUDE.md` — the skills themselves stay generic
- Each skill directory contains a single `SKILL.md` file
