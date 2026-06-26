# Workflow: write-article

**When to use:** Robin wants to write a long-form article for **devweb.org** and run it
through the full pipeline — outline → draft → higher-level improvement → a configurable chain
of cross-model improvement passes (Grok et al., editable per run) → two humanizer passes →
published MDX staged into devweb. Point it at a topic.

**When NOT to use:** a quick edit to an already-published article (edit the `.mdx` directly);
content that isn't a long-form article — a blog post, a tweet, a release note, an email
(wrong shape; use `copy-review`/`message-framing` for short user-facing copy); or when the
cross-model stage should be skipped entirely (the spend isn't worth it for the piece — just
run The Scribe + The Counselor directly, no workflow).

**Type:** mixed — it spawns drafting agents (The Scribe, The Counselor) AND runs a dispatch
script (`scripts/model-pass.sh`) plus a cross-repo publish into devweb. It borrows
`operational-build.md`'s machinery (a runbook with action steps behind a gate), but note
`operational-build` is `Type: execute`; write-article is a machinery cousin, not the same type.

**Inputs:**
- A topic description — Robin provides it inline in the spawn or as a file path.
- Optionally a per-run `RUN_DIR/article-passes.json`. If present, it **replaces**
  `config/article-passes.json` entirely for this run (not a merge — predictable and explicit).
- `RUN_DIR` is set by the Conductor per `docs/run-protocol.md`.
- The OpenRouter key in the keystore (`~/Documents/novadiem/keys/novadiem/openrouter.env`,
  provisioned by the chunk-02 build step), consumed by `scripts/model-pass.sh`. The script
  loud-fails (exit 4) if absent.
- Out of scope: any live-web fact-check (figure-grounding is tool-free, against the draft's own
  cited sources); GPT/Gemini *direct* provider arms (v1 reaches them only via `openrouter:`).
- In scope (standing-authorized): the workflow publishes live — it commits and pushes to `main`
  (production deploy to https://devweb.org) automatically once the proofreader clears and the build
  is green. See the Automation policy below. The dev→prod boundary is crossed under Robin's recorded
  standing authorization, gated by the proofreader, not left as a manual release step.

**Outputs:**
- `RUN_DIR/angle.md` — the angle, working title, proposed pillar.
- `RUN_DIR/versions/NN-<stage>.md` — **the versioned article line. Every stage writes a NEW
  immutable, zero-padded file; no stage ever overwrites another.** `NN` is creation order
  (`00`, `01`, …); the stage name disambiguates. The "current draft" at any point is the
  highest-numbered `versions/` file. This is what makes the run auditable end to end — diff any
  two stages forever. Typical sequence: `00-outline.md`, `01-draft.md`, `02-revise.md`,
  `03-grounding.md` (only if the figure gate triggers), `04-reconcile.md`, `05-humanize-1.md`,
  `06-humanize-2.md`, `07-article.mdx`.
- `RUN_DIR/figure-check.md` — per-claim grounding record (only if the figure gate triggers).
- `RUN_DIR/passes/NN-<id>.md` — one durable candidate per cleared cross-model pass (the
  cross-model perspectives; kept in their own dir because the resume-skip predicate keys on them).
- `RUN_DIR/manifest.md` — auto-written at close-out: one row per `versions/` stage (file, word
  count, one-line "what changed"). The audit index.
- `RUN_DIR/proofread.md` — the step-13 proofreader verdict (`CLEAR` | `HOLD`) + any concerns.
- `RUN_DIR/article.mdx` — a copy of the final `versions/NN-article.mdx`, for the publish step.
- Cross-repo: `devweb/content/articles/<slug>.mdx` — written + committed + pushed live in step 14,
  automatically when the step-13 proofreader returns `CLEAR` and the build is green.
- `RUN_DIR/log.md`, `RUN_DIR/state.json` — run narrative and close-out (step 15).

**Leans on skills:** `humanizer` and `spiral-dynamics` — both loaded by The Counselor in its
frame mode (step 1) and review mode (steps 10–11). The Scribe loads the lite house-voice rules
from `~/.claude/CLAUDE.md` for drafting.

**Reuses workflows:** `message-framing` (step 1 — The Counselor's **frame** mode) and
`copy-review` (steps 10–11 — The Counselor's **review** mode). These are reused **inline**: the
Conductor spawns The Counselor in the named mode and that mode IS the mechanism. There is no
workflow-nesting primitive in the Bureau — steps 1, 10, and 11 do NOT nest the other workflows
as sub-workflows; they reuse the same Counselor mode the other workflow runs.

**Automation policy — RESOLVED standing authorizations (Robin, 2026-06-24).** "Write an article"
runs to completion **autonomously and ships live** — it is automation, not a relay of approval
gates. The only thing that halts a run is a *real problem*, never a preference:
- **Cross-model spend — standing-authorized.** The cross-model stage (step 6) fires the configured
  passes automatically; no per-run `[EXTERNAL-ACTION CHECKPOINT]`. Each call is still logged to
  `RUN_DIR/log.md` with an `[EXTERNAL-ACTION]` line (model, bytes, cost-signal, exit) for audit —
  the principal pre-authorized the *class* (Grok/OpenRouter passes on his own drafts), every firing
  is logged. This is how a recurring gated action is automated legitimately; it is NOT an un-gated
  external action.
- **Data custody / disclosure — resolved.** (a) Sending pre-publication drafts to OpenRouter/xAI is
  accepted. (b) The published article does **NOT** disclose cross-model editing.
- **Live publish — standing-authorized.** The run commits and pushes to `main` (a production deploy
  to live https://devweb.org via Vercel) automatically once the **proofreader clears** and the build
  is green. This is an explicit, recorded standing authorization to cross the dev→prod boundary FOR
  THIS WORKFLOW ON THIS LOW-STAKES SITE — not a silent boundary breach. Safeguards: the proofreader
  step (a cold automated check that HOLDS on any real concern), the green-build gate, and easy
  reversibility (Vercel instant rollback / `git revert` + push).
- **The only stops are problems, not preferences:** (1) the **proofreader** finds a ship-blocking
  concern → hold just before commit + alert Robin; (2) `npm run build` fails → hold + surface;
  (3) config validation fails → hold + name the file. Nothing else waits for a human.

## Done criteria

The run is complete when ALL hold (the success path — proofreader `CLEAR`):
- `RUN_DIR/article.mdx` exists with valid frontmatter (the devweb Zod schema would accept it).
- The step-13 proofreader returned `CLEAR` (`RUN_DIR/proofread.md`).
- `npm run build` in devweb exits 0 with the route table all-static (every route `○` or `●`,
  **no `ƒ`**) — see step 14.
- The article is committed and **pushed to `main`** — live on https://devweb.org (step 14c).
- `RUN_DIR/log.md` carries: the figure-gate decision; the logged cross-model pass list; one
  `[EXTERNAL-ACTION]` line per cross-model call that actually fired; the proofreader verdict; the
  push; and the step-15 close-out with the count of paid passes.
- `RUN_DIR/state.json#accounting` is set (status `available` or, on failure, `unavailable`).

**Held (not complete):** if the proofreader returned `HOLD`, the run is paused just before commit
with Robin alerted (nothing written to devweb, nothing pushed) — resolve the named concerns, then
re-run from step 13. A build failure (14b) halts the same way.

## Edge cases

- **Figure gate skipped (no numbers).** If the latest version carries no quantitative claims, step
  6 logs `grounding: not-triggered` to `RUN_DIR/log.md` and the run continues at step 7 without
  entering 6a (no `NN-grounding.md` version is created). This is a branch, not a failure.
- **All cross-model passes fail.** The step-8 batch may produce zero candidates (every pass
  errored, was skipped, or failed integrity). Step 9 then runs as a Claude-only final revision of
  the latest version. Every prior version is preserved — `model-pass.sh` writes nothing on failure.
- **Resume after interruption mid-batch.** Any cleared candidate already in `RUN_DIR/passes/` is
  reused — step 8 skips that pass without re-charging the paid call. The workflow re-reads the
  effective config and skips every pass whose candidate exists. Candidate identity is keyed on
  the pass **`id`** (the skip predicate matches `*-<id>.md`), not on list position `NN`, so
  reordering or disabling a pass in a per-run config between interruption and resume cannot cause
  a paid call to be re-charged.
- **Per-run config override.** If `RUN_DIR/article-passes.json` exists it replaces
  `config/article-passes.json` entirely (not a merge). The effective config is one or the other,
  never a blend.
- **A draft that is almost entirely a data table.** The figure gate triggers (6a grounds the
  numbers); the length-delta integrity bound in `model-pass.sh` may legitimately reject a
  cross-model pass that compresses the table — that is the partial-failure policy working, not a
  bug. Format step emits a `<RunTable>` only if the frontmatter carries a `run` object.

## Fallback behavior

- If a step fails (non-zero exit, agent error), the Conductor logs the failure to `RUN_DIR/log.md`
  per `docs/conventions.md § Failure signature format` and raises a `[CHECKPOINT]`. **Do not
  auto-retry silently.**
- The article's recoverable state at any point is the latest clean `RUN_DIR/versions/` file. Every
  prior stage is preserved (immutable, numbered), so a bad step never destroys earlier work — roll
  back by reading an earlier version. The draft is never corrupted by a failed cross-model pass —
  the script fails closed and writes only to `passes/`.
- If config validation (step 7) fails, **stop and name the file** — never POST against a
  malformed config.
- If `npm run build` (step 14) fails, the article is NOT staged for release; surface the build
  error and `[CHECKPOINT]` — Robin or a follow-up run fixes the MDX.

## Observability

Everything that spends money or branches is logged to `RUN_DIR/log.md`:
- Every cross-model call (step 8) writes an `[EXTERNAL-ACTION]` line (model, bytes in/out,
  `finish_reason`, status, exit) — written by `model-pass.sh --run-dir`. These audit lines, not a
  per-run human `go`, are the control on the standing-authorized spend.
- The planned cross-model pass list (step 7) is logged before any POST (no `go` awaited).
- The figure-gate decision (`grounding: not-triggered`, or the 6a grounding record) is logged.
- The proofreader verdict (step 13: `CLEAR` / `HOLD` + concerns) is logged; a `HOLD` also fires an
  alert to Robin and logs the hold.
- The publish (step 14c): the commit + push to `main` is logged.
- The step-15 close-out surfaces the count of paid passes fired this run, read back from the
  `[EXTERNAL-ACTION]` lines.
A human inspects the run by reading `RUN_DIR/log.md`, `RUN_DIR/proofread.md`, the
`RUN_DIR/versions/` + `RUN_DIR/passes/` files, and the published article on devweb.

## Steps

Run these as spawned subagents (see "How to spawn an agent" and "Model routing" in
`agents/orchestrator.md`). Sequential — wait for each handoff before the next. Pass `RUN_DIR`
as an absolute path in every spawn prompt.

**Versioned spine (never overwrite).** The article advances through `RUN_DIR/versions/NN-<stage>.md`
files. Each step READS the current draft (the highest-numbered `versions/` file) and WRITES its
output to the NEXT number with a stage-named file — it never edits an existing version in place.
The Conductor assigns `NN` (creation order) and passes both the input path (latest version) and the
output path (next version) in the spawn prompt. This preserves every stage for audit: at close-out
the `versions/` dir + `manifest.md` IS the audit trail, and any two stages can be diffed. Each
cross-model pass still writes its candidate to `RUN_DIR/passes/NN-<id>.md` (its own dir, for the
resume-skip predicate); step 9 reconciles those candidates into the next `versions/` file.

1. **The Counselor** (Voice, **standard**, mode: frame) — angle + house framing → `angle.md`
   Reuses the Counselor **frame** mode (see `workflows/message-framing.md`) inline — spawned, not
   nested. The Counselor classifies the audience's value system (`spiral-dynamics`), chooses the
   angle and working title in the house voice, and proposes a pillar. Writes the angle, working
   title, and proposed pillar to `RUN_DIR/angle.md` for Robin's approval at the next gate.
   **Voice calibration (anti-homogenization):** from the audience read here, the Conductor selects
   the voice-calibration exemplar from `config/calibration-exemplars/index.md` — match the bucket to
   the Counselor's value-system read, rotate within the bucket across runs — and passes that
   exemplar's PATH to the Scribe at steps 3-4 and the Counselor review at steps 10-11. Do NOT
   hardcode one calibration article for every run; a single fixed exemplar is the main source of
   cross-article uniformity and feeds a self-imitation loop.

2. **Action** — proceed automatically (no approval wait). The Counselor's `angle.md` records the
   chosen angle, working title, and pillar (`frameworks` | `memory` | `engineering` — the devweb
   `lib/pillars.ts` enum) for visibility, but the run does **not** stop for sign-off. The title +
   pillar carry forward to the format/publish steps. (If the angle is wrong, Robin redirects after
   seeing the result — cheap to redo; not a reason to hold the pipeline.)

3. **The Scribe** (Outline, **standard**) → next version `NN-outline.md`
   Given `angle.md` + the approved working title + pillar. Produces a section-level outline —
   heading structure (h2/h3) in order, the key claim per section, and any figures/examples to
   gather before drafting. Outline only, no prose.

4. **The Scribe** (Draft, **strong**) — reads the outline → next version `NN-draft.md`
   Writes the full article body end-to-end in the house voice (loads the lite voice rules from
   `~/.claude/CLAUDE.md`). Escalated to **strong** (Opus) — this is the piece's first real prose.

5. **The Scribe** (Revise, **strong**) — higher-level improvement → next version `NN-revise.md`
   Reads the latest version (the draft); standard revision sub-mode: argument structure, evidence
   quality, section balance, transitions. Structural work, not a line-edit. Writes the improved
   article as a NEW version file — the prior draft version is preserved untouched.

6. **Gate** — figure check (conditional): the Conductor reads the latest version for real numbers
   or quantitative claims. If present, proceed to step 6a; else log `grounding: not-triggered` to
   `RUN_DIR/log.md` and skip to step 7. "Real numbers" means specific figures, percentages, dates,
   measurements — **not** vague qualitative statements ("most teams", "a lot faster").
   - 6a. **The Scribe** (Revise, **strong**, sub-mode: ground) — figure grounding → next version `NN-grounding.md` + `figure-check.md`
     Reads the latest version. Re-examine every quantitative claim against the source the draft
     itself cites or the run's own inputs. For each number: confirm it against the cited source,
     correct it if the source disagrees, or — if it cannot be grounded against any source the draft
     names or any run input — mark it `[unverified]` so Robin decides. **No live-web fact-check**
     (out of v1; the Scribe does not invent sources). Writes the grounded article as a NEW version
     file and a separate `RUN_DIR/figure-check.md` listing each claim, its source, and its status.

7. **Action** — cross-model stage prep (standing-authorized — NO human stop)
   The cross-model spend is pre-authorized (see Automation policy). Do NOT raise a per-run
   `[EXTERNAL-ACTION CHECKPOINT]`; the run proceeds straight into the passes. The only check here is
   **config validation, which IS a hard error-stop** — never POST against a malformed config.
   **Validate the effective config** (the per-run `RUN_DIR/article-passes.json` if present, else
   `config/article-passes.json`) with these `jq -e` guards (pattern mirrors `account-run.sh` and
   `scripts/model-pass.sh`'s contract); **on any failure, halt and name the file:**
   - `jq -e '.passes | type == "array"' <config>` — `.passes` is an array.
   - `jq -e '[.passes[] | select(.enabled == true) | .model | startswith("openrouter:")] | all' <config>`
     — every **enabled** pass's `model` carries the routable `openrouter:` provider prefix (v1's
     only arm). A non-`openrouter:` enabled pass fails loud — it is never silently skipped.
   - For each enabled pass, confirm its `instruction` path resolves to a real file under the bureau
     root (`/Users/robin/Code/novadiem/bureau/`): `test -f "<bureau-root>/<instruction>"`. A missing
     instruction file fails **before** the API call, not as an empty-instruction POST.
   Log the ordered enabled-pass list (model IDs + planned call count) to `RUN_DIR/log.md` for the
   record, then proceed to step 8. (No `go` is awaited — the standing authorization + the per-call
   `[EXTERNAL-ACTION]` audit lines are the control.)

8. **Action** — cross-model stage (post-approval)
   **Precondition (before dispatching any pass):** the Conductor confirms `RUN_DIR/` and
   `RUN_DIR/passes/` exist (create `passes/` if missing). `model-pass.sh` only writes its
   `[EXTERNAL-ACTION]` audit line when `--run-dir` points at an existing dir (silent no-op
   otherwise) — without this, a fired paid call goes unlogged and step 15's count under-reports.
   Iterate the effective passes config **in order**. For each pass with `enabled: true`, where
   `<id>` is its stable `id` and `NN` is the pass's zero-padded position in the list (`01`, `02`, …):
   - **Resume check (keyed on the pass `id`, not list position)** — if a cleared candidate for
     pass `<id>` already exists in `RUN_DIR/passes/` (match the glob `*-<id>.md`), **skip this
     pass** (resume-idempotent — a completed candidate is never re-charged; the file existing
     means it cleared every integrity check). The skip predicate keys on `<id>`, never on `NN`:
     if a per-run config is reordered or a pass disabled between an interruption and the resume,
     `NN` shifts but `<id>` is stable, so matching on `<id>` prevents a re-charge.
   - **Otherwise run** (input is the latest `versions/` file — the current draft; the instruction
     path resolves relative to the bureau root):
     ```
     bash scripts/model-pass.sh <model> "$RUN_DIR/versions/<latest>.md" \
       "/Users/robin/Code/novadiem/bureau/<instruction>" \
       "$RUN_DIR/passes/NN-<id>.md" --run-dir "$RUN_DIR"
     ```
     The script makes the POST, runs its integrity checks (HTTP 2xx, no `.error`,
     `finish_reason == "stop"`, output within 50%–300% of input bytes), and writes the candidate
     ONLY on full success. Its exit-code contract: **0** candidate written · **1** bad args /
     missing input · **2** provider error · **3** integrity-check failed · **4** keystore key
     missing.
   - **Partial-failure policy** — if `model-pass.sh` exits non-zero (1/2/3/4), log the failure to
     `RUN_DIR/log.md`, **skip that pass, and continue with the next.** No `versions/` file is
     written in this step (candidates land only in `passes/`; step 9 writes the next version). The
     batch continues with whatever cleared.

9. **The Scribe** (Revise, **strong**, generous integration) — reconcile the cross-model passes → next version `NN-reconcile.md`
   Given the latest `versions/` file (the current draft) + every **cleared** candidate in
   `RUN_DIR/passes/` (if any). **The point of the cross-model stage is that other models' perspectives
   improve the piece and let it evolve — so integrate GENEROUSLY: adopt the candidates' edits by
   default.** This is NOT a gate that defends the original wording, and it is NOT a "promotion
   authority" with editorial veto. The Scribe reverts a candidate's change to its own prior wording
   ONLY when one of these hard guards genuinely applies (and names which, per change):
   - **(a) Facts** — the change breaks a grounded fact or introduces a number/claim not in the source.
   - **(b) Known no-go framing** — the change reintroduces something the run already corrected (e.g.
     a figure-gate fix); a corrected fact stays corrected.
   - **(c) Voice floor** — AI-slop vocabulary, em dashes, curly quotes (the house voice baseline).
   - **(d) Concrete specifics** — the change drops a real name or load-bearing technical detail
     (e.g. a system name) for a vaguer word.
   Everything else — phrasing, structure, tightening, rhythm — let the other model win where its
   version is as good or better. Do NOT preserve the original just because it is the original or
   because it "carries a nuance you prefer." Write the reconciled article as a NEW version file.
   **Mechanical corruption is NOT this step's job** — truncation, refusals, and garbage are already
   caught upstream by `model-pass.sh`'s integrity checks (only cleared candidates reach this step).
   If no candidates exist (all passes failed or were skipped), the Scribe does a Claude-only final
   revision of the latest version.

10. **The Counselor** (Voice, **standard**, mode: review) — humanizer pass 1: AI-tells + vocabulary scrub → next version `NN-humanize-1.md`
    Reuses the Counselor **review** mode (see `workflows/copy-review.md`) inline — spawned, not
    nested. Reads the latest version. Loads the `humanizer` skill. Objective: strip AI tells,
    inflated vocabulary, chatbot artifacts, banned words. Writes the cleaned article as a NEW
    version file.

11. **The Counselor** (Voice, **standard**, mode: review) — humanizer pass 2: read-aloud rhythm + human texture → next version `NN-humanize-2.md`
    Reuses the Counselor **review** mode inline; reads the latest version. Two objectives, both
    distinct from pass 1's de-slop: (a) sentence rhythm, paragraph flow, read-aloud cadence; and
    (b) **human texture** — apply the `humanizer` skill's **TEXTURE LENS** to put back the
    unevenness a single thoughtful person leaves in (a long sentence beside short ones, a
    sentence-initial conjunction, a brief aside, not always an aphoristic closer), and vary the
    texture device from recent articles so the corpus does not converge on one cadence. **Light
    touch: a few real moves, not a rewrite.** Hard scope: texture touches cadence/phrasing/voice
    ONLY, never a fact, number, date, name, code, quote, or figure-grounded claim, and it never
    reintroduces slop (pass 1's de-slop floor still holds). A different objective on the
    now-de-slopped text, not a redundant re-run. Writes the final prose as a NEW version file.
    (The cold proofreader at step 13 still gates everything that follows.)

12. **The Scribe** (Format, **standard**) — MDX + frontmatter → next version `NN-article.mdx`
    Given the latest version (the final prose) + the approved slug + pillar. A mechanical transform
    (no content edits): emits the next version as `NN-article.mdx` with correct frontmatter
    (`title`, `dek`, `date` ISO, `pillar`, `slug` matching `^[a-z0-9-]+$`; optional `read` as an
    integer, `draft`, `run`) and only the allowed MDX components — `<PullQuote>` and `<RunTable>`,
    the ONLY two `devweb/components/mdx/index.ts` compiles. Any other JSX fails the devweb build.
    The Conductor copies this final version to `RUN_DIR/article.mdx` for the publish step.

13. **The Challenger** (Critic, **strong**, fresh context — proofreader / publish-concern) — the safety gate → `proofread.md`, verdict `CLEAR` | `HOLD`
    Reads ONLY the final `article.mdx` (the thing about to ship), cold. This is **not** a style or
    voice review (the humanizer already owns that) — it scans for **ship-blocking concerns** that
    would make publishing this to a public site a mistake:
    - **Sensitive / non-public material** — secrets, credentials, internal-only system details,
      private information about real people or clients, security-exploitable specifics.
    - **Factual / legal / reputational risk** — claims that are wrong or unsupportable, defamation,
      unverified accusations, anything that could embarrass or expose Robin / Novadiem.
    - **Catastrophic failures** — a broken or self-contradictory thesis, an obvious howler, a number
      the figure-gate missed.
    It returns **`CLEAR`** (nothing ship-blocking — proceed to publish) or **`HOLD`** with the
    named concerns. Nitpicks and preferences are NOT `HOLD`s — only a real concern holds. Writes
    `RUN_DIR/proofread.md` (the verdict + any concerns).
    - **`CLEAR`** → continue to step 14 automatically; no human stop.
    - **`HOLD`** → **the run stops here, just before commit, and alerts Robin.** The Conductor fires
      an alert (`scripts/notify-escalation.sh`, or the `notify_robin` MCP tool) with the named
      concerns, logs the hold to `RUN_DIR/log.md`, and waits. Nothing is written into devweb and
      nothing is pushed until Robin resolves it. This is the ONE concern-driven stop in the workflow.

14. **Action** — publish (write → build → commit → push live). Runs automatically only when step 13
    returned `CLEAR`.
    a. Copy `RUN_DIR/article.mdx` → `/Users/robin/Code/novadiem/devweb/content/articles/<slug>.mdx`.
    b. Run `npm run build` in `/Users/robin/Code/novadiem/devweb/`. The Zod schema validates the
       frontmatter; the build must stay **all-static** (every route `○` or `●`, no `ƒ`). **If the
       build fails, HALT** — surface the error and hold (do not commit). A broken build is an
       error-stop, not a preference.
    c. On a green build, **commit and push to `main`** (standing-authorized live publish — see
       Automation policy):
       ```
       git add content/articles/<slug>.mdx
       git commit -m "content: add '<title>' (<pillar> pillar)"
       git push origin main      # → live on https://devweb.org (Vercel auto-deploy)
       ```
       The article is now live. (Reversible via Vercel rollback / `git revert` + push if needed.)

15. **The Conductor** (**standard**) — close out + write the audit manifest + run accounting last → `manifest.md`, `log.md`, `state.json`
    Write **`RUN_DIR/manifest.md`** — the audit index: one row per `versions/` stage in order
    (`NN-<stage>` → word count → one-line "what changed from the prior version"), plus the
    `passes/` cross-model candidates. This is the end-state audit: the `versions/` dir holds every
    stage immutably and `manifest.md` is its table of contents.
    Surface the **count of paid external passes** fired this run, read back from the
    `[EXTERNAL-ACTION]` entries in `RUN_DIR/log.md`. Summarize what ran and what was staged; flag
    anything deferred. As the **final** close-out action — after the manifest, the summary, and the
    final `state.json` / `log.md` updates — run `scripts/account-run.sh <RUN_DIR>` so
    `accounting.json` reflects the terminal state, then set `state.json#accounting` per
    `docs/run-accounting.md`. Note: `account-run.sh` has no
    external-API cost source — it records the note; per-pass dollar capture is a registered v2
    deferral, so v1 surfaces the *count* of paid passes plus the `log.md` bytes-in/out lines.
