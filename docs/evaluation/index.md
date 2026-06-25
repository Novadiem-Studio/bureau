# docs/evaluation — the framework's self-evaluation record

How the bureau gets measured against its own real runs, and how it changes in response. If you
are about to evaluate a run, edit a persona, or change the review process, read the ledger first
so you build on prior findings instead of rediscovering them.

Three docs, three jobs:

| File | Job | Read it when |
|------|-----|-------------|
| `framework-evaluation-log.md` | **Ledger** — dated entries: what each pass evaluated, what held, what we changed, open levers. | First, always. It is the cross-session memory. |
| `architect-challenger-patterns.md` | **Synthesis** — the current Architect→Challenger pattern taxonomy, frequency table, and the pre-flight checklist (encoded into `agents/architect.md`). | You need the current pattern set or the checklist. |
| `challenger-pattern-analysis.md` | **Method** — how to mine run logs into the synthesis; the taxonomy is frozen (extend by appending tags, never rename). | You are running a fresh pattern-mining pass. |

Flow: **method** produces the **synthesis**; every evaluation pass is recorded in the **ledger**
and may correct a persona or the synthesis. Corrections to personas (`agents/*.md`) must cite
the ledger entry that drove them.
