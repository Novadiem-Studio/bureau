name: model-policy challenger role — floor is strong (no standard, no deescalate), no final_gate / high_stakes escalation triggers
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  jq -e '.roles.challenger | (.default_tier=="strong") and (.allowed==["strong","frontier","escalated"]) and (.escalate_when==["second_critic_loop","prior_review_missed_issue"]) and (.deescalate_when==[]) and ((.escalate_when|index("final_gate")) == null) and ((.escalate_when|index("high_stakes_backend_or_security")) == null)' "$ROOT/config/model-policy.v2.json"
expected: exit 0 — jq prints true; nonzero/false if the Challenger role drifts: default tier, the three-tier allowed set with strong as its floor (Robin, 2026-11-09, issue #133: the Challenger never runs on Sonnet, even under quota pressure; this replaces the 2026-09-16 four-tier set that included standard), an empty deescalate_when, the two remaining escalation triggers, or the return of final_gate / high_stakes_backend_or_security as escalation triggers. Mutation: re-add "standard" to allowed → false; re-add "final_gate" to escalate_when → false.
phase: model policy — cold review is bought by fresh context on a capable tier (issues #60, #133)
owner: config/model-policy.v2.json roles.challenger; docs/model-routing-and-cast.md § Escalation ladder
