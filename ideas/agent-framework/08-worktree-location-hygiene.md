# 08. Bureau file-location hygiene

Status: not started. Logged 2026-06-19. **Expanded 2026-06-22** with a second, larger change —
run-output relocation — see "## Run-output location" at the bottom. The two share one theme
(*where Bureau puts its files relative to the target repo*) and ship in one run, but are
independent deliverables. The original worktree fix is below, unchanged.

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

---

## Run-output location (added 2026-06-22)

A **second, larger** location-hygiene change, bundled with the worktree move above because they
answer the same question — *where does Bureau put its files relative to the target repo?* — but
the Architect should treat them as independent deliverables.

**Intent (Robin, 2026-06-22):** a run's output should land in a **gitignored `.bureau/` folder
inside the repo the run operates on**, not only in the global install's `output/runs/`. The
artifacts then live with the project they describe — most valuable in existing-project mode.

**Today:** one global install at `~/Code/novadiem/bureau/` writes every run's artifacts
(`spec.md`, `plan.md`, `prompts.md`, `log.md`, `state.json`, `design/`) to `output/runs/<slug>/`
*inside the install*. `output/` is gitignored there (except `output/studio/`). The execute-plan
prompt folder already lands in the target repo (beside the plan doc); the rest of the run dir
does not.

**Proposed shape (for the Architect to design, not prescribed here):**
- Run artifacts for a run against repo `R` end up under `R/.bureau/runs/<slug>/`.
- `.bureau/` is gitignored in `R` — the same lesson `.bureau-worktrees/` taught us above: an
  un-ignored Bureau dir gets swept into a commit.
- Note the symmetry with the worktree fix: ephemeral worktrees move **out** of the repo to
  `~/.bureau/worktrees/<repo>/<slug>/`; durable run artifacts move **into** the repo at
  `R/.bureau/runs/<slug>/`. Both under one `.bureau` namespace (one in `$HOME`, one in the
  repo). The Architect should make the two names coherent rather than accidental.

**The one decision Robin explicitly deferred to the Analyst/Architect:** whether the run writes
into `R/.bureau/` **from the outset** (RUN_DIR lives there for the whole run) or writes to the
global `output/runs/` as now and is **moved/copied into `R/.bureau/` as a close-out step**.
Both are legitimate; pick one and say why.

**Open design questions the Architect must resolve:**
- **Self-run case:** when Bureau runs *on itself* (target repo == the install, as in this very
  bundle), `R/.bureau/` sits inside the install. Does it coexist with `output/runs/`, or replace
  it for self-runs? Don't create two competing homes for the same artifacts.
- **`output/studio/`** is the committed cross-run Studio Record (The Witness). It is *not*
  per-target-repo and stays in the install. This relocation is for per-run artifacts only.
- **Archiving** (`mv output/runs/<slug> output/archive/<slug>`) and the **resume** instructions
  in `CLAUDE.md` both hard-code `output/runs/<task>/`; both change if RUN_DIR moves.
- **Concurrency** is already slug-scoped (`<slug>/`), so two runs on one repo stay separate —
  confirm that still holds under `.bureau/runs/`.
- **Non-repo or no-target runs** (planning-only against a target that isn't a git repo, or no
  target repo at all) still need a home — fall back to the install's `output/runs/`.

**Acceptance (run-output piece):**
- A run against repo `R` leaves its artifacts under `R/.bureau/runs/<slug>/` (timing per the
  deferred decision), and `R/.bureau/` is gitignored so nothing is committable.
- `CLAUDE.md` (run-dir creation, archiving, resume) and `agents/orchestrator.md` (the "Run
  directory" section) describe the chosen location consistently — no doc still claims artifacts
  live only in the install's `output/runs/`.
- Setup guidance ensures a target repo gets `.bureau/` gitignored before a run writes there.

This piece touches a **canon/process surface** (`agents/orchestrator.md` run-directory
convention, `CLAUDE.md`), so the run's Challenger spawn carries the `Promotion to canon:`
declaration per `agents/orchestrator.md`.
