# Rheo — Persistent Chat Memory

Date: 2026-06-15
Status: Tracks 1–4 shipped. Track 1 (session digests/memory): 2026-06-17. Track 2 (Recallatron entity/topic/procedural graph): 2026-06-22. Track 3 (entity curation + graph backup): 2026-06-22. Track 4 (memory_context + nightly maintenance + UI browsers + backfill): 2026-06-23, deployed + prod backfill run.

Framework-side integration checklist: [Rheo memory framework integration](../agent-framework/07-rheo-memory-framework-integration.md).

## Current execution boundary

This idea has already started. Treat the existing MOT diff as implementation work that needs
to be pulled back under the Bureau:

1. Run a cold Challenger review on the current Layer 0 + Layer 4 diff.
2. Route any blockers to the correct coder.
3. Hand the deploy/build/restart steps to The Mechanic under the production/external-action
   boundary.
4. Only after that, promote Phase 2 memory work (digests, topics, graph, procedural notes).

## Local / remote boundary

The Bureau framework currently lives in the local development workspace. Rheo memory lives in
the remote MOT/Rheo agent runtime. They are expected to converge, but not by blurring runtime
ownership:

- The local framework may review, plan, and produce prompts/runbooks for memory work.
- The remote MOT/Rheo runtime owns the actual memory ledger, MCP tools, bot integration, and
  service restarts.
- Any framework-facing memory integration should begin read-first, with provenance and
  confidence attached to retrieved facts.
- Writes from framework workflows into remote memory must stay deny-by-default until there is
  an explicit adapter, write contract, conflict behavior, and audit trail.
- Shared artifacts are the bridge for now: Challenger findings, deploy records, memory
  receipts, `output/studio/lessons.md`, and future accounting fields.

## Production track

This is the longer production track that absorbs the useful framework/memory concepts while
keeping local framework and remote agent runtime separate.

### Track 1 — Session digests and safe writes (SHIPPED 2026-06-17)

First compressed episodic layer and write discipline:

1. `session_digest` table — `session_id`, `chat_id`, `summary`, `ts`, `topics`, `entity_draft`, `procedural_raw`, `parse_error`, `turn_count`.
2. Digest pass at session boundary or on demand via `summarize_and_archive`.
3. `write_memory` tool for explicit memory commits.
4. Candidate extraction for entities and procedural notes; candidates stay reviewable.
5. Memory receipts for writes: source turn/session, confidence, timestamp, write reason.
6. Conflict behavior for high-risk writes: version, flag, or require review; no silent overwrite.

MCP tools delivered: `chat_log_turn`, `chat_recent`, `chat_search`, `summarize_and_archive`, `write_memory`, `memory_recent`.

### Track 2 — Topics, graph skeleton, and procedural memory (SHIPPED 2026-06-22)

Once digests are reliable:

1. Topic threads (`topic_thread` table with `slug / title / notes / created_at / last_active_at`, plus `topic_thread_session` join table).
2. JSONL entity graph (`ontology/graph.jsonl`) for Person, Project, Deadline, Preference, and Fact.
3. Basic graph traversal tools: `entity_get`, `entity_search`, `entity_related`.
4. Procedural notes as first-class memory (`procedural_notes` table).
5. Session-boundary automation with a conservative prompt and confidence thresholds.
6. Post-digest extraction pass: `lib/extraction.ts` populates entity draft and procedural candidates from each new digest.

MCP tools delivered: `topic_threads`, `topic_thread_create`, `topic_thread_link`, `entity_get`, `entity_search`, `entity_related`.

### Track 3 — Entity curation + graph backup (SHIPPED 2026-06-22)

When conflict handling justifies it:

1. `entity_confirm` and `entity_supersede` curation tools (the real curation surface — `edit_fact` and `consolidate_entities` are NOT built).
2. `ConfirmPatch` shape appended to `ontology/graph.jsonl` — append-only, never rewritten in place.
3. `probable_duplicate_of` dedup signal + Levenshtein utility.
4. `backupGraph()` in nightly cron.

MCP tools delivered: `entity_confirm`, `entity_supersede`.

### Track 4 — Memory context bundle + nightly maintenance + UI browsers (SHIPPED 2026-06-23)

1. `memory_context` boot bundle — one-call `{ topics, entities, procedural, recent_memory }` with optional relevance filtering.
2. `graph_compact` MCP tool — on-demand compaction.
3. `topic_thread_summarize` MCP tool — structured, model-free thread summary.
4. Nightly maintenance (02:00 cron): SQLite VACUUM backup, graph JSONL backup, procedural prune, entity prune, conditional graph compaction (only if ≥5 MB).
5. Historical backfill script (`scripts/backfill-extraction.ts` / `npm run backfill`) — idempotent, ran in production.
6. Session-authed REST routes: `/api/memory/entities`, `/api/memory/procedural/confirm`, `/api/memory/topics/[slug]/summarize`.
7. UI browser pages: `/memory/entities`, `/memory/procedural`, `/memory/topics` (session-gated).

MCP tools delivered: `memory_context`, `graph_compact`, `topic_thread_summarize`.

### Future — not yet tracked

The following capabilities are genuinely future and have no code yet:

- **Vector / semantic retrieval**: sqlite-vec, embedding column, hybrid `fts + vector + graph` search. All search today is FTS5 keyword or substring — no `embedding` column exists anywhere.
- **Full SQLite adjacency tables for the graph**: JSONL stays until query volume warrants migration.
- **Proactive surfacing**: Rheo noticing dated entities and surfacing them unprompted.
- **Cross-channel ingestion**: Gmail routines → entity graph.
- **Decay/staleness scoring**: confidence decay on time-sensitive facts.
- **Evals and benchmarks**: recall accuracy, false-write rate, conflict-handling quality.
- **Framework memory adapter**: local Bureau write authority, narrowly scoped and deny-by-default.

Do NOT invent a "Track 5" — these items are future work without assigned track numbers.

## Framework integration rules

These rules connect the remote memory track to the local Bureau roadmap:

- **Bundle 01:** memory tool preflight checks remote reachability and schema/tool availability.
  Persistent memory writes are durable state mutations, not ordinary local notes.
- **Bundle 02:** memory may surface candidate lessons, but only the framework learning loop
  promotes canon into `docs/conventions.md`, runbooks, or `output/studio/lessons.md`.
- **Bundle 03:** memory can close planning assumptions only when the artifact cites source,
  confidence, timestamp, and stale-sensitivity.
- **Bundle 04:** run accounting should track memory retrieval count, writes proposed/accepted,
  conflicts flagged, digest freshness, and memory preflight status when applicable.
- **Bundle 05:** external notary review (The Notary) gets no memory by default. Any memory excerpt must be
  explicitly allowlisted with provenance.
- **Bundle 06:** local runtime is allowed to experiment with digesting and candidate extraction
  only after remote memory accounting proves the workload and quality bar.

The convergence rule: local framework artifacts may consume memory receipts, cited excerpts,
and accounting fields before they ever gain write authority. Write authority requires an
adapter, a write contract, conflict behavior, and an audit trail.

## Starting point — out-of-band work (2026-06-15)

Layer 0 + Layer 4 (v1) was built directly in the main session before this job was properly
queued. The new session inherits it. What's already done, untested by the framework:

- `mot/db/schema.ts` — `conversation` table added (6 cols, 2 indexes)
- `mot/db/migrations/0003_conversation.sql` — hand-written DDL
- `mot/db/migrations/0003_conversation_fts.sql` — FTS5 virtual table + insert trigger
- `mot/db/client.ts` — `0003_conversation_fts.sql` registered in `HAND_WRITTEN_MIGRATIONS`
- `mot/lib/conversation.ts` — `logTurn`, `getRecentTurns`, `searchTurns` with 2h session gap detection
- `mot/app/api/conversation/route.ts` — `POST` (log turn) + `GET` (recent / keyword search)
- `mot/lib/mcp-tools.ts` — 3 new tools: `chat_log_turn`, `chat_recent`, `chat_search`
- `mot/bot/bot.py` — in-memory deque replaced with `fetch_history()` / `log_turn()` calls to MOT

TypeScript type-check and full test suite (91 tests) pass. Code rsynced to server.
**Not done at time of writing:** server build and service restarts had not been run.

The framework session should: run The Challenger on the diff, route any blockers, then hand
the deploy to The Mechanic.

---

## One-liner

Give Rheo a layered, agent-managed memory system — raw turns, session digests, a semantic
entity graph, and MCP tools Rheo actively drives — so he remembers across restarts, retrieves
only what's relevant to the current question, and builds up a durable model of Robin's
people, projects, and recurring concerns over time.

---

## Problem

Rheo currently holds a rolling 12-message in-memory buffer (per chat_id, lost on restart)
and has zero cross-session memory. He can see open MOT tickets injected into each prompt,
but he has no way to ask "what did we discuss about Arowyn's school last week?" or "did
Robin ever mention that deadline?" A restart is a total amnesia event.

The naive fix — inject the last N raw turns — hits two walls fast: tokens and coherence.
Beyond ~20 turns the signal-to-noise drops and the model loses the thread. Injecting
everything on boot is expensive and often irrelevant.

What's needed is a system where Rheo actively decides what to retrieve, compress, and
update — not one where the bot mechanically pre-injects a fixed window. The research
analogues (MemGPT/Letta for paging, Mem0 for fact consolidation, Zep/Graphiti for
temporal graphs, GraphRAG for hybrid retrieval) all point the same direction: the agent
should manage memory, not just consume it.

---

## Cognitive Memory Model

Three types, borrowed from cognitive science and adapted to this domain:

| Type | What it stores | Storage home | Retrieval |
|------|---------------|--------------|-----------|
| **Episodic** | Raw turns + session digests — what happened, when | `conversation` + `session_digest` tables | Recency, FTS5 keyword |
| **Semantic** | Facts about the world — people, projects, deadlines, preferences | Entity graph (`ontology/graph.jsonl`) + `memory_items` SQL table | Substring search, graph traversal; vector/semantic is future |
| **Procedural** | Recurring patterns — how Robin likes things done, templates, preferences, routines | `procedural_notes` table | Keyword or category lookup |

These are not separate systems — they're three query modes over related data. A single
conversation turn may generate an episodic record, update a semantic entity, and refine a
procedural note.

---

## Architecture: Merged Layers

```
Layer 0 — Ledger          raw turns (append-only)
Layer 1 — Digests         session summaries + entity extraction
Layer 2 — Topics          recurring concern threads, auto-linked
Layer 3 — Entity Graph    people / projects / deadlines with temporal edges
Layer 4 — MCP Surface     tools Rheo calls to read and write all of the above
```

---

## Detailed Layer Descriptions

### Layer 0 — Ledger (episodic raw store)

Append-only SQLite table in MOT's database. No row is ever deleted or updated in place.

```
id          integer   primary key, autoincrement
chat_id     text      Telegram chat ID (identifies the user/conversation)
session_id  text      groups turns within a continuous session
role        text      'user' | 'rheo'
content     text      full message text, no truncation
ts          text      ISO 8601 datetime
```

FTS5 virtual table `conversation_fts` + AFTER INSERT trigger (append-only; no update/delete trigger).

Note: there is NO `embedding` or `ticket_id` column in the real migration (`0003_conversation.sql`). Vector search is not built.

### Layer 1 — Session Digests (episodic compressed)

At each session boundary (detected by a >2h gap or explicit signal), a digest pass runs:

- One `claude -p` call over the session's raw turns.
- Output: 3–5 sentence summary + extracted candidate entities/relations + procedural notes.
- Stored in `session_digest`; candidates fed into the entity graph (Layer 3) pending review.

Real schema (from `0003_complex_roxanne_simpson.sql`):

```
id              integer   primary key, autoincrement
session_id      text      unique
chat_id         text
summary         text
ts              text
topics          text      (nullable)
entity_draft    text      (nullable) — JSON blob for entity extraction input
procedural_raw  text      (nullable) — JSON blob for procedural extraction input
parse_error     integer   default false
turn_count      integer
```

The `summarize_and_archive` MCP tool triggers this pass on demand. Reading digests is via the REST route `GET /api/conversation/digests` — there is no `session_digests` MCP tool.

### Layer 2 — Topic Threads (episodic indexed)

Recurring concerns extracted from digest topics and linked to sessions. Real schema (from `0004_topic_threads.sql`):

```
slug            text   primary key
title           text
notes           text   (nullable)
created_at      text
last_active_at  text
```

Plus join table `topic_thread_session` (`slug`, `session_id`, `added_at`). Labels are canonical slugs. The `topic_thread_summarize` tool/route returns structured JSON — model-free.

Note: the earlier planning doc showed `id / label / description / last_seen / session_ids`. The real schema uses `slug` as PK and a join table, not a comma-separated `session_ids` column.

### Layer 3 — Entity Knowledge Graph (semantic + temporal)

Two distinct semantic stores:

**1. `memory_items` SQL table** (Track 1) — typed facts written via `write_memory`, with `type`, `label`, `label_norm`, `confidence`, `reason`, `superseded_by`. Conflict detection is label-normalized only. FTS5 index (`memory_items_fts`) for keyword search.

**2. Entity graph JSONL** (`ontology/graph.jsonl`, Track 2+) — append-only, gitignored. Entity record shape:
```json
{
  "id": "e_arowyn",
  "type": "Person",
  "label": "Arowyn",
  "properties": { "relations": [] },
  "valid_from": "2026-06-17T00:00:00Z",
  "valid_until": null,
  "confidence": 0.95,
  "source": "session:sess_20260617",
  "superseded_by": null,
  "confirmed": false
}
```
Entity types: `Person | Project | Deadline | Preference | Fact`. Relations live at `properties.relations[]` as `{rel, target_id}` — not a separate edge table. Patch records (`op: 'supersede'` and `op: 'confirm'`) share the same file.

Note: the earlier planning doc showed an `op:create/relate` edge model and separate edge records. The real format is entity records + patch records only — no `op:create`, no separate edge records. Relations are embedded in entity properties and are currently sparsely populated.

Conflict handling: versioned, not overwritten. Every fact carries `source` and optionally `superseded_by`. The curation tools are `entity_confirm` and `entity_supersede` — NOT `edit_fact`, `consolidate_entities`, or `flag_conflict` (those don't exist).

### Layer 4 — MCP Surface (agent-managed)

26 MCP tools at `POST /api/mcp` (Streamable HTTP JSON-RPC, Bearer-auth or session cookie). Rheo calls these to read and write all layers above.

**Retrieval tools (built):**

```
chat_recent            last N turns from the ledger
chat_search            FTS5 keyword search — one mode only (no vector/hybrid)
topic_threads          list threads or get sessions linked to a specific topic
entity_get             fetch one entity with all its properties
entity_search          case-insensitive substring search
entity_related         graph traversal from a seed entity
memory_context         boot bundle: { topics, entities, procedural, recent_memory }
topic_thread_summarize structured, model-free summary of a thread's linked sessions
```

**Memory management tools (built):**

```
chat_log_turn          append a turn to the ledger
write_memory           commit a new memory item
summarize_and_archive  trigger a digest pass on a session
entity_confirm         confirm a pending entity
entity_supersede       mark one entity superseded by another
graph_compact          trigger graph compaction
topic_thread_create    create a new topic thread
topic_thread_link      link a session to a thread
procedural_notes_list  list procedural notes by category
procedural_note_confirm confirm a procedural candidate
memory_recent          return recent or keyword-searched memory items
notify_robin           send a push notification
```

**NOT built — remove from any planning doc that still lists them:**
- `edit_fact` — ABSENT everywhere in the codebase
- `consolidate_entities` — ABSENT
- `flag_conflict` — ABSENT
- `session_digests` as an MCP tool — ABSENT (the REST route `GET /api/conversation/digests` covers this read)
- `chat_search` vector/hybrid mode — ABSENT (FTS5 only)

**Hybrid retrieval (future):** vector search requires sqlite-vec, an `embedding` column in at least one table, and a new `chat_search` mode. None of this is built. Keep it as a clearly-labeled future capability.

---

## Hybrid Retrieval Strategy (FUTURE — NOT BUILT)

Three retrieval modes are envisioned for the future:

| Mode | When to use | Implementation |
|------|-------------|----------------|
| **Keyword (FTS5)** | Exact phrases, names, ticket IDs | Built: SQLite FTS5 on `conversation` + `memory_items` |
| **Vector (semantic)** | "what did we talk about re: cash flow?" | Future: sqlite-vec; requires embedding column and embed-at-write pipeline |
| **Graph traversal** | "what deadlines does Arowyn have?" | Built: walk entity graph via `entity_related` |

**Hybrid search** (FTS + vector + graph expansion) is future. `chat_search(mode: "vector")` and `chat_search(mode: "hybrid")` are not implemented.

---

## Boot Context

On bot startup (or per-turn via `memory_context`), inject only:
- **`memory_context` result** — 3 topics, 5 entities, all confirmed procedural notes, 10 recent memory items, optionally relevance-filtered by query
- **Open MOT tickets** (already in place)

That's it. Rheo calls memory tools on demand for everything else.

---

## Conflict Handling

Versioned, not overwritten. Every fact carries `source` and optionally `superseded_by`.

| Conflict type | Action |
|--------------|--------|
| Same fact, minor wording change | Agent consolidates quietly, logs in entity history |
| Same fact, different value (e.g. deadline date changed) | Keep both, old gets `superseded_by`, confidence on new set to 0.8 |
| Directly contradictory facts (high confidence, opposing claims) | Both kept, flagged for review — use `entity_supersede` or a note in entity properties |
| Robin explicitly corrects something | `entity_supersede` called, old version preserved, confidence on new set to 1.0 |

The agent never auto-resolves a high-confidence contradiction. Low-confidence candidates
(extracted from conversations, not manually confirmed) can be quietly revised.

## Regression and evaluation harness

Memory needs a lasting harness, not one-off smoke checks. Regression fixtures live in `.bureau/regression/` (tracked in git):

- `01-migrations.md`, `02-graph.md`, `03-topics.md`, `04-extraction.md`, `05-mcp-tools.md`, `06-entity-curation.md`, `07-graph-backup.md`

Future eval targets:
- **Recall checks:** known phrase, known person, known deadline, known project, and known preference can be retrieved after restart.
- **Digest checks:** a sample session produces summary, entity candidates, and procedural candidates without inventing facts.
- **Conflict checks:** changed deadline preserves the old value with provenance.
- **Noise checks:** pleasantries and speculation do not create memory writes.
- **Staleness checks:** stale-sensitive facts are marked for review instead of treated as live forever.

---

## Prompts & Extraction Guidelines

### Digest prompt (runs at session boundary)

```
You are summarizing a Rheo/Robin conversation session for long-term memory.

Session turns:
{raw_turns}

Output JSON with three keys:
- "summary": 3–5 sentence human-readable summary of what was covered and decided
- "entities": array of candidate entity updates — each: { type, label, properties, relations[] }
- "procedural": array of candidate notes about Robin's preferences or recurring patterns
  e.g. { "note": "Robin prefers short bullet replies for ticket lists", "confidence": 0.7 }

Be conservative with entities — only include things clearly stated, not inferred.
Flag uncertainty with confidence < 0.8.
```

### Memory write prompt (inline, when Rheo decides to write)

Rheo should call `write_memory` at end of turn when:
- A new person, project, or deadline is mentioned for the first time
- A deadline, preference, or standing fact is explicitly stated or confirmed
- Robin corrects something Rheo said about the world

Rheo should NOT write:
- Speculation or things Robin said might change
- Things already in MOT tickets (the ticket is the record)
- Conversational pleasantries

---

## Open Questions / Trade-offs

**sqlite-vec vs pgvector**
sqlite-vec keeps everything in one SQLite file (simpler ops); pgvector requires Postgres
but is already on the Oriva stack. If MOT ever migrates to Postgres, pgvector is the
natural choice. For now, sqlite-vec is the right call when/if vector retrieval ships.

**Who runs the digest pass?**
Currently: Rheo calls `summarize_and_archive` explicitly, or the post-digest extraction pass
in `lib/extraction.ts` runs after each new digest. A Claude.ai routine on a schedule is
also viable for reliability.

**How does Rheo know when to write memory vs. when to just answer?**
System prompt instruction + examples. The pattern from MemGPT: after every assistant turn,
there's an implicit "should I update memory?" check.

**Ontology JSONL vs dedicated SQLite table**
JSONL is fine while the graph is small (<1,000 entities) and query patterns are simple.
The 5 MB size guard and nightly compaction keep it manageable. Migration to a SQLite
adjacency table is a future option when traversal becomes a hot path.

**Privacy**
All memory is local (MOT's SQLite on rheo.ca). No external service sees it. The bot and
`claude -p` do pass content to Anthropic APIs during digesting — same as any conversation.
No special handling needed beyond what's already in place.

**Memory rot**
Facts become stale. A "Nutrifax has 3 paying customers" fact from six months ago may be
wrong today. Mitigation: nightly prune drops stale unconfirmed low-confidence entities.
Explicit staleness-decay on time-sensitive facts is future.

---

## Stack

- **Next.js 14** (`^14.2.35`) — not 15
- **better-sqlite3** `^11.10.0` + Drizzle ORM `^0.29.5` + FTS5 (SQLite built-in)
- **Single process, single SQLite file** (`mot.db`, WAL mode)
- **Auth:** API key (Bearer, argon2-hashed) OR session cookie (iron-session)
- **Cron:** node-cron `^4.2.1`
- **Bot:** separate repo `rheos/rheo-bot`, deployed at `/opt/rheo-bot` on rheo.ca Lightsail, systemd service `telegram-bot`, webhook `tg.rheo.ca/telegram` — NOT inside the mot repo

---

## Success Criteria

- Rheo can recall cross-session details through tools without injecting large raw history.
- Remote memory survives service restarts and returns cited, timestamped results.
- Memory writes carry source, confidence, reason, and conflict behavior.
- No high-confidence contradiction is silently overwritten.
- Memory-surfaced lessons can improve the Bureau, but only through the local framework's
  Challenger-checkable promotion path.
- Accounting can show whether memory improves resume speed, assumption reduction, and learning
  loop effectiveness.
- The local framework and remote memory runtime converge through explicit adapters and shared
  artifacts, not ambient access.

---

## Prior Art / Inspirations

- **MemGPT / Letta** — agent-managed memory paging; the model explicitly calls memory tools
  to page context in and out. Direct inspiration for the MCP tool approach.
- **Mem0** — fact extraction + consolidation from conversations; the `write_memory` pattern.
- **Zep / Graphiti** — temporal knowledge graph over conversation history; the
  `valid_from`/`valid_until` edge model and graph traversal.
- **GraphRAG** — hybrid retrieval combining vector search with graph traversal for
  multi-hop reasoning. (Future for Rheo.)
- **Oriva memoir memory** (`oriva/future-research/memoir-memory-storage-strategies.md`) —
  summary hierarchies (the digest layer), hybrid relational + vector approach, thematic
  thread entities, conflict-as-versioning rather than overwrite.

---

## Future Extensions

- **Proactive surfacing** — Rheo notices "you mentioned the ICBC renewal in September;
  that's 3 months away" without being asked, by running a background check on dated entities.
- **Cross-channel memory** — ingest signals from Gmail routines into the same entity graph,
  so Rheo's graph includes facts from email, not just Telegram conversations.
- **Vector / semantic retrieval** — sqlite-vec, embedding column, hybrid FTS + vector + graph.
- **Advanced evals** — recall accuracy, false-write rate, conflict handling quality (LongMemEval,
  LoCoMo benchmarks).
- **Framework memory adapter** — narrow read-first access for Bureau workflows, with a write
  contract, conflict behavior, and audit trail.
- **Visual canon representation** — memory conduits into The Archive, entity graph holograms,
  temporal flows. Poster updates are a visual follow-up, not a production blocker.
