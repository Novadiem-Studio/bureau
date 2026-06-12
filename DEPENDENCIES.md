# External dependencies

The framework is self-contained in `agents/`, `workflows/`, and `templates/`. A few
**external skills** and project files extend it. None are required for the default
`feature` workflow on a greenfield project.

## Project files

| File | Required? | Fallback if missing |
|------|-----------|---------------------|
| `project-context.md` (project root) | Recommended | Conductor asks for mode, stack, and constraints at start |
| Target repo `CLAUDE.md` / skills | Existing-project mode | Conductor builds a minimal workspace map in `RUN_DIR/workspace-map.md` |

## Skills

| Skill | Used by | Required? | Fallback |
|-------|---------|-----------|----------|
| **define-workflow** | Conductor, when no workflow in `workflows/index.md` fits | Optional | Conductor drafts a one-off sequence in `log.md` and flags it for promotion to `workflows/` |
| **humanizer** | The Counselor (`copy-review`, `message-framing`) | Optional for non-copy workflows | Counselor applies the short voice rules in `agents/voice.md` only |
| **spiral-dynamics** | The Counselor (`copy-review`, `message-framing`) | Optional | Counselor skips audience vMEME classification; uses plain-language audience notes |
| **monorepo-orientation** | `execute-plan` step 1 (Architect) in multi-repo workspaces | Required for that workflow in monorepos | Architect reads `project-context.md` Workspace Map and target `CLAUDE.md` files manually |
| Per-sub-app skills (`auth`, `redux`, `docker`, …) | Build party during `execute-plan` | As named in each prompt | Spellwright must embed gotchas in the prompt; Mechanic follows the plan's runbook |

## Runtime tools

| Tool | Used by | Notes |
|------|---------|-------|
| **Agent** (subagent spawn) | Conductor | Map model **tiers** from `agents/orchestrator.md` to the runtime's model ids |
| **Claude Design** (human step) | Visionary + The Cleric | No API — `[DESIGN HANDOFF]` checkpoint; export lands in `RUN_DIR/design/handoff/` |
| **CodexBar** + usage poller | Conductor (budget hints) | Optional. Install: `scripts/install-usage-poller.sh`. Reads `~/.novadiem/usage-snapshot.json` — do not call `codexbar usage` per spawn |

## Usage poller (optional)

Keeps Claude quota fresh without blocking the Conductor on OAuth fetches (~15–30s each).

```bash
# One-time install (macOS launchd, every 5 min)
./scripts/install-usage-poller.sh

# Or manual refresh
./scripts/poll-usage-snapshot.sh
cat ~/.novadiem/usage-snapshot.json | jq '.claude'
```

Requires **CodexBar** (`brew` or upstream) and **jq**. Snapshot path: `NOVADIEM_USAGE_SNAPSHOT_PATH`.
Do not use `~/Library/Caches/CodexBar/cost-usage/*.json` for quotas — that is historical cost, not live limits.

Full install, schema, and ops: **`scripts/README.md`**. Per-role tier experiments:
**`config/experiments/README.md`** + `scripts/resolve-model-tiers.sh`.

## Adding a dependency

If a workflow or persona starts requiring a new skill:

1. Document it here (required vs optional, fallback).
2. Name it in the workflow file under **Leans on skills**.
3. Add a lint-friendly reference in `agents/orchestrator.md` if the Conductor must load it at triage.
