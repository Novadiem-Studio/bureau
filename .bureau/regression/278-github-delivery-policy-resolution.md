name: Auto delivery resolves public AND private GitHub repos to PR by default, and honors an explicit local opt-out
phase: GitHub-native delivery
owner: scripts/pr-delivery.sh policy resolver; templates/state.json#git.private_delivery default (2026-09-09 policy flip)
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  trap 'rm -rf "$TMPF"' EXIT INT TERM
  REPO="$TMPF/repo"
  BIN="$TMPF/bin"
  mkdir -p "$REPO" "$BIN"
  git init "$REPO" >/dev/null 2>&1 || exit 1
  git -C "$REPO" remote add origin https://github.com/acme/demo.git

  cat > "$BIN/gh" <<'FAKEGH'
  #!/bin/sh
  case "$1 $2" in
    "repo view") printf '{"nameWithOwner":"acme/demo","url":"https://github.com/acme/demo","visibility":"%s"}\n' "$GH_VIS" ;;
    *) exit 9 ;;
  esac
  FAKEGH
  chmod +x "$BIN/gh"

  make_state() {
    run="$1"
    mkdir -p "$run"
    jq --arg repo "$REPO" '
      .git.enabled = true |
      .git.repo = $repo |
      .git.worktree_path = $repo |
      .git.branch = "bureau/policy" |
      .git.base_branch = "main" |
      .git.run_slug = "policy"
    ' "$ROOT/templates/state.json" > "$run/state.json"
  }

  PUB="$TMPF/public"
  PRIV="$TMPF/private"
  PRIV_OPTOUT="$TMPF/private-optout"
  make_state "$PUB"
  make_state "$PRIV"
  make_state "$PRIV_OPTOUT"
  # Simulate a project's explicit local opt-out (project-context.md's
  # git.private_delivery: local, as carried into state.json's git block —
  # docs/github-delivery.md). Untouched runs use the template's own default.
  jq '.git.private_delivery = "local"' "$PRIV_OPTOUT/state.json" > "$PRIV_OPTOUT/state.json.tmp" \
    && mv "$PRIV_OPTOUT/state.json.tmp" "$PRIV_OPTOUT/state.json"

  GH_VIS=PUBLIC PATH="$BIN:$PATH" "$ROOT/scripts/pr-delivery.sh" status --run-dir "$PUB" >/dev/null || exit 1
  GH_VIS=PRIVATE PATH="$BIN:$PATH" "$ROOT/scripts/pr-delivery.sh" status --run-dir "$PRIV" >/dev/null || exit 1
  GH_VIS=PRIVATE PATH="$BIN:$PATH" "$ROOT/scripts/pr-delivery.sh" status --run-dir "$PRIV_OPTOUT" >/dev/null || exit 1

  jq -e '.git.delivery_mode == "github" and .git.github_visibility == "PUBLIC"' "$PUB/state.json" >/dev/null \
    || { echo "FAIL: public repo did not resolve to github"; exit 1; }
  jq -e '.git.delivery_mode == "github" and .git.github_visibility == "PRIVATE"' "$PRIV/state.json" >/dev/null \
    || { echo "FAIL: private repo with no opt-out must default to github delivery (2026-09-09 policy)"; exit 1; }
  jq -e '
    .git.delivery_mode == "local"
    and .git.github_visibility == "PRIVATE"
    and (.git.delivery_fallback_reason | contains("local delivery"))
  ' "$PRIV_OPTOUT/state.json" >/dev/null \
    || { echo "FAIL: private repo with an explicit local opt-out must still resolve local"; exit 1; }
  echo PASS
expected: exit 0; stdout "PASS"; public auto delivery selects GitHub, private auto delivery ALSO defaults to GitHub since the 2026-09-09 policy flip, and an explicit git.private_delivery: local opt-out still resolves local. Mutation: revert templates/state.json#git.private_delivery to "local" and the PRIV case wrongly resolves local, failing this fixture.
