# Rheo — Persistent Chat Memory

Date: 2026-06-15

## One-liner

Store every Rheo/Telegram conversation turn in MOT's SQLite database and expose it via MCP
tools so Rheo can actually remember things across sessions, search past conversations, and
link chat context to open tickets.

## The problem

Rheo currently holds a rolling 12-message in-memory buffer (per chat_id, lost on restart)
and has zero cross-session memory. He can see open MOT tickets injected into each prompt,
but he has no way to ask "what did we discuss about Arowyn's school last week?" or "did Robin
ever mention that deadline?" The session restart from the previous conversation is a concrete
example — zero context, starting from scratch every time.

## Design

### Layer 1: MOT conversations table

Add a `conversations` table to MOT's SQLite database (`/opt/mot/prisma/schema.prisma`):

```sql
model Conversation {
  id        Int      @id @default(autoincrement())
  chat_id   String
  role      String   -- "user" | "assistant"
  content   String
  ts        DateTime @default(now())
  ticket_id Int?     -- optional link to a MOT ticket
  tags      String?  -- comma-separated, for filtering (e.g. "school,arowyn")
}
```

FTS via SQLite's `fts5` extension or a generated column + index on `content`.

Two new MOT API endpoints:
- `POST /conversations` — append a turn (called by the bot after each exchange)
- `GET /conversations/search?q=...&limit=...&before=...` — FTS query, newest-first
- `GET /conversations/recent?n=20` — last N turns across all sessions (for boot context)

### Layer 2: MCP tools in MOT MCP server

Add two tools to the MCP server at `https://rheo.ca/mot/api/mcp`:

```
chat_recent(n: int) → [{ role, content, ts, ticket_id }]
chat_search(q: string, limit?: int) → [{ role, content, ts, ticket_id, score }]
```

These let a `claude -p` invocation (or a routine) ask the graph directly for past context
rather than relying on what the bot manually injects.

### Layer 3: Bot integration

Two changes to `/opt/telegram-bot/bot.py`:

1. **Store turns**: after each `run_claude()` completes, POST both the user message and the
   assistant reply to `POST /conversations` via the existing MOT headers.

2. **Boot context**: at startup (or lazily on first message), fetch the last 20 turns via
   `GET /conversations/recent?n=20` and use those as the initial `HISTORY[chat_id]` deque
   instead of starting empty. This survives restarts.

3. **MCP flag**: pass `--mcp-config /opt/telegram-bot/mcp-config.json` to `claude -p` so
   Rheo can call `chat_search` and `chat_recent` as actual tools rather than needing them
   injected into the prompt. The mcp-config file points at the MOT MCP server with the API
   key.

### Layer 4: Ontology (optional, later)

The ontology skill's `Thread` + `Message` entity types map cleanly onto this:

```
Thread { subject: "Telegram", participants: [robin_id, rheo_id] }
Message { content, sender, thread, ts }
```

Relations: `Message → links_to → MOTTicket` when Rheo creates or references a ticket.
This lets the ontology graph answer "what tickets came from conversations about school?" or
"show me all the messages that referenced the Upwork deadline."

Not required for the first pass — the SQL layer is sufficient and simpler. Ontology is the
right move once the graph has 6+ months of data and cross-entity queries matter.

## Why now

- MOT's SQLite is already there, battle-tested, with a Prisma schema ready to extend.
- The MCP server is live — adding two tools is a small Prisma query + JSON-RPC handler.
- `claude -p --mcp-config` is the documented fix for headless MCP. Worth doing once so Rheo
  can query his own memory as a tool, not just have it injected.
- The bot currently loses all memory on every restart. One `recent` call at boot fixes that.

## Build order

1. Add `Conversation` model to Prisma schema + migrate.
2. Add REST endpoints: `POST /conversations`, `GET /conversations/search`, `GET /conversations/recent`.
3. Add MCP tools `chat_recent` + `chat_search` to the MCP server.
4. Update bot: persist turns after each exchange, load recent on boot.
5. Add `--mcp-config` to `claude -p` so Rheo can call the tools directly.
6. (Later) Ontology layer: model threads/messages as entities, relate to MOT tickets.

## Out of scope for v1

- UI in MOT for browsing chat history (nice-to-have, not urgent)
- Multi-user support (single-user by design: Robin only)
- End-to-end encryption at rest (API key auth on MOT is sufficient for now)
