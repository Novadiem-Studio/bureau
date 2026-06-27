# Canon Promotion Conventions

> Canon module extracted from `docs/conventions.md`. Load this file only when its concern is triggered by the task.

## Battle-test matrix file format

One canonical definition of the `battle-test.md` format required before any workflow or prompt is promoted to canon. Every workflow and persona file points at this section; nothing re-documents it inline.

**Location and naming:** A file named `battle-test.md`, placed alongside the artifact being promoted to canon — for a **prompt folder**, `<prompt-folder>/battle-test.md`. For a **workflow**, do NOT place it at `workflows/<name>.battle-test.md` or `workflows/battle-test.md`: every `workflows/*.md` file is scanned by the `check-framework.sh` registry lint and would be flagged as an unregistered workflow (and a bare `battle-test.md` would also collide across workflows). Instead place a workflow's matrix at `workflows/battle-test/<workflow>.md` — the registry-lint glob is non-recursive, so the subdir keeps it "alongside the workflow" without tripping the lint.

**When required:** Before any canon promotion — adding a row to `workflows/index.md` (workflow) or committing a prompt folder to `plans/` as the accepted prompt set (prompt).

**File structure**

1. **`## Run <date>` archive block** — the file always opens with a `## Run <date>` heading above the current case table. The date is the date of the run being recorded. On re-promotion (when a workflow or prompt is updated and re-entering canon), the prior `## Run` block is left in place; a NEW `## Run <date>` heading + fresh case table is added ABOVE it. "Re-run in full" means: all cases are re-evaluated and results written fresh — never appending new rows to an existing table. The most recent `## Run` block is the live one. This is a re-run obligation on the Conductor (on `Promotion to canon: yes`, the Conductor re-runs the full matrix and writes a fresh `## Run <date>` block as part of promoting); prior blocks are the audit history.

2. **Case table** — the matrix contains 3–5 representative cases (FR 8). Each row records four required fields (FR 9):

   | Field | Description |
   |-------|-------------|
   | Case name | A short, distinct name for this case. |
   | Input description | Enough detail for a fresh agent to reproduce the run — project type, inputs, any unusual context. |
   | Expected outcome | What "pass" looks like for this case (observable, not judgmental). |
   | Actual result | `pass` or `fail` + a one-line note on any deviation. |

3. **Case representativeness requirement** — the 3–5 cases MUST include:
   - At least one **happy-path / typical** case.
   - At least one **edge case** (unusual-but-valid input or uncommon input shape) — named as such.
   - At least one **failure mode** (bad input, missing dependency, or the scenario the workflow is most likely to fail on) — named as such.

   Case count alone does not satisfy this requirement. A matrix of 3–5 cases that are all happy-path variants under different labels is NOT representative and does not pass the gate, regardless of case count (Edge Case 3).

**FR 12 open-ended-generative interpretation**

For workflows with open-ended input spaces (e.g. arbitrary human text as input), the three category requirements above are re-interpreted as operational scenarios: (1) one nominal run, (2) one run that hits an expected edge (empty input, very long input, or missing context), (3) one run that the workflow must refuse or checkpoint rather than complete. The four per-case fields and the 3–5 count are unchanged.

**`waiver:` block** (optional, but with strict validity rules):

A `waiver:` block may appear in `battle-test.md` when one or more cases fail and Robin has explicitly accepted the failure as a known limitation. A valid waiver MUST name ALL THREE of:
- The failing case (by name).
- The reason the failure is known and accepted.
- Robin's explicit acceptance (a statement attributing the decision to Robin, not a blank entry).

A `waiver:` block that is blank, that names the failing case but not the reason, or that names neither, is NOT a valid waiver and does not close the battle-test Blocker (AC 5, Edge Case 4). Example of an INVALID waiver: `waiver: accepted`. A waiver is a conscious exception with a named reason, not a default.

A valid waiver closes the battle-test gate for the specific failing case it names. It does not close the gate for unnamed cases.

No other section in the framework re-documents this format. Workflow and persona files reference this section by name.

---

## Convention-retirement rule

This rule exists to prevent convention modules from accumulating superseded blocks that cold
reviewers follow as live instructions. To deprecate a section in `docs/conventions.md` or
`docs/conventions/*.md`, three steps must be taken.

**Step 1 — Mark the heading.** Append `— **SUPERSEDED:** replaced by [§ <new section name>]` to the retired section's heading line. The marking lives ON the heading so a skimmer and The Challenger see it at the section anchor. Example:

`## Old fixture format — **SUPERSEDED:** replaced by [§ Regression fixture file format]`

**Step 2 — Set a removal date.** Immediately under the marked heading, one line:

`Removal: <bundle id or calendar quarter>` (e.g. `Removal: Bundle 03` or `Removal: 2026 Q4`) — never "eventually". An overdue removal date is a Blocker **only on a review that actually touches or cites the retired section** — editing that section, or following a `§` citation into it — not on any review of an unrelated convention module. (This scoping prevents the overdue date from ambushing a Conductor editing an unrelated section of the convention set.) When the overdue date fires, the block must be removed or the date explicitly extended with a written reason.

**Step 3 — The Challenger check.** A section carrying `**SUPERSEDED:**` that is still cited as a **live instruction** by `§` reference in any persona or workflow file is a **Blocker** until the citation is repointed to the replacement section. (Citations inside the retired block itself, or in this retirement rule, don't count — only live instructional citations elsewhere.)
