---
name: run-story
description: >
  Orchestrate the full implementation pipeline for a single Jira story (v2).
  Runs generate-task --draft → scout → verify-task → PRE-FREEZE REVIEW (you chat
  and edit the task doc) → generate-task --freeze → tdd-start → independent
  verify → smoke-runner pre-flight → smoke gate → close-story. Each phase runs
  as a fresh-context sub-agent. You intervene at the pre-freeze review, HITL
  slices, and the smoke gate. Usage: /run-story EL-101
---

# run-story (v2)

Drives one story from Jira ticket to committed, closed, and archived. v2 adds a
**reconnaissance-then-review** front end: the codebase is read for ground truth
(scout) and the draft task doc is adversarially checked for undecidable or
repo-contradicting assumptions (verify-task) **before** the acceptance spec
freezes. Then you review, chat, and edit the doc — and only on your explicit
approval does the spec freeze and the build begin.

The design goal of the front end is a **good, detailed, reality-checked spec for
the implementer**. Freezing is the point of no return (the contract must predate
the code), so every reshaping happens before it.

Each phase spawns a sub-agent with a fresh context window to keep accumulated
conversation from inflating cost across a long story.

> **v1 is preserved, commented out, at the bottom of this file.** v2 is the live
> skill. Promote/rollback by moving the comment boundary.

## Invocation

```
/run-story EL-101
```

---

## Phases

```
Phase 0  Pre-flight       (orchestrator — ticket Ready? git hygiene?)
Phase 1  generate-task --draft   (sub-agent — DRAFT doc + spec NAMES, no freeze)
Phase 2  scout            (sub-agent — read-only Recon Report)
Phase 3  verify-task      (sub-agent — contradictions + open questions)
Phase 3b Merge recon into the draft doc   (orchestrator)
⏸ REVIEW  Pre-freeze gate  (YOU — review, chat, edit, answer open questions)
Phase 4  generate-task --freeze  (sub-agent — write + commit frozen suite)
Phase 5  tdd-start        (sub-agent — RED→GREEN against frozen spec; HITL pauses)
Phase 6  verify           (sub-agent — independent clean-checkout re-check)
Phase 6b smoke-runner     (sub-agent — drives the running app; per-row evidence)
⏸ GATE    Smoke test       (YOU — confirm evidence + judge what automation can't)
Phase 7  close-story      (sub-agent — commit / Jira Done / archive / PR)
```

Two truth gates make the pipeline trustworthy: **Phase 3** (verify-task) catches
"Jira-correct but repo-contradicting" before code exists; **Phase 6** (verify)
catches "passes the builder's own tests but is actually wrong" after code exists,
from a clean checkout, never trusting the builder's self-report. **Phase 6b**
(smoke-runner) then drives the RUNNING app through the smoke checklist and brings
back real request/response evidence, so the human gate confirms observed behavior
instead of typing curl by hand — including the data-shape checks a human can't
eyeball (the NULL-masquerading-as-data catch).

---

## Instructions

### Phase 0 — Pre-flight

**0a. Validate the ticket.** Fetch the story from Jira (Cloud ID
`b6770d30-bf33-4b84-8fd7-607d704d0cd1`; fields: summary, description, status,
labels, parent epic, issuelinks).

- If status is not **Ready**, stop:
  ```
  ⛔ {KEY} is in '{status}' — expected Ready.
  Move the story to Ready in Jira before running /run-story.
  ```
- **Label caveat (do not over-gate).** A missing `api-story`/`ui-story` label is
  a warning, not a blocker — bugs and canonical-layer stories are legitimately
  labeled `ai-tools`, `ingestion`, `rm-sync`, `canonical-layer`, etc. Warn and
  continue. (See `.claude/scripts/JIRA_RECIPES.md` Recipe C.)

**0b. Git hygiene across the four code repos.** Cheapest place to catch the
project's most expensive recurring bug — starting from a stale `dev`:

```bash
cd /Users/miken/SoftwareProjects/Spyglass
for r in core-api core-webui RentManagerSyncSerivce ai-service; do
  git -C "$r" fetch origin --quiet
  cur=$(git -C "$r" branch --show-current)
  dev_behind=$(git -C "$r" rev-list --count dev..origin/dev 2>/dev/null)
  head_behind=$(git -C "$r" rev-list --count HEAD..origin/dev 2>/dev/null)
  echo "$r | on:$cur | local dev behind origin/dev:${dev_behind:-?} | HEAD behind origin/dev:${head_behind:-?}"
done
```

Report staleness; do not block on it — `generate-task --freeze` (Phase 4) runs
`branch-sync.sh`, which fast-forwards `dev` before cutting the branch and hard-
STOPs only on a genuinely diverged base. Surface `fetch`/count failures for the
user to decide.

---

### Phase 1 — generate-task --draft (sub-agent)

Spawn a sub-agent to write the DRAFT task doc — spec case names only, NO freeze,
NO commit, NO Jira transition.

```
Agent({
  description: "generate-task --draft for {KEY}",
  prompt: "Run /generate-task {KEY} --draft.
           Monorepo root: /Users/miken/SoftwareProjects/Spyglass/
           Follow the generate-task skill's --draft mode exactly: write the task
           doc with frontmatter spec_state: draft, author the acceptance spec
           case NAMES + AC bindings as a PROPOSED (not frozen) list, and STOP —
           do NOT write test files, do NOT branch, do NOT commit, do NOT
           transition Jira, do NOT spawn any implementation agent.
           Return: task filename, target repos, vertical slices (AFK/HITL),
           proposed spec case names, and any warnings (missing ACs, missing
           Figma, ambiguous repo)."
})
```

**If warnings include missing ACs:** stop and surface — a story with no ACs
cannot produce a spec. **Missing Figma (UI story):** surface and ask whether to
continue.

Report:
```
✅ Phase 1 — DRAFT task doc ready (spec NOT yet frozen)
📄 tasks/{task-filename}
📂 Repos: {repos}
🔀 Slices: {n} AFK, {n} HITL
🧊 Proposed spec cases: {n} (names only — freeze pending review)
⚠️  Warnings: {list or "none"}
```

---

### Phase 2 — scout (sub-agent)

Spawn `scout` to establish repo ground truth for this story. Read-only.

```
Agent({
  description: "scout for {KEY}",
  subagent_type: "scout",
  prompt: "Recon for {KEY}. Monorepo root: /Users/miken/SoftwareProjects/Spyglass/
           Read the draft task doc at tasks/{task-filename} first for context,
           then produce your Recon Report per your instructions. Establish ground
           truth on every named object the story references — endpoints, columns,
           entity/DTO fields, service methods, tool schemas — with real types and
           NULLABILITY, the cross-repo blast radius, and everything Uncertain.
           Read-only: do not edit or run anything."
})
```

Return the Recon Report verbatim to the next phase — do not summarize away its
citations.

---

### Phase 3 — verify-task (sub-agent)

Spawn `verify-task` with the draft doc AND scout's Recon Report. It works off
those two only and does not re-read the repo.

```
Agent({
  description: "verify-task for {KEY}",
  subagent_type: "verify-task",
  prompt: "Adversarially check {KEY} for decidability. Monorepo root:
           /Users/miken/SoftwareProjects/Spyglass/
           Read ONLY these two: the draft task doc at tasks/{task-filename}, and
           scout's Recon Report (below). Do NOT re-read the repo.
           Output contradictions (task assumption vs. repo reality, most
           dangerous first) and open questions (everything the implementer would
           still have to guess), per your instructions.

           --- SCOUT RECON REPORT ---
           {paste scout's full report}"
})
```

---

### Phase 3b — Merge recon into the draft doc (orchestrator)

Fold scout + verify-task output INTO the draft doc so the user reviews **one
reality-checked spec**, not three separate reports. Edit `tasks/{task-filename}`:

- Add a section **`## Reality check (scout + verify-task)`** containing:
  - **Confirmed shapes** — objects scout found to Exist, with file:line + real
    types/nullability. These become authoritative in the doc.
  - **Absent** — named objects that don't exist yet (genuinely new work).
  - **Blast radius** — call sites / cross-repo consumers the change affects.
  - **Contradictions** — each verify-task contradiction, and where possible
    inline a note next to the AC or slice it threatens.
  - **Open questions** — a checklist `- [ ]` the user must resolve before freeze.
- Where scout confirmed a concrete shape the draft had left vague (a column
  type, a nullable flag, an exact method name), tighten the draft's relevant
  section to match reality — that is the whole point of the front end.

Do NOT freeze anything here. Leave `spec_state: draft`.

---

### ⏸ PRE-FREEZE REVIEW GATE (you)

This is the gate the whole v2 front end exists to serve. Present it and then
**converse** — this is not a yes/no prompt.

```
⏸ Pre-freeze review — {KEY}

The draft task doc is reality-checked and ready for your review BEFORE the spec
freezes. Nothing has been committed.

📄 tasks/{task-filename}

Reality check summary:
  ✅ Confirmed: {n} shapes match repo   ⚠️ Contradictions: {n}   ❓ Open questions: {n}

Open questions to resolve:
  1. {open question}
  2. {open question}

{If any contradiction is dangerous (silent-data/scoping), call it out explicitly.}

You can:
  • edit tasks/{task-filename} directly (I'll re-read it),
  • ask me anything about the recon or a shape,
  • tell me to adjust a slice, AC, or spec case name,
  • answer the open questions.

When the spec is right, say "freeze it" and I'll freeze + commit the acceptance
suite, then start the build. Nothing freezes until you do.
```

- Loop here: answer questions, make edits the user asks for (or let them edit),
  re-read the doc after any change. Resolve every open question or explicitly
  mark it accepted-as-is.
- **Only an explicit "freeze it" (or equivalent) advances to Phase 4.** Do not
  infer approval from an ambiguous reply.

---

### Phase 4 — generate-task --freeze (sub-agent)

On approval, freeze and commit the (possibly edited) spec.

```
Agent({
  description: "generate-task --freeze for {KEY}",
  prompt: "Run /generate-task {KEY} --freeze on the doc at tasks/{task-filename}.
           Monorepo root: /Users/miken/SoftwareProjects/Spyglass/
           Follow the generate-task skill's --freeze mode exactly. The doc has
           been human-reviewed at the v2 pre-freeze gate — treat its (possibly
           edited) ACs and proposed case names as the source of truth. Write one
           placeholder test file per AC, bring up the epic branch via
           .claude/scripts/branch-sync.sh, commit the frozen suite per repo,
           transition Jira to In Progress, and flip frontmatter to
           spec_state: frozen. Do NOT spawn an implementation agent.
           Return: frozen case count per repo, commit hash(es), branch state,
           Jira transition result."
})
```

If freeze reports a diverged-base STOP or commit failure, surface it and do not
proceed — the builder must have a committed frozen spec to build against.

Report:
```
✅ Phase 4 — spec frozen & committed
🧊 {n} cases across {repos} · commit {hash}
🌿 {branch} ({created|exists}) · 📋 {KEY} → In Progress
```

---

### Phase 5 — tdd-start (sub-agent)

**API / Sync / AI stories** — spawn the builder:

```
Agent({
  description: "tdd-start for {KEY}",
  prompt: "Run /tdd-start tasks/{task-filename}.
           Monorepo root: /Users/miken/SoftwareProjects/Spyglass/
           Follow every step in the tdd-start skill exactly.
           Context discipline: read only the task file and CLAUDE.md on startup;
           pull source files on demand.
           At a HITL slice: stop, describe the decision, report back — do not
           guess past a HITL gate.
           When COMPLETION.md is written, report: pass/fail counts per repo, the
           smoke test checklist, and any deferred items."
})
```

**HITL pause handling:** if the builder returns a HITL decision, surface it:
```
⏸ HITL gate — slice {n}: {slice}
Decision needed: {what the agent cannot decide alone}
Options: A) {…}  B) {…}  (or describe another approach)
```
Wait for the answer, then re-prompt the builder to continue from that slice.

**UI stories** — skip the builder:
```
⏸ UI story — implement the component from tasks/{task-filename}, then run
/eval-ui tasks/{task-filename}. Reply "done" when implementation is complete.
```

Report (builder counts are NOT yet trusted — Phase 6 re-derives them):
```
✅ Phase 5 — implementation done
📋 Builder-reported: {n} passing ({repos}) — not yet verified
→ Proceeding to independent verification.
```

---

### Phase 6 — verify (sub-agent, independent)

Fresh sub-agent, must NOT read the builder's conversation — only committed state
+ frozen spec. Catches "passes the builder's own tests but is wrong/incomplete."

```
Agent({
  description: "verify for {KEY}",
  prompt: "Independently verify the implementation of {KEY}. Do NOT read the
           builder's conversation — work only from committed code and the frozen
           acceptance spec. Monorepo root: /Users/miken/SoftwareProjects/Spyglass/

           For EACH target repo in tasks/{task-filename}:
           1. CLEAN CHECKOUT — clean tree on the epic branch; verify what was
              actually committed.
           2. FROZEN SUITE GREEN — run acceptance/{KEY}/; report pass/fail per
              case by name.
           3. MANIFEST INTACT — acceptance/{KEY}/manifest.json: every case still
              present with the SAME name + AC binding. FAIL on any rename,
              deletion, re-bind, or manifest edit.
           4. NO PLACEHOLDER SURVIVED — grep frozen case files for 'not
              implemented' / placeholder fail(). Any remaining = FAIL, name it.
           5. NO TAUTOLOGIES — FAIL assertThat(true).isTrue(), assert True,
              expect(true).toBe(true), empty bodies, commented-out assertions,
              or @Disabled/@skip/xit/.skip.
           6. STUB SWEEP on the story diff — TODO/FIXME/NotImplementedError/
              pass-only bodies/hardcoded stub returns, with file:line (warning
              unless on an AC's code path).

           Return a per-repo table + a single VERDICT:
             PASS only if, for every repo: suite fully green, manifest intact,
             zero placeholders, zero tautologies. FAIL otherwise with specifics.
             Report stub-sweep findings either way."
})
```

**FAIL** → surface the specific reasons and re-spawn tdd-start (Phase 5) to fix
them, passing the failing case names in. Do NOT reach the smoke gate on a FAIL —
the smoke gate is a human backstop, never the primary correctness check.

**PASS** → report and continue:
```
✅ Phase 6 — independently verified
🧊 {n}/{n} green from clean checkout ({repos}) · manifest intact · 0 placeholders · 0 tautologies
{⚠️ stub-sweep notes, if any — non-blocking}
```

---

### Phase 6b — smoke-runner (sub-agent, pre-flight)

Only on a Phase 6 PASS. Spawn `smoke-runner` to drive the running app through
every mechanically-executable row of the story's smoke-test checklist and bring
back evidence. It observes behavior; it never approves the story — the human
gate stays.

```
Agent({
  description: "smoke-runner for {KEY}",
  subagent_type: "smoke-runner",
  prompt: "Smoke pre-flight for {KEY}. Monorepo root:
           /Users/miken/SoftwareProjects/Spyglass/
           Work list: the smoke-test checklist in the completion report
           (tasks/completion-{KEY}-*.md). Read tasks/{task-filename} for target
           repos and shapes. Follow your instructions exactly: bring services up
           if needed (docker-compose; --force-recreate after a migration story),
           execute every mechanically-executable row — MCP tools/call, REST
           endpoints, data-shape queries on postgres :5433, the mechanical part
           of UI rows — and return the Smoke Pre-flight Report with verbatim
           request/response evidence and a PASS/FAIL/PARTIAL/NEEDS-HUMAN verdict
           per row. Never edit source, commit, mutate data the checklist didn't
           ask for, or approve the story."
})
```

**Any FAIL row** means live behavior contradicts a green frozen suite — surface
the failing evidence loudly and re-spawn tdd-start (Phase 5) with it. Do NOT
present the smoke gate as confirm-only on a FAIL.

**COULD NOT START** (app won't come up) → surface the reason and fall back to
the manual gate below with the raw checklist; never let an un-driven row be
narrated as passing.

Report:
```
✅ Phase 6b — smoke pre-flight complete
📋 {n} PASS · {n} FAIL · {n} PARTIAL · {n} NEEDS-HUMAN
```

---

### ⏸ SMOKE TEST GATE (you)

Frozen suite verified in Phase 6 and the checklist pre-driven in Phase 6b, so
this gate is "confirm observed evidence + judge what automation can't see"
(visual correctness, UX, integration feel) — not "drive curl by hand." You
should only reach it with zero FAIL rows.

```
⏸ Smoke test required — {KEY}

Smoke pre-flight: {n} PASS · {n} FAIL · {n} PARTIAL · {n} NEEDS-HUMAN

{paste the smoke-runner Rows table + its "For the human at the smoke gate"
section verbatim — the evidence is what lets you confirm without re-running}

{If every executable row passed:} All mechanical rows verified with evidence —
you're confirming, not re-driving. Still yours to judge:
  {the NEEDS-HUMAN / visual items, each with the exact thing to look at}

Reply "approved" when the remaining items pass, or describe any failures.
```

Wait for explicit **"approved"**. On a reported failure: get details, then
decide to re-spawn tdd-start or fix inline. Do not call close-story until
approved.

---

### Phase 7 — close-story (sub-agent)

```
Agent({
  description: "close-story for {KEY}",
  prompt: "Run /close-story {KEY}.
           Monorepo root: /Users/miken/SoftwareProjects/Spyglass/
           The smoke test has already been approved — skip the smoke test
           confirmation prompt and proceed directly to Step 2. Follow every step
           exactly. Spawn review and security-review sub-agents as the skill
           instructs (not inline). Use .claude/scripts/commit-archive.sh for the
           commit/push/archive mechanics where it applies.
           Report: commit hash(es), Jira status, PR URL (if last story in epic),
           next Ready story in the queue (if any)."
})
```

---

### Final report

```
✅ {KEY} complete
📋 Jira: {KEY} → Done
🔀 Commit: {hash} ({repo})
📁 Task files archived
{🚀 PR: {url}  ← only if last story in epic}

{next story:}  Next in queue: {NEXT_KEY} — {title}
   /run-story {NEXT_KEY} to continue, or /run-epic {EPIC_KEY} for the rest.
{empty queue:}  ⏸ Queue empty — no Ready stories remaining.
```

Then send the completion notification: `/notify complete {KEY}`.

<!--
================================================================================
  run-story v1 — PRESERVED FOR REFERENCE (not executed)
================================================================================
  v1 froze the acceptance spec inside a single generate-task run with only a
  quick human "skim" (no reconnaissance, no pre-freeze editing gate, no
  scout/verify-task). v2 above replaces it with a draft → recon → review →
  freeze front end. To roll back to v1, move the comment boundary: comment out
  the v2 body above and un-comment this block.

  ORIGINAL v1 PHASES:
    Phase 1: generate-task   (sub-agent, AFK — froze spec inline)
    Phase 2: tdd-start       (sub-agent, AFK — pauses at HITL slices)
    Phase 3: verify          (sub-agent, AFK — independent re-check, no human)
    Phase 4: smoke test gate (YOU — manual verification in the running app)
    Phase 5: close-story     (sub-agent, AFK)

  v1 Step 1   — Validate the ticket (Ready check; api-story/ui-story label warn).
  v1 Step 1.5 — Pre-flight git hygiene across the four code repos (fetch, report
                dev-behind-origin; generate-task did the actual ff sync).
  v1 Step 2   — Phase 1: spawn /generate-task {KEY} (all-in-one; froze the spec
                and transitioned Jira to In Progress in the same run). Returned
                task filename, repos, slices, warnings.
  v1 Step 3   — Phase 2: spawn /tdd-start {task-filename}. HITL pause handling.
                UI stories implemented manually then /eval-ui.
  v1 Step 3.5 — Phase 3: spawn independent verify (clean checkout, frozen suite
                green, manifest intact, no placeholder, no tautology, stub sweep;
                PASS/FAIL verdict; FAIL re-spawns tdd-start).
  v1 Step 4   — Phase 4: smoke test gate (human, running app; wait "approved").
  v1 Step 5   — Phase 5: spawn /close-story {KEY} (review + security-review
                sub-agents, commit, Jira Done, archive, PR if last story).
  v1 Step 6   — Final report + /notify complete {KEY}.

  The full v1 step text is recoverable from git history of this file (the commit
  prior to the v2 rewrite). The phase map above is the faithful summary; v2
  reuses v1's Phase 3 (verify), Phase 4 (smoke), and Phase 5 (close-story) bodies
  almost verbatim as its Phases 6, smoke gate, and 7.
================================================================================
-->
