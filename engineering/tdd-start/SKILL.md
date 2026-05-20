---
name: tdd-start
description: >
  Start a TDD cycle for any story. Invoke after /generate-task has written
  the TASK.md file. Reads the task file, writes tests first mapped to each AC,
  commits the test file, then implements until all tests pass.
  Works across all repos: core-api (Java), core-webui (Angular),
  RentManagerSyncSerivce (Python), ai-service (Python/FastAPI).
  Usage: /tdd-start task-EL-101-some-slug.md
---

# tdd-start

Executes the TDD cycle for a story. Tests are written before any implementation
code. The test file is committed first so there is a clear record that tests
were not written after the fact.

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

**Determine stack for each repo:**

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

### Step 3 — Red-green-refactor loop (one AC at a time)

Execute the following loop once per AC, in order. Do not write the test for
AC2 until AC1 is green and refactored.

---

#### 3a — Write the test for this AC only

Create (or add to) the test file with a single test method for the current AC.
Do not write any other test methods yet.

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

#### 3b — Commit the test before implementing (AC1 only)

For the **first AC**, commit the test file immediately after writing it,
before writing any implementation. This creates a clear record that the test
came first.

**Java:**
```
git -C core-api add src/test/java/...
git -C core-api commit -m "test({KEY}): write failing test for AC1 — {slug}"
```

**Angular:**
```
git -C core-webui add src/app/...
git -C core-webui commit -m "test({KEY}): write failing test for AC1 — {slug}"
```

**Python:**
```
git -C {repo} add tests/
git -C {repo} commit -m "test({KEY}): write failing test for AC1 — {slug}"
```

For AC2 and beyond: add the new test to the existing file; do not commit again
until all ACs are green (commit happens in Step 4).

If the commit fails, stop and report the error. Do not proceed to implementation.

---

#### 3c — Confirm RED

Run only the test for this AC and verify it **fails**:

**core-api:**
```
./gradlew -p core-api test --tests "*{ClassName}Test.should_{behavior}_when_{condition}"
```

**core-webui:**
```
cd core-webui && ng test --include="**/path/to/{name}.spec.ts" --watch=false
```

**Python:**
```
cd {repo} && python -m pytest tests/test_{module}.py::test_{behavior}_when_{condition} -v
```

**If the test passes without any implementation:** stop. The test is not
testing anything real. Diagnose why (wrong class under test, wrong assertion,
stub returning a value by accident) and fix before continuing.

Report to the user: `🔴 AC{N} — test is RED (expected)`

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

Run the same test again:

**If it still fails:** fix the implementation. Do not move on until it passes.

**If it passes:** report `🟢 AC{N} — test is GREEN`

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

#### 3g — Repeat for next AC

Return to 3a for the next acceptance criterion. Continue until all ACs have
a green, refactored test.

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
📋 Tests: {n} passing, 0 failing ({repo(s)})
📄 Completion report: tasks/completion-{TICKET_KEY}-{slug}.md

Waiting for your smoke test approval.
Run /close-story {TICKET_KEY} once you have confirmed the behaviour.
```

Do not commit implementation code yet — that happens in /close-story
after smoke test approval.
