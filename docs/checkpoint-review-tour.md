# Checkpoint review tour

The Bureau gives reviewers a separate context and a defined set of evidence. This tour follows a routine checkpoint in the integrated Delegate path, from the Conductor's handoff to the decision to continue. It links the design to the scripts and checks that support it. The [README](../README.md) covers the wider system and its current availability.

## Follow a checkpoint

```text
Conductor writes artifact + checkpoint context
                      |
Delegate stages a review packet
                      |
Review helper validates packet and hashes artifacts
                      |
Fresh reviewer returns decision + reported artifact coverage
                      |
Helper checks response; Delegate applies acceptance rules
                      |
              Continue, revise or escalate
```

1. The Conductor writes the artifact and checkpoint context before returning control. Its return block names the artifact, digest, question and checkpoint type. The [integrated bridge contract](delegate-bridge/v2-integrated.md) defines that handoff and the packet the Delegate stages: artifacts, run state, a checkpoint log slice, reviewer instructions and conventions. The full run log and previous verdicts are excluded.

2. [`run-cold-reviewer.sh`](../scripts/run-cold-reviewer.sh) checks required files and rejects packets containing symlinks, a file named `log.md` or transcript-like filenames. It writes `artifact.sha256` for the primary document and `artifacts.sha256` for all documents under review. The reviewer prompt names each artifact with its digest. Supporting instructions and state are kept outside that artifact manifest.

3. The helper launches the reviewer through a host adapter. For example, the Codex adapter copies the packet into a temporary snapshot, makes it read-only, disables network tools and denies access to the live run, repository and session stores. The [host runtime contract](host-runtime.md) describes the adapters and their different boundaries.

4. The response includes a decision, the primary artifact's hash and an `Artifacts-read` list of paths and hashes. The helper validates the response shape, compares the primary hash and checks the reported list against the manifest in both directions. It reports missing and unexpected entries. The [Delegate's acceptance rules](../agents/delegate.md) require discarding a verdict when `hash_match` or `artifacts_read_complete` is false. These flags are part of the helper's result; a successful process exit alone is insufficient.

## Why name every artifact?

A plan can depend on a specification. Staging both files does little good if the reviewer is only told to read the plan.

That failure prompted the packet-coverage change documented in the helper. The manifest now makes supplementary documents explicit, and the returned coverage list can be checked against it. This adds prompt text and bookkeeping, but makes a missing document visible before the review is accepted.

The [packet self-test](../scripts/check-cold-reviewer-packet.sh) demonstrates the distinction with a two-document packet. Stub reviewer responses cover both documents, skip the specification, omit coverage entirely, or claim an unstaged file. It also checks that a Cursor review cannot resume against a packet whose manifest changed.

## What the checks cannot establish

`Artifacts-read` is a reviewer assertion. Matching it to the manifest checks the reported evidence set; it cannot prove that the model read carefully or reached a sound conclusion. The packet self-test uses stub responses, so it tests the harness's handling of those responses, not review quality.

The separate context also removes information. A cold reviewer cannot detect an unwritten trade-off or know that the task overlaps unrelated live work. The [bridge contract's residual-gap section](delegate-bridge/v2-integrated.md) leaves those judgments with the Conductor and keeps the revision counter with the Delegate.

For a separate example of checking that a recorded review still applies, inspect [`verdict-gate.sh`](../scripts/verdict-gate.sh) and its [stale-file regression fixture](../.bureau/regression/189-hash-mismatch-fails-loud.md). The fixture records a file's digest, changes the file, and expects the gate to reject the old record. This is a different verdict contract from the Delegate response above.

## Run the packet check

From the repository root, with Bash, Python 3 and jq available:

```sh
bash scripts/check-cold-reviewer-packet.sh
```

It uses temporary files and stub reviewer commands. It makes no model calls. [`check-framework.sh`](../check-framework.sh) includes this check; the [standing regression suite](../.bureau/regression/README.md) covers additional framework behavior.
