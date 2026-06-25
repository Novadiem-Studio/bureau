# Pre-flight self-checks v2: split the Challenger pattern playbook across Architect and Spellwright

Supersedes `architect-challenger-pre-flight.md` (v1). v1 put all 12 checks on the Architect; v2
corrects that by routing each check to the agent whose artifact actually contains the defect.

We synthesized 130 Challenger findings across 8 runs and identified 17 recurring pattern
categories. The top five (missing-edge-case 24, internal-contradiction 22, wrong-api-shape 18,
under-specified 17, wrong-call-site 12) account for roughly 70% of all findings. These are not
random mistakes. They are structural blind spots in how the framework produces spec, plan, and
prompts.

The goal: catch these before the Challenger does, so the Challenger's passes verify build
correctness instead of fixing avoidable spec and prompt defects. No extra agent spawn.

## What v2 changes from v1

1. **Two owners, not one.** The Architect produces only `spec.md` and `plan.md`. Prompts are
   written later by the Spellwright (`prompt-engineer.md`). v1's checklist repeatedly audited
   "prompts" the Architect never sees. v2 splits the playbook into an Architect self-check and a
   Spellwright self-check.
2. **Evidence, not a verdict.** Each answer must cite the fact that settles it, not a bare Y/N.
3. **Mechanical triggers, not self-assessment.** A grep over the artifact decides which conditional
   blocks run, instead of trusting the agent to notice it owes a check.
4. **A success metric.** Track `critic_loops` before/after, or cut the checks as theater.

## The key insight: check each defect where its artifact exists

The workflow order is:

```
Architect -> spec.md + plan.md -> [checkpoint] -> Challenger R1 (spec+plan)
  -> Spellwright -> prompts.md -> Challenger R2 (prompts)
```

When we re-tag the 130 findings by artifact, **~55 of them (~42%) are against prompts** and are
caught in Challenger round 2. The Architect cannot self-check a prompt that does not exist yet.
Import-completeness is the clearest case: imports only appear in prompt code, so the Architect has
nothing to inspect.

So the playbook splits into two self-checks, each living where its artifact is produced:

- **Architect self-check** runs against spec + plan. It verifies *decisions and claims*: do the
  numbers agree, are edge cases enumerated, are deferred items registered, are the architectural
  claims about live APIs / deploy topology / dependencies / async model actually true.
- **Spellwright self-check** runs against prompts. It verifies the *literal code* the prompt tells
  a coder to write: exact file paths, imports present, real field names, correct call sites, exact
  env keys.

Same defect class, two altitudes. The Architect confirms the fact; the Spellwright confirms the
prompt renders that fact into correct literal code. That is why this is two file edits
(`agents/architect.md` and `agents/prompt-engineer.md`), not one.

## What we want to accomplish

1. Fewer Challenger blockers that force an Architect revision loop (`critic_loops.architect++`).
2. Fewer Spellwright prompts that produce wrong-call-site, import-missing, or wrong-field bugs at
   build time (the round-2 findings).
3. A forcing function that makes both agents verify live facts instead of reasoning from memory.

## Two design rules that make this real, not theater

**Evidence, not a verdict.** A bare "Y" costs nothing and means nothing. Under token pressure an
agent writes "Y" without running the grep, and the check becomes the same noise the name-lint
bundle warns about: a check that always passes trains the reader to ignore it. Each answer must
cite the evidence that settles it, the same discipline the Challenger already uses:

> `API shapes: Y — apiFetch (lib/api.ts:42) returns parsed JSON, not Response`
> `File paths: N — InviteScreen.tsx is at src/ui/auth/, prompt 3 says src/ui/invitations/`

**Mechanical triggers, not self-assessment.** An agent that did not notice it added a dependency
will not fire the dependency check either. Do not leave the trigger to judgment. A short grep over
the plan/prompt text decides which conditional blocks run:

| Trigger grep (over plan.md / prompts.md) | Lights up |
|---|---|
| existing-project mode declared | API shapes, file paths, stale symbols, imports |
| `pip install`, `npm i`, new package in requirements | external-dependency block |
| `.env`, `systemd`, `deploy`, vhost, served asset path | deploy + env block |
| `async def`, `Promise<`, Next.js 13+, FastAPI | async/sync block |
| AC asserts a status code / field name / test string | AC-trace block |

The always-run checks need no trigger. Everything else is gated, so neither agent burns time on a
block that cannot apply (a greenfield CLI tool runs 3 checks, not 12).

## Output discipline

Surface only the N's and the non-obvious Y's (a Y where verification actually found something worth
stating). A run that produces 12 dutiful "Y" lines is noise. Each N becomes a "Passing forward"
note in the handoff, surfaced to the Challenger rather than hidden, and is usually fixable on the
spot.

---

## Architect self-check (against spec + plan)

### Always run

1. **Internal consistency** — every count, enum value, or name that appears twice in spec/plan:
   both instances agree. (internal-contradiction: 22)
2. **Edge enumeration** — every input that can be null, zero, empty, or over a limit has a stated
   handling rule in the spec. (missing-edge-case: 24)
3. **Deferred items registered** — every out-of-scope behavior is a named open question or explicit
   callout, not a buried comment or silence. (deferred-not-documented: 7)

### Existing-project mode

4. **Architectural API claims** — every claim the Architecture section makes about a live endpoint,
   return shape, or signature is grep-verified against the real code. (the architectural half of
   wrong-api-shape: 18)
5. **Target-file existence** — every file the plan names as an edit target exists at that path, and
   every function the plan says it will edit is defined there. (the coarse half of wrong-call-site: 12)
6. **Stale symbol scan (plan level)** — every config key, class, or file name the plan references
   still exists under that name in the live code. (stale-name: 8)

### Conditional (mechanical trigger)

7. **Deploy topology** [deploy/infra] — every asset/route the plan assumes is reachable at runtime
   is in the served path, not just the repo root; health-check targets match the real vhost.
   (deployment-path-gap: 9)
8. **Env vars named** [deploy/external] — every env var the feature needs is named in the spec and
   slated for `.env.example`; base URLs are checked against the deployed routing config. (env-config: 5)
9. **External dependency decision** [new deps] — every new library/service/runtime-capability the
   plan adds has an explicit provisioning step before first use. (external-dependency-unstated: 5)
10. **Async model decision** [async stack] — the architecture picks the right async/sync model for
    the framework (e.g. Next.js 15 route params are a Promise). (architectural async-sync: 3)
11. **AC -> plan trace** [ACs cite values] — every AC asserting a status code, field, or test string
    has an owning plan step that will produce exactly that value. (ac-implementation-mismatch: 8)

## Spellwright self-check (against prompts)

Runs after the Architect, against `prompts.md`. This is where the ~42% prompt-artifact findings live.

1. **File-path audit** — every path named in a prompt exists at that exact location; every function
   edit lands in the file where the function is actually defined. (wrong-call-site)
2. **Import completeness** — every symbol a prompt's code uses (stdlib helpers, ORM funcs,
   decorators, `logger`, types) has an import present in the prompt or already in the target file.
   (import-missing)
3. **Literal API shapes** — every field name, return type, and call signature written into prompt
   code matches the live code, grep-verified. (the literal half of wrong-api-shape)
4. **Exact call sites** — edits land in the right spot: inside the wrapper callback when there is
   one, carrying load-bearing `try/except` verbatim, not at a guessed line number. (wrong-call-site)
5. **Literal env keys** — `.env.example` additions use the correct key names, complete set.
   (env-config)
6. **Literal async/sync signatures** — the function signature the prompt dictates matches the
   framework contract (no blocking sync httpx inside an async route). (async-sync)
7. **Code-level stale names** — counter names, config keys, and symbol names in prompt prose match
   the real keys in code, not paraphrases. (stale-name)

Same evidence-not-verdict and output-discipline rules apply.

## Success metric

The whole premise is "cut first-pass Challenger bounces," so measure it. `critic_loops.architect`
and `critic_loops.prompts` are already in `state.json`. Track their average across runs before and
after this lands; the rework ratio is the framework's key optimization metric. If the self-checks
do not move it, they are theater and should be cut.

## Why this is worth a run

Currently the Challenger catches these cold and the fix loops back. If the Architect and Spellwright
catch their own first, each Challenger pass stays a verification of build correctness rather than a
defect-fixing round. That is the intended role split. The self-checks do **not** narrow the
Challenger's scope; they are a filter in front of it, not a replacement (fresh context still matters).

Two file edits (`agents/architect.md`, `agents/prompt-engineer.md`), no schema or migration. The
mechanical-trigger greps are a handful of lines each. Buildable in one or two Mechanic prompts.

## Source data

`docs/evaluation/architect-challenger-patterns.md` — full 130-row findings table, frequency breakdown, and the
per-pattern examples. Read before authoring the two agent edits so each check cites the right
pattern and a real example. That doc's checklist is the original single-owner version; this idea
supersedes it with the two-owner split.

## Related

- `architect-challenger-pre-flight.md` — v1 (single-owner; kept for history, superseded by this)
- `docs/evaluation/architect-challenger-patterns.md` — the evidence base
- `agents/architect.md`, `agents/prompt-engineer.md` — the two target files
- `agents/critic.md` — the Challenger; its findings are the data this is built from
- `project-framework-optimization-metrics` (memory) — rework ratio as the key metric
