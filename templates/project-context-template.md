# Project Context

> Copy this file to your project root as `project-context.md` and fill it in
> before starting the agent framework. The Orchestrator reads this automatically
> and passes the relevant parts to each subagent it spawns.
> Delete sections that aren't relevant.

## Project Name
[Short name for this project]

## The Idea
[2-3 sentences describing what this is and who it's for]

## Mode
`greenfield` (a new system from scratch) or `existing project` (a feature or change
inside a codebase that already exists). Default is greenfield. If `existing project`,
fill in the Workspace Map, Existing Codebase Notes, and Technical Constraints below —
the agents build within what's already there instead of designing from scratch.

## Domain Knowledge
[Anything the agents need to understand about the domain that isn't obvious.
Industry context, specialized terminology, regulatory constraints, etc.]

## Technical Constraints
[Existing stack if this is an addition to an existing project.
Languages, frameworks, hosting, databases already in use.
Things that cannot change.]

## Existing Codebase Notes
[If building on an existing project: what exists, what patterns are established,
what should be followed or avoided.]

## Workspace Map (existing / multi-repo projects)
> Only for existing projects, especially multi-repo workspaces. Gives the Orchestrator a
> frame of reference for what lives where, so it routes work to the right place and points
> each agent at only the context it needs.

For each relevant repo / sub-app:
- **Name** — what it is
- **Path** — where it lives
- **Purpose** — what it does
- **Stack** — language / framework / database
- **Local context** — where its own CLAUDE.md / conventions / skills live

**Target of this work:** which sub-app(s) / directory(ies) this change touches.

## Git integration (execute / build runs)
- **Integration branch:** `devel` (base branch targeted by Bureau pull requests — adjust per project)
- **Target repo path:** absolute path to the git root that build prompts edit
- **Worktrees:** `$HOME/.bureau/worktrees/<repo-basename>/<run-slug>/` (outside the target repo — no `.gitignore` entry needed; override parent with `BUREAU_WORKTREE_ROOT`)
- **Delivery policy:** `auto` (`public GitHub → PR`, `private/internal → local`) | `github` | `local`
- **Private-repo delivery:** `local` (default) | `github`
- **GitHub merge method:** `merge` (default; preserves branch commits) | `squash` | `rebase`
- **CI on pull requests:** yes | no. With CI, routine integration gates read `gh pr checks` on the pushed commit instead of running the full suite locally. A suite that takes more than about 10 minutes in CI should be sharded first: `docs/ci-sharding.md`.

## Integration gate (build runs)
> The source of truth for the integration gate. Commit this file on the integration branch:
> the final gate reads this block from the copy committed there (`integration-gate.sh
> --final`), never from a run's `state.json`, so a run cannot change what its own final gate
> checks. The Conductor copies it into `state.json#integration_gate`; if that copy ever
> differs, the final gate runs the full local suite. Rules:
> `docs/conductor-gates.md § Integration checkpoint cadence (build runs)`.
>
> - `cadence`: `phase` (default; one integration gate per plan phase) | `every_n` (also every
>   `every_n_prompts` accepted prompts) | `every_prompt`.
> - `ci_covers_full_suite`: `true` only when CI runs the same full suite as the local
>   regression runner. Then the final gate may use CI instead of the local suite (35-55 minutes
>   for rheo-stream, against about 5 on sharded CI).
> - `local_only_gates`: gates that still run locally at a CI-mode final gate, for tests that
>   need Docker, secrets or hardware on the host: `[{"name": "...", "command": "..."}]`.

```json integration_gate
{"cadence": "phase", "every_n_prompts": 4, "ci_covers_full_suite": false, "local_only_gates": []}
```

## Users
[Who are the actual humans using this. Be specific — "small food producers who
are not technical" is better than "users".]

## Success Criteria
[How do we know this worked? What does a successful v1 look like in practice?]

## Known Constraints
[Budget, timeline, team size, anything that should bound the scope.]

## Out Of Scope (Known)
[Things you already know won't be in v1, to save the Analyst time.]

## References
[Links, documents, prior art, competitors, anything relevant.]
