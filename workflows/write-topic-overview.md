# Workflow: write-topic-overview

**When to use:** Robin wants the written overview that sits above a topic hub's article list on a
site with a topics content type (today: devweb.org `/topics/<pillar>`, `content/topics/<pillar>.mdx`,
see its `lib/topics.ts`): a batch of one to three **guide-shaped** pages, each the answer to that
pillar's search query ("ai agent orchestration", "ai agent memory architecture"), that maps the
pillar's essays and glossary terms into a reading order. Point it at a pillar list.

**When NOT to use:** a definition page (→ `write-glossary`); a long-form essay (→ `write-article`);
a wording fix to an existing overview (edit the `.mdx` directly); a pillar with fewer than three
essays to map (write the essays first; an overview of two pieces is a table of contents).

**Type:** mixed — a thin sibling of `write-glossary`: **run `write-glossary`'s eleven steps with the
substitutions below.** Everything not named here (spawn recipe, versioned spine per page, the
cross-model stage and its config validation, resume-skip, partial-failure policy, the per-page
proofreader verdicts, the publish step's build/commit/push, close-out and accounting, the
Automation policy inherited from `write-article`) is exactly as `write-glossary.md` specifies.

**Inputs:**
- `RUN_DIR/topics.json` — the batch, an array: `{ "pillar": "memory", "target_query": "ai agent
  memory architecture", "working_title": "AI agent memory: the field guide", "update": false }`.
  `pillar` required and in the target's `categories`; `target_query` and `working_title` are hints
  the Counselor may improve on; `update: true` allows overwriting a published overview.
- `RUN_DIR/publish-target.json` — copy `config/publish-targets/devweb-topics.json`, replace the
  `repo` placeholder. Drives content dir, essays + glossary dirs used for grounding, file name
  (`<pillar>.mdx`), build, live URL pattern, and the frontmatter/body limits. Required.
- Optionally `RUN_DIR/article-passes.json` (replaces `config/glossary-passes.json` for this run).
- The OpenRouter key for `scripts/model-pass.sh`; read access to the target repo.

**Outputs:** as `write-glossary` with `<pillar>` in place of `<slug>`: `angle.md`,
`grounding/<pillar>.md`, `versions/<pillar>/NN-<stage>.md`, `passes/<pillar>/NN-<id>.md`,
`topics/<pillar>.mdx` (the formatted pages), `publish-packet.md`, `proofread.md`, and the
cross-repo `<repo>/<content_dir>/<pillar>.mdx` for every `CLEAR` page.

**Leans on skills / reuses workflows:** as `write-glossary`.

## Substitutions (the only differences from write-glossary)

**Page contract** (mirrors the target's `frontmatter`/`body` limits; the Zod schema is the truth):
- **Shape:** a guide, 400–700 words, no `#` (the hub renders its own H1 chrome), at most three
  `##`. Prose plus at most one short list. It renders ABOVE the article list, so it must not
  duplicate the list: it explains the terrain and tells the reader what to read first and why.
- **Opening paragraph:** answers the pillar's query directly in two or three sentences — what this
  topic is on this site, and the one claim the pillar's essays share. No throat-clearing.
- **The map:** the body links AT LEAST `body.min_article_links` essays from the pillar
  (`/articles/<slug>`), each with a clause on what that piece settles, in a reading order the
  reader can follow; and AT LEAST `body.min_term_links` glossary terms from the pillar
  (`/glossary/<slug>`) inline where the concept first appears. Prefer linking every essay in the
  pillar; skip one only when it does not belong to the guide's line.
- **Boundary:** one paragraph on what this pillar is NOT, naming the neighbouring pillar(s) with a
  link to their hub (`/topics/<other>`).
- **Close:** where to start (one essay) and where to go after (one or two), then stop. No summary
  paragraph, no call to action.
- **Frontmatter:** `pillar`, `seoTitle` (the query phrasing, ≤ 60 chars), `seoDescription`
  (40–240 chars, the opening claim compressed), `date` (run date), `draft: false`, `updated` only
  when `update: true`. **No author field** (the site renders devweb.org as author).
- **Grounding:** every claim about an essay comes from that essay. The grounding step (step 3)
  reads EVERY essay in the pillar (frontmatter + headings + first and last sections) and every
  glossary term in the pillar, and writes `grounding/<pillar>.md` as a table: slug, one-line
  claim the essay settles, the concepts it introduces. The Scribe writes only from that table.
- **Draft file shape** (steps 4–7): `# <working title>` then the body; Format strips the `#`.

**Step substitutions:**
- Step 1 validates `topics.json` (not `terms.json`): each `pillar` in `categories`, unique in the
  batch; a pillar with an existing `<content_dir>/<pillar>.mdx` halts unless `update: true`; a
  pillar with fewer than three essays under `articles_dir` halts and names it.
- Step 2 (Counselor frame): per pillar, the guide-shaped query to target and a `seoTitle` in that
  phrasing; the reading order it recommends; the boundary it wants drawn. Autocomplete-validated
  query shapes for devweb are in `devweb/docs/plan-content-taxonomy.md` §2.
- Step 3 (grounding): as the page contract above — the whole pillar, not selected essays.
- Step 5 (cross-model): the improve pass uses `config/passes/improve-topic-grok.md` (set via the
  passes config: `RUN_DIR/article-passes.json` copied from `config/topic-passes.json`).
- Step 8 (Format): file name `<pillar>.mdx`; checks the link counts and the word band; a body
  under `min_article_links` or `min_term_links` → one Scribe (Revise, standard) fix, then `HOLD`.
- Step 9 (proofreader): in addition to `write-glossary`'s checks, verifies every `/articles/` and
  `/glossary/` link resolves to a file under the target's dirs and every claim about an essay
  matches that essay's own text; an overview that contradicts an essay it links is `HOLD`.
- Step 10 (publish): `git add <content_dir>/`; commit `content: add <N> topic overview(s)
  (<pillars>)`; live at `<live_url>/topics/<pillar>`.

## Done criteria, edge cases, fallback, observability

As `write-glossary`, with `<pillar>` for `<slug>` and `/topics/<pillar>` for `/glossary/<slug>`.
Additional edge case: **a pillar whose essays disagree** (the grounding table surfaces a
contradiction between two essays) — the overview may not paper over it; it names the tension in
one sentence and links both, and the Conductor logs it as a corpus item for Robin.
