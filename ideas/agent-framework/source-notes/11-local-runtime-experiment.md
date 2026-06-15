---
priority: 11
status: idea (pre-spec)
suggested-workflow: feature
suggested-run-slug: local-runtime-experiment
---

# 11. Local runtime experiment

## One-liner
Add a capability-aware `local` adapter for offline or cheap utility work — tasks that do not need a frontier model — plus a smoke test that confirms the adapter is wired up correctly before use.

## Problem
Every framework task currently routes to cloud models. Some utility work — name linting, doc formatting, small script checks — does not need a frontier model and could run locally for cost or privacy reasons. There is no adapter or routing path for this, so cheap tasks and expensive tasks share the same billing surface.

## Idea
1. Define a `local` tier in the model routing system alongside `standard`, `strong`, and `frontier`.
2. Build a capability-aware adapter that can route a task to a locally running model (e.g., Ollama, llama.cpp, or similar) when the task fits within its capability profile.
3. Define the capability profile: what task types are safe to route locally (name lint, doc diff, template fill) vs. what must stay cloud (architecture, Challenger, code generation).
4. Add a smoke test that confirms the local adapter is reachable and returns coherent output before the framework routes any real task to it.
5. Add `local` to `model-routing.json` and the routing resolution scripts.

## Guardrails
Local routing must never silently degrade quality — if the local model fails or is unavailable, fall back to `standard` with a logged warning, not silently. Tasks with external side effects never route locally.

## Likely home
`config/runtimes/` for the local adapter definition, `scripts/resolve-model-routing.sh` for routing logic, `agents/orchestrator.md` for task-type guidance. Smoke test in `scripts/`.

## Done when
A utility task (e.g., descriptive-name lint) can be explicitly routed to the local adapter. The adapter is either available and tested, or falls back to `standard` with a clear log line. `model-routing.json` reflects the local tier when available.

## Open questions
- Which local model runtime is the primary target? Ollama is the most common but not universal.
- Should local routing be opt-in per task, or automatic based on task-type classification?
- How does the capability profile get maintained as local model quality improves?
