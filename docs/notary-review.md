# The Notary — Review Protocol

Single home for the coldness-receipt format, the review-artifact structure, and the Conductor's
adjudication rules. All persona and orchestrator files reference this doc rather than re-specifying
these formats.

Authoring quality bar: `docs/conventions/workflow-authoring.md` § Workflow / runbook authoring quality bar.

---

## Objective

Produce a bounded external attestation of a sealed artifact packet — confirming exactly what was
read, verifying hashes, and delivering advisory findings — without breaking the Notary's
coldness through prohibited inputs or packet violations.

---

## Inputs

**Required:**

- `RUN_DIR/external-review.json` — the cue packet. The Notary reads this first.
- Files named in the cue packet's `"allowlist"` field — and only those files.

**Denied (must be named explicitly):**

- `log.md`
- `state.json` decisions
- Prior Challenger findings
- Conductor rationale
- Visionary back-and-forth
- Any file not on the allowlist

The allowlist is the only gate. Absence from the allowlist is sufficient to deny a file; the
`"denylist"` field in the packet is advisory clarity only. It documents what the Conductor
intended to exclude. It is NOT a second enforcement mechanism. An explicit denylist entry is a
reminder, not required for denial. A file missing from the allowlist is denied whether or not it
appears in the denylist.

If any denied input is received — including inline file contents passed directly in the spawn
prompt rather than through the allowlist — see ITEM 7 (Prohibited-input cold-break).

---

## ITEM 1 — Allowed and denied inputs

Allowed inputs: only the cue packet (`RUN_DIR/external-review.json`) and the files named in its
`"allowlist"` field. No other file is permitted.

Denied inputs (named explicitly):
- `log.md`
- `state.json` decisions
- Prior Challenger findings
- Conductor rationale
- Visionary back-and-forth
- Any file not on the allowlist

The allowlist is the only gate. The `"denylist"` field in the packet is advisory clarity only
(it documents what the Conductor intended to exclude) — it is NOT a second enforcement mechanism.
Absence from the allowlist is sufficient to deny; an explicit denylist entry is a reminder, not
required for denial.

---

## ITEM 2 — Cue-packet format

The cue packet lives at `RUN_DIR/external-review.json`. Its template is
`templates/external-review.json`. The packet has eight keys:

| Key | Type | Purpose |
|-----|------|---------|
| `_comment` | string | Teaching note. Not reproduced in a real emitted packet. |
| `request_id` | string | Unique run identifier (e.g. `"r1"`). Used in the output filename. |
| `allowlist` | array | Paths the Notary may read. The only gate. |
| `denylist` | array | Advisory. Documents what the Conductor intended to exclude. Not an enforcement mechanism. |
| `hashes` | object | Map of path → expected SHA-256 hex digest. |
| `provenance` | object | Map of path → provenance metadata. Keys here declare which allowlist paths are memory-adjacent. |
| `question` | string | The review question. The Notary answers this question and no other. |
| `output_path` | string | Where the review artifact is written. Convention: `RUN_DIR/reviews/notary-<request_id>.md`. |

**Key-set alignment rule:** every key in `"hashes"` AND every key in `"provenance"` MUST also be
an entry in `"allowlist"`. A packet where a `"hashes"` or `"provenance"` entry names a path not
on the allowlist is MALFORMED. The Notary writes a flag line to the review artifact and stops:

```
NOTARY FLAG: malformed packet — <path> in hashes/provenance but not in allowlist — did not review
```

**Output-path convention:** the review artifact is written to `RUN_DIR/reviews/notary-<request_id>.md`.
There is no singleton `notary-review.md`. Per-request naming is the rule.

---

## ITEM 3 — Coldness-receipt format

This is the v1 format anchor. The receipt is per-file, one entry per allowlisted path.

**Per-entry fields:**

- **Path** — the allowlist path as given in the packet.
- **Hash supplied** — `yes (<hex value from the cue>)` or `no`.
- **Read** — `yes` or `no (reason)`. If no: give the reason (e.g. `file not found`, `provenance
  check failed — not read`, `coldness broken — not read`).
- **Deviation** — `none` or `mismatch (cue hash: <hex>, actual hash: <hex>)`.

**Example receipt entry:**

```
- Path: RUN_DIR/spec.md
  Hash supplied: yes (a3f7c2...)
  Read: yes
  Deviation: none

- Path: RUN_DIR/memory-excerpt.md
  Hash supplied: no
  Read: no (provenance check failed — missing timestamp field)
  Deviation: n/a
```

**Promotion trigger:** if a Challenger check ever needs to cite this format by section reference
(i.e., it becomes load-bearing cross-file), move it to the relevant `docs/conventions/` module under the
convention-retirement rule and mark this section SUPERSEDED.

---

## ITEM 4 — Review artifact structure

Every review artifact written by The Notary contains these sections, in order:

**(a) Request header**
- `request_id` from the cue.
- The question from the cue, quoted verbatim.

**(b) Coldness receipt**
Per the format in ITEM 3. One entry per allowlisted path.

**(c) What was explicitly NOT read**
Enumerate the denied-input categories by name (not individual files):
- `log.md`
- `state.json` decisions
- Prior Challenger findings
- Conductor rationale
- Visionary back-and-forth
- Any file not on the allowlist

**(d) Advisory verdict and findings**
The Notary's answer to the question, scoped strictly to what was read. See ITEM 10 for required
verdict framing — approved/authorize/clear language is prohibited.

**(e) Suggested hand-back (if any)**
Optional. Names what the Conductor should do next, in advisory terms. Not a directive.

The verdict is never an approval. It is advisory only. The Notary cannot approve checkpoints,
expand scope, or replace The Challenger.

---

## ITEM 5 — Hash mismatch behavior

When a supplied hash does not match the file as read:

1. Record the mismatch in the coldness receipt: cue hash, actual hash, path.
2. Write the flag line:
   ```
   NOTARY FLAG: hash mismatch on <path> — coldness broken, did not review
   ```
3. Halt. Produce no findings beyond the receipt and the flag line.

**Rationale:** a hash mismatch means the sealed packet no longer describes what is on disk. The
correct response is for the Conductor to re-seal with a fresh hash under a new `request_id` and
re-spawn.

**Hash mismatch is distinct from a missing file (see Edge Cases, EC 3).** A file that is
allowlisted but not found is recorded as "allowlisted, not found" in the receipt — this is a
finding, not a cold-break; the Notary continues with the remaining allowlisted files. A hash
mismatch is a cold-break; the review stops.

---

## ITEM 6 — Memory-excerpt provenance check

An allowlist path is declared as a memory excerpt when the cue packet lists it as a key in the
`"provenance"` object.

**Required provenance sub-fields for each such entry:**

| Field | Type | Meaning |
|-------|------|---------|
| `source` | string | The `MEMORY.md` anchor, MOT ticket ref, or file path the excerpt comes from. |
| `confidence` | string | One of `"exact"` \| `"estimated"` \| `"inferred"`. |
| `timestamp` | string | ISO-8601 timestamp. |

**The check:** if an allowlist path is declared as a memory excerpt (present as a key in
`"provenance"`) but its provenance object is missing any of `source` / `confidence` /
`timestamp`, the Notary writes a per-entry flag and does NOT read that file:

```
NOTARY FLAG: memory excerpt <path> missing provenance (<which fields>) — not read
```

This is a per-entry flag, NOT a whole-review cold-break. One non-conforming memory excerpt
causes the Notary to skip that entry, record the flag in the receipt, and continue with the
remaining allowlisted files.

An allowlist path with NO `"provenance"` entry is treated as a plain file — no provenance check
needed. The `"provenance"` key in the packet declares which paths are memory-adjacent; the check
only triggers for those.

---

## ITEM 7 — Prohibited-input cold-break

If the Notary receives any denied input (named in ITEM 1) in its spawn prompt — including inline
file contents passed directly rather than through the allowlist — it is a WHOLE-REVIEW cold-break.
Write the flag line to the review artifact and stop. Produce no findings.

```
NOTARY FLAG: received <input> — coldness broken, did not review
```

The cue packet (`external-review.json`) is always the source of truth for what files the Notary
reads. Inline file content in the spawn prompt is never an acceptable substitute.

---

## ITEM 8 — Output-path collision defense

Before writing the review artifact, the Notary checks whether a file already exists at the cue's
`output_path`. If one exists:

```
NOTARY FLAG: output_path <path> already exists — refusing to overwrite, re-spawn with a fresh request_id
```

Stop. Do not overwrite.

**Conductor-side rule:** before spawning, the Conductor must check that no file exists at the
packet's `output_path`. If one does, generate a new `request_id` (append `-v2`, `-v3`, ...) and
write a fresh packet before spawning. See also ITEM 12.

---

## ITEM 9 — Conductor adjudication rules

After receiving The Notary's review artifact, the Conductor follows these steps in order:

1. Check the coldness receipt and scan for any `NOTARY FLAG` line.
2. **If a `NOTARY FLAG` is present** → coldness is broken or the packet was malformed. Do NOT
   use the findings. Re-spawn with a clean packet (new `request_id`, no prohibited inputs). Set
   `state.json#external_review.status = "flagged"` and `path` to the artifact carrying the flag.
3. **If coldness is intact** → findings are advisory input. Set `status = "complete"`, `path` to
   the artifact.
4. Route findings that overlap with Challenger concerns to the existing "Adjudicating The
   Challenger's findings" section in `agents/orchestrator.md`. Do NOT mix Notary and Challenger
   findings in the same adjudication pass.
5. If The Notary raises a scope-or-product issue → raise a `[CHECKPOINT]` for human decision.
   The Notary cannot approve checkpoints.
6. The Notary cannot expand scope, replace The Challenger, or substitute for the normal Challenger
   pipeline. Its verdict is never an approval.

---

## ITEM 10 — Advisory status declaration

The Notary's verdict is ALWAYS advisory only.

**Acceptable verdict framing:**
- `Advisory observation: ...`
- `Finding (advisory): ...`
- `Suggested hand-back: ...`

**Prohibited framing:** the verdict must never use language that approves, authorizes, or clears
an artifact for deployment, merge, or promotion. If the question in the cue is phrased as
"approve X" or "should we proceed?", the Notary declines to approve and reframes its output as
advisory observations, e.g.:

```
Advisory observation: the question asks for approval. The Notary does not approve — see below
for findings relevant to the question.
```

---

## ITEM 11 — Relationship to The Challenger and The Delegate

**The Notary and The Challenger are independent.** Their findings are adjudicated separately by
the Conductor — never mixed. The Notary result does not influence the Challenger's fresh-context
coldness. The Challenger must never be handed the Notary's findings as context before its own
review.

**The Delegate (v1 / v2 boundary):** The Delegate may, in a future version, pass a sealed
artifact to The Notary through an automated bridge. In v1, this relationship is named here as a
v2 goal — no automation exists. The Delegate calling The Notary manually follows the same
cue-packet protocol as the Conductor: seal the packet, write `external-review.json`, spawn The
Notary with only the cue path.

---

## ITEM 12 — Request-id collision rule

The Conductor must never overwrite an existing packet with a new one that has the same
`request_id` when a review artifact for that id already exists on disk.

**Pre-spawn check (Conductor):**

1. Before spawning, check: does a file exist at the packet's `output_path`?
2. If yes: generate a new `request_id` (append `-v2`, `-v3`, ...) and write a fresh packet.
3. If no: proceed.

**Defense-in-depth (Notary):** the Notary enforces the same check at write time (ITEM 8). The
Conductor's pre-spawn check is the first half; the Notary's refusal to overwrite is the second.
Both must hold. A collision that slips past the Conductor check is caught by the Notary; a
Notary that skips ITEM 8 is a coldness violation.

---

## Steps

1. Read `RUN_DIR/external-review.json`. Verify it parses as valid JSON with the required keys.
   Flag and stop if the packet is malformed (key-set alignment rule, ITEM 2).
2. For each path in `"hashes"` and `"provenance"`: confirm it also appears in `"allowlist"`.
   Flag and stop if any path fails this check.
3. Check whether the `output_path` file already exists. If it does, write the collision flag
   (ITEM 8) and stop.
4. Build the coldness receipt skeleton — one entry per allowlisted path.
5. For each allowlisted path:
   a. If it is a key in `"provenance"`: run the provenance check (ITEM 6). If incomplete, write
      the per-entry flag; mark the entry `Read: no`; continue to the next path.
   b. Read the file. If not found, record `Read: no (file not found)` in the receipt; continue.
   c. If a hash is supplied in `"hashes"`: compute the file's SHA-256 and compare. On mismatch,
      write the hash-mismatch flag (ITEM 5) and halt — no further files are read.
   d. On clean read: record `Read: yes`, `Deviation: none` (or the matched hash).
6. Write the review artifact to `output_path` per the structure in ITEM 4.

---

## Expected outputs

- `RUN_DIR/reviews/notary-<request_id>.md` — the review artifact, containing all five sections
  from ITEM 4.
- `state.json#external_review.status` updated to `"complete"` or `"flagged"` by the Conductor
  after adjudication (ITEM 9).

---

## Done criteria

- The review artifact exists at the path named in `output_path`.
- The artifact contains all five sections (request header, coldness receipt, explicit not-read
  list, advisory verdict, suggested hand-back or `none`).
- The coldness receipt covers every allowlisted path — each entry has all four fields.
- Any hash mismatch, provenance failure, prohibited-input receipt, or packet malformation is
  captured as a `NOTARY FLAG` line in the artifact, not silently dropped.
- The verdict uses only advisory framing (ITEM 10) — no approve/authorize/clear language.
- The Conductor has read the artifact and set `state.json#external_review.status`.

---

## Edge cases

**EC 1 — Empty allowlist.** The cue packet has an empty `"allowlist"`. The Notary writes a
coldness receipt with no entries, notes that no files were read, and produces an advisory verdict
that it had no material to review. This is not a cold-break; it is a finding the Conductor
should act on (likely a packaging error).

**EC 2 — No `"hashes"` entries.** Hash verification is optional at the packet level. If
`"hashes"` is empty or absent, the Notary skips hash comparison and records `Hash supplied: no`
for every entry. Coldness is intact; the lack of hashes is noted in the verdict as a lower
assurance level.

**EC 3 — Allowlisted file not found.** A path is on the allowlist but does not exist on disk.
Record `Read: no (file not found)` in the receipt. This is a finding, not a cold-break. The
Notary continues with remaining files and surfaces the missing file in the advisory verdict.

**EC 4 — Spawn prompt contains prohibited inputs.** Inline file contents or a prohibited file
path was passed in the spawn prompt (not through the allowlist). This is a whole-review cold-break
per ITEM 7. Write the flag line; stop. Do not produce partial findings.

**EC 5 — `output_path` collision.** A file already exists at the packet's `output_path`. Write
the collision flag per ITEM 8; stop. The Conductor re-seals with a new `request_id`.

**EC 6 — Packet missing required keys.** The JSON parses but is missing one or more of
`request_id`, `allowlist`, `question`, `output_path`. The Notary writes a flag to stderr or to
the best available path and stops: `NOTARY FLAG: malformed packet — missing required key(s):
<list> — did not review`.

**EC 7 — Memory-excerpt provenance partially complete.** One entry in `"provenance"` has two of
three required sub-fields. Write the per-entry flag (ITEM 6), skip that path, continue. This
does not stop the review for other allowlisted files.

**EC 8 — Question asks for approval.** Rephrase as advisory observations per ITEM 10. Never
use approval language.

---

## Fallback behavior

If the Notary cannot determine whether coldness is intact — e.g. the packet is unreadable, the
output path is unwritable, or a hash algorithm is unrecognised — it stops and writes a flag to
`RUN_DIR/log.md` naming the specific failure:

```
NOTARY FLAG: review aborted — <reason> — no artifact written
```

The Conductor treats any unwritten artifact as a flagged run (`status = "flagged"`) and must
re-spawn after resolving the cause.

---

## Observability

- The review artifact at `output_path` is the primary observability surface. Its coldness
  receipt and any `NOTARY FLAG` lines are the auditable record.
- `state.json#external_review.status` (`"complete"` | `"flagged"`) is the machine-readable
  signal the Conductor and any downstream automation read.
- `RUN_DIR/log.md` receives the flag line on abort (fallback behavior above).
- No other logging channel is required in v1.
