# Git worktree runs

Execute workflows that **write code** use an isolated **git worktree** branched off the
project's integration branch (default `devel`). Planning artifacts stay in `RUN_DIR` under the
global framework install; code changes happen only inside the worktree.

## When it applies

| Workflow | Worktree |
|----------|----------|
| `feature` (planning only) | No — `RUN_DIR` only |
| `execute-plan` steps 1–5 | No — prompts and review only |
| `execute-plan` step 6+ (build) | **Yes** — create before first coder spawn |
| `execute-plan` step 7 (close out) | Merge + remove worktree |

## One global framework install

Clone once: `git@github.com:rheos/agent-framework.git`. Run from any project:

```bash
cd ~/Code/novadiem/oriva          # target repo workspace — not the framework
claude
```

```
Read ~/Code/novadiem/agent-framework/CLAUDE.md and start the agent framework.
Project context: /Users/robin/Code/novadiem/oriva/project-context.md
Run dir: ~/Code/novadiem/agent-framework/output/runs/20260612-oriva-auth/
```

## Project config

In `project-context.md`:

```markdown
## Git integration
- **Integration branch:** `devel`
- **Worktree parent:** `.society-worktrees/` (under target repo; add to `.gitignore` if desired)
```

`integration_branch` defaults to `devel` when omitted.

## Conductor flow

### Before build (after step 5 gate)

```bash
FRAMEWORK=~/Code/novadiem/agent-framework
$FRAMEWORK/scripts/run-worktree.sh create \
  --run-dir "$RUN_DIR" \
  --repo /path/to/target/repo \
  --base devel \
  --merge-policy end_of_job
```

Log output in `RUN_DIR/log.md`. Pass `worktree_path` to every build-party spawn:

```
WORKTREE: <absolute worktree path> — all file edits and git commits here, never on devel directly.
```

### Merge policies (`state.json` → `git.merge_policy`)

| Policy | When to merge |
|--------|----------------|
| `end_of_job` | Step 7 close-out only (default) |
| `per_prompt` | After each accepted build prompt (step 6) |
| `checkpoint` | When human approves at `[CHECKPOINT]` |

**Per-prompt merge** (optional):

```bash
$FRAMEWORK/scripts/run-worktree.sh merge --run-dir "$RUN_DIR"
$FRAMEWORK/scripts/run-worktree.sh sync --run-dir "$RUN_DIR"   # rebase next work onto devel
```

Record prompt id in `state.json` → `git.prompts_merged` (Conductor updates via jq).

### Close out (step 7)

1. Challenger accepted final diff
2. Human go (if policy is `end_of_job`)
3. `run-worktree.sh merge --run-dir "$RUN_DIR"`
4. `run-worktree.sh remove --run-dir "$RUN_DIR"`
5. Move plan out of `todo/` · summarize in `log.md`

On merge conflict: `[CHECKPOINT]` — human resolves in repo on `devel`, then `remove` when done.

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
    "branch": "society/20260612-oriva-auth",
    "worktree_path": "/path/to/repo/.society-worktrees/20260612-oriva-auth",
    "merge_policy": "end_of_job",
    "run_slug": "20260612-oriva-auth",
    "prompts_merged": [],
    "status": "active",
    "created_at": "2026-06-12T12:00:00Z",
    "merged_at": null,
    "last_sync_at": null
  }
}
```

`status`: `active` → `merged` → `removed`

## Scripts

| Command | Purpose |
|---------|---------|
| `run-worktree.sh create` | Branch + worktree + state |
| `run-worktree.sh status` | Show state + `git status -sb` |
| `run-worktree.sh sync` | Rebase society branch onto `devel` |
| `run-worktree.sh merge` | Merge society branch into `devel` |
| `run-worktree.sh remove` | Drop worktree (and branch if merged) |

See `scripts/README.md` for flags.
