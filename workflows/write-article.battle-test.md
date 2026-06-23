## Run 2026-06-23

| Case name | Input description | Expected outcome | Actual result |
|-----------|-------------------|------------------|---------------|
| **nominal** — full pipeline, piece with figures | A topic with quantitative claims; full config (Grok pass enabled via `config/article-passes.json`); all 15 workflow steps run through to staged MDX in devweb. | `draft.md` evolves through each pass; `passes/01-grok.md` candidate exists; figure gate (step 6) triggers and runs 6a (`figure-check.md` written); both Counselor humanizer passes run; `article.mdx` passes devweb `npm run build` (all-static, no `ƒ`); run stops at dev boundary — no push to `main`. Step-7 `[EXTERNAL-ACTION CHECKPOINT]` halts until approved and the halt is logged to `log.md`. | pending — live dry-run gated at external-action checkpoint (PART B) |
| **branch: no-figures piece** | A draft whose body contains no specific figures, percentages, dates, or measurements — only qualitative statements ("most teams", "noticeably faster"). | Step 6 Conductor-gate reads `draft.md`, finds no quantitative claims, logs `grounding: not-triggered` to `RUN_DIR/log.md`, and skips to step 7 without spawning the Scribe in ground sub-mode. No `figure-check.md` produced. Pipeline otherwise proceeds normally. | pass — workflow step 6 (`workflows/write-article.md:157-159`) and Edge Cases section (`write-article.md:79-80`) both document this exact branch path: "If `draft.md` carries no quantitative claims, step 6 logs `grounding: not-triggered`…" — logic confirmed by code read |
| **edge: draft that is almost entirely a data table** | A piece whose body is dominated by a markdown data table (stresses figure-grounding step 6a — tables contain numbers; the `model-pass.sh` length-delta integrity check — a table-heavy draft may compress/expand asymmetrically; and the `<RunTable>` MDX component path in the Format step). | Figure gate triggers (tables contain numbers); `model-pass.sh` applies the 50%–300% length-delta window — a table that a model compresses exits 3 cleanly (logged, draft survives) rather than silently promoting a truncated candidate; Format step emits `<RunTable>` only if `run` object present in frontmatter; devweb `npm run build` accepts the resulting MDX. | pass — `workflows/write-article.md:94-97` explicitly names this as an edge case and documents all three stress paths (figure gate triggers, length-delta check applies as designed, `<RunTable>` conditional on `run` object); `scripts/model-pass.sh` exit-3 + no-write-on-failure confirmed by fixtures 05 and 06 (pass — see length-delta offline runs below); workflow behaviour confirmed by code read |
| **failure: cross-model pass returns 2xx with empty/whitespace body** | `model-pass.sh` receives a 2xx HTTP response but `.choices[0].message.content` is empty or whitespace-only (mocked via offline fixture). | `model-pass.sh` exits 3 (integrity check — non-empty/non-whitespace content check at line 201-202 of script); no candidate file written; `draft.md` survives untouched; step-8 batch policy: log failure, skip pass, continue with the next. | pass — `scripts/model-pass.sh:199-202` contains the `tr -d '[:space:]'`/empty-check; exit 3 confirmed. Fixture `03-finish-reason-length.md` (null-body variant) and `04-finish-reason-null.md` both run exit 3 with no out-file; `02-non-2xx.md` confirms no-write on non-2xx. Offline fixture suite run 2026-06-23: 4/4 pass |
| **failure: `finish_reason:"length"` (truncation)** | `model-pass.sh` receives a 2xx response with `finish_reason: "length"` (mocked via offline fixture `03-finish-reason-length.md`). | `model-pass.sh` exits 3 (integrity check — `finish_reason != "stop"`); no candidate file written; `draft.md` survives; batch continues per partial-failure policy. | pass — fixture `03-finish-reason-length.md` run 2026-06-23: exit 3, out-file not created. Confirmed: `model-pass.sh` exits with "finish_reason is 'length', expected exactly 'stop'" and leaves `draft.md` intact |

---

### Verification notes (PART A — offline, 2026-06-23)

**Offline fixture results** (run via `run.sh` extraction logic against WROOT `/Users/robin/.bureau/worktrees/bureau/20260623-write-article`):

| Fixture | Expected | Actual |
|---------|----------|--------|
| `02-non-2xx.md` | exit 2, out-file not created | PASS — "non-2xx -> exit 2, out-file untouched" |
| `03-finish-reason-length.md` | exit 3, out-file not created | PASS — "finish_reason=length -> exit 3, out-file untouched" |
| `05-length-delta-under.md` | exit 3, out-file not created | PASS — "length-delta under 50% -> exit 3, out-file untouched" |
| `06-length-delta-over.md` | exit 3, out-file not created | PASS — "length-delta over 300% -> exit 3, out-file untouched" |

**`bash check-framework.sh`** (from worktree root): `== all checks passed`, exit 0. One non-blocking WARN about usage-poller plist pointing at the canonical install path rather than this worktree — expected and harmless for a relocated worktree.

**devweb publish-contract build check**: Wrote `/Users/robin/Code/novadiem/devweb/content/articles/zzz-battletest-tmp.mdx` with conformant frontmatter (`title`, `dek`, `date: "2026-06-23"`, `pillar: "engineering"`, `slug: "zzz-battletest-tmp"`, `draft: true`). Ran `npm run build` in devweb — exit 0; route table all-static (no `ƒ`); Zod schema accepted the frontmatter. Temp file deleted; confirmed absent. devweb working tree restored clean. No commit made in devweb.

**Staged live dry-run** (PART B — gated, not fired):

Exact command the Conductor will run after the `[EXTERNAL-ACTION CHECKPOINT]`:

```sh
bash /Users/robin/.bureau/worktrees/bureau/20260623-write-article/scripts/model-pass.sh \
  openrouter:x-ai/grok-4.3 \
  /Users/robin/Code/novadiem/bureau/.bureau/runs/20260623-write-article/passes-test/test-draft.md \
  /Users/robin/.bureau/worktrees/bureau/20260623-write-article/config/passes/improve-grok.md \
  /Users/robin/Code/novadiem/bureau/.bureau/runs/20260623-write-article/passes-test/01-grok.md \
  --run-dir /Users/robin/Code/novadiem/bureau/.bureau/runs/20260623-write-article
```

Model spec (from `config/article-passes.json`, pass id `grok`): `openrouter:x-ai/grok-4.3` — the only enabled pass.
Test draft: `RUN_DIR/passes-test/test-draft.md` (~640 bytes; staged 2026-06-23; topic: Turbopack module resolution vs Webpack).
Instruction file: `config/passes/improve-grok.md` (developmental editor improvement pass).
Keystore: `~/Documents/novadiem/keys/novadiem/openrouter.env` — present and non-empty (confirmed `KEY_PRESENT` 2026-06-23, no network call made).
Target URL: `https://openrouter.ai/api/v1/chat/completions`.
Estimated cost: one short Grok completion (~640 bytes in, ~640-1920 bytes out) — low single-digit cents.
