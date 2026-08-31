# Workflow: codebase-readiness-audit

**When to use:** an operator explicitly requests an opt-in Codebase Readiness Audit to establish
evidence-backed readiness findings, seal an immutable audit version, or supply a selectable sealed
version to a separately started remediation-planning run. Until registry promotion, invoke this
file directly and name the profile explicitly.

**When NOT to use:** ordinary feature planning, implementation, generic code review, production
deployment, commercial marketplace or pricing work, or direct remediation. Do not use it to audit
a client repository without explicit read/run authorization, to execute client fixes, or to infer
approval from a conversation. Build verification of this workflow uses synthetic fixtures only;
it does not audit a client repository.

**Type:** analysis and evidence workflow with immutable publication gates. It is directly
invokable while intentionally unregistered; normal registry routing is its future dispatch seam,
not a new orchestrator branch.

**Objective:** produce a contract-conformant corrected audit and, when the selected profile's gate
and the sealability matrix permit it, an immutable seal that ends at remediation-planning
eligibility without granting client-fix authority.

**Inputs:** an absolute `RUN_DIR`; an explicit audit profile; a readable authorized target
repository and ref; immutable target commit; audit authorization; product-intent sources; runtime
instructions or an explicit statement that none were supplied; credential and data policy; and
the operator's runtime/resource constraints. Production credentials and live customer data are
out of scope unless separately and explicitly authorized.

**Outputs:** the applicable artifacts under `RUN_DIR/audit/`, `RUN_DIR/verdicts/`, and the exact
immutable version path defined by `docs/codebase-readiness-audit-contract.md`. A successful,
selectable seal may yield a remediation-planning eligibility handoff. An incomplete archival seal
is evidence retention only. This workflow produces no client-repository changes and no
execute-plan invocation.

**Contract authority:** `docs/codebase-readiness-audit-contract.md` is the sole authority for all
profiles, evidence classifications, dispositions, artifact fields, paths, hashes, version/index
events, seal states, safe identifiers, packet/verdict rules, selection, and downstream approval.
This workflow references those definitions and MUST NOT reinterpret or duplicate their schemas.

## Steps

Run the numbered steps in order. Pass absolute `RUN_DIR` and only the minimum contract-authorized
inputs to every fresh context. The Conductor owns all gates, version allocation, index mutation,
selection, and downstream authorization decisions.

1. **The Conductor** — validate explicit intake and authorization → `RUN_DIR/audit/profile.md`
   - Require every intake value named in **Inputs**, including an explicit profile and explicit
     runtime-instruction presence or absence. Validate the repository/ref is readable inside the
     authorized boundary and bind the run to the recorded target commit.
   - Reject a missing/unknown profile, unreadable repository/ref, absent audit authorization,
     unsafe credential/data policy, or ambiguous target before spawning an audit agent. There is
     no inferred profile or authorization.
   - Do not access the source audit-service path. It is read-only design provenance, not a runtime
     dependency, and the workflow must work when it is absent.
   - A target commit change requires a new audit run; never retarget through a new version.
   - Resolve the authorized checkout commit under the contract before reads, probes, or publication
     and require exact lowercase equality with `profile.md` `target_commit`.

2. **Analizer 2000** (Product intent, **strong**) — establish intent before evaluation → `RUN_DIR/audit/product-contract.md`
   - Read only authorized intent evidence. Record the intended product/use case, boundary,
     supplied evidence, exclusions, owner questions, and blocked decisions by reference to the
     shared contract.
   - If intent is missing or materially conflicted, emit `[CHECKPOINT]` before any readiness
     finding, recommendation, coverage claim, runtime probe, or conclusion. The operator may
     supply resolving evidence and rerun this step, or request evidence-retention closure.
   - Evidence-retention closure is `incomplete` and `non-conclusive`. Its substantive audit
     content is limited to the contract gap, boundaries, evidence inventory, and blocked owner
     questions. Any mandatory structural absence records remain non-substantive and use only the
     shared contract's explicit absence forms. Continue through step 3 in structural
     evidence-retention mode, skip only step 4 coverage, run step 5 in no-probe mode, then
     continue at step 6. It may seal only after the selected profile's archival predicate and is never
     successful or selectable for remediation planning.

3. **Analizer 2000** (Orientation, **standard**) — declare domain scope from settled intent → `RUN_DIR/audit/domain-register.md`
   - Record every baseline domain and any product-intent-required domain by reference to the
     shared contract. Mark each applicable or excluded, preserve an exclusion reason, and carry
     every excluded area forward as not audited.
   - Use the six fixed baseline safe IDs. Product-specific domains declare unique raw safe IDs;
     reject normalization, rewriting, aliases, and collisions.
   - Publish the human-readable register with the contract's one authoritative machine block.
     Before closure, the Conductor parses that block, rejects malformed/duplicate/aliased state,
     and derives the applicable and excluded ID sets; surrounding prose cannot override them.
   - For unresolved-intent structural evidence retention, create the normal six-baseline-domain
     register, mark every baseline domain excluded because intent is unresolved, and add no
     invented product-specific domain. Preserve this register and skip only step 4 coverage.
     Return control to the Conductor to no-clobber create the coverage ledger and append its zero-
     completion `coverage-closed` event with reason `unresolved-intent` only after the parsed block
     proves exactly six baselines excluded for unresolved intent and no product-specific member.
   - If settled intent produces an all-domains-excluded register, preserve that register, treat
     the audit as incomplete/non-conclusive, and skip only step 4 coverage. Route through the
     evidence-retention rules from step 2; do not manufacture findings. The Conductor closes the
     no-clobber coverage ledger at zero with reason `all-domains-excluded` only when the parsed
     applicable set is empty.

4. **Analizer 2000** (Independent coverage, **standard**) — isolate each domain pass → `RUN_DIR/audit/coverage/<domain_id>.md`
   - Spawn a fresh context for each applicable domain. Give it the product contract, domain
     register, its single named domain, and only the authorized target evidence needed for that
     domain. Do not give it another domain pass's summary or candidate findings.
   - Batching within the host concurrency cap is allowed; input isolation and a separate coverage
     record are required even when passes run sequentially. Partial coverage and limits remain
     explicit. Zero findings is acceptable only after every applicable domain has completed
     coverage.
   - For `catalog`, every domain pass is static deep-read only and MUST NOT execute dynamic
     commands or probes. Any already-supplied authorized runtime procedure belongs only in step 5.
   - Candidate findings follow the shared evidence and disposition contract. Missing evidence is
     not a pass, and an owner question is not silently promoted to a defect.
   - After each no-clobber coverage publication, return control to the Conductor to hash the record
     and append its exact `coverage-completed` event. The Conductor serializes these appends and
     finally appends one terminal `coverage-closed` event; nothing appends after closure.
   - Reject coverage for an excluded or unknown machine-block ID. For normal closure require the
     completed-ID set to equal the parsed applicable set; partial archival requires a nonempty
     proper subset. Bind closure to the exact full-register Markdown hash.
   - If coverage stops partway and the operator chooses archival closure, checkpoint with the
     completed domain set and preserve every valid existing coverage record exactly. Do not delete
     one, add an unproduced record, force the set to zero, or fabricate an absence record.

5. **The Mechanic** (Runtime verification, **strong**) — verify runtime and quarantine setup → `RUN_DIR/audit/runtime-verification.md`, `RUN_DIR/audit/setup-quarantine.md`
   - Work only in an isolated clone, worktree, or local stack with synthetic data and the supplied
     credential/data policy. Never commit setup-only target changes.
   - For normal `catalog`, attempt an already-supplied authorized procedure and record its observed
     outcome; if absent record `not-supplied`. Never create a runnable environment. For `full` and
     `audited`, actively attempt isolated stand-up and synthetic
     lifecycle probes where technically possible.
   - For every archival route, preserve any completed runtime evidence, start no new probe solely
     to archive, and record exact disposition `archival-no-probe`. This disposition is invalid on
     a complete `full` or `audited` route.
   - Validate required `runtime_disposition` against the exact five-value enum and selected normal
     catalog/full/audited or archival predicate.
   - Always write both contract-defined records. A failed or unavailable runtime remains
     `unverifiable`, never pass. Every setup-only change is uncommitted, separately quarantined,
     and remains `approved_client_fix: false`; an explicit no-change quarantine is still required.

6. **The Conductor** — validate the ledger and reserve the next immutable version → `RUN_DIR/audit/versions/vNNNN/reservation.json`
   - Validate the ledger and filesystem from byte zero, then allocate and exclusively publish the
     next reservation exactly as the shared contract requires. The Conductor is the sole allocator
     and version-directory creator.
   - Validate every current machine-readable artifact against the contract's exact schema and JSON
     conventions, recompute completeness and conclusiveness from the recorded facts, and require
     agreement before reservation. Publish `reservation.json` only with its exact contract key
     set, types, constants, and bounds.
   - Apply the contract's collision rescan, reserved-only, interruption recovery, idempotency,
     and terminal version rules. Any partial, conflicting, decreasing, mismatched, or unexpected
     state stops for explicit repair; never reuse, overwrite, widen, wrap, or create a mutable
     latest pointer.

7. **The Architect** (Reconciliation, **strong**) — reconcile only the supplied reservation → `RUN_DIR/audit/versions/vNNNN/corrected-audit.md`
   - Always receive the exact reservation/version plus `RUN_DIR/audit/profile.md`,
     `RUN_DIR/audit/product-contract.md`, `RUN_DIR/audit/domain-register.md`,
     `RUN_DIR/audit/coverage-index.ndjson`,
     `RUN_DIR/audit/runtime-verification.md`, and `RUN_DIR/audit/setup-quarantine.md`. Do not
     allocate a version or write the index.
   - On every path, receive exactly the completed records in the validated closed coverage ledger;
     require that set to satisfy the machine-block closure rule, and never discover, omit, add, or
     substitute a coverage file outside that indexed set.
   - Preserve candidate provenance and visibly resolve duplicates, conflicts, and supersessions.
     Keep owner questions, exclusions, verification limits, and setup quarantine visible.
   - Every substantive finding and the overall conclusion carry the shared evidence
     classification plus the required evidence reference or unavailability reason. Evidence
     ceilings are preserved. Publish no-clobber to the reserved version only.
   - Split archival reconciliation exactly: unresolved intent emits contract-gap content and no
     findings; all domains excluded emits exclusion-only content and no findings; partial coverage
     preserves every indexed finding, provenance item, and evidence ceiling. Every archival form
     remains incomplete, non-conclusive, unsuccessful, non-selectable, and grants no planning
     authority.

8. **The Conductor** — validate and bind the corrected audit → `RUN_DIR/audit/version-index.ndjson` (`corrected` event)
   - Revalidate the complete ledger, reservation state, corrected-audit path/content, target
     commit, required inputs, evidence rules, and exact bytes. Hash the published artifact and
     append the canonical event only after every check passes.
   - Recompute completeness and conclusiveness under the deterministic contract rules, require the
     corrected audit to agree, and validate the exact `reservation.json` and `corrected` index-
     event schemas before appending the exact event.
   - Treat an identical existing event as idempotent success. Stop on missing, partial,
     conflicting, reordered, decreasing, or path/hash-mismatched state; never normalize or repair
     it implicitly.

9. **The Conductor** — apply the selected profile's pre-seal gate → profile gate decision
   - `catalog` and `full` take the shared standard non-premium path and explicitly record that cold
     review was not performed. They never claim the premium gate completed.
   - Before staging an `audited` packet, preflight both the self-contained readiness-reviewer slice
     and the physically restricted `readiness-audit` adapter. If either is absent or invalid, stop
     before packet staging and provider invocation; neither component substitutes for the other.
     The reviewer source is exactly `agents/critic/readiness-audit.md`.
   - `audited` stages the exact bounded packet and invokes only the physically restricted
     `readiness-audit` adapter defined by the shared contract. Consume only its adapter-published
     exact-bound canonical verdict. An audited archival packet includes the preserved
     `RUN_DIR/audit/domain-register.md` and the exact existing valid coverage set used by
     reconciliation—zero only for unresolved intent or all domains excluded. An absence
     placeholder is not a valid substitute for the register or a coverage record.
   - Stage the closed coverage ledger and exactly its indexed records. Bind each packet member to
     the fixed authoritative source; before provider invocation and verdict publication rehash
     both authoritative and staged bytes and reject stale or substituted sources.
   - Rehash the exact full domain-register Markdown bytes, parse its sole contract-defined machine
     block, and require the staged ledger/records to match its derived closure sets. Do not infer
     domain state from surrounding prose.
   - Include profile, selected reservation, and version index in the packet. Apply only the shared
     contract's review mode, candidate/citation schema, and canonical-verdict schema; do not
     duplicate their field definitions here.
   - The provider emits one candidate through the adapter channel and cannot write the result
     directory. The adapter creates it exactly once before invocation, later publishes candidate
     bytes no-clobber inside it, reopens them, and constructs the canonical verdict.
   - Validate attempt → immutable packet → audit version/corrected path → allowlist path/hash →
     exact reviewed-artifact equality → selected corrected bytes.
   - Require the adapter's contract-defined pre-invocation enumeration and byte-hash validation of
     `packet.json` plus every payload, including retention of the manifest hash. Immediately before
     verdict publication, require its post-provider manifest rehash, reparse, re-enumeration, and
     payload rehash; any addition, removal, reorder, rename, alias, or byte change invalidates the
     attempt.
   - A canonical `BLOCKED` verdict requires correction in a newly allocated audit version; the
     unchanged corrected-audit version cannot be retried with a fresh review attempt. A packet,
     identifier, collision, transport, or pre-verdict adapter-validation fault may use a fresh
     attempt id and packet against the same immutable corrected audit only after rehashing proves
     its bytes are unchanged. Changed corrected-audit bytes require a new reserved version.
     Every fault remains fail-closed and produces no seal.
   - Until that restricted adapter profile is implemented and mechanically available, every
     direct `audited` exercise stops here at `[CHECKPOINT]`. It produces no premium-review claim,
     canonical verdict, or seal. A native shared-filesystem reviewer is not a fallback.
   - An `audited` evidence-retention seal has the same exact-bound non-blocked premium gate as any
     other audited seal.

10. **The Conductor** — validate sealability, publish the seal, and append its event → `RUN_DIR/audit/versions/vNNNN/seal.json`, `RUN_DIR/audit/version-index.ndjson` (`sealed` event)
    - Revalidate the ledger, corrected audit, profile gate, hashes, evidence ceilings, and the
      shared completeness/conclusiveness seal matrix. Refuse invalid states and any profile-gate
      mismatch.
    - Validate exactly one shared profile predicate: normal for a complete audit or archival for
      an incomplete audit. Never accept `archival-no-probe` for a complete `full` or `audited`
      audit, and never downgrade audited archival review to the standard path.
    - Recompute completeness and conclusiveness again from the final immutable inputs; derive
      `successful_run`, `selectable_for_remediation_planning`, and selection reason solely from the
      matrix. Validate the exact profile-conditional `seal.json` and `sealed` index-event schemas
      before publishing either record.
    - Exclusively publish the immutable seal, hash it, then append the canonical event. Follow the
      shared profile-conditional cold-review fields; never overwrite a seal or let the Conductor
      create/repair an audited verdict.

11. **Gate** — end audit execution at remediation-planning eligibility → terminal routing checkpoint
    - Revalidate all versions and resolve default or explicit selection under the shared contract.
      Offer only a valid seal marked `selectable_for_remediation_planning: true` as requirements
      input to a separately started remediation-planning run. Planning needs no client-fix
      approval and grants no modification authority.
    - Retain an incomplete archival seal only as non-selectable evidence. Do not offer it as an
      explicit or default planning input.
    - Stop here. Do not create an execute-plan approval, execute a fix, or invoke another build
      workflow. A later completed remediation plan and explicit approval must use the separately
      invoked re-entry below.

## Downstream execute-plan authorization validation

This is a separately invoked Conductor re-entry after remediation planning is complete. It is not
part of normal audit execution, and it never invokes `workflows/execute-plan.md` or executes a
client fix.

1. **The Conductor** — accept exact downstream artifacts for validation → `RUN_DIR/audit/execute-plan-approvals/<approval_id>.json`
   - Accept the raw `approval_id`, explicit decision, selected-seal request/path, and completed
     remediation-plan path while the derived approval path is absent. Validate raw `approval_id`
     against the shared safe-ID grammar before constructing
     any path, derive only `RUN_DIR/audit/execute-plan-approvals/<approval_id>.json`, and require
     the approval at that fixed path. Reject an invalid id, normalization, or any supplied or
     resolved approval path outside that fixed location.
   - As sole approval publisher, observe the explicit human decision, rehash the seal and plan,
     validate the exact record, then use a same-directory temporary file and atomic no-clobber
     publication. Any existing derived path, even identical, fails and needs a new `approval_id`.
     Reopen and validate the published approval before continuing.
   - Treat the seal and plan as regular artifact paths, not safe-ID values. Do not apply the
     identifier grammar to either path; their safety, ledger/lineage, and hashes are validated in
     step 2. Absence or ambiguity stops the re-entry.

2. **The Conductor** — revalidate lineage and exact bytes → authorization decision
   - Validate the version index from byte zero. With no explicit version, resolve the highest
     numeric valid selectable seal; when the operator explicitly names an earlier valid selectable
     seal, accept that exact version instead. Validate the chosen seal and corrected-audit lineage
     and rehash the seal and completed plan at their authorized regular artifact paths.
   - Validate the immutable approval against the contract's exact approval schema, key set, types,
     constants, bounds, fixed path, and seal/plan bindings. Reject every unknown, missing,
     duplicate, wrong-type, non-`approved`, or mismatched value; do not define a second approval
     schema here.

3. **Gate** — fail closed on stale or mismatched authority
   - Reject a missing approval, invalid `approval_id`, approval outside its derived fixed path,
     evidence-only/non-selectable or otherwise invalid seal, approval bound to a different seal,
     different audit version, or different remediation-plan hash, invalid decision, or any other
     path/hash/field mismatch. An explicitly selected earlier valid selectable seal is not stale
     merely because a later selectable version exists. Conversation, earlier approval, audit
     completion, and remediation planning never imply authority. A changed plan or selected seal
     requires a new approval.

4. **The Conductor** — emit only the contract-bounded authorization result → authorized handoff
   - On success, emit the exact seal, plan, and approval paths and hashes and nothing broader. This
     handoff may be consumed by the Conductor to start a separate execute-plan run outside this
     workflow. This workflow does not invoke it, dispatch a coder, or modify the client repository.

## Done

The workflow is done only when all applicable contract artifacts validate, both immutable index
events exist with matching files/hashes, the selected profile gate passed, and a seal was
published under the sealability matrix. A successful selectable run ends at the remediation-
planning offer. An incomplete archival run ends with a valid non-selectable evidence seal. An
`audited` run is not done while the restricted adapter is unavailable, its verdict is missing or
blocked, or its exact binding fails. No done state includes client-fix execution.

The separately invoked downstream re-entry is done only when it emits the bounded handoff after
exact seal, plan, and approval validation. A rejected re-entry emits no authorization handoff.

## Edge cases

- A missing or conflicted product contract stops before findings and can produce only the bounded
  evidence-retention content described in step 2.
- If every declared domain is excluded, the packet is incomplete/non-conclusive. Zero findings
  does not compensate for missing coverage.
- Runtime unavailable or failed is evidence with limits, not a passing probe. Setup enablement is
  always quarantined and never becomes an approved client fix.
- A target commit change does not retarget the active packet; audit the new commit only in a new
  run, never a new version of the existing run.
- Repository size does not reduce domain coverage. Batch within the host cap or checkpoint on the
  operator's runtime constraints.
- Any allocation, ledger, immutable-publication, packet, result, verdict, or seal collision fails
  closed under the contract. Never delete or adopt the colliding object.
- Correcting an audited blocker allocates a new version and repeats packet, review, and sealing.
- Incomplete/non-conclusive evidence may be archived after the selected profile's archival predicate but
  is never remediation-planning input. Incomplete/conclusive is invalid.
- A default selection skips non-selectable seals; an explicitly requested non-selectable or
  invalid seal is rejected.

## Fallback

- On invalid intake or unresolved intent, stop at `[CHECKPOINT]` and name the missing decision or
  evidence. Never infer a profile, intent, authorization, credential permission, or client-fix
  approval.
- On an unavailable runtime, preserve `unverifiable` evidence and limitations; do not substitute a
  production system, live data, or broader credentials.
- On capacity limits, run fresh domain contexts in smaller batches without weakening their input
  isolation.
- On malformed ledger/publication state, stop for explicit repair. Do not rewrite history or retry
  blindly.
- On audited adapter absence or failure, stop at the explicit adapter seam. Do not substitute a
  native subagent, downgrade the selected profile, or label a standard seal audited.
- On a non-blocked audited verdict with warnings, preserve the warnings and evidence ceilings in
  the seal/handoff; do not normalize it to an unqualified pass.
- On downstream authorization failure, emit no handoff. Return to the human approval checkpoint
  for a new approval bound to the exact current seal and completed plan.

## Observability

- `RUN_DIR/audit/profile.md` shows the selected profile, immutable target, and authorization
  boundary. The product contract, domain register, independent coverage, runtime, and quarantine
  artifacts show what was and was not evaluated.
- `RUN_DIR/audit/version-index.ndjson` is the append-only publication ledger. The selected
  version's reservation, corrected audit, and seal make every immutable transition inspectable.
- For audited runs, the staged packet/result paths and adapter-owned canonical verdict expose the
  cold-review boundary and exact reviewed read set without exposing live author history.
- The Conductor records checkpoints, stop reasons, gate outcomes, default/explicit selection, and
  downstream authorization rejection or handoff in the run's normal human-readable log. That log
  is never part of the audited cold packet.
- Build verification uses only synthetic catalog, full, audited, and conflicted-intent fixtures.
  It never accesses the source audit-service path, unapproved client repositories, production
  credentials, or live customer data.
