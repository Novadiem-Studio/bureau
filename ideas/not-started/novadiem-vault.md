# Novadiem Vault — Self-Hosted Secrets MCP

Date: 2026-06-16
Status: not started

---

## One-liner

A local MCP stdio server backed by an encrypted SQLite database that gives
Claude read/write access to all project secrets — replacing scattered `.env`
files and iCloud-synced key folders with a single, encrypted, audited vault
that only runs on Robin's machine.

---

## Problem

Project secrets (API keys, app passwords, DB credentials, SSH passphrases)
currently live in `~/Documents/novadiem/keys/` as plain `.env` files synced
to iCloud. Three problems:

1. **iCloud = third-party trust.** Apple encrypts at rest but holds the keys.
   Account compromise exposes everything. Advanced Data Protection helps but
   still relies on Apple's infrastructure.

2. **Claude can only read via file paths.** There's no canonical interface —
   sessions reference different paths, files drift out of sync, and writing
   back (e.g. updating a key after rotation) requires knowing the exact file
   location. There's no "write the new MOT API key to the vault" — only
   "edit this specific file at this path."

3. **No audit trail.** Nothing records which session read which key, when a
   key was last rotated, or which projects depend on it.

---

## Solution

A Python MCP stdio server — spawned locally by Claude Code, communicates over
stdin/stdout, no network port — backed by a SQLite database at
`~/.novadiem/vault.db`. Secret values are encrypted at rest using Fernet
(AES-128-CBC + HMAC) with a master key stored in the macOS Keychain (Touch
ID protected). The database file can live anywhere; the decryption key never
touches disk.

Claude gets five tools:

```
vault_get(key)                  → decrypted value (string)
vault_set(key, value, desc?, tags?)  → stores/updates entry
vault_list(filter?)             → keys + metadata, NO values
vault_delete(key)               → removes entry + audit record
vault_search(q)                 → search by key name or description
```

A one-time migration script imports the existing `~/Documents/novadiem/keys/`
env files into the vault, then the source files can be removed or kept as
read-only backups.

---

## Architecture

```
Claude Code session
    │  (MCP stdio)
    ▼
vault-server.py           Python, spawned by Claude Code on demand
    │
    ├── Keychain           macOS Keychain → master Fernet key (never on disk)
    │   (keyring lib)
    │
    └── ~/.novadiem/vault.db   SQLite, all values AES-encrypted
            ├── secrets        (key, encrypted_value, description, tags, created_at, updated_at)
            └── audit_log      (key, action, session_hint, ts)
```

**Why stdio, not HTTP?**
stdio MCP servers are spawned as child processes by Claude Code. Zero network
exposure, no auth token needed, no port to secure. If the machine is
compromised enough to intercept the stdio pipe, the game is already over.

**Why Keychain for the master key?**
The master Fernet key never touches disk or env vars. It's stored in macOS
Keychain under a named entry (`novadiem-vault`) and retrieved at runtime via
the `keyring` library. Touch ID protects Keychain access on an M-series Mac.
Even if the `vault.db` file is exfiltrated, it's useless without the key.

**Why not encrypt the SQLite file itself (SQLCipher)?**
SQLCipher requires a custom SQLite build. Per-value Fernet encryption with a
Keychain-managed key achieves the same goal with pure-Python dependencies and
no build step. It also lets the audit log and metadata remain queryable without
full decryption.

---

## Key Naming Convention

`<project>.<service>.<variable>` — dot-separated, lowercase, no spaces.

```
rheo.ca.RHEO_API_KEY
rheo.ca.MOT_API_KEY
rheo.ca.DB_PASSWORD
rheo.ca.DEEPSEEK_API_KEY
nutrifax.OPENROUTER_KEY
nutrifax.DB_PASSWORD
gmail.GMAIL_APP_PASSWORD
novadiem.SMTP2GO_PASS
lightsail.SSH_KEY_PATH
mot.MOT_API_KEY
```

Tags group secrets by project for filtered listing: `vault_list("rheo.ca")`.

---

## MCP Tool Spec

### `vault_get(key: str) → str`

Returns the decrypted secret value. Logs `{key, action: "read", ts}` to
`audit_log`. Raises if key not found or Keychain access fails.

### `vault_set(key: str, value: str, description: str = "", tags: list[str] = []) → None`

Upserts an entry. Encrypts `value` with the Fernet key before writing.
Logs `{key, action: "write", ts}`. Tags are stored as comma-separated text.

### `vault_list(filter: str = "") → list[dict]`

Returns all entries matching `filter` (substring match on key name or tags).
Returns `{key, description, tags, updated_at}` — **never the value**.
Safe to call in any context.

### `vault_delete(key: str) → None`

Removes the entry. Logs `{key, action: "delete", ts}`. Requires confirmation
in the tool's description (Claude should confirm with user before calling).

### `vault_search(q: str) → list[dict]`

Full-text search over key names and descriptions. Returns same shape as
`vault_list`. Values never included.

---

## Security Model

| Threat | Mitigation |
|--------|-----------|
| iCloud account compromise | `vault.db` lives in `~/.novadiem/` — excluded from iCloud sync by default (dot-prefixed hidden dir) |
| `vault.db` exfiltrated | All values Fernet-encrypted; useless without Keychain master key |
| Keychain master key stolen | Keychain requires macOS auth / Touch ID; not accessible remotely |
| Rogue Claude Code session reads all secrets | `audit_log` records every `vault_get` call with a session hint; anomalous bulk reads are visible |
| Plain-text value appears in Claude context | Tool returns decrypted value to Claude; Claude should not echo it back to the user — document this in tool description |

**What this doesn't protect against:** a malicious process running as Robin's
user on the same machine can call `vault_get` too. This is local-process trust,
not multi-tenant security. It's substantially better than a plaintext file in
iCloud, not a HSM.

---

## Migration Plan

1. Build and register the vault MCP server.
2. Run `scripts/migrate_keys.py` — reads all `.env` files under
   `~/Documents/novadiem/keys/`, imports each `KEY=VALUE` pair into the vault
   with auto-derived key names and source path as description.
3. Verify with `vault_list()` that all expected keys are present.
4. Update any sessions/scripts that reference old file paths to use
   `vault_get` instead.
5. Archive `~/Documents/novadiem/keys/` to an encrypted zip on a USB key,
   then remove the folder from iCloud-synced storage.

---

## Dependencies

All pure Python, pip-installable, no system packages:

```
cryptography      # Fernet encryption
keyring           # macOS Keychain access
mcp               # Anthropic MCP Python SDK
```

Total install footprint: small. No Docker, no server process, no port.

---

## File Layout

```
~/Code/novadiem/vault-mcp/
├── vault_server.py       # MCP server (stdio)
├── vault_store.py        # SQLite + Fernet abstraction
├── scripts/
│   ├── init_vault.py     # First-time setup: creates db, generates + stores Fernet key in Keychain
│   └── migrate_keys.py   # Bulk import from ~/Documents/novadiem/keys/
├── requirements.txt
└── README.md             # Setup + cron; key naming convention
```

Database at `~/.novadiem/vault.db` (separate from the code repo — never committed).

---

## Claude Code Registration

Add to `~/.claude/mcp_servers.json` (or equivalent Claude Code MCP config):

```json
{
  "novadiem-vault": {
    "command": "python3",
    "args": ["/Users/robin/Code/novadiem/vault-mcp/vault_server.py"],
    "description": "Novadiem secrets vault — read/write encrypted project keys"
  }
}
```

Claude Code spawns the process on first tool call and keeps it alive for the
session. No manual startup needed.

---

## Success Criteria

- `vault_get("rheo.ca.RHEO_API_KEY")` returns the correct value in any Claude
  Code session without reading a file path.
- `vault_list("rheo.ca")` returns all rheo.ca secrets with metadata but no
  values.
- `vault_set(...)` from a Claude session persists across restarts.
- `~/.novadiem/vault.db` contains no plaintext values — all entries are
  Fernet ciphertext.
- Audit log shows every read and write with timestamp.
- Migration script imports all existing key files with zero manual entries.
- No key file in iCloud after migration.

---

## Open Questions

**Keychain vs. hardcoded master password**
Keychain is cleaner (Touch ID, no password to remember or type), but requires
macOS and the `keyring` library. A password-derived key (PBKDF2 + user-typed
passphrase) would be more portable. Start with Keychain; add passphrase
fallback if needed on other machines.

**Multi-machine access**
The vault is local-only by design. If Robin works across two Macs, the vault
doesn't sync. Options: (a) accept this limitation, (b) sync `vault.db` via
a non-iCloud mechanism (encrypted rsync to the rheo.ca box, fetch on demand),
(c) run a vault server on rheo.ca with mTLS. Start with local-only and revisit.

**Key rotation reminders**
The vault knows `updated_at` per key. A future `vault_stale(days=90)` tool
could flag keys not rotated in >90 days. Not v1, but the schema supports it.

**Should the vault itself be in the Bureau framework repo?**
It's general infrastructure, not a project-specific tool. A standalone repo
(`novadiem/vault-mcp`) keeps it independent and reusable. The framework can
reference it as an external dependency.
