name: critic-blocker-summary-field-documented (D2 — critic.md documents the summary field on blockers)
phase: bug-fix · 20260903-framework-tooling-gaps
owner: agents/critic.md — blocker schema documents summary field (D2 2026-09-03)
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  strip() { grep -v '^[[:space:]]*#' "$1"; }
  # critic.md must mention the "summary" field in the verdict/blocker schema section
  strip "$ROOT/agents/critic.md" | grep -qF '"summary"' \
    || { echo 'FAIL: agents/critic.md does not document the summary field on blockers'; exit 1; }
  # The field must appear near id and citation to be in the blocker schema context
  strip "$ROOT/agents/critic.md" | grep -qF '"id"' \
    || { echo 'FAIL: agents/critic.md does not document the id field (sanity check)'; exit 1; }
  echo "PASS"
  # Mutation note: delete the line containing '"summary"' from agents/critic.md
  # verdict-authoring section. The grep-qF check fails and the fixture exits 1.
expected: PASS
