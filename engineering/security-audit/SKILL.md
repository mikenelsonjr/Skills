---
name: security-audit
description: >
  Full-codebase security and architecture review. Spawns parallel agents
  per threat category across all four repos, then produces a prioritized
  findings report with Jira-ready severity ratings.
  Usage: /security-audit [repo] [--category <name>]
---

# security-audit

Runs a structured security and architecture review across the entire
Spyglass codebase (or a single repo). Agents work in parallel, each
focused on one threat category. Results are merged into a single
prioritized findings report you can act on immediately.

Repeatable — run it now before the refactor, and again after to verify
the surface area shrank.

## Invocation

```
/security-audit                          # all repos, all categories
/security-audit core-api                 # single repo
/security-audit --category auth          # one category, all repos
/security-audit core-api --category rls  # one category, one repo
```

Valid repo names: the `path` of each repo in `{repos}` (PROJECT_HARNESS). Spyglass
default: `core-api`, `core-webui`, `ai-service`, `RentManagerSyncSerivce`.

Valid category names: `auth`, `rls`, `injection`, `secrets`, `input`,
`dependencies`, `data-exposure`, `architecture`

## Bindings

Resolve `{workspace_root}` (default `/Users/miken/SoftwareProjects/Spyglass`) and
`{repos}` (default the four repos above) from the `## PROJECT_HARNESS` block in the
project's `CLAUDE.md`. See HARNESS.md.

---

## Instructions

### Step 1 — Determine scope

Parse the arguments to determine which repos and categories to include.

**Default (no args): all repos × all categories.**

Repo root paths — `{workspace_root}/{repo.path}` for each repo in `{repos}`.
Spyglass defaults:
- `core-api` → `/Users/miken/SoftwareProjects/Spyglass/core-api`
- `core-webui` → `/Users/miken/SoftwareProjects/Spyglass/core-webui`
- `ai-service` → `/Users/miken/SoftwareProjects/Spyglass/ai-service`
- `RentManagerSyncSerivce` → `/Users/miken/SoftwareProjects/Spyglass/RentManagerSyncSerivce`

Announce scope to the user before launching agents:

```
Security audit starting.
Repos: {list}
Categories: {list}
Launching {n} agents in parallel — this will take a few minutes.
```

---

### Step 2 — Launch category agents in parallel

Spawn one agent per category (scoped to the selected repos). All agents
run in parallel. Each agent returns a list of findings — do not wait for
one before starting another.

Pass every agent the following shared context:
- The repo paths and their stacks (see CLAUDE.md per repo)
- The category they are auditing (detailed below)
- Output format: a markdown list of findings, each with: severity
  (CRITICAL / HIGH / MEDIUM / LOW), repo, file path + line range,
  description of the issue, and a recommended fix

Tell each agent: **only report issues you can quote from the code with a
file path and line reference. Do not flag hypothetical or theoretical
issues. If you find nothing, say so explicitly.**

---

#### Category: `auth`

**Auth and authorization review.**

Checks across `core-api` (primary), `core-webui`, `ai-service`:

1. **FirebaseAuthenticationFilter coverage** — are there any controller
   endpoints in `core-api` that are not protected by the filter? Look for
   `permitAll()` rules in `SecurityConfig` and verify each whitelisted
   path is intentional (health check, public callback, etc.).

2. **403 vs 401 discipline** — the convention is 403 for access denial,
   never 401. Find any `HttpStatus.UNAUTHORIZED` or status code `401`
   returned by business logic (not the framework itself).

3. **`@PreAuthorize` / role checks** — scan controllers for endpoints
   that handle sensitive operations (write, delete, admin actions) without
   any role guard. Flag endpoints that should be role-restricted but aren't.

4. **`CurrentUser` propagation** — find any service or repository method
   that accepts a `customerId` or `customerUuid` parameter passed from
   outside (i.e. from the request) without the caller having verified it
   matches the authenticated user. Look for places where a caller-supplied
   ID could differ from `CurrentUser.customerId`.

5. **Angular route guards** — in `core-webui`, verify every route under
   `/pm` and `/owner` has `personaGuard` applied. Find any route that
   could be reached by the wrong persona.

6. **ai-service auth** — the service is internal-only (called from
   `core-api`, not from the frontend). Check that no route in `ai-service`
   is publicly reachable without the internal caller check. Look for any
   missing auth on FastAPI routes.

---

#### Category: `rls`

**Row-level security and multi-tenant isolation review.**

Primary focus: `core-api` and `RentManagerSyncSerivce`.

1. **Customer UUID scoping** — for every Spring Data JPA repository
   method and every `@Query` in `core-api`, verify the query filters by
   `customer_uuid` or `customer_id` (uuid type). Flag any query that
   returns data without a customer scope filter — these are cross-tenant
   data leaks.

2. **AI tool customer scope** — in `core-api/ai/tools/definitions/`,
   every tool's `execute()` method receives a `customerUuid` parameter.
   Verify every SQL string passed to the database in these tools includes
   the customer scope. Flag any tool that queries without it.

3. **`customerId` vs `customerUuid` confusion** — the bigint `customer_id`
   is for legacy joins only; auth scoping must use the UUID column. Find
   any query that scopes by `customerId` (bigint) on a `core_*` table
   where `customer_uuid` should be used instead.

4. **RentManagerSyncSerivce upserts** — every upsert in every entity
   sync module must include `customer_id`. Scan all `execute()` calls to
   PostgreSQL and flag any where `customer_id` is absent from the params.

5. **PostgreSQL RLS policies** — if migration files exist in
   `core-api/src/main/resources/db/migration/`, scan for `CREATE POLICY`
   statements. Report: which tables have RLS enabled, which don't, and
   whether the policy definitions look correct for the multi-tenant model.

---

#### Category: `injection`

**SQL injection and command injection review.**

1. **Raw SQL in `core-api`** — find any `@Query` annotation or
   `EntityManager.createNativeQuery()` call that uses string concatenation
   or `String.format()` to build SQL. All parameters must use `:param`
   named bind parameters or `?` positional params — never string-built
   queries.

2. **JPQL injection** — same check for JPQL queries. String-concatenated
   JPQL is injectable. Flag any `createQuery()` call that builds the query
   string dynamically.

3. **Python SQL in `RentManagerSyncSerivce` and `ai-service`** — scan
   all `cursor.execute()` calls. The second argument must be a params
   tuple/list, never an f-string or `%`-formatted query string.

4. **AI-generated SQL** — in `core-api`, the NL-to-SQL pipeline generates
   SQL strings from user input via Claude. Find where this generated SQL
   is executed and verify it goes through a validation/sanitization layer
   before hitting the database. Flag if the generated SQL is executed
   directly without inspection.

5. **Shell command invocation** — scan Python files for use of subprocess
   or shell execution functions. Verify no user-supplied data flows into
   these calls unescaped. Use Read and Grep tools to find these patterns
   rather than running shell commands.

---

#### Category: `secrets`

**Secrets and credential exposure review.**

Use Read and Grep tools to scan — do not execute shell scripts.

1. **Hardcoded credentials** — scan all four repos for hardcoded API
   keys, passwords, tokens, or connection strings. Grep for patterns:
   `password =`, `secret =`, `api_key =`, `token =`, `Bearer `,
   `AIza`, `sk-`. Exclude test files (they may use fake
   values — note them but don't flag as critical).

2. **`.env` and config file hygiene** — read `.gitignore` in each repo.
   Verify `.env`, `application-local.properties`, `application-secret.*`,
   `serviceAccountKey.json` are listed. Flag any secrets file not covered.

3. **Logged secrets** — scan for log statements (`log.info`, `log.debug`,
   `print`, `logger.info`) that include auth tokens, passwords, or full
   request bodies containing credentials.

4. **Firebase service account** — verify the Firebase config in
   `core-api/config/FirebaseConfig` loads credentials from an env var or
   mounted secret, not from a file committed to the repo.

5. **Vertex AI credentials** — in `ai-service`, verify
   `VERTEX_AI_PROJECT` and `VERTEX_AI_LOCATION` come from env vars and
   that no service account JSON is hardcoded or committed.

---

#### Category: `input`

**Input validation and output encoding review.**

1. **`@Valid` on all controller request bodies** — in `core-api`, scan
   every `@PostMapping`, `@PutMapping`, `@PatchMapping` method signature.
   Every `@RequestBody` parameter must have `@Valid`. Flag any that don't.

2. **DTO field constraints** — for DTOs that use `@Valid`, check that
   string fields have `@Size` or `@NotBlank` where appropriate. Flag DTOs
   that accept unbounded string input for fields that feed into SQL or
   AI prompts.

3. **User-supplied content in AI prompts** — in `core-api`, find where
   user-supplied text (chat messages, query strings) is interpolated into
   the system prompt or tool definitions sent to Claude. Is there any
   prompt injection guard? Flag if user content flows directly into the
   system prompt without sanitization.

4. **Angular form validation** — in `core-webui`, scan reactive form
   definitions for validators. Flag forms that submit to the API without
   any client-side validation (not a security boundary, but defense in
   depth).

5. **File upload handling** — if any endpoint accepts file uploads, verify
   MIME type checking and file size limits are enforced.

---

#### Category: `dependencies`

**Dependency vulnerability review.**

Use Read and Grep tools to inspect dependency manifests — do not run
audit commands.

**core-api:** Read `build.gradle` or `pom.xml`. List all dependencies
with their pinned versions. Flag any library version known to have a
CVE or that is significantly behind the current major release.

**core-webui:** Read `package.json`. Check `dependencies` and
`devDependencies`. Flag packages with known vulnerabilities in their
pinned version (e.g. outdated `@angular/*`, `webpack`, `node-fetch`).

**ai-service and RentManagerSyncSerivce:** Read `requirements.txt`.
Flag packages pinned to versions with known CVEs — common ones to check:
FastAPI < 0.100, requests < 2.31, cryptography < 41, Pillow < 10,
setuptools < 65.

Report: package name, current version, issue, recommended minimum version.

---

#### Category: `data-exposure`

**Sensitive data exposure review.**

1. **PII in API responses** — scan `core-api` DTOs and response types
   for fields that contain PII (SSN, full date of birth, bank account
   numbers, full credit card). Verify these are either not returned or
   are masked/redacted in the serialized response.

2. **Error response content** — check `GlobalExceptionHandler` in
   `core-api`. Verify stack traces, SQL error messages, and internal
   exception details are not included in HTTP error responses. The
   response body should contain a generic message, not the raw exception.

3. **Audit logging coverage** — in `core-api`, find endpoints that
   perform write operations (create, update, delete, approve) and verify
   they emit an audit event via `AuditEventService`. Flag any write
   endpoint with no audit trail.

4. **CORS policy** — find `CorsConfig` in `core-api`. Verify
   `allowedOrigins` is not `*` in production config. If it is `*`,
   flag as HIGH.

5. **Token storage in Angular** — in `core-webui`, check `AuthService`
   and any token handling code. Verify Firebase tokens are not stored in
   `localStorage` (should use memory or `sessionStorage` at most). Flag
   if `localStorage.setItem` is used with auth tokens.

---

#### Category: `architecture`

**Architecture and structural risk review.**

This is a broader review — the agent should read key files and reason
about structural risks, not just grep for patterns.

1. **Service boundary enforcement** — in `core-api`, check whether
   controllers call repositories directly (bypassing the service layer).
   The pattern is Controller → Service → Repository. Flag any controller
   that `@Autowires` a repository.

2. **Transaction boundary correctness** — find `@Transactional` on
   controller methods (should only be on service layer). Also find
   `@Transactional` service methods that call other `@Transactional`
   service methods — check for `REQUIRES_NEW` misuse.

3. **`ai-service` ↔ `core-api` coupling** — the ai-service should be
   called from `core-api` only, via Cloud Tasks callbacks. Verify there
   is no direct HTTP call from `core-webui` to `ai-service`. Flag if
   `environment.apiUrl` in the Angular app points to the ai-service.

4. **Circular dependencies** — in `core-api`, look for services that
   inject each other (A injects B, B injects A). These cause Spring
   context startup failures or require `@Lazy` hacks — flag any found.

5. **Dead code and zombie endpoints** — scan `core-api` controllers for
   `@RequestMapping` endpoints that have no callers in `core-webui`
   (grep for the path string in the Angular service files). Flag
   endpoints that appear unreachable — they're unmonitored attack surface.

6. **RentManagerSyncSerivce error handling** — the sync service writes
   to PostgreSQL. Find any entity sync function that catches exceptions
   silently (bare `except: pass` or logging without re-raise). Silent
   failures mean data gaps with no alert.

7. **Checkpoint bypass risk** — in `RentManagerSyncSerivce`, the
   `checkpoint_manager` enables incremental sync. Find any sync function
   that does not call the checkpoint manager — these functions re-sync
   from scratch on every run, which is a performance and correctness risk.

---

### Step 3 — Collect and merge findings

Wait for all agents to return. Merge their finding lists into a single
report, deduplicating any findings that multiple agents flagged.

Assign final severity using this hierarchy:

| Severity | Criteria |
|----------|----------|
| CRITICAL | Cross-tenant data leak; unauthenticated access to protected data; hardcoded production secret; SQL injection with user input |
| HIGH | Missing auth on a write endpoint; missing `@Valid` on a body that feeds SQL or AI; wide-open CORS; unmasked PII in responses |
| MEDIUM | Missing audit trail on write ops; 401 returned instead of 403; weak DTO validation; dead endpoint with no monitoring |
| LOW | Style/convention violation with minor security relevance; dependency update available without known CVE |

---

### Step 4 — Write the findings report

Write the report to `tasks/security-audit-{YYYY-MM-DD}.md` at the
monorepo root.

```markdown
---
date: {YYYY-MM-DD}
repos: {list}
categories: {list}
---

# Security Audit — {YYYY-MM-DD}

## Summary

| Severity | Count |
|----------|-------|
| CRITICAL | {n} |
| HIGH     | {n} |
| MEDIUM   | {n} |
| LOW      | {n} |
| **Total**| {n} |

---

## Critical findings

### {REPO} — {SHORT TITLE}
**File:** `{path/to/file.java}:{line-range}`
**Category:** {category}

{Description of the issue — 2-4 sentences. What the code does. Why it
is a problem. What could be exploited.}

**Recommended fix:**
{Concrete fix — code snippet or specific change instruction.}

---

{repeat for each finding, grouped by severity then repo}

## No issues found in

{List any category × repo combinations that came back clean — gives
confidence that those areas were actually checked.}

## Suggested Jira stories

{For each CRITICAL and HIGH finding, draft a one-line story title
suitable for creating a Jira ticket:}

- fix({REPO}): {title}
- fix({REPO}): {title}
```

---

### Step 5 — Report to the user

Output a summary to the terminal:

```
Security audit complete — {YYYY-MM-DD}
Report: tasks/security-audit-{YYYY-MM-DD}.md

CRITICAL  {n}  ← fix before next deploy
HIGH      {n}  ← fix this sprint
MEDIUM    {n}
LOW       {n}

Top issues:
  {top 3 findings, one line each}

Run /generate-task on the Jira story titles in the report to start fixing.
```

If zero findings: state clearly which categories were checked and that
nothing was found — do not produce a false-positive finding to seem useful.
