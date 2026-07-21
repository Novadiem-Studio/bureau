# Battle Test: ADR Decision Records

**Artifact:** bundle 35 implementation slice (`docs/conventions/adr-records.md`,
`templates/adr.md`, role contracts, `scripts/preflight-artifacts.sh`)

## Cases

| Case | Setup | Expected result | Status |
|---|---|---|---|
| Happy path — qualifying decision | Existing-project run makes a hard-to-reverse, surprising tradeoff decision. | Architect writes the next `docs/adr/NNNN-slug.md`, cites it in `### ADR Records`, and passes preflight. | PASS — static fixture 218 pins the writer contract; dynamic fixture 216 pins valid shape |
| Edge — no qualifying decision | Run makes only obvious, reversible implementation details. | Architect writes `none — no qualifying new decisions`; no ADR directory is required. | PASS — convention says ADRs are created lazily and only for the three-part qualifier |
| Failure mode — malformed ADR | Target repo has an ADR with mismatched heading number or invalid status. | `preflight-artifacts.sh` exits 1 with `adr-heading` and `adr-status`. | PASS — dynamic fixture 217 pins the failure |
| Failure mode — accepted ADR contradiction | Spec/plan contradicts an accepted ADR without a new superseding ADR. | Round-1 Challenger raises a Blocker. | PASS — static fixture 219 pins the gate |
| Edge — docs drift | Code no longer reflects an accepted ADR. | `docs-reconcile` surveys ADR status/decision drift and reconciles by superseding, not rewriting old bodies. | PASS — static fixture 218 pins the docs-reconcile contract |

## Run — 2026-07-21

Result: 5/5 cases pass in the working tree. The implementation slice is ready, but the bundle is
not done until at least two runs on one target repo accumulate ADRs and a later specialist cites
one instead of re-litigating the decision.
