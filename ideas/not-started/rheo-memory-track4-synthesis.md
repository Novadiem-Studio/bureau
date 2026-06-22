# Rheo Memory Track 4 — Synthesis & Proactive Recall

Date: 2026-06-22
Status: not started
Depends on: Track 3 shipped (entity confirmation + graph quality)

---

## One-liner

Give Rheo a single context-boot call, cross-session synthesis per topic thread,
scheduled maintenance, and a MOT web UI for browsing the Recallatron.

---

## Problem

Track 2 gave Rheo the tools to read memory. Track 3 makes the data trustworthy.
Track 4 makes it actually work in practice — without Robin having to know which
tools to prompt Rheo to call or remember to ask for a topic summary.

Three distinct problems:

**1. Memory boot is a multi-tool ceremony.**
At the start of each session, Rheo currently has to call `memory_recent`, 
`topic_threads`, `procedural_notes_list`, and possibly `entity_search` separately,
then mentally assemble the context. The relevant thread and entities depend on the
conversation's opening message — but Rheo doesn't know which to fetch until the
conversation is underway, so it either fetches everything (noisy) or waits and
asks Robin (defeats the point). A single `memory_context(q)` call that returns a
ranked, relevance-filtered bundle solves this.

**2. Topic threads have no summary.**
A topic thread like `arowyn-school` might have 40 linked sessions spanning months.
Rheo can see the session list and fetch individual digests, but has no way to ask
"what has been established about this topic across all sessions?" without reading
40 digests in one prompt — which blows the context window. Track 2 laid the
thread/session structure; Track 4 needs the synthesis layer on top.

**3. Maintenance is manual or absent.**
- `graph.jsonl` grows forever without compaction (Track 3 adds `graph_compact`,
  but it's manual).
- Unconfirmed entity and procedural note candidates pile up with no pruning.
- Historical sessions (predating Track 2 activation) were never run through
  extraction — the entity graph and procedural memory have no knowledge of
  anything before the Track 2 go-live date.
- The MOT web app has no UI for Robin to browse or curate the Recallatron
  outside of MCP tool calls.

---

## What's in scope

### `memory_context(q?, chat_id?, limit?)` — context bundle

A new MCP tool that assembles a relevance-ranked memory bundle in one call.
Given an optional query string `q` (typically the first message of a session
or a topic keyword), returns:

```ts
{
  topics: TopicThread[],         // threads matching q, ordered by last_active_at
  entities: EntityRecord[],      // active entities matching q via searchEntities
  procedural: ProceduralNote[],  // confirmed procedural notes, optionally filtered
  recent_memory: MemoryRow[],    // recent memory_items, optionally FTS-filtered
}
```

Each section is independently limited (e.g. top 3 topics, top 5 entities, all
procedural notes, 10 recent memory items). Sections with no matches return empty
arrays, not errors. When `q` is absent, returns recent/active items across all
sections with no keyword filter.

Rheo calls this once at session start with the user's opening message as `q`.
The bundle is small enough to fit in Rheo's system prompt without bloat.

Implementation lives in `lib/memory-context.ts`; the function takes a db
instance and graph path, runs the four queries in parallel (Promise.all), and
assembles the bundle. The MCP dispatch in `callMcpTool` is a single `await`.

### `topic_thread_summarize(slug)` — cross-session synthesis

A new MCP tool that produces a concise summary of everything established about
a topic thread across all its linked sessions.

Process:
1. `getThread(slug)` — fetch thread + session list.
2. For each linked session, fetch the `summary` column from `session_digest`.
3. Build a prompt: summaries as numbered bullet context, ask the model to
   synthesize into a coherent overview of what's known, what's unresolved,
   and key entities/decisions.
4. Return the synthesized text.

The model call is a single `anthropic.messages.create` with `claude-haiku-4-5`
(cheap, fast; synthesis doesn't need reasoning) and a hard token cap. When the
total session summaries exceed the context budget, truncate to the most recent N
sessions and note the truncation in the output.

The result is NOT stored — it's generated on demand. Robin or Rheo may want to
cache it manually as a memory item, but auto-storage risks stale summaries.

### Scheduled maintenance

A nightly job (extending the existing `scheduleNightly` in `lib/backup.ts`) runs:

1. **Backup** — `mot.db` + `graph.jsonl` (already in Track 3).
2. **Prune stale candidates** — delete `procedural_notes` rows where
   `confirmed = false` AND `created_at < now - 30 days` AND `mention_count <= 1`.
   Append a SupersessionPatch (not a deletion) for unconfirmed entity candidates
   older than 30 days with no relations and `confidence < 0.85` — mark them
   superseded by a sentinel `id: 'pruned'` so the graph stays append-only.
3. **Compact graph** — call `compactGraph()` from `lib/graph-compact.ts`
   (Track 3). Run after prune so pruned records don't appear in the compacted
   file.

The nightly job logs each step's outcome to `console.log` with `[MOT/nightly]`
prefix (same pattern as other lib logging).

### Historical session backfill

A one-shot script `scripts/backfill-extraction.ts` that:

1. Queries all `session_digest` rows where `parse_error = 0` AND created before
   a given cutoff date (passed as a CLI arg, defaults to Track 2 go-live date).
2. For each row, calls `runExtraction(row)` from `lib/extraction.ts`.
3. Logs progress (row count, entities appended, notes inserted, skipped) to stdout.
4. Safe to re-run: `runExtraction` already deduplicates procedural notes; entity
   records with duplicate labels get the same `probable_duplicate_of` treatment
   as real-time extraction.

This is a script, not a cron or API route. Run manually via
`npx tsx scripts/backfill-extraction.ts --before 2026-06-22`.

### MOT web UI — Recallatron browser

Read-only browsing surfaces in the MOT Next.js app. Three pages:

**`/memory/entities`** — entity graph browser.
- Search box → calls `entity_search` (client-side MCP or direct API).
- Results list: label, type, confidence, confirmed badge.
- Click entity → detail panel: properties, relations (edges), supersession chain.
- Filter: all / confirmed-only / unconfirmed-only.

**`/memory/topics`** — topic thread list.
- Shows all threads, ordered by `last_active_at`.
- Click thread → session list with summaries. "Synthesize" button calls
  `topic_thread_summarize` and renders the result inline.

**`/memory/procedural`** — procedural notes curation.
- Two tabs: Confirmed / Pending.
- Pending tab: each candidate shows note text, category, source session, mention
  count, and a "Confirm" button (calls `procedural_note_confirm`).
- This is the only write surface in the UI; everything else is read-only.

Stack: follows MOT's existing React + Tailwind + ShadCN patterns. No new
dependencies. Direct DB reads via the existing `db` client (server components),
not via MCP tools — the UI is server-rendered, no API round-trip needed.

---

## Architecture notes

**`memory_context` parallelism** — the four sub-queries are independent. Run them
with `Promise.all` in the lib function to avoid serial latency. On a small dataset
the total call should be < 50ms.

**`topic_thread_summarize` and the model** — this is the only place in the MOT
codebase that calls an LLM at runtime (extraction is done by the bot, not MOT).
Use `claude-haiku-4-5-20251001` via the Anthropic SDK; it's already a dependency
of the bot but not MOT. If adding the SDK to MOT feels heavy, an alternative is
to make `topic_thread_summarize` return the raw session summaries as structured
data and let Rheo do the synthesis client-side. That defers the SDK dependency to
a future decision.

**Nightly prune — append-only invariant** — entity records are never deleted from
`graph.jsonl`. Pruning writes a SupersessionPatch with `superseded_by: 'pruned'`.
The `loadGraph` function already handles this sentinel: records with any
non-null `superseded_by` are excluded from active results. A fresh agent reading
the graph sees no pruned records; the full audit history is preserved.

**UI auth** — the Recallatron browser pages are inside the MOT app which uses
`NEXT_PUBLIC_MOT_API_KEY`-gated routes. The procedural note confirm button calls
the existing `procedural_note_confirm` MCP tool via the authenticated MCP
endpoint. No new auth surface.

---

## New MCP tools

| Tool | Args | Notes |
|------|------|-------|
| `memory_context` | `q?: string, chat_id?: string, limit?: number` | Context bundle |
| `topic_thread_summarize` | `slug: string` | On-demand synthesis; not stored |
| `graph_compact` | none | Admin; already in Track 3 but listed here for completeness |

---

## Success criteria

- `memory_context("arowyn school")` returns relevant topic threads, entities,
  and procedural notes in a single call with no more than 3 tool hops.
- `topic_thread_summarize("arowyn-school")` returns a coherent prose summary
  of sessions linked to that thread — not a raw list of digests.
- Nightly job prunes unconfirmed procedural note candidates older than 30 days
  with `mention_count <= 1`; confirmed notes are untouched.
- `scripts/backfill-extraction.ts` processes all pre-Track-2 digests without
  error and produces entity + procedural note candidates that pass the 91-test
  regression suite unchanged.
- `/memory/entities` renders the entity list, entity detail panel, and
  unconfirmed filter without errors.
- `/memory/procedural` confirm button calls the MCP tool and reflects the
  updated confirmed status without page reload.

---

## Open questions

**Should `topic_thread_summarize` store its output?**
Generating on demand is clean but expensive if the thread has 40+ sessions.
An alternative: write the synthesis to a `summary` column on `topic_thread` and
cache it until a new session is linked (at which point mark it stale). Adds
schema complexity but saves repeated model calls. Decide based on observed
usage — start on-demand, add caching if Rheo calls it more than once per session.

**Anthropic SDK in MOT**
MOT is currently a pure Next.js app with no LLM calls. Adding the SDK for
`topic_thread_summarize` is one new dependency and sets a precedent. If Robin
prefers to keep MOT model-free, route the synthesis through the bot: the MCP
tool returns structured session data, and Rheo synthesizes. Both approaches are
valid — the key is making the decision explicit before Track 4 build starts.

**UI framework choice for Recallatron pages**
The entity graph browser with a detail panel and relation traversal will feel
much better as a client-side component (React state for selection, panel
animation) than a server-rendered page. That means either a hybrid (server-fetch,
client-render) or a thin API endpoint. Check whether the MOT app's existing
interactive pages (ticket list, status dashboard) set a pattern to follow.

**Backfill ordering**
`runExtraction` is designed for one digest at a time. Running it on 200 historical
digests serially is safe but slow (~1–2 seconds each if the extraction involves
regex + DB writes). A batch mode that processes them in parallel (bounded
concurrency via a simple semaphore) would finish in seconds rather than minutes.
Worth adding to the backfill script if the digest history is large.

**Historical dedup explosion**
The backfill will likely surface many near-duplicate entities (the same person
mentioned in 50 sessions before Track 2). The `probable_duplicate_of` flagging
from Track 3 helps, but Robin may end up with a large unconfirmed queue to
review. Consider adding a dry-run mode to the backfill script that reports
estimated entity counts and duplicate collisions before writing anything.
