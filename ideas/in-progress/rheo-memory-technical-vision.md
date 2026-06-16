# Novadiem Framework + Rheo Persistent Memory: Integrated Technical Vision

**Version:** 1.0  
**Date:** 2026-06-15  
**Author:** Rheo / Novadiem Studio  
**Status:** Idea → Planning  
**Alignment:** Bundle 02 (Reusable Learning Loop) + cross-bundle extensions  
**One-Liner:** Build a durable, agent-managed, layered memory system for Rheo (and future Novadiem agents) that combines episodic history, semantic entity graphs, procedural patterns, and MCP-driven agency. This turns session-local knowledge into reusable, verifiable canon while strengthening safety, planning quality, and long-term learning across the Society of Specialists.

## Purpose

This memory architecture addresses Rheo's current stateless limitations (rolling in-memory buffer lost on restart) by creating a persistent, queryable, agent-driven system. It enables cross-session recall ("What did we discuss about Arowyn's school?"), reduces assumptions in planning, captures reusable lessons, and integrates deeply with the Novadiem Society of Specialists and The Archive.

It builds directly on the existing Layer 0 (Ledger) + Layer 4 (MCP tools) work completed out-of-band on 2026-06-15.

## Cognitive Memory Model

Three interacting layers inspired by cognitive science and 2026 agent architectures (MemGPT/Letta, Mem0, Graphiti, GraphRAG):

- **Episodic**: Raw turns and session digests — "what happened, when".
- **Semantic**: Entity knowledge graph — facts about people, projects, deadlines, preferences.
- **Procedural**: Recurring patterns, templates, response styles, routines — "how Robin likes things done".

A single turn can contribute to all three. Retrieval is hybrid and agent-orchestrated, not mechanically injected.

## Layered Architecture

### Layer 0 — Ledger (Episodic Raw Store)
- Append-only SQLite table (`conversation`) in MOT.
- Fields: `id`, `chat_id`, `role`, `content`, `ts`, `session_id`, `ticket_id`, `embedding` (nullable for future vector).
- FTS5 virtual table + triggers for keyword search.
- Never deletes or mutates rows.

### Layer 1 — Session Digests (Compressed Episodic)
- Triggered by >2h session gaps or on-demand.
- One structured summary pass per session.
- Outputs: human-readable summary + entity candidates + procedural candidates.
- Stored in `session_digests` table.
- Serves as lightweight boot context (3–5 recent digests + open tickets).

### Layer 2 — Topic Threads
- Indexed recurring concerns (canonical slugs e.g. `arowyn-school`).
- Links sessions for easy navigation and recurrence detection.

### Layer 3 — Entity Knowledge Graph (Semantic + Temporal)
- Starts as ontology-style JSONL; migrates to SQLite adjacency tables as needed.
- Entities: Person, Project, Deadline, Preference, Fact.
- Relations with provenance (`source`), confidence (0.0–1.0), temporal edges (`valid_from`/`valid_until`), and `superseded_by`.
- Versioned: conflicts preserve history; no silent overwrites. High-delta changes flagged for review.

### Layer 4 — MCP Surface (Agent-Managed)
- Tools Rheo actively calls:
  - Retrieval: `chat_recent`, `chat_search` (FTS/vector/hybrid), `entity_get`, `entity_related`, `topic_threads`.
  - Management: `write_memory`, `edit_fact`, `consolidate_entities`, `summarize_and_archive`, `flag_conflict`.
- Agent decides context assembly dynamically — keeps boot injection minimal.

**Hybrid Retrieval Strategy**:
- FTS5 (keyword/exact) + future sqlite-vec (semantic) + graph traversal.
- Ranked by recency, relevance, confidence, source.
- Agent-driven: Rheo pages in only what is needed for the current turn.

## Integration with Novadiem Framework

- **Bundle 01 (Safety)**: Preflight for memory tools; external-action gates on writes; regression fixtures for extraction/conflict handling.
- **Bundle 02 (Learning Loop)**: Digests and writes feed `output/studio/lessons.md` and convention updates. Recurrence promotes to canon.
- **Bundle 03 (Planning)**: Graph reduces greenfield assumptions; supports observable outcomes.
- **Bundle 04 (Accounting)**: Memory stats (size, conflicts, retrievals) in run ledgers.
- **Conductor**: Routes memory tasks and adjudicates conflicts.
- **Challenger**: Reviews writes, hygiene, and quality.
- **The Archive**: Visual and functional representation of the full memory system.
- **Visual Canon**: Extend `VISUAL-CANON.md` with memory motifs (data conduits into Archive, entity graph holograms, temporal split-spiral flows).

Update THE CURRENT and THE ENGINE posters to reflect memory layers.

## Phased Implementation Roadmap

**Phase 1 (Immediate — Foundation)**:
- Challenger review of existing Layer 0+4 diff.
- Mechanic deploy (build + service restarts).
- Basic session digest pass + `write_memory` tool.
- Tie to Bundle 02 close-out.

**Phase 2 (Short-term)**:
- Topic threads.
- Basic graph (JSONL) + traversal.
- Hybrid search skeleton.
- Procedural notes handling.
- Session-boundary automation.

**Phase 3 (Medium-term)**:
- Full SQLite graph tables.
- sqlite-vec integration.
- Conflict review UI in MOT.
- Decay/maintenance routines.
- Workflow integrations (planning, bug-fix).

**Phase 4 (Optimization)**:
- Proactive surfacing.
- Cross-channel ingestion (e.g. Gmail routines).
- Advanced evals and benchmarks.
- Local runtime experiments for retrieval.

## Risks & Mitigations

- **Noise/Drift**: Conservative prompts, confidence thresholds, versioning, Challenger review.
- **Performance/Token Bloat**: Lightweight boot + on-demand retrieval; monitor via accounting.
- **Over-ceremony**: Agent-driven writes with explicit triggers only.
- **Staleness**: Temporal validity + periodic hygiene passes.
- **Privacy**: Local SQLite, per-chat isolation.

## Resources & Prior Art

- **Key Inspirations**: MemGPT/Letta (agent paging), Mem0 (fact consolidation), Graphiti/Zep (temporal graphs), GraphRAG (hybrid retrieval).
- **Local Tech**: sqlite-vec for embedded vectors; FTS5 already in place.
- **Standards**: Model Context Protocol (MCP) for tool interoperability.
- **Further Reading**:
  - Oriva memoir memory strategies.
  - 2026 benchmarks: LongMemEval, LoCoMo.
  - Cognitive hybrids: episodic/semantic/procedural distinctions.

## Success Criteria (Done When)

- Rheo recalls cross-session details accurately via tools without excessive context.
- Memory operations feed reusable framework improvements (Bundle 02).
- All conflicts are versioned and reviewable; no silent corruption.
- Memory visible in visual canon, workflows, and accounting.
- Measurable gains in resume speed, assumption reduction, and learning loop effectiveness.

This living document should be stored in the Archive and evolve through framework runs. It positions Novadiem/Rheo at the forefront of personal agent memory systems.

**Next Actions**:
1. Challenger review of current implementation.
2. Phase 1 execution.
3. Refine prompts and battle-test matrix.