name: Auto delivery resolves public GitHub to PR and private GitHub to the configured fallback
phase: GitHub-native delivery
owner: scripts/pr-delivery.sh policy resolver
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
  make_state "$PUB"
  make_state "$PRIV"
  GH_VIS=PUBLIC PATH="$BIN:$PATH" "$ROOT/scripts/pr-delivery.sh" status --run-dir "$PUB" >/dev/null || exit 1
  GH_VIS=PRIVATE PATH="$BIN:$PATH" "$ROOT/scripts/pr-delivery.sh" status --run-dir "$PRIV" >/dev/null || exit 1

  jq -e '.git.delivery_mode == "github" and .git.github_visibility == "PUBLIC"' "$PUB/state.json" >/dev/null || exit 1
  jq -e '
    .git.delivery_mode == "local"
    and .git.github_visibility == "PRIVATE"
    and (.git.delivery_fallback_reason | contains("private repositories"))
  ' "$PRIV/state.json" >/dev/null || exit 1
  echo PASS
expected: exit 0; stdout "PASS"; public auto delivery selects GitHub while private auto delivery remains local unless explicitly opted in
