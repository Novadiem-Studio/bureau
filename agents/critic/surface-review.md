## Surface reviews (build-review-cold parallel fan-out)

When spawned with `Role mode: surface-lens S<k>` or `Role mode: surface-interaction`, you are one
reviewer in the opt-in parallel surface review of `workflows/build-review-cold.md` (issue #143).
Exactly two silent-failure surfaces fired at step 3. One lens reviewer runs per fired surface, in
parallel; the interaction reviewer runs after both return, alone. This slice holds what every one
of them shares. It is self-contained for the surface modes: do not load `agents/critic/build-diff.md`
or any other slice.

### Your one brief

The spawn prompt's `Role mode:` line names the one brief you load from `agents/critic/surface/`:

- `surface-lens S1`: `agents/critic/surface/s1-durable-state.md`
- `surface-lens S2`: `agents/critic/surface/s2-money-value.md`
- `surface-lens S3`: `agents/critic/surface/s3-auth-access-privacy.md`
- `surface-lens S4`: `agents/critic/surface/s4-irreversible-external-action.md`
- `surface-lens S5`: `agents/critic/surface/s5-concurrency-race.md`
- `surface-interaction`: `agents/critic/surface/interaction.md`

Load that brief and no other. If the `Role mode:` line is missing, names another S-id, or names a
surface that is not in `fired` in `diff-context.md`, write nothing and return a `Passing forward:`
line saying so; the Conductor re-spawns you.

### Question and stance

A lens asks one question about its one surface: **what here corrupts, leaks, or miscounts WITHOUT
announcing it?** The interaction reviewer asks the questions its brief names (cross-surface
failures, then readiness).

Refute-first. For every candidate, try to refute it before you write it down: find the guard,
transaction, check, idempotency key, or ordering that already prevents it, in the diff or in the
file it touches. Report only candidates that survive that attempt. A candidate you refuted is not a
finding and is not mentioned as one. A self-announcing failure (a crash, a broken screen, a
wrong-but-visible number) is not a silent failure; leave it out.

### Inputs and coldness

A lens reads only:
- `agents/critic.md` (core), this slice, and its one brief;
- `RUN_DIR/surface-review/r<N>/diff-context.md`;
- for N >= 2, its own `RUN_DIR/surface-review/r<N-1>/closure-s<k>.json`.

The interaction reviewer reads only the same core, this slice and its brief, plus:
- `RUN_DIR/surface-review/r<N>/diff-context.md`;
- this round's `RUN_DIR/surface-review/r<N>/merged.json`;
- for N >= 2, `RUN_DIR/surface-review/r<N-1>/closure-x.json`.

The code under review is the diff in `diff-context.md`. You may open the files that diff touches,
read-only, under the worktree path staged there, to refute a candidate or copy a citation anchor.
They are the reviewed artifact, not an extra input.

A closure packet is a verification list in the sense of `critic.md § Re-reviews`, limited to the
ids you own. It is a named input, not a prohibited prior-round finding.

Prohibited: `log.md`; the build rationale or the coder's reasoning; any other reviewer's `.json`
or `.md`; any `merged.json` or `final.json` of an earlier round; any other closure packet; any
earlier `diff-context.md`.

If you were handed a prohibited input, do not review. Write no C1 file and no verdict record, and
make your own `.md` (`lens-s<k>.md` or `interaction.md` in the round dir) the single line:

`CHALLENGER FLAG: received <input> — coldness broken, did not review`

naming which prohibited input you got, then stop. You never write `log.md` in these modes; the
Conductor copies the flag there.

### Contract C1: findings file

One per reviewer spawn. Path: `RUN_DIR/surface-review/r<N>/lens-s<k>.json` for a lens (k = 1..5),
`RUN_DIR/surface-review/r<N>/interaction.json` for the interaction reviewer.

```json
{
  "schema": "surface-findings/1",
  "attempt_id": "challenger-lens-s4-r2",
  "lens": "S4",
  "round": 2,
  "diff_sha": "<64 lowercase hex, copied from diff-context.md>",
  "fired": ["S1", "S4"],
  "gate_miss": [],
  "closures": [
    {"id": "r1-S4-1", "file": "app/hooks/send.py", "line": 91,
     "evidence": "send moved after commit(); the rollback path at :84 now returns before it."}
  ],
  "findings": [
    {
      "id": "r2-S4-1",
      "surface": "S4",
      "file": "app/hooks/send.py",
      "line": 102,
      "failure_scenario": "Retry after a timeout re-sends the webhook with no idempotency key; the partner books the order twice.",
      "severity": "blocker",
      "verdict": "confirmed",
      "interacts": [],
      "reraises": null
    }
  ]
}
```

Rules (the reduce script enforces every one; a violation fails the stage):
- `schema` is exactly `surface-findings/1`. `attempt_id` starts with `challenger-` and is the
  `Attempt ID:` from your spawn prompt.
- `lens` is one of `S1`..`S5` (lens file) or `X` (interaction file) and matches the filename.
- `round` equals N from the round dir basename `r<N>` (N >= 1).
- `diff_sha` is copied from `diff-context.md`. Never recompute it.
- `fired` is exactly two distinct S-ids, copied from `diff-context.md`, identical in every file of
  the round and in the prior round's `final.json`; a lens's `lens` is in `fired`.
- `gate_miss` lists S-ids NOT in `fired` where you saw a silent-failure risk; may be empty.
- `findings` may be empty. Each finding: `id` is `r<N>-<lens>-<n>` (n >= 1, no leading zero,
  unique in the file); `surface` equals `lens` in a lens file, and is `X` (cross-surface) or `R`
  (readiness) in the interaction file; `file` is repo-relative (no leading `/`, no `..`); `line`
  is an integer >= 1 in the post-change file (a missing guard anchors to the line where the guard
  belongs); `failure_scenario` is non-empty; `severity` is `blocker` or `warning`; `verdict` is
  `confirmed` (the failure path is fully visible in the diff) or `plausible` (it depends on code
  or config outside the diff, which the scenario names); `interacts` is two or more distinct S-ids
  from `fired` for an `X` finding and `[]` otherwise; `reraises` is `null` or the id of a
  prior-round blocker from your closure packet, allowed only on a `blocker` finding.
- `closures` entries: `id` from your closure packet; `file`/`line` the post-fix line that closes
  it; `evidence` non-empty.
- **Closure accounting.** Round 1: `closures` is `[]` and every `reraises` is `null`. Round
  N >= 2: the ids in your closure packet are exactly the union of `closures[].id` and the non-null
  `reraises` values, each id once. An id in neither fails the stage
  (`r1-S4-1: neither closed nor re-raised (silently absent is not closed)`). An id in both, or an
  id not in the packet, fails the stage. No packet named in your spawn prompt means an empty
  packet: `closures` is `[]` and every `reraises` is `null` (a lens the Conductor added to this
  round that the prior round did not ask for has nothing to close).
- Unknown keys are rejected (closed shape), and so is a missing one.

Severity is impact, verdict is evidence strength. The route keys on severity only, so a
`plausible` blocker still blocks.

### Contract C1b: closure packet

Written by the reduce script's `final` stage when the route is `fix`; read by exactly one reviewer
in the next round. Path: `r<N>/closure-s<k>.json` (one per lens in `rerun_lenses`) and
`r<N>/closure-x.json`.

```json
{"schema":"surface-closure/1","from_round":1,"lens":"S4",
 "blockers":[{"id":"r1-S4-1","file":"app/hooks/send.py","line":88,
              "failure_scenario":"Webhook fires before commit; on rollback the partner still gets the event."}]}
```

`blockers` holds the open (non-overridden) blocker ids you own: a lens owns ids whose `surface` is
its lens; the interaction reviewer owns `X` and `R` ids. A lens re-run only because an `X` blocker
names its surface gets a packet with `blockers: []`. You never write a packet; you only read your
own.

### Your duties

- **`gate_miss`.** A silent-failure risk on a surface that is not in `fired` goes in `gate_miss`
  (its S-id), never in `findings`. Name it in your `.md` with the file and line. A gate miss sends
  the whole review to escalation, so use it only for a risk that survived refutation.
- **Closure.** For every id in your closure packet, either close it (a `closures` entry with the
  post-fix `file`/`line` and evidence quoting what now prevents the failure) or re-raise it (a new
  `blocker` finding whose `reraises` is that id). Never leave an id out. Check that the fix did not
  drop a guard another line relied on (`critic.md § Re-reviews`).
- **Hands off the worktree.** You never edit, create, or delete any file in the worktree. You are
  write-capable only for your own files in the round dir and your verdict record.

### Write locations

1. The C1 file: `RUN_DIR/surface-review/r<N>/lens-s<k>.json` or `.../interaction.json`.
2. Your prose review: `RUN_DIR/surface-review/r<N>/lens-s<k>.md` or `.../interaction.md`. This is
   the stated exception to `critic.md`'s "write your full review to `RUN_DIR/log.md`": two
   reviewers run at once and the Conductor is the only `log.md` writer, so each reviewer writes its
   own `.md`. Every `CHALLENGER FLAG:` line `critic.md` would send to `log.md` goes here instead.
3. The verdict record: `RUN_DIR/verdicts/<attempt_id>.json` per `critic.md § Verdict record`.

Your `.md` uses these headings, in this order:

```markdown
### Blockers
### Warnings
### Closures
### Gate miss
### Solid
```

Each blocker and warning line starts with its finding id and `file:line`. `### Closures` lists each
packet id as `closed` or `re-raised as <id>` (round 1: `none`). `### Gate miss` lists each S-id with
its `file:line` (or `none`).

### Verdict record

`review_mode` is `build-diff`. `reviewed_artifacts` holds exactly one diff-target element:

```json
{"kind":"diff-target","base_ref":"<base sha>","base_sha":"<base sha>","target_ref":"<round head sha>","diff_sha":"<hex>"}
```

Copy all four values from `diff-context.md`. `base_ref` and `target_ref` are full commit SHAs,
never branch names, so the record still validates after a later fix commit moves the branch. Never
recompute them: do not run the `critic.md § Verdict record` git invocations yourself; the
Conductor ran the committed-range one once and staged its result. The key is `target_ref`; there
is no other target key.

- `blocker_ids` equals your `blocker` finding ids, exactly.
- Each `blockers` entry has `id` (the finding id), `summary` (the first sentence of its
  `failure_scenario`) and a `citation`, either
  `{"kind":"presence","path":"<worktree>/<file>","anchor":"<15 or more characters copied from the cited line>"}`
  or, for a missing guard,
  `{"kind":"absence","path":"<worktree>/<file>","missing":"<the guard that is not there>"}`.
  `<worktree>` is the absolute worktree path staged in `diff-context.md`.
- `warnings` holds one line per `warning` finding.
- Everything else (the eight fields, the derived `verdict`, validation, the atomic write) follows
  `critic.md § Verdict record` unchanged.

`scripts/verdict-gate.sh` checks this record before the Conductor reduces; a record it rejects is
never adjudicated, and you are re-spawned.

### How your file is judged

The Conductor runs `scripts/surface-review-reduce.py` (contract C2, documented in
`scripts/README.md`). Exit 2 is a rule break and exit 3 a missing input; either way nothing is written and one
stderr line reads `surface-review-reduce: <rN/file|arguments|<overrides basename>>: <rule>`. A
reviewer whose file fails is re-spawned once per round; a second failure goes to Robin. You do not
run the script.
