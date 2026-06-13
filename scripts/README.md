# Usage snapshot poller

Background job that polls [CodexBar](https://github.com) for live Claude quota and writes a
shared JSON file. The Conductor reads that file at phase boundaries instead of running
`codexbar usage` on every spawn (~15–30s OAuth fetch each time).

## Quick start (macOS)

```bash
# From the canonical agent-framework copy (or any install)
./scripts/install-usage-poller.sh

# Verify
jq '{sonnetLeft: .claude.sonnetLeftPercent, burnMode: .claude.sonnetBurnMode, weeklyLeft: .claude.weeklyLeftPercent}' ~/.novadiem/usage-snapshot.json
```

Installs a **launchd** agent (`com.novadiem.usage-snapshot`) that runs every **5 minutes**
and once at login.

## Files

| File | Role |
|------|------|
| `poll-usage-snapshot.sh` | Fetch usage, write snapshot (callable manually or from launchd) |
| `install-usage-poller.sh` | Copy plist to `~/Library/LaunchAgents/`, load agent, run once |
| `com.novadiem.usage-snapshot.plist` | Template plist (`__POLL_SCRIPT__` / `__LOG_DIR__` substituted on install) |

## Snapshot location

Default: `~/.novadiem/usage-snapshot.json`

Override with `NOVADIEM_USAGE_SNAPSHOT_PATH`. The Conductor documents read rules in
`agents/orchestrator.md` § Usage snapshot (CodexBar).

## Environment variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `NOVADIEM_USAGE_SNAPSHOT_PATH` | `~/.novadiem/usage-snapshot.json` | Where to write the snapshot |
| `NOVADIEM_USAGE_PROVIDERS` | `claude` | Passed to `codexbar usage --provider` |
| `NOVADIEM_USAGE_INCLUDE_JSON` | `0` | Set `1` for extra raw JSON fetch (second OAuth call) |
| `NOVADIEM_USAGE_LOG_DIR` | `~/.novadiem/logs` | launchd stdout/stderr (install only) |
| `CODEXBAR_BIN` | `codexbar` on PATH, else `/usr/local/bin/codexbar` | CodexBar binary |

## Snapshot schema

Poller uses **one** CodexBar text call (matches the GUI). Sonnet and pace lines are not in JSON.

```json
{
  "polledAt": "2026-06-12T05:31:23Z",
  "source": "codexbar",
  "ok": true,
  "providersRequested": "claude",
  "providers": [],
  "claude": {
    "loginMethod": "Claude Max",
    "sessionLeftPercent": 100,
    "sessionUsedPercent": 0,
    "weeklyLeftPercent": 38,
    "weeklyUsedPercent": 62,
    "weeklyResetsIn": "4d 14h",
    "weeklyPaceDeficitPercent": 28,
    "weeklyRunsOutIn": "1d 11h",
    "sonnetLeftPercent": 96,
    "sonnetUsedPercent": 4,
    "sonnetResetsIn": "4d 14h",
    "sonnetBurnTargetLeftPercent": 25,
    "sonnetBurnMode": true
  }
}
```

`sonnetBurnMode` is `true` while `sonnetLeftPercent` > 25. Legacy Claude runs use it to route
aggressively to sonnet spawns; v2 provider-neutral routing should prefer explicit experiments such
as `budget-pressure-standardize`.

Set `NOVADIEM_USAGE_INCLUDE_JSON=1` for a second OAuth call that also stores raw `providers`.

On failure, `ok` is `false`, `error` holds the CodexBar stderr, and `claude` is `null`.

**Stale:** treat as stale if `polledAt` is older than ~10 minutes or `ok` is false.

## What not to use

`~/Library/Caches/CodexBar/cost-usage/*.json` is **historical cost** from JSONL scans — not
live quota percentages. **Designs / Daily Routines** bars in the GUI are often vestigial (design
folded into general pool ~May 2026). Ignore them for routing.

## Conductor behavior

1. Read snapshot at **run start** and before expensive (`frontier` / `escalated`) spawns.
2. Log budget notes in `RUN_DIR/log.md` — do not re-run CodexBar during the run.
3. **Model routing:** run `scripts/resolve-model-routing.sh` — see `config/runtimes/README.md`
   and `config/model-experiments/README.md`.
4. Legacy Claude-only runs may still use `scripts/resolve-model-tiers.sh` and
   `config/experiments/README.md` until migrated.

Thresholds (from `agents/orchestrator.md`):

- `sonnetBurnMode` — legacy Claude signal; in v2 routing, prefer provider-neutral experiments such
  as `budget-pressure-standardize`.
- `sessionUsedPercent` ≥ 90 — session cap risk.
- `weeklyUsedPercent` ≥ 85 — defer non-critical frontier/escalated work.
- `weeklyRunsOutIn` before reset — weekly pace deficit; don't ignore while routing cheaper work.

## Operations

```bash
# Manual refresh
./scripts/poll-usage-snapshot.sh

# Poller logs
tail -f ~/.novadiem/logs/usage-poller.err

# Stop background poller
launchctl unload ~/Library/LaunchAgents/com.novadiem.usage-snapshot.plist

# Restart
launchctl load ~/Library/LaunchAgents/com.novadiem.usage-snapshot.plist
```

## Requirements

- **CodexBar** installed and authenticated for Claude (OAuth).
- **jq** (`brew install jq`).
- **macOS launchd** for `install-usage-poller.sh`. On Linux, use cron:

  ```cron
  */5 * * * * /path/to/agent-framework/scripts/poll-usage-snapshot.sh
  ```

## Alternative: CodexBar serve

`codexbar serve` exposes `GET http://127.0.0.1:8080/usage?provider=claude` with a ~60s cache.
This poller uses the CLI directly so it works without a long-lived serve process. If serve is
already running, you could point a thin wrapper at the HTTP endpoint instead — not shipped here.

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
| `sync` | Rebase society branch onto integration branch |
| `merge` | Merge society branch into integration branch (in repo root) |
| `remove` | Drop worktree; delete branch if already merged |

**create flags:** `--base`, `--slug`, `--merge-policy` (`end_of_job` \| `per_prompt` \| `checkpoint`),
`--worktree-dir` (default: `REPO/.society-worktrees/SLUG`).

Requires **jq**. Society branch naming: `society/<slug>`.
