---
name: tdd-start
description: >
  Run the TDD cycle for a story against a FROZEN acceptance spec that
  /generate-task already authored and committed (one failing case per AC).
  Reads the task file, drives each frozen case from RED to GREEN, adds its own
  unit tests as scaffolding, and may not rename, delete, skip, or weaken any
  frozen case. Works across all repos: core-api (Java), core-webui (Angular),
  RentManagerSyncSerivce (Python), ai-service (Python/FastAPI).
  Usage: /tdd-start task-EL-101-some-slug.md
---

# tdd-start

Executes the TDD cycle for a story **against a frozen acceptance spec**.

## Bindings

Resolve each `{binding}` from the `## PROJECT_HARNESS` block in the project's
`CLAUDE.md`; if absent, use the parenthesized fallback (current Spyglass value).
See HARNESS.md.

- `{repos}` — each has `path`, `lang`, `framework`, `suite_root`, `test` (command).
  The two tables below (frozen-suite paths, stack/framework) are the Spyglass
  defaults; when a `PROJECT_HARNESS` block is present, read each repo's `suite_root`
  / `framework` / `test` from it instead.

`/generate-task` has already authored and committed, per repo, one runnable
acceptance case per AC — each currently failing with `not implemented`. That
frozen spec is the contract. This skill does NOT author the acceptance tests;
it drives each frozen case from RED to GREEN by replacing the placeholder with
a real assertion and writing the implementation that satisfies it.

Two layers of tests are in play, and they are different:

1. **The frozen acceptance suite** (one case per AC, under `acceptance/{KEY}/`
   in each repo). You did not write it and you may NOT rename, delete, skip,
   re-bind, or weaken any case. You complete its assertion body; that is all.
2. **Your own unit tests** (scaffolding). Write as many as you need to drive
   out each AC — validation, happy path, error branches. These are yours to
   author freely under the test-quality rules below. They support your work;
   they never replace a frozen acceptance case.

Supports all four main repos — test patterns and run commands adapt to the
language and framework of the target repo.

## Invocation

```
/tdd-start task-EL-101-some-slug.md
```

Pass the task filename from `tasks/` at the monorepo root. If no filename is
given, look for the most recently modified `task-EL-*.md` in that directory
and confirm with the user before proceeding.

### Context discipline (sub-agent mode)

This skill is designed to run in a **fresh context window** — either
launched as a sub-agent by `generate-task`, or by the user after clearing
context manually.

On startup, read **only**:
1. The task file at `tasks/{filename}`
2. `CLAUDE.md` at the monorepo root (constraints)
3. Each target repo's own `CLAUDE.md` if one exists

Do not read other files until the step instructions direct you to a specific
file path. Pull source files on demand (when writing a test or implementation)
rather than loading them all upfront.

---

## Instructions

Follow every step in order. Do not write implementation code before Step 3d.

### Step 1 — Read and validate the task file

Read the task file at `tasks/{filename}` (monorepo root tasks directory).

Verify:
- Acceptance criteria section is populated — if empty or marked
  `⚠️ NO ACs FOUND`, stop and tell the user the story cannot proceed
  without acceptance criteria
- Status in frontmatter is `active`
- **The frozen acceptance suite exists for every target repo.** The task
  file's **Frozen acceptance spec** section lists each repo's suite path and
  manifest. For each target repo, confirm `acceptance/{KEY}/manifest.json`
  exists and lists one case per AC assigned to that repo. If any repo's suite
  or manifest is missing, STOP and report: the spec must be frozen by
  /generate-task before implementation can begin. Do not author the acceptance
  tests yourself.

Per-repo frozen suite locations — `{repo.path}/{repo.suite_root}` for each target
repo (resolve from `{repos}`; `{KEY}` expands to the ticket key). Spyglass defaults:

| Repo | Frozen suite path |
|---|---|
| `core-api` | `core-api/src/test/java/com/spyglassanalytics/core/api/acceptance/{KEY}/` |
| `core-webui` | `core-webui/src/app/acceptance/{KEY}/` |
| `RentManagerSyncSerivce` | `RentManagerSyncSerivce/tests/acceptance/{KEY}/` |
| `ai-service` | `ai-service/tests/acceptance/{KEY}/` |

**Special case — visual-only UI story:**
If the story type is **UI Story** AND a Figma node ID is set AND all ACs
describe visual/layout outcomes (no behavioral logic, state changes, or
service interactions), stop and tell the user:
"This appears to be a visual-only story. Use /eval-ui after implementing
the component — no TDD cycle needed."

All other story types (including UI stories with behavioral ACs) proceed.

Extract:
- Ticket key (e.g. `EL-101`) from the `ticket:` frontmatter field
- Story summary from the `# TASK:` heading
- Target repos from the `repos:` frontmatter field (list)
- Each numbered AC exactly as written — do not paraphrase

**Figma gate (UI stories only):**

After extracting the above fields, if the story type is **UI Story**, check
the **Figma reference** section:

- If the Figma node ID is populated: continue normally.
- If the node ID is `⚠️ NOT SET` or the section is blank, warn the user:

  "Figma reference is missing from the task file. The /eval-ui step will
  not be able to run without it. Do you have a Figma URL to add now?
  (paste it or type 'skip' to continue without it)"

  If the user provides a URL:
  - Extract `fileKey` and `node-id` query param from the URL
  - Normalize node ID to `:` separator (e.g. `0-1` → `0:1`)
  - Update the task file's Figma reference section before proceeding

  If the user types 'skip', note it and continue — the agent will flag the
  missing Figma reference again in the completion report.

**Determine stack for each repo** (read `{repo.lang}` / `{repo.framework}` from
`{repos}`; Spyglass defaults shown):

| Repo | Stack | Test framework |
|---|---|---|
| `core-api` | Java 21 / Spring Boot | JUnit 5 + Mockito |
| `core-webui` | Angular 18 / TypeScript | Jasmine + Angular TestBed |
| `RentManagerSyncSerivce` | Python 3.10+ | pytest + unittest.mock |
| `ai-service` | Python / FastAPI | pytest + unittest.mock |

If the story spans multiple repos, run the full TDD cycle for each repo in
sequence — complete Steps 2–6 for repo 1, then repeat for repo 2, etc.

---

### Step 2 — Identify the unit(s) under test

From the task file's **Target files** section and the story description,
identify the primary unit being built or modified per repo. This determines
the test file name and location.

**core-api (Java):**
- New controller → test class `{ControllerName}Test`
- New or modified service method → test class `{ServiceName}Test`
- New repository query → test class `{RepositoryName}Test`
- Multiple layers → one test class per layer; start with the service layer
- Mirror the source path under the test tree:
  `src/main/java/.../services/FooService.java`
  → `src/test/java/.../services/FooServiceTest.java`

**core-webui (Angular):**
- New or modified service → `{service-name}.service.spec.ts` alongside the service file
- New component with behavioral logic → `{component-name}.component.spec.ts`
- New guard or resolver → `{name}.guard.spec.ts` / `{name}.resolver.spec.ts`
- Focus tests on the behavioral ACs — not rendering details (those belong in eval-ui)

**RentManagerSyncSerivce (Python):**
- New sync module function → `test_{module_name}.py` in a `tests/` directory
  alongside the module (create `tests/` if it doesn't exist)
- Modified function in an existing module → add test cases to the existing
  `test_{module_name}.py` if one exists, otherwise create it
- Use the module name as the test file name: `owner.py` → `tests/test_owner.py`

**ai-service (Python/FastAPI):**
- New route handler → `tests/test_{router_name}.py`
- New capability module → `tests/test_{capability_name}.py`
- Mirror the source layout under `tests/`

---

## Test quality rules

Before writing any test, internalize these rules. Violations must be fixed
before moving to the next AC.

- **Public interfaces only** — test through the same surface a real caller
  would use. No access to private methods, no assertions on internal fields.
- **Mocks only at system boundaries** — mock the DB, external APIs, time,
  and file I/O. Never mock one internal class to test another internal class.
- **One primary assertion per test** — if you need `assertThat(a)` AND
  `assertThat(b)` to describe the outcome, you are testing two things; split
  into two tests.
- **Tests must survive refactoring** — if renaming an internal method or
  extracting a helper breaks a test without changing observable behavior,
  the test is testing implementation, not behavior. Rewrite it.

---

### Step 3 — Red-green-refactor loop (one frozen AC case at a time)

Execute the following loop once per **frozen acceptance case**, in AC order.
The cases already exist under `acceptance/{KEY}/` — your job is to drive each
one from its `not implemented` placeholder to a real, passing assertion, with
the implementation behind it. Do not start AC2's case until AC1's case is
green and refactored.

The hard rule for every cycle: you may fill in a frozen case's assertion body,
but you may NOT rename it, change its AC binding, delete it, mark it skipped,
or replace its assertion with a tautology (`assertThat(true).isTrue()`,
`assert True`, `expect(true).toBe(true)`, etc.). If you believe a frozen case
is genuinely wrong, STOP and report it to the orchestrator — do not edit around
it.

---

#### 3a — Open the frozen case for this AC, and add your own unit tests

Locate the frozen acceptance case for the current AC (its name and file are in
the manifest). It currently fails with `not implemented`.

Replace the `not implemented` placeholder with a **real assertion** that
exercises this AC through the public interface — using the per-framework
patterns below. This is still the contract case; keep its name and AC binding
exactly as frozen.

Then write your **own unit tests** as scaffolding for the slice — as many as
you need (validation, happy path, error branches). These live in your normal
test files (NOT under `acceptance/{KEY}/`) and are yours to author freely under
the test-quality rules above. The frozen case proves you built the right thing;
your unit tests prove it works internally.

The scaffolds below apply to BOTH the frozen case's assertion body and your own
unit tests.

**core-api (Java) — test class scaffold (create once, before AC1):**

```java
@ExtendWith(MockitoExtension.class)
class {ClassName}Test {

    @Mock private {DependencyOne} dependencyOne;
    @Mock private {DependencyTwo} dependencyTwo;

    @InjectMocks private {ClassUnderTest} subject;

    private static final Long   CUSTOMER_ID   = 1L;
    private static final UUID   CUSTOMER_UUID = UUID.fromString("00000000-0000-0000-0000-000000000001");
    private static final String USER_ID       = "test-user-id";

    @BeforeEach
    void setUp() { }

    // AC{N}: {exact AC text}
    @Test
    void should_{behavior}_when_{condition}() {
        // Arrange
        when(dependencyOne.method(any())).thenReturn(someValue);
        // Act
        var result = subject.methodUnderTest(args);
        // Assert
        assertThat(result).isEqualTo(expected);
        // Verify (where relevant)
        verify(dependencyOne, times(1)).method(any());
    }
}
```

**core-webui (Angular) — test scaffold:**

```typescript
describe('{ClassName}', () => {
  let service: {ClassName};
  // One spy per injected dependency

  beforeEach(() => {
    TestBed.configureTestingModule({
      imports: [...],
      providers: [
        {ClassName},
        { provide: {Dep}, useValue: jasmine.createSpyObj('{Dep}', ['method']) },
      ]
    });
    service = TestBed.inject({ClassName});
  });

  // AC{N}: {exact AC text}
  it('should {behavior} when {condition}', () => {
    depSpy.method.and.returnValue(of(mockValue));
    service.methodUnderTest(args);
    expect(service.someState).toEqual(expected);
  });
});
```

Notes (Angular):
- Use `HttpClientTestingModule` for services that make HTTP calls
- Use `jasmine.createSpyObj` for dependencies — not real instances
- Behavioral ACs only — no DOM rendering assertions (those belong in eval-ui)
- Async: use `fakeAsync` + `tick()` for observable/promise chains

**RentManagerSyncSerivce (Python) — test function:**

```python
from unittest.mock import MagicMock, patch, call
import pytest

# AC{N}: {exact AC text}
def test_{behavior}_when_{condition}():
    # Arrange
    mock_cursor = MagicMock()
    mock_conn = MagicMock()
    mock_conn.cursor.return_value = mock_cursor
    # Act
    result = function_under_test(mock_conn, args)
    # Assert
    assert result == expected
    mock_cursor.execute.assert_called_once_with(expected_sql, expected_params)
```

Notes (Python):
- Use `unittest.mock.patch` for external calls (RentManager API, DB)
- Always test that `customer_id` is included in upsert params (multi-tenant constraint)
- Use `pytest.raises` for error path tests
- Create `tests/__init__.py` if it doesn't exist

**ai-service (Python/FastAPI) — test function:**

```python
from fastapi.testclient import TestClient
from unittest.mock import MagicMock, patch
import pytest
from main import app

client = TestClient(app)

# AC{N}: {exact AC text}
def test_{behavior}_when_{condition}():
    with patch('module.dependency') as mock_dep:
        mock_dep.return_value = expected_value
        response = client.post('/endpoint', json={...})
        assert response.status_code == 200
        assert response.json() == expected
```

Notes (FastAPI):
- Use `TestClient` for route-level tests
- Use `patch` for Vertex AI / external service calls — never call real APIs in tests

---

#### 3b — (removed)

There is no "commit the test first" step. The frozen acceptance suite was
already committed by /generate-task **before** any implementation existed —
that commit is the record that tests predate the code, and it is stronger than
a mid-loop commit because the whole contract was frozen up front. Proceed
straight to the RED check below. The single implementation commit happens in
Step 4.

---

#### 3c — Confirm RED

Run only the frozen acceptance case for this AC and verify it **fails** —
now failing on your real assertion (not on the `not implemented` placeholder,
which you replaced in 3a):

**core-api:**
```
./gradlew -p core-api test --tests "*acceptance.{KEY}.Ac{N}AcceptanceTest.should_{behavior}_when_{condition}"
```

**core-webui:**
```
cd core-webui && ng test --include="**/acceptance/{KEY}/ac{N}.acceptance.spec.ts" --watch=false
```

**Python:**
```
cd {repo} && python -m pytest tests/acceptance/{KEY}/test_ac{N}_acceptance.py -v
```

**If the case passes before you have written any implementation:** stop. Either
your assertion is a tautology (fix it — it must actually exercise the AC) or the
behavior already exists (verify that is truly the case before accepting it).
A frozen case must fail on a real assertion before you implement.

Report to the user: `🔴 AC{N} — frozen case is RED on a real assertion (expected)`

---

#### 3d — Implement the minimum to pass

Write only what is required to make this test go green:

- No extra methods, no extra fields, no extra error handling
- No behavior not asserted by the current test
- Follow conventions from the task file's **Architectural constraints** section
- Match patterns of the surrounding code

If a Flyway migration is needed (core-api):
`core-api/src/main/resources/db/migration/V{NEXT}__description.sql`
where NEXT is one higher than the current latest migration file.

Component files (core-webui): use `.css` not `.scss`, reactive forms only,
inject `HttpClient` directly, build URLs from `environment.apiUrl`.

---

#### 3e — Confirm GREEN

Run the frozen acceptance case for this AC again, plus your own unit tests for
the slice:

**If either still fails:** fix the implementation. Do not move on until the
frozen case AND your unit tests pass.

**If both pass:** report `🟢 AC{N} — frozen case GREEN + unit tests GREEN`

---

#### 3f — Refactor

With the test green, look for opportunities to improve the code without
changing behavior. Refactor triggers to check:

- **Duplication** — two methods doing the same thing → extract a shared helper
- **Long method** — more than ~20 lines of logic → extract private helpers
- **Shallow module** — exposed interface nearly as complex as the implementation → deepen it
- **Feature envy** — logic operating on another class's data → move it to that class
- **Primitive obsession** — raw strings/ints representing domain concepts → introduce a value type

After any refactor, rerun the test to confirm it is still green.
If a refactor breaks the test and you cannot revert it cleanly, the test
was testing implementation details — fix the test to use the public interface.

Report: `✅ AC{N} — refactored and still GREEN`

---

#### 3g — Regression check, then next AC

Before moving on, run the frozen acceptance suite **for this story so far**
(every frozen case implemented up to and including this AC) and confirm all
are still green — implementing this AC must not have broken an earlier one:

```
# core-api
./gradlew -p core-api test --tests "*acceptance.{KEY}.*"
# core-webui
cd core-webui && ng test --include="**/acceptance/{KEY}/*.acceptance.spec.ts" --watch=false
# python
cd {repo} && python -m pytest tests/acceptance/{KEY}/ -v
```

If an earlier frozen case regressed, fix it before continuing. Then return to
3a for the next acceptance criterion. Continue until every frozen case is
green and refactored.

(If your suite is slow, this per-AC regression run can be limited to the
frozen `acceptance/{KEY}/` suite as shown above — the full repo suite still
runs once in Step 5.)

---

### Step 4 — Commit all test and implementation files

Once all ACs are green and refactored, commit the full set of changes
(test file + implementation files) in one commit per repo:

**Java:**
```
git -C core-api add src/
git -C core-api commit -m "feat({KEY}): implement {slug}"
```

**Angular:**
```
git -C core-webui add src/
git -C core-webui commit -m "feat({KEY}): implement {slug}"
```

**Python:**
```
git -C {repo} add .
git -C {repo} commit -m "feat({KEY}): implement {slug}"
```

Confirm the commit succeeded. If it fails, report the error and stop.
For multi-repo stories, commit in each repo before running the full suite.

---

### Step 5 — Run the full test suite (regression check)

Once the target tests are fully green, run the full suite for the repo to
check for regressions:

**core-api:**
```
./gradlew -p core-api test
```

**core-webui:**
```
cd core-webui && ng test --watch=false
```

**RentManagerSyncSerivce:**
```
cd RentManagerSyncSerivce && python -m pytest tests/ -v
```

**ai-service:**
```
cd ai-service && python -m pytest tests/ -v
```

**Categorise every failure before deciding what to do:**

1. Run the full suite and collect all failing test names.
2. For each failure, check whether it existed on this branch before your changes:
   - Run `git stash && ./gradlew test 2>&1 | grep FAILED` (or equivalent), then `git stash pop`
   - If the test was already failing before your changes: it is **pre-existing** — document it
     in the completion report and continue. Do not fix pre-existing failures.
   - If the test was passing before your changes: it is a **regression** — fix it before continuing.

Do not proceed to the completion report with an unresolved regression.
Pre-existing failures are acceptable — document them in the completion report's Notes section
with the label "Pre-existing (not caused by this story)".

For multi-repo stories, run the full suite in all repos before proceeding.

---

### Step 6 — Write COMPLETION.md

Write `tasks/completion-{TICKET_KEY}-{slug}.md` (monorepo root tasks directory):

```markdown
---
ticket: {TICKET_KEY}
status: PASS | FAIL | NEEDS_REVIEW
completed: {YYYY-MM-DD}
---

# COMPLETION: {TICKET_KEY} — {story summary}

## Test results

| Repo | Test file | Tests | Failures |
|------|-----------|-------|----------|
| {repo} | {test file} | {n} | 0 |

## AC results

| AC | Test | Result |
|----|------|--------|
| AC1 | {test name} | ✅ Pass |
| AC2 | {test name} | ✅ Pass |

## Frozen spec integrity

Confirm and report each of these — the run-story verify phase re-checks them
independently, so they must be true:

- [ ] Every frozen case in each repo's `acceptance/{KEY}/manifest.json` still
      exists with its original name and AC binding
- [ ] No frozen case still contains `not implemented` — every placeholder was
      replaced with a real assertion
- [ ] No frozen case was skipped, disabled, or weakened to a tautology
- [ ] `git diff --name-only acceptance/{KEY}/` shows only assertion-body
      changes within the frozen case files (no renamed/deleted case files,
      no manifest edits)

| Repo | Frozen cases | Placeholders remaining | All green |
|------|-------------|------------------------|-----------|
| {repo} | {n} | 0 | ✅ |

## Files changed

- `{file path}` — {what changed}
- `{test file path}` — new test file

## Notes
{Edge cases found, decisions made, anything deferred}

## Smoke test checklist

Derived from the story ACs — one manual verification step per AC.
Check each item off in the running app before calling /close-story.

| # | AC | Manual verification step | Done? |
|---|-----|--------------------------|-------|
| 1 | {AC1 text} | {what to do in the app to verify it} | [ ] |
| 2 | {AC2 text} | {what to do in the app to verify it} | [ ] |

## Ready for smoke test
{yes | no — if no, explain what is blocking}
```

---

### Step 7 — Report completion

Output:

```
✅ TDD cycle complete: {TICKET_KEY}
📋 Builder-reported: {n} passing, 0 failing ({repo(s)}) — pending independent verify
🧊 Frozen spec: {n} cases green, 0 placeholders remaining, manifest intact
📄 Completion report: tasks/completion-{TICKET_KEY}-{slug}.md

Verification (run-story Phase 3) will re-run the frozen suite from a clean
checkout before the smoke gate. Run /close-story {TICKET_KEY} only after
smoke test approval.
```

Do not commit implementation code yet — that happens in /close-story
after smoke test approval.
