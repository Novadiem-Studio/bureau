# Battle Test: Bug Diagnosis Discipline

**Artifact:** bundle 36 implementation slice (`docs/conventions/diagnosing-bugs.md`,
`workflows/bug-fix.md`, build-party personas, build-diff Challenger gate)

## Cases

| Case | Setup | Expected result | Status |
|---|---|---|---|
| Happy path — app target | A non-bureau app bug has a correct test seam in its existing suite. | `repro.md` records the red-capable loop, minimised repro, test path, pre-fix red evidence, and post-fix green evidence; the diff commits the test and fix. | PASS — static fixtures 221-223 pin the workflow/persona/review contracts |
| Happy path — bureau target | A bureau-framework bug is fixed in this repo. | Regression home is `.bureau/regression/NNN-slug.md`; the fixture fails before the fix and passes after. | PASS — fixture 222 pins the per-repo home rule |
| Edge — no correct seam | The bug can be fixed, but every available test seam is too shallow to exercise the real call-site chain. | No fake test is added; `repro.md` records `Regression test: none — no correct seam`, attempted seams, and follow-up. Challenger records at least a Standards warning. | PASS — fixtures 221 and 223 pin the escape and review severity |
| Failure mode — green-only test | A coder adds a test but records no pre-fix red evidence. | Build-diff Challenger raises a Blocker. | PASS — fixture 223 pins missing pre-fix red as a Blocker |
| Failure mode — foggy guess patch | Cause is unclear after reproduction, but the run patches without minimising, hypotheses, or probes. | `diagnosing-bugs` discipline requires minimisation/probes first; unresolved fog raises a checkpoint instead of guess-and-patch. | PASS — fixture 221 pins the foggy-cause loop |

## Run — 2026-07-21

Result: 5/5 cases pass in the working tree. The implementation slice is ready, but the bundle is
not done until a non-bureau bug-fix run leaves a committed app-suite regression test with
pre-fix red and post-fix green evidence.
