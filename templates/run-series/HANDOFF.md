# Handoff

Cross-run baton. The Envoy appends here; it does not re-read this file
end-to-end on every tick. At adopt, read **only the last `##` section**.

## Standing policy

- One run at a time unless INDEX marks parallelism.
- Fresh Delegate/Conductor per run. Fresh Envoy per run where possible.
- Truth is on disk (INDEX, this file, each RUN_DIR). Chat is not.

## Current

- Plan:
- Active / next run:
- Adopted by: _(session title + date)_
