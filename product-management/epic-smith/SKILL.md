---
name: epic-smith
description: >
  Generate a structured Jira Epic from a product intent brief. Reads the intent
  file, produces a delivery-ready Epic with KPIs, scope, ACs, risks, and
  milestones, creates the Epic in Jira, and links it to Confluence.
  Usage: /epic-smith intent-{slug}.md
---

# epic-smith

Transforms a product intent brief into a delivery-ready Epic and creates it
in Jira. Flags missing requirements rather than guessing. Uses the Atlassian
MCP for all Jira and Confluence operations.

## Invocation

```
/epic-smith intent-{slug}.md
```

Pass the intent filename from `pm-docs/agents/runs/intents/`. Run
/write-intent first if you don't have an intent brief yet.

---

## Instructions

### Step 1 — Read the intent brief

Read `pm-docs/agents/runs/intents/{filename}`.

Extract:
- Feature title
- Target users
- Pain points
- Desired outcomes and KPIs
- Scope (in / out)
- Dependencies and constraints
- Open questions

If any of the following are missing or marked `⚠️ OPEN QUESTION`, flag them
clearly in the output and note they will be left as placeholders in the Epic:
- Outcome metrics / KPIs (without these the Epic has no measurable success)
- In-scope items (without these the Epic has no deliverable)
- Target users

Do not stop — produce the best Epic possible with what's available, but call
out every gap explicitly.

---

### Step 2 — Load Spyglass context

Read the following context files to inform the Epic's technical framing:

- `pm-docs/agents/contexts/product-vision.md` — strategic alignment
- `pm-docs/agents/contexts/architecture-overview.md` — technical constraints
- `pm-docs/agents/contexts/glossary.md` — correct terminology

**Terminology rules (override glossary if it conflicts):**
- "Customer" = the PMC (property management company) — not "tenant"
- "Resident" = occupant of a rental unit — not "tenant"
- "Property Owner" = landlord entity (LLC/Trust)
- "PM Admin / PM Staff / Analyst / Viewer" = PM-side roles
- "Owner" = property owner portal role
- All references to "Aptly" mean the external Aptly board integration

---

### Step 3 — Draft the Epic

Write the Epic following this exact structure. Fill every section.
Use `⚠️ TBD` only where information is genuinely unavailable after
checking the intent brief and context files.

```markdown
# Epic: {title}

**Problem**
{2–3 sentences: who is affected, what the current pain is, and why it matters now}

**Outcome / KPIs**
| KPI | Baseline | Target |
|-----|----------|--------|
| {metric} | {current state or "unknown"} | {target} |

**Scope**
In:
- {bullet}

Out:
- {bullet}

**Actors & Permissions**
| Actor | Role code | What they can do |
|-------|-----------|-----------------|
| {actor} | {PM_ADMIN / PM_STAFF / OWNER / etc.} | {capability} |

**Dependencies**
- Systems: {list or "None"}
- Teams: {list or "None"}
- Blocking stories: {EL-XXX or "None"}
- Technical constraints: {list or "None"}

**Acceptance criteria (system-level)**
- [ ] {testable criterion — observable, unambiguous}
- [ ] {testable criterion}

**Milestones**
1. Design sign-off / story refinement complete
2. MVP behind feature flag — internal testing
3. Pilot (selected customers) → GA

**Risks / Mitigations**
| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| {risk} | High/Med/Low | {plan} |

**Non-functional requirements**
- Performance: {e.g. p95 < 500ms or N/A}
- Security: {e.g. must respect customer_id scoping}
- Accessibility: {e.g. WCAG 2.1 AA or N/A}

**Open questions**
{Copy all OPEN QUESTION items from the intent brief. Add any new ones
surfaced during drafting. Write "None" if all resolved.}

**Links**
Confluence: {to be linked after creation} · Jira: {to be linked after creation}
```

---

### Step 4 — Show draft and confirm

Show the full Epic draft to the user and ask:
"Does this Epic look right? Any sections to change before I create it in Jira?
(yes to proceed / describe changes)"

Wait for explicit confirmation. Incorporate any changes before proceeding.

---

### Step 5 — Create the Epic in Jira

Use the Atlassian MCP to create the Epic.

- Tracker ID: `{tracker_id}` (default `b6770d30-bf33-4b84-8fd7-607d704d0cd1`)
- Project key: `EL`
- Issue type: `Epic`
- Summary: `{title}`
- Description: the full Epic markdown from Step 3
- Labels: `epic`

Call `getJiraProjectIssueTypesMetadata` first to get the correct Epic issue
type ID if needed.

Save the returned Jira key (e.g. `EL-215`) — you'll need it in Step 6.

If creation fails: show the error and ask the user whether to retry or
save the Epic draft to file for manual import.

---

### Step 6 — Save the Epic output file

Write the final Epic markdown to:
`pm-docs/agents/runs/epics/epic-{slug}.md`

Add the tracker key to the **Links** section (`{jira_base_url}` default
`https://elevareiq.atlassian.net/browse/`):
`Jira: {jira_base_url}{KEY}`

---

### Step 7 — Report completion

Output:

```
✅ Epic created: {KEY} — {title}
🔗 Jira: {jira_base_url}{KEY}
📄 Output file: pm-docs/agents/runs/epics/epic-{slug}.md

⚠️ Open questions that need resolution before story refinement:
{list any ⚠️ TBD or OPEN QUESTION items}

Next steps:
  1. Resolve open questions above
  2. Run /refine-epic {KEY} to generate and refine the child stories
     (or create stories manually in Jira then run /refine-epic)
```
