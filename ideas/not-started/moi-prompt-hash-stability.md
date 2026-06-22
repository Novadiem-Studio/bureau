# M.O.I. prompt_hash stability refinement

**Priority:** low — capture only. Do not work before the reopen-on-done noise fix (already shipped as `274886a`).

## Observation

After the Phase-2 M.O.I. spine went live (2026-06-18), the System Health panel at `/health` showed
**two distinct prompt_hash values** (53 + 27 rows) for the same `mot-intake` skill in the first hourly batch.

Every row has a non-empty hash — the audit contract is satisfied. But the hash is not stable run-to-run.
The CLASSIFIER-PROMPT region is delimited by `<!-- CLASSIFIER-PROMPT:START/END -->` markers in `SKILL.md`;
the cloud agent hashes only that region. The hash varies slightly across runs, meaning something in that
region is non-deterministic at the time of hashing — likely whitespace normalization, line-ending handling,
or a minor phrasing drift the model introduces before the hash is computed.

## What this means

- The `audit_quality` GROUP BY in `/api/status` bins rows by `(model_version, prompt_hash)`. Two hashes
  mean two buckets instead of one, so the panel shows split counts rather than a unified row per model version.
- Non-breaking — the panel still populates honestly, correction-rate signal is still valid, the refine
  constraint (`prompt_hash` non-null/non-empty) is still met.
- **R-P2-6** (hash stability) is the unmet residual. It was always a "capture-only" follow-up in the Phase-2
  build notes.

## Root cause to investigate

1. Is the cloud agent hashing the region content directly, or hashing after some inline processing?
2. Does the `<!-- CLASSIFIER-PROMPT:START/END -->` boundary land at exactly the same bytes each run, or
   does the model reflow the preamble in a way that includes/excludes a trailing newline?
3. Could the hash be computed outside the model (a pre-run hash of the static file content) rather than
   inside the skill's prompt loop? That would make it perfectly stable.

## Possible fix

Move the hash computation to a deterministic pre-run step: hash the bytes of the `CLASSIFIER-PROMPT` region
directly from `SKILL.md` on disk (or from the git-tracked file), pass the resulting hash as a skill config
value, and have the model use that value verbatim in the audit block rather than computing it inline.

This requires a skill update (how the hash is obtained) and probably a small script or MCP tool to pre-compute
it. Out of scope for Phase 2; worth a small standalone pass when the panel's per-hash grouping matters enough
to act on.
