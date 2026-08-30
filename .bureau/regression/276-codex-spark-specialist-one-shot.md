name: Spark one-shot helper accepts only a committed clean Mage handoff and reserves exit 75 for an untouched failed attempt
owner: scripts/run-codex-spark-specialist.sh
phase: 05 · execute-plan
command: |
  ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
  TMPF=$(mktemp -d)
  trap 'rm -rf "$TMPF"' EXIT INT TERM

  FAKE="$TMPF/fake-codex"
  cat > "$FAKE" <<'FAKE_CODEX'
  #!/usr/bin/env bash
  set -u
  : > "$FAKE_CAPTURE_DIR/args"
  OUTPUT_LAST=""
  WORKTREE=""
  while [ "$#" -gt 0 ]; do
    printf '%s\n' "$1" >> "$FAKE_CAPTURE_DIR/args"
    case "$1" in
      -o)
        OUTPUT_LAST="$2"
        shift
        printf '%s\n' "$1" >> "$FAKE_CAPTURE_DIR/args"
        ;;
      -C)
        WORKTREE="$2"
        shift
        printf '%s\n' "$1" >> "$FAKE_CAPTURE_DIR/args"
        ;;
    esac
    shift
  done
  cat > "$FAKE_CAPTURE_DIR/stdin"
  NONCE=$(sed -n 's/^Run nonce: //p' "$FAKE_CAPTURE_DIR/stdin")
  printf 'private diagnostic %s\n' "$NONCE" >&2
  printf '%s\n' 'safe diagnostic' >&2

  case "$FAKE_MODE" in
    success)
      printf '%s\n' 'spark edit' > "$WORKTREE/spark-ui.txt"
      git -C "$WORKTREE" add spark-ui.txt
      git -C "$WORKTREE" -c user.name='Fixture' -c user.email='fixture@example.invalid' \
        commit -qm 'Spark UI edit'
      cat > "$OUTPUT_LAST" <<'HANDOFF'
  THE MAGE — BUILT 01
  Consumed: 01-small-ui.md; local instructions
  Produced: spark-ui.txt
  Passing forward:
  - none
  Prompt: 01-small-ui.md
  Checkpoint: green — fixture
  Review size: 1 changed file; matches prompt Reviewability yes
  New packages installed: none
  Out-of-scope issues noticed (did NOT touch): none
  HANDOFF
      ;;
    decline)
      printf '%s\n' 'SPARK PROFILE INELIGIBLE — fixture decline' > "$OUTPUT_LAST"
      ;;
    committed-without-handoff)
      printf '%s\n' 'unsafe edit' > "$WORKTREE/unsafe-ui.txt"
      git -C "$WORKTREE" add unsafe-ui.txt
      git -C "$WORKTREE" -c user.name='Fixture' -c user.email='fixture@example.invalid' \
        commit -qm 'Unsafe incomplete Spark edit'
      printf '%s\n' 'not a Mage handoff' > "$OUTPUT_LAST"
      ;;
    *)
      exit 64
      ;;
  esac
  printf '%s\n' '{"type":"turn.completed","usage":{"input_tokens":100,"cached_input_tokens":40,"cache_write_input_tokens":5,"output_tokens":20}}'
  FAKE_CODEX
  chmod +x "$FAKE"

  make_case() {
    CASE_NAME="$1"
    CASE_ROOT="$TMPF/$CASE_NAME"
    CASE_RUN="$CASE_ROOT/run"
    CASE_WORKTREE="$CASE_ROOT/worktree"
    CASE_CAPTURE="$CASE_ROOT/capture"
    CASE_POINTER="$CASE_ROOT/pointer.json"
    CASE_PROMPT="$CASE_ROOT/01-small-ui.md"
    mkdir -p "$CASE_RUN" "$CASE_WORKTREE" "$CASE_CAPTURE"
    git -C "$CASE_WORKTREE" init -q
    git -C "$CASE_WORKTREE" config core.fsmonitor false
    printf '%s\n' base > "$CASE_WORKTREE/base.txt"
    git -C "$CASE_WORKTREE" add base.txt
    git -C "$CASE_WORKTREE" -c user.name='Fixture' -c user.email='fixture@example.invalid' \
      commit -qm 'base'
    CASE_RUN=$(cd "$CASE_RUN" && pwd -P)
    CASE_WORKTREE=$(cd "$CASE_WORKTREE" && pwd -P)
    cat > "$CASE_RUN/model-routing.json" <<'ROUTING'
  {
    "runtime": "openai",
    "roles": {
      "mage": {
        "executionProfiles": {
          "granular-ui-fast": {
            "model": "gpt-5.3-codex-spark",
            "reasoningEffort": "high",
            "transport": "codex-exec-one-shot",
            "helper": "scripts/run-codex-spark-specialist.sh"
          }
        }
      }
    }
  }
  ROUTING
    jq -cn --arg worktree "$CASE_WORKTREE" \
      '{workflow:"execute-plan",git:{worktree_path:$worktree}}' > "$CASE_RUN/state.json"
    cat > "$CASE_PROMPT" <<'PROMPT'
  # 01 — web: small UI edit
  Coder: The Mage
  Execution-profile: granular-ui-fast
  Release-step: no
  ## Do
  1. Make the bounded text-only fixture edit.
  ## Checkpoint (green before 02)
  Seams under test: none — fixture
  PROMPT
    CASE_NONCE="nonce-$CASE_NAME-$$"
    jq -cn --arg run "$CASE_RUN" --arg nonce "$CASE_NONCE" \
      '{run_dir:$run,nonce:$nonce}' > "$CASE_POINTER"
  }

  make_case success
  SUCCESS_RUN="$CASE_RUN"
  SUCCESS_WORKTREE="$CASE_WORKTREE"
  SUCCESS_CAPTURE="$CASE_CAPTURE"
  SUCCESS_POINTER="$CASE_POINTER"
  SUCCESS_PROMPT="$CASE_PROMPT"
  SUCCESS_NONCE="$CASE_NONCE"
  CODEX_BIN="$FAKE" FAKE_MODE=success FAKE_CAPTURE_DIR="$SUCCESS_CAPTURE" \
    BUREAU_POINTER_FILE="$SUCCESS_POINTER" \
    bash "$ROOT/scripts/run-codex-spark-specialist.sh" \
      "$SUCCESS_RUN" "$SUCCESS_WORKTREE" "$SUCCESS_PROMPT" mage-1 \
      > "$TMPF/success-result.json" \
    || { echo 'FAIL: committed success was rejected'; exit 1; }

  jq -e '
    .status == "complete"
    and .reason == "complete"
    and .profile == "granular-ui-fast"
    and .transport == "codex-exec-one-shot"
    and .actual_model == "gpt-5.3-codex-spark"
    and .reasoning_effort == "high"
    and .fallback_safe == false
    and (.handoff_path | type == "string")
  ' "$TMPF/success-result.json" >/dev/null \
    || { echo 'FAIL: wrong success metadata'; exit 1; }
  jq -e '
    .requested_model == "gpt-5.3-codex-spark"
    and .reasoning_effort == "high"
    and .num_turns == 1
    and .usage.input_tokens == 60
    and .usage.cache_creation_input_tokens == 5
    and .usage.cache_read_input_tokens == 40
    and .usage.output_tokens == 20
  ' "$SUCCESS_RUN/codex-specialists/mage-1/envelope.json" >/dev/null \
    || { echo 'FAIL: usage envelope was not normalized'; exit 1; }
  grep -Fqx -- '--ask-for-approval' "$SUCCESS_CAPTURE/args" \
    && grep -Fqx -- 'never' "$SUCCESS_CAPTURE/args" \
    && grep -Fqx -- '--strict-config' "$SUCCESS_CAPTURE/args" \
    && grep -Fqx -- '--ephemeral' "$SUCCESS_CAPTURE/args" \
    && grep -Fqx -- '--ignore-user-config' "$SUCCESS_CAPTURE/args" \
    && grep -Fqx -- '--sandbox' "$SUCCESS_CAPTURE/args" \
    && grep -Fqx -- 'workspace-write' "$SUCCESS_CAPTURE/args" \
    && grep -Fqx -- 'gpt-5.3-codex-spark' "$SUCCESS_CAPTURE/args" \
    && grep -Fqx -- 'model_reasoning_effort="high"' "$SUCCESS_CAPTURE/args" \
    || { echo 'FAIL: Spark/high one-shot flags missing'; exit 1; }
  grep -Fq 'BUREAU_ROLE: mage' "$SUCCESS_CAPTURE/stdin" \
    && grep -Fq 'Workflow: execute-plan' "$SUCCESS_CAPTURE/stdin" \
    && grep -Fq "Run nonce: $SUCCESS_NONCE" "$SUCCESS_CAPTURE/stdin" \
    || { echo 'FAIL: scoped launch prompt missing'; exit 1; }
  [ "$(git -C "$SUCCESS_WORKTREE" rev-list --count HEAD)" -eq 2 ] \
    && [ -z "$(git -C "$SUCCESS_WORKTREE" status --porcelain --untracked-files=all --ignore-submodules=none)" ] \
    || { echo 'FAIL: accepted success was not committed and clean'; exit 1; }
  grep -Fq 'THE MAGE — BUILT 01' "$SUCCESS_RUN/codex-specialists/mage-1/handoff.md" \
    || { echo 'FAIL: validated handoff absent'; exit 1; }
  grep -Fq 'safe diagnostic' "$SUCCESS_RUN/codex-specialists/mage-1/stderr.log" \
    && ! grep -R -Fq -- "$SUCCESS_NONCE" "$SUCCESS_RUN/codex-specialists/mage-1" \
    || { echo 'FAIL: private nonce persisted in normalized evidence'; exit 1; }

  make_case decline
  DECLINE_RUN="$CASE_RUN"
  DECLINE_WORKTREE="$CASE_WORKTREE"
  DECLINE_CAPTURE="$CASE_CAPTURE"
  DECLINE_POINTER="$CASE_POINTER"
  DECLINE_PROMPT="$CASE_PROMPT"
  DECLINE_HEAD=$(git -C "$DECLINE_WORKTREE" rev-parse HEAD)
  CODEX_BIN="$FAKE" FAKE_MODE=decline FAKE_CAPTURE_DIR="$DECLINE_CAPTURE" \
    BUREAU_POINTER_FILE="$DECLINE_POINTER" \
    bash "$ROOT/scripts/run-codex-spark-specialist.sh" \
      "$DECLINE_RUN" "$DECLINE_WORKTREE" "$DECLINE_PROMPT" mage-2 \
      > "$TMPF/decline-result.json"
  DECLINE_RC=$?
  [ "$DECLINE_RC" -eq 75 ] \
    || { echo "FAIL: untouched decline exited $DECLINE_RC instead of 75"; exit 1; }
  jq -e '
    .status == "failed"
    and .reason == "profile-ineligible"
    and .fallback_safe == true
    and .handoff_path == null
  ' "$TMPF/decline-result.json" >/dev/null \
    || { echo 'FAIL: wrong clean-fallback metadata'; exit 1; }
  [ "$(git -C "$DECLINE_WORKTREE" rev-parse HEAD)" = "$DECLINE_HEAD" ] \
    && [ -z "$(git -C "$DECLINE_WORKTREE" status --porcelain --untracked-files=all --ignore-submodules=none)" ] \
    && [ ! -e "$DECLINE_RUN/codex-specialists/mage-2/handoff.md" ] \
    || { echo 'FAIL: fallback-safe decline changed git state or persisted a handoff'; exit 1; }

  make_case committed-without-handoff
  UNSAFE_RUN="$CASE_RUN"
  UNSAFE_WORKTREE="$CASE_WORKTREE"
  UNSAFE_CAPTURE="$CASE_CAPTURE"
  UNSAFE_POINTER="$CASE_POINTER"
  UNSAFE_PROMPT="$CASE_PROMPT"
  CODEX_BIN="$FAKE" FAKE_MODE=committed-without-handoff FAKE_CAPTURE_DIR="$UNSAFE_CAPTURE" \
    BUREAU_POINTER_FILE="$UNSAFE_POINTER" \
    bash "$ROOT/scripts/run-codex-spark-specialist.sh" \
      "$UNSAFE_RUN" "$UNSAFE_WORKTREE" "$UNSAFE_PROMPT" mage-3 \
      > "$TMPF/unsafe-result.json"
  UNSAFE_RC=$?
  [ "$UNSAFE_RC" -eq 76 ] \
    || { echo "FAIL: changed failed attempt exited $UNSAFE_RC instead of 76"; exit 1; }
  jq -e '
    .status == "failed"
    and .reason == "invalid-mage-handoff"
    and .fallback_safe == false
    and .handoff_path == null
  ' "$TMPF/unsafe-result.json" >/dev/null \
    || { echo 'FAIL: changed failure was marked fallback-safe'; exit 1; }
  [ "$(git -C "$UNSAFE_WORKTREE" rev-list --count HEAD)" -eq 2 ] \
    && [ -z "$(git -C "$UNSAFE_WORKTREE" status --porcelain --untracked-files=all --ignore-submodules=none)" ] \
    || { echo 'FAIL: unsafe fixture did not leave the expected clean commit'; exit 1; }

  echo PASS
expected: exit 0; stdout "PASS"; fake Codex receives an ephemeral workspace-only Spark/high Mage invocation, a turn-completed + exact handoff + clean descendant commit is accepted with normalized usage and no persisted nonce; an exit-zero profile decline that leaves HEAD/worktree untouched is rejected with status 75 and fallback_safe=true, while a clean committed attempt without the exact handoff is rejected with status 76 and cannot auto-fallback
