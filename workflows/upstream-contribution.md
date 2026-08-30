# Workflow: upstream-contribution

**Objective:** contribute one narrowly scoped, genuinely useful improvement to an unrelated
public project the studio actually uses, following that project's maintainer expectations.

**When to use:** Robin asks to contribute a fix, documentation correction, missing type, test
improvement, or reproducible bug fix to an upstream dependency or developer tool. Prefer
dependencies used by Bureau, Growoperative, FOAF Auth, or the active development toolchain.

**When NOT to use:** speculative drive-by changes, cosmetic churn with no user benefit, work in a
repository Robin controls, security vulnerabilities needing private disclosure, or anything whose
main purpose is an achievement counter. Use `bug-fix` for first-party defects and `code-review`
for review-only requests.

**Inputs:** target upstream repository; local/fork checkout; maintainer contribution guide and
templates; a reproducible problem or bounded improvement; GitHub authentication; any required
CLA/sign-off identity. The workflow does not authorize public posting by itself.

**Outputs:** `RUN_DIR/upstream-fit.md`, `RUN_DIR/repro.md` when applicable, a focused tested commit
in an isolated worktree, `RUN_DIR/github/cold-review.md`, linked issue, draft/ready upstream PR,
and delivery links in `state.json`/`log.md`.

## Steps

1. **Analizer 2000** (Upstream fit, **standard**) — inspect the dependency as it is actually used,
   reproduce or substantiate the problem, read `CONTRIBUTING`, issue/PR templates, recent related
   issues and maintainer guidance, and identify the smallest useful contribution →
   `RUN_DIR/upstream-fit.md`, `RUN_DIR/repro.md` when applicable.
   - Already fixed, duplicate, unsupported, speculative, or contrary to maintainer guidance: stop.
   - Security-sensitive: stop and use the project's private reporting path.
   - Scope needs maintainer agreement: prepare a concise issue/comment and raise an
     `[EXTERNAL-ACTION CHECKPOINT]` before posting it.
2. **Gate** — confirm the maintainer's expected path, create or claim the real issue, and obtain
   authorization for the externally visible issue and draft PR unless already granted by Robin.
   No throwaway issue and no issue created merely to satisfy the workflow.
3. **Worktree** — fork/clone as the upstream guide requires, configure `origin` as Robin's fork,
   create the Bureau worktree with `--delivery github`, then run `scripts/pr-delivery.sh open`
   with `--github-repo <upstream-owner/repo>` and the claimed issue → linked draft upstream PR.
4. **The Conductor** dispatches the domain owner — **The Mage**, **The Systemsmith**, or **The
   Mechanic** at **strong** — to implement only the confirmed scope in `WORKTREE`, add the
   upstream-appropriate test or documentation proof, follow sign-off/format rules, and commit →
   a focused upstream diff and green local evidence.
5. **The Challenger** (Critic, **strong**, fresh context required) — cold-review the diff against
   `upstream-fit.md`, the issue, the upstream contribution guide, and test evidence; look for scope
   creep, local-only assumptions, compatibility breaks, missing release notes/types/tests, and
   maintainer-hostile framing → `RUN_DIR/github/cold-review.md`, findings.
   The Conductor routes blockers back to the owner (maximum two loops), records every resolution,
   and does not mark the PR ready until the verdict is accepted.
6. **The Conductor** (**strong**) — complete `RUN_DIR/github/evidence.md`, publish the Challenger
   summary and any useful inline comments with `pr-delivery.sh review`, mark the PR ready, and
   hand Robin the PR URL plus test evidence → ready upstream PR, updated `log.md`, `state.json`.
   Responding to maintainers is part of this workflow, but each externally visible response needs
   existing authorization or an `[EXTERNAL-ACTION CHECKPOINT]`. Do not merge an upstream PR;
   maintainers own that action. Monitor only when Robin explicitly asks.

**Done criteria:** the problem is real; maintainer expectations were followed; the PR is focused,
linked, tested, cold-reviewed, and ready; no fabricated review/co-author identity exists; Robin has
the PR and follow-up obligations. A declined or closed PR is still an honest completed attempt when
the outcome and maintainer feedback are logged.

**Fallbacks and edge cases:** if no issue is wanted, follow explicit maintainer guidance and record
that exception before using a manual PR path; if a CLA/DCO is required, stop until the real identity
requirement is satisfied; if the fork cannot run CI, report that uncertainty rather than claiming
green; if upstream scope expands materially, withdraw or re-scope instead of turning one PR into a
grab bag.

**Observability:** issue, PR, review, and CI URLs live in `state.json` and `log.md`; local evidence
lives under `RUN_DIR`; GitHub is the authoritative source for maintainer review and merge state.

