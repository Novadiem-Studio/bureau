# Architect: embed Challenger pattern pre-flight into agents/architect.md

We synthesized 130 Challenger findings across 8 runs and identified 17 recurring pattern
categories. The top five — missing-edge-case (24), internal-contradiction (22),
wrong-api-shape (18), under-specified (17), wrong-call-site (12) — account for ~70% of
all findings. These are not random mistakes; they're structural blind spots in how the
Architect currently produces spec + plan + handoff.

The goal: cut first-pass Challenger bounces by having the Architect run a lightweight
self-check before declaring complete — without adding a full extra agent spawn.

## What we want to accomplish

1. Fewer Challenger blockers that require a full architect revision loop (critic_loops.architect++).
2. Fewer Spellwright prompts that produce wrong-call-site or stale-name bugs at build time.
3. A forcing function that makes the Architect verify live codebase facts rather than
   reason from spec memory.

The playbook lives at `docs/evaluation/architect-challenger-patterns.md` (written 2026-06-22,
synthesized from runs 20260614–20260622).

## How it would work

Add a **"Pre-handoff self-check"** section to `agents/architect.md`, placed just before
the handoff block. The Architect reads the situation flags (below) and runs only the
checks that apply. Answers are one line each (Y / N + note). Any N becomes a "Passing
forward" note in the handoff — surfaced rather than hidden, often fixable immediately.

### Always-run (every run, ~2 min)

These fired across every project type without exception:

1. **Internal consistency** — Every count, enum value, or name that appears in two places
   in spec or plan: do both instances agree? (internal-contradiction: 22 hits)
2. **Boundary coverage** — Every input that can be null, zero, empty, or exceed a stated
   limit: is there an explicit handling rule? (missing-edge-case: 24 hits)
3. **Deferred items registered** — Every behavior punted out of scope: does it have a
   named open question or explicit out-of-scope callout — not just a comment or silence?
   (deferred-not-documented: 7 hits)

### Existing-project mode only

Run when the target is an existing codebase (the most common case). These checks require
reading live files — skip entirely on greenfield.

4. **API shape verification** — Every field name, return type, response envelope, and
   function signature: grep-verified against the live codebase, not written from memory.
   (wrong-api-shape: 18 hits — nearly all in existing-project runs)
5. **File path audit** — Every file path named in a prompt: confirmed to exist at that
   exact location. Every function edit: function confirmed in the named file.
   (wrong-call-site: 12 hits)
6. **Stale symbol scan** — Every config key, variable name, class name, and file name:
   confirmed not renamed, deprecated, or removed in the live codebase.
   (stale-name: 8 hits)
7. **Import completeness** — Every symbol used in a code prompt: an explicit import is
   present or already in the target file. Flag especially: stdlib helpers, ORM functions,
   decorators, logger. (import-missing: 5 hits — all Python/TS existing-project runs)

### When the plan touches deployment or infra

Run when any prompt involves deploy scripts, server config, systemd units, reverse proxy,
or served static assets.

8. **Deploy path trace** — Every asset, route, or file assumed reachable at runtime:
   confirmed in the served directory, not just the repo root. Every health check URL:
   confirmed against the actual vhost config, not a guess.
   (deployment-path-gap: 9 hits — all in runs with a deploy step)
9. **Env config completeness** — Every env var, API key, base URL, or service endpoint:
   confirmed in .env.example with the correct key name. Base URLs verified against the
   deployed routing config, not the spec's assumption.
   (env-config-unstated: 5 hits)

### When the plan adds external dependencies or cross-repo calls

Run when any prompt installs a new package, calls a service in a different repo, or
assumes a runtime capability (MCP connector, Gmail access, cloud egress, etc.).

10. **External dependency inventory** — Every new library, service, or runtime capability:
    confirmed already installed/provisioned, or the plan has an explicit step to do so
    before first use. (external-dependency-unstated: 5 hits — all involved new packages
    or unverified runtime environments)

### When the stack uses async frameworks

Run when the target uses Next.js 13+, FastAPI, async Python, or any framework where
route handlers have async/sync contracts.

11. **Async/sync discipline** — Every function touching I/O: async/sync signature matches
    what the framework expects. Check specifically: Next.js 15+ route params (Promise),
    blocking sync calls inside async FastAPI routes.
    (async-sync-mismatch: 3 hits — all Next.js 15 or FastAPI runs)

### When acceptance criteria cite specific values

Run when any AC asserts a status code, field name, test assertion string, or exact
response shape.

12. **AC → implementation trace** — Every AC asserting a specific value: traced to what
    the implementation will actually produce. For any test already in the repo, read it
    and confirm the planned change won't make it red.
    (ac-implementation-mismatch: 8 hits — concentrates in runs with large AC sections)

## Why this is worth a run

Currently the Challenger catches these things cold and the fix loops back to the Architect.
If the Architect catches them first, the Challenger pass stays a verification of build
correctness rather than a spec-fixing round. That's the intended role split.

The implementation is a one-file edit to `agents/architect.md` — small enough to build
in a single Mechanic prompt with no migration or schema change.

## Source data

`docs/evaluation/architect-challenger-patterns.md` — full findings table, frequency breakdown,
and the 12-check checklist. Read before authoring the architect.md edit so the prompt
cites the right check numbers and examples.

## Related

- `ideas/not-started/` — this idea
- `docs/evaluation/architect-challenger-patterns.md` — the evidence base
- `agents/architect.md` — the target file
- `agents/critic.md` — has a similar self-check concept for the Challenger's own blind spots
