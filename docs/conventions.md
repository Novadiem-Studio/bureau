# Agent-Framework Block Conventions

This is the one canonical location for the three block conventions used across all persona
files in the Novadiem agent-framework. Every persona file that gains an `## Inputs` block
carries a one-line `Convention: docs/conventions.md` pointer; nothing else re-documents these
conventions.

---

## Inputs block spec

The `## Inputs` block appears in every non-exempt persona file, immediately before the
heading specified for that role. It declares the artifact contract for the spawned agent:
what the Conductor passes, what the agent opens on its own, and what it must NOT receive.

### Generic template (used by single-mode roles)

```markdown
## Inputs

Reads (handed by the Conductor):  <params/artifacts named in the spawn prompt>.
Reads (self-read):  <artifact § section>, <artifact (full)> the agent opens itself once spawned.
Does NOT receive:  <tempting-but-wrong input> — <one-line why>.
```

Rules:

- `Reads (handed by the Conductor):` lists the params and artifact paths the spawn prompt
  supplies directly. The Conductor's spawn step must actually pass these.
- `Reads (self-read):` lists what the agent opens on its own once running (prompt files, plan
  sections, a diff in the worktree, sub-app CLAUDE.md + named skills). Omit this line if the
  role has nothing self-read, or write `Reads (self-read): none`. Omit the "handed" line if
  everything is self-read. Collapse to a single `Reads:` line when both halves are identical
  and no split is needed.
- Name `§ section` (not the whole file) when a section is all the role needs; use `(full)`
  when the role genuinely reads end-to-end.
- `Does NOT receive:` names at least one tempting-but-wrong input with a one-line reason.
- Add a `Convention: docs/conventions.md` pointer line under every `## Inputs` block in each
  persona file (not in this conventions doc itself).

### Mode-branched variant (used by The Cleric / The Counselor / The Witness — one pair per mode, under a bolded mode label)

```markdown
## Inputs

**mode: brief** — Reads:  spec.md § Requirements, § Acceptance criteria; project-context.md (if pointed at it).
                  Does NOT receive:  plan.md data-model internals, log.md — the brief decision doesn't need them.
**mode: ingest** — Reads:  RUN_DIR/design/handoff/ (the exported bundle); spec.md § Requirements (for real entity names).
                   Does NOT receive:  the Architect's rationale — the manifest is built from the bundle, not the argument.
**mode: review** — Reads:  RUN_DIR/design/manifest.md; the scoped prompt built; The Mage's changed files.
                   Does NOT receive:  log.md — fidelity is judged against the manifest, not the history.
```

### Highest-stakes instance — The Challenger

Write this out in full, verbatim; it is the load-bearing case for the whole convention:

```markdown
## Inputs

Reads (round 1):  RUN_DIR/spec.md (full), RUN_DIR/plan.md (full), and spec.md § Acceptance criteria — review them together.
Reads (round 2):  RUN_DIR/prompts.md (full), and spec.md § Acceptance criteria — and NOTHING ELSE.
Round 2 is a FRESH SPAWN: the re-spawn itself is legitimate and expected; what is prohibited is
being handed round 1's findings, rationale, or notes. You carry nothing forward from round 1 —
you read prompts.md (full) + § Acceptance criteria with the same cold eyes as round 1.
Does NOT receive:  log.md, prior-round Challenger findings, the Architect's design rationale —
                   your coldness depends on it; these anchor you toward agreeing with a design
                   you never watched get argued. If you were handed any of them, do NOT review:
                   write a single line to RUN_DIR/log.md —
                   `CHALLENGER FLAG: received <input> — coldness broken, did not review` —
                   naming which prohibited input you got, and stop. Produce no findings.
```

---

## Structured handoff footer spec

Every persona file ends with exactly ONE handoff block. The new footer = the three standard
fields first (fixed order), then every role-specific load-bearing field the prior block
carried, unchanged, under the role's existing block title. The old block is REPLACED by this
merged block — never left beside it. No file ends with two blocks.

### The merge rule

**Fixed standard prefix** (always these three, always this order):

```
Consumed: <artifacts actually read this run — checked against the ## Inputs contract; note any deviation>
Produced: <what this agent wrote to disk this run — absolute or RUN_DIR-relative paths>
Passing forward:
- <one item the next agent or Conductor must know>
- <…one bullet per item, OR the single token: none>
```

Rules:

- `Consumed` is the runtime receipt. Names what was actually read; flags any mismatch with the
  declared `## Inputs`. For The Challenger: add a one-line `Excluded held: log.md, prior
  findings, rationale — not received` assertion (or trigger the CHALLENGER FLAG path if any
  were received).
- `Produced` absorbs each prior block's `Wrote:` / `Files changed:` / `Written:` field — they
  are the same thing under a standard name.
- `Passing forward` is a bullet sub-list, one item per line, or the single token `none`. The
  Conductor copies each bullet 1:1 to one `carried_items` entry in `state.json`.
- Fold `Wrote` / `Files changed` / `Written` into `Produced`; keep every other prior field
  verbatim after the standard prefix.
- The Mage's `New packages installed` (with its install-command note) and all build-party
  `Checkpoint` fields are load-bearing — they MUST survive the merge in their original form.

### Mode-branched merge rule

For The Cleric (3 modes, 4 footers), The Counselor (2 modes, 2 footers), and The Witness
(2 mode footers), apply the identical standard prefix to each mode footer independently.
Each mode footer gains `Consumed` / `Produced` / `Passing forward` and keeps its
mode-specific fields.

---

## Acceptance criteria block spec

This block goes at the END of the Analyst's `spec.md` output (not in the Analyst's persona
handoff). The Challenger checks these items by number; the Spellwright's prompts cite the
number they satisfy.

```markdown
## Acceptance criteria

The Challenger checks these by number; the Spellwright's prompts cite the number they satisfy.

1. <Testable statement — "Every <thing> <has/does> <observable property>">
2. <…>
3. <…>
```

Rule: each criterion must be checkable by inspecting the artifact ("Every endpoint returns a
typed error shape"), never a quality judgment ("Error handling is robust").

---

## Passing forward → state.json/carried_items 1:1 mapping rule

- `Passing forward` in the handoff footer is the human-readable source.
- `carried_items` in `state.json` is its transcription.
- The Conductor copies each `Passing forward` bullet to one `carried_items` entry —
  populating from it, never in addition to it.
- A `none` token in `Passing forward` means no new carried items from this agent.
- They are NOT allowed to diverge.
- For footer-exempt droids (Scoot, Tally): the `Passing forward` → `carried_items` rule does
  not reach them (they have no structured footer). The Conductor must manually lift Tally's
  `Needs a real role` and Scoot's `Too big for me` escalation lines into `carried_items` when
  a droid raises one — these are a "Passing forward" by another name.

---

## Exempt / partial list and file ↔ role alias table

### Exempt roles (no `## Inputs` block, no footer change)

- `scoot.md` (Scoot, shop droid) — one-errand role, no fixed artifact set to declare. The
  Conductor writes the specific errand inline each spawn; an Inputs block would be vacuous or
  overspecified. The existing `SCOOT — DONE` footer (Errand / Result / Too big for me)
  adequately covers consumed + produced. No change.
- `tally.md` (Tally, shop droid) — same rationale. Existing `TALLY — DONE` footer (Errand /
  Findings / Scope covered / Needs a real role) adequate. No change.

### Partial treatment

- `witness.md` (The Witness) — gets a structural `## Inputs` block covering the four spawn
  params (`STUDIO_ROOT`, `INSTALL_PATHS`, `MODE`, `TARGET_RUN`). Its existing mode-specific
  handoff footers (`WITNESS BRIEFING COMPLETE`, `WITNESS DIGEST COMPLETE`) gain `Consumed` +
  `Produced` fields; `Passing forward: none` is the norm (no next pipeline agent). Note:
  the Witness's `Consumed` is **informational-only — NOT audited against a contract**. The
  Witness reads wholesale cross-run (every run's `state.json`, log tails, spec titles across
  the studio), so there is no fixed per-run input set to check it against. The OQ3 deviation
  check does not apply to the Witness. Its `Does NOT receive:` is a scope statement ("a
  single RUN_DIR scope — it reads across runs"), not a tempting input an audit could flag.

### File ↔ role alias table (single anchor — reference this, don't re-derive elsewhere)

| Persona file | Cast / role name |
|---|---|
| `orchestrator.md` | The Conductor (Orchestrator) |
| `analyst.md` | Analizer 2000 (Analyst) — note: "Analizer" with an "i", "2000" — deliberate stylization, not a typo |
| `architect.md` | The Architect |
| `critic.md` | The Challenger (Critic) |
| `designer.md` | The Cleric (Designer) |
| `prompt-engineer.md` | The Spellwright (Prompt Engineer) |
| `voice.md` | The Counselor (Voice) |
| `frontend.md` | The Mage (Frontend) |
| `backend.md` | The Systemsmith (Backend) |
| `sysadmin.md` | The Mechanic (Sysadmin) |
| `coupler.md` | The Coupler |
| `witness.md` | The Witness (Archive) |
| `scoot.md` | Scoot (shop droid) — EXEMPT |
| `tally.md` | Tally (shop droid) — EXEMPT |
