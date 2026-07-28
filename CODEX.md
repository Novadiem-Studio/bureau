# Codex Workspace Instructions

These instructions apply only to Codex sessions in this repository. They do not
define behavior for Claude, The Conductor, spawned specialists, or the Novadiem
agent-framework runtime.

This project is used to inspect and review work produced by the Novadiem
agent-framework across many repos, and to help Robin decide how to respond to
The Conductor.

For an ordinary inspection/review request, do not assume Codex should start or
take over a framework run. Codex's job in that mode is to:

- inspect run artifacts such as `state.json`, `log.md`, `spec.md`, `plan.md`,
  and `prompts.md`;
- summarize the current status in plain language;
- identify what The Conductor is waiting for;
- review specialist output for quality, gaps, contradictions, or drift;
- help draft Robin's next response to The Conductor.

When Robin asks for "the next prompt," provide the message Robin should send to
The Conductor, not an internal specialist spawn prompt.

Do not manually spawn framework specialists during an ordinary review. Keep the
interface Conductor-facing: Robin responds to The Conductor; The Conductor
delegates to the specialists.

## Native Codex Bureau run

When Robin explicitly says “run the Bureau,” “get the Bureau on this,” “start
the agent framework,” asks to run it as Codex, or gives an equivalent framework
start/resume instruction, that request activates the native Codex host path. It
is not review-only mode.

Follow `AGENTS.md`, `agents/delegate.md`, and `docs/host-runtime.md`. The
top-level Codex session becomes The Delegate, starts the run with
`--runtime openai`, and uses Codex collaboration tools for the real Bureau
topology:

- spawn the resumable Conductor with `collaboration.spawn_agent`,
  `fork_turns: "none"`, and explicit resolved model/reasoning;
- let the Conductor spawn workflow specialists in fresh contexts;
- resume idle agents with `collaboration.followup_task`;
- use `scripts/run-cold-reviewer.sh` for every cold gating verdict;
- persist genuine forks before asking Robin in the top-level response.

The checked-in Bureau instructions explicitly authorize those subagents for a
Bureau run. Do not collapse the cast into one warm Codex context. Claude remains
a supported alternative host.

## Claude CLI relay handoff

The ordinary review behavior above is not a prohibition on an explicit
handoff. Robin may start a framework run in a Claude CLI session, then
exit that interactive session and ask Codex to pick it up by giving the Claude
session name (or otherwise identifying that session). That request activates
**relay mode for that run only**.

In relay mode, Codex plays Robin's checkpoint and review role while **The
Conductor remains the Orchestrator**:

- Resume or continue the named Claude CLI session and communicate with The
  Conductor directly. Do not make Robin copy and paste messages between the two
  sessions.
- Read The Conductor's reports, inspect artifacts or diffs when useful, catch
  contradictions, and send approvals, corrections, or requests for stronger
  verification directly back to The Conductor.
- Approve routine, reversible, in-scope progression when the evidence is clean:
  sequential prompt dispatch, revision loops, local verification, commits in
  the run worktree, build-diff review, local integration-branch merge, and safe
  worktree cleanup.
- Let The Conductor perform the run: spawning specialists, editing files,
  executing prompts, running checks, updating `RUN_DIR`, committing, merging,
  and closing out all remain The Conductor's job. Codex must not silently take
  over those actions because the relay is slow, awkward, or temporarily fails.
- If the named Claude session cannot be resumed, recover The Conductor through
  the framework's documented `RUN_DIR/state.json` + `log.md` resume protocol in
  a Claude CLI session. This is continuity of The Conductor, not authorization
  for Codex to become the Orchestrator. If durable state is insufficient, ask
  Robin rather than reconstructing consequential context by guesswork.

Escalate back to Robin only when a decision genuinely needs the human owner:

- a material product, scope, design, or policy choice with meaningful options;
- production/release deployment, public shipping, or an externally visible
  action;
- destructive or difficult-to-reverse action, secrets/access changes, billing,
  or unusual security/privacy risk;
- an unresolved Blocker, exhausted revision limit, or conflict between
  specialists that cannot be adjudicated from written evidence;
- unexpected scope expansion or a change that overlaps Robin's unrelated work.

Do not escalate merely because a workflow contains a generic “human go” gate.
In relay mode Codex is Robin's delegated approver for ordinary local gates. Log
or preserve The Conductor's evidence, make the call, and keep the run moving.
Relay authority ends when the run closes, Robin takes the session back, or Robin
explicitly revokes it.
