# Grok Bot Workspace Instructions

These instructions apply only to Grok Bot sessions (Cursor Grok Bot / this
host). They do not change Claude Code or Codex Bureau runs.

For ordinary inspection of Bureau artifacts, do not start a run. Read
`state.json`, `log.md`, and the specialist files, and report in plain language.

## Native Grok Bot Bureau run

When Robin says "run the Bureau," "get the Bureau on this," "start the agent
framework," "run it as grok," or an equivalent start/resume, this top-level
session becomes **The Delegate**. Follow `agents/delegate.md`,
`docs/delegate-bridge/v2-integrated.md`, and `docs/host-runtime.md`.

Start the run with:

```sh
scripts/run-start.sh "$RUN_DIR" --target "$TARGET_REPO" \
  --workflow "$WORKFLOW" --slug "$SLUG" \
  --runtime grok --no-pointer-echo
```

Do not omit `--runtime grok`. Omitting it still resolves Claude. Do not pass
`--runtime openai` or `--runtime claude` from this host.

### Transport

Grok Bot's isolated spawn is the **Task executor**, not a standing agent and
not `scripts/run-grok-specialist.sh` executing a model.

| Bureau operation | This host |
|---|---|
| Fresh specialist | `Task`, `subagent_type: executor`. The prompt is the entire world: persona file, RUN_DIR paths, attempt id, nonce, workflow. Do not paste this chat. Executors start blank. |
| Resumable Conductor | Same Task executor. Keep the returned agent id in `delegate-state.json`. |
| Resume / note | `Task` with `resume`, or `MessageSubagent` to a still-running id. |
| Wait | background completion; `CheckSubagent` if it may be stuck. |
| Genuine fork | persist Delegate state, ask Robin in this chat, then resume the Conductor. |
| Cold reviewer | `scripts/run-cold-reviewer.sh` (same entrypoint). If that helper has no Grok provider path yet, log the gap and fail the checkpoint closed rather than grading in the manager session. |

Before each specialist Task, run:

```sh
scripts/run-grok-specialist.sh --plan "$RUN_DIR" <role> <prompt-file> <attempt-id>
```

Log the JSON payload. The helper still exits 2 and never launches a model.
That is intentional: bash cannot spawn Grok Bot Tasks. The Task call *is* the
launch. `--plan` is the audit record.

### Isolation (non-negotiable)

- No `CreateAgent` fleets, named teammates, or group rooms as specialists.
  They keep memory. Challenger would not be cold.
- No parent transcript in the Task prompt. Paths and persona text only.
- Handoff is on-disk `RUN_DIR` artifacts, not the executor's chat prose.
- Nested Delegate → Conductor → specialist is required. Do not collapse the
  cast into this warm session.

### Model IDs

`RUN_DIR/model-routing.json` records **grok-4.3** / **grok-4.6** from
`config/runtimes/grok.json`. Pass those names in the spawn prompt and in
SPAWN-EVENT lines.

As of 2026-08-25 this host's Task tool only accepts subagent model
`sand-default`. Record the resolved Grok model in routing; the live spawn uses
the host's available executor model until Cursor exposes Grok model slugs on
Task. That is a named host gap, not permission to inherit the manager model
silently or to skip routing.

`grok-build-0.1` stays exec-only. There is no Grok Spark analog helper yet;
Mage uses the role default.

### Claude and Codex

Leave them alone. This file does not authorize changing `run-start.sh`
allowlists for those hosts, their spawn tables, or their helpers.
