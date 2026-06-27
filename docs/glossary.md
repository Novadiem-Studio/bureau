# Agent-Framework Glossary

The decode legend for the shorthand that shows up in run output, spec deliverables, and persona
files: the `XX-N` deliverable labels, the state/status tokens, the checkpoint markers, and the
verdict vocabulary. This is the one place that defines the label scheme; the section headings it
derives from live in `agents/analyst.md § Output structure`, and the cast/role names live in
`docs/conventions/agent-contracts.md § File ↔ role alias table` (this file points there, it does not re-list them).

---

## Deliverable labels (the `XX-N` scheme)

A label is a **type prefix** plus a **sequence number**: `OQ-1` is Open Question #1. The number is
just a handle so anything downstream can cite the item without re-quoting it ("blocked on OQ-3").
The prefixes are not a registered table anywhere in the code; they are an emergent shorthand for
the spec section each item lives in. The numbering restarts per section, per spec.

Two written forms appear, same meaning:

- **Dash form** (`FR-1`, `OQ-3`, `EC-12`): used in the spec deliverables under `ideas/`.
- **Space form** (`FR 7`, `EC 4`, `AC 11`): persona files use this when they cite an item inline
  (e.g. the Challenger checking `AC 11`, a field rule citing `EC 1`).

| Label | Expands to | Lives in / cited by |
|-------|------------|---------------------|
| `FR-N` | Functional Requirement | `spec.md § Functional Requirements`; Spellwright prompts cite the FR they satisfy |
| `AC-N` | Acceptance Criteria | `spec.md § Acceptance criteria`; the Challenger checks these by number |
| `EC-N` | Edge Case & Failure Mode | `spec.md § Edge Cases & Failure Modes`. Framework-specific, not standard PM vocabulary |
| `OQ-N` | Open Question | `spec.md § Open Questions`; an item needing a human decision or more research |
| `AS-N` | Assumption | `spec.md § Assumptions`. Seen zero-padded (`AS-07`) in some specs |
| `ARCH-N` | Architecture item / risk | Architect's architecture section in the spec |
| `ADR-NNN` | Architecture Decision Record | 3-digit form (`ADR-003`): a decision plus its rationale and alternatives |
| domain tags | scoped requirement IDs *inside one spec* | `API-1`, `DB-2`, `AUTH-1`, `UI-3`, `LC-1`, `NEW-2`, `FIX-1` — spec-local, not framework-wide |

### Labels the framework does NOT use

These standard PM prefixes never appear as labels here, so if you see one it is not coming from
the framework: `NFR`, `REQ`, `US`, `UC`, `DEC`, `RISK`, `CON`, `DEP`, `TASK`, `TC`, `BUG`, `DEF`,
and notably `CP`. The concepts (risk, decision, constraint, checkpoint) exist, but they are never
given an `XX-N` code. In particular, a checkpoint is a bracket marker (below), never `CP-1`.

---

## State and status tokens

Source of truth: `templates/state.json` and `agents/orchestrator.md`. Values current as of writing.

- **`phase_status`** (per-phase): `pending` · `in_progress` · `complete` · `blocked`
- **`status`** (run-level, derived): `not_started` · `blocked` · `in_progress` · `complete` · `archived`
- **`phase`**: short free-text label of the active phase (template default `not_started`)
- **`phases_complete[]`**: ordered list of finished phases, e.g. `["analyst","architect"]`
- **`design.status`**: `pending` · `awaiting_design` · `ingested` · `not_needed`
- **`accounting.status` / `external_review.status`**: `pending` → `complete` / `flagged` / `requested`
- **`git.status`**: `active` or `null`

A run is **stale** when `last_updated` is over 4h old (Ministry of Flow's `staleHours`).

---

## Checkpoint markers

A checkpoint is a bracketed literal in the run narrative, not an `XX-N` label. The ones in use:

- `[CHECKPOINT]` — generic stop, waiting on a human
- `[DESIGN-MODEL CHECKPOINT]`
- `[DESIGN HANDOFF]`
- `[DEV-VERIFIED CHECKPOINT]`
- `[EXTERNAL-ACTION CHECKPOINT]`

Clearing one means giving the literal **`go`**. Silence, "continue", or "looks good" do NOT count
as a go.

---

## Verdict / adjudication tokens

The vocabulary roles use to pass or stop work:

- **Challenger (critic)**: `BLOCKER` (route a fix) · `WARNING` (log and proceed) · `CHECKPOINT` (stop for a human). Emits a VERDICT block of `go` / `block` / `accept`.
- **Delegate** (`config/delegate-verdict.schema.json`): `proceed` · `revise` · `escalate`
- **Witness**: distinguishes `blocked` (needs a human) from `in_progress`; emits `go` / `block`
- **Notary**: advisory only; may emit `FLAGGED` (a coldness/isolation rule was broken)

---

## Greenfield assumption-row status

In the Analyst's Greenfield Assumptions table (`agents/analyst.md`), each row carries one of:
`decided` · `deferred` · `needs-Visionary` (triggers a `[CHECKPOINT]`) · `needs-Architect`.

---

## Cast / role names

Not re-listed here. The canonical map of persona file to cast name (The Conductor, The Challenger,
The Spellwright, Analizer 2000, and the rest) is `docs/conventions/agent-contracts.md § File ↔ role alias table`.

---

This file is the single home for the label-and-token legend. Other files reference it by name
rather than re-documenting the scheme.
