# Usage snapshot poller

Background job that polls [CodexBar](https://github.com) for live Claude quota and writes a
shared JSON file. The Conductor reads that file at phase boundaries instead of running
`codexbar usage` on every spawn (~15–30s OAuth fetch each time).

## Quick start (macOS)

```bash
# From the canonical agent-framework copy (or any install)
./scripts/install-usage-poller.sh

# Verify
jq '.claude' ~/.novadiem/usage-snapshot.json
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
| `NOVADIEM_USAGE_LOG_DIR` | `~/.novadiem/logs` | launchd stdout/stderr (install only) |
| `CODEXBAR_BIN` | `codexbar` on PATH, else `/usr/local/bin/codexbar` | CodexBar binary |

## Snapshot schema

```json
{
  "polledAt": "2026-06-12T05:31:23Z",
  "source": "codexbar",
  "ok": true,
  "providersRequested": "claude",
  "providers": [ /* raw CodexBar array */ ],
  "claude": {
    "loginMethod": "Claude Max",
    "updatedAt": "2026-06-12T05:31:24Z",
    "sessionUsedPercent": 0,
    "sessionWindowMinutes": 300,
    "weeklyUsedPercent": 62,
    "weeklyResetsAt": "2026-06-16T19:59:59Z",
    "weeklyResetDescription": "Jun 16 at 12:59PM",
    "monthlyUsedPercent": 4,
    "monthlyResetsAt": "2026-06-16T20:00:00Z"
  }
}
```

On failure, `ok` is `false`, `error` holds the CodexBar stderr, and `claude` is `null`.

**Stale:** treat as stale if `polledAt` is older than ~10 minutes or `ok` is false.

## What not to use

`~/Library/Caches/CodexBar/cost-usage/*.json` is **historical cost** from JSONL scans — not
live quota percentages. Always use the poller snapshot or a direct `codexbar usage` call.

## Conductor behavior

1. Read snapshot at **run start** and before **premium** or **escalated** spawns.
2. Log budget notes in `RUN_DIR/log.md` — do not re-run CodexBar during the run.
3. Conductor and Challenger stay on **opus** regardless of quota; hints only affect optional
   premium work and utility spawns.

Thresholds (from `agents/orchestrator.md`):

- `sessionUsedPercent` ≥ 90 — session cap risk; pause optional premium spawns.
- `weeklyUsedPercent` ≥ 85 — prefer sonnet for new utility spawns; defer non-critical premium.

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
