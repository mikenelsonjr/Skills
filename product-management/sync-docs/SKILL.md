---
name: sync-docs
description: >
  Refresh local context files from Confluence. Fetches the two source pages,
  condenses each into a lean agent-optimized summary, and updates the local
  files. Shows a diff for review before writing. Run manually whenever
  Confluence content has changed significantly.
  Usage: /sync-docs
---

# sync-docs

Pulls the two Confluence source pages, regenerates the local context files
as condensed summaries, and shows you what changed before committing.

Local files are intentionally shorter than Confluence — they are context
indexes, not full copies. The goal is just enough information for an agent
to orient itself; the Confluence URL is always included so the agent can
fetch more detail when needed.

## Invocation

```
/sync-docs
```

No arguments. Syncs all files in one pass.

---

## Source pages

| Confluence page | Page ID | Local files updated |
|---|---|---|
| Spyglass Project Context — AI Agent Reference | `93093890` | `PROJECT_CONTEXT.md`, `core-api/CLAUDE.md`, `core-webui/CLAUDE.md`, `RentManagerSyncSerivce/CLAUDE.md`, `ai-service/CLAUDE.md`, `pm-docs/agents/contexts/architecture-overview.md`, `pm-docs/agents/contexts/glossary.md` |
| Spyglass Product Strategy & Architecture Direction | `95649793` | `PRODUCT_STRATEGY.md`, `pm-docs/agents/contexts/product-vision.md` |

Tracker ID: `{tracker_id}` (default `b6770d30-bf33-4b84-8fd7-607d704d0cd1`)

---

## Instructions

### Step 1 — Fetch both Confluence pages

Use the Atlassian MCP `getConfluencePage` tool to fetch both pages in full.
Extract the body text from each.

If either page cannot be fetched, stop and report the error with the page ID.
Do not write any local files if the source cannot be read.

---

### Step 2 — Check for significant changes

Read the current content of each local file.

For each file, compare the Confluence source against the current local version.
Classify the delta as:

- **No change** — content is materially the same; skip this file
- **Minor update** — small additions, wording tweaks, new rows in a table
- **Significant change** — new sections, removed sections, renamed terms,
  changed constraints or architectural decisions

Report the classification before writing anything:

```
Confluence page 93093890 — last modified: {date}
  PROJECT_CONTEXT.md       — significant change (new §3.6 idempotency section)
  core-api/CLAUDE.md — minor update (new tech debt row)
  core-webui/CLAUDE.md — no change
  RentManagerSyncSerivce/CLAUDE.md — no change
  ai-service/CLAUDE.md — no change
  pm-docs/.../architecture-overview.md — minor update
  pm-docs/.../glossary.md — no change

Confluence page 95649793 — last modified: {date}
  PRODUCT_STRATEGY.md      — significant change (updated time horizons table)
  pm-docs/.../product-vision.md — minor update

Proceed with updates? (yes / review first)
```

Wait for confirmation before writing. If the user says "review first", show
the specific diffs you plan to make before proceeding.

---

### Step 3 — Regenerate updated files

For each file marked **minor update** or **significant change**, regenerate
the content following these rules:

**Condensing rules — apply to every file:**
- Tables and bullets only — no prose paragraphs
- Remove any content that is derivable by reading the code (file paths, class
  names, method names) — these go stale and belong in repo-level CLAUDE.md
- Keep: constraints, terminology rules, "never do X" rules, architectural
  decisions, and pointers to where more detail lives
- Target line counts: `PROJECT_CONTEXT.md` ~150 lines, `PRODUCT_STRATEGY.md`
  ~100 lines, repo CLAUDE.md files ~60-80 lines each, pm-docs context files
  ~25-35 lines each
- Always include the Confluence URL and a `_Last synced: {YYYY-MM-DD}_` line
  at the top of each file

**Per-file scope:**

`PROJECT_CONTEXT.md` — terminology, data layers, user groups/roles, source
systems, API conventions, DB conventions, MCP surface rules, test conventions,
UI eval tiers, known tech debt table. Cross-repo facts only.

`PRODUCT_STRATEGY.md` — what Spyglass is/isn't, thesis claims, target
customer, wedge workflow, build/integrate/defer table, time horizons summary,
moat, revisit signals.

`core-api/CLAUDE.md` — package layout table, Spring conventions,
Flyway rules, auth rules, test pattern snippet, run commands.

`core-webui/CLAUDE.md` — app layout table, Angular conventions,
design system tokens, portal routing, test pattern snippet, eval-ui guidance,
run commands.

`RentManagerSyncSerivce/CLAUDE.md` — module layout table, key constraints
(pg8000, token expiry, IP pinning, GL reports, multi-tenant, checkpoints),
test pattern snippet, run commands.

`ai-service/CLAUDE.md` — layout table, key constraints (Vertex AI, async
jobs, health check, no direct SDK calls), test pattern snippet, run commands.

`pm-docs/agents/contexts/product-vision.md` — mission, target customer,
strategic pillars, what we're not building. Max 20 lines.

`pm-docs/agents/contexts/architecture-overview.md` — stack table, data flow
one-liner, data layers table, key constraints. Max 30 lines.

`pm-docs/agents/contexts/glossary.md` — critical terms table, roles table,
source systems table, process terms table. Max 40 lines.

---

### Step 4 — Show diff and confirm

For each file being updated, show a brief summary of what changed:
- Lines added / removed (approximate)
- Key change in plain English (e.g. "added idempotency constraints", "updated time horizons")

Ask: "Write these changes? (yes / skip {filename} / cancel)"

Apply any selective skips the user requests.

---

### Step 5 — Write files and report

Write the approved files. Update the `_Last synced:` date in each file header.

Then commit the changes from the workspace repo:

```
git add PROJECT_CONTEXT.md PRODUCT_STRATEGY.md \
        core-api/CLAUDE.md core-webui/CLAUDE.md \
        RentManagerSyncSerivce/CLAUDE.md ai-service/CLAUDE.md \
        pm-docs/agents/contexts/
git commit -m "chore: sync context files from Confluence ({date})"
```

Report:

```
✅ Sync complete — {date}

Files updated:
  {list of updated files with one-line change summary each}

Files skipped (no change):
  {list}

Sources:
  Page 93093890 — last modified {date}
  Page 95649793 — last modified {date}
```
