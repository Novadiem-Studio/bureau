# Provider-Neutral Model Experiments

These experiments override tiers in `config/model-policy.v2.json`.

They use provider-neutral tier names only:

- `cheap`
- `standard`
- `strong`
- `frontier`
- `escalated`

Activate manually with:

```bash
NOVADIEM_MODEL_EXPERIMENTS=challenger-frontier-final-gate ./scripts/resolve-model-routing.sh
```

or add ids to `manual_experiments` in `config/model-policy.v2.json`.

Legacy Claude experiments live in `config/experiments/` and are still used by
`scripts/resolve-model-tiers.sh`; do not mix their `sonnet` / `opus` / `premium` tiers into this
v2 experiment folder.
