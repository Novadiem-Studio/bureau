# Rheo Memory Track 3 — Curation & Quality

Date: 2026-06-22
Status: done (edges + compaction deferred — see § Deferred)
Depends on: Track 2 shipped (2026-06-22)

---

## One-liner

Close the entity lifecycle loop, add semantic dedup at extraction time, and harden the graph's
surrounding plumbing. (Edge promotion and compaction were scoped here but deliberately deferred —
see § Deferred.)

---

## Problem

Track 2 left four structural gaps that compound over time:

1. **Entity candidates accumulate with no exit.** Auto-extracted entities land as
   `confirmed: false`. There's no MCP tool to confirm or supersede them. Rheo can
   read them via `entity_search(unconfirmedOnly: true)` but can't act on them.
   The graph grows without any curation possible.

2. **Semantic duplicates are silent.** Two sessions that mention "Arowyn" and
   "Arowyn Goodwin" produce two separate entity records — the spec flagged this as
   EC-6 and deferred it. Without dedup signaling at extraction time, Robin will
   eventually face a graph full of near-duplicate entities with no way to tell which
   are real duplicates vs. distinct entities.

3. **Edges are second-class.** Relations between entities live in `properties.relations`
   on each entity record. This makes it impossible to supersede an individual edge,
   query edges independently, or track edge confidence separately from entity
   confidence. The spec called this out as a Track 3 promotion. *(Deferred — see § Deferred.)*

4. **The JSONL graph is write-only forever.** No compaction means the file grows
   unboundedly. On a large graph with many superseded records, `loadGraph()` gets
   slower because it scans every line. Compaction folds superseded chains and
   rewrites a canonical snapshot — but needs to be atomic and auditable.
   *(Deferred — see § Deferred.)*

Secondary gaps:
- `lib/backup.ts` backs up `mot.db` but not `graph.jsonl` — documented as a TODO
  in CLAUDE.md but not implemented.
- The 8 Track-2 MCP tools accept args and cast them but don't validate shapes.
  A caller passing a non-integer `id` to `procedural_note_confirm` gets a
  runtime error inside the lib function rather than a clean `{error: 'invalid_arg'}`.

---

## What's in scope

Items 1 and 2 above shipped. Items 3 and 4 are deferred (see § Deferred).

### Entity confirmation tools (MCP surface)

Two new MCP tools:

**`entity_confirm(id)`** — sets `confirmed: true` on the entity record by appending a
`ConfirmPatch` (`op: 'confirm', id, ts`) to `graph.jsonl`. The entity's `id` stays
the same; `loadGraph` folds the patch to flip `confirmed`. Rheo calls this after
Robin reviews a candidate.

Error returns (AC-12: no throw): `{error: 'not_found'}`, `{error: 'already_confirmed'}`.

**`entity_supersede(id, superseded_by_id)`** — marks `id` as superseded by
`superseded_by_id` by appending a SupersessionPatch. Used when two entities turn
out to be the same person/thing (the dedup resolution step). Returns `{error:
'not_found'}` or `{error: 'target_not_found'}` as needed.

Both follow the AC-12 contract: return typed `{error}` as `isError:false`, never throw.

### Semantic dedup at extraction (EC-6)

In `lib/extraction.ts`, after an entity is resolved for appending: scan active
entities of the same `type` whose label has edit distance ≤ 2 from the incoming
label (Levenshtein — `lib/levenshtein.ts`, no external library). Also catches
prefix/suffix matches (e.g. "Arowyn" vs "Arowyn Goodwin") with a minimum-length
floor (shorter label ≥ 4 chars). If a probable duplicate is found:

- Add `probable_duplicate_of: [id, ...]` to the incoming entity's `properties`.
- Do NOT merge or suppress — append both and let Robin resolve via `entity_supersede`.

### First-class edge records *(deferred — see § Deferred)*

### JSONL compaction *(deferred — see § Deferred)*

### Arg-shape validation

Add a thin validation layer in `callMcpTool` before dispatch — validate required
args are present and of the right type, return `{error: 'invalid_arg', arg: '...'}` 
for bad input. Covers all Track-2 tools that accept typed args (hand-rolled static
table; Zod reuse assessed and rejected as strictly more code). Doesn't touch the
three tools that already validate with Zod (`mot_create_ticket`, `mot_update_ticket`,
`write_memory`).

### `lib/backup.ts` extension

Extend `scheduleNightly()` to copy `graph.jsonl` to the same backup destination
as `mot.db`. Uses `MOT_GRAPH_PATH` env var. Wrapped in its own try/catch so a
graph-copy failure never aborts the DB backup. `backupGraph(backupDir)` is a named,
tested export mirroring `vacuumInto`.

---

## Architecture notes

- All new MCP tools follow AC-12: return typed `{error}` objects, never throw.
- `ConfirmPatch` is a distinct `op:'confirm'` shape — NOT SupersessionPatch reuse.
  Reusing SupersessionPatch with `old===new` would corrupt chain-walkers. One new
  discriminator branch in `loadGraph`.
- Edit-distance dedup scan at extraction time: only active entities of the same type.
  Emit a `console.warn` at ≥ 1000 entities; never skip. Same-batch asymmetry is
  by design: `appendEntity` writes immediately; the next entity's scan re-reads the
  file and sees the just-appended entity.
- `loadGraph()` is a private (non-exported) function. Track 3 adds one new fold
  branch (`op === 'confirm'`) but does NOT extract a `loadRecords()` helper and does
  NOT add a `record_type:'edge'` branch (both cut with edges/compaction).

---

## New MCP tools

| Tool | Args | Notes |
|------|------|-------|
| `entity_confirm` | `id: string` | Sets confirmed:true via ConfirmPatch |
| `entity_supersede` | `id: string, superseded_by_id: string` | Appends SupersessionPatch |

`graph_compact` was scoped here but is deferred to Track 4 (see § Deferred).
`memory-track1.test.ts` EXPECTED_MCP_TOOLS updated to include the 2 new names.

---

## Success criteria

- `entity_confirm(id)` sets `confirmed:true` on a candidate — verifiable via
  `entity_search(unconfirmedOnly: true)` no longer returning it.
- `entity_supersede(id, target)` causes `id` to no longer appear in
  `entity_search` results, while `target` still does.
- Extraction of a label within edit distance ≤ 2 of an existing same-type entity
  adds `probable_duplicate_of` to the new record's properties.
- Extraction of a label that is a prefix/suffix of an existing same-type entity's
  label (shorter label ≥ 4 chars) also adds `probable_duplicate_of`.
- `lib/backup.ts` copies `graph.jsonl` alongside `mot.db` in the nightly job.
  Absent `graph.jsonl` logs a warn and proceeds; no error.
- All Track-2 MCP tools return `{error: 'invalid_arg'}` on bad arg types rather
  than a runtime error inside the lib function.
- Full check gate green: `npm run typecheck`, `npm test`, `npm run lint`, `npm run build`.

---

## Deferred

**First-class edge records.** Promoting `properties.relations` arrays to standalone
`EdgeRecord` lines in `graph.jsonl` was the riskiest call in the original design.
No code in the repo writes `properties.relations`; `lib/extraction.ts` never sets
it. There is no edge producer and no consumer — the machinery would be dead on day
one. Edge supersession against a shared cuid2 namespace was also the Architect's
own highest-risk call. Deferred: build when a real relation producer exists in the
extraction pipeline.

**JSONL compaction (`graph_compact`).** The `lib/graph-compact.ts` module and the
`graph_compact` MCP tool are deferred to Track 4. The graph is days old and
single-user; `lib/graph.ts:98` already log-warns at 5 MB, which is the just-in-time
trigger. Compaction is the highest-risk operation (live data rewrite, no file lock,
data-loss window during the rename), so building it before the trigger fires is not
justified. Track 4's nightly maintenance step builds `compactGraph()`, gated behind
the 5 MB file-size check so it is a no-op until the graph is actually large.

---

## Open questions

**Edit distance threshold** — resolved: ≤ 2 for typo-like duplicates; prefix/suffix
heuristic (shorter label ≥ 4 chars) catches the "same person, shorter label" case.
Both gates are OR'd (FR-5).

**Edge record migration** — moot until an edge producer exists. When one does, old
entity records encoding relations in `properties.relations` will need a compatibility
shim or a one-time backfill. The question remains open but is not Track 3's problem.

**`graph_compact` as MCP vs. script** — deferred to Track 4 to decide. A MCP tool
is convenient; a standalone script is safer for a privileged, potentially slow
operation. Track 4 may ship both.

**mention_count on entities** — not added in Track 3. Deferred to Track 4 when
confidence evolution becomes relevant.
