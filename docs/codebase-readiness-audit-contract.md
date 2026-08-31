# Codebase Readiness Audit Contract

This document is the sole normative v1 contract for Codebase Readiness Audit artifacts,
states, ownership, publication, and downstream authorization. Workflows, agents, adapters, and
tests MUST point here instead of restating its schemas or inventing compatible variants. A record
with an unknown field value where this contract declares a closed enum, a missing required field,
or an owner other than the one named here is malformed and MUST stop the affected transition.

All paths below are relative to `RUN_DIR` unless stated otherwise. All hashes are lowercase
hexadecimal SHA-256 values of the exact file bytes. An artifact described as immutable is created
through a same-directory temporary file and an atomic no-clobber publication; an existing target
is never removed, truncated, normalized, repaired, or replaced.

### Safe path-bearing identifiers

Every `attempt_id`, `output_id`, and `approval_id`, and any future identifier interpolated into an
artifact path, uses this exact byte grammar:

```text
\A[a-z0-9](?:[a-z0-9-]{0,62}[a-z0-9])?\z
```

The value is 1–64 ASCII bytes, begins and ends with a lowercase ASCII letter or digit, and has
only lowercase ASCII letters, digits, or `-` between them. The executable reference validator is:

```sh
python3 -c 'import re,sys; b=sys.argv[1].encode("utf-8"); raise SystemExit(0 if re.fullmatch(rb"[a-z0-9](?:[a-z0-9-]{0,62}[a-z0-9])?", b) else 1)' "$1"
```

Validation applies to the raw supplied value before any path is constructed. Implementations MUST
reject an invalid value; they MUST NOT trim, case-fold, Unicode-normalize, percent-decode, replace
characters, collapse separators, or otherwise turn it into a valid value. Thus two raw values can
never be accepted as one normalized identifier. A NUL, non-ASCII byte, `.`, `/`, `\`, whitespace,
leading or trailing `-`, or a value outside the byte-length bound is invalid.

After validation, the adapter concatenates the identifier only into the fixed paths named by this
contract. It resolves and verifies the already-existing parent directory without following a
symlink supplied by the packet, rejects every symlink component, and proves that the constructed
parent equals the authorized parent before an exclusive create. A path that escapes, resolves
outside, normalizes to a different target, names an existing object, or collides under the host
filesystem's case/normalization behavior is rejected before provider invocation. `attempt_id`
names `<attempt_id>-packet/`, `<attempt_id>-result/`, and `verdicts/<attempt_id>.json`;
`approval_id` names `audit/execute-plan-approvals/<approval_id>.json`. If `output_id` names an
adapter result member, that member is exactly `<output_id>.json` directly under the validated
`<attempt_id>-result/` directory; it cannot supply a subpath.

## Machine-readable JSON conventions

Every JSON artifact defined here is exactly one RFC 8259 object encoded as UTF-8 without a byte
order mark, leading/trailing non-whitespace bytes, or trailing JSON value. Parsers MUST reject
duplicate object keys at every nesting depth before validation. Each schema table below is an
exact key set: every listed key is required unless its conditional rule says it MUST be omitted,
and every unknown key is rejected. JSON `null` is never accepted. Types are exact: a Boolean is
not an integer, an integer is not a string, and an object/array is not accepted for a scalar.

Common machine types are normative:

| Type | Exact JSON type and validation |
|---|---|
| `schema-version` | JSON integer with the sole permitted value `1`. |
| `sha256` | JSON string matching `^[0-9a-f]{64}$`. |
| `audit-version` | JSON string matching `^v[0-9]{4}$` whose numeric suffix is in `0001..9999`; `v0000` is invalid. |
| `timestamp` | JSON string in UTC RFC 3339 second precision, exactly `YYYY-MM-DDTHH:MM:SSZ`; components MUST form a real Gregorian instant. Fractional seconds and offsets other than `Z` are invalid. |
| `date` | JSON string exactly `YYYY-MM-DD` representing a real Gregorian date. |
| `safe-id` | JSON string whose UTF-8 bytes satisfy **Safe path-bearing identifiers**: 1–64 ASCII bytes and the exact grammar there. Every machine field ending in `_id` uses this type unless a table explicitly says otherwise. |
| `bounded-text` | JSON string containing 1–2000 UTF-8 bytes, valid Unicode scalar values, and no NUL, C0, C1, or DEL control character. Used only for `review_question`. |
| `identity-text` | JSON string containing 1–256 UTF-8 bytes, valid Unicode scalar values, no control character, and no leading or trailing Unicode whitespace. Used only for human identity display fields. |
| `relative-artifact-path` | JSON string containing the exact `/`-separated path relative to `RUN_DIR` named by its schema row; no absolute, empty, `.`, `..`, backslash, symlink, or normalization alias is accepted. |
| `boolean` | JSON Boolean `true` or `false`. |
| `positive-integer` | JSON integer in `1..2147483647`; Booleans are invalid. |
| `nonnegative-integer` | JSON integer in `0..2147483647`; Booleans are invalid. |
| `object` | JSON object with the exact keys declared by its row/table. |
| `array` | JSON array in the declared order with elements of exactly the declared type. |

These bounds apply only to machine-readable identifiers and fields named above. Markdown product
contracts, findings, evidence, and audit prose have no arbitrary length bound from this section.

## Closed enums

The following enums are closed. There are no aliases and no implicit defaults.

- Audit profile: `catalog | full | audited`.
- Evidence classification: `verified | inferred | unverifiable`.
- Finding disposition:
  `implementation_defect | intentional_tradeoff | deferred_work | non_goal | owner_question`.
- Domain applicability: `applicable | excluded`.
- Completeness: `complete | incomplete`.
- Conclusiveness: `conclusive | non-conclusive`.
- Cold-review verdict: `BLOCKED | APPROVED_WITH_WARNINGS | APPROVED`.
- Version-index event: `corrected | sealed`.

Every substantive finding, evidence claim, and overall readiness conclusion MUST carry exactly
one evidence classification. `verified` and `inferred` require an `evidence_reference` and no
`unavailable_evidence_reason`; `unverifiable` requires an `unavailable_evidence_reason` and no
`evidence_reference`. New evidence may raise a classification in a new corrected-audit version;
reconciliation alone MUST NOT promote `inferred` to `verified`.

## Intake and profile selection

`audit/profile.md` is required before an audit agent is spawned and contains:

- `profile`: exactly one of `catalog | full | audited`;
- `target_repository`, `target_ref`, and `target_commit`: the authorized repository boundary,
  requested ref, and immutable audited commit;
- `intent_sources`: supplied product-intent sources, including owner statements when available;
- `runtime_instructions`: supplied local or synthetic procedure, or an explicit absence;
- `credential_policy`: allowed credentials and data; production credentials and live customer
  data are excluded unless separately and explicitly authorized;
- `audit_authorization`: permitted reads and commands plus prohibited actions.

There is no default profile. A missing or unknown profile, unreadable target repository or ref,
or missing authorization stops intake before an audit agent is spawned. The packet remains bound
to `target_commit` even if the target changes during the run; a newer commit requires a new audit
run or version. Repository size has no fixed limit: the Conductor batches independent passes
within the host concurrency cap and checkpoints when the authorized runtime cannot finish within
the operator's stated constraints.

The profiles share every record in this contract and differ only in depth and gates:

- `catalog` performs independent static deep-read coverage for every applicable domain. It
  attempts an already-supplied and authorized local procedure and records its observed outcome,
  but does no setup work to create a runnable environment. When absent it records exact
  disposition `not-supplied`; archival uses `archival-no-probe`.
- `full` adds isolated local stand-up, synthetic lifecycle probes, and runtime verification where
  technically possible. Every setup-only change is quarantined.
- `audited` includes all `full` obligations and adds a fresh premium Challenger cold review of
  the exact corrected-audit version before every seal.

## Product-intent contract

`audit/product-contract.md` is required before readiness findings or conclusions are produced.
It contains:

- intended product or use case, target user, business or operating workflow, readiness goal,
  and supplied deadline;
- audit boundary, supplied evidence, excluded areas, and owner questions;
- every material intent source, independently classified by claim type, authority,
  freshness/precedence, and source location;
- settled decisions, intentional tradeoffs, non-goals, and deferred work;
- for each owner question, the exact decision or conclusion it blocks.

A missing or materially conflicting product-intent contract stops readiness evaluation. The run
may retain only an `incomplete`/`non-conclusive` evidence packet containing the contract gap,
boundaries, evidence inventory, and blocked owner questions; it MUST NOT contain readiness
findings or a recommendation.

Every excluded area is repeated in the final scope boundaries with the statement `not audited`.
If every baseline and product-specific domain is excluded, completeness is `incomplete` and the
result is `non-conclusive`. Zero findings is valid only when each applicable domain has a
completed coverage record.

## Domain register and independent coverage

`audit/domain-register.md` contains the following six baseline domains, each marked `applicable`
or `excluded`:

1. data/business correctness
2. security/authorization
3. schema/drift/deploy
4. feature completeness
5. code health
6. architecture/scale

An excluded domain requires a reason and is a final scope boundary. Product-intent-driven domains
may be added, but use the same record shape. Every applicable domain has one fresh, independently
recorded file under `audit/coverage/` containing:

- `domain_id` and `applicability: applicable`;
- reviewer attempt identifier;
- evidence inspected and coverage performed;
- limitations;
- candidate findings.

Independent passes MUST be preserved as records. A shallow repository scan or a summary from one
reviewer cannot substitute for the domain records. Partial coverage is explicit and contributes
to completeness and evidence ceilings; it is never silently treated as completed coverage.

### Coverage completion ledger

`audit/coverage-index.ndjson` is mandatory, append-only, and Conductor-owned. The Conductor creates
it no-clobber, validates it from byte zero before every append or consumption, and serializes each
compact UTF-8 JSON line with raw-ASCII lexicographically sorted keys. Immediately after each
coverage record is published no-clobber, the Conductor hashes it and appends one exact event:

| Key | Type | Constant or rule |
|---|---|---|
| `schema_version` | `schema-version` | `1`. |
| `event` | JSON string | Exactly `coverage-completed`. |
| `sequence` | `positive-integer` | Starts at `1`, then contiguous. |
| `domain_id` | `safe-id` | Unique and equals the record domain. |
| `coverage_path` | `relative-artifact-path` | Exactly `audit/coverage/<domain_id>.md`. |
| `coverage_sha256` | `sha256` | Exact immutable record hash. |
| `reviewer_attempt_id` | `safe-id` | Equals the record attempt. |
| `recorded_at` | `timestamp` | Append time. |

The Conductor then appends exactly one terminal event:

| Key | Type | Constant or rule |
|---|---|---|
| `schema_version` | `schema-version` | `1`. |
| `event` | JSON string | Exactly `coverage-closed`. |
| `sequence` | `positive-integer` | One after the final completion, or `1` when none exists. |
| `closure_reason` | JSON string | Exactly `all-applicable-completed`, `unresolved-intent`, `all-domains-excluded`, or `partial-coverage-archival`. |
| `domain_register_path` | `relative-artifact-path` | Exactly `audit/domain-register.md`. |
| `domain_register_sha256` | `sha256` | Exact register hash. |
| `completed_count` | `nonnegative-integer` | Exact completion-event count. |
| `completed_set_sha256` | `sha256` | Canonical digest below. |
| `recorded_at` | `timestamp` | Closure time. |

The completed-set digest is SHA-256 of a compact UTF-8 JSON array of exact
`{"path":<coverage_path>,"sha256":<coverage_sha256>}` objects sorted by unsigned bytewise raw-ASCII
path, with no whitespace or trailing newline. Zero completions is valid only for
`unresolved-intent` or `all-domains-excluded`; normal closure requires every applicable domain and
partial archival closure a nonempty proper subset. Nothing may append after closure. A missing,
added, reordered, duplicate, changed, unproduced, or post-closure event/record, or wrong
sequence/count/reason/digest/path/hash, invalidates reconciliation and sealing. There is no repair
or identical-event append.

## Evidence and finding records

Each candidate and reconciled finding contains:

- `finding_id`, `domain_id`, title, and consequence for the readiness goal;
- `evidence_classification`: exactly `verified | inferred | unverifiable`;
- exactly one of `evidence_reference` or `unavailable_evidence_reason`, as constrained above;
- `product_contract_clause`, or disposition as an `owner_question` when no governing clause
  exists;
- `disposition`: exactly
  `implementation_defect | intentional_tradeoff | deferred_work | non_goal | owner_question`;
- severity and priority only when the disposition is `implementation_defect`, based on cost to
  the stated readiness goal.

A finding lacking both evidence location and unavailable-evidence reason is malformed and blocks
reconciliation and sealing. A disagreement between independent passes remains visible until the
corrected audit records how it was resolved.

Material `unverifiable` evidence does not by itself prohibit sealing. It imposes an evidence
ceiling: the dependent finding and overall conclusion remain `unverifiable`, and an overall
readiness pass MUST NOT outrank contract-critical evidence. Remediation planning may carry the
limit forward but MUST NOT relabel an `unverifiable` claim as a defect without new evidence.

## Runtime verification and setup quarantine

`audit/runtime-verification.md` always records:

- procedure or commands;
- synthetic-data shape;
- observed result;
- limitations;
- resulting `evidence_classification`.

A failed or missing runnable environment is `unverifiable`, never a pass. `catalog` does not
create a runnable environment. `full` and `audited` attempt isolated stand-up and synthetic probes
where technically possible.

An archival route records the exact runtime disposition `archival-no-probe`. It preserves any
valid runtime evidence already completed for this audit, but starts no new command, stand-up, or
probe solely to produce an archival seal. This disposition is valid only when the mechanically
derived completeness is `incomplete`; a complete `full` or `audited` audit carrying
`archival-no-probe` fails its profile gate.

`audit/setup-quarantine.md` is always present. It contains either an explicit `none` record or,
for every setup-only change:

- path and action;
- before and after state;
- rationale;
- whether target behavior changed;
- `approved_client_fix: false`.

Quarantined changes are verification scaffolding, not audit findings, remediation candidates,
approved client changes, or authorization to modify the target.

## Corrected audit and reservation

Corrected audits live at `audit/versions/vNNNN/corrected-audit.md`. Each contains:

- audit profile and target commit;
- product-intent contract reference and hash;
- candidate provenance and explicit duplicate, conflict, and supersession resolutions;
- reconciled findings and evidence classifications;
- runtime verification limits and setup-quarantine reference;
- owner questions and scope boundaries;
- completeness and conclusiveness;
- an evidence-classified overall conclusion;
- prioritized remediation candidates.

Remediation candidates are finding-only inputs to later planning. They are not a remediation
specification, implementation plan, or authorization to change the target.

`vNNNN` is a four-digit, one-based, monotonically increasing version: `v0001`, `v0002`, and so
on. The Conductor is the sole allocator and sole creator of version directories. It MUST:

1. Validate the entire version index, every indexed artifact, existing version directories, and
   reservations before mutation.
2. Select one greater than the highest existing numeric suffix, or `v0001` when none exists.
3. Exclusively create `audit/versions/vNNNN/` and no-clobber publish `reservation.json` containing
   exactly the fields in the schema below.
4. Give the Architect only that reserved version and path. The Architect writes
   `corrected-audit.md` with same-directory atomic no-clobber publication and never allocates a
   version or writes the index.
5. Revalidate the reservation and artifact, hash the published bytes, and append the corresponding
   `corrected` event.

`reservation.json` has this exact schema:

| Key | Type | Constant or rule |
|---|---|---|
| `schema_version` | `schema-version` | `1`. |
| `audit_version` | `audit-version` | Equals the containing `vNNNN` directory. |
| `allocation_id` | `safe-id` | Unique to this reservation. |
| `reconciliation_attempt_id` | `safe-id` | The only reconciliation attempt allowed to publish here. |
| `reserved_at` | `timestamp` | Reservation publication time. |

No other key is permitted.

A reservation collision triggers a complete rescan and allocation of the next number; the
colliding directory is never reused for another allocation. A correction or amendment requires a
new reservation and version. A published corrected audit is never edited or replaced. If `v9999`
exists, the Conductor stops and requires a new audit run; it MUST NOT widen or wrap the version.

The exact permitted unpublished state is **reserved-only**: the version directory contains one
regular file named `reservation.json`, that file has the required fields and exact recorded
allocation values, and there are no other entries (including hidden files, temporary files,
subdirectories, or symlinks). “Empty reservation” means this reserved-only state—empty of audit
artifacts—not a filesystem-empty directory. Only the same recorded allocation and reconciliation
attempt may resume a reserved-only directory and publish its corrected audit.

One additional interrupted state is recoverable: the directory contains exactly the valid
`reservation.json` and the same allocation's immutable `corrected-audit.md`, but the matching
`corrected` index event is absent. The Conductor revalidates and hashes both files, then appends
the missing event; it does not republish either file. After the `corrected` event, those same two
files are the only entries until sealing begins. A matching immutable `seal.json` may be present
without its `sealed` event only as the analogous interrupted seal-publication state; after full
revalidation, the Conductor may append only that missing event.

A filesystem-empty version directory, a missing or malformed `reservation.json`, any extra entry,
a surviving temporary file, a symlink or special file, an audit or seal with no matching valid
reservation, a seal before the `corrected` event, a nonmatching allocation/attempt, or conflicting
reservation data is invalid. Any other nonempty unpublished state stops mutation for explicit
repair. A different attempt never completes or adopts an existing directory; it allocates a new
version.

## Deterministic state derivation and profile gates

Before consulting the seal matrix, the Conductor validates mandatory artifacts. Every route
requires valid `audit/profile.md`, `audit/product-contract.md`, `audit/domain-register.md`,
`audit/coverage-index.ndjson`, `audit/runtime-verification.md`, `audit/setup-quarantine.md`, the exact reservation, the immutable
corrected audit, and its matching `corrected` index event. A normal route requires a completed
coverage record for every applicable domain. An archival route requires the preserved domain
register and the exact closed-ledger set of valid coverage records actually completed before archival closure;
that set is zero for unresolved intent or an all-domains-excluded register, but may be a nonempty
proper subset when coverage stopped partway. Deleting an existing valid record, adding an
unproduced record, forcing the set to zero, or fabricating an absence record is invalid. Every
existing coverage record still obeys the selected profile's isolation, evidence, and static-only
rules. An `audited` route additionally requires its valid packet and canonical verdict before
sealing. A missing or malformed mandatory artifact, unknown field, wrong type, invalid hash/path,
or inconsistent binding makes the version **invalid and unsealable**; it is not converted into
`incomplete` evidence.

For a structurally valid artifact set, derive completeness exactly once from recorded facts:

- `incomplete` if the product intent is missing or materially conflicted, every domain is
  excluded, or any applicable domain lacks a completed coverage record;
- otherwise `complete`.

An unavailable or failed runtime alone does not make an otherwise covered audit incomplete; its
classification and limits still constrain conclusiveness.

Then derive conclusiveness:

- `non-conclusive` if completeness is `incomplete`, contract-critical evidence is
  `unverifiable`, an evidence conflict remains unresolved, or an owner question explicitly blocks
  the overall readiness decision;
- otherwise `conclusive`.

The presence of `inferred` evidence alone does not make a result non-conclusive. The corrected
audit MUST show the facts used for both derivations. `successful_run` and
`selectable_for_remediation_planning` are then derived solely from the matrix below; no profile,
agent, human assertion, or approval may override them.

All profiles share this common gate predicate: intake and authorization validate; the target
commit still matches; every route-mandatory artifact and exact schema validates; the domain and
coverage rules above hold; evidence references/classifications and setup quarantine validate;
the ledger, reservation, corrected-audit path/hash, and derived state agree; and publication has
no collision or mutable alias.

Normal and archival profile predicates are separate, exact, and additive.

The **normal predicate** requires mechanically derived `complete` state and the common gate, then:

- normal `catalog` requires independent static deep-read coverage for every applicable domain, no
  dynamic command/probe in domain passes, no setup-created runtime, and any supplied authorized
  runtime procedure recorded by the runtime verifier; it uses the standard path;
- normal `full` requires an isolated stand-up and synthetic runtime attempt where technically
  possible, with every setup-only change quarantined; runtime unavailability remains evidence
  rather than an automatic gate failure, but `archival-no-probe` is invalid; it uses the standard
  path;
- normal `audited` requires the complete normal `full` predicate plus a stable contract-valid
  packet, the physically restricted adapter, and a canonical non-`BLOCKED` verdict bound to the
  exact corrected audit; `archival-no-probe` is invalid and the premium path is mandatory.

The **archival predicate** requires mechanically derived `incomplete` and `non-conclusive` state,
the common gate, the preserved domain register, the exact existing valid coverage set defined
above, and `runtime_disposition: archival-no-probe`. Existing coverage must satisfy the same
profile rules it would on the normal route. Archival `catalog` and archival `full` use
`standard-non-premium` with `cold_review: not-performed`, record `successful_run: false`, and are
not selectable. Archival `audited` additionally requires the same stable bounded packet,
physically restricted adapter, and exact-bound canonical non-`BLOCKED` premium verdict as normal
`audited`; it is likewise unsuccessful and non-selectable. No normal predicate can be satisfied by
an incomplete audit, and no archival predicate can be satisfied by a complete audit.

## Sealability and remediation selectability

The four-state matrix is exhaustive and deterministic:

| Completeness | Conclusiveness | Seal rule | Remediation-planning selection |
|---|---|---|---|
| `incomplete` | `non-conclusive` | Evidence-only archival seal is permitted only after the selected profile's archival predicate and records `successful_run: false`. For `audited`, even this archival seal requires an exact-bound non-`BLOCKED` premium verdict. | `selectable_for_remediation_planning: false`; never a default or explicit planning input. |
| `complete` | `non-conclusive` | Seal is permitted after the selected profile's normal gate, records `successful_run: true`, and preserves every material `unverifiable` ceiling. | `selectable_for_remediation_planning: true`; planning must preserve the evidence limits. |
| `complete` | `conclusive` | Seal is permitted after the selected profile's normal gate and records `successful_run: true`. | `selectable_for_remediation_planning: true`. |
| `incomplete` | `conclusive` | Invalid state; refuse sealing. | Not selectable. |

No profile bypasses its gate. `catalog` and `full` are always
`sealing_path: standard-non-premium` with `cold_review: not-performed`; neither may claim premium
review. Every `audited` seal, including an incomplete evidence-only archival seal, requires a
non-`BLOCKED` verdict bound to the exact corrected-audit version, path, and hash being sealed.
`BLOCKED`, malformed, stale, or differently bound verdicts prevent sealing.

`audit/versions/vNNNN/seal.json` is immutable. Its base exact key set is:

| Key | Type | Constant or rule |
|---|---|---|
| `schema_version` | `schema-version` | `1`. |
| `audit_version` | `audit-version` | Equals the containing version directory. |
| `profile` | JSON string | Exactly `catalog`, `full`, or `audited`; equals `audit/profile.md`. |
| `target_commit` | JSON string | Exactly 40 or 64 lowercase hexadecimal characters; equals intake. |
| `audit_date` | `date` | Seal date. |
| `corrected_audit_path` | `relative-artifact-path` | Exactly `audit/versions/vNNNN/corrected-audit.md` for `audit_version`. |
| `corrected_audit_sha256` | `sha256` | Hash of that exact file. |
| `contract_sha256` | `sha256` | Hash of `audit/product-contract.md`. |
| `completeness` | JSON string | Exactly `incomplete` or `complete`; mechanically derived above. |
| `conclusiveness` | JSON string | Exactly `non-conclusive` or `conclusive`; mechanically derived above. |
| `successful_run` | `boolean` | Exact matrix result. |
| `selectable_for_remediation_planning` | `boolean` | Exact matrix result. |
| `selection_reason` | JSON string | Closed value `incomplete-evidence-only`, `complete-evidence-limited`, or `complete-conclusive`, matching the three sealable matrix rows respectively. |
| `sealing_path` | JSON string | Profile-conditional constant below. |
| `cold_review` | JSON string | Profile-conditional constant below. |

For `catalog` and `full`, the exact conditional key set adds no keys:

- `sealing_path` is exactly `standard-non-premium`;
- `cold_review` is exactly `not-performed`;
- `cold_review_verdict`, `cold_review_verdict_path`, and `cold_review_verdict_sha256` MUST be
  omitted; no verdict exists to reference.

For `audited`, the exact conditional key set additionally requires:

| Key | Type | Constant or rule |
|---|---|---|
| `sealing_path` | JSON string | Exactly `premium-independent-cold-review`. |
| `cold_review` | JSON string | Exactly `performed`. |
| `cold_review_verdict` | JSON string | Exactly `APPROVED_WITH_WARNINGS` or `APPROVED`; `BLOCKED` is unsealable. |
| `cold_review_verdict_path` | `relative-artifact-path` | Exactly `verdicts/<attempt_id>.json` for the accepted `safe-id`. |
| `cold_review_verdict_sha256` | `sha256` | Hash of that exact adapter-published verdict. |

No other seal key is permitted. The audited verdict path/hash and reviewed-artifact binding MUST
match this seal's corrected-audit version, relative path, and SHA-256. A missing conditional key,
forbidden standard-profile verdict key, `BLOCKED`, wrong sealing-path constant, or any path, hash,
or version mismatch prevents publication.

The Conductor validates the profile gate and matrix, exclusively publishes the seal, hashes it,
and appends its `sealed` event. An existing seal path is a collision and stops publication; it is
never overwritten.

## Audited packet manifest and premium verdict

For `audited`, the Conductor stages one fresh bounded packet at
`audit/reviews/<attempt_id>-packet/` with no-clobber directory and file creation. `packet.json` has
this exact key set:

| Key | Type | Constant or rule |
|---|---|---|
| `schema_version` | `schema-version` | `1`. |
| `audit_version` | `audit-version` | Exact corrected-audit version under review. |
| `corrected_audit_path` | packet-member-path string | Exactly one allowlist member containing that version's corrected audit. |
| `review_question` | `bounded-text` | One bounded question; 1–2000 UTF-8 bytes under the common type. |
| `attempt_id` | `safe-id` | Equals the packet/result/verdict path identifier. |
| `output_id` | `safe-id` | Names only the direct result member allowed by the safe-ID rule. |
| `denied_inputs` | array of JSON strings | Exactly the fixed ordered array below. |
| `allowlist` | nonempty array of objects | Canonically sorted exact `{path,sha256}` entries defined below. |

`denied_inputs` is this exact array in this exact order; a missing, added, renamed, or reordered
element is malformed:

```json
[
  "run-log",
  "run-state-and-delegate-state",
  "checkpoint-log-slices",
  "prior-challenger-or-notary-findings-and-verdicts",
  "conductor-or-author-rationale",
  "visionary-back-and-forth",
  "chat-and-session-transcripts",
  "files-absent-from-allowlist"
]
```

Each allowlist element is an object with exactly two keys:

| Key | Type | Rule |
|---|---|---|
| `path` | packet-member-path string | Raw staged payload path under the rules below. |
| `sha256` | `sha256` | Hash of the exact staged file bytes. |

No other `packet.json` or allowlist-entry key is permitted.

The allowlist is a closed packet-relative file set. It contains exactly once every readable
regular payload file except `packet.json`: the product contract, domain register, closed coverage
ledger and its indexed records, runtime-verification and setup-quarantine records, corrected audit, this shared contract,
the readiness workflow, and the self-contained readiness-reviewer slice. An archival packet still
contains its domain register and contains exactly the existing valid coverage set used by
reconciliation: zero for unresolved intent or all domains excluded, otherwise the completed
partial subset. An absence placeholder is never an allowlist member.

The packet-member to authoritative-source map is fixed:

| Packet member | Authoritative source |
|---|---|
| `audit/product-contract.md` | `RUN_DIR/audit/product-contract.md` |
| `audit/domain-register.md` | `RUN_DIR/audit/domain-register.md` |
| `audit/coverage-index.ndjson` | `RUN_DIR/audit/coverage-index.ndjson` |
| `audit/coverage/<domain_id>.md` | Exact record named by the closed coverage ledger |
| `audit/runtime-verification.md` | `RUN_DIR/audit/runtime-verification.md` |
| `audit/setup-quarantine.md` | `RUN_DIR/audit/setup-quarantine.md` |
| `audit/versions/vNNNN/corrected-audit.md` | Exact artifact named by the corrected event |
| `docs/codebase-readiness-audit-contract.md` | Framework `docs/codebase-readiness-audit-contract.md` |
| `workflows/codebase-readiness-audit.md` | Framework `workflows/codebase-readiness-audit.md` |
| `agents/readiness-reviewer.md` | Framework `agents/readiness-reviewer.md` validated by adapter preflight |

Each manifest SHA-256 MUST equal both authoritative-source bytes and staged bytes. Before the
provider and again immediately before verdict publication, the adapter reopens and rehashes every
authoritative source and staged member. A stale, substituted, changed, missing, or differently
bound source invalidates the attempt.

A packet-member path is 1–512 raw ASCII bytes, POSIX-relative, uses `/` as its sole separator,
and has segments of 1–64 bytes matching exactly
`^[A-Za-z0-9](?:[A-Za-z0-9._-]{0,62}[A-Za-z0-9_-])?$`. Empty, `.`, `..`, absolute, backslash,
Unicode, control-byte, trailing-dot, normalization-dependent, and escaping paths are rejected.
Every traversed and final object MUST be a regular no-symlink path beneath the packet root. The
adapter rejects symlinks, hard-link/identity aliases, and any pair of paths that the host
filesystem treats as the same object or whose raw ASCII lowercase forms collide. It does not
normalize or rewrite a path.

The allowlist is sorted ascending by unsigned bytewise lexicographic comparison of the complete
raw ASCII `path` bytes. Raw paths and host-collision keys are unique. The adapter rejects an
unsorted/reordered array, duplicate raw or alias path, missing hash, non-lowercase hash, missing
file, extra regular file, special file, or hash mismatch.

The documented deny list explains the coldness boundary; the closed staged file set and provider
sandbox enforce it. The reviewer receives no live `RUN_DIR`, target-repository path, framework
path, home-directory path, or session-store path.

Before invoking a provider, the readiness adapter validates `packet.json`, exclusively enumerates
the staged directory without following links, proves exact file-set equality, and hashes every
payload. It also hashes the exact `packet.json` bytes and retains that manifest SHA-256 in the
adapter's private state for this invocation. It refuses a pre-existing canonical verdict, result
directory, unsafe identifier, or any malformed condition above, then exclusively creates
`audit/reviews/<attempt_id>-result/`.

After the provider returns and immediately before verdict validation/publication, the same adapter
rehashes `packet.json` and requires equality with the retained manifest hash, reparses it under the
exact schema, then re-enumerates and rehashes every payload. Any manifest or payload addition,
removal, reorder, rename, byte change, alias, or type change invalidates the attempt and publishes
no canonical verdict. Any collision, partial result, or validation failure blocks the attempt;
nothing is deleted, reused, or repaired. A new attempt requires a new attempt id and freshly
no-clobber-staged packet.

The Challenger is a candidate-only producer. Its raw candidate exact key set is only `attempt_id`,
`review_mode`, `reviewed_artifacts`, `blockers`, `blocker_ids`, and `warnings`. A candidate
`verdict`, timestamp, or unknown key is prohibited; it MUST NOT write `log.md`, a Markdown review,
the result record, or the live verdict. Every blocker object has one unique safe `id`.
`blocker_ids` is required and is
exactly the ordered array of `blockers[].id`, with one entry per blocker and no missing, duplicate,
extra, reordered, or mismatched value. An absent `blocker_ids` field is invalid. The readiness
adapter is the sole canonical validator and writer. It:

1. Validates the exact blocker object/ID correspondence, then derives `BLOCKED` when
   `blocker_ids` is nonempty, `APPROVED_WITH_WARNINGS` when `blocker_ids` is empty and `warnings`
   is nonempty, and `APPROVED` when both arrays are empty.
2. Requires candidate `attempt_id` and `review_mode` to equal the packet values exactly.
3. Requires `reviewed_artifacts` to equal the manifest's canonically sorted allowlist exactly,
   in the same order, with the same packet-relative paths and lowercase SHA-256 values and no
   missing or extra element.
4. Requires the allowlist member named by `corrected_audit_path` and the candidate binding to
   equal the reserved versioned corrected-audit path and hash.
5. Supplies current UTC second-precision `reviewed_at`, constructs and validates the exact
   canonical record containing only `schema_version`, `attempt_id`, `audit_version`, `review_mode`,
   derived `verdict`, `reviewed_artifacts`, `blockers`, `blocker_ids`, `warnings`,
   `corrected_audit_path`, `corrected_audit_sha256`, and `reviewed_at`, then atomically no-clobber
   publishes `verdicts/<attempt_id>.json`. A caller-owned verdict or timestamp is invalid.

The Conductor consumes the canonical verdict path and hash but MUST NOT create, rewrite,
normalize, or repair it. `BLOCKED` requires correction in a newly allocated version followed by a
fresh packet and review. Only a non-`BLOCKED`, exact-bound verdict satisfies the `audited` gate.

## Append-only version index

`audit/version-index.ndjson` is the authoritative append-only ledger. The Conductor is its only
writer. Each line is one complete UTF-8 compact JSON object with keys sorted lexicographically.
The one-active-Conductor invariant serializes all version mutations.

A `corrected` event has this exact key set:

| Key | Type | Constant or rule |
|---|---|---|
| `schema_version` | `schema-version` | `1`. |
| `audit_version` | `audit-version` | Version being recorded. |
| `event` | JSON string | Exactly `corrected`. |
| `artifact_path` | `relative-artifact-path` | Exactly `audit/versions/vNNNN/corrected-audit.md` for `audit_version`. |
| `artifact_sha256` | `sha256` | Hash of that exact file. |
| `recorded_at` | `timestamp` | Append time. |

A `sealed` event has this exact key set:

| Key | Type | Constant or rule |
|---|---|---|
| `schema_version` | `schema-version` | `1`. |
| `audit_version` | `audit-version` | Version being recorded. |
| `event` | JSON string | Exactly `sealed`. |
| `corrected_audit_path` | `relative-artifact-path` | Exactly `audit/versions/vNNNN/corrected-audit.md` for `audit_version`. |
| `corrected_audit_sha256` | `sha256` | Equals the corrected event hash and exact file bytes. |
| `recorded_at` | `timestamp` | Append time. |
| `seal_path` | `relative-artifact-path` | Exactly `audit/versions/vNNNN/seal.json` for `audit_version`. |
| `seal_sha256` | `sha256` | Hash of that exact seal. |

No other event key is permitted. In the compact serialized object, keys are ordered
lexicographically by raw ASCII bytes; the two event classes retain their distinct path/hash key
names exactly as shown.

Before every allocation, publication, append, resume, or selection, the Conductor reads and
validates the ledger from byte zero. The order is always: validate ledger and reservation,
no-clobber publish artifact, hash exact bytes, then append one complete event line. Existing
complete lines are never edited.

On resume, an already-present identical `(audit_version,event,path,hash)` is idempotent success.
When the event is absent, it may be appended only after its artifact and reservation fully
revalidate. A partial final line, malformed JSON, unknown event or field shape, conflicting
duplicate, duplicate event with different path or hash, decreasing version, impossible event
order, missing artifact, reservation mismatch, or file/hash mismatch stops all mutation and
requires explicit repair; there is no blind retry. A sealed version is valid only when both
events exist and all recorded paths and hashes match immutable files.

There is no `latest` file, symlink, alias, or mutable pointer. Default selection validates all
versions and chooses the highest numeric valid seal with `successful_run: true` and
`selectable_for_remediation_planning: true`. Explicit selection accepts an earlier version only
when that exact version is valid and selectable. An evidence-only non-selectable seal is skipped
by default and rejected when explicitly named.

## Remediation planning and execute-plan approval

A selected selectable seal may be used by default as requirements input to a separately started
remediation-planning run. Remediation planning needs no client-fix approval, creates no approval
record, grants no authority to change the client repository, and never auto-executes fixes.

Only after a remediation plan is complete may the Conductor observe an explicit human-facing
client-fix checkpoint decision and publish the immutable approval
`audit/execute-plan-approvals/<approval_id>.json`. The Conductor is the sole approval publisher. It
rehashes the selected seal and completed plan, constructs and validates the record, writes a
same-directory temporary file, and atomically publishes no-clobber. Any existing derived approval
path, even with identical bytes, is a collision and requires a new `approval_id`. The approval has
this exact key set:

| Key | Type | Constant or rule |
|---|---|---|
| `schema_version` | `schema-version` | `1`. |
| `approval_id` | `safe-id` | Equals `<approval_id>` in the fixed approval path. |
| `requested_next_workflow` | JSON string | Exactly `execute-plan`. |
| `audit_version` | `audit-version` | Exact selected valid selectable seal version. |
| `seal_path` | `relative-artifact-path` | Exactly `audit/versions/vNNNN/seal.json` for `audit_version`. |
| `seal_sha256` | `sha256` | Hash of that exact seal. |
| `remediation_plan_path` | JSON string | Canonical absolute path exactly of the form `<absolute-remediation-run-dir>/plan.md`, where the parent is the separately started authorized remediation-planning `RUN_DIR`; no symlink, empty, `.`, `..`, backslash, normalization alias, or non-regular target is allowed. |
| `remediation_plan_sha256` | `sha256` | Hash of that exact completed `plan.md`. |
| `decision` | JSON string | Exactly `approved`; every other value is invalid. |
| `decided_at` | `timestamp` | Explicit approval time. |
| `checkpoint_id` | `safe-id` | Human-facing client-fix checkpoint identifier. |
| `approver_identity` | `identity-text` | Explicit human approver identity. |

No other approval key is permitted. The `approval_id` is validated before deriving the fixed
approval path; a caller-supplied alternative approval path is never accepted.

requested_next_workflow: execute-plan

Approval is never inferred from conversation, planning, a previous version, or a superseded
artifact. Approval bound to a different seal, corrected-audit lineage, or remediation-plan hash is
invalid. A changed plan or newer selected seal requires a new immutable approval.

### Downstream execute-plan authorization validation

`workflows/codebase-readiness-audit.md § Downstream execute-plan authorization validation` is the
only later validation surface. The Conductor explicitly re-enters that section after the plan and
approval exist. It revalidates the ledger and selected seal, rehashes the seal and plan, requires
the seal to be selectable, validates the exact approval schema above, and rejects missing,
different, invalid, or hash-mismatched bindings. An explicitly selected earlier valid selectable
seal remains eligible when the approval binds that exact seal and plan.

Success emits only a bounded handoff containing the exact seal, remediation-plan, and approval
paths and hashes. That handoff may authorize the Conductor to start a separate execute-plan run.
The readiness-audit workflow itself never invokes `execute-plan` and never modifies
`workflows/execute-plan.md`.

## Source-method provenance and runtime independence

The source audit-service path
`/Users/robin/Code/novadiem/assistant/find-work/services/codebase-readiness-audit/` is read-only
design provenance. It is not editable scope and is not a runtime dependency. Implementers and the
shipped workflow must never open, invoke, or copy from that path.
The shipped workflow must work when the source path is absent.
