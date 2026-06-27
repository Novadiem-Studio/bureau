# Failure Signature Conventions

> Canon module extracted from `docs/conventions.md`. Load this file only when its concern is triggered by the task.

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
