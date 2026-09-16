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

## Cold reviewer (two phases)

Bash cannot issue a Cursor Task, so the cold review is two calls around one
Task. The manager never grades.

1. **Plan.** `scripts/run-cold-reviewer.sh <RUN_DIR> <CTX> NN <spawn-id> <artifact> <routine|integration>`
   stages the bounded CTX and `artifact.sha256`, writes
   `$CHECKPOINTS_DIR/<spawn-id>-reviewer-task-plan.json` (also printed on stdout),
   logs the exact task prompt, and exits **2** with
   `CURSOR-REVIEWER-HOST-TASK-REQUIRED`. Exit 2 is a host action, not a failure.
2. **Task.** The Delegate issues a local blank read-only Task with the plan's
   `model` and `taskPrompt`, world = the staged CTX, and saves the Task's final
   message as a file, by convention the plan's `responsePath`
   (`<spawn-id>-reviewer-task-response.json`). The message is the verdict JSON,
   or a JSON object carrying it in `.result` or `.structured_output`, optionally
   with `.usage` and `.num_turns`.
3. **Resume.** `scripts/run-cold-reviewer.sh --resume <response-file> <same six args>`
   binds the response to the plan (same spawn id, checkpoint, artifact and staged
   digest; a plan already `resumed` is refused, so a re-spawn gets a new spawn
   id), extracts the verdict, validates it against
   `config/delegate-verdict.schema.json`, writes
   `<spawn-id>-reviewer-verdict.json` and a Claude-shaped
   `<spawn-id>-reviewer-envelope.json` atomically, marks the plan `resumed` with
   the response digest, appends an audit line, and returns the same metadata
   JSON the Claude and Codex adapters return (`verdict_path`, `envelope_path`,
   `artifact_sha256`, `hash_match`, plus `plan_path`). Exit **0**. A rejected
   response exits 1 and writes nothing durable.

Usage the Task did not report stays absent from the envelope (a `_note` says
so); `append-reviewer-tokens.sh` then records a zero-token event with its own
note rather than a fabricated count.

Readiness-audit has no Cursor reviewer adapter (`--resume` is refused there).
Fail that checkpoint closed.

## Starting a Cursor run

```sh
scripts/run-start.sh "$RUN_DIR" --target "$TARGET_REPO" \
  --workflow "$WORKFLOW" --slug "$SLUG" \
  --runtime cursor --no-pointer-echo
```

A `runtime=claude`, `runtime=openai`, or `runtime=grok` routing file is
rejected by `scripts/run-cursor-specialist.sh`.
