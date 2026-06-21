# Rheo — Persistent Chat Memory

Date: 2026-06-15
Status: in progress — Layer 0 + Layer 4 v1 built out of band; framework review/deploy pending.

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

### Track 0 - Stabilize what already exists

Layer 0 + Layer 4 v1 already exist out of band. Before any new memory layer is added:

1. Cold Challenger review of the MOT diff.
2. Route blockers to the correct coder.
3. Mechanic runs remote build and service restart steps under the production/external-action
   boundary.
4. Capture deploy record and memory smoke results.
5. Add a battle-test matrix for the current tools:
   - `chat_log_turn` records a user/assistant turn.
   - `chat_recent` returns the expected recent turns by chat/session.
   - `chat_search` finds exact text through FTS.
   - restart does not lose recall.

### Track 1 - Session digests and safe writes

Add the first compressed episodic layer and write discipline:

1. `session_digests` table or equivalent storage.
2. Digest pass at session boundary or on demand.
3. `summarize_and_archive` and basic `write_memory` tool.
4. Candidate extraction for entities and procedural notes, but candidates stay reviewable.
5. Memory receipts for writes: source turn/session, confidence, timestamp, and write reason.
6. Conflict behavior for high-risk writes: version, flag, or require review; no silent overwrite.

### Track 2 - Topics, graph skeleton, and procedural memory

Once digests are reliable:

1. Topic threads with canonical slugs.
2. JSONL entity graph for Person, Project, Deadline, Preference, and Fact.
3. Basic graph traversal tools: `entity_get`, `entity_search`, `entity_related`.
4. Procedural notes as first-class memory, not just buried digest text.
5. Session-boundary automation with a conservative prompt and confidence thresholds.

### Track 3 - Production graph and review surface

When query volume and conflict handling justify it:

1. Migrate JSONL graph to SQLite adjacency tables.
2. Add sqlite-vec for semantic retrieval, keeping FTS5 for exact recall.
3. Add hybrid retrieval (`fts` + vector + graph expansion).
4. Add a MOT review surface for conflicts, stale facts, candidate entities, and procedural notes.
5. Add decay/maintenance routines for stale-sensitive facts.
6. Integrate memory retrieval into planning and bug-fix workflows through cited excerpts only.

### Track 4 - Optimization and convergence

Only after the production graph is stable:

1. Proactive surfacing for dated entities and recurring obligations.
2. Cross-channel ingestion, such as Gmail routines, through the same write contract.
3. Evals and benchmarks for recall accuracy, false writes, conflict handling, and digest quality.
4. Local-runtime experiments for digesting or candidate extraction only after accounting shows
   cost/quality data.
5. A narrow framework-facing memory adapter: read-first, provenance-bearing, and deny-by-default
   for writes.
6. Archive and visual-canon representation once the system is real enough to depict: memory
   conduits into the Archive, entity graph views, and temporal flows. Poster updates are a
   visual follow-up, not a production blocker.

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
- `mot/db/migrations/0003_conversation.sql` — Drizzle-generated DDL
- `mot/db/migrations/0003_conversation_fts.sql` — FTS5 virtual table + insert trigger
- `mot/db/client.ts` — `0003_conversation_fts.sql` registered in `HAND_WRITTEN_MIGRATIONS`
- `mot/lib/conversation.ts` — `logTurn`, `getRecentTurns`, `searchTurns` with 2h session gap detection
- `mot/app/api/conversation/route.ts` — `POST` (log turn) + `GET` (recent / keyword search)
- `mot/lib/mcp-tools.ts` — 3 new tools: `chat_log_turn`, `chat_recent`, `chat_search`
- `mot/bot/bot.py` — in-memory deque replaced with `fetch_history()` / `log_turn()` calls to MOT

TypeScript type-check and full test suite (91 tests) pass. Code rsynced to server.
**Not done:** server build (`npm ci && NEXT_PUBLIC_BASE_PATH=/mot npm run build`) and service
restarts (`mot.service`, `telegram-bot.service`) have not been run. No Challenger review.

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
| **Episodic** | Raw turns + session digests — what happened, when | `conversations` + `session_digests` tables | Recency, keyword FTS, vector similarity |
| **Semantic** | Facts about the world — people, projects, deadlines, preferences | Entity graph (`ontology/graph.jsonl` or a dedicated table) | Graph traversal + vector |
| **Procedural** | Recurring patterns — how Robin likes things done, templates, preferences, routines | `procedural_notes` table or semantic layer | Keyword or category lookup |

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

Drizzle table in MOT's SQLite (`~/Code/novadiem/mot/db/schema.ts`). Append-only; no
row is ever deleted or updated in place.

```ts
export const conversation = sqliteTable('conversation', {
  id:         integer('id').primaryKey({ autoIncrement: true }),
  chat_id:    text('chat_id').notNull(),
  role:       text('role').notNull(),         // "user" | "assistant"
  content:    text('content').notNull(),
  ts:         text('ts').notNull(),           // ISO datetime
  session_id: text('session_id'),
  ticket_id:  text('ticket_id').references(() => ticket.id),
  embedding:  blob('embedding'),              // sqlite-vec blob — null until v2
});
// FTS5 virtual table + triggers in a hand-written migration (same pattern as ticket_fts)
```

The `embedding` column is nullable — the FTS5 layer handles v1 search; embeddings drop in
without a schema change when vector search is added.

### Layer 1 — Session Digests (episodic compressed)

At each session boundary (detected by a >2h gap or explicit signal), a digest pass runs:

- One `claude -p` call over the session's raw turns.
- Output: 3–5 sentence summary + extracted candidate entities/relations + procedural notes.
- Stored in `session_digests`; candidates fed into the entity graph (Layer 3) pending
  review.

```ts
export const sessionDigest = sqliteTable('session_digest', {
  id:             integer('id').primaryKey({ autoIncrement: true }),
  session_id:     text('session_id').notNull().unique(),
  summary:        text('summary').notNull(),
  ts:             text('ts').notNull(),
  topics:         text('topics'),         // comma-separated: "school,upwork,nutrifax"
  entity_draft:   text('entity_draft'),   // JSON — candidate entities before commit
  procedural_raw: text('procedural_raw'), // JSON — candidate procedural notes
});
```

The digest prompt should explicitly ask for three outputs: (1) the human-readable summary,
(2) candidate entity updates ("Arowyn has a report card due 2026-06-20"), (3) candidate
procedural notes ("Robin prefers short bullet replies when asking for ticket lists"). These
are candidates — the agent or Robin confirms before they're committed to the graph.

### Layer 2 — Topic Threads (episodic indexed)

Recurring concerns extracted from digest topics and linked to sessions. Acts as an index
for episodic retrieval: "find all sessions that touched arowyn-school" → their digests →
raw turns if needed.

```ts
export const topicThread = sqliteTable('topic_thread', {
  id:          integer('id').primaryKey({ autoIncrement: true }),
  label:       text('label').notNull(),    // "arowyn-school", "nutrifax-bounces"
  description: text('description'),
  last_seen:   text('last_seen').notNull(),
  session_ids: text('session_ids'),        // comma-separated
});
```

Labels are canonical slugs, not free text. A small fixed taxonomy is better than open
labels early on — prevents "arowyn_school" / "Arowyn school" / "school-arowyn" drift.
Rheo should suggest new labels; Robin confirms them.

### Layer 3 — Entity Knowledge Graph (semantic + temporal)

People, projects, deadlines, preferences — facts with provenance, confidence, and temporal
validity. Backed by the ontology skill's JSONL format initially; migrates to a dedicated
SQLite table when query volume warrants it.

Entity types in scope:
- `Person` — Arowyn, teachers, clients, vendors, government contacts
- `Project` — Nutrifax, GrowOperative, CryptoWatchTools, specific Upwork leads
- `Deadline` — named deadlines with due dates and recurrence
- `Preference` — how Robin likes things done (procedural memory, stored here as entities)
- `Fact` — one-off truths that don't fit elsewhere ("ICBC renewal is September")

Relations carry temporal edges and provenance:

```jsonl
{"op":"create","entity":{"id":"e_arowyn","type":"Person","properties":{"name":"Arowyn","relation_to_robin":"daughter"}}}
{"op":"create","entity":{"id":"e_crawford_bay_school","type":"Organization","properties":{"name":"Crawford Bay School"}}}
{"op":"relate","from":"e_arowyn","rel":"attends","to":"e_crawford_bay_school","properties":{"since":"2024-09","confidence":1.0,"source":"conversation:2026-06-10"}}
{"op":"create","entity":{"id":"e_report_card","type":"Deadline","properties":{"label":"Arowyn report card","due":"2026-06-20","source_session":"sess_20260615"}}}
{"op":"relate","from":"e_arowyn","rel":"has_deadline","to":"e_report_card"}
```

Key graph properties on relations:
- `valid_from` / `valid_until` — temporal edges (a relationship that ended)
- `confidence` — 0.0–1.0; facts extracted from conversation start at 0.8, manually
  confirmed facts at 1.0
- `source` — `conversation:{id}` or `session:{id}` or `manual`
- `superseded_by` — points to a newer version of the same fact; old version preserved

Conflict handling: when a new fact contradicts an existing one (same entity + relation,
different value), both versions are kept. The older one gets `superseded_by` pointing to
the new one, and a flag is set for review if the confidence delta is large. The agent does
not silently overwrite. Minor wording changes (same meaning) can be consolidated quietly;
anything substantive goes to Robin.

### Layer 4 — MCP Surface (agent-managed)

Tools exposed at `https://rheo.ca/mot/api/mcp` that Rheo calls as an active agent, not
just a passive consumer. The key shift: Rheo decides what to retrieve and what to write
during the conversation, rather than the bot mechanically injecting a fixed context block.

**Retrieval tools:**

```
chat_recent(n: int)
  → last N turns from the ledger

session_digests(n: int)
  → last N session digests; lightweight boot context

chat_search(q: string, mode?: "fts" | "vector" | "hybrid")
  → keyword and/or semantic search over raw turns and digests

topic_threads(label?: string)
  → list threads, or get sessions linked to a specific topic

entity_get(id: string)
  → fetch one entity with all its relations

entity_search(q: string, type?: string)
  → search the graph by name or property

entity_related(id: string, rel?: string, hops?: int)
  → graph traversal — find entities reachable from this one
```

**Memory management tools (agent-driven):**

```
write_memory(type: "fact"|"preference"|"deadline"|"person", content: object)
  → Rheo commits a new entity or relation to the graph

edit_fact(entity_id: string, property: string, new_value: any, reason: string)
  → update a fact; old version preserved with superseded_by

consolidate_entities(ids: string[], canonical_id: string)
  → merge duplicate entities; relations redirected to canonical

summarize_and_archive(session_id: string)
  → manually trigger a digest pass on a session

flag_conflict(entity_id: string, note: string)
  → surface a contradiction for Robin to resolve
```

These tools let Rheo actively say "I should remember this" mid-conversation, rather than
waiting for the next digest pass to catch it. This is the MemGPT/Letta pattern: the agent
manages its own memory page-in/page-out, not just reads from a fixed injected window.

---

## Hybrid Retrieval Strategy

Three retrieval modes, each suited to different query shapes:

| Mode | When to use | Implementation |
|------|-------------|----------------|
| **Keyword (FTS5)** | Exact phrases, names, ticket IDs | SQLite FTS5 on `conversations` + `session_digests` |
| **Vector (semantic)** | "what did we talk about re: cash flow?" | sqlite-vec on `conversations.embedding`; embed at write time |
| **Graph traversal** | "what deadlines does Arowyn have?" | Walk entity graph: `e_arowyn` → `has_deadline` → results |

**Hybrid search** (GraphRAG-style): run FTS + vector in parallel, merge results by score,
then optionally expand via graph traversal on the entity IDs that surface. Return a ranked,
deduped list. The MCP tool `chat_search(mode: "hybrid")` triggers this path.

**Retrieval order for a conversation turn (what Rheo should do, not what the bot injects):**

1. Bot injects: last 3–5 session digests + current open MOT tickets (lightweight, always-on)
2. Rheo decides to call `entity_search` or `chat_search` when the question warrants it
3. If a specific person/project/deadline is referenced, Rheo calls `entity_related` for
   graph context
4. Rheo calls `write_memory` or `edit_fact` at the end of a turn if something worth
   remembering surfaced

This means the "context window" for any given turn is dynamic — Rheo assembles it via tool
calls rather than the bot front-loading everything.

---

## Boot Context

On bot startup, inject only:
- **3–5 session digests** (~10–15 lines) — not raw turns
- **Open MOT tickets** (already in place)

That's it. Rheo calls memory tools on demand for everything else. This keeps boot injection
cheap regardless of how much history accumulates.

Session boundary detection: a gap of >2h between turns triggers a new `session_id`. The
digest pass runs lazily — either at the start of the next session (background thread) or
when Rheo explicitly calls `summarize_and_archive`.

---

## Conflict Handling

Versioned, not overwritten. Every fact carries `source` and optionally `superseded_by`.

| Conflict type | Action |
|--------------|--------|
| Same fact, minor wording change | Agent consolidates quietly, logs in entity history |
| Same fact, different value (e.g. deadline date changed) | Keep both, old gets `superseded_by`, confidence on new set to 0.8 |
| Directly contradictory facts (high confidence, opposing claims) | Both kept, `flag_conflict` called, surfaces to Robin |
| Robin explicitly corrects something | `edit_fact` called, old version preserved, confidence on new set to 1.0 |

The agent never auto-resolves a high-confidence contradiction. Low-confidence candidates
(extracted from conversations, not manually confirmed) can be quietly revised.

## Regression and evaluation harness

Memory needs a lasting harness, not one-off smoke checks:

- **Recall checks:** known phrase, known person, known deadline, known project, and known
  preference can be retrieved after restart.
- **Digest checks:** a sample session produces summary, entity candidates, and procedural
  candidates without inventing facts.
- **Conflict checks:** changed deadline preserves the old value with provenance and flags when
  confidence requires review.
- **Noise checks:** pleasantries and speculation do not create memory writes.
- **Staleness checks:** stale-sensitive facts are marked for review instead of treated as live
  forever.

Accepted checks should become fixtures on the memory track and feed Bundle 01b's regression
fixture convention when the framework phase lands.

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
natural choice. For now, sqlite-vec is the right call.

**Who runs the digest pass?**
Options: (a) bot background thread on session boundary, (b) Claude.ai routine on a
schedule, (c) Rheo calls `summarize_and_archive` explicitly. Option (b) is cleanest for
reliability — a routine that runs every 2h, checks for undigested sessions, and processes
them. Option (a) is simpler to build first.

**How does Rheo know when to write memory vs. when to just answer?**
System prompt instruction + examples. The pattern from MemGPT: after every assistant turn,
there's an implicit "should I update memory?" check. In practice this means the system
prompt tells Rheo to call `write_memory` when specific conditions are met (new entity, stated
fact, confirmed preference) and skip it otherwise. Too aggressive and memory fills with noise;
too conservative and it's useless.

**Ontology JSONL vs dedicated SQLite table**
JSONL is fine while the graph is small (<1,000 entities) and query patterns are simple.
Once graph traversal becomes a hot path, migrate to a proper adjacency table in SQLite.
The JSONL format preserves history; migration is a one-time import.

**Privacy**
All memory is local (MOT's SQLite on rheo.ca). No external service sees it. The bot and
`claude -p` do pass content to Anthropic APIs during digesting — same as any conversation.
No special handling needed beyond what's already in place.

**Memory rot**
Facts become stale. A "Nutrifax has 3 paying customers" fact from six months ago may be
wrong today. Mitigation: `confidence` decays on time-sensitive facts (deadlines, counts,
states) after a configurable interval. The digest pass flags time-sensitive entities for
review when they're older than their expected shelf life.

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
- **Mem0** — fact extraction + consolidation from conversations; the `write_memory` +
  `consolidate_entities` pattern.
- **Zep / Graphiti** — temporal knowledge graph over conversation history; the
  `valid_from`/`valid_until` edge model and graph traversal.
- **GraphRAG** — hybrid retrieval combining vector search with graph traversal for
  multi-hop reasoning.
- **Oriva memoir memory** (`oriva/future-research/memoir-memory-storage-strategies.md`) —
  summary hierarchies (the digest layer), hybrid relational + vector approach, thematic
  thread entities, conflict-as-versioning rather than overwrite.

---

## Future Extensions

- **Proactive surfacing** — Rheo notices "you mentioned the ICBC renewal in September;
  that's 3 months away" without being asked, by running a background check on dated entities.
- **Cross-channel memory** — ingest signals from Gmail routines into the same entity graph,
  so Rheo's graph includes facts from email, not just Telegram conversations.
- **Book editor / memory review UI** — a view in MOT's admin where Robin can browse, confirm,
  or delete candidate entities and procedural notes before they're committed.
- **Routine as memory writer** — the hourly Gmail routine also calls `write_memory` when it
  finds something worth persisting (a confirmed deadline, a new vendor contact).
- **Voice anchors** — Robin's communication patterns (Oriva's `voiceAnchors` concept) stored
  as procedural memory, referenced when Rheo drafts longer responses.
