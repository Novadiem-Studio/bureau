# Battle-test matrix — conductor-capture-ownership (idea #22)

**Canon surfaces touched:** `scripts/conductor-stop.sh`, `scripts/account-tokens.sh`, `agents/orchestrator.md § Pointer lifecycle`, `scripts/promote-fixtures.sh` (enabling glob fix), `.bureau/regression/` fixtures
**Promotion to canon:** yes (declared by The Conductor per docs/conductor-gates.md)
**Status:** EXECUTED 12/12 — `## Run 2026-07-08` block below. Regression suite 112 PASS / 0 FAIL / 4 SKIP.

The fix: a foreign session that merely *read* a run's `log.md` acquired the ownership nonce
from it and fired phantom `CONDUCTOR-TOKEN-EVENT`s; the consumer summed them and the real
conductor's `final:true` blessed the inflated total as `confidence: exact` (observed on the
B16 run, 48.85M / legs:2 / exact). The fix replaces ownership-by-mention with
ownership-by-identity (the firing session's launch cwd, encoded independently in the pointer
and the transcript path), flips consumer confidence from any-leg-final to all-legs-final, and
adds a suspicious-multi-leg annotation.

---

## Run 2026-07-08

**Date:** 2026-07-08
**Environment:** macOS 25.5.0 (Darwin), Bash 3.2, jq
**Actor:** The Conductor (opus) — Phase-3 promotion gate, self-run
**Scripts under test (worktree `bureau/20260707-conductor-capture-ownership`):** `scripts/conductor-stop.sh` (new Step C.0 project-dir gate + `_bl_write_back` preservation), `scripts/account-tokens.sh` (FR-4 all-legs-final + FR-5 suspicious note), `agents/orchestrator.md § Pointer lifecycle` (five-field pointer, nonce-free enrollment line, `resumed_legs` increment), `scripts/promote-fixtures.sh` (three-digit glob)
**Regression suite:** 112 PASS / 0 FAIL / 4 SKIP (skips = pre-existing `slow:` 50/51 + newly-retired 73/75)

| Case | AC/FR | Result | Key evidence |
|------|-------|--------|--------------|
| Foreign-cwd watcher exclusion (the B16 bug) | AC 1 / FR 2 | PASS | End-to-end: a transcript carrying nonce+RUN_DIR but under a different munged projects-dir fires the hook → `exit 0`, NO `CONDUCTOR-TOKEN-EVENT` appended. Fixture 101 + live integration probe. |
| Matching-cwd / resume capture | AC 2 / FR 7 | PASS | A transcript under the munged `project_dir` → hook proceeds, event appended. Fixture 102 + live probe. |
| Nonce-free enrollment log line | AC 3 / FR 3 | PASS | Executed run-start enrollment: the log line matches `[0-9a-f]{8}-[0-9a-f]{4}` **zero** times; the `cat "$_pointer_file"` transcript echo is preserved (Step-C credential). |
| pointer.project_dir present == cwd | AC 10 / FR 1 | PASS | Five-field pointer written by the run-start `printf`; `jq .project_dir` == the Conductor's `$(pwd -P)`, non-empty. |
| resumed_legs increment on resume | FR 11 | PASS | Executed resume sub-path (A) echo-existing + shared tail: `state.json.resumed_legs` absent → 1 after one resume. Increment sits in the shared tail (both sub-paths), not nested. |
| Consumer per-leg all-final (mixed → partial) | AC 4 / FR 4 | PASS | Fixture 104: two sessions, one `final:true`, one not → `conductor_tokens.confidence == "partial"` (was `exact` under any-final). Mutation-verified (revert to any-final → 104 FAILs). |
| Suspicious-multi-leg note | AC 5 / FR 5 | PASS | Fixture 105: `legs > resumed_legs + 1` → `_note` CONTAINS "conductor legs detected" (substring; note merged with `$cond_block_note`). Mutation-verified (null note → 105 FAILs). |
| All-legs-final → exact | AC 7 / FR 4 | PASS | Fixture 106: both sessions carry a `final:true` → `confidence == "exact"`, `legs == 2` (73 successor). Mutation-verified. |
| B16 re-score ON A COPY (evidence preserved) | AC 6 / FR 8 | PASS | `account-run.sh` (via `bash`) on a `mktemp` copy of the sealed B16 archive → `confidence: "partial"` (was `exact`), `_note` present, `processed` sum **48851832 unchanged** (no exclusion), exit 0, valid JSON. Sealed archive SHA-256 identical before/after (byte-for-byte untouched). |
| EC-2 fail-open (absent project_dir) | EC 2 / FR 6 | PASS | Fixture 103 + the 16 pre-existing project_dir-less hook fixtures (62-71, 92-98, 100) stay GREEN via fail-open. `project_dir` deliberately NOT in Step B's required-keys guard. Mutation-verified (adding it → 103 + the fleet FAIL). |
| `_bl_write_back` preserves project_dir | EC 8 | PASS | Baseline write-back recomposes `{…, project_dir: .project_dir}`; traced a real first-fire baseline rewrite — `project_dir` survives, gate does NOT self-disable after first fire. |
| promote-fixtures.sh three-digit glob | AC 8 | PASS | Candidate glob extended to `[0-9][0-9][0-9]-*.md` (mirrors `run.sh:21`); dry-run now enumerates a three-digit fixture (106) that the old two-digit glob silently skipped. `bash -n` clean. |

**Exit discipline:** every path in `conductor-stop.sh` is `exit 0` (`grep -cE "exit [1-9]"` == 0). The single permitted stderr is the W2 diagnostic, emitted ONLY when a `project_dir` mismatch coincides with nonce+RUN_DIR both present in the transcript (owner-looking false-exclude) — never on a plain mismatch.

**Summary:** 12/12 PASS. Regression suite 112/0/4. Upstream drift check (`check-drift.sh`): one global install — no per-project copies to drift-check. Accepted residual (named per FR 5 / round-1 W5): EC-2 fail-open lets a foreign session win against a *legacy* (pre-fix, project_dir-less) pointer via the retained nonce-grep — bounded to in-flight runs at the upgrade boundary, self-heals when that run's pointer is removed. Deferred (round-1 OQ 1): no session_id pinning in v1 (same-cwd-watcher residual doubly-mitigated by retained nonce-grep + nonce-out-of-log).

**Build-integrity note:** the build-diff cold reviewer left one un-restored mutation in the worktree (`|| [ -z "$project_dir" ]` added to Step B's required-keys guard during its fail-open mutation check). It was caught by this promotion-gate suite re-run (10 project_dir-less fixtures failed) and reverted before promotion. Lesson recorded in the evaluation ledger.

---

## Case table

The twelve cases above are the standing matrix for this bundle. Re-run on any change to
`conductor-stop.sh` Step C.0 / `_bl_write_back`, `account-tokens.sh` FR-4/FR-5 confidence
logic, or `agents/orchestrator.md § Pointer lifecycle`. Each fixture case (101-106, 103) is
mutation-tested; the enroll/resume cases (AC 3/10, FR 11) and the B16-copy re-score (AC 6) are
executed live because no hook fixture can drive a real Conductor enrollment.
