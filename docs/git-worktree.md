# Git worktree runs

Execute workflows that **write code** use an isolated **git worktree** branched off the
project's integration branch (default `devel`). Planning artifacts stay in `RUN_DIR` under the
global framework install; code changes happen only inside the worktree.

The worktree is the isolation mechanism, not the default delivery mechanism. Public GitHub
repositories deliver through the issue/PR path in `docs/github-delivery.md`; direct local merge
exists only after delivery resolves explicitly to `local`.

## When it applies

| Workflow | Worktree |
|----------|----------|
| `feature` (planning only) | No — `RUN_DIR` only |
| `execute-plan` steps 1–5 | No — prompts and review only |
| `execute-plan` step 6+ (build) | **Yes** — create before first coder spawn |
| `execute-plan` step 7 (close out) | GitHub PR merge (default) or explicit local merge, then remove worktree |

## One global framework install

Clone once: `git@github.com:rheos/bureau.git`. Run from any project:

```bash
cd ~/Code/example-target          # target repo workspace — not the framework
claude
```

```
Read ~/Code/bureau/CLAUDE.md and start the agent framework.
Project context: /path/to/target/project-context.md
Run dir: /path/to/target/.bureau/runs/20260612-target-auth/
```

## Project config

In `project-context.md`:

```markdown
## Git integration
- **Integration branch:** `devel`
- **Worktree parent:** `$HOME/.bureau/worktrees/<repo-basename>/` (outside the target repo — no `.gitignore` entry needed; override with `BUREAU_WORKTREE_ROOT`)
- **Delivery policy:** `auto` (public GitHub → PR; private/internal → local), `github`, or `local`
- **Private-repo delivery:** `local` (default) or `github`
```

`integration_branch` defaults to `devel` when omitted.

## Conductor flow

### Before build (after step 5 gate)

```bash
FRAMEWORK=~/Code/novadiem/bureau
$FRAMEWORK/scripts/run-worktree.sh create \
  --run-dir "$RUN_DIR" \
  --repo /path/to/target/repo \
  --base devel \
  --merge-policy end_of_job \
  --delivery auto
```

Log output in `RUN_DIR/log.md`. Pass `worktree_path` to every build-party spawn:

```
WORKTREE: <absolute worktree path> — all file edits and git commits here, never on devel directly.
```

Immediately resolve/open delivery per `docs/github-delivery.md`. GitHub mode creates or links an
issue, pushes the branch, and opens a draft PR before implementation.

### Merge policies (`state.json` → `git.merge_policy`)

| Policy | When to merge |
|--------|----------------|
| `end_of_job` | Step 7 close-out only (default) |
| `per_prompt` | Local delivery only: after each accepted build prompt (step 6) |
| `checkpoint` | Local delivery only: when human approves at `[CHECKPOINT]` |

**Per-prompt merge** (optional):

```bash
$FRAMEWORK/scripts/run-worktree.sh merge --run-dir "$RUN_DIR"
$FRAMEWORK/scripts/run-worktree.sh sync --run-dir "$RUN_DIR"   # rebase next work onto devel
```

Record prompt id in `state.json` → `git.prompts_merged` (Conductor updates via jq).

### Close out (step 7)

**GitHub delivery (default for public repos):**

1. Challenger accepted final diff; all objections are resolved
2. Complete and publish `RUN_DIR/github/evidence.md`
3. `pr-delivery.sh review`, then `pr-delivery.sh ready`
4. Human go / required collaborator approval and branch checks
5. `pr-delivery.sh merge`, then `run-worktree.sh remove`

**Explicit local delivery:**

1. Challenger accepted final diff
2. Human go (if policy is `end_of_job`)
3. `run-worktree.sh merge --run-dir "$RUN_DIR"`
4. `run-worktree.sh remove --run-dir "$RUN_DIR"`
5. Move plan out of `todo/` · summarize in `log.md`

On a GitHub conflict or blocked branch-protection check: `[CHECKPOINT]`; do not bypass the rule.
On a local merge conflict: `[CHECKPOINT]` — human resolves in repo on `devel`, then `remove`.

**Tree hygiene is forbidden in the target repo.** Never run `git clean` (any flags) or a
`reset --hard` + clean sweep in the target repo at close-out or before a merge. `.bureau/runs/`
is gitignored BY DESIGN and holds every concurrent run's live state: a `git clean -fdx` there
deletes ALL tracks' run dirs while sparing tracked files (verified live 2026-07-05 — one
track's close-out hygiene swept `mot/.bureau/runs/` for every track; tracked
`.bureau/regression/` survived, which is the fingerprint of this failure). If a pristine tree
is needed, clean inside your run's WORKTREE. The target repo's untracked state is never yours
to sweep.

## Concurrent runs

Two runs on the **same repo** are safe when each has its own worktree + `RUN_DIR`. Do not share
one worktree. Stagger test DB / docker steps if both hit shared infra.

## state.json `git` block

```json
{
  "git": {
    "enabled": true,
    "repo": "/path/to/repo",
    "base_branch": "devel",
    "branch": "bureau/20260612-oriva-auth",
    "worktree_path": "<home>/.bureau/worktrees/target/20260612-target-auth",
    "merge_policy": "end_of_job",
    "delivery_policy": "auto",
    "private_delivery": "local",
    "delivery_mode": "github",
    "github_repo": "owner/target",
    "github_visibility": "PUBLIC",
    "issue_number": 42,
    "issue_url": "https://github.com/owner/target/issues/42",
    "pr_number": 43,
    "pr_url": "https://github.com/owner/target/pull/43",
    "pr_is_draft": true,
    "pr_evidence_path": "/absolute/run/dir/github/evidence.md",
    "cold_review_status": null,
    "coauthors": [],
    "run_slug": "20260612-oriva-auth",
    "prompts_merged": [],
    "status": "pull_request_open",
    "created_at": "2026-06-12T12:00:00Z",
    "merged_at": null,
    "last_sync_at": null
  }
}
```

`status` in GitHub mode: `active` → `pull_request_open` → `ready_for_review` → `merged` →
`removed`. Local mode retains `active` → `merged` → `removed`.

## Scripts

| Command | Purpose |
|---------|---------|
| `run-worktree.sh create` | Branch + worktree + state |
| `run-worktree.sh status` | Show state + `git status -sb` |
| `run-worktree.sh sync` | Rebase bureau branch onto `devel` |
| `pr-delivery.sh open/refresh/review/ready/merge` | GitHub-native delivery lifecycle |
| `run-worktree.sh merge` | Merge bureau branch into `devel` for resolved local delivery only |
| `run-worktree.sh remove` | Drop worktree (and branch if merged) |

See `scripts/README.md` for flags.
