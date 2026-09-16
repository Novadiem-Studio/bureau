name: every role's tier agrees across policy, the cast table, and its agent file
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  python3 - "$ROOT" <<'PY'
  import json, re, os, sys
  root = sys.argv[1]
  policy = json.load(open(f"{root}/config/model-policy.v2.json"))["roles"]
  cast = open(f"{root}/docs/model-routing-and-cast.md").read()
  rows = {m.group(2): m.group(3) for m in re.finditer(
      r'^\|\s*\*\*([^*]+)\*\*[^|]*\|\s*`(agents/[\w-]+\.md)`\s*\|\s*([a-z]+)\s*\|', cast, re.M)}
  # Conductor is deliberately absent: agents/orchestrator.md defers to
  # roles.conductor.tier at runtime rather than naming a tier of its own.
  alias = {
      "analyst": "agents/analyst.md", "architect": "agents/architect.md",
      "challenger": "agents/critic.md", "cleric": "agents/designer.md",
      "counselor": "agents/voice.md", "delegate": "agents/delegate.md",
      "mage": "agents/frontend.md", "mechanic": "agents/sysadmin.md",
      "notary": "agents/notary.md", "scribe": "agents/scribe.md",
      "spellwright": "agents/prompt-engineer.md", "systemsmith": "agents/backend.md",
      "witness": "agents/witness.md", "coupler": "agents/coupler.md",
      "tally": "agents/tally.md", "scoot": "agents/scoot.md",
  }
  TIERS = {"cheap", "standard", "strong", "frontier", "escalated"}
  bad = []
  for role, f in sorted(alias.items()):
      p = policy[role]["default_tier"]
      c = rows.get(f)
      a = None
      path = os.path.join(root, f)
      if os.path.exists(path):
          m = re.search(r"\*\*Recommended tier:\*\*\s*\**\s*([a-z]+)", open(path).read()[:1500])
          if m and m.group(1) in TIERS:
              a = m.group(1)
      if len({v for v in (p, c, a) if v}) > 1:
          bad.append(f"{role}: policy={p} cast={c} agent_file={a}")
  if bad:
      print("TIER MISMATCH:")
      for b in bad:
          print(" ", b)
      raise SystemExit(1)
  print("true")
  PY
expected: exit 0 — prints true; nonzero with the offending roles listed if a role's default tier is changed in one place and left stale in another. A tier is declared in three places (config/model-policy.v2.json, the cast table in docs/model-routing-and-cast.md, and the agent file's "Recommended tier:" line) and nothing previously compared them. On 2026-09-16 that produced three separate stale-tier defects in one session — systemsmith, then cleric twice — each found by review rather than by a check. Mutation: set roles.cleric.default_tier to "standard" without touching agents/designer.md → exit 1 naming cleric.
phase: model policy — a tier set in one place and stale in another (issue #60)
owner: config/model-policy.v2.json; docs/model-routing-and-cast.md § cast tables; agents/*.md tier lines
