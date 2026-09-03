# Tool Discipline Convention

> Canon convention module. Load when a persona pointer references
> `docs/conventions/tool-discipline.md`, or when the work involves choosing
> between Edit/Write/Read/Grep and Bash for file operations.
>
> **Why this matters (eval ledger 2026-09-03):** In the nutrifax-zine run, 74%
> of all tool calls were Bash and ~47% of run-scoped Bash was sed-editing +
> cat/grep-inspecting that Edit/Read/Grep do in-context WITHOUT a turn. Cost
> equals turns × accumulated context, so each shell round-trip re-reads
> ~250-340k of cache. The exemplar: `architect-5` applied 5 blocker fixes to a
> 1,233-line plan.md in 234 Bash / 0 Edit calls — 60M processed, 99.5%
> cache_read, only 35k output.

## The rule

| Operation | Right tool | Never use Bash for this |
|-----------|-----------|------------------------|
| Edit an artifact (spec.md, plan.md, prompts.md, a persona, a script) | **Edit** or **Write** | sed, awk, cat >, tee |
| Inspect / search a file for a pattern | **Grep** | grep via Bash |
| Read a file (known path) | **Read** | cat, head, tail |
| Run tests, docker, git, or framework ceremony scripts (run-*.sh, the gates, account-*.sh, emit-event.sh, log-append.sh) | **Bash** | (these ARE Bash's domain) |
| Navigate / check structure | **Bash** (ls, find) | (fine) |

## Rationale

- **Edit/Write/Read/Grep** execute in-context — no new tool-call turn, no re-read of
  accumulated context. They are free in cost terms.
- Every **Bash** call is a new turn that re-reads the full accumulated context window.
  On a run with 200k+ tokens in context, one unnecessary sed call costs as much as a
  small specialist spawn.

## Practical guidance

- Opening a file to search for a pattern? Use **Grep**, then **Read** the relevant section.
- Applying a targeted text replacement? Use **Edit** with the old/new strings.
- Writing a new file? Use **Write**.
- Running `scripts/preflight-artifacts.sh`, `scripts/verdict-gate.sh`, `git diff`, or
  `pytest`? Those are framework ceremony or test execution — use **Bash**.
- Unsure? Ask: "Could I do this with Edit/Read/Grep?" If yes, do that.

## Scope

Applies to every specialist and to the Conductor itself. The Conductor's own tool-call
profile should match: Edit artifacts, Read/Grep to inspect, Bash for git/framework/tests.

No exception for "just a quick grep" — the accumulation of quick greps is the problem.
