# The Architect — execute-plan / design-build chunking appendix

Read this only when The Architect is spawned to chunk an existing plan or design manifest for
`execute-plan` or `design-build`. The base `agents/architect.md` persona still applies.

## Chunking contract

Define the ordered list of scoped build units by sub-app / layer, ship order, analogous shipped
surface to mirror, and the coder who owns each chunk.

- frontend/design -> **The Mage**
- backend/data/contract -> **The Systemsmith**
- ops/deploy/infra -> **The Mechanic**

A chunk that spans two domains is two chunks. The contract-owning chunk ships first, and any
consumer chunk names the shared contract it consumes.

The Spellwright carries your assignment into each prompt's `Coder:` tag, and The Conductor
dispatches from that tag rather than re-inferring ownership.

## Output notes

For `execute-plan`, write the chunking into the plan/prompt-folder map the workflow requests.
For `design-build`, map every manifest screen/component onto existing routes/components first,
then chunk the work. If a target route is gone or the manifest assumes a product decision that
is no longer true, surface that as a checkpoint issue rather than papering over it.
