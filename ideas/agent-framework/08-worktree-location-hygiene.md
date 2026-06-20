# 08. Worktree location hygiene

Status: not started. Logged 2026-06-19.

## Problem
`scripts/run-worktree.sh` creates execute/bug-fix worktrees **inside** the target repo, at
`$REPO/.bureau-worktrees/$SLUG` (default set at `run-worktree.sh:106`). A git worktree nested
inside another working tree is an anti-pattern that confuses tools that scan a repo:

- **Cursor / VS Code Git panel** stops reliably showing changes in the main checkout. Observed
  2026-06-19 on `rheo.ca`: an edit committed-ready on `main` did not appear in Cursor's source
  control panel no matter how many refreshes, because a nested worktree
  (`.bureau-worktrees/20260617-upwork-html-search-ingest`) scrambled the editor's repo
  boundary detection. The CLI saw the change fine; the editor did not.
- File watchers, search indexers, linters, and test runners also walk the nested worktree.
- The nested dir can itself show up oddly in `git status` (it appeared as ` M` in the parent).
- **Worst: it can get committed by accident.** Confirmed on `rheo.ca` (2026-06-19): a `git add`
  during a build run swept the worktree into the index as a **gitlink** (mode `160000`) and it
  was committed to `main`, because the project did not gitignore `.bureau-worktrees/`. A
  committed gitlink pointing at an ephemeral worktree commit is broken history and was a likely
  contributor to the editor confusion. Removing the worktree later surfaced it as a phantom
  deletion to reconcile.

## Fix
Put worktrees **outside** the target repo by default, env-overridable. One-line change to the
default in `scripts/run-worktree.sh`:

```bash
# current (run-worktree.sh ~105)
if [[ -z "$WORKTREE_DIR" ]]; then
  WORKTREE_DIR="$REPO/.bureau-worktrees/$SLUG"
fi

# proposed
if [[ -z "$WORKTREE_DIR" ]]; then
  # Outside the repo so editors, file watchers, and indexers never see a nested worktree.
  WORKTREE_DIR="${BUREAU_WORKTREE_ROOT:-$HOME/.bureau/worktrees}/$(basename "$REPO")/$SLUG"
fi
```

`REPO` is already resolved to an absolute path above, so `basename "$REPO"` is safe. The
`mkdir -p "$(dirname "$WORKTREE_DIR")"` that follows still works. The existing
"path already exists" guard still protects against collisions.

## Files to update (default path appears in 5 places)
- `scripts/run-worktree.sh:15` (usage comment) and `:106` (the actual default).
- `docs/git-worktree.md:38` (the "Worktree parent" line; drop the "add to .gitignore" advice,
  it is no longer inside the repo) and `:103` (the `worktree_path` example in the state.json
  block).
- `scripts/README.md:170` (the `--worktree-dir` default note).
- `templates/project-context-template.md:50` (the "Worktrees" line).

The framework's own `.gitignore:3` (`.bureau-worktrees/`) can stay; harmless.

## Why this is safe for in-flight runs
The change only affects **newly created** worktrees. It cannot break a run that already has one:

- `cmd_create` writes the **absolute** `worktree_path` into that run's `state.json` (`git`
  block) at create time.
- Every other command (`merge`, `sync`, `remove`, `status`) and `scripts/preflight.sh` reads
  `worktree_path` from `state.json`. None of them recompute the default.

So an active run with a worktree at the old `.bureau-worktrees/...` path keeps working at that
path through merge and remove. New runs land in the external location. No coordination with
running jobs is required to ship this.

## Migration / cleanup
- Existing nested worktrees can be left to finish and `remove` at their current path, or moved
  with `git worktree move <old> <new>` and a `state.json` `worktree_path` update.
- **Audit other repos that used the old default** for accidentally committed worktree gitlinks:
  `git ls-files -- '.bureau-worktrees/*'`. If any show up, `git rm` the gitlink and commit. As
  belt-and-suspenders, add `.bureau-worktrees/` to each such project's `.gitignore` (and to the
  setup guidance in `templates/project-context-template.md`), so a stray in-repo worktree can
  never be committed even if someone overrides the default back inside a repo.
- Triggering case to clean up separately: `rheo.ca` currently has
  `.bureau-worktrees/20260617-upwork-html-search-ingest` (branch
  `bureau/20260617-upwork-html-search-ingest`). Check whether it holds unmerged work; if it is
  merged or abandoned, `git worktree remove` it to stop the Cursor confusion now.

## Acceptance boundary
- `run-worktree.sh create` against any repo places the worktree outside that repo (verify the
  resulting `worktree_path` is not under `$REPO`).
- `BUREAU_WORKTREE_ROOT` override is honored.
- `check-framework.sh` still passes (it asserts `run-worktree.sh` exists and is referenced by
  `execute-plan.md`; the path default is not asserted, so no lint change needed).
- Docs and template no longer describe an in-repo worktree path.

## Gate-theater check
Script-enforced: the default lives in `run-worktree.sh`, so the behavior is verifiable by
inspecting the created `worktree_path`, not left to Conductor discretion. Passes the
cross-bundle principle.
