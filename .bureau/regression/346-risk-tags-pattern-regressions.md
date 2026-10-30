name: risk-tags patterns found by the verification pass — pricing and balances escalate, variable-URL fetch, nested agents, lenient fences
command: |
  set -e
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  S="$ROOT/scripts/risk-tags.sh"
  TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
  W="$TMP/w"; mkdir -p "$W/app/pricing" "$W/plugins/foo/agents/sub" "$W/web"
  git -C "$W" init -q; git -C "$W" config user.email t@t; git -C "$W" config user.name t
  echo 'x = 1' > "$W/a.py"; git -C "$W" add -A; git -C "$W" commit -qm base
  run() {
    B=$(git -C "$W" rev-parse HEAD); eval "$2"; git -C "$W" add -A; git -C "$W" commit -qm "$1"
    set +e; "$S" --worktree "$W" --base "$B" ${3:-} --out "$TMP/$1.json" >/dev/null 2>&1; rc=$?; set -e
  }
  run pricing "printf 'def total(price, qty):\n    return price * qty\n' > '$W/app/pricing/calc.py'"
  [ "$rc" -eq 3 ] || { echo "FAIL pricing module not escalated (rc $rc)"; exit 1; }
  run balance "printf 'user.balance -= amount\n' > '$W/app/accounts.py'"
  [ "$rc" -eq 3 ] || { echo "FAIL balance arithmetic not escalated (rc $rc)"; exit 1; }
  run page "printf 'export default function Pricing() { return <h1>Plans</h1> }\n' > '$W/app/pricing/page.tsx'"
  [ "$rc" -eq 0 ] || { echo "FAIL pricing page escalated (rc $rc)"; exit 1; }
  run fetchvar "printf 'const r = await fetch(API_URL, {method: \"POST\"})\n' > '$W/web/sync.ts'"
  [ "$rc" -eq 1 ] && jq -e '.review_tags|index("network-egress")' "$TMP/fetchvar.json" >/dev/null || { echo "FAIL fetch(API_URL) (rc $rc)"; exit 1; }
  run fetchprop "printf 'const r = await fetch(config.apiEndpoint, options)\n' > '$W/web/prop.ts'"
  [ "$rc" -eq 1 ] && jq -e '.review_tags|index("network-egress")' "$TMP/fetchprop.json" >/dev/null || { echo "FAIL fetch(config.apiEndpoint) (rc $rc)"; exit 1; }
  run fetchlocal "printf 'const r = await fetch(\"/api/items\")\n' > '$W/web/local.ts'"
  [ "$rc" -eq 0 ] || { echo "FAIL same-origin fetch flagged (rc $rc)"; exit 1; }
  run agent "printf -- '---\ntools: Bash\n---\n' > '$W/plugins/foo/agents/sub/x.md'"
  [ "$rc" -eq 1 ] && jq -e '.review_tags|index("tool-allowlist")' "$TMP/agent.json" >/dev/null || { echo "FAIL nested agent (rc $rc)"; exit 1; }
  printf -- '- item\n  ```JSON risk_tags\n  {"tags": [{"id": "proj-x", "class": "review", "lines": ["zebra_api"]}]}\n  ```\n' > "$TMP/ctx.md"
  run fence "echo 'v = zebra_api()' >> '$W/a.py'" "--project-context $TMP/ctx.md"
  [ "$rc" -eq 1 ] && jq -e '.review_tags|index("proj-x")' "$TMP/fence.json" >/dev/null || { echo "FAIL indented upper-case fence (rc $rc)"; exit 1; }
  printf '```json risk_tags\n{"tags": []}\n' > "$TMP/open.md"
  run unterminated "echo 'w = 1' >> '$W/a.py'" "--project-context $TMP/open.md"
  [ "$rc" -eq 2 ] || { echo "FAIL unterminated fence not refused (rc $rc)"; exit 1; }
  echo PASS
expected: exit 0; stdout PASS. A pricing module and `balance -=` escalate (money) while a pricing page.tsx does not; `fetch(API_URL, ...)` trips network-egress; a nested plugin agent .md with `tools:` trips tool-allowlist; an indented, upper-case ```JSON risk_tags fence is parsed; an unterminated one exits 2. MUTATION — removing the pricing path or balance pattern from config/risk-tags.json, or reverting the fence regex in scripts/risk-tags.sh to the unindented lower-case form, makes this fixture exit non-zero.
phase: bureau-lite · issue #100 (cold-review fixes)
owner: scripts/risk-tags.sh + config/risk-tags.json
