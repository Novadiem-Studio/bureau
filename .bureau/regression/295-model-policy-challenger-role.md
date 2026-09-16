name: model-policy challenger role — standard allowed, author_ran_strong deescalate, no final_gate / high_stakes escalation triggers
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  jq -e '.roles.challenger | (.default_tier=="strong") and (.allowed==["standard","strong","frontier","escalated"]) and (.escalate_when==["second_critic_loop","prior_review_missed_issue"]) and ((.deescalate_when|index("author_ran_strong")) != null) and ((.escalate_when|index("final_gate")) == null) and ((.escalate_when|index("high_stakes_backend_or_security")) == null)' "$ROOT/config/model-policy.v2.json"
expected: exit 0 — jq prints true; nonzero/false if the Challenger role drifts: default tier, the four-tier allowed set with standard (Robin, 2026-09-16), the two remaining escalation triggers, the author_ran_strong deescalate slug, or the return of final_gate / high_stakes_backend_or_security as escalation triggers. Mutation: re-add "final_gate" to escalate_when → false.
phase: model policy — reviewer differs from author (issue #55)
owner: config/model-policy.v2.json roles.challenger; docs/model-routing-and-cast.md § Escalation ladder
