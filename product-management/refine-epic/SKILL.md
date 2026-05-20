---
name: refine-epic
description: >
  Scan all stories in a Jira epic, score each one for quality, and refine
  weak stories in sequence. Shows a summary of what needs work before
  starting, then runs the refine-story flow for each weak story.
  Usage: /refine-epic EL-50
---

# refine-epic

Scans every story in an epic, identifies which ones are underspecified,
and refines them one by one — asking questions, drafting, getting your
approval, and updating Jira before moving to the next.

## Invocation

```
/refine-epic EL-50
```

Pass the epic key. All child stories will be scanned.

---

## Instructions

### Step 1 — Pull the epic and all child stories

Fetch the epic from Jira via Atlassian MCP, then fetch all stories
linked to it.

Cloud ID: `b6770d30-bf33-4b84-8fd7-607d704d0cd1`

JQL to fetch stories in the epic:
```
project = EL AND "Epic Link" = {EPIC_KEY} ORDER BY created ASC
```

If no stories are found, try:
```
project = EL AND parent = {EPIC_KEY} ORDER BY created ASC
```

For each story, pull: summary, description, labels, status, priority,
issue links.

---

### Step 2 — Score each story

Evaluate every story against the quality rubric:

| Signal | Issue |
|---|---|
| Missing `api-story` / `ui-story` label | MISSING TYPE |
| Description vague or < 3 sentences | WEAK DESCRIPTION |
| No ACs, or ACs are checkbox-only (no Given/When/Then) | MISSING/WEAK ACS |
| UI story with no eval-tier set | MISSING EVAL TIER |
| No estimate (S/M/L) | MISSING ESTIMATE |
| Done or In Progress status | SKIP — already worked |

Stories with status Done or In Progress are skipped entirely.

For each story in To Do or Ready, count the number of issues found.

---

### Step 3 — Show the quality summary

Before refining anything, show the user a summary table so they can
decide what to prioritise:

```
**Epic: {EL-50} — {epic name}**
Scanned {n} stories ({skipped} skipped — already in progress or done)

| Key | Title | Issues found | Needs work? |
|-----|-------|-------------|-------------|
| EL-45 | New customer onboarding | MISSING ACS, MISSING TYPE | ✅ Yes |
| EL-49 | Tenant provisioning workflow | WEAK DESCRIPTION | ✅ Yes |
| EL-52 | Fix dashboard filter | None | ✅ Good |
| EL-66 | User management screens | MISSING ACS, MISSING EVAL TIER | ✅ Yes |

{n} stories need attention. Ready to refine them?

Options:
  "all" — refine all weak stories in order
  "EL-45, EL-66" — refine specific stories only
  "skip EL-49" — refine all except the ones listed
  "stop" — exit without refining
```

Wait for the user's response before proceeding.

---

### Step 4 — Refine stories in sequence

For each story selected for refinement, run the full refine-story flow:

**4a — Diagnose and ask questions**

Evaluate the story against the quality rubric. Identify:
- Gaps answerable from context (resolve without asking)
- Gaps that need the user's input

If questions are needed:

```
─────────────────────────────────
**Story {n} of {total}: {KEY} — {title}**
─────────────────────────────────

I found these gaps I need to clarify:

1. {Question}
2. {Question}

(or reply "skip this one" to move on)
```

If no questions needed, announce the story and proceed directly to the draft.

**4b — Draft**

Using original content + inferences + user answers, write the complete
rewrite following the refine-story template:
- Improved title (if vague)
- Type label
- 2-4 sentence description
- Background (if useful)
- Full AC set in Given/When/Then format
- eval-tier for UI stories
- Dependencies
- Out of scope

**4c — Show for approval**

```
Here's the updated story for {KEY}:

{full draft}

─────────────────────────────────
Approve this? ("yes" / tell me what to change / "skip")
```

Apply requested edits and show revised draft until approved or skipped.

**4d — Update Jira**

On approval, update the story via Atlassian MCP:
- Summary, description, labels, dependencies

Confirm the update, then immediately move to the next story.

---

### Step 5 — Final report

After all stories are processed:

```
**Epic {KEY} refinement complete**

| Story | Result |
|-------|--------|
| EL-45 | ✅ Updated — 5 ACs written, type: api-story |
| EL-49 | ✅ Updated — description rewritten, estimate: M |
| EL-66 | ⏭ Skipped by user |
| EL-52 | ✅ Already good — no changes needed |

{n} stories updated. {m} skipped. {k} already complete.

Stories updated to Ready-eligible: {list any that now meet all rubric
criteria and could be promoted}
```

---

## Pacing notes

- Never ask more than 5 questions per story
- Never update Jira without explicit approval for that story
- If the user says "just write it" or "make reasonable assumptions",
  skip questions and go straight to the draft
- Keep the inter-story transitions brief — one line then the next story
- If the user goes quiet mid-session, pick up where you left off when
  they return — do not restart from the beginning

## Context references

Project conventions (error shapes, auth pattern, Resident vs tenant,
customer isolation, eval tiers):
https://elevareiq.atlassian.net/wiki/x/AoCMBQ

AC templates:
https://elevareiq.atlassian.net/wiki/x/AgCRBQ
