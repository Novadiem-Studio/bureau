# Runtime Adapters

Runtime adapters map provider-neutral tiers from `config/model-policy.v2.json` to the model
settings available in a specific host.

The framework should reason in tiers (`cheap`, `standard`, `strong`, `frontier`, `escalated`),
not in vendor model names. Adapters are the only place model IDs, reasoning-effort knobs, and
provider capability details belong.

Resolve a run with:

```bash
NOVADIEM_MODEL_RUNTIME=openai ./scripts/resolve-model-routing.sh
```

Then copy `~/.novadiem/resolved-model-routing.json` into the run directory as
`RUN_DIR/model-routing.json`.

## Local Aliases

Canonical adapters may use symbolic model aliases when exact provider names are likely to drift.
Hermes or Mission Control can translate those aliases to real provider IDs at dispatch time.

## Fresh Context

Fresh context is tracked separately from model strength. If a runtime cannot guarantee a fresh
context for a role that requires it, the resolver emits a capability warning and the Conductor
must log the review/build as downgraded.
