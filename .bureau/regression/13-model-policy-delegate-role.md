name: Bundle 09 — model-policy delegate role well-formed
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  jq -e '.roles.delegate | (.default_tier=="strong") and (.allowed==["standard","strong","frontier","escalated"]) and (.escalate_when|length==9) and (.deescalate_when|length==1) and (.deescalate_when[0]=="bundle04_benchmark_replay_clean")' $ROOT/config/model-policy.v2.json
expected: exit 0 — jq prints true; nonzero/false if the delegate role entry drifts (tier, allowed set, escalate count, or the single deescalate slug). The allowed set is the four-tier form from 8f57bc1 (frontier/escalated opened to Delegate and Scribe, 2026-09-09); the Bundle 09 two-tier form is superseded.
phase: 05 · execute-plan
owner: prompts.md Prompt 5 (config/model-policy.v2.json)
