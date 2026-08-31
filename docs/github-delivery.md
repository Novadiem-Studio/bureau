# GitHub delivery

Code-changing Bureau runs use an issue, isolated branch/worktree, early draft pull request,
cold-review evidence, and a GitHub merge. This is the default for public GitHub repositories.
Private and internal repositories default to local delivery unless `project-context.md` opts in.
Non-GitHub repositories retain an explicit local fallback.

The purpose is a truthful collaboration record. Do not split coherent work into junk pull
requests, create throwaway issues, fabricate reviewers, or attribute agents as co-authors.

## Policy

| `git.delivery_policy` | Public GitHub repo | Private/internal GitHub repo | GitHub unavailable |
|---|---|---|---|
| `auto` (default) | GitHub | `git.private_delivery` (`local` by default) | Non-GitHub remote: local; unresolved GitHub remote: fail closed |
| `github` | GitHub or fail closed | GitHub or fail closed | Fail closed |
| `local` | Local | Local | Local |

`scripts/pr-delivery.sh open` resolves the policy and writes `git.delivery_mode`. A local merge
is blocked while an `auto` or `github` policy is unresolved, and remains blocked after it resolves
to GitHub. This prevents an accidental return to the old branch-to-local-merge close-out.

Security reports do not go through public issue creation. Follow the target project's private
security-reporting policy; record the private reference in `log.md`, then use GitHub delivery only
if the eventual PR can safely be public.

## Opening sequence

1. Write an issue body in `RUN_DIR/github/issue.md`:
   - bug: reproduction criteria, expected/actual behavior, and affected version;
   - feature: acceptance criteria and explicit out-of-scope boundaries.
2. Obtain external-action authorization unless the user's request or project policy already
   authorizes issue/PR creation.
3. Create the worktree with `--delivery auto` (the default).
4. Open or link the issue and open the draft PR before implementation:

```sh
<FRAMEWORK>/scripts/pr-delivery.sh open \
  --run-dir "$RUN_DIR" \
  --issue-title "<issue title>" \
  --issue-body-file "$RUN_DIR/github/issue.md" \
  --title "<pull request title>" \
  --summary "<problem and intended result>"
```

Use `--issue <number-or-url>` to link existing work. For a genuine contribution from a fork,
add `--github-repo <upstream-owner/repo>`; the helper pushes the Bureau branch to `origin` and
opens the PR against that upstream repository with a qualified head ref.

GitHub cannot open a PR from a branch with no commits. When needed, `open` creates one empty
`chore: start Bureau run …` commit. The default regular merge preserves that truthful start marker
and every subsequent branch commit in the target branch's history. Use an explicit squash override
only when the target repository prefers a collapsed history.

`open` creates `RUN_DIR/github/evidence.md` and `pr-body.md`, links the issue with `Fixes #…`,
records the Bureau run id, pushes the branch, and stores issue/PR identifiers in `state.json`.

## Evidence and cold review

Before review, replace every placeholder in `RUN_DIR/github/evidence.md`. It must contain:

- problem and intended result;
- important architectural decisions;
- tests and checks actually run;
- screenshots or an explicit not-applicable statement;
- risks and rollback instructions;
- the Challenger verdict;
- each objection and how it was resolved.

Publish current commits and evidence with:

```sh
<FRAMEWORK>/scripts/pr-delivery.sh refresh --run-dir "$RUN_DIR"
```

Write the Challenger summary to a file and translate it into GitHub activity:

```sh
<FRAMEWORK>/scripts/pr-delivery.sh review \
  --run-dir "$RUN_DIR" \
  --review-summary "$RUN_DIR/github/cold-review.md" \
  --verdict accepted
```

Use `--verdict changes-requested` when blockers remain. When line-specific findings help, add
`--inline-comments <json-file>` where the file is an array of `{path,line,body,side?}` objects.
The helper posts comments against the current branch commit.

If the authenticated GitHub user authored the PR, the helper posts the cold verdict as a normal
PR comment; it never pretends that self-review is an approval. If a genuinely separate
collaborator runs it, it submits an approval or requested-changes review. Repository branch
protection remains authoritative for required human approvals.

## Ready and merge

After the cold verdict is accepted, all objections are resolved, the evidence is complete, and
the worktree is clean:

```sh
<FRAMEWORK>/scripts/pr-delivery.sh ready --run-dir "$RUN_DIR"
<FRAMEWORK>/scripts/pr-delivery.sh merge --run-dir "$RUN_DIR"
<FRAMEWORK>/scripts/run-worktree.sh remove --run-dir "$RUN_DIR"
```

`ready` rejects placeholder evidence. `merge` rejects drafts and outstanding requested changes,
then delegates the merge to GitHub without bypassing branch protection. `merge`, `squash`, and
`rebase` methods are supported; regular `merge` is the default so the accepted branch commits stay
visible on the target branch, and target-repository policy wins. Package checks, dev verification,
run logs, state updates, and accounting still happen at workflow close-out.

## Merge gate

`git.merge_gate` decides **who triggers** `pr-delivery.sh merge` once the mergeable preconditions
hold — tests green, cold review posted with an `accepted` verdict, objections resolved, evidence
complete, worktree clean:

| `git.merge_gate` | Behavior |
|---|---|
| `self` (default for GitHub delivery) | The Conductor runs `pr-delivery.sh merge` itself as soon as those preconditions hold — no per-run human checkpoint. Hands-off. |
| `human` (opt-out) | The Conductor raises the `[DEV-VERIFIED CHECKPOINT]` and waits for the human "go" before `pr-delivery.sh merge`. |

`self` removes the human **click**, never the **gates**: an unmerged PR still needs green tests
and an `accepted` cold review, and the production-deploy and external-action boundaries are
unchanged (merging the PR to the default/integration branch is *delivery*, not a production
deploy). It never fabricates an approval — a self-authored PR's verdict is posted as a comment,
and repository **branch protection stays authoritative**: a repo that requires a human review
holds at that gate regardless of `merge_gate`. Set `git.merge_gate: human` in `project-context.md`
for any repo whose merge you want to hand-approve. A shared/multi-maintainer install may prefer
`human` as its default.

## Genuine co-authorship

When another human materially contributes code, design, tests, or the solution itself, record
their verified GitHub commit identity and add exactly this trailer to the relevant commit:

```text
Co-authored-by: Full Name <verified-email@example.com>
```

Confirm the identity with the person or from their own commits. Never add a trailer for an agent,
review-only feedback, nominal participation, or a person who did not co-author the change. The
trailer must be in a commit that lands through the merged PR. After the commit exists, make the
provenance check inspectable:

```sh
<FRAMEWORK>/scripts/pr-delivery.sh coauthor \
  --run-dir "$RUN_DIR" \
  --name "Full Name" \
  --email "verified-email@example.com" \
  --commit <sha> \
  --confirmed-human
```

The helper refuses base-branch commits and commits missing the exact trailer, then records the
verified human identity and commit in `state.json#git.coauthors`.

## State and observability

Inspect delivery with `scripts/pr-delivery.sh status --run-dir "$RUN_DIR"`. The `git` block stores
the resolved repository visibility, fallback reason, issue/PR links, draft status, cold-review
status, and terminal merge time. The human-readable sequence and every external-action approval
remain in `RUN_DIR/log.md`.
