---
name: refine-story
description: >
  Refine a poorly specified Jira story. Pulls the story, diagnoses what's
  missing or weak, asks targeted questions, rewrites with proper description
  and ACs, then updates Jira on your approval.
  Usage: /refine-story EL-101
---

# refine-story

Pulls a Jira story, diagnoses quality gaps, asks only what's genuinely
ambiguous, drafts an improved story, and updates Jira after your approval.

## Invocation

```
/refine-story EL-101
```

---

## Quality rubric

A story is considered complete when it has ALL of the following:

| Signal | Complete | Incomplete |
|---|---|---|
| Type label | `api-story` or `ui-story` present | No label |
| Description | Clear problem + user value, > 3 sentences | Vague or one-liner |
| Acceptance criteria | **Every AC** in Given/When/Then format, covers happy path + auth + error | Checkbox list, plain bullets, or missing entirely — all are incomplete |
| Vertical coverage | Every AC describes an observable end-user or API-consumer outcome | Any AC describes an internal implementation step ("add a method", "create a table", "update a DTO") |
| Story type specific | API: error contract defined. UI: eval-tier set | Not present |
| Dependencies | Explicitly stated or "None" | Not mentioned |
| Estimate | S / M / L present | Not set |

---

## Instructions

### Step 1 — Pull the story

Fetch the full story from Jira via Atlassian MCP.
- Cloud ID: `b6770d30-bf33-4b84-8fd7-607d704d0cd1`
- Pull: summary, description, labels, status, parent epic, issue links, priority

If the story does not exist, stop and report.

---

### Step 2 — Diagnose

Evaluate the story against every item in the quality rubric. Produce an
internal diagnosis listing each gap. Do not show this diagnosis to the user
yet — use it to form your questions.

Classify each gap as:
- **Answerable from context** — you can infer it from the story + project
  context without asking (e.g. story is clearly about an API endpoint so
  type = api-story)
- **Needs clarification** — genuinely ambiguous, you need the user's input

Resolve answerable gaps yourself. Only ask about genuinely ambiguous ones.

**Vertical coverage check:** For each AC, ask: does this describe something
an end-user or API consumer can observe? Or does it describe how the system
is built internally?

- Observable: "When X is requested, the response includes fields A, B, C" ✅
- Observable: "When the user submits the form, a success banner appears" ✅
- Implementation step: "Add a `count` field to the DTO" ✗ — reframe it
- Implementation step: "Create a service method that queries the table" ✗ — reframe it
- Implementation step: "Run a Flyway migration to add column X" ✗ — this is
  a consequence of an AC, not an AC itself

Reframe any implementation-step ACs as observable outcomes. This is an
answerable-from-context gap — you do not need to ask the user.

---

### Step 3 — Ask targeted questions

If there are gaps that need clarification, show the user a brief diagnosis
summary followed by your questions. Keep questions to a maximum of 5.
Group related questions together. Be specific — reference the story by name.

Format:

```
**EL-101: {story title}**

I've reviewed this story and found a few things I need to clarify before
I can write proper ACs:

1. {Question about the most critical gap}
2. {Question about the next gap}
...

Once you answer these I'll draft the full updated story for your review.
```

If there are NO gaps that need clarification (you can resolve everything
from context), skip this step and go straight to Step 4.

---

### Step 4 — Draft the improved story

Using the original story content, your inferences, and the user's answers,
write a complete rewrite. Follow this structure exactly:

```
## {Story title — improve it if vague}

**Type:** API Story | UI Story
**Epic:** {epic key and name}
**Estimate:** S | M | L
**Labels:** api-story | ui-story

---

### Description
{2-4 sentences. What is being built, why it matters to the PM,
what system or data it touches. No bullet points.}

### Background
{Optional — only if there's useful context about why this story exists,
what it replaces, or what problem it solves. Omit if not needed.}

### Acceptance criteria

{API stories — Given/When/Then per scenario:}

AC1 (Happy path):
  Given {valid input and auth}
  When {action}
  Then {specific response — status code, fields, types}
  AFK — agent can implement and verify autonomously

AC2 (Auth / access control):
  Given {wrong customer or missing token}
  When {same action}
  Then {403}
  AFK — standard auth pattern, no judgment needed

AC3 (Missing / degraded data):
  Given {upstream data absent}
  When {action}
  Then {graceful response}
  AFK | HITL — use AFK if fallback is obvious (empty list, 404); use HITL if
  fallback behavior is a product decision

AC4 (Downstream failure):
  Given {upstream service down}
  When {action}
  Then {fallback behavior}
  HITL — requires human decision: {what the agent cannot decide alone}

AC5 (Validation):
  Given {invalid input}
  When {action}
  Then {400 with details}
  AFK — validation rules are fully specified in the AC

{UI stories — eval tier + visual and behavioral ACs:}

eval-tier: 1 | 2 | 3
Figma node: {id} | N/A

Visual ACs:
  AC1: {Specific visual requirement}
  AFK — agent implements to match Figma; eval-ui verifies visually
  ...

Behavioral ACs (Given/When/Then):
  AC_:
    Given {user is on the page / component is rendered}
    When {user interaction or state change}
    Then {observable outcome — UI state, emitted event, service call}
    AFK | HITL — {AFK if behavior is fully specified; HITL if interaction design needs a decision}

### Dependencies
{EL-XX: story title — must be Done before this starts}
{None}

### Out of scope
{What this story deliberately does not cover — helps the agent avoid
over-engineering}
```

---

### Step 5 — Show for approval

Present the full draft and ask:

```
Here's the updated story. Does this look right, or would you like to
change anything before I update Jira?

(Reply "looks good" to update, or tell me what to change)
```

Wait for explicit approval. Do not update Jira without it.
Apply any edits the user requests and show the revised draft again
before updating.

---

### Step 6 — Update Jira

On approval, update the Jira story via Atlassian MCP:
- Update `summary` if the title was improved
- Update `description` with the full rewrite
- Add `api-story` or `ui-story` label
- Update `priority` / estimate if you can map S/M/L to the Jira field
- Add dependency issue links if identified

Report:
```
✅ EL-101 updated in Jira.
   Title: {new title if changed}
   Labels: {labels added}
   ACs: {n} acceptance criteria written
   Dependencies: {linked stories or "None"}
```

---

## Notes for writing good ACs

- **Every AC must be Given/When/Then** — no exceptions, no plain bullets.
  This is a hard requirement: /tdd-start maps each Gherkin AC directly to
  one test method (Arrange = Given, Act = When, Assert = Then). ACs that
  aren't Gherkin cannot be systematically tested.
- **ACs describe outcomes, not implementation** — "The response includes a
  `total_count` field" is a good AC. "Add a `total_count` field to the DTO"
  is an implementation task, not an AC. If an AC could appear verbatim in
  a commit message, it's probably an implementation step — reframe it as
  what the user or API consumer observes.
- **AFK vs HITL** — every AC gets one of these tags. AFK means the agent
  can implement and verify it autonomously without any human judgment.
  HITL means there is a decision the agent cannot make alone: an ambiguous
  business rule, a design choice, an external credential, or a product policy.
  Being explicit here prevents the agent from guessing or stalling mid-slice.
- Reference the project context document for error shape, auth pattern,
  and response conventions:
  https://elevareiq.atlassian.net/wiki/x/AoCMBQ
- Customer isolation: every data AC must imply scoping by `customerUuid`
- Use `Resident` not "tenant" for property occupants
- UI eval-tier decision:
  - Tier 1 if a Figma node exists or will exist
  - Tier 2 if it's a targeted visual change with no Figma frame
  - Tier 3 if purely behavioral (no visible change)
