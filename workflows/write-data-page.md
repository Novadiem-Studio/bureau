# Workflow: write-data-page

**When to use:** Robin wants a first-party **data page** for a site with a data content type (today:
devweb.org `/data/<slug>`, `content/data/<slug>.mdx`, see its `lib/data.ts`): a page that publishes
figures derived from the studio's own run records — tokens by role, API-equivalent cost with the
arithmetic shown, a dated price basis, named sources — plus the dataset file itself and, when the
batch says so, `run:` frontmatter blocks (RunTables) on the essays those runs produced. Point it at a
dataset definition.

**When NOT to use:** an essay that merely mentions costs (→ `write-article`); a definition
(→ `write-glossary`); a figure that cannot be regenerated from a script over files in the repo
(no substrate, no page: docs/plan-content-taxonomy.md §1 "grounded, not spun").

**Type:** mixed — a thin sibling of `write-glossary`: **run `write-glossary`'s eleven steps with the
substitutions below.** Everything not named here is exactly as `write-glossary.md` specifies,
including the Automation policy inherited from `write-article`.

**Inputs:**
- `RUN_DIR/datasets.json` — the batch, an array: `{ "slug": "run-costs", "title": "What a
  multi-agent article costs to produce", "question": "what does one Bureau article run cost, in
  tokens and API-equivalent dollars, by role?", "script_args": ["--workflows",
  "write-article,write-glossary,write-topic-overview"], "publish_dataset_file": true,
  "apply_run_frontmatter": ["vectors-in-the-file", "clean-audit-run-proves-nothing"], "update": false }`.
- `RUN_DIR/publish-target.json` — copy `config/publish-targets/devweb-data.json`, replace the `repo`
  placeholder. Names the dataset script, the pricing table, the content and public dirs, limits.
- Optionally `RUN_DIR/article-passes.json` (copy `config/data-passes.json`; the data Grok pass).
- The OpenRouter key for `scripts/model-pass.sh`; read access to the target repo's `.bureau/`.

**Outputs:** as `write-glossary` with `<slug>` = the dataset slug, plus `RUN_DIR/dataset/`
(`dataset.json`, `tables.md`, `coverage.md`, `run-frontmatter/<essay>.yaml`), and cross-repo:
`<repo>/<content_dir>/<slug>.mdx`, `<repo>/<public_data_dir>/<slug>.json` (when
`publish_dataset_file`), and the named essays' `run:` frontmatter (when `apply_run_frontmatter`).

## Substitutions (the only differences from write-glossary)

**Page contract** (the target's Zod schema is the truth):
- **Numbers are copied, never composed.** Every figure on the page comes from
  `RUN_DIR/dataset/tables.md` (or `coverage.md`) verbatim: same digits, same rounding, same units.
  The writer selects which tables and rows to show and writes the prose around them; the writer
  never computes, rounds, sums, or restates a number. `scripts/check-numbers.py <page> tables.md
  coverage.md` must exit 0 at Format (step 8) and again at the proofread (step 9).
- **Shape:** 600–1200 words of prose plus the tables, at most five `##`. Order: (1) the question
  and the one finding the numbers support, in three sentences; (2) the price basis table and what
  "API-equivalent" means here (Claude legs ran on a subscription; only Grok was metered; Grok tokens
  are estimates from byte counts; cache writes priced at the 1-hour rate; aliases priced at the
  model they resolve to on the as-of date); (3) the runs table with a reading of it, including the
  coverage column and why some runs show `n/a`; (4) the leg breakdown for complete runs, with what
  it shows about where the cost sits; (5) what the dataset cannot say yet and how it will grow.
  Links to the essays the runs produced (`/articles/<slug>`) and to the relevant glossary terms
  ([run accounting](/glossary/run-accounting) at minimum).
- **Frontmatter:** `title`, `slug`, `dek` (40–240), `date` (run date), `asOf` (the dataset's
  `as_of`), `sources` (one entry per price source in `dataset.json#pricing_basis`, with its
  `fetched` date), `dataset: { file: "/data/<slug>.json", format: "json" }` when
  `publish_dataset_file`, optional `seoTitle` (≤ 60), `seoDescription` (40–240), `draft: false`.
  **No author field** (the site renders devweb.org as author).
- **Voice:** house voice; a data page is plain and dry by design. No em dashes, no curly quotes.

**Step substitutions:**
- Step 1 validates `datasets.json`; a slug already present under `<content_dir>/` halts unless
  `update: true`; each `apply_run_frontmatter` essay must exist under `articles_dir`.
- Step 2 (Counselor frame): the reader is someone pricing agent pipelines; the frame names what the
  page must NOT claim (actual spend, per-token billing, comparability across model generations).
- Step 3 (grounding) is **mechanical**: the Conductor runs, from the bureau root,
  `python3 <dataset_script> --target-repo <repo> --pricing <pricing> --out RUN_DIR/dataset --as-of
  <run date> [script_args...]`, logs the command and the summary line, and hands the Scribe
  `tables.md` + `coverage.md` only. No specialist grounds a data page by hand.
- Step 4 (Scribe Draft): from the tables; tables pasted verbatim; prose written around them.
- Step 5 (cross-model): the improve pass uses `config/passes/improve-data-grok.md`; the reconcile
  step (6) re-runs `check-numbers.py` on the candidate before adopting anything and rejects the
  whole candidate if a number changed.
- Step 8 (Format): frontmatter per the contract; runs `check-numbers.py`; any orphan number →
  one Scribe fix (restore the table value), then `HOLD`.
- Step 9 (proofreader): re-runs `check-numbers.py`; recomputes the arithmetic on at least three
  sampled rows from the printed formulas; verifies every source URL and `fetched` date match
  `dataset.json#pricing_basis`; verifies the caveats in the contract are all stated. Any invented,
  rounded, or unsourced figure is `HOLD`.
- Step 10 (publish): copy the page to `<content_dir>/<slug>.mdx`; copy `RUN_DIR/dataset/dataset.json`
  to `<public_data_dir>/<slug>.json` when `publish_dataset_file`; for each `apply_run_frontmatter`
  essay, insert the `run:` block from `RUN_DIR/dataset/run-frontmatter/<essay>.yaml` into that
  essay's frontmatter (the target's RunTable renders it; nothing else in the essay changes; the
  build's Zod schema validates it); build; `git add <content_dir>/ <public_data_dir>/
  <articles_dir>/<each essay>.mdx`; commit `content: add data page '<title>' (+ RunTables on N
  essays)`; push; live at `<live_url>/data/<slug>`.

## Done criteria, edge cases, fallback, observability

As `write-glossary`, plus: the published page passes `check-numbers.py` against the shipped
`dataset.json`'s tables; the dataset file is reachable at `<live_url>/data/<slug>.json`; each
RunTable essay renders its table. Additional edge case: **the dataset script finds fewer than two
complete-coverage runs** — the page still ships but its rollup section says so plainly and the
Conductor logs it; the page is built to be regenerated as coverage grows (`update: true` next run).
