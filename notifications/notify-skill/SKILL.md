---
name: notify
description: >
  Send a notification email via Gmail MCP. Two triggers:
  1. Story complete and ready for smoke test
  2. Queue empty, agent is waiting for new work

  Called automatically by close-story (queue empty check) and tdd-start
  (on completion). Can also be invoked manually:
  /notify complete EL-101
  /notify empty
---

# notify

Sends a notification email to Mike so he can action a completed story or
replenish the queue. Designed to reach him on his work laptop while the
dev laptop is running unattended.

Recipient: always send to the same address Claude Code is authenticated
with via the Gmail MCP. This is Mike's personal Google account which he
checks throughout the day.

---

## Invocation

```
/notify complete EL-101
/notify empty
```

- `complete EL-101` — story is done, smoke test needed
- `empty` — queue exhausted, agent is waiting

---

## Instructions

### Step 1 — Determine trigger type

Read the argument:
- First word is `complete` → Trigger A (story ready for smoke test)
- First word is `empty` → Trigger B (queue empty)
- No argument or unrecognised → ask the user which trigger to use

---

### Step 2 — Gather content for the email

**Trigger A — story complete:**

Read the completion file for the ticket: `{repo}/tasks/completion-{KEY}-*.md`

Extract:
- Story title (from the `# COMPLETION:` heading)
- Ticket key
- AC results table — pass/fail per AC
- Files changed list
- Ready for smoke test: yes/no
- Any notes the agent left

Also read the task file `{repo}/tasks/task-{KEY}-*.md` to get:
- Epic name
- Jira URL
- Story type (api-story / ui-story)

If completion file is not found: send the email with what is known from
the ticket key alone and note the missing report.

**Trigger B — queue empty:**

Query Jira for current queue state:
- Count of stories in Ready status
- Count of stories in To Do status (drafted but not yet Ready)
- The highest-priority epic with unstarted work

Use JQL:
```
project = EL AND status = "To Do" ORDER BY priority ASC
```
Tracker ID: `{tracker_id}` (default `b6770d30-bf33-4b84-8fd7-607d704d0cd1`)

---

### Step 3 — Check Gmail MCP availability

Before attempting to send, verify the Gmail MCP is connected by listing
available tools. If Gmail MCP is not available, fall through to Step 5
(fallback output).

To check: attempt to list or describe available Gmail tools. The MCP
server URL is `https://gmailmcp.googleapis.com/mcp/v1`. If tools are
available, proceed to Step 4. If not, go to Step 5.

---

### Step 4 — Send the email via Gmail MCP

Use the Gmail MCP send tool to send the appropriate email.

The Gmail MCP send tool typically accepts: `to`, `subject`, `body` (plain
text or HTML). Use whichever parameter names the tool exposes — check the
tool schema before calling.

---

#### Trigger A email — story complete

**Subject:**
```
✅ EL-{KEY} ready for smoke test — {story title}
```

**Body:**
```
{story title}
{epic name} · {api-story | ui-story}

All automated checks passed. Ready for your smoke test.

ACCEPTANCE CRITERIA
{AC results table formatted as plain text, e.g.:}
  AC1 ✅  Given valid lease ID, returns renewal recommendation
  AC2 ✅  Returns 403 when lease not owned by customer
  AC3 ✅  Returns LOW confidence when no market data

FILES CHANGED
{list of changed files, one per line}

NOTES
{agent notes from completion report, or "None"}

LINKS
  Jira:  {jira_base_url}{KEY}      # default https://elevareiq.atlassian.net/browse/
  Task:  {repo}/tasks/task-{KEY}-{slug}.md

---
Run /close-story EL-{KEY} on the dev laptop once you're happy with it.
```

---

#### Trigger B email — queue empty

**Subject:**
```
⏸ Agent queue empty — ready for new work
```

**Body:**
```
The Ready queue is empty. The agent is idle and waiting.

QUEUE STATUS
  Ready:  0 stories
  To Do:  {n} stories (drafted, not yet promoted)

NEXT UP
  Highest-priority epic with unstarted work:
  {epic key}: {epic name}

  Stories in To Do under this epic:
  {list up to 5 story keys + titles}

TO RESUME
  Review and promote stories to the ready state in the tracker:
  {jira_base_url}{project_key}     # default https://elevareiq.atlassian.net/browse/EL

  Then on the dev laptop, run:
  /generate-task {next story key}

---
Agent is standing by.
```

---

### Step 5 — Fallback if Gmail MCP not available

If the Gmail MCP is not connected, print the full email to the terminal
output instead so the content is not lost:

```
⚠️  Gmail MCP not available — email content below.
Copy and send manually if needed.

─────────────────────────────────────────
Subject: {subject}

{body}
─────────────────────────────────────────
```

This ensures the notification content is always produced even if the
send fails.

---

### Step 6 — Confirm and report

After sending (or fallback output):

```
📧 Notification sent: "{subject}"
   Trigger: {complete EL-XXX | empty}
   Method: {Gmail MCP | terminal fallback}
```

---

## Calling context

This skill is called from two places:

**From `/close-story`** (queue empty check, Step 9):
The close-story skill checks for remaining Ready stories after committing.
If the queue is empty it calls `/notify empty` automatically.

**From `/tdd-start`** (story complete, Step 8):
After writing COMPLETION.md, tdd-start calls `/notify complete EL-XXX`
to alert you the story is ready for smoke testing.

Both callers pass the correct argument — you do not need to determine the
trigger from context when called this way.
