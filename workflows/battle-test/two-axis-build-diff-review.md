# Battle-test: two-axis build-diff review

**Canon surface touched:** `agents/critic.md`, `agents/critic/build-diff.md`,
`docs/conventions.md`, `docs/conventions/fowler-smell-baseline.md`
**Promotion to canon:** yes
**Status:** EXECUTED 5/5 in working tree 2026-07-20. Static fixtures 209-211 pin the two-axis
contract, loadable Fowler floor, and verdict-record schema wording; the standing suite rerun is
the mechanical promotion check.

## Run 2026-07-20 (promotion)

| Case name | Input description | Expected outcome | Actual result |
|-----------|------------------|-----------------|---------------|
| Happy path: both axes clean | A build diff exactly implements the scoped prompt, stays inside named files, runs the named checkpoint, and follows local standards. | Build-diff review reports `### Spec-fidelity` and `### Standards`; both axes have no findings; `### Axis summary` reports each axis clean without choosing a cross-axis winner. | pass - fixture 209 pins the headings and no-reranking rule. |
| EDGE: spec clean, standards warning | A diff implements the prompt correctly but duplicates a validation branch in two files where repo docs are silent. | Spec-fidelity axis remains clean; Standards axis reports `possible Duplicated Code` as a warning from the Fowler floor. The warning does not imply the feature is wrong. | pass - fixture 210 pins the loadable Fowler floor and build-diff slice pointer. |
| FAILURE MODE: standards clean, spec blocker | A diff is idiomatic and well-tested but implements the wrong endpoint or omits one prompt requirement. | Spec-fidelity axis reports a blocker even if Standards is clean. A clean Standards axis cannot soften or rerank away the Spec-fidelity blocker. | pass - fixture 209 pins severity-inside-axis and no cross-axis winner. |
| FAILURE MODE: missing repo standards | A repo has no useful `CLAUDE.md`, `CONTRIBUTING.md`, or coding-standards document for the changed surface. | Standards axis still runs using `docs/conventions/fowler-smell-baseline.md`; baseline smells are heuristics and repo docs would override them if present. | pass - fixture 210 asserts the baseline is loadable and contains exactly 12 smell entries. |
| EDGE: verdict record stays schema-stable | A build-diff review emits axis-grouped prose but writes a JSON verdict record for the reviewed diff. | The record uses the existing diff-target `reviewed_artifacts` array with `kind`, `base_ref`, `base_sha`, `target_ref`, and `diff_sha`; it does not add axis fields unless `verdict-gate.sh` changes too. | pass - fixtures 209 and 211 pin the no-axis-fields decision and gate-accepted diff-target shape. |

