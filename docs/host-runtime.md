# Host runtime contract

The Bureau separates two decisions:

- **runtime routing** chooses provider model IDs and reasoning effort in
  `RUN_DIR/model-routing.json`;
- **agent host transport** creates, resumes, and waits for agent contexts.

The first-class pairings are:

| `model-routing.json#runtime` | Agent host | Status |
|---|---|---|
| `claude` | Claude Code Agent tool | supported |
| `openai` | Codex collaboration tools | supported |
| `codex` | alias for `openai` at startup/reviewer boundaries | supported |
| `grok` | Grok Bot Task/executor (`GROK.md`) | supported on Grok Bot; `run-start.sh --runtime grok` |
| `openrouter`, `hermes` | no native transport adapter yet | routing-only; fail closed for a run |

Do not infer host behavior from a model name. Read `runtime` once, select the
matching column below, and keep that transport for the run.

## Spawn, resume, wait, and human forks

| Operation | Claude Code host | Codex host | Grok Bot host |
|---|---|---|---|
| Fresh specialist | Agent tool, `subagent_type: general-purpose`, explicit `model` | Codex multi-agent spawn, currently exposed as `multi_agent_v1.spawn_agent`, `fork_context: false`, explicit `model` and `reasoning_effort` | Task executor, blank prompt, no parent transcript; log `--plan` payload first |
| Qualified fast Mage pass | normal fresh specialist | one-shot `scripts/run-codex-spark-specialist.sh`; Spark/high; `execute-plan` only; no resume | role default; no grok-build helper yet |
| Resumable Conductor | Agent tool; retain returned agent id | Codex multi-agent spawn, currently exposed as `multi_agent_v1.spawn_agent`; retain returned agent id | Task executor; retain agent id in `delegate-state.json` |
| Resume an idle agent | `SendMessage` to retained id | `multi_agent_v1.send_input` to retained id | Task `resume` or `MessageSubagent` |
| Pass a note to a running agent | `SendMessage` | `multi_agent_v1.send_input` | `MessageSubagent` |
| Wait for liveness/completion | host Agent/SendMessage result | `multi_agent_v1.wait_agent` | background completion; `CheckSubagent` if stuck |
| Genuine human fork | top-level `AskUserQuestion` | Delegate persists state and asks Robin in its top-level final response; after Robin replies, `multi_agent_v1.send_input` resumes the Conductor | Delegate persists, asks Robin in this chat, then resumes the Conductor |

Codex fresh-context spawns MUST pass no parent transcript. In the current tool
surface that means `fork_context: false`; in older/future surfaces this may be
called `fork_turns: "none"`. Passing the parent conversation (`fork_context:
true`, `fork_turns: "all"`, or equivalent) defeats the Bureau's cold-review and
specialist-isolation design.

Every native spawn uses `RUN_DIR/model-routing.json#roles.<role>`:

- pass `model` explicitly;
- on Codex, also pass `reasoningEffort` as `reasoning_effort`;
- never silently inherit the manager's model;
- keep the role's existing first-message identity, input, workflow, attempt, and
  nonce lines unchanged.

### Codex Spark execution profile

The Codex host's native collaboration endpoint currently accepts the configured Terra/Sol
child-agent set but rejects Spark as an unknown spawn model. The Codex CLI can start Spark, so
the Bureau exposes it as a separate, explicit execution profile rather than weakening the native
spawn allowlist:

- policy: `model-policy.v2.json#execution_profiles.granular-ui-fast`;
- resolved route: `model-routing.json#roles.mage.executionProfiles.granular-ui-fast`;
- transport: `scripts/run-codex-spark-specialist.sh` → ephemeral, one-shot `codex exec`;
- scope: first attempt at a vetted `execute-plan` Mage prompt for one existing component/style
  boundary, text-only inputs, and a known local validation command;
- fallback: the resolved Mage role default (normally Sol/high), only when the helper proves HEAD
  and the worktree are unchanged.

The prompt-folder tag `Execution-profile: granular-ui-fast` is necessary but not sufficient: the
Conductor and helper recheck policy eligibility at dispatch. New features, architecture, state,
API/navigation/contracts, dependencies/generated files, cross-coder work, sensitive/external
effects, visual/image judgment, release steps, retries, and review fixes stay role-default. Spark
never enters `multi_agent_v1.spawn_agent`, cannot be resumed, and cannot spawn its own subagents.
See `workflows/execute-plan/build-tail.md § OpenAI fast profile` for event and fallback handling.


## Grok host transport (Grok Bot)

Grok Bot is a first-class Bureau host. Entrypoint: `GROK.md`. Start a run with
`--runtime grok`. Claude Code and Codex do not use this path.

Live specialist spawn is the Grok Bot **Task executor**. It starts blank: no
parent transcript, no Grok Bot chat history, no standing-agent memory. That is
the isolation proof for this host. `CreateAgent` fleets, named teammates, and
group rooms remain forbidden as specialists.

`scripts/run-grok-specialist.sh` does **not** launch a model. Bash cannot spawn
Grok Bot Tasks. Before each Task, the Delegate or Conductor runs `--plan` and
logs the JSON payload (role, model, attempt, isolation flags). The helper still
exits 2. Then the host issues the Task. A `runtime=claude` or `runtime=openai`
routing file is rejected by the helper.

### Isolation contract

1. `model-routing.json#runtime` is `grok`.
2. `fork_context` is false: Task prompt contains persona text and paths only.
3. No standing agent as a specialist.
4. Routing records `grok-4.3` or `grok-4.6` from `roles.<role>`. As of 2026-08-25
   this host's Task tool only accepts `sand-default`; log the resolved Grok model
   on the SPAWN-EVENT and in the prompt. That is a named model-id gap, not a
   skip-routing license. `grok-build-0.1` stays exec-only.
5. Handoff is on-disk `RUN_DIR` artifacts, not executor prose. Same producer
   artifact rule as Codex.

`config/runtimes/grok.json` sets `supports_fresh_context_subagents` true because
Task executors start blank. If a future host cannot guarantee that, flip it
false and fail closed again.

### Starting a Grok run

```sh
scripts/run-start.sh "$RUN_DIR" --target "$TARGET_REPO" \
  --workflow "$WORKFLOW" --slug "$SLUG" \
  --runtime grok --no-pointer-echo
```

## Codex producer artifact handoff

Codex subagents can complete or stall without leaving the required files on disk.
For any producer role whose persona says it writes artifacts (`Analyst`,
`Architect`, `Designer`, `Spellwright`, and build-party coders), the Conductor
must treat the on-disk artifacts as the handoff, not the live prose.

After each producer spawn returns or times out:

1. verify the required output paths exist and contain the required marker
   sections named by the persona;
2. if missing, send one resume/nudge to the same agent: "write the required
   files now; if filesystem writes are unavailable, return an `ARTIFACT PACKET`
   with one fenced block per required file";
3. if the agent returns an `ARTIFACT PACKET`, the Conductor may mechanically
   transcribe that exact packet into the named files. This is not Conductor
   authorship: no paraphrase, no synthesis, no omitted sections. Log it as
   `mechanical-transcription-from-specialist`;
4. if neither on-disk artifacts nor a complete artifact packet appear after the
   nudge, close that agent, log `no-handoff`, and retry with a shorter,
   artifact-only prompt or escalate.

Never build an artifact-only retry prompt through shell interpolation of
Markdown. Put the prompt in the tool call message directly, or read it from a
plain file without command substitution. Markdown fences and backticks are data,
not shell syntax.

The Bureau's checked-in `AGENTS.md`, Delegate persona, and Conductor persona
explicitly authorize these Codex subagents when Robin starts a Bureau run. This
is framework execution, not ad-hoc delegation.

## Integrated Delegate topology

The topology is identical on Claude, Codex, and Grok Bot:

1. The Delegate creates the run and spawns one resumable Conductor.
2. The Conductor spawns fresh specialists and returns a `CONDUCTOR-RETURN` block
   at each checkpoint.
3. The Delegate stages a cold checkpoint packet and calls
   `scripts/run-cold-reviewer.sh`.
4. The Delegate validates the verdict, then resumes the same Conductor.

Host wording such as “Agent tool” or “SendMessage” is transport syntax, not a
different workflow. Use the mapping above.

On Codex, start a new integrated run with:

```sh
scripts/run-start.sh "$RUN_DIR" --target "$TARGET_REPO" \
  --workflow "$WORKFLOW" --slug "$SLUG" \
  --runtime openai --no-pointer-echo
```

On Grok Bot, use `--runtime grok` (see `GROK.md`). Claude keeps the existing
command without `--runtime` (or with `--runtime claude`).

## Cold reviewer boundary

`scripts/run-cold-reviewer.sh` is the single entrypoint for both hosts. The
caller stages only the v2 manifest under `NN-context`; the helper rejects
symlinks, `log.md`, and transcript-like files. Before each provider call it
appends the exact task prompt to the warm run log for audit; that log is never
part of the reviewer packet.

- Claude uses the existing `Read`-only, `--add-dir "$CTX"`,
  `--setting-sources ""`, no-session-persistence invocation.
- Codex copies the staged packet to a temporary directory and runs an ephemeral
  `codex exec` with user config and exec rules ignored, network tools disabled,
  the snapshot read-only, and explicit filesystem denies for the live run,
  target repository, framework checkout, home directory, and Codex/Claude
  session stores. The prompt contains snapshot paths only. Codex uses
  `config/delegate-verdict.codex.schema.json`, a closed structured-output
  projection of the unchanged Claude verdict contract.

Both paths emit a normalized verdict file and a Claude-shaped one-shot usage
envelope. Callers append exactly one `REVIEWER-TOKEN-EVENT` per returned
envelope.

## Token-accounting guarantees

The three JSONL per-leg rows below apply to integrated Delegate-topology Claude runs. A
direct-Conductor Claude run has no `delegate_session_id` with which to locate the top-session
transcript tree, so its Conductor/specialist figures remain an explicit legacy gap.

| Rail | Claude Code host | Codex host |
|---|---|---|
| Cold reviewer | exact one-shot envelope | exact stable `codex exec --json` `turn.completed.usage`, normalized by the helper |
| Top-level Delegate | post-hoc Claude JSONL window keyed by `delegate_session_id`; exact or explicitly degraded | unavailable |
| Resumable Conductor | post-hoc Claude JSONL sum across recorded/discovered Conductor legs; exact or explicitly degraded | unavailable |
| Specialists | post-hoc Claude JSONL joined by SPAWN-EVENT `attempt_id` and the run-scope nonce; exact or explicitly degraded | unavailable |

On Claude, `scripts/account-run.sh` invokes `scripts/aggregate-transcripts.sh` at terminal
close-out; the retired Stop/SubagentStop scripts are permanent exit-0 compatibility stubs and are
not an accounting fallback. “Unavailable” is a named accounting gap, not zero usage. Codex does
not expose the same stable JSONL transcript and per-specialist ownership interface, so the
aggregator returns a named `_runtime_gap` before transcript lookup. Until a stable session-usage
API exists, do not scrape Codex transcripts or fabricate zero-token specialist events. Run
artifacts, checkpoints, and decisions remain fully tracked. See `docs/run-accounting.md § B2`.
The Spark one-shot helper does preserve its exact `turn.completed.usage` in a normalized envelope,
but that per-attempt evidence is not silently promoted into the currently unavailable aggregate
specialist rail.

## Resume

Resume from `RUN_DIR/state.json`, `RUN_DIR/log.md`, and
`RUN_DIR/delegate-state.json` as usual. Read `model-routing.json#runtime` before
selecting a transport. If the retained Codex agent id is still available, use
`multi_agent_v1.send_input`; otherwise spawn a fresh Conductor with `fork_context: false`,
the same `RUN_DIR`, `topology: integrated`, and a recovery instruction naming
the durable artifacts. Log the recovery because transcript continuity was lost.
Spark profile attempts are never resumed: a clean failed first attempt falls back to a new native
Mage at its role-default model; an unsafe/dirty attempt requires adjudication.
