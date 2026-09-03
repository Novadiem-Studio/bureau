# Tool Discipline Convention

> Canon convention module. Load when a persona pointer references
> `docs/conventions/tool-discipline.md`, or when the work involves choosing
> between Edit/Write/Read/Grep and Bash for file operations.
>
> **Why this matters (eval ledger 2026-09-03):** In the nutrifax-zine run, 74%
> of all tool calls were Bash and ~47% of run-scoped Bash was sed-editing +
> cat/grep-inspecting that Edit/Read/Grep collapse into far fewer turns. Cost
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

- **The cost is turns, not the tool.** Every tool call (Bash, Edit, Read, Grep alike) is a
  turn that re-reads the full accumulated context, billed as cache_read. On a run holding
  200k+ tokens, one turn costs about the same whether it is a `sed` or an `Edit`.
- **Dedicated tools do the same work in far fewer turns.** `Read` loads a file into context
  once and you then work from it; the Bash habit re-`cat`s it every time it wants to look.
  `Edit` is exact-match-or-fail in one call; `sed -i` invites a `cat`-to-verify then a redo.
  `Grep` finds matches across files in one call; `find … | xargs grep` is several.
- So `architect-5`'s 234 Bash calls were costly not because a Bash call beats an `Edit` on
  price, but because they were 234 turns doing what ~15 dedicated-tool calls would: same
  per-turn tax, 15× the turns.

## Practical guidance

- Opening a file to search for a pattern? Use **Grep**, then **Read** the relevant section.
- Applying a targeted text replacement? Use **Edit** with the old/new strings.
- Writing a new file? Use **Write**.
- Running `scripts/preflight-artifacts.sh`, `scripts/verdict-gate.sh`, `git diff`, or
  `pytest`? Those are framework ceremony or test execution — use **Bash**.
- Unsure? Ask: "Could I do this with Edit/Read/Grep?" If yes, do that.
- **If you are churning one file** — a third Bash inspect→edit→re-inspect pass — stop: Read it
  once, land the change in one Edit. If a single artifact is genuinely taking dozens of tool
  calls, stop and report for re-scope rather than burning turns.

## Scope

Applies to every specialist and to the Conductor itself. The Conductor's own tool-call
profile should match: Edit artifacts, Read/Grep to inspect, Bash for git/framework/tests.

No exception for "just a quick grep" — the accumulation of quick greps is the problem.
