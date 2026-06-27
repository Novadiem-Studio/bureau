# Workflow Authoring Conventions

> Canon module extracted from `docs/conventions.md`. Load this file only when its concern is triggered by the task.

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

## Workflow step-line spec

Every numbered step in a `workflows/*.md` file has a **leading line** that the Ministry of Flow (aka Logistics)
parser (`mof/lib/workflow-parser.ts`) and a human skimmer both read for three things:
the agent, the tier, and the output. Author every step line to this shape so it is
self-describing for free.

**The shape:**

1. **Lead with the agent.** The FIRST bold span on the line is exactly and only the agent's
   cast name — `**The Architect**`, `**Analizer 2000**`, `**The Conductor**` — no verb prefix
   (`**Spawn The Witness**` is wrong), no role descriptor inside the bold (`**Survey**` is
   wrong), no parens inside the bold span. The agent name must be one of the resolvable cast
   names (see `docs/conventions/agent-contracts.md § File ↔ role alias table`); a name the
   parser can't resolve renders as a dark, agent-less node.
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
