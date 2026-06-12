# Provider-Neutral Model Routing Plan

Date: 2026-06-12

## Purpose

Update the agent-framework model policy so the Society can run through Claude Code, Codex/OpenAI,
Hermes, Mission Control, or OpenRouter without rewriting role instructions.

The goal is not "always use the strongest model." The goal is:

- start each role on the least expensive model tier that is usually good enough;
- preserve fresh-context isolation where the workflow depends on it;
- escalate only when the work gives evidence that a stronger model is needed;
- log model choices so a run can be audited and improved later.

## Current Problem

The framework already has useful model machinery:

- `config/model-policy.json`
- `config/experiments/*.json`
- `scripts/resolve-model-tiers.sh`
- role notes in `agents/orchestrator.md`

But the tier names and runtime mapping are Claude-specific:

- `sonnet`
- `opus`
- `premium` as `claude-fable-5`
- `claude` quota fields in the usage snapshot

When the same framework runs inside Codex or a future Hermes/Mission Control runtime, those names
turn into folklore instead of policy. The Conductor can still spawn subagents, but it cannot make
intentional budget-aware model choices across providers.

## Design Principle

Split model routing into three layers:

1. **Role policy**
   - The Society role: Conductor, Challenger, Architect, Mage, Systemsmith, etc.
   - Default capability tier.
   - Allowed tiers.
   - Escalation and de-escalation triggers.
   - Fresh-context requirements.

2. **Capability tier**
   - Provider-neutral names such as `cheap`, `standard`, `strong`, `frontier`, `escalated`.
   - Describes job difficulty and risk, not a vendor model name.

3. **Runtime adapter**
   - Maps capability tiers to actual model IDs and settings for Claude, OpenAI/Codex, Hermes,
     Mission Control, or OpenRouter.
   - Owns provider-specific knobs such as reasoning effort, service tier, context window,
     tool support, and cost hints.

## Proposed Capability Tiers

| Tier | Meaning | Typical use |
|------|---------|-------------|
| `cheap` | Fast, low-cost, routine transformation | copy cleanup, file surveys, simple status updates |
| `standard` | Good general model, low/medium reasoning | Analyst, Cleric ingest, Spellwright first pass, routine Mechanic |
| `strong` | Prior-frontier or high-capability model | Architect first pass, Systemsmith, Challenger first pass, Mage first pass |
| `frontier` | Current best available practical model | final gates, high-risk architecture, subtle UI/state implementation |
| `escalated` | Strongest model plus highest reasoning/time budget | repeated failures, hard adjudication, security/data/money risk |

The important shift: `frontier` is not the default. A model that was best-in-class a few weeks ago
is usually still excellent for first-pass planning, critique, and implementation.

## Proposed Role Defaults

| Role | Default tier | Escalate when |
|------|--------------|---------------|
| Conductor | `strong` | conflicting agent outputs, hard adjudication, second critic loop, checkpoint decisions |
| Analyst | `standard` | huge scope, fuzzy product boundaries, regulated/high-stakes domain |
| Architect | `strong` | novel architecture, irreversible data model choices, critic finds real design gaps |
| Challenger | `strong` | final pre-build gate, high-stakes backend/security/data work, prior review missed something, second review loop |
| Cleric | `standard` | design handoff is ambiguous, manifest extraction fails, UI drift review is subtle |
| Spellwright | `standard` | prompts are incoherent after one fix, many cross-repo dependencies |
| Counselor | `standard` | highly sensitive audience, legal/medical/political copy |
| Mage | `strong` | complex state, design fidelity failure, animation/layout bugs, high-risk mobile/web split |
| Systemsmith | `strong` | auth, migrations, idempotency, payments/credit, permissions, data integrity |
| Mechanic | `standard` | prod deploys, irreversible infra, secret handling, database restore/migration |

Fresh context remains a separate requirement. In particular, Challenger must be fresh-context even
when it runs on `standard` or `strong`; otherwise the log should mark the review as same-context.

## Configuration Shape

Add a provider-neutral policy file:

```json
{
  "version": 2,
  "default_runtime": "codex",
  "manual_experiments": [],
  "roles": {
    "challenger": {
      "agent": "The Challenger",
      "default_tier": "strong",
      "allowed": ["strong", "frontier", "escalated"],
      "fresh_context_required": true,
      "escalate_when": [
        "final_gate",
        "second_critic_loop",
        "high_stakes_backend_or_security",
        "prior_review_missed_issue"
      ]
    }
  }
}
```

Add runtime adapters:

```text
config/runtimes/claude.json
config/runtimes/openai.json
config/runtimes/openrouter.json
config/runtimes/hermes.json
```

Example OpenAI/Codex adapter shape:

```json
{
  "runtime": "codex",
  "tiers": {
    "cheap": {
      "model": "small-fast",
      "reasoning_effort": "low"
    },
    "standard": {
      "model": "good-general",
      "reasoning_effort": "medium"
    },
    "strong": {
      "model": "prior-frontier",
      "reasoning_effort": "high"
    },
    "frontier": {
      "model": "best-available",
      "reasoning_effort": "high"
    },
    "escalated": {
      "model": "best-available",
      "reasoning_effort": "xhigh"
    }
  }
}
```

Use symbolic model aliases in the framework repo. Provider-specific installs can map those aliases
to real model IDs in a local, possibly untracked runtime file.

## Escalation Rules

Escalation should be event-driven:

- A critic finds real blockers in the same phase twice.
- A specialist output is thin, contradictory, or misses obvious anchors after one routed fix.
- The Conductor has to adjudicate a real disagreement between two specialists.
- The task touches auth, permissions, money/credit, migrations, data retention, irreversible infra,
  or public launch risk.
- The human explicitly asks for the strongest pass.

De-escalation should also be explicit:

- The task is mechanical and has a strong local pattern.
- A prior prompt/spec/manifest is already vetted and the role is translating it.
- The current budget snapshot says a high-tier quota is hot.
- The output will be reviewed by a stronger fresh-context Challenger before execution.

## Usage And Budget Snapshot

Replace Claude-specific usage assumptions with a provider-neutral snapshot model:

```json
{
  "polledAt": "2026-06-12T09:00:00-07:00",
  "ok": true,
  "providers": {
    "openai": {
      "sessionUsedPercent": 62,
      "weeklyUsedPercent": 48
    },
    "anthropic": {
      "sessionUsedPercent": 20,
      "weeklyUsedPercent": 77
    },
    "openrouter": {
      "monthlySpendPercent": 41
    }
  }
}
```

The resolver should not need to know every provider's billing semantics. It only needs normalized
signals such as:

- session pressure;
- weekly/monthly pressure;
- per-provider availability;
- whether a provider/runtime supports fresh subagent context and tools.

## Runtime Requirements

Each runtime adapter should declare capabilities:

```json
{
  "supports_fresh_context_subagents": true,
  "supports_parallel_subagents": true,
  "supports_filesystem_tools": true,
  "supports_browser_tools": false,
  "supports_reasoning_effort": true
}
```

If a runtime cannot satisfy a role's hard requirement, the Conductor must log it:

- `fresh_context_required_but_unavailable`
- `same_context_review`
- `tools_missing`
- `model_alias_unresolved`

For Challenger, lack of fresh context should downgrade the review's authority rather than silently
pretending it was a true cold review.

## Implementation Phases

### Phase 1 — Add Provider-Neutral Policy

- Add `config/model-policy.v2.json`.
- Keep `config/model-policy.json` as the Claude-compatible legacy file during transition.
- Add role fields:
  - `default_tier`
  - `allowed`
  - `fresh_context_required`
  - `escalate_when`
  - `deescalate_when`
  - `lock` only when absolutely required.
- Set Challenger default to `strong`, not absolute best, with clear escalation to `frontier` /
  `escalated`.

### Phase 2 — Add Runtime Adapters

- Add `config/runtimes/claude.json`.
- Add `config/runtimes/openai.json`.
- Add placeholder `config/runtimes/openrouter.json`.
- Add placeholder `config/runtimes/hermes.json`.
- Use aliases for real model IDs so private/local preference can be overlaid later.

### Phase 3 — Update Resolver

- Update `scripts/resolve-model-tiers.sh` or replace it with `scripts/resolve-model-routing.sh`.
- Inputs:
  - provider-neutral role policy;
  - selected runtime;
  - runtime adapter;
  - usage snapshot;
  - manual experiments.
- Output:
  - `~/.novadiem/resolved-model-routing.json`;
  - per-role resolved tier;
  - per-role runtime model alias / model id;
  - per-role reasoning effort;
  - active escalation/de-escalation reasons;
  - any capability warnings.

### Phase 4 — Update Orchestrator Docs

- In `agents/orchestrator.md`, replace Claude-specific tier language with provider-neutral tier
  language.
- Keep a Claude runtime section for existing Claude Code usage.
- Add Codex/OpenAI and OpenRouter/Hermes runtime sections.
- Add a rule: model choice is resolved from `RUN_DIR/model-routing.json`, not from workflow prose.
- Add a rule: every spawn is logged with role, tier, runtime model, reasoning effort, and whether
  fresh context was actually used.

### Phase 5 — Update Experiments

Replace Claude-specific experiments with provider-neutral experiments:

- `budget-pressure-standardize`
- `architect-frontier`
- `mage-frontier`
- `challenger-frontier-final-gate`
- `systemsmith-standard`
- `openrouter-budget-route`

Experiments should override tiers or runtime, not hardcode vendor model names unless they live in a
runtime adapter.

### Phase 6 — Update Checks

- Extend `check-framework.sh` to validate:
  - every role has a valid default tier;
  - every role's allowed tiers exist;
  - runtime adapters define every tier used by the policy;
  - experiments only use valid tiers;
  - fresh-context-required roles are called out in docs;
  - legacy Claude files still pass until removed.

### Phase 7 — Trial Run

Run one low-risk workflow in Codex/OpenAI mode:

- Choose a docs-only or prompt-generation task.
- Start utility roles on `standard`.
- Run Challenger on `strong`.
- Escalate only if the output is thin or contradictory.
- Compare cost/quality against a frontier-heavy run.
- Record findings in `config/runtimes/README.md` or a run retrospective.

## Acceptance Criteria

- A Conductor can start a run and resolve model routing without knowing vendor model names.
- Claude Code still works through the Claude adapter.
- Codex/OpenAI runs can choose cheaper first-pass models and escalate by rule.
- Hermes/Mission Control can provide an OpenRouter-backed adapter without editing agent personas.
- The run log shows which model/tier/reasoning each subagent used.
- Challenger freshness is tracked independently from model strength.
- No role instruction says `opus` or `sonnet` as a universal truth; those appear only in the Claude
  adapter or Claude-specific notes.

## Non-Goals

- Do not rewrite the Society roles.
- Do not remove Claude support.
- Do not require the same model provider for every role in a run.
- Do not make the Conductor guess model IDs from memory.
- Do not treat `frontier` as a status symbol; it is a tool for specific risk.

## Open Questions

- Should final Challenger review always escalate to `frontier`, or only when the prompt/code surface
  is high-risk?
- Should provider choice be per-run, per-role, or per-spawn?
- Should Mission Control own all runtime mapping, leaving this repo with only role policy?
- Should local/private model aliases live in `~/.novadiem/model-aliases.json` so the canonical repo
  avoids stale provider model IDs?
- How should the resolver score "fresh context available" when a runtime can spawn agents but cannot
  prevent context leakage?

## First Concrete Patch

The smallest useful implementation should:

1. Add `config/model-policy.v2.json`.
2. Add `config/runtimes/openai.json` and `config/runtimes/claude.json`.
3. Add `scripts/resolve-model-routing.sh`.
4. Update `agents/orchestrator.md` to prefer `RUN_DIR/model-routing.json`.
5. Update `check-framework.sh` to validate the new files.
6. Run one docs-only framework task using the new routing and record the result.
