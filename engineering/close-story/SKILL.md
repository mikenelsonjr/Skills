---
name: close-story
description: >
  Close out a completed story after smoke test approval. Commits all changes
  with a conventional commit message, transitions the Jira ticket to Done,
  archives the task and completion files, and reports the next Ready story
  in the queue.
  Usage: /close-story EL-101
---

# close-story

Runs after you have smoke tested the story and are satisfied with the result.
This is the only point where implementation code gets committed. Do not run
this skill without explicit smoke test approval from the user.

## Invocation

```
/close-story EL-101
```

---

## Instructions

### Step 1 — Verify smoke test approval and code review

**If invoked by the run-story orchestrator** (the prompt will say "smoke test has already been
approved by the user — skip the smoke test confirmation prompt"), skip the confirmation
question and proceed directly to Step 2.

**If invoked directly by the user**, confirm before doing anything:

"You are about to commit and close {KEY}. Before proceeding, confirm:
  1. Smoke test: have you checked all items in the completion report's smoke test checklist?
  2. Code review: have you run /review or /security-review (required for auth/data/API stories)?

Ready to commit? (yes/no)"

Wait for explicit confirmation. Do not proceed on ambiguous responses.
If the user says no or raises concerns, stop and let them direct next steps.

**If the user has not run a code review**, offer to run it:
"Would you like me to run /review now before committing? (yes/no)"

If yes, spawn a review sub-agent with a fresh context window:

```
Agent({
  description: "Code review for {KEY}",
  prompt: "Run /review against the current branch in the repo at {repo-path}.
           Compare against the base branch (dev). Report any blocking issues —
           violations of conventions in CLAUDE.md, spec mismatches, security
           concerns. List findings as BLOCKING or ADVISORY. Do not fix anything —
           report only."
})
```

Wait for the sub-agent result. If blocking issues are found, surface them to
the user and stop — do not commit until the user has resolved or explicitly
accepted each one.

**Security review trigger:** If the task file's story description or changed
files include any of the following, spawn a security-review sub-agent instead
of (or in addition to) the standard review:
- Authentication or authorization logic
- Data access or RLS policies
- API endpoints that accept user input
- Token handling, session management, or credential storage

```
Agent({
  description: "Security review for {KEY}",
  prompt: "Run /security-review against the current branch in {repo-path}.
           Focus on: auth/authz, RLS, injection vectors, secrets exposure,
           input validation. Report findings with severity (CRITICAL/HIGH/MEDIUM/LOW).
           Do not fix anything — report only."
})
```

Treat security findings the same as code review blockers.

---

### Step 2 — Locate the task and completion files

Find the relevant files for this ticket in the central tasks directory at the
monorepo root:

- Task file: `tasks/task-{KEY}-*.md`
- Completion file: `tasks/completion-{KEY}-*.md`

The repo where code changes live is determined by reading the task file's
`repos:` frontmatter field — do not guess from story type.

If the task file is not found, stop and report the error. The task file must
exist before this skill can proceed.

Read the completion file and verify `status: PASS`. If status is `FAIL` or
`NEEDS_REVIEW`, warn the user:

"The completion report for {KEY} is marked {status}. Are you sure you want
to commit this? (yes/no)"

Wait for confirmation before continuing.

---

### Step 3 — Review staged changes

Run `git status` and `git diff --stat` inside the repo directory.

**If the working tree is clean (nothing to commit):** this is expected when tdd-start
already committed the implementation (the normal run-story flow). In this case:
- Run `git log --oneline -5` to confirm the story's commits are present on the branch
- Show the user the relevant commits
- Proceed to Step 4 — there is nothing to stage or commit, skip Steps 4–6 and go directly to Step 7

**If there are uncommitted changes:** show the user a summary of what will be committed:
- List of changed files
- Number of insertions and deletions
Continue to Step 4.

---

### Step 4 — Stage all changes

```
git add -A
```

Exclude the task and completion files from the commit — they are internal
workflow files, not production code. Stage everything except:

```
git reset HEAD tasks/
```

Confirm the staged file list looks correct before committing.

---

### Step 5 — Build the commit message

Use the S8 conventional commit format.

**Determine commit type:**

| Story content | Type |
|---|---|
| New feature / endpoint / component | `feat` |
| Bug fix | `fix` |
| Refactor with no behaviour change | `refactor` |
| Tests only | `test` |
| Config, tooling, dependencies | `chore` |

**Derive the slug** from the story summary in the task file:
- Lowercase, hyphenated, max 50 chars
- Drop articles and filler words

**Build the change summary** (2–4 sentences) from the completion file's
**Files changed** and **Notes** sections. Describe what was built, not
how. Focus on observable behaviour.

**Final commit message format:**

```
{type}({KEY}): {story summary in sentence case, max 60 chars}

{2-4 sentence change summary. What was built. What it does.
Any important edge cases handled.}

Resolves: https://elevareiq.atlassian.net/browse/{KEY}
```

Show the full commit message to the user and ask:
"Does this commit message look correct? (yes / edit)"

If the user says edit, take their corrections before committing.

---

### Step 6 — Commit

```
git commit -m "{message}"
```

Confirm the commit hash and that the commit was created successfully.

---

### Step 7 — Transition Jira to Done

Use the Atlassian MCP to transition the ticket to **Done**.

- Cloud ID: `b6770d30-bf33-4b84-8fd7-607d704d0cd1`
- Call `getTransitionsForJiraIssue` for the ticket key to get available transitions
- Find the transition ID for "Done"
- Apply the transition with `transitionJiraIssue`

If the transition fails: warn the user but do not block — the commit is
already made. The user can update Jira manually.

---

### Step 8 — Archive the task and completion files

The task files live at the monorepo root (`tasks/`), which is not a git repo.
Move the files using plain filesystem commands, then commit the move from
within the story's code repo (the first repo listed in the task file's
`repos:` frontmatter):

```
mv /Users/miken/SoftwareProjects/Spyglass/tasks/task-{KEY}-{slug}.md \
   /Users/miken/SoftwareProjects/Spyglass/tasks/archive/task-{KEY}-{slug}.md

mv /Users/miken/SoftwareProjects/Spyglass/tasks/completion-{KEY}-{slug}.md \
   /Users/miken/SoftwareProjects/Spyglass/tasks/archive/completion-{KEY}-{slug}.md
```

The archive move does not need to be committed — these are workflow files,
not production code. The files are simply moved out of the active tasks
directory to keep it clean.

This keeps the `tasks/` directory clean while preserving the full audit
trail in `tasks/archive/`.

---

### Step 9 — Check whether this was the last story in the epic

Query Jira for any remaining open stories in the same epic:

```
project = EL
AND "Epic Link" = {EPIC_KEY}
AND status != Done
AND issueKey != {KEY}
```

(Substitute the epic key from the task file's `epic:` frontmatter field.)

**If open stories remain:** skip the PR step — more commits are coming on
this branch. Proceed directly to Step 10.

**If no open stories remain (this was the last story):** the epic is complete.
Proceed to open a PR for each repo that has commits on the feature branch.

For each repo listed in the task file's `repos:` frontmatter:

1. Push the feature branch to origin:
   ```
   git -C {repo-path} push -u origin feature/{epic-key-slug}
   ```

2. Build a PR title and body. The title is:
   `feat({EPIC_KEY}): {epic summary in sentence case, max 60 chars}`

   The body should summarise what the epic delivered — draw from the
   completed task files in `tasks/archive/` that share the same epic key.
   List the stories (KEY + one-line summary each) under a "Stories" section.

3. Open the PR using the GitHub CLI:
   ```
   gh pr create \
     --repo {github-org}/{repo-name} \
     --base dev \
     --head feature/{epic-key-slug} \
     --title "{title}" \
     --body "$(cat <<'EOF'
   ## Summary
   {2-3 bullet points summarising what the epic built}

   ## Stories
   - {KEY1}: {story title}
   - {KEY2}: {story title}

   ## Test plan
   - [ ] All story smoke tests passed
   - [ ] Full test suite green on feature branch
   - [ ] No regressions in adjacent features
   EOF
   )"
   ```

4. Report the PR URL to the user.

If `gh` CLI is not available or the push fails, warn the user with the
push command they should run manually, and stop.

---

### Step 10 — Report the next story in the queue

Query Jira for the next Ready story using JQL:

```
project = EL
AND status = Ready
AND labels in (api-story, ui-story)
ORDER BY priority ASC, created ASC
```

Cloud ID: `b6770d30-bf33-4b84-8fd7-607d704d0cd1`

Report the result:

**If a next story is found (epic still in progress):**
```
✅ {KEY} committed and closed.
📋 Jira: {KEY} → Done
📁 Task files archived
🌿 Branch: feature/{epic-key-slug} — {n} stories remain in epic

Next story in queue:
  {NEXT_KEY}: {story title}
  Type: {api-story | ui-story}
  Epic: {epic name}

Run /generate-task {NEXT_KEY} to start.
```

**If this was the last story in the epic (PR opened):**
```
✅ {KEY} committed and closed — epic {EPIC_KEY} complete!
📋 Jira: {KEY} → Done
📁 Task files archived
🚀 PR opened: {PR_URL}

Epic {EPIC_KEY} is done. Waiting for PR review.
```

**If the queue is empty (no epic context):**
```
✅ {KEY} committed and closed.
📋 Jira: {KEY} → Done
📁 Task files archived

⏸ Queue is empty — no Ready stories remaining.
Waiting for new work. Add stories to Ready in Jira to continue.
```

The queue-empty state also triggers the S7 notification email if Gmail
MCP is connected. Check for it and send if available — use the S7 template
with status "Queue empty".
