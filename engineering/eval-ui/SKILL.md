---
name: eval-ui
description: >
  Run the visual evaluation loop for a UI story. Screenshots the running
  Angular component via Playwright, fetches the Figma design via Figma MCP,
  then compares both images directly using Claude's vision. No separate API
  key needed — Claude Code does the comparison in the current session.
  Usage: /eval-ui task-EL-101-some-slug.md
---

# eval-ui

Runs the visual evaluation loop for a UI story. Claude Code handles the
visual comparison directly — Playwright captures the implementation,
Figma MCP exports the design, and Claude compares them in the same session.

No ANTHROPIC_API_KEY required. This uses your existing Claude Code session.

## Invocation

```
/eval-ui task-EL-101-some-slug.md
```

---

## Prerequisites

1. **Angular dev server is running:**
   ```
   cd core-webui && ng serve
   ```

2. **Figma MCP is connected** in this Claude Code session.
   Verify by checking available tools — Figma tools should be listed.

3. **eval-ui dependencies installed:**
   ```
   cd /path/to/eval-ui && npm install && npm run install-browsers
   ```

4. **Auth state captured** (if not already done):
   ```
   node /path/to/eval-ui/setup-auth.js
   ```

---

## Instructions

### Step 1 — Read and validate the task file

Read `core-webui/tasks/{filename}`.

Extract:
- Ticket key from `ticket:` frontmatter
- Figma node ID from the **Figma reference** section
- Figma file key from `FIGMA_FILE_KEY` env var or task file
- App route from the story description or behavioral ACs
- Story type must be **UI Story** — stop if API Story

If Figma node ID is missing or marked `⚠️ NOT SET`:
  Do not stop silently. Ask the user:
  "The Figma node ID is not set in the task file. Do you have a Figma URL?
  Paste it and I will extract the node ID and update the task file, then continue."

  If the user provides a URL:
  - Extract `fileKey` (path segment after `/design/`) and `node-id` query param
  - Normalize node ID to `:` separator (e.g. `0-1` → `0:1`)
  - Update the task file's **Figma reference** section with the node ID and URL
  - Continue to Step 2

  If the user cannot provide a URL, stop and explain that eval-ui cannot run
  without a Figma reference.

If route cannot be determined:
  Ask the user: "What route should Playwright navigate to for this component?"

---

### Step 2 — Check dev server

```bash
curl -s -o /dev/null -w "%{http_code}" http://localhost:4200
```

If not 200/301/302: stop and tell the user the dev server is not running.

---

### Step 3 — Eval loop (up to 3 passes)

Run up to 3 passes. Each pass follows steps 3a → 3b → 3c → 3d.

**3a — Take Playwright screenshot**

```bash
EVAL_SCRIPT=/path/to/eval-ui/eval-ui.js

node $EVAL_SCRIPT \
  --route   "{APP_ROUTE}" \
  --output  core-webui/tasks/eval-screenshot-pass{N}.png
```

If exit code 1 (auth redirect detected): stop and tell the user to
re-run setup-auth.js to refresh the session.

**3b — Get Figma design image**

Use the Figma MCP `get_screenshot` tool to export the design node as an
image. Pass the Figma file key and node ID from the task file.

The Figma node ID format for the MCP may use `-` or `:` as separator —
try both if one fails (e.g. `123:456` and `123-456`).

Cache the design image to `core-webui/tasks/eval-design.png` on
the first pass — do not re-fetch on subsequent passes since the design
has not changed.

**3c — Compare images directly (no API call needed)**

You now have two images:
- `eval-screenshot-pass{N}.png` — the implementation
- `eval-design.png` — the Figma reference design

Read both files and compare them visually using your own vision. Evaluate
the implementation against the design and produce a structured assessment
in this exact JSON format (write it to
`core-webui/tasks/eval-result-pass{N}.json`):

```json
{
  "pass": false,
  "summary": "one sentence overall assessment",
  "high_severity": [
    {
      "element": "concise element name, e.g. card header",
      "issue": "specific problem, e.g. padding 16px should be 24px",
      "fix": "actionable CSS/class fix, e.g. change p-4 to p-6"
    }
  ],
  "medium_severity": [ ...same shape... ],
  "low_severity":    [ ...same shape... ]
}
```

Severity definitions:
- **HIGH** — wrong component, element missing, broken layout, wrong text
  content, spacing >= 16px off, wrong color family
- **MEDIUM** — correct color family but wrong shade, wrong typography,
  spacing 8–15px off, icon wrong but similar
- **LOW** — spacing < 8px off, subtle shade variation, minor alignment

`pass = true` only when `high_severity` is empty.

Focus on structure and layout — ignore differences in real data values
(names, amounts, dates). Ignore browser scrollbars.

**3d — Decide next action**

- If `pass: true` → exit loop, proceed to Step 4 (COMPLETION.md)
- If `pass: false` AND passes remaining → apply fixes and go to next pass
- If `pass: false` AND max passes reached → proceed to Step 5 (escalation)

**Applying fixes between passes:**
Read the `high_severity` array from the result JSON. Each item has a
specific `fix` instruction. Apply each fix to the relevant component
file. Apply the minimum change — do not refactor unrelated code.
After applying all fixes, increment pass counter and run Step 3a again.

---

### Step 4 — Pass path: write COMPLETION.md

Write `core-webui/tasks/completion-{TICKET_KEY}-{slug}.md`:

```markdown
---
ticket: {TICKET_KEY}
status: PASS
completed: {YYYY-MM-DD}
---

# COMPLETION: {TICKET_KEY} — {story summary}

## Visual eval results
Status: PASS
Passes: {n} of 3

## AC results

| AC | Type | Result |
|----|------|--------|
| AC1 | Visual | ✅ Pass — zero high-severity issues |
| AC2 | Behavioral | ✅ Pass |

## Remaining low/medium issues (non-blocking)
{List any from final result JSON — for reviewer awareness during smoke test}

## Files changed
- `{file}` — {what changed}

## Notes
{Anything reviewer should know}

## Ready for smoke test
yes
```

Then call `/notify complete {TICKET_KEY}`.

---

### Step 5 — Escalation path: write COMPLETION.md

Write `core-webui/tasks/completion-{TICKET_KEY}-{slug}.md`:

```markdown
---
ticket: {TICKET_KEY}
status: NEEDS_REVIEW
completed: {YYYY-MM-DD}
---

# COMPLETION: {TICKET_KEY} — {story summary}

## Visual eval results
Status: NEEDS_REVIEW — max passes reached with unresolved HIGH issues
Passes: 3 of 3

## Unresolved HIGH severity issues
{Copy from final eval-result-pass3.json high_severity array}

## Screenshot progression
- Pass 1: tasks/eval-screenshot-pass1.png
- Pass 2: tasks/eval-screenshot-pass2.png
- Pass 3: tasks/eval-screenshot-pass3.png

## Ready for smoke test
no — human review needed for unresolved visual issues above
```

Then call `/notify complete {TICKET_KEY}`.

---

## Env var reference

| Variable | Required | Default | Notes |
|---|---|---|---|
| `APP_BASE_URL` | No | `http://localhost:4200` | Dev server URL |
| `FIGMA_FILE_KEY` | Yes* | — | From Figma file URL after `/design/` |

*`FIGMA_FILE_KEY` is needed by the Figma MCP tool. Set in `~/.zshrc`:
```bash
export FIGMA_FILE_KEY="abcXYZ123..."
```

**No `ANTHROPIC_API_KEY` needed.** The visual comparison is done by
Claude Code in the current session using its native vision capabilities.
