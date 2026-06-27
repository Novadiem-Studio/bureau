# Regression Fixture Conventions

> Canon module extracted from `docs/conventions.md`. Load this file only when its concern is triggered by the task.

## Regression fixture file format

One canonical definition of the per-fixture file format used in `RUN_DIR/regression/`. Every workflow and persona file points at this section; nothing re-documents it inline.

**Location and naming:** Fixtures live in `RUN_DIR/regression/`, one file per fixture, named `<NN>-<slug>.md` (NN = capture order).

**Five required fields:**

| Field | Required | Meaning |
|-------|----------|---------|
| `name:` | yes | Human-readable fixture name. |
| `command:` | yes | Copy-pasteable command. The literal value `command: <none — phase accepted on visual inspection>` is the legal value when a phase had no discrete verification command (see "Handling on re-run" below). A `command:` whose passing signal is "it worked when I ran it" is malformed — the `expected:` field must carry an objective signal instead. |
| `expected:` | yes | The passing signal: exit code, log line, or visible output. Must be specific enough that a fresh agent running the command in a clean context can determine pass/fail without judgment. |
| `phase:` | yes | Prompt id + workflow that introduced the fixture (e.g. `04 · execute-plan`). |
| `owner:` | yes | Owning workflow/prompt — so a deliberate breaking change knows which fixture to retire and why. |

**Two optional state flags** (not required fields; presence signals special handling):

| Field | Optional | Meaning |
|-------|----------|---------|
| `slow:` | optional | `slow: human judgment required` — present when the fixture cannot meet the <2-minute re-run target. A `slow:` fixture is **carried as a Warning** on re-run, never a blocker. |
| `retired:` | optional | `retired: <phase> — <reason>` — present when a deliberate change makes the fixture incorrect. A file carrying a `retired:` flag is **skipped** (not failed) by the re-run gate. Do NOT delete retired fixture files; the retirement notation is the record of a deliberate breaking change. |

**Handling on re-run**

When the Conductor re-runs fixtures from `RUN_DIR/regression/` before dispatching the next prompt (per `workflows/execute-plan/build-tail.md`), it applies the following rules per fixture file:

- **`retired:` present** → skip; not run, not a blocker.
- **`slow:` present** → skip running; carry as a Warning in the re-run log.
- **`command:` is the literal `<none — phase accepted on visual inspection>`** → skip; carry as a Warning (same handling as `slow:`); NOT run, NOT a blocker. This rule must be stated explicitly here so the legal `<none>` value cannot silently defeat the re-run gate (FR 4, Edge Case 1).
- **All other fixtures** → run the `command:` and compare output to `expected:`. A failure BLOCKS the next prompt; the logged failure names the fixture file, the command, and the actual failing output (never a generic "regression failed").
- The re-run result (per-fixture: pass / skip-Warning / fail-Blocker) is logged to `RUN_DIR/log.md` before the next coder is dispatched. This log entry is the inspectable artifact that makes the gate non-discretionary (AC 11).

**Passing signal, not a judgment rule:** A fixture whose `expected:` field is a vague judgment ('it worked', 'looks right') is malformed; the expected signal must be objective enough for a fresh agent to evaluate from the command's output alone.

**Fixture lifecycle: scratch → promote → standing**

Fixtures live in three homes across their lifetime:

- **Scratch (in-build):** `RUN_DIR/regression/` — authored during an execute-plan build, gitignored, pointing at the worktree via the `$ROOT` anchor (see "Repo-relative authoring rule" below). These are never committed. After promotion the scratch copy is superseded-but-retained as run provenance; it is not deleted.
- **Promote (close-out):** `scripts/promote-fixtures.sh` performs the deterministic mechanical core of promotion — skip `<none>` → refuse non-repo-relative → dedupe by slug + `command:`/`expected:` content → copy verbatim → run suite green — on the set the Conductor selects. The script does NOT repath, does NOT commit, does NOT push. See `scripts/README.md` and `workflows/execute-plan/build-tail.md` step 7.
- **Standing (committed):** `<repo>/.bureau/regression/` — promoted fixtures committed to the integration branch. The runner at `.bureau/regression/run.sh` executes the suite. This is the machine-checkable guarantee on every clone and CI checkout.

The scratch copy is superseded after promotion but left in place (gitignored, no cleanup cost; run archiving preserves it as provenance).

**Repo-relative authoring rule (FR 13 — malformed-fixture condition)**

Every fixture MUST be authored from the scratch dir with the anchor:

```sh
ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
```

and reference every in-repo path as `"$ROOT/…"`. Because of this anchor, the identical fixture text resolves to the worktree during the build (the runner exports `ROOT`; run standalone, `git rev-parse` resolves to the worktree) and to the repo after promotion — so **promotion is a verbatim copy with no rewriting**. A fixture whose `command:` body **lacks the `$ROOT` anchor above** — resolving its own operative paths via a machine-absolute path, a `$RUN_DIR` reference, or any un-anchored absolute path instead — is **malformed** and is refused at promotion (never rewritten), the same standard as a vague `expected:` field. The refusal check is the **absence of the anchor**: an anchored fixture is conformant even if its body mentions `$RUN_DIR` or an absolute path as test data it writes to a temp file (e.g. a fixture that exercises the promotion script's own refuse/skip paths). The prototype's 15 fixtures in `.bureau/regression/` already follow this rule.

**Mutation-test requirement (malformed-fixture condition)**

Before a fixture is accepted into `RUN_DIR/regression/` and before it is promoted to `.bureau/regression/`, deleting or inverting the guaranteed code MUST make the fixture's `command:` exit non-zero. This is an **authoring obligation** — NOT something `scripts/promote-fixtures.sh` verifies. The script cannot mutation-test generically (it does not know which source line each fixture guards); it explicitly does not attempt it. A fixture that passes the suite but fails mutation-test is malformed and must be fixed before promotion. The Conductor confirms mutation-test by a note in `log.md` before invoking the script.

**Comment-strip authoring rule (malformed-fixture condition)**

Static-grep fixtures MUST strip comment lines before grepping. Use `grep -v '^[[:space:]]*#'` (or equivalent) before any pattern check. A fixture whose `grep` pattern matches a code comment rather than live code is malformed: the guarantee can be deleted from real code and the fixture still passes. Example (correct):

```sh
strip() { grep -v '^[[:space:]]*#' "$1"; }
strip "$SCRIPT" | grep -q 'load-bearing-token'
```

**BSD grep / literal-`$` rule (malformed-fixture condition)**

Any fixture pattern containing a literal `$` character MUST use `grep -F` (fixed-string). BSD/macOS grep BRE/ERE mishandles a `$` in the middle of a pattern, so `grep 'add-dir "$CTX"'` silently fails to match the literal text while `grep -F` matches it.

**Nested-heredoc indentation rule (malformed-fixture condition)**

A `command: |` fixture that embeds a heredoc (e.g. `cat <<'EOF'` writing test input to a temp file) MUST indent the **entire** command block by at least 2 spaces — including the heredoc body lines AND the closing delimiter, with the closing delimiter at *exactly* 2 spaces. The runner (`run.sh`) extracts a `command: |` block by capturing lines only while they stay indented, stripping 2 leading spaces, and it STOPS at the first column-0 line. A heredoc body authored at column 0 truncates the command there: the runner then executes only the setup plus an unterminated heredoc opener and exits 0 **vacuously** — a false pass that tests nothing. After the 2-space strip, a 2-space-indented heredoc body lands at column 0 and the closing delimiter closes correctly. Always verify such a fixture by running it **through `run.sh`'s extraction path**, never by executing the raw `command:` body — the raw body closes the column-0 heredoc fine and hides the truncation.

No other section in the framework re-documents this format. Workflow and persona files reference this section by name.

---
