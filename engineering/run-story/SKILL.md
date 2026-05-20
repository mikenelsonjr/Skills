---
name: run-story
description: >
  Orchestrate the full implementation pipeline for a single Jira story.
  Runs generate-task → tdd-start as a sub-agent → smoke test gate → close-story
  as a sub-agent. Each skill runs in a fresh context window. You only intervene
  at HITL slices and the smoke test gate.
  Usage: /run-story EL-101
---

# run-story

Drives one story from Jira ticket to committed, closed, and archived — with
you approving at the smoke test gate and any HITL decision points.

Each phase spawns a sub-agent with a fresh context window. This keeps
accumulated conversation context from inflating costs across a long story.

## Invocation

```
/run-story EL-101
```

---

## Phases

```
Phase 1: generate-task   (sub-agent, AFK)
Phase 2: tdd-start       (sub-agent, AFK — pauses at HITL slices)
Phase 3: smoke test gate (YOU — manual verification in the running app)
Phase 4: close-story     (sub-agent, AFK)
```

---

## Instructions

### Step 1 — Validate the ticket

Before spawning anything, fetch the story from Jira and confirm it is in
**Ready** status.

- Cloud ID: `b6770d30-bf33-4b84-8fd7-607d704d0cd1`
- Fetch: summary, status, labels, parent epic

If the story is not Ready, stop:
```
⛔ {KEY} is in '{status}' — expected Ready.
Move the story to Ready in Jira before running /run-story.
```

If the story has no `api-story` or `ui-story` label, warn the user and ask
whether to continue. Do not stop — the user may have a reason.

---

### Step 2 — Phase 1: generate-task (sub-agent)

Spawn a sub-agent to generate the task file:

```
Agent({
  description: "generate-task for {KEY}",
  prompt: "Run /generate-task {KEY}.
           Monorepo root: /Users/miken/SoftwareProjects/Spyglass/
           Follow every step in the generate-task skill exactly.
           Do NOT spawn any implementation sub-agent at Step 11 —
           report back to the orchestrator instead.
           When complete, return:
             - task filename (e.g. task-{KEY}-{slug}.md)
             - list of target repos
             - list of vertical slices with AFK/HITL classification
             - any warnings (missing ACs, missing Figma, git issues)"
})
```

Wait for the sub-agent to return.

**If warnings include missing ACs:** stop and surface to the user — the
story cannot be implemented without acceptance criteria.

**If warnings include missing Figma (UI story):** surface to the user and
ask whether to continue without visual eval.

Report to the user:
```
✅ Phase 1 complete — task file ready
📄 tasks/{task-filename}
📂 Repos: {repo-1}, {repo-2}
🔀 Slices: {n} AFK, {n} HITL
⚠️  Warnings: {list or "none"}
```

---

### Step 3 — Phase 2: tdd-start (sub-agent)

For **API stories, Sync stories, and AI stories** — spawn the implementation
sub-agent:

```
Agent({
  description: "tdd-start for {KEY}",
  prompt: "Run /tdd-start {task-filename}.
           Monorepo root: /Users/miken/SoftwareProjects/Spyglass/
           Follow every step in the tdd-start skill exactly.
           Context discipline: read only the task file and CLAUDE.md on startup.
           Pull source files on demand as each step requires them.
           When you reach a HITL slice: stop, describe the decision needed,
           and report back — do not guess or proceed past a HITL gate.
           When COMPLETION.md is written, report back with:
             - test results summary (pass/fail counts per repo)
             - smoke test checklist from the completion report
             - any notes or deferred items"
})
```

**HITL pause handling:** If the sub-agent reports back with a HITL decision,
surface it to the user in this format:

```
⏸ HITL gate — slice {n}: {slice description}

Decision needed: {what the agent cannot decide alone}

Your options:
  A) {option 1}
  B) {option 2}
  (or describe a different approach)
```

Wait for the user's answer, then re-prompt the sub-agent with the decision
and tell it to continue from the HITL slice.

**For UI stories:** Skip the tdd-start sub-agent. Tell the user:
```
⏸ UI story — implement the component manually from tasks/{task-filename},
then run /eval-ui {task-filename} when ready.
Reply "done" when implementation is complete.
```
Wait for "done" before proceeding to Step 4.

When the sub-agent finishes, report:
```
✅ Phase 2 complete — implementation done
📋 Tests: {n} passing, 0 failing ({repos})
```

---

### Step 4 — Smoke test gate

This is the only step that requires you to manually exercise the running app.

Present the smoke test checklist from the completion report:

```
⏸ Smoke test required — {KEY}

Start the app (docker-compose up -d) if it is not already running.

Smoke test checklist:
{paste the checklist table from COMPLETION.md verbatim}

Reply "approved" when all items are checked, or describe any failures.
```

**Wait for explicit "approved".** Do not proceed on ambiguous replies.

If the user reports a failure: ask for details, then decide whether to
re-spawn tdd-start to fix the issue or address it inline. Do not call
close-story until the user has approved.

---

### Step 5 — Phase 4: close-story (sub-agent)

On smoke test approval, spawn the close-story sub-agent:

```
Agent({
  description: "close-story for {KEY}",
  prompt: "Run /close-story {KEY}.
           Monorepo root: /Users/miken/SoftwareProjects/Spyglass/
           The smoke test has already been approved by the user — skip the
           smoke test confirmation prompt and proceed directly to Step 2.
           Follow every step in the close-story skill exactly.
           Spawn review and security-review sub-agents as instructed in
           the skill (do not run them inline).
           Report back with:
             - commit hash(es)
             - Jira status
             - PR URL (if this was the last story in the epic)
             - next Ready story in the queue (if any)"
})
```

Wait for the sub-agent to return.

---

### Step 6 — Report and hand off

```
✅ {KEY} complete

📋 Jira: {KEY} → Done
🔀 Commit: {hash} ({repo})
📁 Task files archived
{🚀 PR: {url}  ← only if last story in epic}

{If next story exists:}
Next story in queue: {NEXT_KEY} — {title}
Run /run-story {NEXT_KEY} to continue, or /run-epic {EPIC_KEY} to drive
the rest of the epic automatically.

{If queue is empty:}
⏸ Queue empty — no Ready stories remaining.
```

Send a smoke-test-approved notification via the notify skill:
```
/notify complete {KEY}
```
