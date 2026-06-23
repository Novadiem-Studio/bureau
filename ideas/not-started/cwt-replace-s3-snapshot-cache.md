# CryptoWatchTools: replace S3 scanner snapshots with in-memory cache

**Priority:** medium — cost + simplification. Net deletion of moving parts; no new external dependencies.
**Scope:** `cryptowatchtools/` web app only.

## Context — why do this

The S3 scanner-snapshot system was built to cut **Vercel** load: serverless functions share no
disk and get torn down between requests, so a cron precomputed scanner data and wrote it to S3
where any function instance could read it. S3 was never the right tool — it was the only shared,
persistent store available on a stateless platform.

Two things have changed:

1. **The app now runs as a single long-running Node process** on the 2 GB Lightsail box
   (`deploy-selfhost.sh` → systemd service `cryptowatchtools`, started via `react-router-serve`;
   MySQL co-located on the same box at `52.76.172.45`). Vercel is now rollback-only
   (`vercel.json` `git.deploymentEnabled: false`, auto-deploy off). On a stateful server,
   module-level memory persists across requests — the existing `mysql` pool
   (`app/lib/mysql-client.server.ts:4`) and `ExchangeFactory` (`app/lib/exchanges/exchange-factory.ts:12`)
   singletons already rely on exactly this.
2. **Vercel load is no longer the concern; the S3 bill is.** And the system as configured gives
   nothing back for it.

### The system is currently the worst of both worlds

- The cron runs **once a day** (`vercel.json` cron `0 0 * * *`), but the snapshot is considered
  **stale after 3 minutes** (`app/lib/freshness.ts:11`, `AGING_THRESHOLD_MS = 180_000`).
- So for ~23 h 57 m of every day, each scanner request does a full S3 GET (downloads the body),
  discards it as stale, and queries MySQL anyway (`most-negative.tsx:8-20`,
  `volatility-scanner.tsx:64-96` — read snapshot, then fall through to live compute).
- Result: paying S3 GET + cross-region egress (bucket `us-east-1`, app in Singapore) on nearly
  every request, for **zero** DB-load reduction.

### The fix

Replace the S3 round-trip with an **in-memory read-through TTL cache** (with single-flight to
avoid cache stampedes). The DB then gets hit at most once per TTL per dataset regardless of
traffic — the Lightsail offload the snapshot system was supposed to provide — with no S3, no disk,
no separate cron. Cached data is single-digit MB and bounded by the instrument count, trivial
against the box's RAM (MySQL's buffer pool is the real memory consumer, not this).

## Key findings (from codebase exploration)

- **No existing TTL/memoize/single-flight utility** exists — build one. Mirror the
  `globalThis` + `Symbol.for(...)` pinned-singleton idiom in `app/lib/server-init.server.ts:7-8`
  so HMR / re-import doesn't duplicate the cache.
- **The RSI snapshot is written but never read.** `SNAPSHOT_RSI` / `RsiSnapshot` appear only in the
  store definition and the cron writer (`refresh-scanners.tsx:330,348`) — no reader. Drop it
  entirely; no RSI cache needed.
- **The four funding readers can share one cached base.** The cron already computes all four lists
  (`getMostNegativeFundingRates`, `getWorseningNegativeRates`, `getStillNegativeButImproving`,
  `getTurnedPositiveFundingRates`) plus one shared `getFundingMultiTfChanges` call across the union
  (`refresh-scanners.tsx:216-313`). Each reader returns its slice.
- **Movers is one comprehensive base, filtered per request.** Compute `checkVolatility` with
  `percent: 0` (all 10 timeframes, nothing filtered) + `checkVolume` + `getLatestPriceTimestamp`,
  then apply the per-request `percent`/`timeframe` params in memory — exactly what the snapshot read
  path already does (`volatility-scanner.tsx:75`).
- **`computedAt` only ships on the rarely-hit snapshot branch today**, so the `FreshnessMarker`
  (`app/components/freshness-marker.tsx`) gets no timestamp ~all the time. The cache has a natural
  "last computed" time → emit `computedAt` on every response; the marker finally works everywhere.
- **`hoursToTimeframe` is defined locally** in each reader (`volatility-scanner.tsx:8`,
  `volume-scanner.tsx:16`) — not from the store, so deletion is safe. Duplicated 3×; optional
  consolidation into the shared types module.
- **`@aws-sdk/client-s3` is used only by** `scanner-store.ts` and the two `test-s3.*` smoke scripts.
  Removable. **Watchlist caching does NOT use S3** (`app/lib/vercel-cache.ts` uses `/tmp` via `fs`) —
  leave it alone.
- **CDN headers stay.** `cacheHeaders()` (`app/lib/cache.ts`, `s-maxage=60, stale-while-revalidate=120`)
  is harmless on self-host and still useful on the Vercel-rollback path. The real load reduction now
  comes from the in-memory cache, not the headers.

## Plan

### New files

- **`app/lib/ttl-cache.ts`** — generic read-through TTL cache. One entry per key holding
  `{ data, computedAt }` plus an in-flight promise for single-flight. Signature roughly
  `getOrCompute<T>(key, ttlMs, compute: () => Promise<T>): Promise<{ data: T; computedAt: number }>`.
  Pin the registry on `globalThis` via `Symbol.for("cryptowatchtools.ttlCache")` (mirror
  `server-init.server.ts`). Concurrent misses await the same promise. Default TTL **60 s** (aligns
  with the existing client poll in `app/lib/use-scanner-polling.ts:17` and the old `s-maxage`);
  underlying data only changes every 5–30 min, so 60 s is conservative and tunable.
- **`app/lib/scanner-types.ts`** — move the domain types currently exported by `scanner-store.ts`
  (`Timeframe`, `MoverCoin`, `MoversSnapshot`, `FundingTrend`, `FundingRow`, `DynamicsRow`,
  `FundingSnapshot`) here. Drop `SnapshotEnvelope` (S3-specific) and the RSI types.
- **`app/lib/scanner-cache.server.ts`** — the two cached base builders, each wrapping `getOrCompute`:
  - `getMoversBase()` → comprehensive movers set (reuse `checkVolatility` w/ `percent:0`,
    `checkVolume`, `getLatestPriceTimestamp` from `price-tracker.server.ts` /
    `volume-tracker.server.ts`).
  - `getFundingBase()` → the four lists + one shared `getFundingMultiTfChanges`, reproducing the
    cron's row-building (`refresh-scanners.tsx:216-313`). This is where DRY pays off — the four
    readers stop issuing independent query sets.
  - `getVolumeBase()` → volume-change computed once across the standard timeframe set from the
    `volume_history` table (plus current prices from `price_snapshots`), so the per-request
    threshold percents filter a cached base instead of re-querying. This is the messier one: the
    logic currently lives as inline parameterized SQL in `volume-scanner.tsx` and needs lifting
    into this module and generalizing from "the requested windows" to "all standard windows."

### Modified readers (filter/shape the cached base per request; emit `computedAt`)

`app/routes/api/most-negative.tsx`, `worsening-negative.tsx`, `improving-negative.tsx`,
`turned-positive.tsx` → call `getFundingBase()`, return the relevant slice.
`app/routes/api/volatility-scanner.tsx` → call `getMoversBase()`, apply per-request
`percent`/`timeframe` filtering (the logic already present in its snapshot branch).
`app/routes/api/volume-scanner.tsx` → call `getVolumeBase()`, apply the per-request threshold
percents in memory; drop its vestigial `scanner-store` imports (re-point the `Timeframe` type to
`scanner-types.ts`). Keep its stablecoin exclusion and top-100 slice.
Remove the `readSnapshot` / `snapshotFreshness` blocks and the now-redundant separate live path.

### Deletions

- `app/lib/scanner-store.ts` (S3 client + read/write/freshness + key constants).
- `app/routes/api/cron/refresh-scanners.tsx` and its registration in `app/routes.ts:49`.
- `crons` array in `cryptowatchtools/vercel.json`.
- `@aws-sdk/client-s3` from `package.json`; delete `test-s3.js`, `test-s3.mjs`.
- Optional cleanup: `aws-s3-policy.json`, dead `AWS_*` / `S3_*` env vars in `.env*`, and the CLAUDE.md
  line describing `AWS_*` as "S3 credentials for caching."

### Preserve (do NOT touch)

`app/lib/freshness.ts` and `app/components/freshness-marker.tsx` (used by `funding.tsx`, `movers.tsx`,
`markets.tsx`, `site-header.tsx`); `app/lib/vercel-cache.ts` and the watchlist route; `cacheHeaders()`.

## Open decisions (defaults chosen — flip if you disagree)

1. **Funding row shape.** The deleted cron computes *richer, more-correct* funding rows (trend
   derived via `deriveTrend`, plus `improvementScore` / `hoursElapsed`). The current live-fallback
   paths — what users actually get almost all the time today — emit *thinner* rows with **hardcoded
   trend strings that don't even match the `FundingTrend` type** (a latent bug:
   `worsening-negative.tsx:43` etc.).
   **Default: adopt the cron's richer compute** — it fixes the bug, matches the shape the snapshot
   path served, and consolidates the queries. Cost: a quick visual check of the funding dashboard
   since the displayed trend values change. (Alternative: preserve the thin shape exactly for zero
   behavior change, carrying the type-mismatched trends forward.)

2. **Volume scanner. — DECIDED: include it.** It already opts out of S3 (`volume-scanner.tsx:72`,
   queries `volume_history` with inline parameterized SQL), so shutting down S3 didn't strictly
   require touching it — but it hits the DB uncached on every request, which is load on the 2 GB box.
   It now gets the same in-memory treatment via `getVolumeBase()` (see Plan above). Note this is the
   one piece needing an actual SQL lift — generalizing the inline per-request query into a
   compute-all-standard-windows-once base.

## Verification

1. `npm run typecheck` — confirms all `scanner-store` imports are re-pointed and nothing references
   the deleted symbols.
2. `npm run build` — confirms `routes.ts` no longer references the deleted cron module.
3. Run locally (`docker-compose up`, app on `:3000`) and hit each endpoint twice:
   `/api/most-negative`, `/api/worsening-negative`, `/api/improving-negative`,
   `/api/turned-positive`, `/api/volatility-scanner` and `/api/volume-scanner`
   (with and without `?<tf>=<pct>` params).
   - First call computes (watch for one set of DB queries in logs); second call within the TTL
     window returns from memory (no DB queries). This is the load-reduction proof.
   - Each response includes a `computedAt`; load the funding + movers dashboards and confirm the
     `FreshnessMarker` shows a live "Ns ago" that ticks over and refreshes after the TTL.
4. Log the serialized byte size of each base on first populate to get a measured RAM figure
   (expected single-digit MB).
5. Grep the repo for `@aws-sdk`, `readSnapshot`, `SNAPSHOT_` → only `node_modules`/`build` hits remain.
6. Deploy via `deploy-selfhost.sh`; confirm no S3 calls in app logs and the scanners still populate.
