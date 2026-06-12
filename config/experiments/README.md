# Model tier experiments

Small JSON files that **override** role tiers from `config/model-policy.json` when their
`activate_when` conditions match the usage snapshot, or when you force them on.

## How activation works

| Mechanism | Example |
|-----------|---------|
| **Auto** | `sonnet-burn.json` — fires when `~/.novadiem/usage-snapshot.json` has `claude.sonnetBurnMode: true` |
| **Manual env** | `NOVADIEM_MODEL_EXPERIMENTS=systemsmith-sonnet` |
| **Policy file** | Add experiment id to `manual_experiments` in `model-policy.json` |

Resolve before each run:

```bash
./scripts/resolve-model-tiers.sh
jq '.roles' ~/.novadiem/resolved-model-tiers.json
```

## Rules

- **Only Challenger is locked** (always opus). All other roles accept experiment overrides within `allowed`.
- Overrides must use a tier in the role's `allowed` array — invalid overrides fall back to default.
- **`premium`** maps to **fable** at spawn time (`claude-fable-5` in Claude Code).
- Log active experiments and tier per spawn in `RUN_DIR/log.md`.
- Copy resolved tiers to `RUN_DIR/model-tiers.json` at run start.

## Example experiments

| Id | Trigger | Effect |
|----|---------|--------|
| `sonnet-burn` | `sonnetBurnMode` | Utility roles → sonnet; spawn don't inline |
| `weekly-fable-build` | weekly ≥ 70% used | Architect + Mage → premium (fable) |
| `architect-fable` | manual | Architect → premium |
| `mage-fable` | manual | Mage → premium |
| `build-party-fable` | manual | Architect + Mage → premium |
| `conductor-sonnet` | manual | Main session → sonnet (strict routing) |
| `systemsmith-sonnet` | manual | Systemsmith → sonnet |

```bash
# Fable build party for one run
NOVADIEM_MODEL_EXPERIMENTS=build-party-fable ./scripts/resolve-model-tiers.sh

# Conductor on sonnet, everything else default/experiments
NOVADIEM_MODEL_EXPERIMENTS=conductor-sonnet,sonnet-burn ./scripts/resolve-model-tiers.sh
```

## Adding an experiment

1. Copy an existing file; set unique `id`.
2. `activate_when` keys (all optional, ANDed):
   - `sonnetBurnMode: true`
   - `weeklyUsedPercent_gte: 85`
   - `sessionUsedPercent_gte: 90`
   - `manual_only: true` — only via env / `manual_experiments`
3. `overrides`: role key → tier (`sonnet`, `premium`, `opus`, `escalated`).
4. `conductor_notes`: strings the Conductor should log when this experiment is active.

## Role keys

`conductor`, `challenger`, `architect`, `mage`, `analyst`, `cleric`, `spellwright`, `counselor`, `systemsmith`, `mechanic`
