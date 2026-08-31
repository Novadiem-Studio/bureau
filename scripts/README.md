# Usage snapshot (statusLine)

`scripts/statusline-usage.sh` is the Claude Code `statusLine` command. Claude Code pipes a
JSON payload on stdin after each API response; the script extracts the 5-hour and 7-day
`rate_limits` fields, writes `~/.novadiem/usage-snapshot.json` in the standard schema, and
prints a compact status bar. No external app, no keychain prompts, no launchd agent needed —
Claude Code itself (the token owner) hands the numbers over directly.

The snapshot is updated after every API response, so the Conductor always reads live data
without triggering any separate process.

Retired scripts `poll-usage-snapshot.sh` and `install-usage-poller.sh` are kept in place
for reference but marked retired at the top of each file.

## Setup

Wire it in `~/.claude/settings.json` (merge into the existing file — do not replace it):

```json
{
  "statusLine": {
    "type": "command",
    "command": "<path-to-bureau>/scripts/statusline-usage.sh"
  }
}
```

No other install step. Requires **jq** (`brew install jq`).

## Verify

After any Claude Code API response, check the snapshot:

```bash
jq '{sessionUsed: .claude.sessionUsedPercent, weeklyUsed: .claude.weeklyUsedPercent, weeklyResetsIn: .claude.weeklyResetsIn}' ~/.novadiem/usage-snapshot.json
```

## Snapshot location

Default: `~/.novadiem/usage-snapshot.json`

Override with `NOVADIEM_USAGE_SNAPSHOT_PATH`. The Conductor read rules are in
`agents/orchestrator.md` § Budget handling.

## Environment variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `NOVADIEM_USAGE_SNAPSHOT_PATH` | `~/.novadiem/usage-snapshot.json` | Where to write the snapshot |

## Snapshot schema

`source` is `"claude-code-statusline"`. Fields from `rate_limits` are the 5-hour session
window and the 7-day weekly window. Sonnet-specific fields are not available from this
source and are always `null`; `sonnetBurnMode` is always `false`.

```json
{
  "polledAt": "2026-06-12T05:31:23Z",
  "source": "claude-code-statusline",
  "ok": true,
  "providersRequested": "claude",
  "providers": [],
  "claude": {
    "loginMethod": "Claude Max",
    "sessionLeftPercent": 100,
    "sessionUsedPercent": 0,
    "sessionWindowMinutes": 300,
    "sessionResetsIn": "0d 4h",
    "weeklyLeftPercent": 38,
    "weeklyUsedPercent": 62,
    "weeklyResetsIn": "4d 14h",
    "weeklyPaceDeficitPercent": null,
    "weeklyRunsOutIn": null,
    "sonnetLeftPercent": null,
    "sonnetUsedPercent": null,
    "sonnetResetsIn": null,
    "sonnetBurnTargetLeftPercent": null,
    "sonnetBurnMode": false
  },
  "rateLimits": {
    "fiveHour": { "usedPercent": 0, "resetsAt": 1749710400 },
    "sevenDay": { "usedPercent": 62, "resetsAt": 1750060800 }
  }
}
```

On failure (jq missing, no rate_limits in payload), the snapshot is left untouched from the
last good write. Treat as **stale** if `polledAt` is older than ~30 minutes or `ok` is false.

## Conductor behavior

1. Read snapshot at **run start** and before expensive (`frontier` / `escalated`) spawns.
2. Log budget notes in `RUN_DIR/log.md`.
3. **Model routing:** run `scripts/resolve-model-routing.sh` — see `config/runtimes/README.md`
   and `config/model-experiments/README.md`.
4. Legacy Claude-only runs may still use `scripts/resolve-model-tiers.sh` and
   `config/experiments/README.md` until migrated.

### One-shot Spark Mage helper (Codex)

`scripts/run-codex-spark-specialist.sh <RUN_DIR> <WORKTREE> <PROMPT_FILE> <ATTEMPT_ID>`
is the transport for the resolved `granular-ui-fast` execution profile. It is not a general
launcher: it accepts only a vetted first-pass `execute-plan` prompt owned by The Mage and tagged
`Execution-profile: granular-ui-fast`. It runs Spark/high in an ephemeral `codex exec`, requires
a clean worktree and one committed result, verifies the exact Mage handoff, and stores sanitized
evidence in `RUN_DIR/codex-specialists/<attempt-id>/`.

Exit `0` means a committed handoff is ready for normal cold review. Exit `75` proves Spark failed
without touching HEAD or the worktree, so the Conductor may start a fresh role-default Mage
attempt. Exit `2` is a contract/setup error; exit `76` or an interrupted/unrecognized status may
include worktree effects. None of those may be reset or retried automatically. The private
nonce-bearing launch prompt and raw Codex events are temporary and must not be copied into run
artifacts.

Thresholds (from `agents/orchestrator.md`):

- `sonnetBurnMode` — always `false` from this source; the legacy sonnet-burn auto-trigger is
  inactive. Use manual experiments such as `budget-pressure-standardize` instead.
- `sessionUsedPercent` ≥ 90 — session cap risk.
- `weeklyUsedPercent` ≥ 85 — defer non-critical frontier/escalated work.

---

## Post-hoc run accounting

In integrated Delegate-topology Claude runs, Delegate, Conductor, and specialist token figures are
recovered from Claude JSONL transcripts at terminal close-out. Direct-Conductor Claude runs do not
record the Delegate session identity needed to locate the transcript tree, so their per-leg figures
remain an explicit legacy gap. `scripts/aggregate-transcripts.sh` is the sole authoritative per-leg
source; the retired Stop/SubagentStop rail is not a fallback.

Run the public close-out command after the run's final merge, summary, and state/log updates:

```sh
scripts/account-run.sh "$RUN_DIR"
```

`account-run.sh` chooses a half-open upper bound, invokes
`aggregate-transcripts.sh "$RUN_DIR" --until <bound>`, validates its stdout contract, passes that
fragment to `account-tokens.sh` for derived metrics, and atomically publishes
`RUN_DIR/accounting.json`. An unchanged re-run reuses the saved `_posthoc.run_ended_at` bound; growth
in the recorded SPAWN-EVENT/Conductor-leg basis advances the bound and re-aggregates the run. There
is no deferred Stop-hook refresh after this command.

The aggregator is also useful on its own:

```sh
scripts/aggregate-transcripts.sh "$RUN_DIR"
scripts/aggregate-transcripts.sh "$RUN_DIR" --until 2026-08-14T12:00:00Z
```

It emits one JSON object containing `delegate`, `conductor`, and `specialists` blocks. Usage is
deduplicated by Claude `message.id`; transcript gaps, collisions, and incomplete zeroes are labelled
with non-exact confidence and a note. A non-Claude runtime returns a named `_runtime_gap` before any
Claude transcript lookup, and `account-run.sh` does not replace that gap with legacy hook totals.
Full contracts and confidence rules: `docs/run-accounting.md § B2`.

### Retired Stop/SubagentStop compatibility stubs

`scripts/conductor-stop.sh` and `scripts/subagent-stop.sh` are permanent exit-0 stubs. They remain
on disk so stale wiring fails softly, but they do not read transcripts, append token events, refresh
accounting, or remove run-scope files.

Do not wire either script into `~/.claude/settings.json`. Remove only legacy Bureau entries whose
commands end in `scripts/conductor-stop.sh` or `scripts/subagent-stop.sh`; preserve `statusLine` and
all unrelated settings. On its Claude-host branch, `./check-framework.sh` fails when either retired
Bureau hook remains wired.
`REVIEWER-TOKEN-EVENT` is not retired: cold-reviewer usage is still appended explicitly by
`scripts/append-reviewer-tokens.sh`, not by a Claude Stop hook.

Legacy `SPAWN-TOKEN-EVENT`, `CONDUCTOR-TOKEN-EVENT`, and `DELEGATE-TOKEN-EVENT` lines can remain in
old run logs. They are compatibility metadata only: `account-tokens.sh` no longer rolls their token
figures up, and a usable post-hoc fragment wins every per-leg write. Narrow legacy reads may recover
an old Delegate session id, missing work-shape, or an agent-id consistency check; they never restore
the retired numeric source.

### Run-scope nonce files (`~/.novadiem/active-runs/`)

Each run owns one JSON file keyed by its munged `RUN_DIR` (every `/` and `.` becomes `-`):

```json
{"run_dir":"<absolute RUN_DIR>","nonce":"<secret>","written_at":"<ISO-8601 UTC>","project_dir":"<cwd>"}
```

There is no `baseline` or live-hook role field. `run-start.sh` preserves an existing valid nonce and
`written_at` for the same `RUN_DIR`, making the nonce write-once for the run's life. Direct-Conductor
startup echoes the file so the Conductor can copy the nonce into specialist `Run nonce:` prompt
lines. Delegate startup uses `--no-pointer-echo`; its Conductor reads the file privately. The nonce
must never be copied into `log.md` or another run artifact.

The file enables strict post-hoc specialist membership when `run_started_at` exists and its
`written_at` does not postdate that bound; otherwise aggregation explicitly degrades to legacy
first-`RUN_DIR:` membership. Keep it through close-out for pre-archive re-accounting. Archive cleanup
removes only that run's keyed file and any legacy `.delegate` sibling. Do not mass-delete active-run
files while runs may still need strict re-accounting. On resume, a missing or foreign file requires recovery of the original; do not mint a
replacement nonce and do not restore the deleted `run-reopen.sh`. Post-hoc growth re-aggregation
replaces that retired baseline-reopen ceremony.

For isolated tests, `BUREAU_POINTER_FILE` forces one exact file path; `BUREAU_POINTER_DIR` overrides
the keyed directory root:

```sh
export BUREAU_POINTER_FILE="$(mktemp -d)/run-scope"
export BUREAU_POINTER_DIR="$(mktemp -d)"
```

---

# Artifact pre-flight (`preflight-artifacts.sh`)

A read-only checker that validates artifact cross-references and embedded-snippet invariants before the Challenger spawn and at close-out.

Two phases:

- `round1` (default) — gates the Challenger spawn. Requires `spec.md` and `plan.md`; checks (a) artifact presence, (b) dangling ID cross-references in `plan.md`, (c) every FR defined in `spec.md` cited by ID in `plan.md`, (d) four forbidden snippet patterns in fenced blocks (`jq -e .` lone-dot gate, `flock`, `readarray`, `mapfile`), (f) convention-citation (idea #18): a compound structural term (store-slice / db-column / saga / … the closed set in `check_convention_citations`) immediately adjacent to a backticked concrete name in `spec.md`/`plan.md` with no `CLAUDE.md §` / `novadiem-engineering §` / `no CLAUDE.md for` citation → `convention-uncited`; a citation whose file/heading does not resolve on disk → `convention-source-missing`, and (j) target-repo ADR shape when `state.json#target_repo/docs/adr/` exists: `NNNN-slug.md`, matching `# ADR-NNNN:` heading, valid `Status:`, `Date:`, `## Context`, `## Decision`, no duplicate numbers, and valid supersession targets. Convention-citation is the one *semantic* producer gate; ADR shape is purely mechanical; the reuse-claim and numeric-consistency checks are advisory producer self-check rows only (no script block — no deterministic grammar reaches zero false positives on real specs).
- `final` — gates close-out. Adds `prompts.md` to the required set and extends checks (b) and (d) to `prompts.md`; also runs check (e): every AC defined in `spec.md` cited by ID in `plan.md` or `prompts.md`, and check (i): every prompt checkpoint declares `Seams under test:` with a named public seam or explicit `none`.

Exit-code contract:

| Exit | Meaning | Output |
|------|---------|--------|
| 0 | All checks passed | stdout: `preflight: clean` |
| 1 | One or more defects found | stdout: one report line per defect — `file:approx-line — check-id — detail` |
| 2 | Cannot run (bad args, RUN_DIR missing or unreadable) | stderr: error |

Distinct from `scripts/preflight.sh`, which checks env keys against the live environment and writes `preflight.md`. This script is read-only and writes nothing.

---

# Git worktree (`run-worktree.sh`)

Isolated checkout per execute build run. Full flow: `docs/git-worktree.md`.

```bash
# After execute-plan step 5 gate, before build
./scripts/run-worktree.sh create \
  --run-dir "$RUN_DIR" \
  --repo /path/to/target/repo \
  --base devel \
  --merge-policy end_of_job \
  --delivery auto

# During run
./scripts/run-worktree.sh status --run-dir "$RUN_DIR"

# Explicit local close-out only
./scripts/run-worktree.sh merge --run-dir "$RUN_DIR"
./scripts/run-worktree.sh remove --run-dir "$RUN_DIR"
```

| Subcommand | Purpose |
|------------|---------|
| `create` | `git worktree add` + `state.json` `git` block |
| `status` | Print `git` state + `git status -sb` in worktree |
| `sync` | Rebase bureau branch onto integration branch |
| `merge` | Merge into integration branch only when delivery resolved to local |
| `remove` | Drop worktree; delete branch if already merged |

**create flags:** `--base`, `--slug`, `--merge-policy` (`end_of_job` \| `per_prompt` \| `checkpoint`),
`--delivery` (`auto` \| `github` \| `local`), `--private-delivery` (`local` \| `github`),
`--worktree-dir` (default: `$HOME/.bureau/worktrees/REPO_BASENAME/SLUG`; override with `BUREAU_WORKTREE_ROOT` env var).

Requires **jq**. Bureau run branches use the `bureau/<slug>` prefix.

---

# GitHub pull-request delivery (`pr-delivery.sh`)

Issue-first, draft-PR-first delivery for code-changing runs. Public GitHub repositories use it by
default; private/internal repositories opt in. Full policy and evidence contract:
`docs/github-delivery.md`.

```bash
./scripts/pr-delivery.sh open \
  --run-dir "$RUN_DIR" \
  --issue-title "Describe the problem" \
  --issue-body-file "$RUN_DIR/github/issue.md" \
  --title "Implement the fix"

./scripts/pr-delivery.sh refresh --run-dir "$RUN_DIR"
./scripts/pr-delivery.sh review --run-dir "$RUN_DIR" \
  --review-summary "$RUN_DIR/github/cold-review.md" --verdict accepted
./scripts/pr-delivery.sh ready --run-dir "$RUN_DIR"
./scripts/pr-delivery.sh merge --run-dir "$RUN_DIR" --merge-method squash
```

| Subcommand | Purpose |
|---|---|
| `open` | Resolve policy, create/link issue, push branch, and open draft PR |
| `refresh` | Push commits and replace the PR body from the run evidence |
| `review` | Publish cold-review summary and optional inline comments; real collaborators may approve/request changes |
| `coauthor` | Verify a real human's exact commit trailer and record its provenance |
| `ready` | Require accepted cold review + complete evidence, then mark ready |
| `merge` | Merge through GitHub without bypassing branch protection |
| `status` | Show recorded and live GitHub delivery state |

Requires **git**, **jq**, and authenticated **gh** for GitHub mode. An `auto` policy records a
local fallback reason when GitHub is unavailable; explicit `github` policy fails closed.

---

# Gitignore enforcement (`ensure-bureau-ignored.sh`)

Idempotent helper that ensures `.bureau/runs/` and `.bureau/archive/` are in a repo's
`.gitignore` before Bureau writes there. Called by the Conductor at run start for every
new targeted run.

```bash
./scripts/ensure-bureau-ignored.sh /path/to/target/repo
```

Appends exactly `.bureau/runs/` and `.bureau/archive/` (two scoped entries) — never a blanket
`.bureau/` entry, which would silently un-track `.bureau/regression/`. Safe to run multiple
times; idempotent, no lock.

---

# Fixture promotion (`promote-fixtures.sh`)

Deterministic mechanical core of Bureau regression fixture promotion. Run at execute-plan
close-out (step 7) in the worktree, before final review and PR/local merge. Full lifecycle:
`docs/conventions/regression-fixtures.md § Regression fixture file format`. Wiring:
`workflows/execute-plan/build-tail.md` step 7.

```bash
# Dry-run first (report decisions, write nothing, run no suite):
sh scripts/promote-fixtures.sh \
  --src "$RUN_DIR/regression" \
  --repo /path/to/target/repo \
  --only slug1,slug2

# Then apply:
sh scripts/promote-fixtures.sh \
  --src "$RUN_DIR/regression" \
  --repo /path/to/target/repo \
  --only slug1,slug2 \
  --apply
```

| Arg | Type | Description |
|-----|------|-------------|
| `--src <dir>` | Required | Scratch fixture dir for this run (`RUN_DIR/regression/`). |
| `--repo <dir>` | Required | Target repo root whose `.bureau/regression/` is the promoted home. |
| `--only <slug,...>` | Optional | Comma-separated fixture slugs (without `.md`) to process. Omit to process all `NN-*.md` in `--src`. |
| `--apply` | Optional | Without it: dry-run (report decisions, write nothing, run no suite). |

| Exit code | Meaning |
|-----------|---------|
| `0` | Survivors copied and suite green (or dry-run with no clash). |
| `2` | Setup error: bad args, `--src` or `--repo` missing or not a dir, no `run.sh` in target repo. |
| `3` | Dedupe content clash (same slug, different `command:`/`expected:`) — `[CHECKPOINT]`; nothing copied past the clash; Conductor resolves. Report names every already-copied slug. |
| `4` | Suite non-green after copy; Conductor must NOT commit; investigate failing fixture. |

**Hard constraints (these never change):**
- DOES NOT mutation-test (mutation-test is an authoring-convention obligation, not a script gate).
- DOES NOT repath (repo-relative is an authoring-time guarantee per `docs/conventions/regression-fixtures.md`).
- NEVER commits (commit is a Conductor action gated on exit 0).
- NEVER pushes (delivery tooling owns the push).

---

# Cross-model pass (`model-pass.sh`)

One deterministic "improve this draft" call to a non-Claude model, for the
`write-article` workflow's cross-model stage. Routes by a provider-prefixed
`<model-spec>` (v1 ships the `openrouter:` arm only). The caller supplies everything;
the script makes no routing decisions and promotes nothing — it writes a **candidate**
out-file that the workflow's Scribe step reconciles. Full design: `plan-write-article-workflow.md §1`.

```bash
scripts/model-pass.sh \
  openrouter:x-ai/grok-4.3 \
  "$RUN_DIR/draft.md" \
  config/passes/improve-grok.md \
  "$RUN_DIR/passes/01-grok.md" \
  --run-dir "$RUN_DIR"
```

**Fail-closed:** the out-file is written ONLY when every integrity check passes — HTTP 2xx,
no `.error`, non-empty content, `finish_reason` exactly `"stop"`, and output within 50%-300%
of the input byte count. On any failure it writes nothing, errors to stderr, and exits
non-zero (the candidate is built at a temp path and `mv`'d into place only after all checks
pass, so "out-file exists" means "this candidate cleared"). Use it from a workflow action
step, never speculatively — each call spends real money on a third-party API.

| Arg | Type | Description |
|-----|------|-------------|
| `<model-spec>` | Required | Provider-prefixed model id, e.g. `openrouter:x-ai/grok-4.3`. Only `openrouter:` is routable in v1. |
| `<draft-file>` | Required | Absolute path to the draft markdown to improve (must exist, non-empty). |
| `<instruction-file>` | Required | Absolute path to the pass instruction file (must exist, non-empty). |
| `<out-file>` | Required | Absolute path for the candidate; parent dir must exist. Written only on full success. |
| `--run-dir <RUN_DIR>` | Optional | Append one `[EXTERNAL-ACTION]` audit line (model, bytes in/out, `finish_reason`, status, exit) to `RUN_DIR/log.md`. |

| Exit code | Meaning |
|-----------|---------|
| `0` | Candidate written to `<out-file>`. |
| `1` | Bad arguments or missing input files (before any network call). |
| `2` | Provider error (non-2xx HTTP, curl failure, or `.error` in the response). |
| `3` | Integrity check failed (`finish_reason` != `stop`, empty content, or length-delta out of range). |
| `4` | OpenRouter key missing (`OPENROUTER_API_KEY` absent and no valid `OPENROUTER_KEYSTORE` supplied). |

The request body is built with `jq -n` (the draft is arbitrary markdown — never
string-interpolated). The key is read from `OPENROUTER_API_KEY`, or from the optional
`OPENROUTER_KEYSTORE` file if supplied; it is never echoed.

---

# Integration gate (`integration-gate.sh`)

The **single shared integration-checkpoint gate executor** (Delegate v2, spec OQ1 / FR14).
It is the one copy of the gate logic, extracted from `watcher.sh`'s inline executor so there
is no duplicate to drift. Two callers run it: the **v2 Delegate** (manager mode) before it
spawns the cold reviewer at an integration checkpoint, and the **refactored v1 watcher**
(in place of its inline body). "The build cannot grade its own homework" (FR14): the caller,
never the Conductor/build, runs it; the canonical gate set is resolved from the project's own
runners/manifest, **never** from `claimed-gates`.

```bash
scripts/integration-gate.sh \
  --checkpoint-type integration \
  --worktree-path "$WORKTREE" \
  --base-ref devel \
  --claimed-gates '[{"name":"unit","command":"…","result":"red","pre-existing":true}]' \
  --known-flaky-gates '[]' \
  --state-json "$RUN_DIR/state.json" \
  --out "$CTX"
```

| Flag | Required | Description |
|------|----------|-------------|
| `--checkpoint-type` | yes | `integration` runs the gate; `routine` is a no-op (exit 0, no file). |
| `--worktree-path` | yes (integration) | Abs path to the build worktree, or `(none)` → short-circuit escalate. |
| `--base-ref` | yes (integration) | Git ref; unresolvable in the worktree → short-circuit escalate. |
| `--claimed-gates` | yes (integration) | Single-line inline JSON array. **Cross-check input only** (never the executed set). |
| `--known-flaky-gates` | optional | Single-line inline JSON array; demotes a named re-run red to `flaky: true`. |
| `--state-json` | yes (integration) | Abs path to `RUN_DIR/state.json` — the `#scope` projection source. |
| `--out <dir>` | yes | The caller-staged `$CTX` dir. The script **writes into it but never creates it** (the caller owns `$CTX`); it fails clearly if the dir is absent. |

- **Output:** writes `integration-results.json` into `--out` — the EVIDENCE file (`schema_version`,
  `checkpoint_type`, `escalate_marker`, `canonical_source`, `gates`, `pre_existing`,
  `under_declaration`, `scope`, `fast_forward_ok`, `conflicts_clean`, `errors`). It carries **NO
  `verdict` key** — the proceed/revise/escalate Decision is the cold reviewer's (`NN-verdict.md`).
- **Deps:** POSIX `sh` + `python3` + `git` — exactly what `watcher.sh` already required (no new dep).
- **Exit codes:** `0` results written (or routine no-op); `2` usage error (missing/unknown flag,
  `--out` absent or not a directory).
- **Callers:** the v2 Delegate (manager mode) and the refactored v1 `watcher.sh` (Phase 4).

---

# Cold reviewer dispatcher (`run-cold-reviewer.sh`)

The six-position dispatcher retains its existing `routine` and `integration` calls. An audited
Codebase Readiness Audit uses the same launcher with the closed staged packet as `CTX`:

```bash
scripts/run-cold-reviewer.sh \
  "$RUN_DIR" \
  "$RUN_DIR/audit/reviews/<attempt_id>-packet" \
  0 readiness-adapter packet.json readiness-audit
```

In `readiness-audit` mode, `packet.json`—not the three legacy checkpoint/spawn/artifact
placeholders—owns the attempt, output, question, allowlist, hashes, and corrected-audit binding.
The adapter requires a readable, valid `model-routing.json` with a supported runtime and a
nonempty `roles.challenger.model` (plus a valid Challenger reasoning effort for Codex); audited
mode has no silent routing defaults. It validates the closed staged and authoritative read set
before and after the provider, and gives the provider only that isolated packet. Claude runs from
the staged root with Read-only tools, no settings, and no session
persistence. Codex runs ephemerally from a read-only packet copy with network disabled and
explicit denies for the live run, original packet, target repository, Bureau framework, home and
session/configuration stores, and any supplied unstaged sentinel.

The adapter exclusively reserves `audit/reviews/<attempt_id>-result/`, validates and atomically
publishes the provider's exact six-field candidate as `<output_id>.json`, reopens and fully
revalidates those immutable published bytes, derives the standard Challenger verdict only from
that reopened candidate, and atomically publishes `verdicts/<attempt_id>.json`. Any malformed
packet, changed binding, result or verdict collision, provider mismatch, or partial attempt fails
closed. It never deletes, repairs, reuses, or overwrites readiness output; retry with a freshly
staged packet and a new attempt identity.

---

# Revision cap (`revise-cap.sh`)

Deterministic revision-cap enforcement (Delegate v2, spec W-c / FR11 / AC15). On a `revise`
verdict the Delegate calls this one-shot; it atomically increments the single authoritative
counter (`delegate-state.json#revise_counts[NN]`) and emits the cap decision. The Delegate acts
on this stdout, never on its own cap inference — restoring v1 `verdict-write.sh`'s hard cap as a
**script guarantee**, not a model instruction.

```bash
scripts/revise-cap.sh "$RUN_DIR/delegate-state.json" 05 2
# stdout: "revise" (under cap) | "escalate" (new count >= cap)
```

| Arg | Required | Description |
|-----|----------|-------------|
| `<delegate-state.json-path>` | yes | Abs path to the per-run `delegate-state.json`. |
| `<NN>` | yes | Zero-padded checkpoint ordinal (the `revise_counts` key). |
| `<cap>` | yes | Integer cap (default policy: 2). |

- **Output:** `revise` or `escalate` to stdout; the file's `revise_counts[NN]` is incremented and
  written atomically (`.tmp` → `os.replace`, so concurrent calls cannot corrupt the JSON).
- **Deps:** POSIX `sh` + `python3`.
- **Exit codes:** `0` success; `1` any error (file not found, invalid JSON, non-integer cap, write
  failure).
- **Caller:** the v2 Delegate (manager mode), on a `revise` verdict.

---

# Ledger `Robin's call:` set (`ledger-set-robins-call.sh`)

Deterministic `Robin's call:` population on an escalation resolution (Delegate v2, spec W6 / AC14).
The model never hand-edits the append-only ledger (`delegate-decisions.md`): this one-shot locates
the blank `Robin's call:` line for record `NN` and fills only that line, touching nothing else — so
the append-only invariant stays a **script guarantee**. `ledger-append.sh` is untouched.

```bash
LEDGER_FILE="$RUN_DIR/delegate-decisions.md" \
  scripts/ledger-set-robins-call.sh 05 "approved as-is"
```

- **Inputs:** `<NN>` (checkpoint ordinal) + `"<literal value>"`. Among `NN`'s § 9 records
  (`## NN.<attempt> — <timestamp>`) it targets the one whose `decision:` is `escalate` —
  `Robin's call:` only ever resolves an escalation, and `revise` records carry a blank field that
  stays blank (so `NN` alone is ambiguous on the revise→escalate cap path). The ledger path
  resolves from `$LEDGER_FILE` (preferred) else `$RUN_DIR/delegate-decisions.md`.
- **Output:** that escalate record's blank `Robin's call:` line is filled (atomic `.tmp` →
  `os.replace`; every other byte preserved). Refuses to overwrite an already-filled field, and
  refuses if there is no unresolved escalation record for `NN`.
- **Deps:** POSIX `sh` + `python3`.
- **Exit codes:** `0` filled; `1` any error (no unresolved escalation for `NN`, already filled, bad
  args, write failure, or neither `$LEDGER_FILE` nor `$RUN_DIR` set).
- **Caller:** the v2 Delegate (manager mode), on an escalation resolution.

---

## ChatGPT flat export

`sync-chatgpt-export.sh` copies canon visual docs + locked `reference/` assets into
`../chatgpt-export/` (flat directory for ChatGPT and similar upload UIs).

```bash
./scripts/sync-chatgpt-export.sh
ls ../chatgpt-export/
```

Run after editing `LORE.md`, `VISUAL-CANON.md`, `VISUAL-SYSTEM.md`, or adding a locked
reference image. Full manifest: `reference/README.md` (copied flat as `UPLOAD-INDEX.md`).
