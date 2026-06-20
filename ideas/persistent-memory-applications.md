# Persistent Memory Applications — idea cluster

**Date:** 2026-06-18
**Author:** Robin (Novadiem)
**Status:** Idea cluster / capture doc

A grouping of product ideas that share one engine and one bet. Held together "for now"
so the shared platform and the shared thesis stay visible. Individual ideas can
graduate to their own files (and framework runs) when they firm up.

## The shared thesis
LLM chats forget. Every session starts from scratch. The unlock is durable, structured,
per-subject memory that compounds over time, with provenance and confidence so you can
trust what it remembers. Each idea here points that same capability at a different
domain. The memory is the product; the domain is the wrapper. It turns an AI from
"helpful in the moment" into a reliable long-term collaborator.

## The engine: The Recallatron
The working name for the memory engine itself. Four parts working together:
- **Append-only ledger** — raw input is never lost or overwritten.
- **Layered processing** — raw stays available while higher layers give clean,
  actionable views (digests, topics, graph).
- **Provenance-rich entity graph** — people, projects, evolving preferences, and
  superseded decisions, with receipts and confidence; staleness flags surface outdated
  facts.
- **On-demand tool surface** — agents or the user pull only what's needed instead of
  drowning in context.

This is the productized form of the Rheo 5-layer memory architecture (ledger → digests
→ topics → entity graph → MCP tools; spec:
`agent-framework/ideas/in-progress/rheo-persistent-memory.md`). The Bureau agents
operate it: the Conductor routes work and queries memory, the Challenger flags
inconsistencies and stale facts, the Recallatron serves provenance on demand.

## Shared primitives (what every idea here reuses)
- **MemoirQuill / Oriva platform** (`~/Code/novadiem/oriva`, built + in dogfood):
  document ingestion + normalization, a resumable multi-stage LLM pipeline with
  per-stage model routing (OpenRouter), **pgvector retrieval**, provenance +
  safety/coverage gates, and a combined consent + billing gate. Stack: Next + Prisma +
  Postgres/pgvector + pg-boss.
- **Rheo runtime** (SQLite + MCP tools in the bot): where the ledger and live recall
  tools run today. Layer 0 + FTS is built; digests, graph, and procedural layer are
  planned tracks.

Open architectural question across the cluster: when an idea reuses the MemoirQuill
platform vs. the Rheo runtime, and where the two converge.

---

## Built / in flight
The three concrete products that already exist or have their own spec.

| Product | Whose memory | Status | Detail |
|---------|--------------|--------|--------|
| **MemoirQuill** | a person's life story | v1 built, in dogfood (Robin + Ernest Pitt) | `~/Code/novadiem/oriva` |
| **TutorQuill / ScholarQuill** | a student's learning | idea, sibling on MemoirQuill platform | `ideas/tutor-idea.md` |
| **Rheo persistent memory** | the assistant relationship | Layer 0 built; rest planned | `ideas/in-progress/rheo-persistent-memory.md` |

---

## Application backlog (where else to point the engine)
Each is the same engine with a different wrapper. "Durable thing" is what a one-off chat
can't hold.

| # | Direction | Durable thing it holds | Note |
|---|-----------|------------------------|------|
| 1 | **Personal Life OS / Second Brain** | projects, health, finances, relationships, goals, evolving preferences, superseded decisions, with full history and staleness flags | the broadest. "What have I learned about my sleep this year?" with receipts back to journal entries. Crowded space (Mem, Tana, Notion AI). |
| 2 | **Long-running creative projects** | character arcs, plot threads, world-building, research, versioned story decisions across months or years | Challenger flags inconsistencies; provenance answers "why did we change this character's motivation?" |
| 3 | **Software dev companion** | architecture, past debugging sessions, style prefs, library and trade-off decisions; dependency + issue graph | resume a complex refactor weeks later with full context. Crowded (Cursor, Copilot, Claude projects). |
| 4 | **Research / knowledge-work assistant** | recurring topic threads; people, sources, and claims with confidence + provenance | synthesis over time, pulling insight across dozens of sessions. |
| 5 | **Health / wellness coaching** | symptoms, treatments, habits, nutrition, fitness over time; responses to treatment with provenance | high trust/safety bar. Pairs with a coaching agent. Liability care needed. |
| 6 | **Business / freelance ops hub** | client relationships, project history, contracts, prefs, open threads | "Client X prefers Y comms style, has these open threads." Multi-client orchestration. Closest to Robin's own Upwork work. |
| 7 | **Multi-agent team coordination** | shared institutional memory across Bureau specialists; past outcomes, process refinements, evolving consensus | meta-application: the Bureau using the engine on itself. Internal tooling more than a product. |
| 8 | **Legacy / family history** | oral history, genealogy, family stories, conflicting-memory resolution | overlaps MemoirQuill heavily; likely a MemoirQuill mode, not a separate product. |
| 9 | **Reflective journaling companion** | mood threads, growth tracking, long-term pattern recognition | needs strong ethical safeguards. Reflective, not clinical therapy. |
| 10 | **Entrepreneurial / startup brain** | idea evolution, customer interviews, pivot decisions, learnings, market notes | "what we tried, what we learned, why we pivoted" with chain of custody. |

**Niche but powerful:** legal case management (with disclaimers), elder-care
coordination, game-mastering (campaign memory), a "personal constitution" updater for
life values and decisions.

## Adjacent: project-agent (integration target, not an application)
`~/Code/novadiem/project-agent` looks similar but runs the opposite way. It is grounded
RAG over a project's authored corpus (docs/skills/decisions on disk): it answers with
citations and invalidates its cache when a doc changes. Truth lives in the files, not in
an accumulating memory, so it is not a Recallatron application.

It is the best **consumer** of the engine. Today it is a stateless doc-reader. With the
Recallatron as a memory backend it would remember what each stakeholder asked, what got
decided in a walkthrough, and why an open question resolved the way it did, with
receipts, evolving over months. project-agent owns the stakeholder surface and the
structured-feedback flow; the Recallatron owns the memory.

Stack: FastAPI + Next + Postgres, a third runtime alongside the MemoirQuill platform and
the Rheo runtime. Active track: the in-progress "Stakeholder Companion" idea
(`ideas/in-progress/stakeholder-companion.md`).

## Why the Recallatron fits these
Each property maps to a class of use case:
- **Provenance + receipts** → high-stakes or reflective work: health, legal-ish
  decisions, creative continuity, research.
- **Layered structure** → raw input stays available while higher layers give clean,
  actionable views.
- **Entity graph** → anything with relationships or evolving entities: people,
  projects, preferences, complex webs.
- **Tool surface** → agents and users pull only what's needed instead of drowning in
  context.
