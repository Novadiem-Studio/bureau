# Cursor Agent host

Entrypoint: `CURSOR.md`. Start a run with `--runtime cursor`. Claude Code,
Codex, and Grok Bot do not use this path.

Live specialist spawn is the Cursor Agent **Task** tool. It starts blank: no
parent transcript, no Cursor chat history, no `.cursor/agents/` memory. That
is the isolation proof for this host.

`scripts/run-cursor-specialist.sh` does **not** launch a model. Bash cannot
spawn Cursor Tasks. Before each Task, the Delegate or Conductor runs `--plan`
and logs the JSON payload. The helper still exits 2. Then the host issues the
Task.

## Isolation contract

1. `model-routing.json#runtime` is `cursor`.
2. `fork_context` is false: Task prompt contains persona text and paths only.
3. No sticky Cursor subagent file as a specialist.
4. Routing records a Task slug from `config/runtimes/cursor.json`. Pass it
   explicitly. `inherit` is forbidden.
5. Handoff is on-disk `RUN_DIR` artifacts, or a mechanical `ARTIFACT PACKET`
   when the Task cannot write that path.

`config/runtimes/cursor.json` sets `supports_fresh_context_subagents` true
because Task executors start blank.

## Local vs cloud

| Mode | When | Where RUN_DIR lives |
|---|---|---|
| `environment: local` | default | Delegate machine; specialists write it directly |
| `environment: cloud` | Robin asked for cloud, and the current workspace is the target (or a Bureau self-run) | still the Delegate machine; cloud Tasks return an `ARTIFACT PACKET` unless they cloned a repo that already contains that run dir |

Cloud Task clones the **current workspace** onto a VM and works on its own
branch (`bc-…` agent ids). It does not mount `~/Code/novadiem/bureau` and it
does not see another checkout's `.bureau/runs/`.

Do not vendor the Bureau into a target repo to make cloud work. Multi-repo
cloud (canonical Bureau + a different target) is the Cursor SDK / Cloud
Agents API `repos` array, which this host has not wired yet. Fail that case
closed.

Cold graded review stays on **local** Task even when producers run in cloud:
the reviewer packet is staged on the Delegate machine.

## Cold reviewer

`scripts/run-cold-reviewer.sh` stages the bounded CTX, writes
`$CHECKPOINTS_DIR/${SPAWN_ID}-reviewer-task-plan.json`, and exits 2 with
`CURSOR-REVIEWER-HOST-TASK-REQUIRED`. The Delegate then issues a local blank
Task whose prompt is that plan's `taskPrompt` and whose world is the staged
CTX. The manager never grades.

Readiness-audit has no Cursor reviewer adapter yet. Fail that checkpoint
closed.

## Starting a Cursor run

```sh
scripts/run-start.sh "$RUN_DIR" --target "$TARGET_REPO" \
  --workflow "$WORKFLOW" --slug "$SLUG" \
  --runtime cursor --no-pointer-echo
```

A `runtime=claude`, `runtime=openai`, or `runtime=grok` routing file is
rejected by `scripts/run-cursor-specialist.sh`.
