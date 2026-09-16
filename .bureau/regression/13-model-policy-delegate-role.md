name: Bundle 09 — model-policy delegate role well-formed
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  jq -e '.roles.delegate | (.default_tier=="strong") and (.allowed==["standard","strong","frontier","escalated"]) and (.escalate_when|length==9) and (.deescalate_when==["author_ran_strong"]) and (.cold_reviewer.rule=="differs_from_author") and (.cold_reviewer.author_cheap=="standard") and (.cold_reviewer.author_standard=="strong") and (.cold_reviewer.author_strong=="standard") and (.cold_reviewer.author_frontier=="strong") and (.cold_reviewer.author_escalated=="strong")' $ROOT/config/model-policy.v2.json
expected: exit 0 — jq prints true; nonzero/false if the delegate role entry drifts (tier, allowed set, escalate count, the single deescalate slug, or the cold_reviewer rule). The allowed set is the four-tier form from 8f57bc1 (frontier/escalated opened to Delegate and Scribe, 2026-09-09); the Bundle 09 two-tier form is superseded. The deescalate slug is author_ran_strong and the cold_reviewer rule is differs_from_author (Robin, 2026-09-16, issue #50); the former bundle04_benchmark_replay_clean gate is retired.
phase: 05 · execute-plan
owner: prompts.md Prompt 5 (config/model-policy.v2.json); issue #50
