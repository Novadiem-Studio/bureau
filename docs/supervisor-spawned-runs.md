# Supervisor-spawned Bureau runs — what actually works

The role that uses this file is **The Envoy** (`agents/envoy.md`): point it at a
plan, it launches and relays. This doc is the mechanics, not the persona.

> **Scope.** Everything here is the mechanics of launching a run as a separate
> `claude --bg` **session**. If the Envoy spawns its Delegate as a **subagent**
> instead (Agent tool, the way the Delegate spawns the Conductor), most of this
> stops applying to that path: the two inventories, the three `--resume` fork
> cases, the `--add-dir` variadic trap and prompt-landing verification are all
> session-launch concerns a subagent does not have. The parts that stay true
> either way are the gate discipline — runs raise gates by write-and-stop, never
> `AskUserQuestion` — and the resume-from-disk contract. This file remains
> authoritative for anything still launched with `--bg`.
>
> **Where `--bg` came from — full provenance, 2026-09-13.** The 2026-09-02 Codex
> report described one command that got a session reading files and two that
> failed. `--bg` was carried forward from a *failed* one, which is a confusing
> route to the right answer, so the record is worth stating precisely.
>
> Codex's `--bg` attempt failed with `--add-dir /path` in the **space form**, and
> its own diagnosis was that variadic handling "consumed the prompt, leaving the
> session idle." That is the trap documented in §1, and the equals form fixes it.
> So the command prescribed here is not the failed one: it is the failed one with
> its actual defect corrected, and it has since launched the entire Rheo Stream
> campaign (S1, 0a, 0b1, 0b2, 0v) successfully. **`--bg` works.**
>
> What Codex got *working* was plain `claude "<prompt>"` in an interactive PTY,
> and its report lists three costs that disqualify it for unattended supervision:
> a workspace-trust screen that needs an interactive answer; a positional prompt
> that **did not survive that screen** and had to be typed into the PTY a second
> time; and a session that **died when the PTY terminated**. Visible, but mortal
> and hand-held.
>
> | mode | Robin can see it | supervisor can relay into it | survives unattended |
> |---|---|---|---|
> | Terminal / PTY `claude "…"` | yes, a window | unestablished (0b1 suggests no) | **no — died with the PTY** |
> | `claude --bg` | no | yes, measured | yes, measured |
> | subagent (Agent tool) | yes, in the parent transcript | yes, by construction | yes |
>
> So neither existing launch mode is good: `--bg` survives but is invisible, PTY
> is visible but fragile and mortal. That is the real case for the subagent path,
> and it does not rest on `--bg` having been a mistake.

An agent supervising Bureau runs needs two things from every run it starts: to
**see** it, and to **get a verdict into it**. Everything below was established
empirically on 2026-09-10 while supervising the Rheo Stream build, plus the
2026-09-02 Codex→Claude handoff recovered from `~/.codex/sessions/`. Facts are
marked as measured or inferred; the measured ones cost several hours to learn.

The short version: **launch with `claude --bg`, never `-p`, never a Terminal
window, and make runs raise gates by writing state and ending the turn.** The
provenance note above explains how `--bg` was arrived at by a confusing route;
the rule itself stands, and "never a Terminal window" is earned — Codex's PTY
session died with its terminal.

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

| launched as | in the app / `list_sessions` | `claude agents` | human can watch |
|---|---|---|---|
| desktop app | **yes** | no | yes (app) |
| `claude --bg` | **no** | yes, short id | claude.ai link |
| Terminal / PTY `claude "…"` | **YES — adopted** | yes (`kind: interactive`) | the window AND the app |
| headless `claude -p` | not established | yes (`kind: interactive`) | claude.ai link |

**CORRECTED 2026-09-13.** This table previously said no CLI launch mode reaches
the app. That is wrong, and it is the assumption that put the Envoy on `--bg`
and made its runs invisible to Robin.

**App sessions are wrappers around CLI sessions.** Each app record at
`~/Library/Application Support/Claude/claude-code-sessions/**/local_*.json`
carries a `cliSessionId` pointing at an ordinary transcript under
`~/.claude/projects/`. **107 of 111 app records** on this machine reference a CLI
transcript — i.e. nearly every session in the sidebar is a wrapped CLI session.
Note the direction: that is a property of app records, **not** an adoption rate.
It does not say what fraction of CLI launches get adopted, which nobody has
measured.

Measured on the 2026-09-02 Codex handoff, whose three sessions split cleanly:

| session | launch | app record |
|---|---|---|
| `be22c754` | `--bg` | none |
| `b475d6a5` | `--resume … --bg` | none |
| `f4fa384a` | **PTY** | `local_9346adbe` ✓ |

So a PTY-launched `claude` is adopted and appears in the sidebar; `--bg` is not.
`--resume <id> --bg` does **not** promote an existing background session either —
it forks a copy, which is what `b475d6a5` was, and that copy blocked.

**What is NOT established:** whether `claude attach <id>` promotes a running
`--bg` session into an adopted one. The mechanism is plausible (`attach` opens a
background session in a terminal, and terminal-attached sessions are the ones
that get adopted) and it would give both durability and visibility, but nobody
has run it. Test before relying on it.

**`--name` does not control the app title, and is not stored in the app record.**
Codex passed `--name '🏛️ Bureau Phase 1'`; the stored title is "Bureau Phase 1
checkpoint resume" with `titleSource: "auto"`, and the record's 29 fields contain
no name, alias or label field holding the flag's value. Zero of 111 app records
carry an emoji title. So the emoji-prefix convention below is useful only in
`claude agents` output — do not expect it in the sidebar.

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
