# Calibration exemplars — voice/texture reference library

The `write-article` pipeline calibrates voice and shape against an exemplar (the Counselor reads it in frame; the Scribe reads it in outline/draft). Using ONE exemplar — or only the pipeline's own past output — homogenizes the whole corpus and creates a self-imitation loop that sharpens the "pipeline signature" over time. This library holds several exemplars keyed to AUDIENCE/CONTEXT.

## Selection rule (the Conductor follows this)

1. Read the Counselor's `angle.md` audience read (the spiral-dynamics value system it already classifies in the frame step).
2. Map that value system to a bucket below.
3. Pass the chosen exemplar's PATH to the Counselor (frame) and the Scribe (outline/draft) as the voice calibration — instead of hardcoding a single default.
4. **Rotate within the bucket** across runs (vary by run index) so successive same-audience pieces don't all match the same exemplar.

The mechanism that makes this work already exists: the Counselor classifies the audience on every run. This library is just the menu it selects from.

## Provenance tags (the honest part)

Genuinely-human exemplars must come from a human. The pipeline cannot author its own "human" exemplar without recreating the homogenization this library exists to fix.

- **[HUMAN]** — hand-written by Robin. The gold standard: it anchors his real voice, which is what the house should sound like.
- **[EXTERNAL]** — writing by an outside author Robin admires; a referenced excerpt used as a cadence target (not republished). The best source of genuinely *different* rhythm. SLOTS to fill.
- **[PIPELINE-ADJACENT]** — earlier or converted output. Breaks the single-exemplar rut but does NOT break the self-imitation loop. Interim only; upgrade toward [HUMAN]/[EXTERNAL].

## Buckets

### technical-builder  (Orange + Yellow — engineers, builders, systems thinkers)
devweb engineering/frameworks pieces; agent + architecture writing.
- **[PIPELINE-ADJACENT, interim]** `/Users/robin/Code/novadiem/novadiem.com/articles/*.md` — rotate among these. Distinct from the current default, but provenance is AI-assisted; not a clean anchor.
- **[HUMAN] — ANCHOR SLOT (the key gap):** a hand-written technical piece Robin designates, or an [EXTERNAL] technical essay he names. ← fill this to break the loop on the technical bucket.
- candidate [HUMAN] raw-voice sources worth blessing: Robin's hand-written design docs / ADRs (e.g. `decisions/*.md`, architecture docs). Raw technical voice in his hand, even if not essay-shaped.

### founder-vision  (Green + Yellow — movement, mission, the "why")
- **[HUMAN]** `/Users/robin/Code/foaftech/Growoperative/press/neighbour-economy-essay.md` — clearly Robin's hand; first-person, real texture. Strong anchor.

### consumer-warm  (Green + Purple — neighbours, end users; plain and warm)
- `/Users/robin/Code/foaftech/Growoperative/press/messaging.md` + `fact-sheet.md` — approved warm register (positioning copy, not essay; use for tone, not shape).

### professional-client  (Blue + Orange — clients, proposals, formal register)
- `/Users/robin/Code/novadiem/assistant/upwork/agentic-ai-engineer/work/02-final.md` — the reviewed proposal. (M2R client-comms exemplars if/when available.)

## How to add an exemplar
Drop the path under the right bucket with a provenance tag and a one-line note on register. For [EXTERNAL] excerpts, store a short referenced passage (a few paragraphs) under `config/calibration-exemplars/external/<name>.md` with attribution; it is an internal cadence reference, never republished.

## Status
- founder-vision: anchored ([HUMAN] neighbour essay).
- consumer-warm / professional-client: seeded.
- **technical-builder: interim only — needs a [HUMAN] or [EXTERNAL] anchor from Robin.** This is the one open slot.
