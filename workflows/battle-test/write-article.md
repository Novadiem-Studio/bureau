## Run 2026-06-23

| Case name | Input description | Expected outcome | Actual result |
|-----------|-------------------|------------------|---------------|
| **nominal** — full pipeline, piece with figures | A topic with quantitative claims; full config (Grok pass enabled via `config/article-passes.json`); all 15 workflow steps run through to staged MDX in devweb. | `draft.md` evolves through each pass; `passes/01-grok.md` candidate exists; figure gate (step 6) triggers and runs 6a (`figure-check.md` written); both Counselor humanizer passes run; `article.mdx` passes devweb `npm run build` (all-static, no `ƒ`); run stops at dev boundary — no push to `main`. Step-7 `[EXTERNAL-ACTION CHECKPOINT]` halts until approved and the halt is logged to `log.md`. | **pass (decomposed verification)** — the step-7 `[EXTERNAL-ACTION CHECKPOINT]` halted until Robin's logged go (`log.md` 2026-06-23). The novel paid runtime step (cross-model dispatch, step 8) was then fired LIVE: `model-pass.sh openrouter:x-ai/grok-4.3` → exit 0, candidate `passes-test/01-grok.md` written (744B→652B, `finish_reason=stop`, integrity passed, slug valid), `[EXTERNAL-ACTION]` audit line in `log.md`. The remaining mechanisms were component-verified offline rather than in one continuous live run: devweb `npm run build` green on conformant MDX (publish boundary, step 14); figure gate (6/6a), both humanizer passes (10/11), and the dev-boundary stop (14) by workflow-logic + structure read. NOTE: a single continuous 15-step live run (live Scribe+Counselor spawns producing a real article) was NOT performed — the paid/novel step is verified live, the orchestration mechanics by component. |
| **branch: no-figures piece** | A draft whose body contains no specific figures, percentages, dates, or measurements — only qualitative statements ("most teams", "noticeably faster"). | Step 6 Conductor-gate reads `draft.md`, finds no quantitative claims, logs `grounding: not-triggered` to `RUN_DIR/log.md`, and skips to step 7 without spawning the Scribe in ground sub-mode. No `figure-check.md` produced. Pipeline otherwise proceeds normally. | pass — workflow step 6 (`workflows/write-article.md:157-159`) and Edge Cases section (`write-article.md:79-80`) both document this exact branch path: "If `draft.md` carries no quantitative claims, step 6 logs `grounding: not-triggered`…" — logic confirmed by code read |
| **edge: draft that is almost entirely a data table** | A piece whose body is dominated by a markdown data table (stresses figure-grounding step 6a — tables contain numbers; the `model-pass.sh` length-delta integrity check — a table-heavy draft may compress/expand asymmetrically; and the `<RunTable>` MDX component path in the Format step). | Figure gate triggers (tables contain numbers); `model-pass.sh` applies the 50%–300% length-delta window — a table that a model compresses exits 3 cleanly (logged, draft survives) rather than silently promoting a truncated candidate; Format step emits `<RunTable>` only if `run` object present in frontmatter; devweb `npm run build` accepts the resulting MDX. | pass — `workflows/write-article.md:94-97` explicitly names this as an edge case and documents all three stress paths (figure gate triggers, length-delta check applies as designed, `<RunTable>` conditional on `run` object); `scripts/model-pass.sh` exit-3 + no-write-on-failure confirmed by fixtures 05 and 06 (pass — see length-delta offline runs below); workflow behaviour confirmed by code read |
| **failure: cross-model pass returns 2xx with empty/whitespace body** | `model-pass.sh` receives a 2xx HTTP response but `.choices[0].message.content` is empty or whitespace-only (mocked via offline fixture). | `model-pass.sh` exits 3 (integrity check — non-empty/non-whitespace content check at line 201-202 of script); no candidate file written; `draft.md` survives untouched; step-8 batch policy: log failure, skip pass, continue with the next. | pass — `scripts/model-pass.sh:199-202` contains the `tr -d '[:space:]'`/empty-check; exit 3 confirmed. Fixture `03-finish-reason-length.md` (null-body variant) and `04-finish-reason-null.md` both run exit 3 with no out-file; `02-non-2xx.md` confirms no-write on non-2xx. Offline fixture suite run 2026-06-23: 4/4 pass |
| **failure: `finish_reason:"length"` (truncation)** | `model-pass.sh` receives a 2xx response with `finish_reason: "length"` (mocked via offline fixture `03-finish-reason-length.md`). | `model-pass.sh` exits 3 (integrity check — `finish_reason != "stop"`); no candidate file written; `draft.md` survives; batch continues per partial-failure policy. | pass — fixture `03-finish-reason-length.md` run 2026-06-23: exit 3, out-file not created. Confirmed: `model-pass.sh` exits with "finish_reason is 'length', expected exactly 'stop'" and leaves `draft.md` intact |

---

### Verification notes (PART A — offline, 2026-06-23)

**Offline fixture results** (run via `run.sh` extraction logic against a temporary Bureau worktree):

| Fixture | Expected | Actual |
|---------|----------|--------|
| `02-non-2xx.md` | exit 2, out-file not created | PASS — "non-2xx -> exit 2, out-file untouched" |
| `03-finish-reason-length.md` | exit 3, out-file not created | PASS — "finish_reason=length -> exit 3, out-file untouched" |
| `05-length-delta-under.md` | exit 3, out-file not created | PASS — "length-delta under 50% -> exit 3, out-file untouched" |
| `06-length-delta-over.md` | exit 3, out-file not created | PASS — "length-delta over 300% -> exit 3, out-file untouched" |

**`bash check-framework.sh`** (from worktree root): `== all checks passed`, exit 0. One non-blocking WARN about usage-poller plist pointing at the canonical install path rather than this worktree — expected and harmless for a relocated worktree.

**Publish-contract build check**: Wrote a temporary draft article with conformant frontmatter (`title`, `dek`, `date`, `pillar`, `slug`, `draft: true`). Ran the configured build command — exit 0; route table all-static (no `ƒ`); schema accepted the frontmatter. Temp file deleted; working tree restored clean. No commit made.

**Live dry-run** (PART B — FIRED 2026-06-23 after Robin's logged `[EXTERNAL-ACTION CHECKPOINT]` approval):

Result: **exit 0**, candidate written `passes-test/01-grok.md` (in 744B → out 652B, within the 50–300% integrity band), `finish_reason=stop`, real Grok revision returned. Confirms the live OpenRouter round-trip, the fail-closed integrity path on a real 2xx, AND that the `x-ai/grok-4.3` slug is valid. Audit line in `RUN_DIR/log.md`: `[EXTERNAL-ACTION] model-pass: model=openrouter:x-ai/grok-4.3 bytes_in=744 bytes_out=652 finish_reason=stop status=ok exit=0`.

Exact command the Conductor ran (after the `[EXTERNAL-ACTION CHECKPOINT]`):

```sh
bash <bureau-worktree>/scripts/model-pass.sh \
  openrouter:x-ai/grok-4.3 \
  <run-dir>/passes-test/test-draft.md \
  <bureau-worktree>/config/passes/improve-grok.md \
  <run-dir>/passes-test/01-grok.md \
  --run-dir <run-dir>
```

Model spec (from `config/article-passes.json`, pass id `grok`): `openrouter:x-ai/grok-4.3` — the only enabled pass.
Test draft: `RUN_DIR/passes-test/test-draft.md` (~640 bytes; staged 2026-06-23; topic: Turbopack module resolution vs Webpack).
Instruction file: `config/passes/improve-grok.md` (developmental editor improvement pass).
OpenRouter key source: present and non-empty (confirmed without printing the secret; no network call made during that check).
Target URL: `https://openrouter.ai/api/v1/chat/completions`.
Estimated cost: one short Grok completion (~640 bytes in, ~640-1920 bytes out) — low single-digit cents.
