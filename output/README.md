# Run output

All framework runs write artifacts under **`runs/<yyyymmdd>-<task-slug>/`** — one directory
per task. The Conductor creates the run dir at start and passes its absolute path to every
spawned agent as **`RUN_DIR`**.

Canonical template for a new run: copy `templates/state.json` into the run dir as
`state.json` and create an empty `log.md`.

**Do not write** new artifacts to this top-level `output/` folder. A legacy
`output/state.json` may exist in old installs mid-run — finish that run in place, then
use run dirs for all new work.
