# Battle-test: codebase-readiness-audit

**Canon surface touched:** `workflows/codebase-readiness-audit.md`
**Promotion to canon:** yes
**Status:** EXECUTED 5/5 — all fixed cases passed against the accepted Prompt 01–05 implementation.

## Run 2026-08-30

| Case name | Input description | Expected outcome | Actual result |
|-----------|-------------------|------------------|---------------|
| Happy: catalog with no supplied environment | Explicit `catalog` profile, authorized static target evidence, and an explicit statement that no runtime procedure was supplied. | Complete independent static coverage without creating a runnable environment; record `runtime_disposition: not-supplied`. | pass — shipped workflow and contract require static-only catalog coverage and the exact `not-supplied` disposition without setup work. |
| EDGE: full profile needs setup-only changes | Explicit `full` profile whose isolated stand-up needs local setup-only changes and may still leave runtime evidence unavailable. | Attempt isolated stand-up; classify unavailable evidence as `unverifiable`; retain an always-present quarantine with every setup change uncommitted and `approved_client_fix: false`. | pass — shipped workflow and contract preserve all quarantine and evidence-ceiling requirements. |
| Happy: audited exact-hash pass | Valid closed audited packet, exact allowlist hashes, matching reviewed-artifact set, and a blocker-free provider candidate. | Adapter publishes the candidate and a derived non-`BLOCKED` canonical verification verdict bound to the exact corrected-audit bytes. | pass — the actual readiness launcher published the exact-read-set candidate and derived canonical verdict. |
| FAILURE: audited read-set hash mismatch | Valid packet followed by a provider candidate whose reviewed-artifact hash differs from the manifest. | Fail closed after provider execution; retain immutable candidate attempt evidence and publish no canonical verdict or seal-enabling result. | pass — the actual readiness launcher rejected the mismatch, retained the candidate, and created no canonical verdict. |
| BOUNDARY: planning eligibility is not execution approval | One complete selectable seal, one incomplete archival seal, and a downstream request lacking exact current approval bindings. | Allow the complete seal as planning input only; reject the incomplete seal for selection and emit no execute-plan handoff without a completed plan plus exact explicit approval. | pass — shipped selection and authorization gates preserve planning eligibility while refusing incomplete or unapproved execution. |
