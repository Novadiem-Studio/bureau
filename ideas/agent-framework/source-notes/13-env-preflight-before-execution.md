---
priority: 13
status: idea (pre-spec)
suggested-workflow: feature
suggested-run-slug: env-preflight-before-execution
---

# 13. Env preflight before execution

## One-liner
Before the build party starts, check that required environment variables are set, `.env.example` is current, and real validation targets are reachable — no fake validation passes.

## Problem
Build party runs fail mid-execution because a required env var is missing, an `.env.example` is stale, or an external service the build assumes is reachable is not. These are all knowable before the first prompt fires. Catching them mid-run wastes a pass and can leave partial state.

## Idea
1. Add a preflight step at the start of any `execute-plan` or `operational-build` workflow run.
2. Preflight checks:
   - All required env vars declared in `.env.example` are present in the environment.
   - `.env.example` matches the vars actually used in the build prompts (no undeclared vars, no stale entries).
   - Reachability check for any external services the prompts will call (not a smoke test — just a ping or a token validation).
3. Preflight runs before any agent is spawned and fails fast with a clear list of what is missing.
4. Preflight results are logged to `RUN_DIR/preflight.md` so the Conductor can surface them at the checkpoint.

## Guardrails
No fake validation — do not let a preflight "pass" on a placeholder value like `your-key-here`. Preflight should not reach external services in a way that consumes quota or triggers rate limits.

## Likely home
New `scripts/preflight.sh` + preflight step at the top of `execute-plan` and `operational-build` workflows. A preflight result artifact at `RUN_DIR/preflight.md`.

## Done when
Running an `execute-plan` workflow with a missing env var fails immediately at preflight with a clear message, before any agent is spawned. A passing preflight produces a `preflight.md` confirming all checks passed. The Conductor reads `preflight.md` before handing off to the build party.
