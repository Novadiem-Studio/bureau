# Codex Workspace Instructions

These instructions apply only to Codex sessions in this repository. They do not
define behavior for Claude, The Conductor, spawned specialists, or the Novadiem
agent-framework runtime.

This project is used to inspect and review work produced by the Novadiem
agent-framework across many repos, and to help Robin decide how to respond to
The Conductor.

Do not assume Codex should take over a framework run. Robin normally talks to
The Conductor in another session. Codex's job here is to:

- inspect run artifacts such as `state.json`, `log.md`, `spec.md`, `plan.md`,
  and `prompts.md`;
- summarize the current status in plain language;
- identify what The Conductor is waiting for;
- review specialist output for quality, gaps, contradictions, or drift;
- help draft Robin's next response to The Conductor.

When Robin asks for "the next prompt," provide the message Robin should send to
The Conductor, not an internal specialist spawn prompt.

Do not manually spawn framework specialists unless Robin explicitly asks Codex
to debug or simulate framework internals. Keep the interface Conductor-facing:
Robin responds to The Conductor; The Conductor delegates to the specialists.
