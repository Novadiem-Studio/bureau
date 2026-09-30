# Cross-run learning log

This file is the framework's cross-run learning log. The Conductor appends one entry per
failure repair — gated by the `lessons-append` gate in both `workflows/operational-build.md`
and `workflows/execute-plan/build-tail.md`, each in its respective close-out step. The full
entry format is defined below.

A run that produced no failure repair appends nothing. A run that produced multiple failure
repairs appends one entry per repair — multiple entries may share the same `run:` value. The
recurrence rule (per `docs/conventions/failure-signatures.md § Recurrence rule`) counts **distinct `run:` values**
among entries sharing a failure tail, not the total number of entries — two entries from the
same run are still one run, not two, for recurrence-counting purposes.

## Entry format

Every entry has four fields:

| Field | Value shape |
|-------|-------------|
| `run:` | The RUN_DIR slug (the `<yyyymmdd>-<task-slug>` dir name). This is the **recurrence-count key**: the recurrence rule (`docs/conventions/failure-signatures.md § Recurrence rule`) counts **distinct `run:` values** for a given failure tail, not occurrences. Two failure signatures recorded in the same run count as one run, not two. |
| `failure-signature:` | The failure-signature slug from `docs/conventions/failure-signatures.md § Failure signature format` (`<run-slug>-<NN>-<layer>-<short-description>`), OR a one-line summary if no formal slug was recorded for the failure. |
| `artifact-patched:` | The durable framework file that was changed to repair the failure, OR `none — deferred` when no durable file was patched this run. |
| `status:` | Exactly one of the valid values below. |

### Valid `status:` values

- **`promoted`** — A named change is already present in a canonical framework file (a
  convention, runbook, script, workflow, or persona). The lesson is closed.
- **`deferred: <reason>`** — Promotion is intentionally withheld. The reason line carries
  why, and a next-review trigger (a run or a date). Per
  `docs/conventions/failure-signatures.md § Recurrence rule`, a lesson whose failure tail now appears in two distinct `run:` values (count ≥ 2)
  must be `promoted` or carry a written `deferred: <reason>` — a blank or `scoped-local`
  entry at count ≥ 2 becomes a **Blocker** at that second (or later) run's close-out.
- **`scoped-local: <reason>`** — Judged not a framework defect (e.g. a one-off
  `env/preflight` environment glitch). **Disallowed once the same failure tail has appeared
  in two distinct `run:` values** — at count ≥ 2 the failure is evidence of a recurring
  issue, not a one-off, so `scoped-local` is no longer a legal status for it.

### Format example

```
format example — NOT a real lesson, remove before use

run: EXAMPLE
failure-signature: EXAMPLE-01-example-synthetic-not-real
artifact-patched: docs/runbooks/ios-build.md
status: promoted
```

`run: EXAMPLE` is a synthetic slug, not a real `<run-slug>`, and `example-synthetic-not-real`
is a tail no real failure can produce — so the recurrence rule never matches this entry and it
is never counted as a real lesson or a recurrence.

---

<!-- Live lessons log — append entries below; one per failure repair (one per failure-signature: slug). -->

run: 20260620-principal-delegate
failure-signature: 12-fixture-false-pass-on-comment-match
artifact-patched: output/runs/20260620-principal-delegate/regression/{04,09,12,15}-*.md (strip comment lines before grepping; mutation-test each static guard)
status: promoted — comment-strip authoring rule added to docs/conventions/regression-fixtures.md § Regression fixture file format
note: A static-grep fixture false-passes when its asserted token also appears in a code COMMENT — the guarantee can be deleted from the real code and the fixture still passes. Caught by the Challenger via mutation testing (delete the guaranteed line from a script copy → the fixture must FAIL). Rule: grep only NON-comment code (e.g. pipe through `grep -v '^[[:space:]]*#'`), and always mutation-test a static guard before trusting it.

run: 20260620-principal-delegate
failure-signature: 12-bsd-grep-mid-dollar-mismatch
artifact-patched: output/runs/20260620-principal-delegate/regression/{05,09,12}-*.md (use grep -F for literal-$ patterns)
status: promoted — BSD grep / literal-$ rule added to docs/conventions/regression-fixtures.md § Regression fixture file format
note: macOS/BSD grep BRE/ERE mishandles a `$` in the MIDDLE of a pattern, so `grep 'add-dir "$CTX"'` fails to match the literal text while `grep -F` matches it. Use grep -F (fixed-string) for any fixture/guard pattern containing a literal `$`. Confirmed twice this run.

run: 20260621-fixture-promotion-lifecycle
failure-signature: 03-fixture-heredoc-col0-awk-truncation
artifact-patched: docs/conventions/regression-fixtures.md § Regression fixture file format (nested-heredoc indentation authoring rule)
status: promoted — nested-heredoc indentation rule added to docs/conventions/regression-fixtures.md § Regression fixture file format
note: A `command: |` fixture that embeds a heredoc (`cat <<'EOF'`) whose body sits at COLUMN 0 false-passes when run via `.bureau/regression/run.sh`: the runner's awk captures the command block only while lines stay indented and STOPS at the first column-0 line, truncating the command to the setup + an unterminated heredoc opener — which exits 0 vacuously without invoking the code under test. Rule: indent the ENTIRE command block ≥2 spaces (heredoc bodies + the closing delimiter at exactly 2 spaces) so the 2-space strip lands the heredoc body at col 0 and the delimiter closes correctly. ALWAYS verify a fixture THROUGH run.sh's extraction, never by running the raw `command:` body (the raw body masks the truncation). Caught by the Conductor mid-build; the dogfood fixtures 16–21 were re-authored and re-verified through the extraction path before promotion.

## 2026-07-06 — rheo-memory-track5 (mot)
- **BSD sed voids GNU-style mutation probes.** `sed "0,/re/s//x/"` silently no-ops on macOS;
  a mutation test that doesn't verify the mutation actually landed proves nothing. Verify the
  mutated line changed (grep it) before trusting a NOT-CAUGHT result. Caught in-run at fixture 10.
- **onnxruntime-node + process.exit() = SIGABRT.** With a live inference threadpool,
  process.exit(0) dies with "mutex lock failed" exit 134. Operator scripts that embed must
  RETURN on success and use process.exitCode (assignment) for failure signaling so Node drains
  the pool. Found + fixed in mot's backfill-embeddings.ts; verified by two independent probes.
- **npm swallows flags without `--`.** A documented `npm run script --flag` silently drops the
  flag (a dry-run became a real run). Runbooks must write `npm run script -- --flag`; an
  operator-doc claim is only correct if empirically probed. Caught at the final gate.

## [2026-07-31T10:02:42Z] — resume-safety: a session dying mid-mutation-verify leaves broken, uncommitted source
failure-signature: interrupted-mutation-verify-leaves-broken-worktree
Context: mj-gateway 20260729 build tail was resumed after the prior Conductor session died. The log claimed "PROMPT 3 ACCEPTED (with one hardening routed back)", but the worktree held UNCOMMITTED, BROKEN source: api.py had `if False:  # MUTATION: never start the worker` — a mutation-testing artifact left in when the session died mid-verify. A naive resume trusting the log's "accepted" wording could have committed broken code (worker would never start).
Lesson: on resume, ALWAYS inspect the actual working tree (`git status`, `git diff`) and grep for mutation markers (`MUTATION`, `if False`) before trusting the log's acceptance claims. The log is the decision record; the working tree is ground truth for interrupted work. Mutation-verify must revert in a scratch copy or restore instantly — never leave the mutation in the source between steps.

## [2026-08-01T02:19:37Z] — dependency: an unpinned SDK floor (>=X) silently resolves to a breaking major
failure-signature: unpinned-dep-floor-resolves-to-breaking-major
Context: mj-gateway Prompt 7 spec/plan specified `mcp[cli]>=1.4`. By build time that floor resolved to the just-released mcp 2.0.0 — a breaking rewrite that removes `FastMCP` and renames `McpError`, the exact 1.x API the prompt dictates. A naive install would have produced code that can't import its own framework.
Lesson: when a prompt/spec targets a specific SDK API, pin the dependency BELOW the next major (`>=1.8,<2`), not just a bare `>=floor`. The coder caught this at `uv pip install` time and pinned <2; the plan's dep floor should be corrected upstream. For any LLM-authored plan citing a dependency ">=X", verify what X currently resolves to before building.

## [2026-08-02T04:12:56Z] — mock-only verification passed a gateway that never started its Discord client
failure-signature: mock-tests-miss-lifespan-wiring-gap
Context: mj-gateway Phases 1-3 built + cold-reviewed + merged with 47-48 green tests, ALL mock-based. At deploy, the gateway's FastAPI lifespan ran preflight→queue→worker but NEVER called mj.start_client() — so the self-bot never connected (self_bot_connected always False; every job would fail "discord disconnected"). Prompt 3's lifespan spec omitted start_client; Prompt 4 built start_client but nothing wired it in; Prompt 5 wired the worker only. Each per-prompt Challenger diff-review passed because it checked each diff against ITS prompt, and no test exercised "does the running app actually connect the client." Codex caught it at deploy (commit aebaeaa).
Lesson: mock-based unit tests + per-diff cold review do NOT catch cross-prompt WIRING/integration gaps — a symbol built in one prompt that no later prompt actually calls. For a multi-prompt build that assembles a runnable service, add a startup/integration smoke (even mocked at the boundary: assert the lifespan invokes start_client / the app's declared external clients are wired) OR a deploy-stage healthz gate BEFORE calling the build done. The build-tail should treat "does it actually run end-to-end" as a distinct check from "do the unit seams pass." Related: an MCP stdio server was also mis-specced as an always-on systemd daemon (stdio exits with no client) — same class of deploy-reality gap that mock tests can't surface.

## [2026-08-02T15:37:36Z] — a host-wide Traefik catch-all on a SHARED domain shadows the other tenants
failure-signature: catch-all-route-shadows-shared-host-tenants
Context: exposing mj-gateway's MCP, Codex added a Traefik route `Host(`mcp.rheo.ca`)` at `priority: 10000` with basicAuth. But mcp.rheo.ca was already a SHARED MCP host (M.O.L at /mol, M.O.T at /mot, served by a Coolify app with `Host(mcp.rheo.ca) && PathPrefix(/)`). The high-priority host-wide rule overrode them → every path (/mol, /mot, /mj, /mcp) returned mj's Basic 401; M.O.L + M.O.T broke. Nobody checked whether the subdomain was already multi-tenant before scoping a route to the whole host.
Lesson: before adding a Traefik/proxy route for a NEW service on an EXISTING subdomain, enumerate what already serves that host (`docker ps` + inspect labels for `Host(`that-domain`)`, `ls` the proxy's dynamic dir) and confirm you're not shadowing a tenant. Scope every service on a shared host by its own `PathPrefix(`/name`)`; never a bare `Host()` catch-all, and be extra wary of an explicit high `priority` that jumps the queue. Verify post-change that the OTHER tenants still return THEIR responses, not the new service's auth.

## [2026-09-27T19:42:06Z] — a coder that backgrounds its full test suite loses the run when its turn ends
run: 20260926-1a4-automatic-memory
failure-signature: 20260926-1a4-automatic-memory-01-workflow-directive-backgrounded-suite-dies-at-turn-end
artifact-patched: agents/backend.md, agents/frontend.md, agents/sysadmin.md (step 3), docs/conventions/tool-discipline.md § Long-running commands and waits, workflows/execute-plan/build-tail.md step 6, agents/delegate.md § Main manager loop step 2
status: promoted — Novadiem-Studio/bureau#92 (branch feat/92-ci-gated-checkpoints). Coders run checkpoint suites in the foreground in their own turn, never run_in_background or &, even under a session directive to background long commands; a manager that must detach a long gate uses nohup plus a done-marker file and polls it with a deadline. Deferred at the 1a4a close-out and promoted-pending at 1a4a-2 (Envoy decision, 2026-09-28); in 1a4a-2 every coder spawn carried the rule by hand and it held.
Context: rheo-stream 1a4a Prompt 4. systemsmith-4 started make test in the background and ended its turn, and the job died with it. The Conductor had to resume the coder to re-run it in the foreground, and that run found a real boundary-test failure (fixed in 848e606). Separately, the Delegate's integration-gate.sh wrapper for checkpoint 08 was killed (exit 144) before the gate wrote integration-results.json, and about 40 minutes of gate time were lost until it was re-run under nohup.
Lesson: a suite that outlives the agent that started it has no reader. Coder checkpoints run the suite in the foreground in the same turn. A manager that must background a long gate detaches it (nohup plus a done-marker file) and polls that file.

## [2026-09-27T20:54:17Z] — unbounded background wait loops ran for 10-11 hours after their checkpoint was settled another way
run: 20260926-1a4-automatic-memory
failure-signature: 20260926-1a4-automatic-memory-03-workflow-directive-unbounded-wait-loops-orphaned
artifact-patched: agents/delegate.md § Every wait has a deadline, docs/conventions/tool-discipline.md § Long-running commands and waits, agents/backend.md, agents/frontend.md, agents/sysadmin.md (step 3)
status: promoted — Novadiem-Studio/bureau#92 (branch feat/92-ci-gated-checkpoints). Every wait loop gets a deadline of about 60-90 minutes, exits on failure markers as well as the success file, and is stopped once what it waited for is settled; the Delegate sweeps `ps -eo pid,etime,command` for loops still pointing at the RUN_DIR at close-out. Carried by hand as the Envoy's wait-loop hygiene rule through 1a4a-2 (state.json#decisions.wait_loop_rule).
Context: the 1a4a Delegate started five background `until ls $RUN_DIR/build-checkpoints/07-*; do sleep 30; done` loops with no timeout. Checkpoint 07 was settled through a fork (the permission-classifier refusal, 07.F1), so the file never appeared, and the loops ran for 10-11 hours until Robin spotted them in the app's Background tasks panel.
Lesson: a wait with no deadline outlives its purpose silently. Bound it, make it exit on failure as well as success, and sweep for orphans at close-out.
