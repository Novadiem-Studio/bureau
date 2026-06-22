# Architect → Challenger: Recurring Patterns & Pre-Flight Checklist

Synthesized from 9 Challenger passes across 8 bureau runs (2026-06-14 → 2026-06-22).
Each finding was tagged by artifact (where it lived) and pattern (what kind of problem it was).

---

## Pattern Frequency Table

| Pattern | Count |
|---------|-------|
| missing-edge-case | 24 |
| internal-contradiction | 22 |
| wrong-api-shape | 18 |
| under-specified | 17 |
| wrong-call-site | 12 |
| deployment-path-gap | 9 |
| ac-implementation-mismatch | 8 |
| stale-name | 8 |
| deferred-not-documented | 7 |
| external-dependency-unstated | 5 |
| env-config-unstated | 5 |
| import-missing | 5 |
| test-coverage-gap | 4 |
| async-sync-mismatch | 3 |
| reuse-missed | 2 |
| false-positive-risk | 1 |
| caller-cant-supply | 1 |

---

## Top Patterns Described

**missing-edge-case (24)**
The spec or prompt describes the happy path and leaves boundary conditions — null inputs, platform-specific branches, zero values, oversize inputs — for the implementer to infer. Concentrates wherever input constraints are stated nowhere: symbol batch limits, optional fields, empty query strings, platform checks.
Example: `threshold=0 silently mislabels volatility data` — spec never stated what to do when threshold resolves to zero.

**internal-contradiction (22)**
Two places in the same artifact assert mutually exclusive facts — a count, a name, a behavioral rule. Surfaces in specs that evolved through revision without a reconciliation pass and in plans not re-read against the spec after a change. The spec gets updated at a checkpoint; the old version survives in a different section.
Example: `Prompt 04 self-contradicts '400 symbols max' then '100'` — both limits in the same prompt.

**wrong-api-shape (18)**
A prompt or spec references a field, endpoint, return type, or call signature that doesn't match live code — wrong field name, wrong response envelope depth, or a type mismatch. Appears when prompts are authored from memory or a stale spec rather than from the actual codebase.
Example: `apiFetch(...) returns raw Response not parsed JSON` — prompt told the implementer to use the return value directly, producing silent wrong behavior.

**under-specified (17)**
A component, rule, or behavior is named but not defined precisely enough for an implementer to build it without guessing. Concentrates in spec-bodies where a deliverable is listed but its schema, format, or interaction rule is omitted.
Example: `dynamics module path unnamed in spec` — the feature was listed but the file it lives in was never stated.

**wrong-call-site (12)**
A prompt directs an edit to the wrong file, function, or code location. The change is valid in isolation but lands in the wrong place in the actual codebase. Recurs whenever multi-file refactors were planned from spec-reasoning rather than from a live file-tree walk.
Example: `InviteScreen.tsx path wrong in every prompt` — every prompt in the set had the wrong directory.

**deployment-path-gap (9)**
The plan assumes a file, route, or asset is reachable in the deployed environment but the path doesn't exist there, wasn't created by any build step, or is served from a different location.
Example: `Logo assets 404 — not in served cryptowatchtools/public/` — files were at repo root, not in the served public directory.

**ac-implementation-mismatch (8)**
An acceptance criterion asserts a specific status code, field name, or test assertion that the implementation can't produce as written — authored before the spec was fully settled or not updated after a revision.
Example: `GenerateCodeModal.test.ts:421 asserts old URL shape; test suite red` — AC matched old behavior, change immediately broke the suite.

**stale-name (8)**
A symbol, variable, file name, endpoint, or config key in the plan or prompt refers to something renamed, replaced, or deleted in the live codebase — or carried from a prior iteration of the same doc.
Example: `plan.md still said 'Luna' everywhere spec.md said 'Vesper'` — name changed at a checkpoint but the plan wasn't updated.

**deferred-not-documented (7)**
A behavior, follow-up, or dependency is punted out of scope but not written down as a named open question or explicit out-of-scope callout. Left as a comment, an implied assumption, or a verbal agreement.
Example: `Two out-of-repo follow-ups gate the feature's actual usefulness` — the feature only works in prod when two other things are done, but neither was a named ticket or callout.

**import-missing (5)**
A prompt uses a symbol — function, class, decorator, ORM helper, stdlib module — without including or verifying an import. Under strict TypeScript or Python, this is a hard startup failure.
Example: `func.lower() used but func never imported — NameError at startup`.

**async-sync-mismatch (3)**
A function's async/sync contract doesn't match what the framework expects — blocking sync call inside an async route, or sync signature where the framework passes an async value.
Example: `Next.js 15 route params is Promise<params> — permanent 404` — params unwrapped synchronously in a framework that requires await.

---

## Architect Pre-Challenger Checklist

Run this before handing off to Spellwright.

1. **Numeric consistency pass.** Read every count, limit, and enum value. Where the same number appears in two places (item counts, batch limits, status enums), verify both agree. Flag any value referenced from two places but defined in only one.

2. **API shape verification.** For every API call, response field, return type, or function signature named in spec or prompts, grep the live codebase to confirm field name, envelope depth, and type. Never write field names from memory.

3. **File path audit.** For every file path in a prompt, confirm it exists at that exact location. For every function edit, confirm the function is defined in the named file. Walk the actual directory tree — don't reconstruct it from the spec.

4. **Boundary and null coverage.** For every input that can be null, zero, empty, or exceed a stated limit, confirm the spec or prompt has an explicit handling rule. Check specifically: optional fields, empty query strings, platform branches (Platform.OS, env flags), zero-value thresholds, and batch limits.

5. **Stale symbol scan.** For every config key, variable name, class name, and file name in spec/plan/prompts, grep the repo to confirm it exists under that exact name. Flag anything recently renamed, deprecated, or removed.

6. **Deploy path trace.** For every asset, route, or file the plan assumes is reachable at runtime, confirm it exists in the served directory — not just the repo root — and that the build/copy step that puts it there is in the plan.

7. **AC → implementation trace.** For each acceptance criterion asserting a status code, field name, or test assertion, trace it to the implementation spec and verify the code will produce exactly that value. For any test already in the repo, read it and confirm it won't go red after the planned change.

8. **Import completeness.** For every symbol used in a code prompt, confirm an explicit import is present in the prompt or already in the target file. Treat `func`, `String`, `logger`, `datetime`, and similar as unverified until confirmed in scope.

9. **External dependency inventory.** For every library, service, env var, or out-of-repo process the plan depends on, confirm it is already installed and provisioned — or that the plan has an explicit step to do so before first use. Covers: pip/npm packages not yet in requirements, env vars not in .env.example, services in separate repos, runtime assumptions about the trigger environment.

10. **Deferred items register.** For every behavior or follow-up punted out of scope, confirm it is named explicitly in the spec as an open question or out-of-scope callout — not left as a comment, implied assumption, or verbal agreement. Pay particular attention to cross-repo dependencies and follow-ups that gate the feature's usefulness.

11. **Async/sync discipline.** For every function touching I/O, confirm whether the framework expects async or sync and that the prompt's signature matches. Check especially: Next.js route params (Promise in v15+), Python httpx sync inside async routes, async saga vs useEffect navigation.

12. **Env config completeness.** For every environment variable, config key, base URL, or service endpoint referenced in spec or prompts, confirm it is in .env.example with the correct key name. Verify base URLs against the deployed service's actual routing config, not the spec's assumption about it.

---

## Full Findings Table

| Run | Sev | Finding | Action | Artifact | Pattern |
|-----|-----|---------|--------|----------|---------|
| cryptowatch | BLOCKER | plan.md used stale name "Luna"; spec said "Vesper" | FIXED | plan | stale-name |
| cryptowatch | BLOCKER | Logo assets 404 — not in served public/ directory | FIXED | architecture-section | deployment-path-gap |
| cryptowatch | BLOCKER | Prompt 07 missing useEffect for tabFreshnessAt | FIXED | prompt | missing-edge-case |
| cryptowatch | WARNING | rsi-bulk rejects >100 symbols; no chunking specified | ACKNOWLEDGED | spec-body | missing-edge-case |
| cryptowatch | WARNING | Movers snapshot drops timeframes | ACKNOWLEDGED | spec-body | under-specified |
| cryptowatch | WARNING | Dynamics module path unnamed in spec | ACKNOWLEDGED | spec-body | under-specified |
| cryptowatch | WARNING | Trend derivation is new logic, not reuse as stated | ACKNOWLEDGED | spec-body | internal-contradiction |
| cryptowatch | WARNING | HAL 9000 list incomplete in spec | ACKNOWLEDGED | spec-body | under-specified |
| cryptowatch | WARNING | Sidebar count wrong: spec says 6, actual is 7 | ACKNOWLEDGED | spec-body | internal-contradiction |
| cryptowatch | WARNING | Cost premise wrong: re-hits exchanges claim is false | ACKNOWLEDGED | assumptions | internal-contradiction |
| cryptowatch | WARNING | withMysql wrapper means header edit is inside callback | ACKNOWLEDGED | prompt | wrong-call-site |
| cryptowatch | WARNING | Prompt 04 leaves second window.location.reload() at line 60 | ACKNOWLEDGED | prompt | stale-name |
| cryptowatch | WARNING | 7 routes also consumed by Discord bot, unmentioned | ACKNOWLEDGED | architecture-section | external-dependency-unstated |
| cryptowatch | WARNING | Edge-cache key is per-query-string, not per-route | ACKNOWLEDGED | architecture-section | missing-edge-case |
| cryptowatch | WARNING | cache.ts committed but 14 route edits uncommitted together | ACKNOWLEDGED | plan | deployment-path-gap |
| cryptowatch | WARNING | PriceChangeIndicator reuse contradicts ScannerCard props and cost goal | ACKNOWLEDGED | prompt | internal-contradiction |
| cryptowatch | WARNING | RSI "merge and pass down" architecturally impossible | ACKNOWLEDGED | prompt | caller-cant-supply |
| cryptowatch | WARNING | Headline BTC price field doesn't exist in /api/market-info | ACKNOWLEDGED | prompt | wrong-api-shape |
| cryptowatch | WARNING | volume dataTimestamp is wall-clock Date.now(), not data age | ACKNOWLEDGED | prompt | wrong-api-shape |
| cryptowatch | WARNING | Prompt 04 self-contradicts "400 symbols max" then "100" | ACKNOWLEDGED | prompt | internal-contradiction |
| cryptowatch | WARNING | "Confirm it already redirects" invites leaving chained redirect | ACKNOWLEDGED | prompt | missing-edge-case |
| cryptowatch | WARNING | Untyped API boundary in build diff | ACKNOWLEDGED | architecture-section | under-specified |
| cryptowatch | WARNING | threshold=0 silently mislabels volatility data | ACKNOWLEDGED | edge-cases | missing-edge-case |
| cryptowatch | WARNING | Probe reuses full URL instead of minimal | ACKNOWLEDGED | prompt | reuse-missed |
| cryptowatch | WARNING | useEffect missing fetchData from deps array | ACKNOWLEDGED | prompt | missing-edge-case |
| cryptowatch | WARNING | Stale banner can lag up to ~60s, unspecified | ACKNOWLEDGED | spec-body | under-specified |
| invite-qr | BLOCKER | Static-export /i/[code] serving unengineered; SPA rewrite tension unverified | FIXED | architecture-section | deployment-path-gap |
| invite-qr | BLOCKER | GenerateCodeModal.test.ts:421 asserts old URL shape; test suite red | FIXED | acceptance-criteria | ac-implementation-mismatch |
| invite-qr | BLOCKER | expo-camera declared but not installed; fails from clean container | FIXED | prompt | external-dependency-unstated |
| invite-qr | BLOCKER | Cold-launch /i/CODE double-fires redeem pipeline; two instances uncoordinated | FIXED | architecture-section | missing-edge-case |
| invite-qr | BLOCKER | useInviteDeepLink ignores Platform.OS === 'web' | FIXED | prompt | missing-edge-case |
| invite-qr | WARNING | AASA uses legacy paths array not modern components | FIXED | architecture-section | wrong-api-shape |
| invite-qr | WARNING | Android assetlinks half-specified | FIXED | spec-body | under-specified |
| invite-qr | WARNING | inviteLinkFor base URL wrong (hardcoded not env var) | FIXED | spec-body | env-config-unstated |
| invite-qr | WARNING | Call-site count 4 vs actual 6 | FIXED | spec-body | internal-contradiction |
| invite-qr | WARNING | verify→signup nav is useEffect in InviteScreen.tsx:39-43, not saga | FIXED | spec-body | wrong-call-site |
| invite-qr | WARNING | acceptInvitationSaga already toasts; scanner success will double up | FIXED | spec-body | missing-edge-case |
| invite-qr | WARNING | AS-07/AS-08 can't pass without backend wording change | FIXED | acceptance-criteria | ac-implementation-mismatch |
| invite-qr | WARNING | InviteScreen.tsx path wrong in every prompt | FIXED | prompt | wrong-call-site |
| invite-qr | WARNING | Auth state is useSession().isAuthenticated not from useInvitations() | FIXED | prompt | wrong-api-shape |
| invite-qr | WARNING | Theme tokens should be useThemeColors not raw colors.ts | FIXED | prompt | wrong-call-site |
| invite-qr | WARNING | Test file should be in __tests__/ subdir, not root | FIXED | prompt | wrong-call-site |
| invite-qr | WARNING | Camera rationale wrong: expo-image-picker not in app.json plugins | FIXED | prompt | internal-contradiction |
| invite-qr | WARNING | experiments.typedRoutes: true not mentioned | ACKNOWLEDGED | prompt | env-config-unstated |
| invite-qr | WARNING | Falling-edge success detection less guarded than reference pattern | FIXED | prompt | missing-edge-case |
| invite-qr | WARNING | No orchestration test added | FIXED | acceptance-criteria | test-coverage-gap |
| stakeholder | BLOCKER | resolve_column rule 3 inverts society-desk design; in_progress wrong | FIXED | spec-body | internal-contradiction |
| stakeholder | BLOCKER | FR-1.2 enum omits build_in_progress so rule 3 can never fire | FIXED | spec-body | ac-implementation-mismatch |
| stakeholder | BLOCKER | recent-activity log leaks internal Challenger findings to sponsors | FIXED | architecture-section | missing-edge-case |
| stakeholder | BLOCKER | Column(String, …) — String not imported, NameError at startup | FIXED | prompt | import-missing |
| stakeholder | BLOCKER | from api.app.config import settings wrong path, ModuleNotFoundError | FIXED | prompt | import-missing |
| stakeholder | BLOCKER | apiFetch(...) returns raw Response not parsed JSON — silent wrong-build | FIXED | prompt | wrong-api-shape |
| stakeholder | BLOCKER | params.project on Next.js 15 is Promise<params> — permanent 404 | FIXED | prompt | async-sync-mismatch |
| stakeholder | WARNING | Membership gate 403 vs code's 404 | FIXED | spec-body | ac-implementation-mismatch |
| stakeholder | WARNING | delegate role falls through to developer view | FIXED | spec-body | missing-edge-case |
| stakeholder | WARNING | Log heading format ## [YYYY-MM-DD] not bare dates | FIXED | spec-body | internal-contradiction |
| stakeholder | WARNING | Integration test fixture exercises only trivial paths | FIXED | acceptance-criteria | test-coverage-gap |
| stakeholder | WARNING | checkpoint_count markers not stated | FIXED | spec-body | under-specified |
| stakeholder | WARNING | Result shape union not typed | FIXED | spec-body | under-specified |
| stakeholder | WARNING | datetime.utcfromtimestamp deprecated in Python 3.12 | FIXED | prompt | stale-name |
| stakeholder | WARNING | admin endpoints 422 vs code's 400 | FIXED | spec-body | ac-implementation-mismatch |
| stakeholder | WARNING | api/tests/ dir doesn't exist yet | FIXED | prompt | deployment-path-gap |
| stakeholder | WARNING | Migration filename missing _HHMM timestamp component | FIXED | prompt | under-specified |
| stakeholder | WARNING | design/manifest.md not in build repo | FIXED | prompt | deployment-path-gap |
| stakeholder | WARNING | params.project vs awaited slug inconsistency | FIXED | prompt | async-sync-mismatch |
| rheo-memory-track1 | BLOCKER | searchTurns() passes raw input into FTS5 MATCH; ftsPhrase() exists but unused | FIXED | prompt | reuse-missed |
| rheo-memory-track1 | BLOCKER | GET /api/conversation?q= has no try/catch — FTS throw becomes unhandled 500 | FIXED | prompt | missing-edge-case |
| rheo-memory-track1 | WARNING | No tests for any new code path | FIXED | acceptance-criteria | test-coverage-gap |
| rheo-memory-track1 | WARNING | GET /api/tickets ignores limit param (bot passes limit, API reads per_page) | FIXED | prompt | wrong-api-shape |
| rheo-memory-track1 | WARNING | New FTS migration breaks source-of-truth convention; no SQL twin | FIXED | architecture-section | deferred-not-documented |
| rheo-memory-track1 | WARNING | Commit message mismatch — 911-line diff; new MCP server not mentioned | ACKNOWLEDGED | plan | under-specified |
| rheo-memory-track1 | WARNING | MCP exposes ticket-mutation tools over single shared API key | ACKNOWLEDGED | architecture-section | missing-edge-case |
| upwork-desk | BLOCKER | Full-fetch step absent from spec and plan; no HTML parser in requirements | FIXED | plan | under-specified |
| upwork-desk | BLOCKER | deploy.sh health check hits wrong vhost; second live proxy unaccounted for | FIXED | architecture-section | deployment-path-gap |
| upwork-desk | BLOCKER | Email LLM fallback mis-models chat_completion return shape; must extract choices[0] | FIXED | prompt | wrong-api-shape |
| upwork-desk | BLOCKER | ingest.py dedup uses func.lower() but func never imported — NameError | FIXED | prompt | import-missing |
| upwork-desk | WARNING | FastAPI global dependencies can't exempt /health via route registration | FIXED | prompt | wrong-api-shape |
| upwork-desk | WARNING | status default/tier1_only interaction rule unwritten | FIXED | spec-body | under-specified |
| upwork-desk | WARNING | mot.py uses separate SessionLocal(); plan ambiguous on which session | FIXED | plan | under-specified |
| upwork-desk | WARNING | M.O.T. base URL 127.0.0.1:3100/api/tickets unverified (may have basePath) | FIXED | assumptions | env-config-unstated |
| upwork-desk | WARNING | Repo has no rheo-ssl.conf, only api.rheo.ca.conf | FIXED | assumptions | deployment-path-gap |
| upwork-desk | WARNING | raw_payload stores verbatim JSON without truncation policy | ACKNOWLEDGED | spec-body | under-specified |
| upwork-desk | WARNING | Dedup normalization double-applied and self-inconsistent | FIXED | prompt | internal-contradiction |
| upwork-desk | WARNING | New service files reference logger with no logger defined | FIXED | prompt | import-missing |
| upwork-desk | WARNING | mot.py "Depends on: LlmLog model" is wrong (pre-existing) | ACKNOWLEDGED | prompt | stale-name |
| upwork-desk | WARNING | AC-12 positive auth case only implicit | FIXED | acceptance-criteria | ac-implementation-mismatch |
| upwork-desk | WARNING | AC-14 .gitignore check has no owning step | FIXED | acceptance-criteria | ac-implementation-mismatch |
| upwork-desk | WARNING | AC-13 dual-vhost health check unverifiable until Prompt 5 | ACKNOWLEDGED | acceptance-criteria | deferred-not-documented |
| gmail-llm | BLOCKER | Wrong auth header — X-API-Key rejected; only Authorization: Bearer accepted | FIXED | architecture-section | wrong-api-shape |
| gmail-llm | BLOCKER | Trigger cannot reach API — egress blocked in cloud-routine environment | FIXED | architecture-section | deployment-path-gap |
| gmail-llm | BLOCKER | Gmail MCP-at-runtime assumption unproven for this trigger environment | FIXED | assumptions | external-dependency-unstated |
| gmail-llm | BLOCKER | email_parse._llm_fallback reads choices[0] directly; normalizer envelope unwritten | FIXED | prompt | wrong-api-shape |
| gmail-llm | BLOCKER | max_tokens=1024 truncates proposal AND humanizer pass | OVERRIDDEN | spec-body | missing-edge-case |
| gmail-llm | BLOCKER | job_id typed Optional[int] but is str everywhere in live code | FIXED | prompt | wrong-api-shape |
| gmail-llm | BLOCKER | Routes converted to async def — blocking sync httpx calls stall event loop | FIXED | prompt | async-sync-mismatch |
| gmail-llm | BLOCKER | Prompt 05 wrong route signature: per-route auth + async; auth is app-wide, sync | FIXED | prompt | wrong-call-site |
| gmail-llm | WARNING | Idempotency depends on upwork_url always present; can be None | FIXED | edge-cases | missing-edge-case |
| gmail-llm | WARNING | fetch_full_description fires on 100% of email leads; guaranteed-failing call | FIXED | spec-body | missing-edge-case |
| gmail-llm | WARNING | deepseek_api_key is dead config; plan rationale wrong | FIXED | assumptions | stale-name |
| gmail-llm | WARNING | humanizer Gemini→Haiku is a quality change dressed as config default | ACKNOWLEDGED | assumptions | internal-contradiction |
| gmail-llm | WARNING | .env.example additions incomplete | FIXED | prompt | env-config-unstated |
| gmail-llm | WARNING | provider-default mechanism unspecified | FIXED | spec-body | under-specified |
| gmail-llm | WARNING | Plan line 10 is a leaked editor command | FIXED | plan | stale-name |
| gmail-llm | WARNING | Python target is 3.9 not 3.12 | FIXED | assumptions | env-config-unstated |
| gmail-llm | WARNING | proposal_model/humanizer_model collapse both onto same Haiku (self-editing) | FIXED | spec-body | internal-contradiction |
| gmail-llm | WARNING | purpose/job_id plumbing unspecified | FIXED | spec-body | under-specified |
| gmail-llm | WARNING | Chunk 5 per-job try/except at jobs.py:96 is load-bearing; must be carried verbatim | FIXED | prompt | wrong-call-site |
| gmail-llm | WARNING | MCP tools/call error envelope has no input validation spec | FIXED | spec-body | under-specified |
| gmail-llm | WARNING | .env.example line numbers wrong | FIXED | prompt | stale-name |
| gmail-llm | WARNING | Prompt 06 missing JSON-RPC framing vs M.O.T. precedent | FIXED | prompt | wrong-api-shape |
| gmail-llm | WARNING | Truncated key advisory-only not noted | ACKNOWLEDGED | prompt | deferred-not-documented |
| gmail-llm | WARNING | Prompt 03 hedges exact proposal.py call sites | FIXED | prompt | wrong-call-site |
| gmail-llm | WARNING | prompt 02 db-session contradicts ground truth | FIXED | prompt | internal-contradiction |
| gmail-llm | WARNING | Counter names in prose differ from real keys in code | FIXED | prompt | stale-name |
| gmail-llm | WARNING | temperature= always sent to Anthropic SDK — 400s on Opus/Fable | FIXED | prompt | wrong-api-shape |
| gmail-llm | WARNING | No -32600 guard in MCP chunk 06 | ACKNOWLEDGED | prompt | missing-edge-case |
| gmail-llm | WARNING | tools/call missing name → isError not -32602 | ACKNOWLEDGED | prompt | missing-edge-case |
| memory-track2 | BLOCKER | bot/bot.py does not exist in MOT repo; Phase 4/5 target it as deliverable | FIXED | plan | wrong-call-site |
| memory-track2 | BLOCKER | Extraction pass input produced by out-of-scope bot; input contract undefined | FIXED | architecture-section | external-dependency-unstated |
| memory-track2 | WARNING | "contentless"/"delete-then-reinsert" mis-describes real FTS5 idiom | FIXED | spec-body | internal-contradiction |
| memory-track2 | WARNING | FKs target session_digest.session_id (UNIQUE column, not PK) | FIXED | spec-body | wrong-api-shape |
| memory-track2 | WARNING | AC-12 typed-error convention inconsistent with existing throw→isError:true pattern | FIXED | acceptance-criteria | ac-implementation-mismatch |
| memory-track2 | WARNING | AC-4 and R2 directly contradict each other | FIXED | acceptance-criteria | internal-contradiction |
| memory-track2 | WARNING | mention_count created but unwritten in spec | FIXED | spec-body | deferred-not-documented |
| memory-track2 | WARNING | OQ-1 in two contradicting states in spec | FIXED | open-questions | internal-contradiction |
| memory-track2 | WARNING | Prompt 4 builds against unverified DigestRow shape | ACKNOWLEDGED | prompt | under-specified |
| memory-track2 | WARNING | Prompt 3 getThread assumes summary column on session_digest | ACKNOWLEDGED | prompt | wrong-api-shape |
| memory-track2 | WARNING | Cross-category procedural dedup load-bearing behavior carried only by comment | ACKNOWLEDGED | prompt | deferred-not-documented |
| memory-track2 | WARNING | searchActiveMemory undefined behavior for empty q | ACKNOWLEDGED | edge-cases | missing-edge-case |
| memory-track2 | WARNING | procedural_notes.note_norm dedup app-enforced not DB UNIQUE — TOCTOU race | ACKNOWLEDGED | architecture-section | missing-edge-case |
| memory-track2 | WARNING | Two out-of-repo follow-ups gate feature's actual usefulness | ACKNOWLEDGED | plan | deferred-not-documented |
| nav-runtime | WARNING | FR-4(d) near-dup fires on legitimate singular/plural pairs | FIXED | spec-body | false-positive-risk |
| nav-runtime | WARNING | "9 workflows" is ambiguous against 10-file directory | ACKNOWLEDGED | spec-body | internal-contradiction |
| nav-runtime | WARNING | macOS ships bash 3.2; no mapfile/declare -A/readarray | ACKNOWLEDGED | architecture-section | external-dependency-unstated |
| nav-runtime | WARNING | Allowlist purpose is "insurance" yet still requires maintenance | ACKNOWLEDGED | spec-body | internal-contradiction |
