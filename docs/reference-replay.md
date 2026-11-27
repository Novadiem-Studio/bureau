# Reference replay: scoring the Challenger against known answers

The Challenger and the cold reviewer are LLM judges. Until #161 nothing measured whether they were
right: the eval ledger counted what a gate caught, and a miss showed up only when a later reviewer
or a person happened to find a defect in an approved diff. `scripts/reference-replay.sh` turns those
past reviews into a fixed test set. It replays a fresh Challenger on the exact diff an earlier one
saw and checks the verdict against what we now know about that diff.

## What a case is

One past build-diff review whose outcome is known:

| kind | meaning | a trial passes when |
|------|---------|---------------------|
| `known-miss` | the Challenger approved, and a later gate or person found a defect | every expected finding is in a blocker or warning |
| `known-catch` | the Challenger blocked a real defect | every expected finding is in a blocker or warning |
| `control` | no gate, review or later use has faulted the diff | the verdict is not `BLOCKED` |

Controls are what keep the numbers honest: a Challenger that blocks everything finds every miss.
A BLOCKED control is not automatically wrong (it may be a real defect nobody noticed), so its
blockers are listed for a hand read.

Real cases point at private repos, so they live in a private repo, not here. This repo ships the
runner, this format and synthetic fixtures (`.bureau/regression/364` to `366`).

## Case file

```json
{
  "id": "toy-build-1",
  "kind": "known-miss",
  "review_mode": "build-diff",
  "held_out": true,
  "target_repo": "/absolute/path/to/repo",
  "base_sha": "<40-hex>",
  "target_sha": "<40-hex>",
  "diff_sha": "<sha256 of `git diff base target`, from the verdict record>",
  "prompt_paths": ["docs/plans/x/01-prompt.md"],
  "extra_files": [{"from": "/abs/path", "to": "notes/x.md", "sha256": "<64-hex>"}],
  "leak_patterns": ["a string that exists only in the later fix"],
  "expected": [
    {"id": "e1", "anchor": "API_URL", "pattern": "https|cleartext", "summary": "what the defect is"}
  ],
  "source": {"run_dir": "...", "verdict": "verdicts/challenger-3.json", "original_model": "opus",
             "original_verdict": "APPROVED_WITH_WARNINGS", "found_by": "who found it, where"},
  "packet_gap": "what the original reviewer had that the replay does not",
  "notes": "free text"
}
```

- `diff_sha` comes from the original verdict's `reviewed_artifacts` diff-target entry. Build
  refuses (exit 3) when the regenerated diff does not hash to it, so a case can only replay the
  exact bytes that were reviewed. Never use a `build-NN.diff` from the run dir: those can be
  rewritten after a fix lands.
- `prompt_paths` are repo-relative files in the tree at `target_sha`. A prompt folder that only
  ever lived in the run dir, or was back-filled into the repo later, can't be verified. Leave it
  out and say so in `packet_gap`.
- `extra_files` are pinned by sha256 and refused (exit 5) if they changed. Use them only for a
  file you can show predates the review.
- `leak_patterns` are strings that appear only in the fix. Build refuses (exit 4) if any is in
  the packet, including the reviewed diff. A refusal usually means the string was not fix-only.
- `expected[].anchor` is a case-insensitive substring and `pattern` a case-insensitive regex.
  Both must match inside one blocker or warning. Anchor on something any correct finding must
  name (the variable, the function), and keep the pattern loose: it decides whether the defect
  was seen, not how it was phrased.
- `held_out: false` marks a case a persona or checklist edit has already been taught from. Report
  held-out and taught cases separately, or an edit is graded on its own training data.

## The packet

`build` writes a packet the reviewer cannot see past:

- `tree/`: `git archive` of `target_sha`, so there is no `.git`, no later commit, and no run dir.
- `review.diff`: the regenerated diff.
- `extra/`: the pinned extra files.
- `persona/`: the current `agents/critic.md` and `agents/critic/build-diff.md`. Their hashes are
  recorded in `packet.json`, so a trial is tied to the persona it ran on.
- `BRIEF.md`: a fixed task prompt.

Nothing comes from `log.md`, `verdicts/`, `checkpoints/` or `coderabbit/`, which all hold the
answer.

## A trial

`run` builds a fresh packet per trial and spawns `claude -p` in it with `--tools Read,Grep,Glob`,
`--add-dir <packet>`, `--setting-sources ""`, `--no-session-persistence`, the Challenger verdict
schema as `--json-schema`, and `stream-json` output. The model defaults to the Challenger's tier in
`config/model-policy.v2.json` resolved through `config/runtimes/claude.json`; `--model` overrides
it.

After the spawn, `audit` reads every tool call in `events.jsonl`. Any path outside the packet, or
any tool other than Read, Grep and Glob, marks the trial `contaminated`, and it is not scored.
Otherwise the verdict is scored and the exported tree is deleted (it is reproducible from git).
Each trial directory keeps `BRIEF.md`, the diff, the persona, `events.jsonl`, `verdict.json`,
`score.json`, `audit.json` and `trial.json` (model, status, token usage, turns).

```bash
scripts/reference-replay.sh run cases/x.json results/2026-11-27 --trials 3
scripts/reference-replay.sh summary results/2026-11-27
```

`summary` prints raw counts per case, like `2/3 found, 1/3 as blocker`, plus contaminated and
failed trials and the tokens spent. No rates, no averages across cases: the set is small and the
cases are not alike.

## What this measures, and what it doesn't

It measures the persona plus the model on a fixed packet. Use it to compare a persona edit, a
model tier or a host against the same cases.

It does not measure:

- **The Conductor's packet-building.** The real Challenger got whatever the Conductor chose to hand
  it. The replay gets a fixed brief, the tree, the diff and the listed prompts.
- **Anything that needs a live run.** The replay can't run tests or the app. Pick cases whose
  defect is visible by reading code. A miss that only a test run could show is the live gate
  working, not a reviewer failure.
- **Spec-plan or prompts reviews.** Their spec and plan are usually overwritten in place in the
  run dir, so the round-1 version is gone. Build-diff only, for now.

Trials are not deterministic. Run each case at least three times before reading anything into it,
and get Robin's go on token spend before a full pass.
