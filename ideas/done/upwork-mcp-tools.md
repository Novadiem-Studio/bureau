# Upwork Triage MCP Expansion

Date: 2026-06-20
Status: not started

---

## One-liner

Expand the existing `api.rheo.ca/mcp` endpoint with job-management tools so Claude agents
(especially the `claude -p rheo` Telegram bot) can read, filter, dismiss, update status,
and work with proposal drafts without opening the browser app.

---

## Problem

The Upwork triage MCP server at `api.rheo.ca/mcp` currently exposes one tool:
`upwork_ingest_email`. That covers getting jobs *in*, but nothing for working with them
afterward. The entire job lifecycle — reviewing scored jobs, tracking status, iterating
on proposal drafts — requires opening `rheo.ca/upwork` in a browser.

The `claude -p rheo` Telegram bot is the natural interface for lightweight ops work (scan
today's jobs, push a job to "submitted", tighten a proposal draft on mobile) but has no
way to touch the job database. The gap makes the Telegram agent close to useless for
Upwork work.

The DNS entry `mcp.rheo.ca` is already registered but nothing answers on it — the endpoint
still lives at the `/mcp` path on `api.rheo.ca`. That inconsistency should be resolved as
part of this work.

---

## Solution

Add six new tools to the existing JSON-RPC 2.0 endpoint and wire up the `mcp.rheo.ca`
vhost so there's a clean dedicated URL. No new server, no new auth — the endpoint is
already registered with Claude and the `claude -p rheo` profile; new tools just need
permission grants on first call.

Split the handler logic into `services/mcp_tools.py` so `routers/mcp.py` stays as pure
dispatch. The handlers call the DB session and service layer directly, the same pattern
as the current `upwork_ingest_email` handler — no `HTTPException`, errors surface as
`isError: true` in the tool result.

---

## Tools

### `upwork_list_jobs`
List jobs with optional status filter. Returns a condensed list (id, title, score, reason,
status, budget, proposal_count, upwork_url) sorted by tier2_score desc. Caps at 20 results.

```
Input:  { status?: string }   # one of: new/review/submitted/reply/won/lost/dismissed
                               # omit for the default view (tier1 passed, not dismissed)
Output: [{ id, title, tier2_score, tier2_reason, status, budget_min, budget_max,
           proposal_count, upwork_url, mot_filed }]
```

### `upwork_get_job`
Full detail for one job: description, proposal draft if it exists, all metadata.

```
Input:  { job_id: string }
Output: { ...all Job fields }
```

### `upwork_update_status`
Change a job's status. Keeps `dismissed` bool in sync (same logic as the REST route).

```
Input:  { job_id: string, status: string }  # one of the JOB_STATUSES enum
Output: { ok: true, job_id, status }
```

### `upwork_dismiss_job`
Dismiss a job (sets `status="dismissed"` and `dismissed=True`).

```
Input:  { job_id: string }
Output: { ok: true }
```

### `upwork_draft_proposal`
Generate a proposal draft if one doesn't exist; return the existing draft if it does.
Calls `services/proposal.py::generate_proposal()` and persists the result.

```
Input:  { job_id: string }
Output: { job_id, proposal_draft: string }
```

### `upwork_update_draft`
Save an edited proposal draft. REST equivalent `PATCH /jobs/{id}/draft` also exists
(added 2026-06-20) and is used by the browser UI's Save button.

```
Input:  { job_id: string, draft: string }
Output: { ok: true, job_id }
```

---

## Architecture

```
claude -p rheo (Telegram bot)
    │  HTTPS JSON-RPC 2.0
    ▼
mcp.rheo.ca  (Apache vhost — new, proxies to 127.0.0.1:8001)
    │
    ▼
FastAPI  api.rheo.ca  :8001
    └── routers/mcp.py          dispatch only — handle_rpc() switch
            └── services/mcp_tools.py   handler functions (new)
                    ├── db.query(Job)
                    ├── services/proposal.py::generate_proposal()
                    └── services/tier2.py  (score_job — not called here, already scored)
```

Auth is unchanged: every request must carry `Authorization: Bearer <RHEO_API_KEY>`.
The `verify_api_key` dependency on the FastAPI app covers the `/mcp` route automatically.

---

## Build Steps

1. **`services/mcp_tools.py`** — one function per tool, each takes `(db: Session, args: dict, req_id: Any) -> dict`. Returns a standard `_rpc_result` / `_rpc_error` envelope.

2. **`routers/mcp.py`** — add tool defs to the `TOOL_DEF` list (rename to `TOOL_DEFS`), extend `_dispatch_tool` with branches for each new tool name.

3. **`apache/mcp.rheo.ca.conf`** — new vhost file mirroring the `api.rheo.ca` proxy config, pointing to `:8001`. Add to `deploy.sh` alongside the existing vhost enables.

4. **`tests/`** — unit tests for each handler in `mcp_tools.py` using the existing SQLite in-memory fixture. Mock `generate_proposal` for the draft tool test.

5. **Deploy + permission grants** — `./deploy.sh`, then trigger each new tool from the Telegram bot and grant permissions in Claude when prompted.

Note: `PATCH /jobs/{id}/draft` (the `upwork_update_draft` REST counterpart) was already
added to `routers/jobs.py` on 2026-06-20 for the browser UI's Save button. The MCP handler
can call the same DB write directly.

---

## `mcp.rheo.ca` vs `api.rheo.ca/mcp`

The server is already registered at `api.rheo.ca/mcp`. Two options:

- **Add alias only**: the new vhost at `mcp.rheo.ca` proxies to the same backend path. Both URLs work. Don't re-register; the existing registration stays.
- **Switch registration**: update the registered URL to `mcp.rheo.ca` and drop the path from the canonical address. Cleaner long-term.

Recommendation: add the alias in this build, switch the registration at the same time so it's done once cleanly.

---

## Open Questions

**Pagination on `upwork_list_jobs`**
A 20-result cap keeps responses token-efficient for the Telegram bot. If there are regularly
more than 20 actionable jobs, add `offset` or cursor pagination. Start capped, add pagination
only if it's needed in practice.

**`upwork_ingest_html` via MCP**
The HTML search-results ingest path (`POST /jobs/ingest-html`) takes a multipart file
upload — awkward to expose as an MCP tool where the argument is a JSON string. Pasting raw
HTML into a tool call is feasible but bulky. Skip for now; the browser "Import Jobs" panel
handles this well.

**Should `upwork_draft_proposal` block?**
Proposal generation calls the LLM and can take 10-20 seconds. The Telegram bot will see
the response delayed. This is acceptable (same as the browser UI's "Generating..."). No
streaming needed in v1.
