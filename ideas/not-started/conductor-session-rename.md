# Conductor: auto-rename session to run slug

When the Conductor creates a new run dir, it should immediately rename the Claude Code
session to match the slug (e.g. `20260620-some-task`) so the session list stays navigable
without manual `/rename` calls.

## How it works

`~/.claude/sessions/$PPID.json` holds the session metadata for the current Claude Code
process. It has a `"name"` field — the same field `/rename` writes to. Writing to it
renames the session live.

`$PPID` in a Bash tool call is the PID of the Claude Code process that spawned the shell.

One-liner:

```bash
python3 -c "
import json, os, sys
p = os.path.expanduser('~/.claude/sessions/' + sys.argv[1] + '.json')
d = json.load(open(p)); d['name'] = sys.argv[2]; open(p, 'w').write(json.dumps(d))
" $PPID "<slug>" 2>/dev/null || true
```

The `|| true` makes it a no-op in non-interactive / headless contexts where the session
file may not exist.

## Where to add it

`agents/orchestrator.md` — "Run directory" section (~line 664), right after the sentence
about creating the run dir and initializing `state.json` and `log.md`. One new step:
once the `<yyyymmdd>-<task-slug>` is determined, run the rename one-liner.

`CLAUDE.md` step 4 already points at orchestrator.md for this sequence — no change needed
there.

## Verified

Tested in session `0ed16fdb` (2026-06-20): wrote `"name": "conductor-rename-test"` to the
file and it updated the session label immediately; restored to `"intake-followups"`.
