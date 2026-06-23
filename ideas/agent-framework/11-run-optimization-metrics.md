---
priority: bundle-04-followup
status: idea (open)
suggested-workflow: feature
suggested-run-slug: run-optimization-metrics
source: audit of the Bundle 09 run (20260620-principal-delegate) + Robin's direction, 2026-06-21
---

# 11. Run optimization metrics (tokens, loops, wall-clock, human-wait)

## Purpose

Bundle 04 made a run's *shape* visible (which roles spawned, which models, how many critic
loops, did it finish). It did not capture the numbers you actually optimize a run against:
how many **tokens**, how many **loops**, how much **wall-clock**, and how much **human-wait**
(time a run sits blocked on Robin at a checkpoint). On a Claude subscription, dollars are
irrelevant; tokens, time, and human-attention are the real budget. This bundle captures those
four, live, into `log.md`, so a finished run reports them with one `grep` and so studio-level
trends can show whether the loop-cost work (Bundle 09) and the loop-count work (Bundle 12) are
actually paying off.

Dollars are explicitly out of scope. The cost unit is the token.

## Why this wasn't done in Bundle 04

Two different reasons, one trivial and one real:

- **Timing and human-wait** were never asked for by the `SPAWN-EVENT` and checkpoint
  conventions. The Conductor already writes those records; it just does not stamp them with a
  time. Cheap to add.
- **Tokens** are the genuine constraint, and they are exactly why `accounting.json#cost` reads
  `"no token/cost source in scope for v1"`. A running model cannot see its own token usage.
  There is no runtime API, env var, or tool that tells the Conductor or a subagent how many
  tokens it has used; the counts are computed server-side and only exist in the transcript
  afterward. So the Conductor cannot write token counts into `log.md` on its own. You have to
  reach the harness layer (a hook) to get the number.

## Design principle: log.md is the source of truth

Do **not** reconstruct metrics by combing the session transcript after the fact. The session
`.jsonl` is large, and a run can span multiple resumed sessions with no built-in cross-session
run id, so after-the-fact reconstruction silently misses legs (verified during the Bundle 09
audit: the reconstruction keyed on a single conductor session and would have missed any resumed
leg). Instead, capture as the run goes, as structured one-line-JSON records in `log.md`, the
same shape as the existing `SPAWN-EVENT` lines. `log.md` is keyed to the run dir, not the
session, so it accumulates correctly no matter how many sessions a run spans. The consumer
(`account-run.sh`) then parses `log.md` only and never touches a transcript.

## First implementation slice

1. **Enrich the `SPAWN-EVENT` complete line** with `at`, `started_at`, `duration_s`, `turns`,
   and a `tokens` object (`input`, `cache_creation`, `cache_read`, `processed`, `output`).
   `processed = input + cache_creation + cache_read` is the reliable figure; `output` is
   recorded but flagged unreliable (see Risks).
2. **Add a `CHECKPOINT-EVENT` line type**: `{id, status: raised|resolved, at, wait_s, decision}`.
   Sum of `wait_s` across a run is the human-wait number, available per checkpoint.
3. **Capture tokens via a `SubagentStop` hook.** It fires at the harness layer when each Task
   subagent finishes and receives that subagent's `transcript_path`. The hook sums the usage
   from that one transcript (a single known file, read once, at completion, not a fishing
   expedition) and appends the token record to the active run's `log.md`. It can lift the
   framework `attempt_id` from the task prompt in that transcript, so the record is
   self-contained. Glue required: tell the hook which `RUN_DIR` is active (an env var the
   launcher sets, or a small `output/runs/.active` pointer). If no active run is set, the hook
   must no-op cleanly, never crash the run or write to the wrong run.
4. **Cover the Conductor's own tokens.** `SubagentStop` covers subagents only, and the
   Conductor was ~27% of the Bundle 09 run. Capture it with the main-session `Stop` hook or a
   one-shot close-out parse of the conductor transcript. Do not double-count it against the
   specialists.
5. **Teach `account-run.sh` (or a sibling `account-tokens.sh`) to read `log.md` only** and emit
   the metrics, reusing Bundle 04's `{value, confidence}` schema. It already greps
   `SPAWN-EVENT`; it learns the new fields and the one new line type.
6. **Derived metrics** the consumer computes: rework ratio (loop tokens / total),
   tokens-per-loop, minutes-per-loop, active-vs-blocked time, human-wait total. These are the
   levers for spotting whether a workflow change reduced loop cost or loop count.

## Worked example (already reconstructed)

The Bundle 09 run was reconstructed by hand from its transcripts as the target shape:
`output/runs/20260620-principal-delegate/token-accounting.json`. Headline numbers: 31.4M
processed tokens, 2 critic loops, ~53m wall-clock, ~2m human-wait (one design-model checkpoint,
Robin present). The critic loop was the top cost on both axes the metrics care about: the single
architect revision was 34% of tokens and the longest phase (10m36s); total rework was ~57% of
tokens and ~32% of active time. That reconstruction is the floor this bundle automates and makes
multi-session-safe.

## Done when

- A finished run reports, readable from `log.md` with no transcript combing: tokens per phase
  and total; loop count; wall-clock per phase and total; human-wait per checkpoint and total.
- The numbers are correct for a run that spanned more than one session.
- Confidence labels are preserved per Bundle 04's schema (`processed` exact; `output`
  estimated).
- The capture is script-enforced or hook-enforced, not Conductor-discretionary (passes the
  gate-theater rule).

## Risks

- **`output_tokens` is unreliable** and must not be the headline. A turn that wrote a 71KB file
  in the Bundle 09 run logged `output_tokens: 2` (large writes bill as cache, not output). Lead
  with `processed`; mark `output` estimated.
- **The hook needs the active `RUN_DIR`.** Get this wrong and tokens land in the wrong run or
  the hook crashes a build. It must fail safe (no-op when no run is active).
- **Do not reintroduce transcript-combing in the consumer.** `log.md` is authoritative; the hook
  is the only component that reads a transcript, once, at the moment of completion.
- **Keep it Bash 3.2 / macOS portable** (the script host); no GNU-only `date`, no `declare -A`.

## Couplings

- Extends **Bundle 04** (run accounting): same `{value, confidence}` schema, same
  short-pointer-in-`state.json` rule, the actual packet in its own file.
- Sibling of **Bundle 10** (also a Bundle 04 follow-up): 10 hardens the existing script's tests;
  11 adds new metrics. They do not conflict.
- Measures **Bundle 09** (cuts loop *cost*) and **Bundle 12** (cuts loop *count*). These metrics
  are how you tell either one worked. Bundle 04's stated purpose led with "what it cost"; this
  closes that gap with the cost unit that matters on a subscription.
- Later slice (out of scope here): aggregate per-run metrics into `output/studio/` for
  cross-run trends, reusing the Studio Record without redefining ownership.
