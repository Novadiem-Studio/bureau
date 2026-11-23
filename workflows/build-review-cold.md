# Workflow: build-review-cold

**When to use:** a self-contained change in existing code that you can just build — no fresh
requirements to settle, no plan to decompose — where you want the framework's speed-first third
gear: **build solo, then run zero or one cold diff review**, or, for a diff on exactly two
silent-failure surfaces where Robin opts in, one fan-out set of cold reviews (steps 6-9).
GitHub delivery always gets one cold readiness read: the step-5 review, or on the fan-out path the
interaction reviewer's readiness pass (step 8). Local delivery runs a cold review only if the diff
can fail silently. This is the right size for the common case where a bug would announce itself
(a crash, a broken feature, a
visibly wrong result), so the only review worth paying for is the one that catches the bugs that
DON'T announce themselves. Local runs normally ship through the self-gate; public PRs pay for one
additional cold read because the delivery record promises reviewed evidence.

**When NOT to use:**
- A new product or feature that needs requirements or design before anyone can build → `feature`,
  or `bureau-lite` when it needs a short spec and plan but not the full review cadence. This
  workflow has no spec/plan/prompt phase; if you can't just build it, it isn't this.
- A framework / canon change — anything touching `workflows/`, `agents/`, `docs/conventions*`, a
  `plans/` prompt folder, or `index.md` → the full pipeline / `execute-plan` with its gates. Canon
  changes carry the promotion + battle-test gate, which lives in the fuller review, not here.
- A diff touching 3 or more silent-failure surfaces, a genuinely high-blast-radius change (a
  migration that also re-prices a ledger, an authz rewrite spanning a tenancy boundary), or a diff
  that needs design → escalate to `execute-plan` (or `feature` if it needs design). A diff on
  exactly 2 surfaces escalates too, unless Robin turned on the surface fan-out for this diff (step
  3, then step 6). One cold reviewer on a wide, interacting diff is under-powered.
- A known defect to reproduce → repair → verify with a captured repro test → `bug-fix` (that
  workflow captures a repro and re-runs it; this one gates on the diff's failure surface instead).

This is the speed-first gear. Speed is the point, so the guard above matters: when a task fits two
workflows and one of them is this, take this ONLY if it clearly clears the four bars above.

**Type:** mixed (builds solo, then runs zero or one cold review, or, opt-in for exactly 2 fired
surfaces, one fan-out set of cold reviews per round, and adjudicates, in one run. No `spec.md`, no
`plan.md`, no `prompts.md`, no reconciliation, no per-diff critic loop.)

**Inputs:** the change to build (inline, or a short description); the target repo / sub-app; in
existing projects, the workspace orientation (see "Existing-project mode" in
`agents/orchestrator.md`) and the per-sub-app skills the affected surface needs. No plan doc, no
prompt folder.

**Outputs:** under `RUN_DIR` (see `docs/run-protocol.md`): `log.md`, `state.json`. When the
self-gate or GitHub readiness gate fires, `diff-context.md` — the diff + the review question, handed to the cold
Challenger so it reviews cold (the diff, not the build session). When the surface fan-out runs
(steps 6-9), `surface-review/r<N>/` per round: its `diff-context.md`, each reviewer's `.json` and
`.md`, `merged.json`, `final.json`, the closure packets a `fix` route writes, and `overrides.json`
when the Conductor overrides a blocker. The change itself lands in an isolated worktree and is
delivered through a linked PR for public GitHub repositories (or the
recorded local fallback) to the dev/integration branch. No `spec.md`, no `plan.md`, no `prompts.md`.

**Leans on skills:** **novadiem-engineering** (cross-project coding standards — loaded by the
builder and, when it runs, the cold Challenger, so build and review hold the same bar) + the
project's `testing` skill if it has one + the per-sub-app skills the affected surface needs. Load
the skill; don't duplicate its runbook.

## Steps

Run these as spawned subagents where named (see "How to spawn an agent" and "Model routing" in
`agents/orchestrator.md`). Pass `RUN_DIR` as an absolute path in every spawn prompt.

1. **Worktree** — create the isolated branch/worktree with `scripts/run-worktree.sh create` and
   the project delivery policy. Derive acceptance criteria into `RUN_DIR/github/issue.md`; obtain
   external-action authorization if not already granted; then run `scripts/pr-delivery.sh open`
   before coding. Public GitHub repositories require the linked issue and draft PR;
   private/non-GitHub work may use the recorded local fallback.

2. **The Conductor** dispatches the coder the change's domain names — **The Mage** (frontend/UI) ·
   **The Systemsmith** (backend/data/contract) · **The Mechanic** (ops/infra) — at tier **strong**
   to plan and build the change solo and commit it: no spec/plan/prompts, no reconciliation, no
   per-diff critic loop → a built, committed diff in the worktree. Green-before-done still applies
   (`novadiem-engineering §5`): the builder
   runs the work's own checkpoint (type/tests/build) and gets it green. If the change turns out to
   need requirements or design, or spans several coders' domains at once, STOP and raise a
   `[CHECKPOINT]` — this isn't a build-review-cold task (see When NOT to use).

3. **Gate** — the silent-failure self-gate (advisory human judgment; the operator, or the Conductor
   self-gating — no script). Read the built diff and ask ONE question: **does this diff write
   durable state, move value, gate access, fire something irreversible, or change concurrent access
   to shared data — where a wrong result would NOT announce itself in use?** Scan ALL FIVE surfaces
   (do NOT stop at the first YES) and count how many fire, then route on the count: **0 fire, ship
   (step 4 for local delivery; step 5 for GitHub delivery, whose readiness requires a cold review);
   exactly 1 fires, run the ONE cold build-diff review (step 5); exactly 2 fire, escalate unless
   Robin turns on the surface fan-out (below); 3 or more fire, or a single high-blast-radius change,
   escalate to fuller review (see When NOT to use).**
   - **S1 — Durable state:** a DB migration/schema change; a write to a persisted record, ledger
     row, or stored document; a change to how persisted data is serialized, keyed, or de-duplicated.
   - **S2 — Money / value:** code that computes, moves, credits, debits, prices, or reconciles a
     balance, ledger, invoice, quota, or credit.
   - **S3 — Auth / access / privacy:** a change to who can read/write what — an authz check, a
     permission/role gate, a visibility/scoping filter, a tenancy boundary, or a secret/PII path.
   - **S4 — Irreversible external action:** code that sends (email/SMS/webhook/notification),
     deletes, deploys, or mutates external infra (DNS, billing) where the effect can't be pulled back.
   - **S5 — Concurrency / race:** a diff that adds or changes concurrent access, shared mutable
     state, ordering assumptions, or a non-atomic read-modify-write on durable/shared data — where
     the failure is a lost update, double-processing (double-charge, duplicate send), or a dropped/
     reordered event. Cue: new locks/transactions/async ordering, or a shared-state write with no
     atomicity/idempotency guard on a durable or money surface.

     Decision test per surface: not "could the app be important" but "if this exact line is wrong,
     does something visibly break, or does it quietly do the wrong thing?" A crash / broken screen /
     wrong-but-visible number is self-announcing, so that surface does NOT fire. Silent corruption /
     silent leak / silent miscount / irreversible side effect / silent race fires. Scan all five and
     count: 0 fired, ship locally or run the GitHub-readiness cold review; exactly 1 fired, run the
     ONE cold review; 2 or more fired (or a single high-blast-radius change), do NOT run the single
     cold review. The failure modes interact across surfaces and one refute-first reviewer
     under-powers it, so 3 or more escalate (see When NOT to use), and 2 escalate too unless the
     fan-out route below applies. The same interaction is why the fan-out path carries its own
     interaction reviewer (step 8). `[CHECKPOINT]` if the operator can't decide the gate cleanly.

   **Exactly 2 fired: the opt-in surface fan-out.** The default is off: a 2-surface diff escalates
   exactly as it always has. A task or brief line `Surface fan-out: requested` only makes the
   Conductor ask; a line reading `Surface fan-out: on` is read as a request, never as on. Only
   Robin's literal answer at the fork below turns it on. Nothing an agent writes (the brief, the
   Delegate's own summary, a spawn prompt) can enable it.
   - **Eligible** only when all hold: exactly 2 surfaces fired; not high-blast-radius; no design
     needed; the diff touches no canon/process surface (the bold label **The canon/process
     surfaces** in `docs/conductor-gates.md`).
   - **Eligible, with `Surface fan-out: requested`:** stage
     `RUN_DIR/surface-review/r1/diff-context.md` as step 6 describes, then return a genuine fork
     (`docs/delegate-bridge/v2-integrated.md`, heading `v2 §1`, the Conductor return-block
     schemas) with `return-type: genuine-fork`,
     `signal-fired: 3`, `artifact` = `RUN_DIR/surface-review/r1/diff-context.md` and
     `artifact-hash` = its `shasum -a 256`, asking: "Escalate to execute-plan (default) or run the
     surface fan-out trial on S<a>+S<b>?" The Delegate appends the fork to the ledger
     `RUN_DIR/delegate-decisions.md` as record `<NN>.F<k>` (for example `03.F1`, header
     `## 03.F1 — <timestamp>`) and asks Robin; `scripts/ledger-set-robins-call.sh <NN>.F<k>`
     writes his literal answer into that record's `Robin's call:` line. When the Conductor
     resumes, it reads that `Robin's call:` value from the ledger itself, never from the
     Delegate's relay text, and goes to step 6 only when it says to run the fan-out. Either way
     `fanout_source` is `ledger:<NN>.F<k>`. On a direct-Conductor run there is no ledger: Robin's
     own chat reply is quoted verbatim in the `log.md` entry, the Conductor goes to step 6 only on
     that reply, and `fanout_source` is `chat`. On a no, escalate; the staged file stays as the
     record of what was offered.
   - **Eligible without a request:** escalate as before, with no fork. There is no fork without a
     request.
   - **Not eligible** (3-5 fired, high-blast-radius, needs design, or a canon/process diff):
     escalate.

   **`SURFACE-GATE:` line, every case.** Once the route is settled (after Robin's answer when a
   fork ran), the Conductor writes one machine line to `log.md`, composed with `jq -cn` and
   appended through `scripts/log-append.sh "$RUN_DIR" "<heading>" -` with the line on stdin (the
   `GRILL-TRIGGER:` precedent). These are the keys, in this order:

   ```
   SURFACE-GATE: {"at_round":0,"fired":["S1","S4"],"count":2,"high_blast_radius":false,"needs_design":false,"eligible_fanout":true,"fanout_requested":true,"fanout":"on","fanout_source":"ledger:03.F1","route":"fanout","escalated_to":null}
   ```

   `count` is the length of `fired`; `high_blast_radius` and `needs_design` are the step-3
   judgments the eligibility list names. `eligible_fanout` is true only when every **Eligible**
   condition above holds (exactly 2 fired, not high-blast-radius, no design needed, not a
   canon/process diff, and otherwise in scope for this workflow), whatever Robin answers, and
   `fanout_requested` is true when the task or brief carries `Surface fan-out: requested` or
   `Surface fan-out: on`.
   `at_round` is 0 here and N when a fan-out round escalates (step 9). `fanout` is `on` or `off`.
   `fanout_source` names where the answer to the fork lives whenever a fork ran, whatever Robin
   answered (a no included): `ledger:<NN>.F<k>` or `chat`. It is `none` only when no fork ran (0
   or 1 fired, not eligible, or eligible without a request). A step-9 escalation line repeats the
   step-3 value. `route` is `ship`, `single`, `fanout` or `escalate` (this step's vocabulary, separate from the reduce routes; `single` is any step-5
   review, the GitHub readiness one included, and `ship` is step 4). `escalated_to` is null
   unless `route` is `escalate`, then
   `{"run_dir":"<absolute RUN_DIR carrying the escalated review>","workflow":"execute-plan|feature"}`.
   The eval reads both arms from this line (its control arm selects on `eligible_fanout`), so a
   zero-surface ship writes one too.

4. **The Conductor** (**strong**) — local-delivery close-out when the self-gate returned NO → `log.md`,
   `state.json`. Close out at the `[DEV-VERIFIED CHECKPOINT]` (format in `agents/orchestrator.md`):
   confirm dev is green, human go, then use the recorded local merge into the dev/integration branch only and
   `run-worktree.sh remove`; append the run to `log.md`; run `scripts/account-run.sh <RUN_DIR>`
   and set `state.json#accounting` per `docs/run-accounting.md` as the final action. This is the
   local zero-silent-risk path. The run ends at dev-verified.

5. **The Challenger** (Critic, **strong**, fresh context required) — cold build-diff review, run
   when the self-gate returned YES or when GitHub delivery needs its readiness review → `log.md`,
   findings. The Conductor first writes
   `RUN_DIR/diff-context.md` (the diff + the ONE question) and spawns ONE cold build-diff reviewer,
   refute-first, diff-only. It reviews per the build-diff slice (`agents/critic/build-diff.md`) and is
   spawned cold per the delegate-v2 cold-reviewer recipe (`docs/delegate-bridge/v2-integrated.md § v2 §3`):
   fresh context, `--tools "Read"`, `--add-dir "$CTX"` on the staged diff-context only,
   `--setting-sources ""` for coldness. It does **NOT** receive `log.md`, the build rationale, or the
   builder's reasoning. When one silent-failure surface fired, the one question it answers is:
   **"what here corrupts, leaks, or miscounts WITHOUT announcing it?"** When zero fired but GitHub
   delivery requires review, it instead cold-reviews correctness, scope, tests, risks, and rollback
   evidence without inventing a silent-failure premise.
   - **The Conductor / Robin adjudicates:** route the fix back to the coder (max 2x —
     `max_critic_loops`), accept, or `[CHECKPOINT]`. On a canon/process-surface diff, the spawn
     carries the `Promotion to canon: yes/no` block and the Challenger applies the 15a/15b promotion
     + battle-test gate (`agents/critic/build-diff.md`).
   - **Close out** at the `[DEV-VERIFIED CHECKPOINT]` as in step 4: publish the Challenger summary
     and objection resolutions, mark the PR ready, get human go, then GitHub/local fallback merge +
     worktree removal, append to `log.md`, then `scripts/account-run.sh <RUN_DIR>` last. The run
     ends at dev-verified.

Steps 6-9 run only on the surface fan-out path: step 3 routed here on Robin's recorded yes to the
fork a `Surface fan-out: requested` line raised (round 1), or step 9 routed `fix` (round N+1).
Each round lives in `RUN_DIR/surface-review/r<N>/`. Every reviewer loads `agents/critic.md` core,
the shared slice `agents/critic/surface-review.md` (inputs, coldness, the findings and
closure-packet contracts, write locations, the verdict record) and exactly one brief from
`agents/critic/surface/`. The file shapes live in that slice and the CLI in `scripts/README.md`
under the heading "Surface review reduce (`surface-review-reduce.py`)"; this file does not
restate them.

6. **The Challenger** (Surface lens, **strong**) — one fresh-context Challenger per lens in the round's set, every lens in the set spawned in ONE message → `surface-review/r<N>/lens-s<k>.json`

   - **Stage `r<N>/diff-context.md`** (round 1's was staged at step 3 for the fork). The
     Conductor computes the four binding values once, with the committed-range invocation, where
     `$R` is the absolute run worktree path:
     ```sh
     base_sha=$(git -C "$R" rev-parse "$(jq -r .git.base_sha "$RUN_DIR/state.json")")
     target_ref=$(git -C "$R" rev-parse HEAD)   # the round head, after the round's fix commit
     diff_sha=$(git -C "$R" diff "$base_sha" "$target_ref" | shasum -a 256 | awk '{print $1}')
     base_ref="$base_sha"
     ```
     The file opens with this fixed `key: value` header, one key per line and in this order, ended
     by one blank line; then comes the lens question (step 5's one-surface question, **"what
     here corrupts, leaks, or miscounts WITHOUT announcing it?"**; the interaction reviewer takes
     its questions from its brief), then the diff:
     ```
     round: <N>
     base_ref: <base_sha>
     base_sha: <base_sha>
     target_ref: <round head, full SHA>
     diff_sha: <64 lowercase hex>
     worktree: <absolute $R>
     fired: S<a>,S<b>
     ```
     Shell variables do not survive between the Conductor's calls, so every later step reads these
     values back from this header (step 7 shows how) instead of reusing them. Every round reviews
     the full diff from the run base, not the fix delta. Reviewers copy the values; they never
     recompute them.
   - **The round's set.** Round 1: the two fired lenses. Round N >= 2: the prior
     `final.json#rerun_lenses`, plus any fired surface step 9's fix-delta scan fired, plus the
     lens a prior-round partner note logged `rerun` names. In a readiness-only fix round (every
     open blocker an `R` finding) the set is empty and this step spawns nothing unless the
     fix-delta scan or a `rerun` partner note adds a lens.
   - **Spawn primitive.** The host spawn in `agents/orchestrator.md § How to spawn an agent`: on
     Claude the Agent tool, a fresh spawn (never a fork), with `model` passed explicitly. Rounds 1
     and 2 use the string at `RUN_DIR/model-routing.json .roles.challenger.model`. Round 3 and any
     later round follow the second fix loop, which is `second_critic_loop` in
     `.roles.challenger.escalateWhen`: those reviewers spawn on `.tiers.escalated.model`, the
     `escalated` tier `docs/model-routing-and-cast.md` § Escalation ladder names for that
     trigger, and the Conductor appends one hand-written `MODEL-OVERRIDE:` line per such spawn
     (format in `docs/run-accounting.md` § MODEL-OVERRIDE, `configured` the challenger model,
     `actual` the escalated one, `reason` naming `second_critic_loop`). The prompt opens `You are running as The
     Challenger`, carries the `Attempt ID:` line and the run's nonce line as every specialist spawn
     does, then `Role mode: surface-lens S<k>`. It names the slice, exactly one brief,
     `r<N>/diff-context.md`, and for N >= 2 only the closure packet `final` wrote for this
     reviewer (`r<N-1>/closure-s<k>.json`; a lens the fix-delta scan or a partner note added has
     none). This is NOT
     the step-5 recipe: `scripts/run-cold-reviewer.sh` and `claude -p --tools "Read"` cannot
     write, and each reviewer writes its own findings file, `.md` and verdict record. A reviewer
     may read tracked worktree files read-only and never edits the worktree (step 7 checks).
   - **Accounting.** Role `challenger`, attempt id `challenger-lens-s<k>-r<N>`. Two `SPAWN-EVENT`
     lines per spawn, each composed with `scripts/emit-event.sh spawn-event` and appended by the
     Conductor only: a `started` line for every lens in the round's set before the one spawn
     message (two in round 1; one, two or none in a later round), then one terminal line each, `complete` (returned, findings file exists), `no-handoff` (returned without one, a
     coldness flag included) or `failed` (the spawn errored). A re-spawn takes the suffix `-2`
     (`challenger-lens-s<k>-r<N>-2`), `attempt: 2`, and its own `started` line before dispatch. No
     `rework` key.
   - **`log.md`.** The Conductor is its only writer: after each reviewer returns it appends one
     summary line for that reviewer. Reviewers write their own `.md` in the round dir.

7. **The Conductor** (Reduce) — run `scripts/surface-review-reduce.py lenses` → `surface-review/r<N>/merged.json`

   First read the round's values back from the `diff-context.md` header (the lines before its
   first blank line), in the same call as the commands that use them:
   ```sh
   CTX="$RUN_DIR/surface-review/r<N>/diff-context.md"
   R=$(sed -n '1,/^$/s/^worktree: //p' "$CTX")
   target_ref=$(sed -n '1,/^$/s/^target_ref: //p' "$CTX")
   diff_sha=$(sed -n '1,/^$/s/^diff_sha: //p' "$CTX")
   ```
   `$attempt_id` is a reviewer's attempt id exactly as its `started` SPAWN-EVENT logged it
   (`challenger-lens-s<k>-r<N>`, or `challenger-lens-s<k>-r<N>-2` after a re-spawn).

   Then, in this order, once every lens in the round's set has returned. In a readiness-only fix
   round with no added lens there are no lens files, so a has nothing to gate, but b still runs,
   and c uses `--lenses none`.

   a. **Verdict gate.** For each lens attempt of the round,
      `bash scripts/verdict-gate.sh "$RUN_DIR" "$attempt_id"`, the required pre-adjudication gate
      (the bold label **Pre-adjudication gate** in `docs/conductor-gates.md`). A DEFECT is never
      adjudicated. Then check the findings file belongs to that attempt:
      `jq -e --arg a "$attempt_id" '.attempt_id == $a' "$RUN_DIR/surface-review/r<N>/lens-s<k>.json" >/dev/null`.
      A non-zero exit (a mismatch, or a file that is missing or not JSON) is treated as a gate
      DEFECT.
   b. **Worktree check.** `git -C "$R" rev-parse HEAD` equals the staged `target_ref`, and
      `git -C "$R" status --porcelain` is empty. The reviewers are write-capable, so this proves
      none of them changed the code it read. If either fails, do not reduce: log the porcelain
      output and raise `[CHECKPOINT]`, because the Conductor cannot tell which state the reviewers
      read.
   c. **Reduce.**
      `scripts/surface-review-reduce.py lenses "$RUN_DIR/surface-review/r<N>" --lenses <set> --diff-sha "$diff_sha"`.
      Round 1 names exactly the two fired lenses (for example `--lenses S1,S4`). `--lenses none`
      is only for a readiness-only fix round (N >= 2, prior `rerun_lenses` empty), where it writes
      an empty `merged.json`. Exit 0 wrote the record; exit 2 (invalid input) and exit 3 (missing
      input) wrote nothing and printed one stderr line, `surface-review-reduce: <where>: <rule>`.
      Never edit a reviewer's file to make it pass.

   **One re-spawn per reviewer per round**, whatever the cause. A gate DEFECT (an `attempt_id`
   mismatch included), or a reduce exit 2 or 3 whose `<where>` is that reviewer's file,
   re-spawns that reviewer once under its `-2` attempt, then a, b and c run again. Before the
   re-spawn the Conductor moves the failed attempt's files (`lens-s<k>.json` and `lens-s<k>.md`,
   or `interaction.json` and `interaction.md`) into `r<N>/attempt-1/`, so the `-2` attempt
   cannot read or reuse them and the reduce never sees them. A coldness flag (the reviewer's `.md` is the single
   `CHALLENGER FLAG:` line) is copied to `log.md` and the prohibited input removed before the
   re-spawn. A second failure for the same reviewer is `[CHECKPOINT]`.

   **Partner notes.** A lens `### Warnings` line that starts `partner <S-id>:` names a risk the
   lens saw on the other fired surface. It is for the Conductor, never handed to another
   reviewer. Here the Conductor only collects the round's partner notes from the lens `.md`
   files; it judges and logs them in step 9, after `final` has run, so the round's `final.json`
   exists when a note escalates. None is silently capped.

8. **The Challenger** (Surface interaction, **strong**) — reads the diff and this round's merged findings; hunts cross-surface failures, then runs the readiness pass → `surface-review/r<N>/interaction.json`

   Runs after step 7's `lenses` stage, alone, and re-runs every `fix` round, because a fix to one
   surface is how a new interaction appears. Same spawn primitive and accounting as step 6, with
   attempt id `challenger-interaction-r<N>` (re-spawn `-2`) and `Role mode: surface-interaction`;
   its brief is `agents/critic/surface/interaction.md`. The spawn names `r<N>/diff-context.md`,
   `r<N>/merged.json`, and for N >= 2 only its own closure packet `r<N-1>/closure-x.json`. The
   first pass hunts failures that exist only where the two fired surfaces meet. The second is the
   readiness pass: step 5's zero-surface questions (correctness, scope, tests, risks, rollback),
   asked on every fan-out run, local or GitHub, with findings marked `surface: "R"`. Every id in
   this file is `X`-prefixed, readiness findings included. On GitHub delivery this pass is the
   run's one cold readiness read.

9. **The Conductor** (Gate) — run `scripts/surface-review-reduce.py final` and route on its route field → `surface-review/r<N>/final.json`

   - **Before `final`:** read `R`, `target_ref` and `diff_sha` back from the `diff-context.md`
     header as step 7 does, run
     `bash scripts/verdict-gate.sh "$RUN_DIR" challenger-interaction-r<N>` (or its `-2` attempt)
     and step 7's `attempt_id` check on `interaction.json`, and repeat step 7's worktree check,
     with step 7's one re-spawn (failed files moved to `r<N>/attempt-1/`) and `[CHECKPOINT]` rules.
   - **Run:** `scripts/surface-review-reduce.py final "$RUN_DIR/surface-review/r<N>" --lenses <set> --diff-sha "$diff_sha" --max-fix-rounds "$(jq -r .max_critic_loops "$RUN_DIR/state.json")"`,
     adding `--overrides "$RUN_DIR/surface-review/r<N>/overrides.json"` when the Conductor has
     overridden a blocker. `--lenses` is the same set as step 7. On route `fix` it writes the
     closure packets for round N+1. A successful `final` removes stale `closure-*.json` in its
     round dir, so the packets on disk always match the latest `final.json`.
   - **Partner notes, after `final`:** the Conductor judges each note step 7 collected on its
     merits, against this round's `final.json`. Its outcome is `covered` when a `final.json`
     finding at that `file:line` lists the named surface in `surfaces` and describes the same
     failure mechanism the note names. Two risks can share a `file:line`, so a finding there
     about a different failure does not cover the note, and when the Conductor cannot say the two
     match, the note is not `covered`. It is `dismissed` when the Conductor can give a reason it
     is not a risk. `covered` cannot happen when the named lens did not run this round, so a note
     that is neither is `rerun` when `final.json#route` is `fix`: the named lens joins round
     N+1's set (as a lens the fix-delta scan adds does, with no closure packet, which the script
     accepts). On any other route (`ship`, `checkpoint` once the cap is reached, or `escalate`)
     it is `escalated`. A note already logged `rerun` is judged again against round N+1's
     `final.json` and cannot be `rerun` a second time: if it is still neither `covered` nor
     `dismissed`, it is `escalated`, whatever that round's route. Before that `covered` match,
     the Conductor maps the note's round-N `file:line` onto round N+1's revision, because the
     fix commit may have moved the code: from `git -C "$R" diff -U0 <r<N> target_ref> <r<N+1>
     target_ref> -- <file>` (both read from the rounds' `diff-context.md` headers), it shifts the
     line by the net lines added or removed in hunks wholly above it. When the line sits inside a
     changed hunk, the file was renamed or deleted, or the diff cannot be read, there is no
     mapping and the note cannot be `covered`. The note's `PARTNER-NOTE` line for round N+1
     records the mapped line, or the original one when there is no mapping. For each note it
     writes one machine line to `log.md`, composed with `jq -cn` and appended through
     `scripts/log-append.sh "$RUN_DIR" "<heading>" -` with the line on stdin, as the
     `SURFACE-GATE:` line is (no new emit-event type). These are the keys, in this order:

     ```
     PARTNER-NOTE: {"round":1,"from":"S1","about":"S4","file":"app/b.py","line":20,"outcome":"covered","reason":"r1-S4-1 at app/b.py:20 is the same double send the note names"}
     ```

     `round` is N; `from` is the lens whose `.md` carries the note; `about` is the note's
     `<S-id>`; `file` and `line` are its `file:line`; `outcome` is `covered`, `dismissed`,
     `rerun` or `escalated`; `reason` is never empty. One `escalated` note sends the run down the
     `escalate` route below, whatever `final.json#route` says, with this round's `final.json`
     open blockers and the note itself as the hand-over.
   - **Route on `final.json#route`:**
     - `ship`: close out as step 5's Close out does. On GitHub delivery, publish the `final.json`
       summary as the review summary.
     - `fix`: send the open blockers to the coder and increment `critic_loops`
       (`docs/conductor-gates.md`); the coder commits. Then run the fix-delta scan, step 3's
       five-surface scan over the fix delta (round-N head to the new head). A surface firing
       outside `fired` means escalate, since the count would be 3. Otherwise go to round N+1:
       step 6 stages a new `diff-context.md` at the new head.
     - `escalate` (a `gate_miss`, a fix-delta surface outside `fired`, checkpoint option A, or,
       Conductor-raised, a partner note logged `escalated` above):
       append a `workflow_shifts` entry to `state.json` (`docs/run-protocol.md`; any role may
       shift to a heavier cadence), write a `SURFACE-GATE:` line with `at_round` N, `route`
       `escalate` and `escalated_to`, and hand the open blockers in the last `final.json` to the
       escalated pipeline's coder as known defects to fix. They are build input there, never
       reviewer input.
     - `checkpoint`: raise exactly this block.
       ```
       [CHECKPOINT] — Human input needed
       Phase: build-review-cold step 9 (surface fan-out), round r<N>
       Issue: <B> blocker(s) survive <M> fix rounds (max_critic_loops). Fired: S<a>, S<b>.
         Record: RUN_DIR/surface-review/r<N>/final.json
         - <id> <file>:<line> [<surfaces>] <one-line scenario>
       Options:
         A) Escalate to execute-plan (feature if a blocker needs design); the worktree and diff carry over
         B) Accept the named risk: the Conductor writes one override per blocker and closes out
         C) Allow one more fix round (raises max_critic_loops for this run only)
       Awaiting your response before continuing.
       ```
       On A, escalate as above. On B the Conductor writes one override per blocker into
       `overrides.json` and re-runs `final`, which then routes `ship`. On C it raises
       `state.json#max_critic_loops` by one and re-runs `final` on the same round dir with the
       raised `--max-fix-rounds` before round N+1; that rewrites `final.json` to `fix` and writes
       the closure packets.
   - A blocker whose fix needs a design or requirements decision escalates instead of looping.
     The Conductor may override a blocker only with a logged reason written to `overrides.json`
     (`{"overrides":[{"id","reason"}]}`), then re-runs `final`.

> **Production boundary — hard stop (non-negotiable).** This workflow's finish line is the change
> **built, verified, and green on the dev/integration branch**. The Conductor does NOT deploy beyond
> dev, merge toward a release/prod branch, or ship to the public as part of this workflow. Same hard
> stop `workflows/execute-plan/build-tail.md` carries in full — see its "Production boundary — hard
> stop" block; not re-documented here at length. When dev is green, raise the
> `[DEV-VERIFIED CHECKPOINT]` and stop. Production is the human's call.

> **External-action boundary — separate gate (applies regardless of stage).** If the change fires
> any action in the external-action taxonomy (sent emails/SMS, chat posts, webhook calls,
> notifications, payment triggers, calendar invites, DNS/infra mutations, other side-effecting
> outbound HTTP), the builder must surface it and raise an `[EXTERNAL-ACTION CHECKPOINT]` before it
> fires — even at dev stage, and even if the self-gate would otherwise ship without a cold review.
> See `docs/external-action-boundary.md`. This gate and the production gate are separate
> protections; neither subsumes the other. (Note: firing an S4 irreversible external action fires
> BOTH the self-gate cold review AND this checkpoint.)

The full agent specs, verdict format, worktree mechanics, and checkpoint formats live in
`agents/orchestrator.md` and the per-agent files in `agents/`. This file just names the sequence; it
doesn't duplicate them.
