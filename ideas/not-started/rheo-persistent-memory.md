# Rheo — Persistent Chat Memory

Date: 2026-06-15

## One-liner

Give Rheo a layered memory system: raw turns in SQLite, session digests, topic summaries,
and a semantic search index — so he remembers across restarts, retrieves relevant past
context without dumping everything into the prompt, and builds up a knowledge graph of
Robin's people, projects, and deadlines over time.

## The problem

Rheo currently holds a rolling 12-message in-memory buffer (per chat_id, lost on restart)
and has zero cross-session memory. He can see open MOT tickets injected into each prompt,
but he has no way to ask "what did we discuss about Arowyn's school last week?" or "did Robin
ever mention that deadline?" The session restart from the previous conversation is a concrete
example — zero context, starting from scratch every time.

The naive fix — inject the last N raw turns into every prompt — hits two walls fast: tokens
and coherence. Oriva's memoir memory system (see `oriva/future-research/memoir-memory-storage-strategies.md`)
solved an analogous problem at book scale. The same patterns apply here, at conversation scale.

---

## Architecture

### Layer 0: Raw turns (the ledger)

A `conversations` table in MOT's SQLite database. Append-only. Never rewrite history.

```prisma
model Conversation {
  id         Int      @id @default(autoincrement())
  chat_id    String
  role       String   // "user" | "assistant"
  content    String
  ts         DateTime @default(now())
  session_id String?  // groups turns into a session (bot restart boundary)
  ticket_id  Int?     // link to a MOT ticket when one was created/referenced
  embedding  Bytes?   // sqlite-vec blob — added in v2 when semantic search is wanted
}
```

FTS via SQLite `fts5` on `content` for keyword search. Vector search (sqlite-vec or
a pgvector upgrade) for semantic "find conversations about cash flow" queries later.

REST endpoints:
- `POST /conversations` — append a turn (called by the bot after each exchange)
- `GET /conversations/recent?n=N` — last N turns, for boot context
- `GET /conversations/search?q=...&limit=...` — FTS, newest-first

### Layer 1: Session digests (the summary hierarchy)

Drawing from Oriva's `ChapterSummary` pattern: after each session ends (bot restart or N-hour
gap), run a digest pass that produces a 2–4 sentence summary of what was covered. These
digests are cheap to inject — the bot loads the last 5 session digests (~10 lines) instead
of 50 raw turns.

```prisma
model SessionDigest {
  id         Int      @id @default(autoincrement())
  session_id String   @unique
  summary    String   // 2-4 sentences
  ts         DateTime // session end time
  topics     String?  // comma-separated detected topics: "school,upwork,nutrifax"
}
```

Digest generation: at bot startup (or when a session boundary is detected), call
`claude -p` with the session's raw turns and ask for a digest. One API call per session,
stored permanently.

### Layer 2: Topic threads (thematic entities)

Oriva calls these ThematicThreads. For Rheo they're recurring concerns: Arowyn's school,
Nutrifax, Upwork leads, cash flow, Crawford Bay, health. Rheo detects these from the
digest topics and tracks them as first-class entities in MOT (or the ontology graph).

```prisma
model TopicThread {
  id          Int      @id @default(autoincrement())
  label       String   // "arowyn-school", "nutrifax-bounces", "upwork"
  description String?
  lastSeen    DateTime
  sessionIds  String   // comma-separated session_ids that touched this topic
}
```

This lets Rheo answer "what have we talked about regarding Arowyn's school?" by fetching
`TopicThread.label = "arowyn-school"` → linked session digests → raw turns if needed.
Three levels of zoom: topic summary → session digest → raw turns. Inject only what fits.

### Layer 3: Entity knowledge graph (temporal)

Oriva uses `Entity` + `EntityRelationship` with temporal edges. Rheo builds the same thing
over time from conversations:

```
Person: Arowyn, Robin, teachers, clients, vendors
Project: Nutrifax, GrowOperative, CryptoWatchTools, a specific Upwork lead
Deadline: "ICBC renewal", "Crawford Bay school registration", "domain expiry"
```

Relations: `Robin → parent_of → Arowyn (always)`, `Nutrifax → has_deadline → payment_due
(July 2026)`. These get linked to MOT tickets when they exist.

The ontology skill's `Thread + Message + Task` entity types are the right home for this.
Rheo (or a background routine) writes entities to `memory/ontology/graph.jsonl` as they
surface in conversation. Skill contract:

```yaml
ontology:
  reads: [Person, Project, Deadline, Message, Thread]
  writes: [Message, Thread, Action]
```

This is the layer that lets a future Rheo say "you mentioned the ICBC renewal was due in
September — is that still the case?" without it being in an open MOT ticket.

### Layer 4: MCP surface

Add tools to the MOT MCP server at `https://rheo.ca/mot/api/mcp`:

```
chat_recent(n: int)              → [{ role, content, ts }]
chat_search(q: string)           → [{ role, content, ts, score }]  // FTS or vector
session_digests(n: int)          → [{ summary, topics, ts }]
topic_threads(label?: string)    → [{ label, description, lastSeen }]
```

With `--mcp-config` wired into `claude -p`, Rheo calls these as tools rather than relying
on what the bot pre-injects. He decides what to retrieve based on the question asked.

### Layer 5: Bot wiring

Changes to `/opt/telegram-bot/bot.py`:

1. **Persist turns** — after each `run_claude()`, POST user message + reply to
   `POST /conversations`.
2. **Boot context** — on startup, fetch `session_digests(n=5)` and inject as:
   ```
   === RECENT SESSION SUMMARIES ===
   [2026-06-13] Discussed Upwork lead for React Native job, Arowyn school report.
   [2026-06-14] Nutrifax bounce alerts, CryptoWatchTools redesign paused.
   ...
   ```
   This is ~10 lines, not 50 raw turns. Much cheaper than `recent?n=20`.
3. **MCP flag** — add `--mcp-config /opt/telegram-bot/mcp-config.json` so Rheo can call
   memory tools directly mid-conversation.
4. **Session boundary detection** — when a new conversation starts after >2h gap, trigger
   a background digest of the previous session.

---

## What not to do (lessons from Oriva)

- **Don't inject all raw turns.** The summary hierarchy exists precisely so you don't have
  to. Raw turns are for retrieval; digests are for boot context.
- **Don't use pure vector search.** Keep exact links (turn → ticket, turn → entity) in
  relational. Vector search is for "find semantically similar conversations," not for
  provenance.
- **Don't auto-resolve contradictions.** If Robin says something that conflicts with what
  Rheo recorded earlier, flag it — don't silently overwrite. Store both, ask.

---

## Build order

### v1 — Ledger + boot context (minimum viable memory)
1. Add `Conversation` + `SessionDigest` models to Prisma schema + migrate.
2. Add REST endpoints: `POST /conversations`, `GET /conversations/recent`,
   `GET /conversations/search` (FTS), `POST /conversations/digest`.
3. Bot: persist turns + load session digests on boot.
4. Add `chat_recent` + `session_digests` MCP tools.
5. Wire `--mcp-config` into `claude -p`.

### v2 — Topic threads + semantic search
6. Add `TopicThread` model. Extract topics from digests (one more `claude -p` call).
7. Add sqlite-vec (or migrate MOT to Postgres + pgvector for consistency with Oriva).
8. Add `chat_search` with vector similarity + FTS hybrid.
9. Add `topic_threads` MCP tool.

### v3 — Entity graph
10. Wire ontology skill into the bot. After each session digest, extract entities + relations.
11. Link entities to MOT tickets where they exist.
12. Add ontology MCP queries: `entity_get`, `entity_related`.

---

## Out of scope for v1

- UI in MOT for browsing chat history (nice-to-have)
- Multi-user support (single-user by design)
- Encryption at rest beyond what SQLite on the server provides
- Book-level coherence checks (Oriva concern, not Rheo)
