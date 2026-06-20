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

## Workflow / runbook authoring quality bar

A workflow file, skill, or runbook is ready only when a fresh Conductor or Mechanic can run it
from written context alone. Natural-language directives are allowed; hidden assumptions are not.

Minimum shape:

- **Objective:** what outcome this directive exists to produce, in one sentence.
- **Inputs:** required files, params, environment, credentials, target app/host, and what is
  intentionally out of scope.
- **Steps:** ordered actions with the tool, script, skill, MCP, or CLI named wherever the choice
  affects repeatability.
- **Expected outputs:** artifacts, changed files, build outputs, logs, or handoff blocks the step
  must produce.
- **Done criteria:** concrete checks that prove the directive completed; never only "looks good".
- **Edge cases:** known failure modes, missing inputs, ambiguous targets, partial success, and
  generated/artifact churn.
- **Fallback behavior:** when to retry, when to use another tool, when to stop for human input,
  and what to report if the minimum quality bar cannot be met.
- **Observability:** for anything unattended, scheduled, webhook-driven, externally visible, or
  dev-deployed, name where success/failure is logged and how a human can inspect the run.

Boundary rule: keep judgment in workflows and deterministic repetition in tools. The workflow
describes routing, decisions, gates, and handoffs; scripts/skills/runbooks hold exact repeated
commands and reusable service procedures. If a natural-language step has become a fragile
sequence of exact shell/API calls, promote that sequence into a named script or skill and call it
from the workflow.

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

---

## Workflow step-line spec

Every numbered step in a `workflows/*.md` file has a **leading line** that the Ministry of Flow (aka Logistics)
parser (`society-desk/lib/workflow-parser.ts`) and a human skimmer both read for three things:
the agent, the tier, and the output. Author every step line to this shape so it is
self-describing for free.

**The shape:**

1. **Lead with the agent.** The FIRST bold span on the line is exactly and only the agent's
   cast name — `**The Architect**`, `**Analizer 2000**`, `**The Conductor**` — no verb prefix
   (`**Spawn The Witness**` is wrong), no role descriptor inside the bold (`**Survey**` is
   wrong), no parens inside the bold span. The agent name must be one of the resolvable cast
   names (see the file ↔ role alias table below); a name the parser can't resolve renders as
   a dark, agent-less node.
2. **Tier is its own standalone bold token.** Put one of the parser-supported tier tokens —
   `**cheap**`, `**standard**`, `**strong**`, `**frontier**`, or `**escalated**` — somewhere
   in the leading line as its own bold span, never buried inside a compound bold label like
   `**Survey (spawn, tier: standard)**`. Conductor-internal coordination steps that spawn
   nothing may omit the tier.
3. **`→` marks the produced output ONLY; it lives on the leading line and is the FIRST `→` in
   the step block.** Where the step writes a file or artifact, put `→ <target>` on the leading
   line — `→ spec.md (Architecture)`, `→ \`log.md\``, `→ ground-truth.md` — and make it the FIRST
   `→` anywhere in the whole step block (leading line + body). The parser reads the first `→` in
   the block as the node's output, so a leading line that carries ZERO arrows lets the parser fall
   through to a `→` in the body and mis-label the node — the leading line must carry the output
   arrow itself. Never use `→` for sequences or flow — write `01..NN`, `then`, or commas instead;
   a stray sequence arrow also mis-labels the node. Multiple output targets are comma-separated
   after a single `→`.

**Mode / role descriptor — how to add one WITHOUT breaking the lead span.** A step often needs
to say which mode or sub-role the agent runs in. Put it in PARENS immediately AFTER the bold
agent name, never inside it. The descriptor and the tier share the parens:

`**Analizer 2000** (Survey, **standard**) — read repo only … → \`ground-truth.md\``

The lead bold span is still `**Analizer 2000**` (the parser reads it); `Survey` is the mode in
prose-parens; `**standard**` is the standalone tier token inside the parens. This is the
canonical compound form. `feature.md` already uses it (`**Analizer 2000** (Analyst, **standard**)`).

**Anonymous spawns are banned.** A step that spawns a fresh-context agent must name a
resolvable cast member — even when the agent does a narrow slice of that persona's job. The
step's PROSE scopes the behavior (`read repo only, no doc claims`); the cast NAME just gives
the parser and a reader a tier-and-traceability anchor. Naming the agent does NOT import the
full persona — the prose is the instruction, the name is the label. (See "Naming vs. persona
scope" below.)

**Naming vs. persona scope.** When a step names a cast member for a slice of work narrower than
that persona's full frame (e.g. Analizer 2000 doing a repo-only Survey, not full requirements
extraction), the step's own prose is authoritative for what the agent does. The convention is:
NAME for routing + tier + traceability; PROSE for behavior. A reader who sees `**Analizer 2000**
(Survey, …)` reads the parenthetical mode and the prose, not the analyst persona's full
responsibilities list. This keeps the parser fed without over-applying the persona.

**Control steps are the exception.** Some steps are control nodes, not agent spawns: a gate, a
worktree operation, a human checkpoint. These are valid steps and do NOT lead with an agent cast
name. A control step leads with its control keyword in bold — `**Gate**`, `**Worktree**` — instead
of an agent name; it carries no tier token and no `→` output unless it genuinely produces one (a
`[CHECKPOINT]` marker may appear in its body). A reader and the parser both treat a control-keyword
lead as a non-agent node, so it is not a malformed agent step. Example:
`**Gate** — show the human the runbook and target; get a go before anything executes. \`[CHECKPOINT]\`.`

**Reference, don't re-document.** `index.md` and the `define-workflow` skill point at this
section; they do not restate it.

---

## Regression fixture file format

One canonical definition of the per-fixture file format used in `RUN_DIR/regression/`. Every workflow and persona file points at this section; nothing re-documents it inline.

**Location and naming:** Fixtures live in `RUN_DIR/regression/`, one file per fixture, named `<NN>-<slug>.md` (NN = capture order).

**Five required fields:**

| Field | Required | Meaning |
|-------|----------|---------|
| `name:` | yes | Human-readable fixture name. |
| `command:` | yes | Copy-pasteable command. The literal value `command: <none — phase accepted on visual inspection>` is the legal value when a phase had no discrete verification command (see "Handling on re-run" below). A `command:` whose passing signal is "it worked when I ran it" is malformed — the `expected:` field must carry an objective signal instead. |
| `expected:` | yes | The passing signal: exit code, log line, or visible output. Must be specific enough that a fresh agent running the command in a clean context can determine pass/fail without judgment. |
| `phase:` | yes | Prompt id + workflow that introduced the fixture (e.g. `04 · execute-plan`). |
| `owner:` | yes | Owning workflow/prompt — so a deliberate breaking change knows which fixture to retire and why. |

**Two optional state flags** (not required fields; presence signals special handling):

| Field | Optional | Meaning |
|-------|----------|---------|
| `slow:` | optional | `slow: human judgment required` — present when the fixture cannot meet the <2-minute re-run target. A `slow:` fixture is **carried as a Warning** on re-run, never a blocker. |
| `retired:` | optional | `retired: <phase> — <reason>` — present when a deliberate change makes the fixture incorrect. A file carrying a `retired:` flag is **skipped** (not failed) by the re-run gate. Do NOT delete retired fixture files; the retirement notation is the record of a deliberate breaking change. |

**Handling on re-run**

When the Conductor re-runs fixtures from `RUN_DIR/regression/` before dispatching the next prompt (per `workflows/execute-plan.md`), it applies the following rules per fixture file:

- **`retired:` present** → skip; not run, not a blocker.
- **`slow:` present** → skip running; carry as a Warning in the re-run log.
- **`command:` is the literal `<none — phase accepted on visual inspection>`** → skip; carry as a Warning (same handling as `slow:`); NOT run, NOT a blocker. This rule must be stated explicitly here so the legal `<none>` value cannot silently defeat the re-run gate (FR 4, Edge Case 1).
- **All other fixtures** → run the `command:` and compare output to `expected:`. A failure BLOCKS the next prompt; the logged failure names the fixture file, the command, and the actual failing output (never a generic "regression failed").
- The re-run result (per-fixture: pass / skip-Warning / fail-Blocker) is logged to `RUN_DIR/log.md` before the next coder is dispatched. This log entry is the inspectable artifact that makes the gate non-discretionary (AC 11).

**Passing signal, not a judgment rule:** A fixture whose `expected:` field is a vague judgment ('it worked', 'looks right') is malformed; the expected signal must be objective enough for a fresh agent to evaluate from the command's output alone.

No other section in the framework re-documents this format. Workflow and persona files reference this section by name.

---

## Battle-test matrix file format

One canonical definition of the `battle-test.md` format required before any workflow or prompt is promoted to canon. Every workflow and persona file points at this section; nothing re-documents it inline.

**Location and naming:** A file named `battle-test.md`, placed alongside the workflow or prompt file being promoted to canon.

**When required:** Before any canon promotion — adding a row to `workflows/index.md` (workflow) or committing a prompt folder to `plans/` as the accepted prompt set (prompt).

**File structure**

1. **`## Run <date>` archive block** — the file always opens with a `## Run <date>` heading above the current case table. The date is the date of the run being recorded. On re-promotion (when a workflow or prompt is updated and re-entering canon), the prior `## Run` block is left in place; a NEW `## Run <date>` heading + fresh case table is added ABOVE it. "Re-run in full" means: all cases are re-evaluated and results written fresh — never appending new rows to an existing table. The most recent `## Run` block is the live one. This is a re-run obligation on the Conductor (on `Promotion to canon: yes`, the Conductor re-runs the full matrix and writes a fresh `## Run <date>` block as part of promoting); prior blocks are the audit history.

2. **Case table** — the matrix contains 3–5 representative cases (FR 8). Each row records four required fields (FR 9):

   | Field | Description |
   |-------|-------------|
   | Case name | A short, distinct name for this case. |
   | Input description | Enough detail for a fresh agent to reproduce the run — project type, inputs, any unusual context. |
   | Expected outcome | What "pass" looks like for this case (observable, not judgmental). |
   | Actual result | `pass` or `fail` + a one-line note on any deviation. |

3. **Case representativeness requirement** — the 3–5 cases MUST include:
   - At least one **happy-path / typical** case.
   - At least one **edge case** (unusual-but-valid input or uncommon input shape) — named as such.
   - At least one **failure mode** (bad input, missing dependency, or the scenario the workflow is most likely to fail on) — named as such.

   Case count alone does not satisfy this requirement. A matrix of 3–5 cases that are all happy-path variants under different labels is NOT representative and does not pass the gate, regardless of case count (Edge Case 3).

**FR 12 open-ended-generative interpretation**

For workflows with open-ended input spaces (e.g. arbitrary human text as input), the three category requirements above are re-interpreted as operational scenarios: (1) one nominal run, (2) one run that hits an expected edge (empty input, very long input, or missing context), (3) one run that the workflow must refuse or checkpoint rather than complete. The four per-case fields and the 3–5 count are unchanged.

**`waiver:` block** (optional, but with strict validity rules):

A `waiver:` block may appear in `battle-test.md` when one or more cases fail and Robin has explicitly accepted the failure as a known limitation. A valid waiver MUST name ALL THREE of:
- The failing case (by name).
- The reason the failure is known and accepted.
- Robin's explicit acceptance (a statement attributing the decision to Robin, not a blank entry).

A `waiver:` block that is blank, that names the failing case but not the reason, or that names neither, is NOT a valid waiver and does not close the battle-test Blocker (AC 5, Edge Case 4). Example of an INVALID waiver: `waiver: accepted`. A waiver is a conscious exception with a named reason, not a default.

A valid waiver closes the battle-test gate for the specific failing case it names. It does not close the gate for unnamed cases.

No other section in the framework re-documents this format. Workflow and persona files reference this section by name.

---

## Failure signature format

One canonical definition of how a single failure is recorded in `RUN_DIR/log.md` so that the same failure recurring in a later run is countable. Every workflow and persona file points at this section; nothing re-documents it inline.

**Five required fields:**

| Field | Value shape |
|-------|-------------|
| `failing-step:` | the command, tool, runbook step, or workflow directive that failed |
| `observed-error:` | the literal error message or symptom |
| `suspected-layer:` | exactly one value from the vocabulary table below |
| `artifact-patched:` | the durable framework file modified, OR the literal `none — carried` followed by a reason |
| `verification-case:` | the smallest copy-pasteable command or inspection that confirms the fix |

**`suspected-layer:` vocabulary** — one row per layer, both columns authored together. The left column is the canonical value written in the `suspected-layer:` field; the right column is the slug `<layer>` token used inside the failure-signature slug. The slug token is the canonical value with spaces and slashes collapsed to single hyphens, so the slug stays one shell-safe word. A new layer value adds one row, both columns at once.

| `suspected-layer:` value (canonical) | slug `<layer>` token |
|---|---|
| `script` | `script` |
| `workflow directive` | `workflow-directive` |
| `env/preflight` | `env-preflight` |
| `external contract` | `external-contract` |
| `target code` | `target-code` |

**Failure-signature slug** — the stable key under which a failure is recorded and counted:

```
<run-slug>-<NN>-<layer>-<short-description>
```

- `<run-slug>` — the RUN_DIR slug (the `<yyyymmdd>-<task-slug>` dir name). Ties the slug to one run, so distinct-run counting is reading the prefix, not guessing.
- `<NN>` — two-digit ordinal of the failure within that run (`01`, `02`, …), in capture order. Makes two failures in one run distinct keys while sharing a run prefix.
- `<layer>` — the slug token from the vocabulary table above (the hyphenated form of the `suspected-layer:` value).
- `<short-description>` — 2–5 lowercase hyphenated words naming the specific failure (e.g. `preflight-key-missing`, `worktree-stale-lock`). The same failure recurring in a later run gets the SAME `<short-description>` — this is what makes recurrence countable.

Worked example:

```
20260619-reusable-learning-loop-01-env-preflight-key-missing
```

Recurrence detection counts the **`<layer>-<short-description>` tail**, not the whole slug, so the same failure in two different runs (different `<run-slug>` and `<NN>`) still matches.

No other section in the framework re-documents this format. Workflow and persona files reference this section by name.

---

## Recurrence rule

A lesson appearing in two `run:` entries in `output/studio/lessons.md` must be either promoted to a durable framework artifact or explicitly deferred with a written reason before the second run's close-out is accepted.

**The Challenger-verifiable count test:**

> Count the distinct `run:` slugs among `output/studio/lessons.md` entries whose `failure-signature:` shares the same `<layer>-<short-description>` tail. If that count is **≥ 2**, the entry's `status:` MUST be `promoted` or `deferred: <reason>` — never blank, never `scoped-local`. A `count ≥ 2` entry that is blank or `scoped-local` is a **Blocker** at the second (or later) run's close-out.

- **Promoted** means a named change was made to a canonical file (convention, runbook, script, workflow, or persona).
- **Deferred** means a written rationale explains why promotion is intentionally withheld and names the next review trigger.
- The count is distinct `run:` values, NOT occurrences. Two failure signatures in the same run are one run (not two).
- `scoped-local` is disallowed at `count ≥ 2` on purpose: a failure that recurred across two runs is, by evidence, not a one-off.
- A third carry without promotion is a Blocker that forces the Conductor to promote or `[CHECKPOINT]` for a human decision.

---

## Convention-retirement rule

This rule exists to prevent this document from accumulating superseded blocks that cold reviewers follow as live instructions. To deprecate a section in `docs/conventions.md`, three steps must be taken.

**Step 1 — Mark the heading.** Append `— **SUPERSEDED:** replaced by [§ <new section name>]` to the retired section's heading line. The marking lives ON the heading so a skimmer and The Challenger see it at the section anchor. Example:

`## Old fixture format — **SUPERSEDED:** replaced by [§ Regression fixture file format]`

**Step 2 — Set a removal date.** Immediately under the marked heading, one line:

`Removal: <bundle id or calendar quarter>` (e.g. `Removal: Bundle 03` or `Removal: 2026 Q4`) — never "eventually". An overdue removal date is a Blocker **only on a review that actually touches or cites the retired section** — editing that section, or following a `§` citation into it — not on any review of `docs/conventions.md`. (This scoping prevents the overdue date from ambushing a Conductor editing an unrelated section of the same file.) When the overdue date fires, the block must be removed or the date explicitly extended with a written reason.

**Step 3 — The Challenger check.** A section carrying `**SUPERSEDED:**` that is still cited as a **live instruction** by `§` reference in any persona or workflow file is a **Blocker** until the citation is repointed to the replacement section. (Citations inside the retired block itself, or in this retirement rule, don't count — only live instructional citations elsewhere.)
