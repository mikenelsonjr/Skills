# Jira operation recipes (Atlassian MCP, direct)

These are the deterministic Jira sequences the skills use. They are recipes, not
a script: the model *decides whether* to run one; the steps *are* fixed. Encoding
them here stops each skill from re-improvising the multi-step MCP dance (the
source of "found the wrong transition id" flakiness).

**Cloud ID:** `b6770d30-bf33-4b84-8fd7-607d704d0cd1`
**Project:** `EL` · **Base browse URL:** `https://elevareiq.atlassian.net/browse/`

The Atlassian MCP tools are namespaced per session (e.g.
`mcp__claude_ai_Atlassian_Rovo__*` or `mcp__claude_ai_Atlassian__*`). Use whichever
prefix is live; the tool *names* below are stable.

---

## Recipe A — Transition a ticket by target state name

Never hardcode a transition id — they differ per issue/workflow. Always resolve
by name at call time.

1. `getTransitionsForJiraIssue` — `{ cloudId, issueIdOrKey: "EL-XXX" }`
2. From the returned list, find the transition whose **`to.name`** (or transition
   `name`) case-insensitively equals the target: `"In Progress"` / `"Done"`.
   - If no exact match, pick the closest (`"Start Progress"` → In Progress,
     `"Resolve"`/`"Close"` → Done) and **report which name you chose**.
   - If nothing plausibly matches, STOP and report the available names — do not
     force a random transition.
3. `transitionJiraIssue` — `{ cloudId, issueIdOrKey, transition: { id: "<matched id>" } }`

Failure is non-blocking for the pipeline: if the transition errors, warn and
continue — the commit/task file is still valid, the human can move it by hand.

---

## Recipe B — "Won't Do" / superseded (EL has NO Won't Do resolution)

The EL project runs a simplified workflow: there is **no "Won't Do" resolution**,
and the API **rejects a `resolution` field** on transition. To close something as
won't-fix or superseded:

1. Transition to **Done** via Recipe A (do NOT pass any `resolution`).
2. `createIssueLink` — link it to the superseding ticket with the appropriate
   type (e.g. `"is superseded by"` / `"relates to"`; resolve the exact type name
   via `getIssueLinkTypes` first).
3. `addCommentToJiraIssue` — one line stating why it was closed and what replaces
   it, so the audit trail carries the intent the missing resolution can't.

---

## Recipe C — Next Ready story in an epic (queue check)

Used by close-story to decide "was this the last story?" and to surface the next
actionable one.

JQL (substitute `{EPIC_KEY}` from the task file's `epic:` frontmatter, `{KEY}`
= the story just closed):

```
project = EL AND "Epic Link" = {EPIC_KEY} AND status != Done AND issueKey != {KEY} ORDER BY Rank ASC
```

Run via `searchJiraIssuesUsingJql` — `{ cloudId, jql, maxResults: 50 }`.

- **Zero results** → this was the last open story; the epic is complete → open the
  PR (git side).
- **Results** → more stories remain; skip the PR. The first row (Rank ASC) is the
  next candidate — but note the `api-story`-label caveat below.

**`api-story` label caveat:** the run-story/run-epic queue JQL filters to
`api-story`. rm-sync stories are labeled `ingestion`/`rm-sync`, NOT `api-story`,
so a naive queue can skip a genuinely-next rm-sync story and surface a
*blocked* api-story as if it were actionable. When picking "next Ready", either
include the sync labels or verify the top row isn't Blocked before declaring it
next.

---

## Recipe D — Add a comment / worklog

- Comment: `addCommentToJiraIssue` — `{ cloudId, issueIdOrKey, commentBody }`.
  `commentBody` may be plain text; the MCP wraps it in ADF.
- Worklog: `addWorklogToJiraIssue` — only if the pipeline is tracking time; not
  used by default.

---

## Reading a story (generate-task / refine-*)

`getJiraIssue` — `{ cloudId, issueIdOrKey, fields: [...] }`. Need: `summary`,
`description` (ADF — traverse for Figma links, see generate-task Step 5),
`labels`, `status`, `parent`/epic link, `issuelinks` (Blocks / is Blocked By).
`getJiraIssueRemoteIssueLinks` for Figma URLs stored as remote links.
