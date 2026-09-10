# Supervisor-spawned Bureau runs — what actually works

An agent supervising Bureau runs needs two things from every run it starts: to
**see** it, and to **get a verdict into it**. Everything below was established
empirically on 2026-09-10 while supervising the Rheo Stream build, plus the
2026-09-02 Codex→Claude handoff recovered from `~/.codex/sessions/`. Facts are
marked as measured or inferred; the measured ones cost several hours to learn.

The short version: **launch with `claude --bg`, never `-p`, never a Terminal
window, and make runs raise gates by writing state and ending the turn.**

---

## 1. The launch command

```bash
claude --bg \
  --name '🛰️ <run name>' \
  --permission-mode auto \
  --add-dir=/Users/robin/Code/novadiem/bureau \
  --add-dir=<run worktree> \
  "$(cat <run-prompt-file>)"
```

Every flag is load-bearing, and three of them fail silently if wrong.

**`--permission-mode auto` — without it the run does nothing.** Bare
`claude -p "<prompt>"` starts a session that denies *every* Bash call with
"needs approval and this session is non-interactive". The session looks alive
and accomplishes nothing. Measured.

Choose the mode per run, though. Codex used `auto` for a run touching
production Coolify resources and afterwards judged that a mistake, advising
Manual. `auto` is right for a code-build run with no production mutations; it is
the wrong default for a run that can touch live infrastructure.

**`--add-dir=` must use the equals sign.** The flag is variadic
(`--add-dir <directories...>`), so the space-separated form keeps consuming
following arguments — **including the run prompt**, which is silently swallowed
as another directory. Codex hit this before switching to the `=` form.

**`--name` cannot be changed later.** There is no way to rename a CLI session:
no messaging channel into it, and desktop rename tools do not reach it. A
missed `--name` is permanent for the life of the run — one run spent its whole
life called `rheo-stream-workspace-c5`. Use a distinctive emoji prefix so
supervisor-spawned runs are separable from hand-started ones at a glance.

**Verify the prompt actually landed.** Claude shows a workspace-trust screen
for an untrusted folder, and per Codex's account *"the original positional
prompt did not appear to survive the trust screen, so I sent the same prompt
into the running PTY a second time."* A launch into an untrusted directory can
produce a live session that never received its brief. After launching, confirm
the run read its prompt — run-dir writes appearing, or the transcript showing
the brief — before reporting it as started.

### Pre-launch checklist

The failure mode is not disagreeing with any of this, it is launching in a
hurry and skipping a flag. Do not send the command until all five hold:

1. `--bg` (not `-p`, not a Terminal window)
2. `--name` set, with the emoji marker
3. `--permission-mode` chosen deliberately for this run's blast radius
4. `--add-dir=` (equals form) for the framework install and the worktree
5. the prompt forbids `AskUserQuestion` and states the stop conditions

---

## 2. Visibility: two separate inventories

| launched as | `list_sessions` / `send_message` | `claude agents` | human can watch |
|---|---|---|---|
| desktop app | **yes** | no | yes (app) |
| `claude --bg` | no | **yes, short id** | claude.ai link |
| Terminal `claude "…"` | no | yes (`kind: interactive`) | the window |
| headless `claude -p` | no | yes (`kind: interactive`) | claude.ai link |

**Session-management MCP tools only see desktop-app sessions.** A CLI session
of any kind is invisible to them — `send_message` fails on both the
`local_<uuid>` and bare `<uuid>` forms with "session not found". `--name` makes
no difference. Measured on all three CLI launch modes.

So a supervisor keeps **two** inventories: the session-management tool for the
human's own app sessions, and `claude agents --json` for everything it launched
itself. Check both.

**Every session has a claude.ai/code URL.** Each transcript carries a
`remote_session_change` attachment with
`https://claude.ai/code/session_01…` — the same link that appears in commit and
PR footers. That is how a human watches a CLI-launched run, and a supervisor
should hand over the link whenever it reports a launch. Extract it from the
target run's own `.jsonl`:

```bash
grep -oh "https://claude\.ai/code/session_01[A-Za-z0-9]*" \
  ~/.claude/projects/<slugified-cwd>/<session-uuid>.jsonl | head -1
```

Do **not** grep your own transcript for it: a session accumulates every session
id it has merely read.

**Sidebar groups are unavailable.** They are a desktop-app concept, CLI
sessions never appear there, and the sidebar tools are not exposed to a
supervisor. The emoji in `--name` is the only grouping mechanism available.

---

## 3. Relay: getting a verdict into a run

This is the hard part, and the reason launch mechanics matter at all.

### `--resume` forks a copy in three distinct cases

Each produces a second agent writing one run directory — the corruption mode
the whole design exists to avoid:

1. **The session is mid-turn.** *"already running in the background, so this
   started a copy as `<id>`"*.
2. **The session is idle but its terminal is still open.** *"is open in another
   Claude Code process, so this started a copy"*. **`status: idle` is not a
   sufficient precondition** — a Terminal-launched session is unreachable for
   its entire life, because its window is open for its entire life. Measured.
3. **The short id was passed instead of the full session id.** `--resume` needs
   the full lowercase uuid exactly as `claude agents --json` prints it. Codex
   hit this: `claude --resume be22c754 --bg …` produced copy `b475d6a5`, and
   both sessions ended blocked with the run paused.

**If a copy spawns, `claude stop <copy-id>` immediately, then verify the run
directory's mtimes did not move.** A copy killed inside a minute does no damage.

### What does work

- **`claude --bg --resume <full-uuid> "<verdict>"`** continues the same session
  in place, *when nothing else holds it*. Under the gate protocol below, a run
  is stopped exactly when it needs a verdict, so this covers the real case.
- **A PTY you control** is a true relay into a *running* session and never
  forks. This is how the Codex handoff worked — `claude` launched inside an
  interactive PTY it could type into again later. `tmux`, `script` or `expect`
  give a supervisor the same thing from one-shot shell calls.
- **A desktop session** accepts `send_message`, but the human has to start it.

---

## 4. Never raise a gate with `AskUserQuestion`

An interactive picker **owns the session's turn until a human clicks it**.
While it is up:

- the session cannot receive messages — `send_message` returns `queued` and the
  message is never read. **"Queued" is not "delivered."**
- nothing is written to the run directory;
- the session reports `isRunning: true` and looks healthy from outside.

That last property is what makes it dangerous: a stalled run is
indistinguishable from a long subagent leg. Diagnose it by reading the
transcript for `(called AskUserQuestion)` as the last action.

Measured cost: one run stalled **over an hour** with a verdict on its own fork
sitting unread in its transcript, ending in a takeover and a brief window with
two Delegates live on one run directory.

**The protocol that works** — write the gate down and stop:

1. write it to `state.json#checkpoints` and `open_questions`, append to
   `log.md`;
2. fire the human notification with the question and the recommendation;
3. **end the turn** and wait.

The verdict can then arrive by any channel — relay, resume, or the human
answering directly — and the run is unblockable by all of them, where a picker
admitted only the last, and only while someone was watching. This also matches
what a checkpoint protocol already assumes ("hold at the gate",
write-before-return).

A run that raises gates this way is **structurally supervisable**. One that uses
pickers is not, regardless of how carefully it is monitored.

---

## 5. Taking over a stalled run

The run directory on disk is authoritative, not any session — that is what
makes fresh-leg resume work at all.

1. **Verify the old session is dead *immediately* before writing anything.** In
   one incident a session was declared dead that had come back to life
   **fourteen seconds earlier**, briefly putting two Delegates with live
   Conductors on one run dir. Check liveness and run-dir mtimes in the same
   breath as the takeover write, never minutes before.
2. Back up `state.json`.
3. Resolve the checkpoint in `state.json`; append the verdict and a takeover
   entry to `log.md`.
4. Send the old session a **stand-down order**. If it is picker-blocked the
   message queues and it reads it whenever it unblocks — which is exactly what
   you want: it wakes up, sees the order, and stands down instead of resuming.
5. Launch a fresh Delegate leg pointed at the run directory.
6. Record ownership in `delegate-state.json` (session id, leg number, and which
   conductor ids are dead) so the accounting stays legible.

A well-behaved run will reconcile the mess itself: after one takeover the
incoming leg noticed a dangling spawn event with no terminal pair, emitted the
missing `terminated` line, and re-dispatched the work as a retry.

---

## 6. Running the supervision loop

**Monitor the run directory, not the session.** `state.json`, `log.md` tail,
`SPAWN-EVENT` lines, plus git branch/worktree/PR state. The session's own status
is the least reliable signal — `isRunning: true` covers both "working hard" and
"frozen on a picker".

**Scope-check by file map, not by directory.** A plan assigns *files* to chunks,
and legitimate work crosses directory lines: one chunk implemented a protocol
declared by another, in the other's directory. Directory-based filtering
produced three false alarms in one session. Grep the plan for the filename to
find its owner before calling anything a leak.

**Wakeup cadence is not guaranteed.** A 15-minute loop fired ~5 hours late once.
Runs must therefore hold their gates safely without supervision — which the
write-and-stop protocol gives — and a supervisor should re-verify everything
after a long gap rather than assume continuity.

**Verify the run's claims before ruling on them.** When a run escalated a fork
it supplied four supporting facts; all four checked out, including a subtle one
(that a term appeared in the prompts only in an unrelated sense). Checking cost
minutes and made the verdict defensible.

**Findings from other sessions are "raised, not established."** A parallel
review session filed a confident architectural objection; verified against the
ratified decision record, its central claim was simply wrong, and acting on it
would have blocked a run on a non-issue.

**Attach deadlines to deferrals.** When a run defers a known defect, bind it to
the milestone it must precede. A deferred defect with no deadline is a forgotten
defect — and one deferred here sat under a substrate that a later *scored*
benchmark would run on, where it would have silently distorted the comparison.
