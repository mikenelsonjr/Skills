---
name: run-epic
description: >
  Orchestrate the full implementation pipeline for all Ready stories in a
  Jira epic. Iterates over stories in priority order, running /run-story for
  each one. Pauses at every smoke test gate for your approval. Opens a PR
  when the last story closes.
  Usage: /run-epic EL-50
---

# run-epic

Drives all Ready stories in an epic to Done, one at a time, with you
approving at each smoke test gate.

Delegates each story entirely to /run-story — this skill is purely an
iterator and progress tracker. All the context-management and sub-agent
discipline lives in run-story.

## Invocation

```
/run-epic EL-50
```

Replace `EL-50` with the Jira epic key.

---

## Instructions

### Step 1 — Load the epic

Fetch the epic and all its stories from Jira.

- Cloud ID: `b6770d30-bf33-4b84-8fd7-607d704d0cd1`
- Fetch the epic: summary, description, status
- Fetch all child stories: key, summary, status, labels, priority

If the epic does not exist or has no stories, stop and report.

Filter to stories in **Ready** status only. Sort by priority ascending,
then by created date ascending (oldest first).

If no stories are in Ready status:
```
⛔ No Ready stories found in epic {KEY}.
Move stories to Ready in Jira to begin.
```

---

### Step 2 — Show the plan

Present the work queue to the user before doing anything:

```
Epic: {EPIC_KEY} — {epic title}

Ready stories ({n}):
  1. {KEY1}: {title} ({type}, {estimate})
  2. {KEY2}: {title} ({type}, {estimate})
  ...

Not Ready (skipped for now):
  - {KEY}: {title} — {status}
  ...

This will run each story through the full pipeline:
  generate-task → tdd-start → [your smoke test] → close-story

You will be paused at the smoke test gate for every story, and at any
HITL decision points within a story.

Ready to start? (yes / no / start from {KEY} to skip earlier stories)
```

Wait for confirmation before proceeding.

---

### Step 3 — Iterate over stories

For each story in the queue, in order:

#### 3a — Run the story

Invoke `/run-story {KEY}` for the current story. Follow all steps in the
run-story skill exactly — this is not a sub-agent call, it is a direct
invocation of the run-story skill in this conversation so the smoke test
gate and HITL pauses surface to you directly.

#### 3b — Record the outcome

After each story completes, update a running progress summary:

```
Epic {EPIC_KEY} progress:
  ✅ {KEY1}: {title} — Done (commit {hash})
  🔄 {KEY2}: {title} — In progress...
  ⏳ {KEY3}: {title} — Waiting
```

#### 3c — Handle failures

If a story fails (tests can't pass, smoke test rejected, blocking review
finding):

```
⛔ {KEY} blocked — {reason}

Options:
  A) Fix and retry — describe what to change
  B) Skip this story and continue with the next
  C) Abort the epic run
```

Wait for the user's choice. Do not auto-retry or skip without instruction.

---

### Step 4 — Epic complete

When all Ready stories are Done:

```
🎉 Epic {EPIC_KEY} complete

Stories delivered:
  ✅ {KEY1}: {title}
  ✅ {KEY2}: {title}
  ...

{If PR was opened by the last close-story:}
🚀 PR: {url}

{If stories remain in other statuses:}
⚠️  {n} stories not in Ready were skipped:
  - {KEY}: {title} — {status}
  Move them to Ready and run /run-epic {EPIC_KEY} again to continue.
```

---

## Notes

- **run-story is the unit** — this skill adds no orchestration logic of its
  own. If run-story behaviour changes, run-epic inherits the improvement
  automatically.
- **Smoke test gates are per-story** — you approve each story individually.
  There is no "approve all" shortcut; each smoke test is a real verification.
- **Partial runs are safe** — if you abort mid-epic, completed stories are
  already committed and Done in Jira. Run `/run-epic {EPIC_KEY}` again and
  it will pick up only the remaining Ready stories.
- **HITL slices surface here** — when run-story pauses for a HITL decision,
  you answer in this conversation and run-story resumes. No special handling
  needed at the epic level.
