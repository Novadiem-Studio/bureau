# Cursor Agent Workspace Instructions

These instructions apply only to Cursor Agent sessions (this host, including
Cursor Cloud Agents). They do not change Claude Code, Codex, or Grok Bot
Bureau runs.

Grok Bot in Cursor is a **different** host (`GROK.md`, `--runtime grok`). Do
not start a Grok run from a Cursor Agent session, and do not start a Cursor
run from Grok Bot.

For ordinary inspection of Bureau artifacts, do not start a run. Read
`state.json`, `log.md`, and the specialist files, and report in plain language.

## Native Cursor Bureau run

When Robin says "run the Bureau," "get the Bureau on this," "start the agent
framework," "run it as cursor," or an equivalent start/resume, this top-level
session becomes **The Delegate**. Follow `agents/delegate.md`,
`docs/delegate-bridge/v2-integrated.md`, `docs/host-runtime.md`, and
`docs/host-cursor.md`.

Start the run with:

```sh
scripts/run-start.sh "$RUN_DIR" --target "$TARGET_REPO" \
  --workflow "$WORKFLOW" --slug "$SLUG" \
  --runtime cursor --no-pointer-echo
```

Do not omit `--runtime cursor`. Omitting it still resolves Claude. Do not pass
`--runtime openai`, `--runtime claude`, or `--runtime grok` from this host.

### Transport

Cursor's isolated spawn is the **Task tool**, not a sticky `.cursor/agents/`
desk and not `scripts/run-cursor-specialist.sh` executing a model.

| Bureau operation | This host |
|---|---|
| Fresh specialist | `Task`, blank prompt. Persona file, RUN_DIR paths, attempt id, nonce, workflow. Do not paste this chat. Pass `model` from routing. `environment` is `local` unless Robin asked for cloud and the cloud rules below hold. |
| Resumable Conductor | Same Task. Keep the returned agent id in `delegate-state.json`. Cloud Conductor ids are `bc-…`. |
| Resume / note | `Task` with `resume` to a still-running or idle id. |
| Wait | background completion; poll only if the next step is blocked on that agent. |
| Genuine fork | persist Delegate state, ask Robin in this chat, then resume the Conductor. |
| Cold reviewer | Two phases. `scripts/run-cold-reviewer.sh` stages the packet, writes the Task plan, and exits 2 with `CURSOR-REVIEWER-HOST-TASK-REQUIRED`. Issue a **local** blank Task against that staged CTX, save its final message to the plan's `responsePath`, then re-run with `--resume <that file>` to get the verdict, envelope and metadata JSON. Never grade in the manager session. |

Before each specialist Task, run:

```sh
scripts/run-cursor-specialist.sh --plan --environment local \
  "$RUN_DIR" <role> <prompt-file> <attempt-id>
```

Use `--environment cloud` only when the cloud rules below hold. Log the JSON
payload. The helper still exits 2 and never launches a model. That is
intentional: bash cannot spawn Cursor Tasks. The Task call *is* the launch.

### Isolation (non-negotiable)

- No `.cursor/agents/` files, named teammates, or group rooms as specialists.
  They keep memory. Challenger would not be cold.
- No parent transcript in the Task prompt. Paths and persona text only.
- Never pass `model: inherit`. Use the resolved Task slug.
- Handoff is on-disk `RUN_DIR` artifacts, not the Task's chat prose. If the
  specialist cannot write `RUN_DIR` (typical for a cloud VM that does not see
  the local run dir), it returns an `ARTIFACT PACKET`; the Conductor
  transcribes it mechanically.
- Nested Delegate → Conductor → specialist is required. Do not collapse the
  cast into this warm session.

### Cloud

Robin asked to run specialists in the cloud: set Task `environment: cloud`.

Cloud Task clones **this workspace**, not an arbitrary second repo. Allowed
only when the current workspace is the target repo, or this is a Bureau
self-run (install path is the target). Do not copy `~/Code/novadiem/bureau`
into a project to make cloud work.

Cold roles stay local: Challenger, Notary, and the Delegate reviewer Task.
They grade a staged packet on this machine.

Named gaps, fail closed rather than improvise:

- multi-repo cloud (Bureau install + a different target) needs the Cursor SDK
  / Cloud Agents API `repos` array — not Task;
- readiness-audit cold reviewer has no Cursor adapter yet;
- token accounting is a named `_runtime_gap` (same class as Codex).

Unattended SDK launch is deferred. This host is the Cursor Agent session
Robin is talking to.

### Model IDs

`RUN_DIR/model-routing.json` records the Task slugs from
`config/runtimes/cursor.json`. Pass those names on every Task.

As of 2026-09-14 this host's Task tool accepts:

- `composer-2.5-fast`
- `gpt-5.6-sol-medium`
- `cursor-grok-4.6-high-fast`
- `claude-opus-5-thinking-high`

If Cursor's live allowlist later omits a resolved slug, log the gap, pass the
closest listed slug, and keep the resolved id in routing and SPAWN-EVENT.
That is a named model-id gap, not permission to inherit the manager model.

### Claude, Codex, and Grok Bot

Leave them alone. This file does not authorize changing `run-start.sh`
allowlists for those hosts, their spawn tables, or their helpers.
