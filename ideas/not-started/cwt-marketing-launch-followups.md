# CryptoWatchTools — marketing-site launch follow-ups

**Created:** 2026-06-24 · **Source:** design-build run `20260622-cwt-marketing-design-build` (shipped to prod 2026-06-24).
**Scope:** `cryptowatchtools/`. These are the carried, non-blocking items from the marketing-site rebuild that went live, plus the now-live redesign work that this run did NOT verify.

## Context
The marketing-site rebuild (home/pricing/auth/SEO/mobile) shipped to `cryptowatchtools.com` on 2026-06-24 via `deploy-selfhost.sh` (merged into `redesign-build` → built locally → rsync to the Lightsail box → systemd restart). Deploying necessarily shipped the **whole `redesign-build`** (44 commits of in-progress redesign + the marketing layer), because the marketing pages depend on redesign-build's foundation and can't be deployed alone. The live site was the old pre-redesign app until this deploy. Rollback path: repoint the `cryptowatchtools.com` A record back to Vercel (still live).

## Follow-up items

1. **Raster PNG OG card** (priority: high — affects every shared link). `og:image` still points at `public/og-image.svg`; most social scrapers (Facebook/LinkedIn/Slack/Twitter) won't render SVG, so link previews show no image. Create a ~1200×630 PNG OG card from the brand (see `cryptowatchtools/docs/og-image-design-spec.md`) and point `og:image`/`twitter:image` at it in `home.tsx` `meta()`.

2. **Wire the live hero squeeze-count** (coupled — do WITH the S3-cache refactor). The hero eyebrow is a static pill ("funding scanner · 500+ coins · 6 exchanges"); the designed live copy is "N coins squeezing right now". `HeroBanner` already exposes optional `squeezeCount?: number` + `squeezeAsOf?: string` props (unwired). When `agent-framework/ideas/not-started/cwt-replace-s3-snapshot-cache.md` ships `getFundingBase()` (correct `deriveTrend` count + working `FreshnessMarker`), pass the count from the `home.tsx` loader → zero structural change. Funding is ~30-min fresh, so "right now" is honest.

3. **Verify the rest of the now-live redesign** (priority: high — it's live but unverified). Only the marketing layer went through this run's review. The other ~44 `redesign-build` commits (dashboard/admin/scanner/API routes) shipped to prod unverified and carry **39 pre-existing `tsc` errors** (in `dashboard/admin/*`, `api/*`, `tools/*`, `react-router.config.ts` — see the run's `baseline-typecheck.txt`). QA the live dashboard/scanners end-to-end and clear those type errors.

4. **Mobile sign-in band order** (nit). On mobile, sign-in renders the form above the brand band; manifest §4 mobile suggests the brand band on top. `auth-brand-panel.tsx` / `sign-in.tsx`.

5. **`WordmarkLockup` light-theme token** (nit, latent). `theme="light"` maps `primaryColor` to `var(--background)` (a dark-canvas token); only matters once an on-white lockup ships (email/social). Introduce real light tokens or remap then.

6. **Production box cleanup** (ops). The deploy rsynced another run's `.society-worktrees/20260614-cryptowatchtools-redesign/` source tree to the box as inert bloat (the app runs from `build/server/index.js`; the nested source is never imported). Remove it from the box and consider adding `.society-worktrees`/`.bureau-worktrees` to `deploy-selfhost.sh`'s rsync `--exclude` list so future deploys don't re-ship worktree dirs.

## Close-out actions (bureau-side, separate from cryptowatchtools)
- `origin/redesign-build` synced to the deployed merge commit — **done at close-out** (so the remote matches prod).
- **PENDING — upstream port (same-day rule):** the new `design-build` workflow (`workflows/design-build.md` + its `workflows/index.md` row) and this run's lessons must be committed + pushed to the canonical bureau repo. Needs a *focused* commit — the bureau working tree has unrelated WIP (write-article workflow, CLAUDE.md run-dir changes), so don't `git add -A`. Run lessons are already saved as bureau memories: [[verify-infra-against-ground-truth]], [[worktree-vite-needs-npm-ci]], [[cwt-s3-cache-teardown-in-pipe]].
