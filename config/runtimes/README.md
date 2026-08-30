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

For a new run, prefer the opening ceremony so the runtime is captured from the
start:

```bash
scripts/run-start.sh "$RUN_DIR" --target "$TARGET_REPO" --workflow "$WORKFLOW" \
  --slug "$SLUG" --runtime openai --no-pointer-echo
```

`openai` means the Codex host adapter; `codex` is accepted as an alias by
`run-start.sh`. Claude remains the default when `--runtime` is omitted. Host
spawn/resume mappings and accounting guarantees live in `docs/host-runtime.md`.

`grok` is the Grok Bot host adapter (`config/runtimes/grok.json`, `GROK.md`).
Start with `--runtime grok`. Live spawn is Task/executor; `scripts/run-grok-specialist.sh --plan`
is the pre-spawn audit. `openrouter` and `hermes` remain routing-only.

Base tiers resolve native spawn models. Optional `execution_profiles` resolve narrow alternate
transports without changing a role's default tier. In the OpenAI adapter,
`granular-ui-fast` maps a qualifying first-pass Mage prompt to Spark/high through
`scripts/run-codex-spark-specialist.sh`; all normal spawns and every fallback continue to use the
resolved Terra/Sol role route. Profile eligibility lives in `config/model-policy.v2.json`, not in
the adapter.

## Local Aliases

Canonical adapters may use symbolic model aliases when exact provider names are likely to drift.
Hermes or Mission Control can translate those aliases to real provider IDs at dispatch time.

## Fresh Context

Fresh context is tracked separately from model strength. If a runtime cannot guarantee a fresh
context for a role that requires it, the resolver emits a capability warning and the Conductor
must log the review/build as downgraded.
