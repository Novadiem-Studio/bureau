# Rheo Memory Track 3 — Curation & Quality

Date: 2026-06-22
Status: not started
Depends on: Track 2 shipped (2026-06-22)

---

## One-liner

Close the entity lifecycle loop, add semantic dedup at extraction time, promote
edges to first-class graph records, and keep the JSONL graph maintainable long-term.

---

## Problem

Track 2 left four structural gaps that compound over time:

1. **Entity candidates accumulate with no exit.** Auto-extracted entities land as
   `confirmed: false`. There's no MCP tool to confirm or supersede them. Rheo can
   read them via `entity_search(unconfirmed_only: true)` but can't act on them.
   The graph grows without any curation possible.

2. **Semantic duplicates are silent.** Two sessions that mention "Arowyn" and
   "Arowyn Goodwin" produce two separate entity records — the spec flagged this as
   EC-6 and deferred it. Without dedup signaling at extraction time, Robin will
   eventually face a graph full of near-duplicate entities with no way to tell which
   are real duplicates vs. distinct entities.

3. **Edges are second-class.** Relations between entities live in `properties.relations`
   on each entity record. This makes it impossible to supersede an individual edge,
   query edges independently, or track edge confidence separately from entity
   confidence. The spec called this out as a Track 3 promotion.

4. **The JSONL graph is write-only forever.** No compaction means the file grows
   unboundedly. On a large graph with many superseded records, `loadGraph()` gets
   slower because it scans every line. Compaction folds superseded chains and
   rewrites a canonical snapshot — but needs to be atomic and auditable.

Secondary gaps:
- `lib/backup.ts` backs up `mot.db` but not `graph.jsonl` — documented as a TODO
  in CLAUDE.md but not implemented.
- The 8 Track-2 MCP tools accept args and cast them but don't validate shapes.
  A caller passing a non-integer `id` to `procedural_note_confirm` gets a
  runtime error inside the lib function rather than a clean `{error: 'invalid_arg'}`.

---

## What's in scope

### Entity confirmation tools (MCP surface)

Two new MCP tools:

**`entity_confirm(id)`** — sets `confirmed: true` on the entity record by appending a
supersession-style patch to `graph.jsonl`. The entity's `id` stays the same; the patch
adds `confirmed: true`. Rheo calls this after Robin reviews a candidate.

Error returns (AC-12: no throw): `{error: 'not_found'}`, `{error: 'already_confirmed'}`.

**`entity_supersede(id, superseded_by_id)`** — marks `id` as superseded by
`superseded_by_id` by appending a SupersessionPatch. Used when two entities turn
out to be the same person/thing (the dedup resolution step). Returns `{error:
'not_found'}` or `{error: 'target_not_found'}` as needed.

Both follow the AC-12 contract: return typed `{error}` as `isError:false`, never throw.

### Semantic dedup at extraction (EC-6)

In `lib/extraction.ts`, after an entity is resolved for appending: scan active
entities of the same `type` whose label has edit distance ≤ 2 from the incoming
label (Levenshtein — no external library needed for short labels). If a probable
duplicate is found:

- Add `probable_duplicate_of: [id, ...]` to the incoming entity's `properties`.
- Set `confirmed: false` on the incoming entity (already the case, but make it
  explicit in the comment).
- Do NOT merge or suppress — append both and let Robin resolve via
  `entity_supersede`.

The scan uses `searchEntities` filtered by type, then a small in-process
edit-distance pass. No embedding model needed for this.

### First-class edge records

Promote entity relations from `properties.relations` arrays to standalone JSONL
records alongside entity records. New record shape:

```ts
interface EdgeRecord {
  record_type: 'edge'
  id: string           // ulid
  from_id: string      // entity id
  to_id: string        // entity id
  rel: string          // relation type, e.g. 'child_of', 'works_on'
  confidence: number
  confirmed: boolean
  source_session_id?: string
  created_at: string
  superseded_by?: string
}
```

`lib/graph.ts` gains `appendEdge`, `getEdgesFrom`, `getEdgesTo`, `supersedEdge`.
`relatedEntities` and `getEntity` use edge records for traversal when present;
fall back to `properties.relations` for records written before Track 3 (migration
compatibility, no backfill needed).

The `properties.relations` encoding on pre-Track-3 entities stays as-is — don't
rewrite old records.

### JSONL compaction

`lib/graph-compact.ts` — a standalone function (not called in request handlers):

1. Load all records from `graph.jsonl`.
2. Fold all supersession chains to canonical active records only.
3. Write to a temp file alongside `graph.jsonl`, then `fs.renameSync` (atomic on
   same filesystem).
4. The original file is moved to `graph.jsonl.bak-<timestamp>` before rename
   (one backup retained; prior bak removed).
5. A new MCP tool `graph_compact()` exposes this — admin/Robin-only, no Rheo
   auto-call.

### Arg-shape validation

Add a thin validation layer in `callMcpTool` before dispatch — validate required
args are present and of the right type, return `{error: 'invalid_arg', arg: '...'}` 
for bad input. Covers all Track-2 tools that accept typed args. Doesn't need a
schema library; the validation is simple enough to write inline.

### `lib/backup.ts` extension

Extend `scheduleNightly()` to copy `graph.jsonl` to the same backup destination
as `mot.db`. Use the `MOT_GRAPH_PATH` env var to resolve the path (mirrors
the test isolation pattern).

---

## Architecture notes

- All new MCP tools follow AC-12: return typed `{error}` objects, never throw.
- Edge records in `graph.jsonl` are differentiated by `record_type: 'edge'`.
  `loadGraph()` needs to route on this field — entity records have no
  `record_type` field currently, so the presence of `record_type: 'edge'` is
  sufficient disambiguation.
- Edit-distance dedup scan at extraction time: only scan active entities of
  the same type. The graph won't be large in early use; if it grows past ~10k
  entities this scan becomes a bottleneck — flag it with a count-based warning
  log at that point, don't optimize prematurely.
- Compaction should never run in a request handler. Expose it as a manual MCP
  tool and/or a separate script (`scripts/compact-graph.sh`).

---

## New MCP tools

| Tool | Args | Notes |
|------|------|-------|
| `entity_confirm` | `id: string` | Sets confirmed:true via patch |
| `entity_supersede` | `id: string, superseded_by_id: string` | Appends SupersessionPatch |
| `graph_compact` | none | Admin — rewrites canonical graph.jsonl |

Plus `memory-track1.test.ts` EXPECTED_MCP_TOOLS update to include the 3 new names.

---

## Success criteria

- `entity_confirm(id)` sets `confirmed:true` on a candidate — verifiable via
  `entity_search(unconfirmedOnly: true)` no longer returning it.
- `entity_supersede(id, target)` causes `id` to no longer appear in
  `entity_search` results, while `target` still does.
- Extraction of a label within edit distance 2 of an existing same-type entity
  adds `probable_duplicate_of` to the new record's properties.
- `graph_compact()` produces a file with no superseded records and the same set
  of active entity ids as before compaction.
- `lib/backup.ts` copies `graph.jsonl` alongside `mot.db` in the nightly job.
- All Track-2 MCP tools return `{error: 'invalid_arg'}` on bad arg types rather
  than a runtime error inside the lib function.

---

## Open questions

**Edit distance threshold** — the spec says < 3, meaning distance ≤ 2. Is that
right for names like "Arowyn" vs "Arowyn Goodwin"? Edit distance is 8 there —
the "same person with different label form" case isn't caught by edit distance
at all. A better heuristic might be: one label is a prefix/suffix of the other
with the same entity type, OR edit distance ≤ 2 for truly typo-like cases.
Worth discussing before implementing.

**Edge record migration** — old entity records encode relations in `properties.relations`.
Rheo's traversal code will need to handle both encodings for years. A one-time
backfill script (read old relations, append Edge records) would clean this up
but risks writing duplicate edges if re-run. Leave as compatibility shim for now
and revisit when the graph is larger?

**`graph_compact` as MCP vs. script** — a MCP tool is convenient but compaction
is a privileged, potentially slow operation. A script callable from the Mechanic
or via `! npx tsx scripts/compact-graph.ts` might be safer. Both could exist.

**mention_count on entities** — the column exists on `procedural_notes`, and the
extraction pipeline increments it on procedural duplicate skips. Entities don't
have an equivalent. Should Track 3 add entity mention tracking too, or defer to
Track 4 when it becomes relevant for confidence evolution?
