# Model tier experiments

Small JSON files that **override** role tiers from `config/model-policy.json` when their
`activate_when` conditions match the usage snapshot, or when you force them on.

## How activation works

| Mechanism | Example |
|-----------|---------|
| **Auto** | `sonnet-burn.json` — designed to fire when `claude.sonnetBurnMode: true`, but `sonnetBurnMode` is always `false` from the statusLine source (Sonnet metering not exposed via `rate_limits`). **Auto-trigger is inactive; activate manually if needed.** |
| **Manual env** | `NOVADIEM_MODEL_EXPERIMENTS=systemsmith-sonnet` |
| **Policy file** | Add experiment id to `manual_experiments` in `model-policy.json` |

Resolve before each run:

```bash
./scripts/resolve-model-tiers.sh
jq '.roles' ~/.novadiem/resolved-model-tiers.json
```

## Rules

- **Only Challenger is locked** (always opus). All other roles accept experiment overrides within `allowed`.
- **Claude Code: haiku, sonnet, and opus** — `premium` / Fable experiments are **disabled** (`disabled: true`). Haiku is locked to Scoot.
- Overrides must use a tier in the role's `allowed` array — invalid overrides fall back to default.
- Log active experiments and tier per spawn in `RUN_DIR/log.md`.
- Copy resolved tiers to `RUN_DIR/model-tiers.json` at run start.

## Example experiments

| Id | Trigger | Effect |
|----|---------|--------|
| `sonnet-burn` | `sonnetBurnMode` (auto-trigger **inactive** — manual only; see above) | Utility roles → sonnet; spawn don't inline |
| `conductor-sonnet` | manual | Main session → sonnet (strict routing) |
| `systemsmith-sonnet` | manual | Systemsmith → sonnet |
| ~~`weekly-fable-build`~~ | — | **disabled** |
| ~~`architect-fable` / `mage-fable`~~ | — | **disabled** |

## Adding an experiment

1. Copy an existing file; set unique `id`.
2. `activate_when` keys (all optional, ANDed):
   - `sonnetBurnMode: true`
   - `weeklyUsedPercent_gte: 85`
   - `sessionUsedPercent_gte: 90`
   - `manual_only: true` — only via env / `manual_experiments`
3. `overrides`: role key → tier (`sonnet` or `opus` on Claude Code).
4. `conductor_notes`: strings the Conductor should log when this experiment is active.

```bash
# Conductor on sonnet, utility burn when snapshot says so
NOVADIEM_MODEL_EXPERIMENTS=conductor-sonnet,sonnet-burn ./scripts/resolve-model-tiers.sh
```

## Role keys

`conductor`, `challenger`, `architect`, `mage`, `analyst`, `cleric`, `spellwright`, `counselor`, `systemsmith`, `mechanic`, `witness`, `coupler`, `tally`, `scoot`
