# CryptoWatchTools Redesign — run as an agentic build (existing-project mode)

Date: 2026-06-14

## One-liner

Take the CryptoWatchTools rebrand + redesign and run it through the framework the way it's
meant to run: a `feature` pass in **existing-project mode** (writers' room → design handoff →
vetted prompts), then `execute-plan` (build party → reviewed diffs → dev gate). Fold the
Vercel cost cut into the same wave, because the redesign and the cost fix touch the same files.
This is the first time the framework points at the `crypto-site` repo, so it's also a real test
of existing-project mode and the Cleric design loop against a live, shipping product.

## Why this one (and why now)

**The honest reason it exists.** Asked to "create a spec to redesign the site," I wrote
`crypto-site/docs/redesign-brand-spec.md` solo — a requirements + architecture + design brief.
That is precisely the artifact the writers' room produces (Analizer 2000 → The Architect →
The Cleric). I shortcut the pipeline: no Analyst scoping the edge cases, no Architect pressure-
testing the structure, no Challenger reviewing it cold, no Cleric briefing Claude Design through
the real handoff. The spec is a decent *seed*, not a framework output. This idea is the
correction: run it properly, and get the artifacts the framework is supposed to emit.

**Three things make now the right moment:**

1. **The seed already exists.** `redesign-brand-spec.md` gives the Analyst and Architect a strong
   starting brief (brand foundation, restructured IA, the freshness model, screen-by-screen
   direction, hard constraints). They sharpen and challenge it rather than starting cold.

2. **Two concerns share the same files, so one wave is cheaper than two.** The redesign
   consolidates six overlapping scanner/funding routes into a few workspaces; the cost cut
   (`crypto-site/docs/vercel-cost-reduction-plan.md`) rewrites those same loaders to read cron-
   computed snapshots instead of recomputing per poll. Doing them separately means editing the
   same files twice and re-resolving the same merge. The redesign's **freshness model** ("as of
   HH:MM:SS · updated 34s ago" + manual refresh + stale state) is literally the UI that the
   snapshot architecture needs. They are one change.

3. **There's live pressure.** The Vercel team is over 75% of the Fluid Active-CPU free tier and
   getting "upgrade to avoid disruption" emails (May 19, Jun 2 2026), with CryptoWatchTools as the
   sole driver. The cost cut isn't optional; pairing it with a redesign people will notice is the
   moment to ship both.

## What this exercises in the framework

This is a good build to run because it stresses the parts of the framework that greenfield runs
don't:

- **Existing-project mode** against a repo the framework has never touched: cross-repo
  orientation, scoping each agent to the right surface, building within the current stack
  (React Router v7 SSR, Tailwind v4, shadcn/ui) rather than proposing a rewrite.
- **The full Cleric design loop** — brief → `[DESIGN HANDOFF]` checkpoint → Claude Design →
  ingest the bundle → `design/manifest.md` → Spellwright consumes it. A rebrand with real screens
  is exactly what that loop is for, and it hasn't been run end-to-end on a shipping product.
- **Folding two plans into one** — the Architect has to reconcile the redesign brief and the cost
  plan into a single coherent build order, not staple them together.
- **The build party on a real deploy target** — Mage (the React/UI work), Systemsmith (the loader
  rewrites + cron snapshot store), Mechanic (Vercel `crons`, env, the dev→prod boundary). With the
  **production boundary** enforced: nothing ships past dev until Robin confirms.

## Inputs that already exist (don't regenerate these)

- **`crypto-site/docs/redesign-brand-spec.md`** — the seed brief: brand idea, color/type system,
  restructured IA (8 nav items → 5 workspaces), the freshness model, screen-by-screen direction,
  the five open decisions, hard constraints.
- **`crypto-site/docs/vercel-cost-reduction-plan.md`** — the snapshot architecture, target routes,
  the polling/caching changes, verification steps.
- **`crypto-site/logo/`** — the new mark (blue / transparent / mono-white) + avatar, made
  2026-06-13. The brand is built *around* these; design refines, doesn't reinvent.
- **`crypto-site/cryptowatchtools/docs/`** — `funding-analyst-thesis.md` (the parked paid hook the
  design leaves a slot for), `og-image-design-spec.md` (prior art), `TECHNICAL_AUDIT.md`.

## The run shape

**Phase A — `feature` workflow, existing-project mode.** First create
`crypto-site/project-context.md` from `templates/project-context-template.md` with
**Mode: existing project** and a Workspace Map (the `cryptowatchtools` app, the `cron-jobs`
collectors, the `discord-bot`, the Vercel deploy). Then:

1. **Analizer 2000** — scope the redesign + cost cut as one change against `redesign-brand-spec.md`
   and `vercel-cost-reduction-plan.md`; pin down edge cases (the funding color-semantics caveat,
   the dead/duplicate routes to delete, the Luna-vs-HAL rename) → `spec.md`.
2. **The Architect** — reconcile both docs into one design model + build order; decide how the
   freshness UI and the snapshot store meet → `spec.md` (Architecture), `plan.md`.
3. **[DESIGN-MODEL CHECKPOINT]** — Conductor shows Robin the design model + the five decisions
   from the brief (name, Luna vs HAL, dark-only v1, paid-tier slot, display typeface) and waits.
4. **The Challenger** (round 1) — review spec + plan cold.
5. **The Cleric** (brief) — DESIGN: NEEDED. Brief Claude Design from the brand foundation + the
   key-screens list → `[DESIGN HANDOFF]` checkpoint.
6. **The Cleric** (ingest) — read the returned bundle → `design/manifest.md` (tokens as Tailwind v4
   `@theme` / `:root` values, per the brief's handoff format).
7. **The Spellwright** — spec + plan + manifest → `prompts.md`.
8. **The Challenger** (round 2) — review the prompts.

**Phase B — `execute-plan`.** Carry `plan.md` into a scoped prompt folder beside the plan, gate
it, then the build party builds each part with a Challenger review per diff, stopping at dev.

## Scope

**In:**
- Brand system built on the existing mark (tokens, type, the night-canvas palette, Luna Gold accent).
- IA consolidation: Markets · Movers · Funding · Watchlists · Luna · Settings; delete the
  duplicate/dead routes (`funding-scanner-mysql`, `test-price-indicator`, the Convex-wired
  `watchlist-export`).
- The freshness model + the snapshot architecture from the cost plan, built together.
- Rebuilt key screens (Home, Pricing, auth, dashboard shell, Movers, Funding, Markets, Watchlists,
  Luna), real Settings, a real Pricing page with the "Pro — coming soon" slot.
- The Luna rename (retire "HAL 9000").

**Out:**
- The AI Funding Analyst product itself (parked — design the entry point + upsell slot only).
- Light mode (dark-only v1).
- Net-new features beyond what exists. Rebrand + restructure + cost fix, not expansion.

## Suggested phasing (for the Architect to refine)

1. **Tokens + shell.** Brand tokens into `app.css`, type fix (Inter vs the declared `-apple-system`
   mismatch), the dashboard shell + sidebar (5 items), the shared freshness marker component.
2. **Snapshot backend + Movers.** The cron snapshot store + loader rewrites (cost plan Phase 2),
   the merged Movers scanner reading snapshots, the unified empty/loading/error/stale states.
3. **Funding + Markets.** The merged Funding workspace (tabs) and the Markets macro dashboard.
4. **Public surfaces.** Home, Pricing (with the paid slot), auth split layout — kept static/cacheable.
5. **Luna + Watchlists + Settings.** The renamed, guided assistant; the promoted watchlist tool; real Settings.

## Decisions to resolve (carried from the brief, surface at the design-model checkpoint)

1. Keep the name **CryptoWatchTools** (recommended) vs rename.
2. Assistant name **Luna** (recommended, matches the moon) vs HAL 9000.
3. **Dark-only v1** (recommended) vs ship light mode too.
4. Paid tier: design the **slot only** (recommended) vs build billing now.
5. Display typeface: Space Grotesk (lead) / Clash Display / Inter Tight.

## Risks / watch-outs

- **First run against `crypto-site`.** Add it to `check-drift.sh`'s known installs; the framework
  hasn't oriented in this repo before, so budget time for the Workspace Map.
- **Dead-code minefield.** The repo has duplicate routes, a removed Convex backend still referenced,
  and test routes in nav. The Analyst must inventory what's real before the Architect plans on it,
  or prompts will target files that lie about what they do.
- **Docker + Vercel reality.** Dev runs in Docker; deploy is Vercel `sin1`. The Mechanic owns the
  `vercel.json` `crons` + `CRON_SECRET` work and must not cross the production boundary unprompted.
- **Funding color semantics.** Negative funding is the *bullish* signal — the design and the build
  both have to map color to the trade signal, not the raw sign. Easy to get backwards; call it out
  in the spec and the prompts.
- **Don't let the rebrand balloon.** The temptation is to add features. Hold the "out of scope" line;
  this wave is identity + structure + cost, nothing more.

## Relationship to existing work

- **`redesign-brand-spec.md`** — the seed brief this run sharpens into real framework artifacts.
  It was produced solo; this idea routes it back through the writers' room and the design loop.
- **`vercel-cost-reduction-plan.md`** — folded in, not run separately. Its snapshot model is the
  backend the redesign's freshness UI sits on.
- **Ministry of Flow (aka Logistics) / Stakeholder Companion** — once this runs, `crypto-site` emits the same
  `state.json` / `log.md` artifacts those tools read, so the redesign build becomes another live
  run they can watch and report on. A useful real-world run for both to consume.
