# Novadiem Framework + Rheo Persistent Memory: Integrated Technical Vision

**Version:** 1.1
**Date:** 2026-06-15 (updated 2026-06-24)
**Author:** Rheo / Novadiem Studio
**Status:** Tracks 1–4 shipped. Foundation through maintenance layer is live in production as of 2026-06-23.
**Alignment:** Bundle 02 (Reusable Learning Loop) + cross-bundle extensions
**One-Liner:** Build a durable, agent-managed, layered memory system for Rheo (and future Novadiem agents) that combines episodic history, semantic entity graphs, procedural patterns, and MCP-driven agency. This turns session-local knowledge into reusable, verifiable canon while strengthening safety, planning quality, and long-term learning across the Society of Specialists.

## Purpose

This memory architecture addresses Rheo's stateless limitations (rolling in-memory buffer lost on restart) by creating a persistent, queryable, agent-driven system. It enables cross-session recall ("What did we discuss about Arowyn's school?"), reduces assumptions in planning, captures reusable lessons, and integrates deeply with the Novadiem Society of Specialists and The Archive.

Tracks 1–4 are shipped. The remaining vision items (vector retrieval, proactive surfacing, cross-channel ingestion, advanced evals, framework memory adapter) are future work with no committed track number.

## Cognitive Memory Model

Three interacting layers inspired by cognitive science and 2026 agent architectures (MemGPT/Letta, Mem0, Graphiti, GraphRAG):

- **Episodic**: Raw turns and session digests — "what happened, when".
- **Semantic**: Entity knowledge graph — facts about people, projects, deadlines, preferences. Two stores: `memory_items` SQL table (Track 1) and entity graph JSONL `ontology/graph.jsonl` (Track 2+).
- **Procedural**: Recurring patterns, templates, response styles, routines — "how Robin likes things done". `procedural_notes` table (Track 2).

A single turn can contribute to all three. Retrieval is agent-orchestrated via MCP tools, not mechanically injected.

## Layered Architecture

### Layer 0 — Ledger (Episodic Raw Store) — SHIPPED Track 1
- Append-only SQLite table (`conversation`) in MOT.
- Fields: `id`, `chat_id`, `role`, `content`, `ts`, `session_id`.
- No `embedding` column — vector search is not built. No `ticket_id` column in the real migration.
- FTS5 virtual table `conversation_fts` + AFTER INSERT trigger (append-only; no update/delete trigger).
- Never deletes or mutates rows.

### Layer 1 — Session Digests (Compressed Episodic) — SHIPPED Track 1
- Triggered by >2h session gaps or on-demand via `summarize_and_archive`.
- One structured summary pass per session.
- Outputs: human-readable summary + entity candidates + procedural candidates.
- Stored in `session_digest` table: `session_id`, `chat_id`, `summary`, `ts`, `topics`, `entity_draft`, `procedural_raw`, `parse_error`, `turn_count`.
- Serves as lightweight boot context: the bot reads the 3–5 most recent raw session digests via the REST route `GET /api/conversation/digests`. There is no `session_digests` MCP tool. (`memory_context` is a separate on-demand bundle — see Layer 4 — that returns topics/entities/procedural/recent-memory and never reads `session_digest`.)

### Layer 2 — Topic Threads — SHIPPED Track 2
- Indexed recurring concerns (canonical slugs e.g. `arowyn-school`).
- Schema: `topic_thread` (`slug PK`, `title`, `notes`, `created_at`, `last_active_at`) + `topic_thread_session` join table (`slug`, `session_id`, `added_at`).
- Links sessions for navigation and recurrence detection.
- `topic_thread_summarize` tool returns structured JSON (model-free, no LLM synthesis).

### Layer 3 — Entity Knowledge Graph (Semantic + Temporal) — SHIPPED Tracks 2+3
- Append-only JSONL at `ontology/graph.jsonl` (gitignored, server-only).
- Two record shapes: entity records (no `op`) + patch records (`op: 'supersede'` or `op: 'confirm'`).
- Entity shape: `{ id, type, label, properties: { relations?: [{rel, target_id}][] }, valid_from, valid_until, confidence, source, superseded_by, confirmed }`.
- Entity types: `Person | Project | Deadline | Preference | Fact`.
- Relations live at `properties.relations[]` — not a separate edge table. Currently sparsely populated; richer relation-linking is future.
- No `op:create` or `op:relate` records — those were planning-doc concepts. The real format is entity records + supersede/confirm patches only.
- Versioned: conflicts preserve history via `superseded_by`; no silent overwrites.
- Curation tools: `entity_confirm` and `entity_supersede` — `edit_fact`, `consolidate_entities`, and `flag_conflict` are NOT built and do not exist.
- Compaction: atomic write-to-tmp + rename via `lib/graph-compact.ts`. Nightly auto-compact when ≥5 MB.

Also: `memory_items` SQL table (Track 1) for directly-written typed facts, with `memory_items_fts` for keyword search.

### Layer 4 — MCP Surface (Agent-Managed) — SHIPPED Tracks 1–4

26 MCP tools at `POST /api/mcp`. Rheo calls these actively to assemble context and manage memory.

**Retrieval (built):**
- `chat_recent`, `chat_search` (FTS5 keyword only — no vector/hybrid mode), `chat_log_turn`, `summarize_and_archive`
- `topic_threads`, `topic_thread_create`, `topic_thread_link`, `topic_thread_summarize`
- `entity_get`, `entity_search` (substring), `entity_related`, `entity_confirm`, `entity_supersede`, `graph_compact`
- `write_memory`, `memory_recent`, `memory_context`
- `procedural_notes_list`, `procedural_note_confirm`
- `mot_list_tickets`, `mot_get_ticket`, `mot_create_ticket`, `mot_update_ticket`, `mot_get_status`, `mot_get_ministry_config`
- `notify_robin`

**NOT built — do not list as present:**
- `edit_fact`, `consolidate_entities`, `flag_conflict` — absent from codebase
- `chat_search` vector/hybrid mode — absent; FTS5 only

**Hybrid Retrieval Strategy (FUTURE):**
- FTS5 keyword search is built. Graph traversal is built.
- Vector (sqlite-vec) + hybrid FTS+vector+graph is future. No `embedding` column exists in any table.
- Ranked hybrid retrieval is a future capability, not current.

## Integration with Novadiem Framework

- **Bundle 01 (Safety)**: Preflight for memory tools; external-action gates on writes; regression fixtures for extraction/conflict handling (`.bureau/regression/` — 7 fixture files, tracked in git).
- **Bundle 02 (Learning Loop)**: Digests and writes feed `output/studio/lessons.md` and convention updates. Recurrence promotes to canon.
- **Bundle 03 (Planning)**: Graph reduces greenfield assumptions; supports observable outcomes.
- **Bundle 04 (Accounting)**: Memory stats (size, conflicts, retrievals) in run ledgers.
- **Conductor**: Routes memory tasks and adjudicates conflicts.
- **Challenger**: Reviews writes, hygiene, and quality.
- **The Archive**: Visual and functional representation of the full memory system.
- **Visual Canon**: Extend `VISUAL-CANON.md` with memory motifs (data conduits into Archive, entity graph holograms, temporal split-spiral flows).

## Phased Implementation Roadmap

**Phase 1 — Foundation (SHIPPED 2026-06-17, Track 1):**
- Conversation ledger + FTS5.
- Session digest pass + `write_memory` + `memory_recent` tools.
- Challenger review + deploy.
- Tied to Bundle 02 close-out.

**Phase 2 — Recallatron (SHIPPED 2026-06-22, Tracks 2+3):**
- Topic threads (`topic_thread` + join table).
- Entity graph JSONL + traversal tools (`entity_get`, `entity_search`, `entity_related`).
- Procedural notes table + tools.
- Session-boundary extraction pass (`lib/extraction.ts`).
- Entity curation (`entity_confirm`, `entity_supersede`).
- Graph backup.

**Phase 3 — Maintenance layer (SHIPPED 2026-06-23, Track 4):**
- `memory_context` boot bundle.
- `topic_thread_summarize` + `graph_compact` tools.
- Nightly prune + compaction cron.
- Historical backfill script (ran in production).
- UI browsers: `/memory/entities`, `/memory/procedural`, `/memory/topics`.
- Session-authed REST routes for memory browsing.

**Phase 4 — Future (no committed track):**
- Vector retrieval (sqlite-vec, embedding column, hybrid search).
- Proactive surfacing for dated entities.
- Cross-channel ingestion (e.g. Gmail routines → entity graph).
- Decay/staleness scoring on time-sensitive facts.
- Advanced evals and benchmarks (LongMemEval, LoCoMo).
- Framework memory adapter: read-first, provenance-bearing, deny-by-default for writes.

Note: the earlier planning doc labeled the MOT base as "Track 0" and used Track 1-4 for memory work. The actual delivery used Track 1-4 for all four shipped memory tracks. "Track 0" is not a real shipping unit in the codebase — the MOT base predated the tracking convention. Do not confuse the old planning Track 0-4 with the real Track 1-4 — they map approximately but not exactly.

## Stack (as shipped)

- **Next.js 14** (`^14.2.35`) — not 15
- **better-sqlite3** `^11.10.0` + Drizzle ORM `^0.29.5` + FTS5 (SQLite built-in)
- **Single process, single SQLite file** (`mot.db`, WAL mode)
- **Cron:** node-cron `^4.2.1` (nightly at 02:00)
- **Bot:** separate repo `rheos/rheo-bot` at `/opt/rheo-bot` on rheo.ca Lightsail, systemd service `telegram-bot`, webhook `tg.rheo.ca/telegram` (moved out of mot repo 2026-06-21)

## Risks & Mitigations

- **Noise/Drift**: Conservative prompts, confidence thresholds, versioning, Challenger review.
- **Performance/Token Bloat**: Lightweight boot via `memory_context` + on-demand retrieval; monitor via accounting.
- **Over-ceremony**: Agent-driven writes with explicit triggers only.
- **Staleness**: Temporal validity + nightly prune. Full confidence-decay on time-sensitive facts is future.
- **Privacy**: Local SQLite, per-chat isolation.
- **Graph size**: 5 MB guard + nightly compaction keep JSONL manageable. SQLite adjacency migration is future.

## Resources & Prior Art

- **Key Inspirations**: MemGPT/Letta (agent paging), Mem0 (fact consolidation), Graphiti/Zep (temporal graphs), GraphRAG (hybrid retrieval).
- **Local Tech**: FTS5 in place; sqlite-vec is future.
- **Standards**: Model Context Protocol (MCP) for tool interoperability.
- **Further Reading**:
  - Oriva memoir memory strategies.
  - 2026 benchmarks: LongMemEval, LoCoMo.
  - Cognitive hybrids: episodic/semantic/procedural distinctions.

## Success Criteria (Done When)

- Rheo recalls cross-session details accurately via tools without excessive context. (Shipped.)
- Memory operations feed reusable framework improvements (Bundle 02).
- All conflicts are versioned and reviewable; no silent corruption. (Shipped — `superseded_by` chain.)
- Memory visible in visual canon, workflows, and accounting.
- Measurable gains in resume speed, assumption reduction, and learning loop effectiveness.

This document should evolve through framework runs and be kept in sync with the ground-truth survey produced by each major track delivery.
