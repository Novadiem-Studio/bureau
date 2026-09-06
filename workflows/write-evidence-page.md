# Workflow: write-evidence-page

**When to use:** Robin wants an **evidence page** for a site with an evidence content type (today:
devweb.org `/evidence/<slug>`, `content/evidence/<slug>.mdx`, see its `lib/evidence.ts`): a "does X
work" question answered from the studio's own run records — what was measured, the runs it stands
on, the answer as far as the evidence goes, its limits — with a **grade on the evidence** from a
closed set. Point it at a question list.

**When NOT to use:** an opinion piece about a practice (→ `write-article`); a definition
(→ `write-glossary`); a question the run records cannot bear on (no measurement, no page); a grade
meant to recommend a practice (grades describe evidence, never whether to do the thing —
docs/plan-content-taxonomy.md §6.4).

**Type:** mixed — a thin sibling of `write-data-page`: **run `write-glossary`'s eleven steps with
`write-data-page`'s substitutions AND the ones below.** Everything not named here is as those two
files specify (mechanical grounding, verbatim tables, `check-numbers.py` at Format / reconcile /
proofread, the data Grok pass, the Automation policy).

**Inputs:**
- `RUN_DIR/questions.json` — the batch, an array: `{ "slug": "does-an-ai-code-reviewer-catch-real-problems",
  "question": "Does an AI code reviewer catch real problems?", "target_query": "does ai code review work",
  "measures": ["challenger findings taxonomy", "critic loops", "cold-review decisions", "proofreader holds"],
  "related_hint": ["clean-audit-run-proves-nothing", "who-checks-the-checker"], "update": false }`.
- `RUN_DIR/publish-target.json` — copy `config/publish-targets/devweb-evidence.json`, replace the `repo`
  placeholder. Names the dataset script + args, dirs, limits, the grade set.
- Optionally `RUN_DIR/article-passes.json` (copy `config/data-passes.json`).
- The OpenRouter key; read access to every repo root the dataset script scans (`--roots`).

**Outputs:** as `write-data-page` with `RUN_DIR/dataset/{dataset.json,tables.md,coverage.md}` from
`scripts/review-evidence-dataset.py` (one dataset for the whole batch), `RUN_DIR/evidence/<slug>.mdx`
per question, and cross-repo `<repo>/<content_dir>/<slug>.mdx` (+ `<public_data_dir>/review-evidence.json`
once per batch when any page sets `dataset`).

## Substitutions (beyond write-data-page's)

**Page contract** (the target's Zod schema is the truth):
- **Frontmatter:** `question` (as the reader types it), `slug`, `answer` (ONE sentence, 40–280 chars,
  as far as the evidence goes — no further), `grade` ∈ {strong, mixed, limited, insufficient},
  `gradeNote` (one sentence: what the evidence can and cannot support), `date`, `asOf` (the dataset's
  as_of), `sources` (the dataset file's provenance: the framework's pattern doc with its refresh date
  as `fetched`; the devweb data page URL when it is drawn on), optional `dataset`
  (`{ file: "/data/review-evidence.json", format: "json" }`), `seoTitle` (≤ 60, the query phrasing),
  `seoDescription` (40–240), `draft: false`. **No author field.**
- **Body, 600–1200 words plus verbatim tables, at most five `##`, in this order:**
  1. **What was measured** — the concrete records behind the question (which counters, which
     verdict files, which taxonomy), and what they cannot see (misses are invisible; only catches are
     recorded; no control group; one framework; models changed across the corpus).
  2. **What it stands on** — the corpus table(s) verbatim from `tables.md`: runs, repos, records
     present; the coverage table when it matters.
  3. **The answer** — the numbers that bear on the question, each copied from the tables, read
     plainly; the answer sentence restated; nothing the tables do not show.
  4. **Why this grade** — the grade defined once, then why the evidence lands there: sample size,
     first-party-ness, absence of ground truth for misses, confounds. **The grade is a statement about
     the evidence. A sentence telling the reader to adopt, keep, or drop the practice is a HOLD.**
  5. **What would change the grade** — the specific record that would move it up or down.
  Links: at least two essays (`/articles/<slug>`) that argue the practice, at least one glossary term,
  and the run-costs data page (`/data/run-costs`) where cost is mentioned.
- **Numbers are copied, never composed** (write-data-page's rule): `check-numbers.py <page>
  tables.md coverage.md` exits 0 at Format, on the Grok candidate, and at the proofread.
- **Publication guard:** the dataset identifies non-devweb runs by repo, workflow family and date
  only; the page names no task, client, or finding text from other repos. The proofreader checks.

**Step substitutions:**
- Step 1 validates `questions.json`; each `related_hint` essay must exist.
- Step 2 (Counselor frame): the reader is deciding whether to add a review stage to an agent
  pipeline; the frame names what the page must NOT do (recommend), and the exact grade vocabulary.
- Step 3 (grounding) is mechanical: from the bureau root run
  `python3 <dataset_script> <dataset_script_args...> --out RUN_DIR/dataset --as-of <run date>` once
  for the batch; log the command and its summary line; hand the Scribe `tables.md` + `coverage.md`.
- Step 4 (Scribe Draft, one spawn per question or one for the batch): from the tables only; proposes
  the grade and gradeNote from the evidence's shape (N, first-party, no ground truth for misses).
- Step 9 (proofreader): in addition to write-data-page's checks — the grade is one of the closed
  set; the "Why this grade" section's reasons match the grade (a `strong` grade on a first-party,
  no-control corpus is a HOLD; `limited` or `mixed` is the honest ceiling for this corpus today);
  no sentence recommends a practice; the publication guard holds; every linked essay exists.
- Step 10 (publish): copy each `CLEAR` page to `<content_dir>/<slug>.mdx`; copy
  `RUN_DIR/dataset/dataset.json` to `<public_data_dir>/review-evidence.json` when any page sets
  `dataset`; build; `git add <content_dir>/ <public_data_dir>/`; commit `content: add <N> evidence
  page(s) (<slugs>)`; push; live at `<live_url>/evidence/<slug>`.

## Done criteria, edge cases, fallback, observability

As `write-data-page`. Additional edge case: **the dataset cannot bear on a question** (the relevant
record is absent for nearly every run) — the page still ships if Robin's batch asked for it, with
grade `insufficient` and a body that says exactly which record is missing; otherwise the Conductor
drops the question and logs it as a candidate for a future run once the record exists.
