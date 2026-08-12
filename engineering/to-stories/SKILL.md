---
name: to-stories
description: Break a plan, spec, or PRD into independently-grabbable issues on the project issue tracker using tracer-bullet vertical slices. Use when user wants to convert a plan into issues, create implementation tickets, or break down work into issues.
---

# To Issues

Break a plan into independently-grabbable issues using vertical slices (tracer bullets).

## Invocation

```
/to-stories                        # work from conversation context
/to-stories EL-50                  # fetch Jira epic by key
/to-stories https://elevareiq.atlassian.net/browse/EL-50   # fetch Jira epic by URL
```

## Process

### 1. Gather context

Work from whatever is already in the conversation context. If the user passes a Jira epic key (e.g. `EL-50`) or a Jira URL as an argument, fetch the epic from Jira and use it as the primary source.

**Fetching a Jira epic:**

- Jira base URL: `https://elevareiq.atlassian.net/browse/`
- Cloud ID: `b6770d30-bf33-4b84-8fd7-607d704d0cd1`
- Use `getJiraIssue` with the epic key to retrieve: `summary`, `description`, `status`, `labels`, and any child issues or issue links
- Also call `searchJiraIssuesUsingJql` with JQL `"Epic Link" = {KEY} OR parent = {KEY}` to retrieve existing child stories — list them so you do not create duplicates
- Read the full description, acceptance criteria, and any linked Confluence pages to understand scope

If no argument is given, work from whatever plan or spec is in the conversation context.

### 2. Explore the codebase (optional)

If you have not already explored the codebase, do so to understand the current state of the code. Issue titles and descriptions should use the project's domain glossary vocabulary, and respect ADRs in the area you're touching.

### 3. Draft vertical slices

Break the plan into **tracer bullet** issues. Each issue is a thin vertical slice that cuts through ALL integration layers end-to-end, NOT a horizontal slice of one layer.

Slices may be 'HITL' or 'AFK'. HITL slices require human interaction, such as an architectural decision or a design review. AFK slices can be implemented and merged without human interaction. Prefer AFK over HITL where possible.

<vertical-slice-rules>
- Each slice delivers a narrow but COMPLETE path through every layer (schema, API, UI, tests)
- A completed slice is demoable or verifiable on its own
- Prefer many thin slices over few thick ones
</vertical-slice-rules>

### 4. Quiz the user

Present the proposed breakdown as a numbered list. For each slice, show:

- **Title**: short descriptive name
- **Type**: HITL / AFK
- **Blocked by**: which other slices (if any) must complete first
- **User stories covered**: which user stories this addresses (if the source material has them)

Ask the user:

- Does the granularity feel right? (too coarse / too fine)
- Are the dependency relationships correct?
- Should any slices be merged or split further?
- Are the correct slices marked as HITL and AFK?

Iterate until the user approves the breakdown.

### 5. Publish the issues to the issue tracker

For each approved slice, publish a new Jira story. Use `createJiraIssue` with:

- `issuetype`: `Story`
- `project`: `EL`
- `summary`: the slice title
- `description`: the body from the template below (Atlassian Document Format or plain markdown — use the format the MCP accepts)
- `parent` / `Epic Link`: set to the source epic key if one was provided (e.g. `EL-50`)
- `labels`: `["api-story"]`, `["ui-story"]`, or omit if multi-repo — match the target repo for the slice
- Cloud ID: `b6770d30-bf33-4b84-8fd7-607d704d0cd1`

Publish issues in dependency order (blockers first) so you can reference real issue keys in the "Blocked by" field of later issues.

After creating each issue, immediately add an issue link (`createIssueLink`, type `"is blocked by"`) for any declared blocker.

<issue-template>
## What to build

A concise description of this vertical slice. Describe the end-to-end behavior, not layer-by-layer implementation.

Avoid specific file paths or code snippets — they go stale fast. Exception: if a prototype produced a snippet that encodes a decision more precisely than prose can (state machine, reducer, schema, type shape), inline it here and note briefly that it came from a prototype. Trim to the decision-rich parts — not a working demo, just the important bits.

## Acceptance criteria

- [ ] Criterion 1
- [ ] Criterion 2
- [ ] Criterion 3

## Blocked by

- {KEY} — {title} (if applicable)

Or "None — can start immediately" if no blockers.

## Slice type

AFK / HITL — {reason if HITL}

</issue-template>

Do NOT close or modify the parent epic.