# Workflow: write-short-script

**Objective:** a narrated short's script (`vo/script.json`) that a viewer who never read the source
article understands on one watch: what the thing was for, what went wrong, why, and what to do
about it in their own work.

**When to use:** Robin wants the narration for a devweb short (the vertical explainer series on
the devweb YouTube channel) written from a devweb article, or a short's script was judged too
abstract and needs a rewrite. Triggers: "write the script for episode N", "run the script through
the bureau", a short whose draft Robin couldn't follow.

**When NOT to use:** a long-form article (→ `write-article`); short user-facing copy that is not
narration (→ `message-framing` / `copy-review`); building the video itself (picture, VO recording,
render), which stays in the short's own build session after Robin approves the script.

**Type:** plan — it produces a script for Robin's approval. Nothing irreversible runs: no paid VO,
no upload, no publish. Run as **direct Conductor** (a planning run with one terminal human gate,
per `CLAUDE.md § Default entrypoint`).

**Inputs** (the Conductor writes them to `RUN_DIR/brief.md` before step 1):
- The source article path (devweb `content/articles/<slug>.mdx`) and the candidate's line from
  `~/Code/novadiem/assistant/ideas/devweb-shorts/candidates-devweb.md` (hook, receipt, visual).
- The lesson the viewer should leave with, in one sentence.
- **Length: as long as the message needs to be coherent, up to the platform limit** (YouTube
  Shorts and Instagram Reels both allow up to 3 minutes). There is no house window (Robin,
  2026-10-31: "i want to go by what the platform allows and how much we need to actually convey a
  coherent message"). Shorter is better only when nothing the viewer needs is cut. Seconds =
  words ÷ 2.85 (the series narrator, Chris on eleven_v4, measured 2.87 words/s on episode 4).
- Series rules from `~/Code/novadiem/assistant/ideas/devweb-shorts/README.md`: no product names,
  every fact traced to the article, hook in the first 3 s, no URL on screen and nothing beyond
  plain `devweb.org` in the description.
- When rewriting: the earlier scripts and Robin's notes on them, verbatim. These go to the
  Counselor and the Scribe only, never to the cold reader.
- Out of scope: picture design beyond one plain line per beat, VO recording, rendering, upload.

**Outputs:**
- `RUN_DIR/brief.md` — the inputs above.
- `RUN_DIR/angle.md` — the viewer, the moment they hit this, the one rule, the plain words.
- `RUN_DIR/versions/NN-<stage>.md` — immutable, numbered script versions (never overwrite).
  Each version holds the beats (`I`, `II`, …), the narration per beat, one `Picture:` line per
  beat, the word count and the estimated seconds.
- `RUN_DIR/coldread/NN.md` — one file per cold read: the reader's explain-back, every word or
  step it could not follow, and a verdict `CLEAR` | `HOLD`.
- `RUN_DIR/facts.md` — every claim in the final script traced to a quoted line of the article,
  marked as general advice, or flagged.
- `RUN_DIR/script.json` — the final script in the kit's shape:
  `{"lines": [["I", "..."], ...], "facts": "..."}` (`tools/devweb-kit/vo/vo.py` reads `lines`).
- `RUN_DIR/log.md`, `RUN_DIR/state.json`.

**Leans on skills:** `humanizer` and `spiral-dynamics` (The Counselor, steps 1 and 7). The house
voice rules in `~/.claude/CLAUDE.md` (The Scribe).

**Reuses workflows:** the Counselor's frame and review modes from `message-framing` and
`copy-review`, inline (spawned, not nested), as `write-article` does.

## Done criteria

- The latest cold read (a fresh spawn that saw only the script) is `CLEAR`: its explain-back
  states correctly what the thing was for, what broke, why, and what the viewer should do, and it
  lists no word or step it could not follow.
- `RUN_DIR/facts.md` traces every claim; nothing is flagged.
- The final script is within the platform limit and follows the series rules.
- Robin has the script and storyboard in front of him at the gate (step 9). His OK is what lets
  the build session record the VO; this workflow ends at the gate.

## Edge cases

- **The cold reader never clears.** After three rounds (steps 3–6) still `HOLD`: stop and give
  Robin the last script, the open items, and a one-line view on whether the topic is too dense to
  land (a narrower point, or a different topic). Do not loop further.
- **Clarity needs more time.** Add it. Length is set by what the message needs, up to the platform
  limit; never cut a step the viewer needs to make a target length.
- **A clearer line needs a fact the article doesn't have.** It stays out, or it is phrased as
  advice to the viewer (a general rule), never as a claim about the article's incident.
- **The source incident is internal tooling.** Name it by what it does in plain words ("a script
  that logs what each AI job cost"), never by its internal name.

## Fallback behavior

- A spawn errors or returns no handoff: log it per `docs/conventions/failure-signatures.md` and
  re-spawn once; then `[CHECKPOINT]` to Robin. Never auto-retry silently.
- Every version is kept, so a bad revise never loses the previous script.

## Observability

`RUN_DIR/log.md` records each spawn, each cold-read verdict and its open items, the revise
decisions, the fact-trace result and the gate. A human inspects the run through `versions/`,
`coldread/`, `facts.md` and `log.md`.

## Steps

Spawn per `agents/orchestrator.md § How to spawn an agent`, explicit model from
`RUN_DIR/model-routing.json`. Sequential.

1. **The Counselor** (Voice, **frontier**, mode: frame) — the viewer and the angle → `angle.md`
   Reads `brief.md` (with any earlier scripts and Robin's notes). Names the viewer (someone
   building software with AI tools who has not read the article), the moment in their own work
   when this bites them, the one rule they leave with, and every concept the script must teach,
   each with its plainest phrasing (what the machine is for, what a test checks, and so on).
   Proposes the hook (a failure or surprise in the first 3 s).

2. **The Scribe** (Draft, **strong**) — the script → `versions/01-draft.md`
   Reads `brief.md`, `angle.md` and the source article. Writes the beats: hook, the viewer's
   situation, what the thing was for, what broke and why, the proof from the article, what to do.
   One `Picture:` line per beat (what the viewer sees, so the picture carries what words can't).
   No term the angle didn't teach; no product names. Word count and seconds at the end.

3. **The Conductor** — copy only the narration and the `Picture:` lines of the latest version into
   `RUN_DIR/coldread/input-NN.md` (no title, no notes, no article, no angle).

4. **The Challenger** (Cold read, **standard**) → `coldread/NN.md`
   A FRESH spawn every round, mode slice `agents/critic/short-script.md § cold-read`. Reads only
   `coldread/input-NN.md`. Explains back what it understood and lists what it could not follow.

5. **Gate** — the Conductor reads the verdict. `CLEAR`: go to step 7. `HOLD`: go to step 6. After
   the third `HOLD`, stop per Edge cases.

6. **The Scribe** (Revise, **strong**) — fix what the reader missed → `versions/NN-revise.md`
   Reads the latest version, the latest `coldread/NN.md`, `angle.md` and the article. Fixes every
   open item: plain words, a missing step, a picture line that should carry the idea. Then back to
   step 3 for a new cold read.

7. **The Counselor** (Voice, **frontier**, mode: review) — humanizer and spoken rhythm → `versions/NN-humanize.md`
   Reads the latest version. Scrubs AI tells, makes it sound said aloud by one person, keeps every
   plain-word fix the cold reads earned. If it changes a sentence's meaning, the Conductor runs one
   more cold read (step 3).

8. **The Challenger** (Fact trace, **standard**) → `facts.md`
   Mode slice `agents/critic/short-script.md § fact-trace`. Reads the final version and the
   article. Every claim gets a quoted article line, or is marked general advice, or is flagged. A
   flag goes back to step 6.

9. **Gate** — the Conductor writes `script.json` from the final version (lines + a `facts` string
   built from `facts.md`) and shows Robin the script as a fenced block with the one-line picture
   per beat, the word count and the estimated length. `[CHECKPOINT]`. On his OK the build session
   copies `script.json` into the short's `vo/` and records; on notes, re-enter at step 6 with his
   notes added to `brief.md`.
