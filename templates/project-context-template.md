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
