# Illustrate profile: cryptowatchtools /learn

Project profile for `workflows/illustrate-pages.md`. Everything specific to the /learn manual in
`rheos/cryptowatchtools` lives here; the workflow's generic steps point at these fields by name.
Derived from the run that shipped figures on 14 pages (rheos/cryptowatchtools#25 and #31,
2026-10-15 to 2026-10-16). To illustrate another project, copy this file and replace each field.

## Target

- **repo:** `rheos/cryptowatchtools`, checkout `/Users/robin/Code/novadiem/crypto-site/cryptowatchtools`.
  `main` auto-deploys (GitHub Actions `deploy.yml`, self-hosted Lightsail box).
- **content_dir:** `learn/content/` (one `<section>/<slug>.md` per page). A page is "published"
  when it is on `origin/main`.
- **run_dir:** `.bureau/runs/20261012-learn-manual/`. The strand keeps its own diary in
  `RUN_DIR/illustrations/notes.md` and its resume card in `RUN_DIR/illustrations/HANDOFF.md`.
  It writes to the shared `RUN_DIR/log.md` only for merge SHAs and decisions the content strand
  needs. RUN_DIR is rsynced by `deploy-selfhost.sh`, so nothing private goes in it.
- **worktrees:** `.society-worktrees/learn-illustrations` (branch `learn/illustrations`, the
  drawing tooling) and one fresh `.society-worktrees/learn-figures-wiring-<n>` per wiring PR.

## Figure tooling

The library is **not on main**. It lives on branch `learn/illustrations` under `learn/figures/`:

- `lib/` (style, svg, axis incl. `brokenAxis`, marks, candles, flow, figs, check). `check.ts`
  holds `checkSvg` (under 12 KB, `<title>` and `<desc>`, no em dash, no external refs, no
  fonts or `<image>`), `checkCaption` (caption under 40 words, alt at least 40 characters, no
  em dash) and `expectEqual`. `figs.ts` holds `checkWords` (at most 30 words inside a figure).
- `defs/<slug>.ts`: one pure function per figure, data object in, SVG string out, and it throws
  when a drawn value disagrees with the page arithmetic. Each def also exports its caption and alt.
- `render.ts`: `npx tsx learn/figures/render.ts [--only=a,b] [--no-png]` from the worktree.
  Writes `samples/<name>.svg`, a 2x `samples/<name>.png` via local headless Chrome (`CHROME_BIN`
  overrides), and merges captions into `samples/captions.json`. A new figure needs a row in
  `buildSamples()` with its viewBox size.
- `looks/`: restyle outputs. `looks/whiteboard/*.webp` (first five) is committed;
  `looks/whiteboard/wave2/` and every PNG master are uncommitted scratch in that worktree.

Before a drawer starts, merge `origin/main` into `learn/illustrations` so it reads current page text.

## Reference source (optional brief path)

- **frames_dir:** `/Volumes/Bertha/learning/_learn-frames/` on Robin's private drive. Opaque ids
  only (`vNNN-mmss-k.jpg`); the real names are only in `mapping.private.md` there, and the
  moment index is `pilot-moments.md`. Outside the repo AND outside RUN_DIR.
- **Rule (Robin, 2026-10-15T18:27:57Z):** course video frames are reference only. The
  brief-writer may view them; the drawer never does. Nothing from a frame is committed, shipped
  or traced. The spec's FR13 still applies: every figure is drawn from scratch.
- Never name the course, its author, a video file or transcript text in a brief, a commit, a
  PR or any file under `~/Code`.
- Coverage when last indexed: 236 of 952 videos linked to transcripts; 715 have none.
- Since the first three briefs, figures have been drawn from page numbers alone. Use the brief
  path only when a page's figure needs a teaching point the page text does not make obvious.

## Look

- **look:** whiteboard (Robin picked it on 2026-10-16 over faithful dark, editorial and
  light textbook).
- **style_file:** `config/illustrate-profiles/cryptowatchtools-learn.style.txt`
  (dark slate `#15171a`, marker strokes, the site's colour roles: red stops and losses, amber
  levels and caps, blue entry, white text).
- **webp:** `--webp --webp-width 1400 --webp-quality 82`. Shipped sizes ran 59 to 126 KB.

## Wiring convention

- `<slug>.webp` beside `<slug>.md`, referenced on its own line as
  `![<alt>](./<slug>.webp "<caption>")`, inserted before the heading named in the wiring plan.
- Caption and alt come from `samples/captions.json`. Neither may contain a straight double
  quote (it would end the title) or an em dash.
- Alt says what the diagram shows ("A bar chart of..."), never "image of".
- `app/learn/content/assets.ts` globs `learn/content/**/*.webp` (added in #25). A new image
  format needs the same glob.
- Content batches add no figures. The figures strand owns the convention.

## Checks (the Gate step)

Run from the wiring worktree, in order:

```bash
npm run -s learn:gate
npm run learn:check
npm run learn:test
npm run -s learn:terms -- --staged
npx tsx learn/tools/typecheck-compare.ts --run
```

- `learn:gate` re-stamps `learn/originality/pass.json`. The stamp covers the content hash, so
  every wiring commit carries a fresh stamp, and a rebase onto a new main needs a new one.
- `learn:check` must report 0 errors **with the build**; also grep
  `build/client/learn/<page>/index.html` for the hashed `.webp` src.
- Expected at the time of #31: 292/292 tests; typecheck errors only in untouched
  `app/routes/api` files (baseline).
- **Known false positive:** `risk/risk-above-2pct` reads the image URL, so "risk" in a
  filename (`portfolio-risk.webp`) plus "account" in the alt flags any percentage above 2.
  Reword the alt ("balance") until the lint skips image URLs.

## Merge protocol with the content strand

A content Conductor publishes text batches to the same `main` in parallel. Both strands
re-stamp `pass.json`, so merges must be ordered:

- Whoever merges to main tells the other; the other rebuilds its branch on the new SHA with
  a fresh stamp per commit.
- Before merging: `gh pr list --state open` and message the content session if it has a PR
  in flight. If it has none, go.
- CI: `learn-checks` can run twice on one SHA and the first gets cancelled. Merge only when
  the NEWEST run is `success`:
  `gh api repos/rheos/cryptowatchtools/commits/$SHA/check-runs -q '[.check_runs[]|select(.name=="learn-checks")]|sort_by(.started_at)|last|.conclusion'`
- Merge: `gh pr merge <n> --merge --match-head-commit <sha>`. Never squash.
- After: wait for `deploy.yml` on the merge SHA (`gh run watch --exit-status`), then curl each
  page (follow the trailing-slash redirect) and its hashed `.webp` for `200 image/webp`.
- Message the merge SHA to the current content session and add one line to `RUN_DIR/log.md`.
  The current session ids are in `RUN_DIR/illustrations/HANDOFF.md`, not here.
- After each content merge, the content session lists the newly published pages that need a
  figure. That list feeds the Select step.
