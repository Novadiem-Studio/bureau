# Workflow: illustrate-pages

**Objective:** put an accurate, house-styled figure on published content pages, where every
number in the figure provably matches the page it sits on.

**When to use:** a site already has published pages with worked numbers, processes or
comparisons (a manual, docs, a course) and Robin wants figures added to them, one page at a
time or in waves. Typical trigger: "add illustrations to the live pages", "draw figures for the
batch that just merged", "get the figures strand going on <site>".

**When NOT to use:** decorative art with no numbers to get right (chapter openers, hero images:
that is a paid-generation decision for Robin, see `video-production` money rules); a chart that
must update from live data (that is a component, `build-review-cold`); writing the page text
itself (the content workflow for that site); a single figure Robin has already drawn.

**Type:** mixed. Spawns a drawer (and, on the optional reference path, a librarian and a
brief-writer), runs `scripts/figure-restyle.sh`, then wires, gates, PRs and merges.

**Inputs:**
- A **project profile**, `config/illustrate-profiles/<project>.md`, plus its style file. The
  profile names the repo, content dir, run dir, figure tooling, look, WebP settings, wiring
  convention, check commands and the merge protocol with any parallel content strand. The
  steps below refer to profile fields by name and hold no project specifics. Start a new
  project by copying `cryptowatchtools-learn.md`.
- The list of candidate pages (published on the default branch).
- Optional: a private reference source (video frames, screenshots) for briefs.
- Out of scope: changing page text. A wrong number on a page goes to the content strand as a
  note; the figure follows the page as published.

**Outputs:** per page, `<slug>.<ext>` beside the page with an image line, alt and caption; the
code-drawn source (`defs/<slug>.ts`, SVG, PNG) on the figures branch; one issue and one merged
PR per wave; a line in the run log with the merge SHA.

**Leans on skills:** `video-production` (only its paid-generation money rules, if Robin asks
for generated art); `humanizer` for captions when the profile's site has no voice gate.
Scripts: `scripts/figure-restyle.sh`.

## Roles and models (as run on cryptowatchtools, 2026-10-15/16)

| Role | Ran as | Sees |
|---|---|---|
| Strand Conductor (select, preview, restyle check, wiring, PR, merge) | Claude Opus, the illustrations session itself | everything except private frames |
| Librarian | Sonnet subagent | the private reference source |
| Brief-writer | Sonnet subagent | frames plus page text |
| Drawer | Sonnet subagent | page text and briefs only, never frames |
| Restyle | Codex CLI `codex exec` with its built-in `image_generation` tool, on Robin's ChatGPT plan | the rendered PNG only |

The restyle check was done by the Conductor reading each PNG, not a cold reviewer. It caught
every error that reached it (one misspelled label); a Challenger pass is optional, not needed.

## Steps

1. **The Conductor** (Profile, **strong**): load the project profile and style file, confirm the figures worktree and run dir exist, read the strand's notes and handoff → `RUN_DIR/<strand>/notes.md`
   - The figures strand is its own session. It never resumes, messages as, or writes for the
     content strand's agents (a forked session once resumed the content writer by mistake and
     two writers drafted the same files for five minutes). Its diary goes in its own notes file,
     not the shared run log.
   - If the profile names no look yet, step 6 runs first on one figure.

2. **The Conductor** (Select, **strong**): pick the pages and get Robin's go on the list → page list in `notes.md`
   - Only pages published on the default branch. Unpublished drafts change under you.
   - Rank by teaching value: a worked calculation, a process with steps, a comparison of two
     cases, a rule with a threshold. Skip pages whose point is pure prose.
   - Ask the content strand for its ranked list of live pages that need a figure; it sends one
     after each merge.
   - One sentence per page on what the figure shows, using the page's own numbers. Robin
     answers with a go on the whole list or a subset. That go covers wiring those pages and
     merging them.

3. **Analizer 2000** (Librarian, **standard**): OPTIONAL, only when the profile names a reference source: index it and pull a few frames per topic into the private frames dir → `<frames_dir>/index.md`, `pilot-moments.md`
   - Hard privacy rules in the prompt: opaque ids only, real names only in a private mapping file
     in the frames dir, no transcript text in the reply, nothing written under `~/Code`, frames
     dir outside the repo and outside RUN_DIR.
   - Use transcripts or lesson summaries to find chart moments, then extract 3 to 5 frames per
     moment (`ffmpeg -ss <t> -i <video> -frames:v 1 -q:v 3 <file>.jpg`) and drop frames with no chart.
   - Reply with counts and gaps only.

4. **The Cleric** (Brief-writer, **standard**): OPTIONAL, same condition: look at the frames and write one figure brief per page in original words → `RUN_DIR/<strand>/briefs/<slug>.md`
   - Describe the CONCEPT, never the instance: no coin, ticker, date, timeframe or price level
     from a frame, no source name, layout, colours or annotation style, no transcript text, no
     shape that could recreate a frame.
   - Every labelled value comes from the page text, quoted with its source line. A teaching
     point the page does not support goes under "Ideas outside the page" for the content strand.
   - Brief sections: figure job, type (schematic vs real data, and why), must show, values with
     the arithmetic to assert, generic geometry, must NOT show, caption under 40 words, alt text,
     ideas outside the page.
   - Then a **Gate**: the Conductor greps the briefs for tickers, dates, exchange names and any
     source names before the drawer sees them.

5. **The Mage** (Drawer, **standard**): draw each figure in code from the page's own numbers, assert every value, render SVG and a 2x PNG, commit and push the figures branch with no PR → `defs/<slug>.ts`, `samples/<slug>.svg`, `samples/<slug>.png`, `samples/captions.json`
   - The prompt says: work only from the page text (and the brief, if any). Never open the
     frames dir. Draw from scratch.
   - Before the spawn, update the figures branch from the default branch so the drawer reads
     current page text. If a content merge changes a page mid-draw (it happened: a group cap
     went from 2% to 1%), message the drawer before it finishes that figure.
   - Every figure is a pure function. It recomputes the page's sums and throws on any mismatch,
     and maps every drawn level or bar back through its axis to check it lands on its value.
   - Keep the figure sparse: about 25 words inside it at most, the explanation in the caption.
     The restyle copies text faithfully only when there is little of it.
   - The page wins over the Conductor's request. The drawer once corrected the brief: a 4.7%
     on the page was the chance of six straight losses, not the 5.9% drawdown.
   - Run the profile's SVG checks (size, title and desc, no em dash, no external refs) and the
     caption check (under 40 words, factual alt).
   - Reply: per figure, path, size and the asserted values in one line; anything the page did
     not support.

6. **The Conductor** (Look, **strong**): FIRST RUN ON A PROJECT ONLY: restyle one dense figure in 3 or 4 candidate looks with `scripts/figure-restyle.sh` (a different style file each), check each as in step 8, and let Robin pick → profile `style_file`
   - What the cryptowatchtools test showed: a look that is told it may redesign the layout
     misspells labels (the editorial look wrote "planred"); a light textbook look invents a
     figure number; a faithful look barely changes anything. Robin picked the hand-drawn
     whiteboard. Expect a similar spread.
   - Generated art bills to Robin's ChatGPT plan through Codex, not an API key. Check before
     reaching for a site's own OpenAI key: on cryptowatchtools it had no credits.

7. **The Conductor** (Restyle, **standard**): run `scripts/figure-restyle.sh <png> <out.png> --style-file <profile style> --webp ...` per figure, in parallel waves of about five → `looks/<look>/<slug>.png`, `looks/<look>/<slug>.webp`
   - The script holds the content rules (every label character for character, every mark in the
     same relative place, nothing added). Only the style varies by project.
   - Each call takes 1 to 3 minutes. Save state to the notes file before a long wave if the
     session window is high; a quota cut once landed between the restyle and its check.
   - PNG masters stay out of git; commit the WebP set to the figures branch if useful as a
     record.

8. **The Conductor** (Restyle check, **strong**): read each restyled PNG beside its source PNG and its page, label by label and level by level, and record PASS or FAIL per figure → `notes.md`
   - **Tolerance.** Text: zero differences. Any misspelling, dropped or added word, changed
     number or invented title or figure number fails. Marks: a line, bar or level may sit
     slightly off its code position only if its label is correct, it keeps its order against
     every neighbouring level, and it does not cross onto a labelled value that would change the
     reading. The one drift accepted so far: a pause line drawn about 11 px low onto a nearby
     gridline (0.15% of the value), accepted because its label and the claim were right.
   - On FAIL, re-run the restyle once or twice. If it still fails, ship the code-rendered PNG
     converted to WebP, or drop that figure from the wave and say so.

9. **Worktree**: a fresh wiring branch and worktree off the latest default branch, after checking the content strand's open PRs → profile `worktrees`
   - Never wire on the figures branch; it carries tooling that is not meant for main.

10. **The Conductor** (Wiring, **standard**): copy each WebP beside its page and insert the image line with alt and caption per the profile's wiring convention → page files, assets
    - Do it with a short script per wave: a map of page key to the heading the figure goes
      before, assert the heading exists, refuse any caption or alt with a straight double quote
      or an em dash.
    - If the site has never served this image format, add it to the asset pipeline (on
      cryptowatchtools, a `.webp` glob in `assets.ts`) and confirm the built page references
      the hashed file.
    - When a figure replaces an older one, grep the repo for links to the old file before
      deleting it.

11. **Gate**: run the profile's check commands; all must pass before the PR
    - Includes the full site check with a build, the tests, any originality or terms stamp
      (fresh), and a typecheck against the baseline.
    - A lint error caused by the figure's file name or alt text (not the page) is fixed in the
      alt text and logged as a tooling carry for the content strand, not suppressed.

12. **The Conductor** (Ship, **standard**): create the issue (pages and acceptance), commit with a message naming the pages, open the PR with `Closes #N` and a table of page and what its figure shows → issue, PR
    - Acceptance in the issue: file beside each page, every number matches its page, checks
      pass, each page serves its image after deploy.
    - The PR body states how the figures were made (code-drawn and asserted, restyled, checked
      by eye) and, if frames were used, that none shipped.

13. **Gate**: merge per the profile's merge protocol: pre-merge notice, newest CI run green, merge commit with `--match-head-commit` (never squash), deploy watched, every page and image curled
    - Robin's go from step 2 covers this merge. Hold only if he said "let me review", or the
      content strand has a PR merging first.

14. **The Conductor** (Close-out, **standard**): message the merge SHA to the content strand, add one line to the shared run log, update the strand's notes and handoff → `RUN_DIR/log.md`, `notes.md`, `HANDOFF.md`
    - The handoff names the current session ids, branches, worktrees, uncommitted scratch, and
      the next pages waiting for figures. Rewrite it whenever it stops matching reality.

## Done criteria

- Every page in the wave is on the default branch with its image line, alt and caption.
- Each figure's def asserts every labelled value and the render passes.
- Each restyle has a recorded PASS against its source and page.
- The profile's checks passed on the PR head; the newest CI run passed; it merged as a merge commit.
- The deploy passed and every page returns 200 with its image served at the expected type.
- The merge SHA is in the run log and the content strand has been told.

## Edge cases and fallback

- **Page changes after drawing.** Re-read the page on the wiring branch; if a number moved,
  fix the def, re-render, re-restyle that figure. Never ship a figure drawn against an older page.
- **Restyle keeps failing.** Ship the code-rendered PNG as WebP or drop the figure (step 8).
- **Quota cut mid-wave.** Notes first, then work. A takeover session reads the notes and
  HANDOFF, checks uncommitted changes are only the wiring and the stamp, re-checks every
  shipped image by eye, then finishes the gate.
- **Content strand merges first.** Rebase or rebuild the wiring branch on its SHA with a fresh
  stamp, re-run the gate.
- **No reference source, or none for a topic.** Draw from page numbers only; that worked for
  11 of 14 figures.
- **Paid generation.** Generated decorative art (Midjourney, Higgsfield) is a separate yes from
  Robin. This workflow's restyle runs on the ChatGPT plan and needs no extra approval.

## Observability

- Strand diary: `RUN_DIR/<strand>/notes.md`, one timestamped line per event.
- Resume card: `RUN_DIR/<strand>/HANDOFF.md`.
- Restyle calls: `scripts/figure-restyle.sh --log <file>` appends one line per call.
- Merges: the PR, the deploy run, and the merge-SHA line in `RUN_DIR/log.md`.

## What cost time on the first run

- A forked session thought it was the content session and resumed the content writer
  (18:26 to 18:31Z, 2026-10-15). Two writers wrote the same draft files; the content strand had
  to redraft. Step 1's ownership rule exists for this.
- The site's OpenAI key was tried first for image generation and had no credits. Codex's
  `image_generation` on the ChatGPT plan worked. `codex exec -i` takes several files, so a
  prompt after `-i` is read as an image; the script puts the prompt first.
- A Codex design-spec memo on the code figures was written and never used once the restyle
  route worked. Skip it.
- The editorial look misspelled a label. Looks that may redesign the layout are not safe for
  number-dense figures.
- `learn:check` flagged two errors that were the risk lint reading `portfolio-risk.webp` in the
  image URL. The fix was alt wording; the lint should skip image URLs.
- The original HANDOFF.md went stale within hours (it still described SVG-only figures). Step
  14 rewrites it at the end of every wave.

## Project profiles

| Profile | Project | Look |
|---|---|---|
| [cryptowatchtools-learn](../config/illustrate-profiles/cryptowatchtools-learn.md) | rheos/cryptowatchtools `/learn` manual | whiteboard |
