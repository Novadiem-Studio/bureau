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

Wire it in `~/.claude/settings.json`:

```json
{
  "statusLine": "/Users/robin/Code/novadiem/bureau/scripts/statusline-usage.sh"
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

Thresholds (from `agents/orchestrator.md`):

- `sonnetBurnMode` — always `false` from this source; the legacy sonnet-burn auto-trigger is
  inactive. Use manual experiments such as `budget-pressure-standardize` instead.
- `sessionUsedPercent` ≥ 90 — session cap risk.
- `weeklyUsedPercent` ≥ 85 — defer non-critical frontier/escalated work.

---

# Git worktree (`run-worktree.sh`)

Isolated checkout per execute build run. Full flow: `docs/git-worktree.md`.

```bash
# After execute-plan step 5 gate, before build
./scripts/run-worktree.sh create \
  --run-dir "$RUN_DIR" \
  --repo /path/to/target/repo \
  --base devel \
  --merge-policy end_of_job

# During run
./scripts/run-worktree.sh status --run-dir "$RUN_DIR"

# Close-out (end_of_job policy)
./scripts/run-worktree.sh merge --run-dir "$RUN_DIR"
./scripts/run-worktree.sh remove --run-dir "$RUN_DIR"
```

| Subcommand | Purpose |
|------------|---------|
| `create` | `git worktree add` + `state.json` `git` block |
| `status` | Print `git` state + `git status -sb` in worktree |
| `sync` | Rebase bureau branch onto integration branch |
| `merge` | Merge bureau branch into integration branch (in repo root) |
| `remove` | Drop worktree; delete branch if already merged |

**create flags:** `--base`, `--slug`, `--merge-policy` (`end_of_job` \| `per_prompt` \| `checkpoint`),
`--worktree-dir` (default: `$HOME/.bureau/worktrees/REPO_BASENAME/SLUG`; override with `BUREAU_WORKTREE_ROOT` env var).

Requires **jq**. Bureau run branches use the `bureau/<slug>` prefix.

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
close-out (step 7) after the integration branch merge, before the commit. Full lifecycle:
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
- NEVER pushes (push is past the production boundary; always the human's call).

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
| `4` | Keystore key missing (`~/Documents/novadiem/keys/novadiem/openrouter.env` absent or `OPENROUTER_API_KEY` empty). |

The request body is built with `jq -n` (the draft is arbitrary markdown — never
string-interpolated). The key is sourced from the keystore; it is never echoed.

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
