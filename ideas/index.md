# Ideas — status index

All ideas tracked in this folder, organized by status. An idea is **done** when its
corresponding run is complete. Detail files hold the full spec; this file is the
at-a-glance view.

---

## Done

| Idea | Run | Detail |
|------|-----|--------|
| **Upwork MCP Tools** — 6 job-management tools on `mcp.rheo.ca/mol`; MOT at `mcp.rheo.ca/mot`; unified key | `20260620-upwork-mcp-tools` (complete) | `done/upwork-mcp-tools.md` |
| **Ministry of Flow** — local dashboard across all installs and runs, Bureau cast avatars, checkpoint status | `20260612-society-desk` (complete) | `done/society-desk.md` |
| **Workflow Registry Visualizer** — Ministry of Flow feature showing each workflow's pipeline structure, agent tiers, checkpoints | `20260613-society-desk-workflow-viz` (complete) | `done/society-desk-workflow-viz.md` |
| **Provider-neutral model routing** — tier-based routing (standard/strong/frontier) across Claude, Codex, Hermes, OpenRouter | Implemented via foundation-contracts batch; `config/runtimes/` + `model-policy.v2.json` exist | `done/provider-neutral-model-routing-plan.md` |

---

## In progress

| Idea | Run | State | Detail |
|------|-----|-------|--------|
| **CryptoWatchTools redesign** — rebrand + 5-workspace sidebar, Movers scanner, Vercel cost cut | `20260614-cryptowatchtools-redesign` | Wave 3a built + dev-verified; paused — Robin decides: more workspaces or deploy | `in-progress/cryptowatchtools-redesign-build.md` |
| **Stakeholder Companion** — project-agent status reader over live framework run artifacts; three-job activation | `20260614-stakeholder-companion` | Dev-verified on feature branch; awaiting merge go-ahead | `in-progress/stakeholder-companion.md` |
| **Ministry System blueprint** — government ops dashboard: M.O.T., M.O.I., domain ministries | `20260614-ministry-system-blueprint` + `20260617-moi-spine-reconcile` | **Phase 1 (M.O.T.) BUILT + LIVE** at rheo.ca/mot; **Phase 2 (M.O.I. spine) RECONCILED to Option B** (cloud-routine-as-pipeline + a rheo.ca systemd timer) — spec + plan ready to build (8 sub-phases, AC-1..13); Phases 3+ not started | `in-progress/ministry-system.md` |
| **Upwork Sales Desk revival** — no-API triage + M.O.T. integration on rheo.ca | `20260615-upwork-sales-desk` | Analyst complete; rest of feature pipeline pending | `in-progress/upwork-triage-no-api-revival.md` |
| **Rheo persistent memory** — MOT conversation ledger + MCP recall tools, moving toward layered agent-managed memory | out-of-band start `2026-06-15`; framework run pending | Layer 0 + Layer 4 v1 built directly; needs Challenger review, blocker routing, then Mechanic deploy | `in-progress/rheo-persistent-memory.md` |

---

## Not started

| Group | Index | Notes |
|-------|-------|-------|
| **Agent framework improvements** | [`agent-framework/index.md`](agent-framework/index.md) | Consolidated execution roadmap for Bureau improvements, including the Rheo memory framework-integration track. |
| **Novadiem Vault** | [`not-started/novadiem-vault.md`](not-started/novadiem-vault.md) | Self-hosted MCP secrets vault — encrypted SQLite + macOS Keychain master key, replaces iCloud key files, Claude reads/writes via MCP tools. |
| **YouTube Channel Digest** | [`not-started/youtube-channel-digest.md`](not-started/youtube-channel-digest.md) | Grouped YouTube channel monitoring (RSS) → per-group `claude -p` analysis → 2×/day Telegram digest, on the rheo.ca box. First launch: the trading group (Chart Hackers + MooninPapa + 100x Club) → Blofin trading-setup extraction (Chart Hackers is the proven prompt). Future **M.O.I. adapter** (files M.O.T. tickets via the spine's chosen on-box interface) — ties into `20260617-moi-spine-reconcile`. Blocker: datacenter-IP transcript fetch needs a home relay. Spec: `rheo.ca/docs/youtube-channel-digest.md`. |
| **Other** | [`not-started/`](not-started/) | All other not-started ideas. One numbered file per idea. Promote one at a time; run `feature` or the indicated workflow. |
