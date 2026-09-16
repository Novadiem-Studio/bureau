name: every role's tier agrees across policy, the cast table, and its agent file
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  python3 - "$ROOT" <<'PY'
  import json, re, os, sys
  root = sys.argv[1]
  policy = json.load(open(f"{root}/config/model-policy.v2.json"))["roles"]
  cast = open(f"{root}/docs/model-routing-and-cast.md").read()
  # The tier cell is not always a bare word: the droid rows read
  # "standard - **sonnet, capped**" and "cheap - **haiku, locked**". Take the
  # LEADING tier token and ignore the qualifier, rather than demanding a format
  # the docs do not use — an earlier draft reported scoot and tally as missing
  # when both were declared, which would have been a false red on every run.
  rows = {}
  for m in re.finditer(
          r'^\|\s*\*\*([^*]+)\*\*[^|]*\|\s*`(agents/[\w-]+\.md)`\s*\|\s*([^|]+?)\s*\|', cast, re.M):
      first = re.match(r'([a-z]+)', m.group(3).strip())
      if first:
          rows[m.group(2)] = first.group(1)
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
      # A MISSING declaration is a failure, not an abstention. An earlier draft
      # dropped None values before comparing, so a role declared in only one
      # place compared clean — the absence-reads-as-success defect, in the guard
      # written to catch stale declarations.
      if c is None:
          bad.append(f"{role}: no cast-table row for {f}")
          continue
      if a is None:
          bad.append(f"{role}: no valid 'Recommended tier:' line in {f}")
          continue
      if p not in TIERS:
          bad.append(f"{role}: policy tier {p!r} is not a known tier")
          continue
      if len({p, c, a}) > 1:
          bad.append(f"{role}: policy={p} cast={c} agent_file={a}")
  if bad:
      print("TIER DECLARATION PROBLEM:")
      for b in bad:
          print(" ", b)
      raise SystemExit(1)
  print("true")
  PY
expected: exit 0 — prints true; nonzero with the offending roles listed if a role's default tier is changed in one place and left stale in another. A tier is declared in three places (config/model-policy.v2.json, the cast table in docs/model-routing-and-cast.md, and the agent file's "Recommended tier:" line) and nothing previously compared them. On 2026-09-16 that produced three separate stale-tier defects in one session — systemsmith, then cleric twice — each found by review rather than by a check. A MISSING declaration fails too: an earlier draft dropped None values before comparing, so a role declared in only one place passed — the absence-reads-as-success defect inside the guard built to catch stale declarations. Mutations: set roles.cleric.default_tier to "standard" without touching agents/designer.md → exit 1 naming cleric; delete a cast-table row → exit 1 naming the missing row.
phase: model policy — a tier set in one place and stale in another (issue #60)
owner: config/model-policy.v2.json; docs/model-routing-and-cast.md § cast tables; agents/*.md tier lines
