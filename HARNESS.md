# HARNESS.md — Portable Engineering Loop Blueprint

The Spyglass skill chain (`run-story` and its sub-skills) is a **general-purpose
engineering loop** wearing Spyglass-specific clothing. This document separates the
two: the **universal pipeline** (works on any project), and the **project
bindings** (the ~9 seams each new project must define). Define the bindings for a
project — in its `CLAUDE.md` under a `## PROJECT_HARNESS` block — and the same
skills run there.

> **Scope note.** This is the *implementation* loop (`generate-task → tdd-start →
> verify → smoke → close-story`, orchestrated by `run-story`). The upstream
> *planning* skills (`write-intent`, `epic-smith`, `refine-story`) are already
> nearly project-agnostic; their only binding is the tracker (#1). The downstream
> `notify-skill` is fully portable.

---

## Part 1 — The Universal Loop (ports anywhere)

This skeleton is invariant across tracker, language, and deploy target. It is the
*value* of the harness — the philosophy, not the plumbing.

```
0  VALIDATE     work-item exists, is in the "ready" state, workspace is clean
1  DRAFT        work-item → task doc + proposed acceptance cases (NOT frozen)
2  RECON        read the codebase for ground truth (scout) — what exists, real shapes
3  ADVERSARIAL  check the draft against recon (verify-task) — contradictions + gaps
⏸  PRE-FREEZE   HUMAN reviews/edits the reality-checked spec; nothing committed yet
4  FREEZE       commit one failing case per AC — the contract now predates the code
5  BUILD        TDD each frozen case RED→GREEN; may not weaken the frozen suite
6  VERIFY       independent clean-checkout re-check — never trust the builder's report
6b SMOKE-PREP   drive the RUNNING app through the checklist; bring back real evidence
⏸  SMOKE GATE   HUMAN confirms evidence + judges what automation can't (visual/UX)
7  CLOSE        commit + mark work-item done + publish (PR)
```

### The invariant principles (why this loop is worth porting)

1. **The contract predates the code.** The acceptance spec freezes *before* the
   build. Freezing is the point of no return; every reshaping happens before it.
2. **Two independent truth gates.** Phase 3 catches "tracker-correct but
   repo-contradicting" *before* code exists. Phase 6 catches "passes the builder's
   own tests but is actually wrong" *after*, from a clean checkout, never reading
   the builder's conversation.
3. **Humans gate meaning, machines gate mechanics.** Two human pauses only: the
   pre-freeze review (is this the right spec?) and the smoke gate (does it really
   work?). Everything mechanical is automated and evidenced.
4. **Fresh context per phase.** Each phase is a sub-agent with a clean window, so a
   long story doesn't inflate cost or drift.
5. **No self-report trust.** The builder's pass counts are provisional until an
   independent agent re-derives them from committed state.

None of these five depend on Jira, Java, Docker, or a monorepo. They are the
transferable asset.

---

## Part 2 — The Binding Taxonomy (the 9 seams)

Each seam is a place the universal loop touches something project-specific. For a
new project, define each one. The table shows the Spyglass value and the abstract
concept the skill actually needs.

| # | Seam | Universal concept | Spyglass value (today) |
|---|------|-------------------|------------------------|
| 1 | **Tracker** | a work-item store with a status lifecycle | Jira, Cloud ID `b6770d30-…`, MCP Atlassian tools |
| 2 | **Item lifecycle** | the 3 states the loop keys on | `Ready` → `In Progress` → `Done` |
| 3 | **Item ID format** | how a work-item is named | `EL-101` (`{PROJ}-{n}`) |
| 4 | **Workspace root** | the dir all paths resolve from | `/Users/miken/SoftwareProjects/Spyglass/` |
| 5 | **Repo set** | code repos in scope + their languages | `core-api` (Java), `core-webui` (TS), `RentManagerSyncSerivce` (Py), `ai-service` (Py) |
| 6 | **Branch model** | how branches are cut & based | epic branch off `dev`; `branch-sync.sh`; PR to `dev` |
| 7 | **Acceptance-suite convention** | where frozen cases live + how one is written per language | `acceptance/{KEY}/` + `manifest.json`; JUnit / Jasmine / pytest templates |
| 8 | **Run/smoke harness** | how you bring the app up & drive it | `docker-compose` (`--force-recreate` post-migration), postgres `:5433`, MCP `tools/call`, REST, `ng serve` :4200 |
| 9 | **Close mechanics** | commit + mark-done + publish | `commit-archive.sh`, Jira→Done, PR to `dev`, `/notify` |

### Where each seam is hardcoded today (so you know what to touch)

- **#1/#2/#3 Tracker** — `run-story` Phase 0, `close-story` Steps 7 & 9,
  `to-stories`. Cloud ID literal in 3 files; `Ready`/`In Progress`/`Done` threaded
  throughout. **Hardest seam** — differs most between Jira ↔ Aptly ↔ GitHub Issues.
- **#4 Workspace root** — `/Users/.../Spyglass/` literal, ~10× in `run-story`
  sub-agent prompts alone, plus `close-story`, `generate-task`.
- **#5 Repo set** — the `for r in core-api core-webui …` loop (git hygiene), the
  per-repo suite-path table, the language→framework table.
- **#6 Branch model** — `branch-sync.sh`, `dev` base, epic-branch naming.
- **#7 Acceptance suite** — `generate-task` (suite paths + per-language failing-case
  templates + manifest), `tdd-start` (same paths + framework table), `verify`
  (tautology grep is per-language: `assertThat(true)`, `assert True`,
  `expect(true).toBe(true)`).
- **#8 Run/smoke** — `run-story` Phase 6b, `smoke-runner` agent, `eval-ui`
  (`localhost:4200`, `APP_BASE_URL`).
- **#9 Close** — `close-story`, `commit-archive.sh`.

---

## Part 3 — Per-Project Context Contract

To run the harness on a project, put this block in that project's `CLAUDE.md`. The
skills read their bindings from here instead of hardcoded literals.

```yaml
## PROJECT_HARNESS

# 1–3 Tracker
tracker:        jira            # jira | aptly | github | file
tracker_id:     b6770d30-bf33-4b84-8fd7-607d704d0cd1   # Jira Cloud ID / Aptly board ID / gh repo
item_lifecycle: {ready: "Ready", active: "In Progress", done: "Done"}
item_id_format: "EL-{n}"

# 4–5 Workspace + repos
workspace_root: /Users/miken/SoftwareProjects/Spyglass
repos:
  - {path: core-api,               lang: java,       test: "./gradlew test", framework: junit}
  - {path: core-webui,             lang: typescript, test: "npm test",       framework: jasmine}
  - {path: RentManagerSyncSerivce, lang: python,     test: "pytest",         framework: pytest}
  - {path: ai-service,             lang: python,     test: "pytest",         framework: pytest}

# 6 Branch model
base_branch:    dev
branch_scheme:  "feature/{epic-slug}"        # one branch per epic, shared across stories
pr_target:      dev

# 7 Acceptance suite
suite_dir:      "acceptance/{KEY}"           # relative to each repo's test root
manifest:       true                         # freeze a manifest.json of case names + AC bindings

# 8 Run / smoke
run_up:         "docker-compose up -d --force-recreate"
db_dsn:         "postgres://localhost:5433/..."
ui_base_url:    "http://localhost:4200"
smoke_channels: [mcp_tools_call, rest, data_shape_sql, ui_xhr]

# 9 Close
close_helpers:  [".claude/scripts/commit-archive.sh"]
notify:         "/notify complete {KEY}"
```

### Minimal contract (single-repo, GitHub Issues, no Docker)

Most projects need far less. Example for a solo Python repo tracking work in
GitHub Issues:

```yaml
## PROJECT_HARNESS
tracker:        github
tracker_id:     mikenelsonjr/some-repo
item_lifecycle: {ready: "ready", active: "in-progress", done: "closed"}   # gh labels/state
item_id_format: "#{n}"
workspace_root: /Users/miken/SoftwareProjects/some-repo
repos:
  - {path: ., lang: python, test: "pytest", framework: pytest}
base_branch:    main
branch_scheme:  "issue-{n}"
pr_target:      main
suite_dir:      "tests/acceptance/{KEY}"
run_up:         "python -m app &"
ui_base_url:    null            # no UI → eval-ui / ui smoke rows skipped
close_helpers:  []
notify:         null
```

---

## Part 4 — Portability Verdict per Skill

| Skill / agent | Portable as-is | Needs binding | Spyglass-only |
|---|---|---|---|
| `run-story` (orchestrator) | skeleton ✅ | #1–#9 all | — |
| `generate-task` | draft/freeze logic ✅ | #3 #5 #7 | — |
| `tdd-start` | RED→GREEN discipline ✅ | #5 #7 | — |
| `verify` (agent) | independence principle ✅ | #7 (tautology grep per-lang) | — |
| `smoke-runner` (agent) | evidence-not-approval ✅ | #8 | — |
| `scout` (agent) | recon method ✅ | #4 #5 | — |
| `verify-task` (agent) | adversarial method ✅ | — (works off scout) | — |
| `close-story` | commit+done+publish ✅ | #1 #6 #9 | — |
| `eval-ui` | screenshot-vs-figma ✅ | #8 (ui_base_url) | — |
| `to-stories` | slice method ✅ | #1 | — |
| `write-intent`,`epic-smith`,`refine-*` | ✅ | #1 | — |
| `notify-skill` | ✅ fully portable | — | — |

**Bottom line:** *zero* skills are irreducibly Spyglass-specific. Every one is
universal-method + bindings. The bindings concentrate in three seams that matter
most when moving to a new project: **#1 tracker** (Jira→Aptly→GitHub is the biggest
rewrite), **#5 repos/languages**, and **#8 run harness**. Nail those three in a
project's `PROJECT_HARNESS` block and the loop transfers.

---

## Part 5 — Hardest Seam: the Tracker Adapter (#1–#3)

The tracker is the only seam with genuinely different *tool surfaces* (Jira MCP vs
Aptly REST vs `gh` CLI). Everything else is paths and commands. If/when you
genericize, the tracker wants a thin adapter — the same 6 operations the skills
already use, mapped per backend:

| Operation | Jira (today) | Aptly | GitHub Issues |
|---|---|---|---|
| `get_item(id)` | `getJiraIssue` | `GET /card/{id}` | `gh issue view {n}` |
| `is_ready(id)` | status == `Ready` | stage in {ready col} | label `ready` |
| `set_active(id)` | transition→In Progress | advance stage | label swap |
| `set_done(id)` | transition→Done | terminal stage | `gh issue close` |
| `next_ready()` | JQL `status=Ready` | cards in ready stage | `gh issue list -l ready` |
| `comment/link(id)` | `addCommentToJiraIssue` | `POST /card/{id}/comment` | `gh issue comment` |

The rest of the loop calls these six verbs; only the adapter knows the backend. A
skill written against these verbs runs on Spyglass (Jira) **and** Excalibur (Aptly
board `5K9eCCqZBe3ERTswA`) unchanged.

---

## How to onboard a new project (the checklist)

1. Copy the skills into the project's `.claude/{skills,agents,scripts}` (or via the
   sync script).
2. Write the `## PROJECT_HARNESS` block into the project's `CLAUDE.md` (Part 3).
3. Fill the three high-value seams first: tracker (#1), repos (#5), run harness (#8).
4. If the tracker isn't Jira, supply the 6-verb adapter mapping (Part 5).
5. Dry-run `run-story` on one small item; the pre-freeze gate will surface any
   binding you got wrong before anything commits.
```
