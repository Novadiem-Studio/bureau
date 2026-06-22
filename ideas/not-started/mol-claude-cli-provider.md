# M.O.L. — `claude_cli` LLM provider (Claude subscription, headless)

**Repo:** `mol` (`~/Code/novadiem/mol/backend`). **Priority:** medium — proposal quality is
the active pain. Self-contained; no framework run required, one focused pass.

## Problem

The proposal writer drafts on OpenRouter `anthropic/claude-haiku-4-5`. Haiku is too light:
weak, AI-tell-heavy copy, ignores the "no em dashes" rule, and the gemini humanizer then
flattens whatever it gets (observed live: "routes work" → "sends out work", "unsupervised" →
"run on their own", sharp technical terms genericized). A blind code-level em-dash strip was
tried as a band-aid, but replacing ` — ` with `, ` produces comma splices — rejected.

Root cause is model strength, not prompt wording. Fix: route mol's LLM calls through Robin's
Claude **subscription** headless via the `claude` CLI (`claude -p`) instead of per-token APIs,
and draft proposals on Opus 4.8.

## Why the CLI (not OpenClaw, not the API)

- **OpenClaw (`:18789`)** is a WebSocket control UI with no completions API — not a usable
  transport. (`config.openclaw_url` is dead; rheo-infra plans to remove the references.)
- **The API key path** (`llm_provider="claude"`, Anthropic SDK) is exactly the per-token billing
  we want to avoid.
- **`claude -p` is the proven subscription-headless transport**, already used by `rheo-bot`
  (`~/Code/novadiem/rheo-bot/bot.py`) on the same box, and by the YouTube-digest idea. Same
  pattern, same auth (`~/.claude` subscription login). Confirmed on this machine (CLI v2.1.185):
  `claude -p --output-format json` →
  `{"type":"result","result":"<model text>","usage":{...},"total_cost_usd":...}`.
  No `--temperature` / `--max-tokens` flags exist (`claude -p --help`).

## Decisions (settled with Robin)

- **Routing: global.** When `LLM_PROVIDER=claude_cli`, all five roles (scoring, parse, analysis,
  proposal, humanizer) go through the subscription. No per-role override built. Accepted tradeoff:
  batch ingest spawns one subprocess per job, each carrying ~2.5s of Claude Code's own startup
  overhead (model-independent) — a 20-job email digest adds ~80s.
- **Models:** proposal + humanizer default to **Opus 4.8** (quality where it matters);
  scoring/parse/analysis default to **Haiku 4.5** to limit the batch penalty.
- **Keep the humanize pass**, now on Opus 4.8 with the surgical prompt (rewritten earlier this
  session — minimal edits, no paraphrasing, preserve technical terms). Em-dash safety comes from
  the prompt + a strong model, not a code strip.

## Implementation (by file)

### `app/config.py`
Add after the `claude_*_model` block:
```python
cli_scoring_model: str = "claude-haiku-4-5"
cli_parse_model: str = "claude-haiku-4-5"
cli_analysis_model: str = "claude-haiku-4-5"
cli_proposal_model: str = "claude-opus-4-8"
cli_humanizer_model: str = "claude-opus-4-8"
cli_timeout_default: int = 60       # scoring/parse/analysis
cli_timeout_proposal: int = 240     # proposal_draft / proposal_humanize (Opus is slower)
```
Keep `llm_provider = "openrouter"` (code default — portable, CI-safe). Leave `openclaw_url`.

### `app/services/llm.py`
- `import subprocess, json, os`.
- Add a `"claude_cli"` key to `_MODEL_MAP` mapping the five roles to the `cli_*_model` attrs
  (mandatory — `resolve_model` KeyErrors without it).
- In `chat_completion`, add a branch **before** the OpenRouter fallthrough:
  `if settings.llm_provider == "claude_cli": return _claude_cli_chat_completion(...)`.
- Add `_claude_cli_chat_completion(model, messages, purpose, job_id, resolved_max, temperature)`,
  modeled on `_claude_chat_completion`:
  - Split system vs user messages (every mol caller sends one of each → lossless), join each to a
    string. Build
    `["claude","-p",prompt,"--model",model,"--allowedTools","","--output-format","json"]`,
    append `["--system-prompt", system]` when present. `--allowedTools ""` = pure text gen.
  - **Sanitized env (the load-bearing detail):** spawn with `os.environ` minus `ANTHROPIC_API_KEY`
    and `ANTHROPIC_AUTH_TOKEN`. If either is present the CLI silently uses per-token API auth
    instead of the subscription.
  - Timeout: `cli_timeout_proposal` for `proposal_draft`/`proposal_humanize`, else `cli_timeout_default`.
  - **Loud failure** (the `rheo-silent-auth-failure` anecdote — an expired token returns a 401
    captured into the subprocess and never logged): on TimeoutExpired / non-zero rc / empty stdout /
    `is_error:true` envelope → log returncode+stderr and **raise**, never return blank.
  - Parse the JSON envelope defensively (fall back to raw stdout on `JSONDecodeError`):
    `content = envelope["result"]`; usage from `envelope["usage"]`; `cost = envelope.get("total_cost_usd")`
    (notional API-equiv cost; subscription is flat-rate). Build the standard
    `{"model","choices":[{"message":{"content"}}],"usage"}` envelope and call `_write_llm_log`.
  - `resolved_max` / `temperature` accepted but **inert** (no CLI flags) — comment it.

### `app/services/proposal.py`
- **Delete** `_strip_em_dashes` and drop its call (final `return` becomes the plain humanized text).
- Fix the now-stale `HUMANIZER_PROMPT` line referencing "an em-dash sweep also runs after you" →
  just instruct em dashes → comma/colon/period. Draft `SYSTEM_PROMPT` already bans em dashes.

### `.env` (local + prod `/opt/mol`, not committed) + `.env.example` (committed)
Set `LLM_PROVIDER=claude_cli`. Document the `CLI_*` fields in `.env.example`. Both machines already
have `claude` + `~/.claude` auth (rheo-bot on the box; Claude Code locally).

### `tests/test_llm_claude_cli.py` (new)
Mock `subprocess.run` (no real CLI). Cover: command array built correctly; env strips
`ANTHROPIC_API_KEY`/`ANTHROPIC_AUTH_TOKEN`; JSON envelope → mol envelope with summed `total_tokens`
+ `cost`; non-zero rc raises; empty stdout raises; `is_error` envelope raises; `resolve_model`
returns the `cli_*` model when `llm_provider="claude_cli"`. Existing suite (mocks the wrappers,
not `chat_completion`) stays green — 74 tests.

## Verification

1. Real CLI smoke: `claude -p 'return only JSON: {"score":7,"reason":"x"}' --output-format json --allowedTools "" --model claude-haiku-4-5` → `result` holds the JSON string. (Done during planning.)
2. End-to-end: `LLM_PROVIDER=claude_cli .venv/bin/python scripts/test_proposal.py` (harness stubs the DB log, tees each stage). Confirm analysis (Haiku), draft (Opus), humanize (Opus) all non-empty, no comma splices, copy reads well vs. the old haiku output. ~50–90s total (two Opus calls).
3. `.venv/bin/pytest` — new tests pass, prior 74 green.

## Risks / notes

- **Batch latency** (accepted): N-job ingest ≈ N × ~4s. Scoring/parse on Haiku to minimize it.
- **Auth shadowing:** the env-strip is load-bearing — a stale `ANTHROPIC_API_KEY` silently bills per-token.
- **CLI version drift:** `--output-format json` field names could change; defensive parse falls back to raw stdout.
- **LlmLog token counts** for this provider include Claude Code's ~15–30k injected context — inflated vs. OpenRouter/SDK rows. Flag with a code comment.
- **MCP path:** `generate_proposal` is reachable via `/mcp`; with claude_cli it spawns `claude -p` on the box (fine over the HTTP boundary; bounded by the 240s timeout).
- **Em dashes** now rely on Opus draft + Opus humanizer following the prompt. If they still leak, revisit with a grammar-aware fix — not the blind comma swap.
