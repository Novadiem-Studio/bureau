---
priority: bundle-06
status: idea (consolidated)
suggested-workflow: feature
suggested-run-slug: navigation-and-runtime-experiments
source-ideas:
  - source-notes/04-descriptive-name-lint.md
  - source-notes/11-local-runtime-experiment.md
---

# 06. Navigation and runtime experiments

## Purpose

Improve fresh-agent navigability and explore cheaper/offline runtime paths for low-risk
utility tasks. This bundle is intentionally last because it optimizes the framework rather
than protecting correctness.

## Consolidates

| Source | Role in this bundle |
|---|---|
| `04-descriptive-name-lint` | Warning-only check for vague script, workflow, and runbook names. |
| `11-local-runtime-experiment` | Capability-aware local adapter for cheap/offline utility work. |

## Execution note

The two parts do not have to land together. Descriptive-name lint is a tiny opportunistic win
and can be done earlier if a small warm-up change is useful. Local runtime should wait until
Bundle 04 can show which tasks are actually worth routing locally.

## First implementation slice

Implement name lint only:

1. Add a warning-only section to `check-framework.sh` (at repo root, not `scripts/`).
   The lint block must print warnings to stdout and **must never increment `errors` or alter
   the exit code** — `check-framework.sh` exits 1 when `errors > 0`, so a hygiene warning
   that touches `errors` becomes a build break across every install.
2. Back it with a small script only if the shell logic becomes awkward.
3. Flag generic names such as `util`, `helper`, `run`, `test`, `common`, temp-looking files
   outside temp paths, and near-duplicate workflow/script names.
4. Add an allowlist for legitimate legacy names, **pre-populated from the current tree** so
   the check is silent on day one. A noisy lint on first run trains agents to ignore
   `check-framework.sh` entirely, which is worse than no lint.
5. Do not fail the build on warnings.

## Local runtime experiment slice

Only after accounting identifies repeated low-risk utility work. Session digesting and
candidate memory extraction may become candidates, but only after Rheo memory has enough
quality/cost data to prove local routing will not degrade recall or pollute memory.

1. Add a provider-neutral `local` runtime adapter under `config/runtimes/`.
2. Define a capability profile:
   - safe: name lint, doc formatting, template fill, narrow summaries;
   - unsafe: architecture, Challenger review, code generation, external side effects.
3. Add a smoke test before routing any real task locally.
4. Fall back to `standard` with a log line if local is unavailable or incoherent.
5. Keep local routing opt-in until several runs prove it does not degrade quality.

## Done when

- `check-framework.sh` can warn about vague names without blocking legitimate work.
- Local routing, if enabled, is explicit, smoke-tested, and never silently lowers quality.
- The local adapter is used for utility tasks only, not judgment-heavy roles.

## Risks

- Name lint can become noisy and train agents to ignore framework checks. Keep warnings few.
- Local runtime can save money while quietly reducing quality. Default to fallback and opt-in.
- Maintaining a capability profile is ongoing work; do not add it unless accounting shows a
  real utility workload.

## Carried from Bundle 1a close-out (validation-safety-damage-preventers)

A visualizer-navigability follow-up deferred at Bundle 1a's close-out, recorded here so it
survives archiving the run dir:

- **society-desk: recognize `Preflight` as a control keyword.** Bundle 1a added preflight steps
  to `execute-plan` (step 5c) and `operational-build` (step 2b). The society-desk workflow parser
  (`lib/workflow-parser.ts`) has a closed control-keyword allowlist (bracket marker / **Gate** /
  **Worktree** only), so preflight steps had to lead with **The Conductor** to render as a
  resolving node instead of a dark, agent-less one. Adding `Preflight` to the parser's
  control-keyword allowlist would let preflight steps be true control nodes. This is a change in
  the **separate society-desk repo**, made via its governed workflow-improvements change path —
  out of framework scope, low value, cosmetic. (Bundle 1a carried_item #8.)
