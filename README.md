# Claude Code Skills

Reusable Claude Code skills organized by function. Import into any project as a git submodule.

## Structure

```
Skills/
├── engineering/          # Dev workflow — TDD, story execution, security
├── notifications/        # Email and messaging via Gmail MCP
└── product-management/   # Jira/Confluence — epics, stories, intent briefs
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
| run-story | `/run-story EL-101` | Orchestrate full story pipeline (generate → TDD → smoke test → close) |
| run-epic | `/run-epic EL-50` | Orchestrate full epic pipeline, story by story |
| close-story | `/close-story EL-101` | Commit → Jira Done → archive → PR if last story |
| security-audit | `/security-audit [repo]` | Full-codebase security + architecture review |

### Notifications

| Skill | Command | Description |
|---|---|---|
| notify-skill | `/notify complete EL-101` | Send Gmail notification (story complete or queue empty) |

## Usage

### Add to a project as a submodule

```bash
git submodule add git@github.com:your-org/claude-skills.git .claude/skills
git commit -m "chore: add claude-skills submodule"
```

### Clone a project that uses this submodule

```bash
git clone --recurse-submodules git@github.com:your-org/your-project.git
# or after clone:
git submodule update --init --recursive
```

### Update skills in a project

```bash
git submodule update --remote .claude/skills
git commit -m "chore: update claude-skills"
```

## Notes

- Skills live at `.claude/skills/` so Claude Code picks them up automatically
- Project-specific skills (Jira keys, Confluence URLs, repo paths) are configured in each project's `CLAUDE.md` — the skills themselves stay generic
- Each skill directory contains a single `SKILL.md` file
