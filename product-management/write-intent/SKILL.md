---
name: write-intent
description: >
  Interactively draft a product intent brief for a new Epic. Asks targeted
  questions about the feature idea, then writes a structured intent brief to
  pm-docs/agents/runs/intents/. The intent brief is the input for /epic-smith.
  Usage: /write-intent "brief description of the idea"
---

# write-intent

Guides you through drafting a product intent brief for a new Epic. Asks only
what's needed, flags open questions rather than guessing, and produces a
structured markdown file ready to feed into /epic-smith.

## Invocation

```
/write-intent "description of the idea"
```

The quoted description is optional but helps orient the first question.

---

## Instructions

### Step 1 — Assess available context

Before asking any questions, review the current conversation for content that
already answers any of the seven intent fields (users, pain, outcomes, metrics,
scope-in, scope-out, dependencies, open questions).

**If the conversation contains rich context** (the user has described the
feature in detail, explained the pain, outlined scope, etc.) — do NOT ask
questions that are already answered. Pre-fill those fields from what was said.
Only ask about fields that are genuinely missing or ambiguous.

**If the conversation is sparse** (just a brief description or nothing beyond
the invocation arg) — work through the questions below one at a time.

The goal is to ask the minimum number of questions needed. If all fields are
clearly covered by the conversation, skip directly to Step 2.

---

The seven fields to fill (ask only what's missing):

**Q1 — Who is this for?**
"Which user roles does this primarily serve? (e.g. PM Admin, Property Owner,
PM Staff, Analyst — or a mix)"

**Q2 — What's the pain?**
"What's the current pain or friction? Walk me through what the user has to do
today and why it's a problem."

**Q3 — What does success look like?**
"If we ship this and it works perfectly, what changes for the user? What
would you measure to know it worked? (quantitative targets preferred)"

**Q4 — What's in scope?**
"What are the 3–5 things this Epic must deliver? Bullet points are fine."

**Q5 — What's explicitly out of scope?**
"What are we deliberately NOT doing in this Epic to keep it focused?"

**Q6 — What are the known dependencies or constraints?**
"Any systems, teams, or technical constraints we need to work around?
(e.g. 'requires RentManager sync to have lease data', 'must work with
existing Firebase auth', 'blocked on EL-XXX')"

**Q7 — Open questions**
"What's still unclear or unresolved? I'll flag these in the brief so
/epic-smith knows to highlight them."

Ask questions **one at a time** — wait for each answer before asking the next.

---

### Step 2 — Confirm and fill gaps

After collecting any missing answers (or immediately if context was complete),
summarise back what you've captured in 3–4 sentences:
"Here's what I've captured: {summary}. Does that sound right, or anything
to add/change?"

Wait for confirmation or corrections. Incorporate any changes.

If any critical sections are thin (e.g. no measurable outcome, no scope
definition), probe once:
"Before I write this up — the outcome metrics are vague. Even a rough
target helps /epic-smith set a meaningful KPI. Do you have a number in mind,
or should I flag it as an open question?"

---

### Step 3 — Derive the slug and filename

Derive a short slug from the feature description:
- Lowercase, hyphenated, max 40 chars
- Drop articles and filler words
- Examples: "renewal offer automation" → `renewal-offer-automation`

Filename: `intent-{slug}.md`
Save to: `pm-docs/agents/runs/intents/intent-{slug}.md`

---

### Step 4 — Write the intent brief

Write the file using this exact structure:

```markdown
# Intent: {feature title}

_Created: {YYYY-MM-DD}_

## Target users
{bullet list of roles this serves}

## Current pain points
{2–4 sentences or bullets describing the current state and why it's painful}

## Desired outcomes
{what changes for the user when this ships}

## Outcome metrics / KPIs
- {Metric}: {baseline} → {target}
- {Metric}: {baseline} → {target}
{If unknown, write: "⚠️ OPEN QUESTION: target not yet defined"}

## Scope
**In:**
- {bullet}
- {bullet}

**Out:**
- {bullet}
- {bullet}

## Known dependencies and constraints
- {dependency or constraint}
{Write "None identified" if empty}

## Open questions
{List each unresolved question prefixed with "OPEN QUESTION:"}
{Write "None" if all clear}
```

---

### Step 5 — Report completion

Output:

```
✅ Intent brief written: pm-docs/agents/runs/intents/intent-{slug}.md

Next step: run /epic-smith intent-{slug}.md to generate the Jira Epic.
```
