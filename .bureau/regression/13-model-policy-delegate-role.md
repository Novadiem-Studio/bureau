name: Bundle 09 — model-policy delegate role well-formed
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  jq -e '.roles.delegate | (.default_tier=="strong") and (.allowed==["standard","strong","frontier","escalated"]) and (.escalate_when|length==9) and (has("deescalate_when")|not) and (.cold_reviewer.rule=="capable_tier_fresh_context") and (.cold_reviewer.tier=="strong") and ((.cold_reviewer|has("author_strong"))|not)' "$ROOT/config/model-policy.v2.json"
expected: exit 0 — jq prints true; nonzero/false if the delegate role entry drifts (tier, allowed set, escalate count, the ABSENCE of deescalate_when, or the cold_reviewer rule/tier). The allowed set is the four-tier form from 8f57bc1 (frontier/escalated opened to Delegate and Scribe, 2026-09-09); the Bundle 09 two-tier form is superseded. The deescalate slug is author_ran_strong and the cold_reviewer rule is differs_from_author (Robin, 2026-09-16, issue #50); the former bundle04_benchmark_replay_clean gate is retired.
phase: model policy — cold review is bought by fresh context (issue #60)
owner: prompts.md Prompt 5 (config/model-policy.v2.json); issue #50
