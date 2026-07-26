# Calibration exemplars — voice/texture reference library

The `write-article` pipeline calibrates voice and shape against an exemplar (the Counselor reads it in frame; the Scribe reads it in outline/draft). Using ONE exemplar — or only the pipeline's own past output — homogenizes the whole corpus and creates a self-imitation loop that sharpens the "pipeline signature" over time. This library holds several exemplars keyed to AUDIENCE/CONTEXT.

## Selection rule (the Conductor follows this)

1. Read the Counselor's `angle.md` audience read (the spiral-dynamics value system it already classifies in the frame step).
2. Check for a project-specific voice-owner bucket matching the destination or named author. A matching voice owner takes precedence over a generic audience bucket.
3. If no voice-owner override matches, map the value system to a generic bucket below.
4. Pass the chosen exemplar's PATH to the Counselor (frame) and the Scribe (outline/draft) as the voice calibration — instead of hardcoding a single default.
5. **Rotate within a generic bucket** across runs (vary by run index) so successive same-audience pieces don't all match the same exemplar. For a voice-owner bucket, keep the owner primary and rotate among the exemplar's modes or secondary texture references instead.

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
- **[EXTERNAL] — ANCHORED (genuine human):** `external/dan-luu.md` + `external/simon-willison.md` (rotate between them); `external/paul-graham.md` for essay spine. Calibrate technical prose to THESE. The novadiem.com pieces above drop to subject-matter reference only (AI-seeded; not for voice).
- A hand-written technical piece *Robin vouches for* would still beat a borrowed voice; this slot stays open for it.
- candidate [HUMAN] raw-voice sources worth blessing: Robin's hand-written design docs / ADRs (e.g. `decisions/*.md`, architecture docs). Raw technical voice in his hand, even if not essay-shaped.

### founder-vision  (Green + Yellow — movement, mission, the "why")
- **[EXTERNAL] — ANCHORED (genuine human):** `external/maciej-ceglowski.md` (literary, warm, wide sentence-variance) + `external/paul-graham.md` (essay spine). For the warmer / community / Green-Purple end of this bucket, `external/wendell-berry.md` also fits.
- **[AI-GENERATED]** `/Users/robin/Code/foaftech/Growoperative/press/neighbour-economy-essay.md` — reads hand-written (first-person, personal anecdotes, real texture) but Robin confirms it is AI-generated. NOT a human anchor. Do NOT use it to break the self-imitation loop; it IS the loop.

### consumer-warm  (Green + Purple — neighbours, end users, rural; plain and warm)
- **[HUMAN] — lived rural-storytelling anchor (closest to target for rural-community pieces):** `external/rancher-fb-working-dog.md` — a real rancher's Facebook voice; warm, unforced, genuinely uneven (the unevenness is the asset). INTERNAL reference only, NEVER reproduced. Best for on-the-ground storytelling texture; pair with Berry for the moral/communal register.
- **[EXTERNAL] — ANCHORED (genuine human):** `external/wendell-berry.md` (the literary/moral cousin — warm, plainspoken, rooted in food/land/community; good for the argument's heart) + `external/craig-mod.md` (place + sensory warmth, for the lived-scene opening). Calibrate warmth HERE; never use the technical anchors for a Green/Purple piece.
- `/Users/robin/Code/foaftech/Growoperative/press/messaging.md` + `fact-sheet.md` — approved positioning copy + guardrails; use for on-message claims and tone (the primary source for a GrowOperative piece), not for prose shape.

### conscious-community  (Green + Turquoise/Purple — festival / healing / alternative-living crowd)
For messaging aimed at the conscious-festival / healing / regenerative / alternative-living subculture (large in the Kootenays; overlaps GrowOperative's people). For this audience the jargon IS the calibration — fluency in the dialect signals kin.
- **[HUMAN] — ANCHOR (festival/healing flavor):** `external/festival-conscious-community.md` (Jeet-K's festival post). INTERNAL only. Calibrate to its WARMTH / kinship / connection register, NOT its fog.
- **[HUMAN] — second ANCHOR (outdoor/snow-stoke flavor):** `external/sijay-snowboard-conscious.md` (Sijay's snow-season post). The flow / nature-mysticism / "first chair massive" wing of the same register. Two flavors give the bucket range rather than one writer's tics.
- For both: the reach-for-profound IS the dialect here, not a flaw to fix. CRITICAL: marry their connection register to a REAL, specific GrowOperative scene (their warmth, your concreteness); press-kit rules still hold (honest soft-launch, neighbours-not-banking, no crypto-for-users). WHEN NOT TO USE: it backfires on the rancher/farmer crowd (the Madrone register is its opposite), on engineers, and on formal readers. Audience-classify first.

### mythmaker-hjeron  (Purple primary + Green care — Hjeron's own audience and voice)
**Project-specific override:** when an article is for MythMaker or written as Hjeron, this bucket beats the generic `conscious-community` match. Hjeron's own voice is the primary calibration; do not rotate him out in favor of an admired outside voice.
- **[HUMAN, VOICE OWNER] — ANCHOR:** `external/hjeron-warriors-path-transcripts.md` — a multi-register excerpt set from Hjeron's public Warrior's Path transcripts. It captures his myth-to-action movement, direct questions, candid first-person stakes, active verbs, repetition, and invitation to walk or build together.
- The exemplar contains five modes. Select the mode by article intent rather than forcing one cadence everywhere: mythic frame, lived misunderstanding, tracking a story, candid rebuilding, or purpose and invitation.
- For extra texture, a `conscious-community` exemplar may inform the audience read, but it must not replace Hjeron's voice. MythMaker's Orange proof remains concentrated at booking and workshop conversion moments, not spread through reflective prose.
- Treat transcript teachings as attributed source material, not automatically verified fact. Preserve the exemplar's cultural, medical, safety, Burning Man, and punctuation guardrails.

### professional-client  (Blue + Orange — clients, proposals, formal register)
- `/Users/robin/Code/novadiem/assistant/upwork/agentic-ai-engineer/work/02-final.md` — the reviewed proposal. (M2R client-comms exemplars if/when available.)

## How to add an exemplar
Drop the path under the right bucket with a provenance tag and a one-line note on register. For [EXTERNAL] excerpts, store a short referenced passage (a few paragraphs) under `config/calibration-exemplars/external/<name>.md` with attribution; it is an internal cadence reference, never republished.

## Status

**Genuine human anchors are now in** (external published writers, short attributed excerpts under `external/`):
- **technical-builder — ANCHORED:** Dan Luu + Simon Willison (rotate); Paul Graham essay spine.
- **founder-vision — ANCHORED:** Maciej Cegłowski + Paul Graham.
- **essay-spine (cross-cut):** Paul Graham. **texture-spice:** Maciej Cegłowski.
- **consumer-warm — ANCHORED:** a real rancher's Facebook post (`rancher-fb-working-dog.md` — [HUMAN], the lived-storytelling anchor, internal-only) + Wendell Berry (literary/moral cousin) + Craig Mod — the Green/Purple warm register (community / neighbour / local-paper / rural pieces). For a GrowOperative piece, pair with the press kit's messaging/fact-sheet as the on-message guardrail.
- **conscious-community — ANCHORED:** Jeet-K (festival/healing) + Sijay (outdoor/snow-stoke) — two flavors of the conscious-community register, both [HUMAN] internal-only. For the conscious / festival / healing / outdoor crowd (big in the Kootenays). Calibrate their warmth/kinship register but keep GrowOperative concrete + on-message. Backfires outside that subculture.
- **professional-client — still interim.** Formal-business is a different register; no fitting external human anchor yet.

Corollary learned the hard way: AI-generated prose in Robin's repos is good enough to pass as hand-written on a read (it fooled a careful reviewer). So provenance is NOT judged by reading — a [HUMAN]/[EXTERNAL] tag is valid only if (a) Robin vouches a specific in-repo piece is genuinely hand-written, or (b) it is a known external human author. The AI neighbour essay is tagged [AI-GENERATED] for exactly this reason.

**Still better, when Robin has it:** a genuinely hand-written piece of his own (a pre-AI blog post, school/work writing). His real voice beats a borrowed one. He'll dig one up later; until then the house calibrates toward these admired outside writers.
