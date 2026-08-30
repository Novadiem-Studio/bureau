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

- `catalog` performs independent static deep-read coverage for every applicable domain. It runs
  an already-supplied and authorized local procedure when one exists, but does no setup work to
  create a runnable environment. Otherwise runtime evidence is `unverifiable`.
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
   `audit_version`, `allocation_id`, `reconciliation_attempt_id`, and `reserved_at`.
4. Give the Architect only that reserved version and path. The Architect writes
   `corrected-audit.md` with same-directory atomic no-clobber publication and never allocates a
   version or writes the index.
5. Revalidate the reservation and artifact, hash the published bytes, and append the corresponding
   `corrected` event.

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

## Sealability and remediation selectability

The four-state matrix is exhaustive and deterministic:

| Completeness | Conclusiveness | Seal rule | Remediation-planning selection |
|---|---|---|---|
| `incomplete` | `non-conclusive` | Evidence-only archival seal is permitted after the selected profile's normal gate and records `successful_run: false`. For `audited`, even this archival seal requires an exact-bound non-`BLOCKED` premium verdict. | `selectable_for_remediation_planning: false`; never a default or explicit planning input. |
| `complete` | `non-conclusive` | Seal is permitted after the selected profile's normal gate, records `successful_run: true`, and preserves every material `unverifiable` ceiling. | `selectable_for_remediation_planning: true`; planning must preserve the evidence limits. |
| `complete` | `conclusive` | Seal is permitted after the selected profile's normal gate and records `successful_run: true`. | `selectable_for_remediation_planning: true`. |
| `incomplete` | `conclusive` | Invalid state; refuse sealing. | Not selectable. |

No profile bypasses its gate. `catalog` and `full` are always
`sealing_path: standard-non-premium` with `cold_review: not-performed`; neither may claim premium
review. Every `audited` seal, including an incomplete evidence-only archival seal, requires a
non-`BLOCKED` verdict bound to the exact corrected-audit version, path, and hash being sealed.
`BLOCKED`, malformed, stale, or differently bound verdicts prevent sealing.

`audit/versions/vNNNN/seal.json` is immutable and contains:

- schema version, `audit_version: vNNNN`, profile, target commit, and audit date;
- corrected-audit relative path and SHA-256;
- product-contract SHA-256;
- `completeness`, `conclusiveness`, `successful_run`,
  `selectable_for_remediation_planning`, and selection reason;
- profile-conditional sealing and cold-review fields as follows.

For `catalog` and `full`, the seal MUST contain `sealing_path: standard-non-premium` and
`cold_review: not-performed`. It MUST omit `cold_review_verdict`,
`cold_review_verdict_path`, and `cold_review_verdict_sha256`; no verdict exists to reference.

For `audited`, the seal MUST contain `cold_review: performed`, `cold_review_verdict` with exactly
`APPROVED_WITH_WARNINGS` or `APPROVED`, `cold_review_verdict_path`, and
`cold_review_verdict_sha256`. The path and hash MUST identify the adapter-published canonical
verdict whose reviewed-artifact binding exactly matches this seal's corrected-audit version,
relative path, and SHA-256. A missing field, `BLOCKED`, `not-performed`, or any path, hash, or
version mismatch prevents publication.

The Conductor validates the profile gate and matrix, exclusively publishes the seal, hashes it,
and appends its `sealed` event. An existing seal path is a collision and stops publication; it is
never overwritten.

## Audited packet manifest and premium verdict

For `audited`, the Conductor stages one fresh bounded packet at
`audit/reviews/<attempt_id>-packet/`. `packet.json` contains:

- `audit_version`;
- exactly one `corrected_audit_path` naming a staged packet-relative allowlist member;
- exactly one bounded review question;
- safe attempt and output identifiers;
- `allowlist`: a canonically path-sorted array of `{path,sha256}` objects.

The allowlist is a closed packet-relative file set. It contains exactly once every readable
regular payload file except `packet.json`: the product contract, domain register, coverage
records, runtime-verification and setup-quarantine records, corrected audit, this shared contract,
the readiness workflow, and the self-contained readiness-reviewer slice. Each `path` is a safe
relative path within the packet, and each `sha256` is lowercase. Absolute paths, empty or `..`
segments, path escape, symlinks at any traversed component, duplicate normalized paths, duplicate
entries, missing hashes, non-lowercase hashes, missing files, extra regular files, special files,
and hash mismatches make the packet malformed.

`packet.json` explicitly denies these history categories:

- `log.md`, `state.json`, and delegate state;
- checkpoint log slices;
- prior Challenger or Notary findings and verdicts;
- Conductor or author rationale and Visionary back-and-forth;
- chat and session transcripts;
- every file absent from the allowlist.

The documented deny list explains the coldness boundary; the closed staged file set and provider
sandbox enforce it. The reviewer receives no live `RUN_DIR`, target-repository path, framework
path, home-directory path, or session-store path.

Before invoking a provider, the readiness adapter validates the packet and refuses a pre-existing
canonical verdict, result directory, unsafe output identifier, or any malformed condition above.
It then exclusively creates `audit/reviews/<attempt_id>-result/`. Any collision, partial result,
or validation failure blocks the attempt; nothing is deleted, reused, or repaired. A new attempt
requires a new attempt id and freshly staged packet.

The Challenger is a candidate-only producer. It returns one structured candidate with
`review_mode: verification`, blockers, warnings, and `reviewed_artifacts`; it MUST NOT write
`log.md`, a Markdown review, the result record, or the live verdict. The readiness adapter is the
sole canonical validator and writer. It:

1. Derives exactly `BLOCKED`, `APPROVED_WITH_WARNINGS`, or `APPROVED` from the candidate blockers
   and warnings.
2. Validates the existing Challenger verdict schema and `review_mode: verification`.
3. Requires `reviewed_artifacts` to equal the manifest's canonically sorted allowlist exactly,
   in the same order, with the same packet-relative paths and lowercase SHA-256 values and no
   missing or extra element.
4. Requires the allowlist member named by `corrected_audit_path` and the candidate binding to
   equal the reserved versioned corrected-audit path and hash.
5. Only after all checks pass, atomically no-clobber publishes the canonical verdict at
   `verdicts/<attempt_id>.json`.

The Conductor consumes the canonical verdict path and hash but MUST NOT create, rewrite,
normalize, or repair it. `BLOCKED` requires correction in a newly allocated version followed by a
fresh packet and review. Only a non-`BLOCKED`, exact-bound verdict satisfies the `audited` gate.

## Append-only version index

`audit/version-index.ndjson` is the authoritative append-only ledger. The Conductor is its only
writer. Each line is one complete UTF-8 compact JSON object with keys sorted lexicographically.
The one-active-Conductor invariant serializes all version mutations.

A `corrected` event has exactly these fields:

- `audit_version`, `event: corrected`, `artifact_path`, `artifact_sha256`, `recorded_at`, and
  `schema_version`.

A `sealed` event has exactly these fields:

- `audit_version`, `event: sealed`, `corrected_audit_path`, `corrected_audit_sha256`,
  `recorded_at`, `schema_version`, `seal_path`, and `seal_sha256`.

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

Only after a remediation plan is complete may a human-facing client-fix checkpoint create the
immutable approval `audit/execute-plan-approvals/<approval_id>.json`. It contains:

- `requested_next_workflow: execute-plan`;
- selected `audit_version`;
- seal relative path and SHA-256;
- remediation-plan path and SHA-256;
- explicit decision and decision time;
- checkpoint id;
- approver identity.

Approval is never inferred from conversation, planning, a previous version, or a superseded
artifact. Approval bound to a different seal, corrected-audit lineage, or remediation-plan hash is
invalid. A changed plan or newer selected seal requires a new immutable approval.

### Downstream execute-plan authorization validation

`workflows/codebase-readiness-audit.md § Downstream execute-plan authorization validation` is the
only later validation surface. The Conductor explicitly re-enters that section after the plan and
approval exist. It revalidates the ledger and selected seal, rehashes the seal and plan, requires
the seal to be selectable, validates every approval field including
`requested_next_workflow: execute-plan`, and rejects missing, stale, superseded, or mismatched
bindings.

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
