# Workflow: write-glossary

**When to use:** Robin wants glossary / definition pages for a site with a glossary content type
(today: devweb.org, `content/glossary/`, see its `lib/glossary.ts`): a **batch of terms**, each a
short "what is X" page whose definition is grounded in the site's own essays and code, published
to the target's glossary directory. Point it at a term list, or at a cluster name from
`devweb/docs/plan-content-taxonomy.md` §10 (harness cluster, memory cluster) and it derives the list.

**When NOT to use:** a long-form essay (→ `write-article`); a wording fix to an existing term (edit
the `.mdx` directly); a term the site has no essay to ground (write the essay first: a definition
that cites nothing fails the target build); user-facing copy that is not a definition
(→ `copy-review` / `message-framing`).

**Type:** mixed — spawns drafting agents (The Counselor, The Scribe, The Challenger) AND runs
`scripts/model-pass.sh` plus a cross-repo publish. A sibling of `write-article`: the same versioned
spine, automation policy and scripts, applied per term across a batch, with lighter passes because
each page is 250–600 words.

**Inputs:**
- `RUN_DIR/terms.json` — the batch, an array of objects:
  `{ "term": "agent harness", "slug": "agent-harness", "pillar": "frameworks",
     "target_query": "what is an agent harness", "related_hint": ["harness-is-the-product"],
     "aliases": ["harness"], "update": false }`.
  `term`, `slug`, `pillar` required; `target_query` and `related_hint` are hints the Counselor and
  the grounding step may improve on; `aliases` optional; `update: true` allows overwriting a
  published term (the Format step then sets `updated`). 5–8 terms per run is the working size.
- `RUN_DIR/publish-target.json` — copy `config/publish-targets/devweb-glossary.json` and replace
  the `repo` placeholder with the checkout path. Drives: category enum, content dir, the essays
  dir used for grounding + `related` validation, build command/check, live URL, the frontmatter
  and body limits. **Required**: this workflow has no article-only mode; a definition page exists
  to be published into a glossary.
- Optionally `RUN_DIR/article-passes.json`; if present it **replaces** `config/glossary-passes.json`
  for this run (not a merge).
- The OpenRouter key (`OPENROUTER_API_KEY` or `OPENROUTER_KEYSTORE`) for `scripts/model-pass.sh`.
- Read access to the target repo (the grounding step reads its essays; nothing is written there
  until step 10).
- Out of scope: live-web fact-check (grounding is against the site's own essays and code only);
  writing new essays; changing the target's schema or routes.

**Outputs:**
- `RUN_DIR/angle.md` — batch audience read; per term the query phrasing to target, a proposed
  `seoTitle` (≤ `seo_title_max_chars`), and any DROPPED terms with the reason.
- `RUN_DIR/grounding/<slug>.md` — per term: the passages from the target's essays that define or use
  it (file + heading refs), the qualifying `related` slugs, or `UNGROUNDED`.
- `RUN_DIR/versions/<slug>/NN-<stage>.md` — **the versioned line, per term.** Every stage writes a
  NEW zero-padded file; nothing overwrites. Typical: `00-draft.md`, `01-reconcile.md`,
  `02-humanize.md`, `03-term.mdx`.
- `RUN_DIR/passes/<slug>/NN-<id>.md` — one cleared cross-model candidate per pass per term.
- `RUN_DIR/glossary/<slug>.mdx` — the formatted pages, copied from each term's final version.
- `RUN_DIR/proofread.md` — per-term verdict `CLEAR` | `HOLD` | `DROP` with concerns.
- Cross-repo: `<repo>/<content_dir>/<slug>.mdx` for every `CLEAR` term, committed + pushed live.
- `RUN_DIR/manifest.md`, `RUN_DIR/log.md`, `RUN_DIR/state.json`, `accounting.json`.

**Leans on skills:** `humanizer` and `spiral-dynamics` (The Counselor, frame + review modes).
The Scribe loads the lite house-voice rules from `~/.claude/CLAUDE.md`.

**Reuses workflows:** `write-article` — its versioned spine, its cross-model stage
(`scripts/model-pass.sh`, config validation, resume-skip, partial-failure policy) and its
**Automation policy** apply here verbatim: cross-model spend and live publish are
standing-authorized; the run stops only on a real problem (proofreader `HOLD`, red build, malformed
config), never for a preference. `message-framing` and `copy-review` are reused inline as the
Counselor's frame and review modes, not nested.

## The page contract

What a term page is, so every agent writes to the same shape (mirrors the target's
`frontmatter`/`body` limits in `publish-target.json`; the target's Zod schema is the source of truth):

- **Definition:** ONE sentence, 40–240 characters, that answers "what is `<term>`?" on first read.
  Present tense. Names the thing before describing it. No hedging ("essentially", "can be thought
  of as"). It becomes the dek, the meta description and the JSON-LD description.
- **Body:** 250–600 words, at most two `##` headings, no `#` (the target renders the H1):
  (1) the boundary — what the term is NOT, its nearest neighbour and the difference;
  (2) one concrete example from a named system the site has written about, linking the essay
  (`/articles/<slug>`); (3) optionally how it shows up in practice. Links go only to the site's own
  essays or to primary sources named in those essays.
- **Frontmatter:** `term`, `slug` (`^[a-z0-9-]+$`), `pillar` (one of `categories`), `definition`,
  `date` (run date, ISO), `related` (≥1 essay slugs that exist under `articles_dir` and actually
  use the concept), optional `aliases`, `seoTitle` (the target query phrasing, ≤ 60 chars),
  `updated` (only when `update: true`), `draft: false`. **No author field**: the target renders the
  site as author of reference pages.
- **Voice floor:** house voice (`~/.claude/CLAUDE.md`): no em dashes, no curly quotes, no banned
  vocabulary, no chatbot artifacts. A definition page is not an essay: no anecdote lead, no closer.
- **Draft file shape** (steps 4–7, before Format):
  ```
  # <term>

  > <definition sentence>

  <body>
  ```

## Done criteria

Complete when ALL hold:
- Every term in `terms.json` has a verdict in `RUN_DIR/proofread.md` (`CLEAR`, `HOLD`, or `DROP`).
- Every `CLEAR` term's `.mdx` sits in `<repo>/<content_dir>/`, `build_cmd` exited 0 with
  `build_check` satisfied (for `all-static`: every route `○` or `●`, no `ƒ`), and the commit is
  pushed to `main` — live at `<live_url>/glossary/<slug>`.
- `RUN_DIR/log.md` carries: the validated batch, the grounding summary (grounded / UNGROUNDED per
  term), the planned pass list, one `[EXTERNAL-ACTION]` line per cross-model call that fired, the
  per-term verdicts, the build result, the push, and the step-11 close-out with the paid-pass count.
- `RUN_DIR/manifest.md` lists every `versions/<slug>/` stage.
- `state.json#accounting` is set.

**Held (not complete):** any `HOLD` term is left in `RUN_DIR/glossary/` (nothing written to the
target for it), Robin is alerted with the named concern, and the run notes which terms shipped
and which wait. `CLEAR` terms in the same batch still publish; a hold on one term never blocks
the others.

## Edge cases

- **UNGROUNDED term.** Grounding (step 3) finds no essay that defines or uses the concept. The term
  is marked `UNGROUNDED`, drafting skips it, and the proofreader records `DROP` with "no essay to
  cite". Log it as a candidate for `write-article`. Never invent a `related` link to satisfy the
  schema.
- **Slug already published.** Step 1 halts and names the term unless its `terms.json` entry has
  `update: true`; then Format sets `updated` to the run date and step 10 overwrites the file.
- **Definition over 240 characters (or two sentences).** Reconcile (step 6) guard (e) and Format
  (step 8) both enforce it; if Format cannot fit the sentence without changing meaning, the term is
  `HOLD` with the over-long definition quoted.
- **A `related` slug that does not exist.** The target build fails and names the file
  (`[glossary] <file>: related essay "<slug>" does not exist`). Step 10 removes that term's file
  from the target, marks it `HOLD` with the build message, rebuilds, and publishes the rest.
- **All cross-model passes fail** for a term (or for the batch). Step 6 runs as a Claude-only
  revision of `00-draft.md`; every earlier version is preserved.
- **Resume mid-batch.** Candidate identity is `passes/<slug>/*-<id>.md`; an existing cleared
  candidate is never re-charged. Terms with a `03-term.mdx` already in `versions/` skip to step 9.
- **Batch of one.** Everything runs the same; the spawns are simply shorter.
- **Draft too short/long.** Format checks the `body.min_words`/`max_words` band; outside it,
  the Scribe (Revise, standard) trims or extends once; still outside → `HOLD`.

## Fallback behavior

- A failed step (non-zero exit, agent error) is logged to `RUN_DIR/log.md` per
  `docs/conventions/failure-signatures.md § Failure signature format` and raises a `[CHECKPOINT]`.
  **No silent retry.**
- The recoverable state per term is its highest-numbered `versions/<slug>/` file; roll back by
  reading an earlier one. `model-pass.sh` fails closed and writes only to `passes/`.
- Malformed `terms.json` or `publish-target.json` (step 1) or a malformed passes config (step 5):
  **stop and name the file.** Never POST against a malformed config.
- Red build in step 10 after removing the named term: **halt**, surface the error, `[CHECKPOINT]`.
  Nothing is committed on a red build.

## Observability

- Every cross-model call writes an `[EXTERNAL-ACTION]` line to `RUN_DIR/log.md` via
  `model-pass.sh --run-dir` (model, bytes in/out, `finish_reason`, status, exit).
- The planned pass list × term count is logged before any POST.
- Grounding status per term, the per-term verdicts, the build result (with the route table's
  `○`/`●`/`ƒ` check), and the commit + push are logged.
- Close-out surfaces the paid-pass count and the shipped / held / dropped tallies.
- A human inspects the run by reading `RUN_DIR/log.md`, `RUN_DIR/proofread.md`,
  `RUN_DIR/grounding/`, `RUN_DIR/versions/<slug>/`, and `<live_url>/glossary`.

## Steps

Run these as spawned subagents (see "How to spawn an agent" and "Model routing" in
`agents/orchestrator.md`). Sequential; wait for each handoff before the next. Pass `RUN_DIR` as
an absolute path in every spawn prompt. Batch steps (3, 4, 6, 7, 8) take the whole term list in
one spawn and write one file per term; the Conductor lists the term slugs and the exact input →
output path per term in the spawn prompt.

1. **Action** — validate inputs → `log.md` (the validated batch)
   Read `RUN_DIR/publish-target.json`: `page_type` must be `glossary`; `repo` must be a real
   checkout (the `<path-to-devweb-checkout>` placeholder still present is a halt); `content_dir`,
   `articles_dir`, `categories`, `frontmatter`, `body` present. Read `RUN_DIR/terms.json`: array,
   every entry has `term`, `slug` matching `^[a-z0-9-]+$`, `pillar` in `categories`; slugs unique
   in the batch; a slug already present in `<repo>/<content_dir>/` halts unless `update: true`.
   **On any failure halt and name the file.** Log the batch (term count, slugs, pillars).

2. **The Counselor** (Voice, **standard**, mode: frame) — batch framing + per-term query → `angle.md`
   Reuses the Counselor **frame** mode inline. One audience read for the batch
   (`spiral-dynamics`): who types "what is `<term>`" and what they need first. Per term: the exact
   query phrasing to target (take `target_query` if given, else the most natural "what is a/an X" /
   "X meaning" form), a proposed `seoTitle` in that phrasing (≤ `seo_title_max_chars`), and a one-line
   note on the boundary the body must draw. May mark a term `DROP` (duplicates another term, or no
   plausible demand) with a reason. Voice calibration: pick the exemplar per `write-article` step 1
   and pass its path to steps 4, 6 and 7.

3. **The Scribe** (Revise, **standard**, sub-mode: ground) — grounding per term → `grounding/<slug>.md`
   For each term: read the essays named in `related_hint`, and grep `<repo>/<articles_dir>` for the
   term and its aliases. Extract the passages that define or use the concept, with file + heading
   refs, and the exact system names and figures those passages carry. List the qualifying `related`
   slugs (an essay qualifies only if it uses the concept, not merely the word). A term with no
   qualifying essay is written up as `UNGROUNDED` with what was searched. Reads the repo; writes
   only under `RUN_DIR`. No live web; no invention.

4. **The Scribe** (Draft, **strong**) — draft every grounded term to the page contract → `versions/<slug>/00-draft.md`
   Reads `angle.md` and each term's `grounding/<slug>.md`; loads the lite voice rules. Writes each
   page in the draft file shape: the one-sentence definition as the blockquote, then a body of
   250–600 words with the boundary, the grounded example linking the essay, and at most two `##`.
   Uses only facts, names and figures present in the grounding file. Skips `UNGROUNDED` and
   Counselor-`DROP` terms (logs the skip).

5. **Action** — cross-model stage (standing-authorized, no human stop) → `passes/<slug>/NN-<id>.md`
   Validate the effective config (`RUN_DIR/article-passes.json` if present, else
   `config/glossary-passes.json`) with `write-article` step 7's `jq -e` guards; on failure halt and
   name the file. Ensure `RUN_DIR/passes/<slug>/` exists per term. Log the planned pass list × term
   count. For each drafted term, for each enabled pass in order: skip if `passes/<slug>/*-<id>.md`
   exists (resume, never re-charged); else
   ```
   bash scripts/model-pass.sh <model> "$RUN_DIR/versions/<slug>/00-draft.md" \
     "<bureau-root>/<instruction>" "$RUN_DIR/passes/<slug>/NN-<id>.md" --run-dir "$RUN_DIR"
   ```
   Partial-failure policy as `write-article` step 8: log, skip that pass, continue.

6. **The Scribe** (Revise, **strong**, generous integration) — reconcile per term → `versions/<slug>/01-reconcile.md`
   Per term: the draft plus every cleared candidate under `passes/<slug>/`. Integrate generously
   (adopt candidate edits by default) with `write-article` step 9's hard guards (a) facts, (b)
   known no-go framing, (c) voice floor, (d) concrete specifics, plus **(e) the definition stays
   one sentence within `definition_max_chars`** and **(f) every link still points at a grounded
   essay**. No candidates → Claude-only revision of the draft.

7. **The Counselor** (Voice, **standard**, mode: review) — one humanizer pass per term → `versions/<slug>/02-humanize.md`
   Reuses the Counselor **review** mode inline; loads `humanizer`. Short pages get one combined
   pass: strip AI tells and banned vocabulary, then read-aloud rhythm with a light texture touch.
   Hard scope as `write-article` step 11: cadence and phrasing only; never a fact, name, number,
   link, or the definition's meaning. Reads the site's most recent glossary pages (if any) so the
   batch does not converge on one cadence.

8. **The Scribe** (Format, **standard**) — MDX + frontmatter per term → `versions/<slug>/03-term.mdx`
   Mechanical transform, no content edits. Frontmatter from the page contract: `term`, `slug`,
   `pillar`, `definition` (the blockquote sentence, verbatim), `date` (run date), `related` (the
   qualifying slugs from `grounding/<slug>.md`, at least one), `aliases` (from `terms.json` plus any
   the grounding surfaced), `seoTitle` (from `angle.md`), `draft: false`, and `updated` only when the
   entry has `update: true`. Body = the humanized body with the `#` and blockquote lines removed.
   No custom JSX (`mdx_components` is empty). Checks the `body` word band and the definition
   length; outside the band → one Scribe (Revise, standard) fix, then `HOLD` if still outside. The
   Conductor copies each final version to `RUN_DIR/glossary/<slug>.mdx`.

9. **The Challenger** (Critic, **strong**, fresh context — proofreader / publish-concern) — per-term verdict → `proofread.md`
   Reads ONLY `RUN_DIR/glossary/*.mdx` and the matching `grounding/<slug>.md` files, cold. Not a
   style review. Per term returns `CLEAR`, `HOLD` (named concern) or `DROP` (`UNGROUNDED`, or a
   definition the grounding does not support). Checks: the definition and example say only what the
   cited essays say (no invented capability or number); no sensitive or non-public material; no
   factual / legal / reputational risk; frontmatter conforms (definition length, `related` slugs
   present as files under `<repo>/<articles_dir>`, `pillar` in `categories`); voice floor (no em
   dashes, curly quotes, banned vocabulary). Nitpicks are not `HOLD`s. Any `HOLD` fires an alert to
   Robin (`scripts/notify-escalation.sh` or the `notify_robin` MCP tool) with the concern; the run
   continues to step 10 for the `CLEAR` terms.

10. **Action** — publish the `CLEAR` terms (write → build → commit → push live) → `log.md` (build + push)
    a. Copy each `CLEAR` `RUN_DIR/glossary/<slug>.mdx` → `<repo>/<content_dir>/<slug>.mdx`.
    b. Run `build_cmd` in `<repo>`; apply `build_check` (`all-static`: every route `○` or `●`, no
       `ƒ`). The target's loader validates every `related` slug and the schema; on a failure that
       names one term's file, remove that file from the target, mark the term `HOLD` with the build
       message, and rebuild once. Any other red build: **halt**, do not commit.
    c. On green:
       ```
       git -C <repo> add <content_dir>/
       git -C <repo> commit -m "content: add <N> glossary terms (<pillars>)"
       git -C <repo> push origin main      # → live at <live_url>/glossary
       ```
       Log the shipped slugs and the live URLs. Reversible via `git revert` + push.

11. **The Conductor** (**standard**) — close out + manifest + accounting last → `manifest.md`, `log.md`, `state.json`
    Write `RUN_DIR/manifest.md`: one row per `versions/<slug>/NN-<stage>` (word count, one line on
    what changed) plus the `passes/` candidates. Surface shipped / held / dropped tallies and the
    paid-pass count read back from the `[EXTERNAL-ACTION]` lines. As the final action run
    `scripts/account-run.sh <RUN_DIR>` and set `state.json#accounting` per `docs/run-accounting.md`.
