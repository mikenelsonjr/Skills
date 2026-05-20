---
name: generate-task
description: >
  Generate a TASK.md work order file for a Jira story. Invoke with a ticket key:
  /generate-task EL-101
  Pulls the full story from Jira, writes a structured work order to the central
  tasks/ directory, and transitions the ticket to In Progress.
---

# generate-task

Generates a `task-{KEY}-{slug}.md` work order file for a Jira story and
transitions it to In Progress. Run this once at the start of each story before
writing any code. All task files live in a single central directory at the
Spyglass monorepo root: `tasks/`.

## Invocation

```
/generate-task EL-101
```

Replace `EL-101` with the Jira ticket key for the story you are starting.

---

## Instructions

Follow every step in order. Do not skip steps or reorder them.

### Step 1 — Check for an existing task file

Before pulling from Jira, check the central tasks directory for an existing file
matching the ticket key:

- `tasks/task-{KEY}-*.md`

If a file is found:
- Show the user its path and first 20 lines
- Ask: "This story already has a task file. Resume from it, or regenerate from Jira?"
- If **resume**: stop here. The user should point the agent at the existing file.
- If **regenerate**: continue to Step 2. The existing file will be overwritten.

If no file is found: continue to Step 2.

---

### Step 2 — Pull the story from Jira

Use the Atlassian MCP to fetch the full story. You need:

- `summary` — the story title
- `description` — full story description including acceptance criteria
- `labels` — used to determine story type
- `status` — current status (should be Ready; warn if not)
- `parent` or `epic link` — the epic this story belongs to
- `issuelinks` — any dependency links (Blocks / is Blocked By)

Jira base URL: `https://elevareiq.atlassian.net/browse/`
Cloud ID: `b6770d30-bf33-4b84-8fd7-607d704d0cd1`

If the story does not exist or cannot be fetched, stop and report the error.
Do not create a task file for a story that cannot be verified in Jira.

---

### Step 3 — Determine story type and target repo(s)

Use the Jira `labels` field and the story description to determine which
repo(s) this story touches. A story may span multiple repos.

**Label → repo mapping (when labels are present):**

| Label | Story type | Primary repo |
|---|---|---|
| `api-story` | API Story | `core-api` |
| `ui-story` | UI Story | `core-webui` |

**All available repos:**

| Repo | Language | Purpose |
|---|---|---|
| `core-api` | Java 21 / Spring Boot | Backend REST API |
| `core-webui` | Angular 18 / TypeScript | Frontend web app |
| `RentManagerSyncSerivce` | Python | RentManager API → PostgreSQL data sync |
| `ai-service` | Python / FastAPI | AI content generation (Vertex AI / Gemini) |
| `infrastructure` | YAML / Terraform | Infrastructure as code (no .git) |

**How to determine target repos:**

1. If labels are present, use them as the primary signal.
2. Scan the story description for keywords that suggest additional repos:
   - "sync", "RentManager", "import", "data pipeline" → `RentManagerSyncSerivce`
   - "AI", "generate", "Gemini", "Vertex", "content generation" → `ai-service`
    - "gateway", "API gateway", "routing" → `infrastructure`
3. If **no labels** and description is ambiguous: ask the user which repo(s) apply.
   Do not guess.

**Multi-repo stories:**

Some stories require changes across multiple repos (e.g., a new API endpoint
plus a UI screen, or a sync change plus an API change). When this is the case:
- List **all** target repos in the task file's `repos` frontmatter field
- In the "Target files" section, group files by repo
- The agent should work through each repo's changes in sequence

---

### Step 4 — Extract acceptance criteria

Parse the story description to extract acceptance criteria. They may appear as:

- Checkbox markdown: `- [ ] AC text` or `* [ ] AC text`
- Numbered list under a heading like `## Acceptance Criteria`
- Inline bullet points

Preserve the exact AC text — do not paraphrase or rewrite.

If no ACs are found: note this clearly in the task file under a warning.
The story should not proceed without ACs — surface this to the user.

---

### Step 5 — Extract Figma node ID (UI stories only)

For UI stories, perform all three checks below in order. Stop as soon as a
Figma URL is found.

**Check 1 — Parse the Jira description ADF**

Jira returns the description as Atlassian Document Format (ADF), a nested JSON
structure. A Figma URL may be hidden as a link mark rather than visible text.
Traverse the full ADF tree and inspect every node for `figma.com` URLs:

- Plain text nodes: `node.text` (look for a `figma.com` substring)
- Hyperlink marks: `node.marks[].attrs.href` where `type == "link"`
- Inline card nodes: `node.attrs.url`

The Figma URL format to match: `https://www.figma.com/design/{fileKey}/...`

**Check 2 — Fetch remote links**

Call `getJiraIssueRemoteIssueLinks` for the ticket. Scan every remote link's
`object.url` and `object.title` for a `figma.com` URL.

**Check 3 — User prompt (fallback)**

If no Figma URL was found in either check, do **not** silently write
`⚠️ NOT SET`. Instead, ask the user:

"No Figma link found in the Jira description or remote links for {KEY}.
Do you have a Figma URL to add before we start? (paste it or type 'skip')"

If the user provides a URL, extract the node ID from it (below) and continue.
If the user types 'skip', write `⚠️ NOT SET` and note it in the Step 11 warnings.

**Extracting the node ID from a Figma URL:**

Given: `https://www.figma.com/design/{fileKey}/{name}?node-id={rawId}&...`

- `fileKey` = path segment immediately after `/design/`
- `node-id` query param = the raw node ID (may use `-` or `:` as separator;
  normalize to `:` format, e.g. `0-1` → `0:1`)

Include both in the task file:
```
Node ID: {normalized node ID}   ← e.g. 0:1
File:    {full Figma URL}
```

If the URL has no `node-id` param, use `0:1` as the default and note it.

---

### Step 6 — Determine likely files to change

Based on the story type and description, list the files most likely to need
changes. Use the project structure from memory (documented below) and the
story description as signals. This list is a starting point for the agent,
not a contract — the agent may touch other files.

**core-api (Java / Spring Boot) → look for:**
- Controller in `core-api/src/main/java/com/spyglassanalytics/core/api/controllers/`
- Service in `.../services/`
- Repository in `.../repositories/`
- DTOs in `.../dto/`
- Test in `core-api/src/test/java/com/spyglassanalytics/core/api/`
- Migration in `core-api/src/main/resources/db/migration/` (if schema changes needed)

**core-webui (Angular / TypeScript) → look for:**
- Component in `core-webui/src/app/components/{feature}/`
- Service in `core-webui/src/app/services/`
- Store in `.../core/stores/` (if complex state)
- Shared component in `.../shared/components/` (if reusable UI)
- Entity/model in `.../entities/`

**RentManagerSyncSerivce (Python) → look for:**
- Entity sync module in `RentManagerSyncSerivce/{entity}.py` (e.g., `owner.py`, `property.py`, `lease.py`)
- Entry point / CLI args in `RentManagerSyncSerivce/main.py`
- Database utilities in `RentManagerSyncSerivce/db_utils.py`
- Requirements in `RentManagerSyncSerivce/requirements.txt`

**ai-service (Python / FastAPI) → look for:**
- Route handlers in `ai-service/main.py`
- Generation logic / Vertex AI integration in `ai-service/` Python modules
- Requirements in `ai-service/requirements.txt`

**aptly-sync-orchestrator (Java / Spring Boot) → look for:**
- Orchestration logic in `aptly-sync-orchestrator/src/main/java/.../`
- Pub/Sub publisher in `.../pubsub/` or `.../messaging/`
- Scheduling config in `.../config/`
- Database queries for board sync status

**aptly-sync-worker (Java / Spring Boot) → look for:**
- Pub/Sub listener / push endpoint in `aptly-sync-worker/src/main/java/.../`
- Aptly API client in `.../client/` or `.../aptly/`
- Sync logic in `.../services/`
- WebFlux async HTTP handlers

**infrastructure → look for:**
- API Gateway specs in `infrastructure/api-gateway/*.yaml`
- Deployment scripts in `infrastructure/api-gateway/*.sh`

List 3–6 specific file paths per target repo. If you cannot determine the
exact paths, list the directories and note they need confirmation.

---

### Step 6b — Decompose into vertical slices

Using the ACs extracted in Step 4, group them into **tracer-bullet vertical
slices** — thin end-to-end paths that each cut through all integration layers
and deliver one independently demoable or verifiable behavior.

**Rules for slicing:**

- Each slice touches ALL relevant layers (DB → service → controller → test,
  or sync module → DB → test) — never a single horizontal layer
- Slice 1 is always the tracer bullet: the simplest thing that proves the
  full plumbing works end-to-end (e.g. endpoint exists and returns 200)
- Each slice must be independently demoable — a stakeholder or a curl command
  can verify it without waiting for the next slice
- Maximum 5–7 slices per story; if more are needed, the story is too big
- Order by dependency: slice N+1 must be able to build on top of slice N

**Mark each slice as:**

- **AFK** — the agent can implement and verify this autonomously; the
  outcome is deterministic and testable
- **HITL** — requires a human decision mid-implementation (design choice,
  ambiguous business rule, external credential, product policy decision)

**Example decomposition for an API story (GET + POST endpoint):**

Instead of:
```
Layer 1: Add migration
Layer 2: Add entity / repository
Layer 3: Add service
Layer 4: Add controller
Layer 5: Write tests
```

Write slices:
```
Slice 1 (AFK): GET /endpoint returns 200 with empty array when no records exist
  ACs covered: AC1 (happy path structure)
  Demoable: curl GET and see []

Slice 2 (AFK): GET /endpoint returns records scoped to customer_uuid
  ACs covered: AC2 (data returned), AC3 (customer isolation)
  Demoable: seed two customers' records, verify only caller's records appear

Slice 3 (HITL): POST /endpoint creates a record — error contract TBD
  ACs covered: AC4 (create), AC5 (validation errors)
  Demoable: POST valid body → 201, POST invalid body → 400
  HITL reason: validation error shape (field-level vs message-only) needs product decision
```

After drafting slices, proceed directly to Step 7 — do not pause for user confirmation.
Only stop if: (a) no ACs were found, (b) the story type or target repo is genuinely ambiguous,
or (c) a HITL slice requires an immediate product decision before any implementation is possible.
Slice structure can be adjusted when tdd-start surfaces surprises during implementation.

---

### Step 7 — Build the slug

Derive a short slug from the story summary:
- Lowercase
- Replace spaces and special characters with hyphens
- Max 40 characters
- Drop common words (the, a, an, for, to, with, and)

Examples:
- "Add renewal recommendation endpoint" → `renewal-recommendation-endpoint`
- "User management screens owners pm users" → `user-management-screens`
- "Front end state management" → `frontend-state-management`

Final filename: `task-{KEY}-{slug}.md`
Example: `task-EL-101-renewal-recommendation-endpoint.md`

---

### Step 8 — Write the task file

Write the file to `tasks/task-{KEY}-{slug}.md` (central tasks directory at
the Spyglass monorepo root).

Use the exact template below. Fill every section completely.
Do not omit sections — use `N/A` or `⚠️ NOT SET` for genuinely empty sections.
Only include constraint subsections that are relevant to the target repos.

```markdown
---
ticket: {KEY}
type: {api-story | ui-story | sync-story | ai-story | aptly-story | infra-story | multi}
repos:
  - {repo-name-1}
  - {repo-name-2}
status: active
epic: {epic key and name}
jira: https://elevareiq.atlassian.net/browse/{KEY}
confluence: https://elevareiq.atlassian.net/wiki/spaces/ELEVAREIQ
created: {YYYY-MM-DD}
---

# TASK: {KEY} — {story summary}

## Story
{story description — full text, not summarised}

## Type
{API Story | UI Story | Sync Story | AI Story | Aptly Story | Infra Story | Multi-repo}

## Acceptance criteria
{numbered list — exact text from Jira, not paraphrased}

1. AC1
2. AC2
3. AC3
...

## Vertical slices

Ordered implementation sequence. Each slice cuts end-to-end through all layers.
Slice 1 is always the tracer bullet — the thinnest path that proves the plumbing works.

| # | Slice | ACs covered | AFK/HITL | Demoable by |
|---|-------|-------------|----------|-------------|
| 1 | {Tracer bullet — simplest end-to-end path} | AC1 | AFK | {how to verify, e.g. curl command} |
| 2 | {Next observable behavior} | AC2, AC3 | AFK | {how to verify} |
| 3 | {Slice requiring a human judgment call} | AC4 | HITL | {what the human must decide before this slice} |

## Figma reference
{UI stories only — omit section entirely for non-UI stories}

Node ID: {figma_node_id}
File: {figma file URL if available}

⚠️ NOT SET — visual eval loop cannot run without a Figma node ID.
{Remove the warning line above if node ID is set}

## Dependencies
{List any stories this story is blocked by, with their keys and titles}
{Write "None" if no blocking dependencies}

## Target repos and files
{Group files by repo. For each repo, list specific file paths likely to change.}

### {repo-name-1}
- `path/to/file` — reason
- `path/to/file` — reason

### {repo-name-2}
- `path/to/file` — reason
- `path/to/file` — reason

{Use a single repo section if only one repo is involved.}

## Architectural constraints
Constraints for all repos are in `CLAUDE.md` at the monorepo root and in
each repo's own `CLAUDE.md` (if present). The implementing agent must read
those files — do not duplicate rules here.

Key constraints that apply to this story:
{List only story-specific constraints or exceptions — e.g. "this story touches
the auth layer; see the auth constraint in CLAUDE.md core-api section" or
"N/A — standard constraints apply, see CLAUDE.md"}.

## Definition of done
- [ ] All acceptance criteria implemented
- [ ] Test file written before implementation (API stories — TDD)
- [ ] All tests passing with no regressions
- [ ] Visual eval loop passed with zero high-severity issues (UI stories)
- [ ] COMPLETION.md written
- [ ] Jira status updated to Done after smoke test approval
```

---

### Step 9 — Ensure the epic feature branch exists

Each epic gets a single shared feature branch across all its stories. All
story commits stack on this branch; a single PR is opened when the last story
is done.

**Branch naming convention:** `feature/{epic-key-slug}`
- Lowercase, hyphenated
- Example: epic "EL-50 Email Ingestion" → `feature/el-50-email-ingestion`

**For each repo listed in the task file's `repos:` frontmatter:**

1. Check whether the branch already exists:
   ```
   git -C {repo-path} branch --list feature/{epic-key-slug}
   ```
2. If the branch does **not** exist locally, create it from the current
   default branch (`dev` or `main` — check which is used in that repo):
   ```
   git -C {repo-path} checkout -b feature/{epic-key-slug}
   ```
3. If the branch already exists, check it out:
   ```
   git -C {repo-path} checkout feature/{epic-key-slug}
   ```
4. Report to the user: "Switched {repo} to feature/{epic-key-slug}"

Do not push the branch yet — pushing happens in /close-story when the
last story for the epic is complete.

If git operations fail for a repo (e.g. uncommitted changes blocking
checkout), warn the user and do not block — the task file is still valid.
The user should resolve the git state manually before starting work.

---

### Step 10 — Transition the Jira ticket to In Progress

Use the Atlassian MCP to transition the ticket status to **In Progress**.

- Cloud ID: `b6770d30-bf33-4b84-8fd7-607d704d0cd1`
- Get available transitions first with `getTransitionsForJiraIssue`
- Find the transition ID for "In Progress"
- Apply the transition

If the transition fails: warn the user but do not block — the task file is
still valid. The user can update Jira manually.

If the story is not in **Ready** status when you fetch it: warn the user:
"This story is currently in '{status}' — expected Ready. Continue anyway?"
Wait for confirmation before writing the file.

---

### Step 11 — Launch implementation

Report a brief summary, then immediately spawn the implementation agent.
Do not wait for the user to invoke the next skill manually — launch it now
so the context from this conversation does not carry over.

```
✅ Task file created: tasks/task-{KEY}-{slug}.md
📋 Jira: EL-XXX → In Progress
📂 Target repo(s): {repo-1}, {repo-2}
🌿 Branch: feature/{epic-key-slug} (created | already exists)
⚠️  Warnings: {list any — missing ACs, missing Figma node, unexpected status, git issues, etc.}

Spawning implementation agent with a fresh context window...
```

**For API stories, Sync stories, and AI stories** — spawn a `tdd-start`
sub-agent immediately:

```
Agent({
  description: "TDD implementation of {KEY}",
  prompt: "Run /tdd-start for the task file at tasks/task-{KEY}-{slug}.md.
           The monorepo root is /Users/miken/SoftwareProjects/Spyglass/.
           Read only the task file to begin — do not read other files until
           the skill instructs you to. Follow every step in the tdd-start
           skill exactly. Report back when Step 7 (COMPLETION.md) is written."
})
```

**For UI stories** — tell the user to implement first, then invoke eval-ui:

```
UI story — no TDD sub-agent. Implement the component from the task file,
then run /eval-ui task-{KEY}-{slug}.md for visual verification.
```

**For HITL slices** — when the sub-agent encounters a HITL slice, it will
surface the decision to the user and pause. The user answers, then the
agent continues.

---

## Quick reference — project structure

Monorepo root: `/Users/miken/SoftwareProjects/Spyglass/`
Central tasks directory: `tasks/`
Base package (API): `com.spyglassanalytics.core.api`

| Repo | Language | Has .git | Purpose |
|---|---|---|---|
| `core-api` | Java 21 / Spring Boot 3.x | Yes | Backend REST API |
| `core-webui` | Angular 18 / TypeScript | Yes | Frontend web app |
| `RentManagerSyncSerivce` | Python 3.10+ | Yes | RentManager API → PostgreSQL data sync |
| `ai-service` | Python / FastAPI | Yes | AI content generation (Vertex AI / Gemini) |
| `infrastructure` | YAML / Terraform | No | Infrastructure as code |
| `tools` | JavaScript / Playwright | No | UI evaluation utilities |

Archive completed task files to `tasks/archive/` after smoke test approval.
