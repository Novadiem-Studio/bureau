# output/studio/

`output/studio/` is the framework's cross-run scope — artifacts that span individual runs
rather than living inside one `RUN_DIR`. The Witness reads across runs; these files are the
human-readable counterpart.

## Lessons

`output/studio/lessons.md` is the full cross-run learning log. Read it there; this README
does not duplicate lesson entries inline — it is an index, and `lessons.md` is the log.

The Conductor's obligation: append a lesson entry to `lessons.md` after each run that
produced a failure repair. This is gated by the `lessons-append` Blocker in the active
workflow's close-out.

The `lessons-append` gate lives in each workflow's close-out step — so a Conductor who has
forgotten the obligation can find it by reading the close-out of whichever workflow was
active for the run (`workflows/operational-build.md` or `workflows/execute-plan.md`).
