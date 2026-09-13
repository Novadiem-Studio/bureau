# Run-series campaign kit

Copy these three files next to a plan (or in the plan’s parent) when starting a
new series. The Envoy looks them up via `scripts/run-series-resolve.sh`.

A plan is a directory with `INDEX.md` and one card per run. The first live
instance is rheo-stream’s
`rheo-stream-workspace/private/agent-context/build-plan/` — charter, live
state, and HANDOFF sit in the parent `agent-context/` directory.

| File | Job |
|------|-----|
| `SUPERVISOR.md` | Campaign charter: authority + escalation + external-action gates |
| `SUPERVISOR-STATE.md` | Live watch surface. Keep it short. Read each tick; do not grow a novel. |
| `HANDOFF.md` | Cross-run baton and retired tick history |

Do not invent a fourth book. Run cards and INDEX stay in the plan dir.
INDEX may have a second table for evaluation / A/B gates; the Envoy reads
both and does not launch that track until Robin says tokens can be spared.
Meanwhile it only **marks** replay bases (merge SHA, optional
`eval/<gate>-base` branch). Later trials check that tree out, get the same
task, and compare; they do not replay the Bureau conversation.

The Envoy does not become the Delegate for the campaign; it launches each
run as its own Delegate session (`docs/supervisor-spawned-runs.md`).
