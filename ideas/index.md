# Ideas — status index

All ideas tracked in this folder, organized by status. An idea is **done** when its
corresponding run is complete. Detail files hold the full spec; this file is the
at-a-glance view.

---

## Done

| Idea | Run | Detail |
|------|-----|--------|
| **Ministry of Flow** — local dashboard across all installs and runs, Bureau cast avatars, checkpoint status | `20260612-society-desk` (complete) | `done/society-desk.md` |
| **Workflow Registry Visualizer** — Ministry of Flow feature showing each workflow's pipeline structure, agent tiers, checkpoints | `20260613-society-desk-workflow-viz` (complete) | `done/society-desk-workflow-viz.md` |
| **Provider-neutral model routing** — tier-based routing (standard/strong/frontier) across Claude, Codex, Hermes, OpenRouter | Implemented via foundation-contracts batch; `config/runtimes/` + `model-policy.v2.json` exist | `done/provider-neutral-model-routing-plan.md` |

---

## In progress

| Idea | Run | State | Detail |
|------|-----|-------|--------|
| **CryptoWatchTools redesign** — rebrand + 5-workspace sidebar, Movers scanner, Vercel cost cut | `20260614-cryptowatchtools-redesign` | Wave 3a built + dev-verified; paused — Robin decides: more workspaces or deploy | `in-progress/cryptowatchtools-redesign-build.md` |
| **Stakeholder Companion** — project-agent status reader over live framework run artifacts; three-job activation | `20260614-stakeholder-companion` | Dev-verified on feature branch; awaiting merge go-ahead | `in-progress/stakeholder-companion.md` |
| **Ministry System blueprint** — government ops dashboard: M.O.T., M.O.I., domain ministries | `20260614-ministry-system-blueprint` | Blueprint approved; implementation not started | `in-progress/ministry-system.md` |
| **Upwork Sales Desk revival** — no-API triage + M.O.T. integration on rheo.ca | `20260615-upwork-sales-desk` | Analyst complete; rest of feature pipeline pending | `in-progress/upwork-triage-no-api-revival.md` |

---

## Not started

| Group | Index | Notes |
|-------|-------|-------|
| **Agent framework improvements** | [`agent-framework/not-started/index.md`](agent-framework/not-started/index.md) | 15 ranked ideas for making Bureau runs more efficient and less error-prone. Ordered by dependency, then strength. Each idea keeps its own status as it moves to `in-progress/` or `done/` inside `agent-framework/`. |
| **Rheo persistent memory** | [`not-started/rheo-persistent-memory.md`](not-started/rheo-persistent-memory.md) | MOT conversations table + MCP tools (`chat_recent`, `chat_search`) so Rheo remembers across restarts and sessions. |
| **Other** | [`not-started/`](not-started/) | All other not-started ideas. One numbered file per idea. Promote one at a time; run `feature` or the indicated workflow. |
