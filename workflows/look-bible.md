# Workflow: look-bible

**Objective:** a measured look bible for a video series: numbers, not adjectives, taken from
reference videos Robin picked, so every episode's crew builds to the same bar and its gap pass
has something to measure against. "You can't recreate an opinion. You can recreate a number."

**When to use:** a series has no look bible yet (`tools/devweb-kit/LOOK.md` for devweb), Robin
names new reference videos, or he says the episodes look cheap next to something. `make-short`
step 0 calls it when `LOOK.md` is missing. Triggers: "build the look bible", "measure these
shorts", "make it look like X".

**When NOT to use:** one episode's fixes (→ `make-short` steps 19-20); a style the series does
not want to copy (pick different references first).

**Type:** plan. It writes study notes and numbers; nothing renders, uploads or spends. Run as
**direct Conductor**; Robin's only part is naming the references.

Method credit: the look-match loop in Mr omi's claude-animated-shorts skill (MIT,
github.com/mromidev/claude-animated-shorts), studied 2026-11-02. We borrow the method, not his
numbers: his were measured on a different style.

## Inputs

- **References**, named by Robin: video files or links, and which parts of them matter. Study
  material only: never uploaded, published, quoted on screen or credited (series README,
  "Borrowed topics stay quiet").
- **Our current frames:** the latest finished episode's master (devweb: the newest
  `renders/*_1080p60.mp4`) and the kit README.
- The series rules (devweb: `~/Code/novadiem/assistant/ideas/devweb-shorts/README.md`). The palette
  and the one-world rule are ours and are not up for matching: the bible measures how well a
  reference uses its look, and we carry that quality into ours.

## Outputs

`RUN_DIR` holds the working files. The result lives with the kit so every episode reads it:

- `tools/devweb-kit/look/<topic>.md`, one per topic: the reference's numbers, the same numbers on
  our latest episode, the gap stated plainly, and a recipe in our stack (which kit file or crew
  role, which value).
- `tools/devweb-kit/LOOK.md`: one page of targets per topic, each a number with its unit, plus
  the top ten changes ranked by visual impact.
- `RUN_DIR/brief.md`, `log.md`, `state.json`.

## Topics

Each is measured on many frames across all the references, frame by frame where it matters:

| Topic | Measure |
|---|---|
| motion | camera speed per frame (phase correlation, captions masked), share of frames moving, glide length and easing, hold creep in % per frame, cuts per video, impact kicks |
| grade | luma median and p5/p95, saturation p90, shadow and highlight hue, how light changes across the story |
| depth | share of screen time with background blur, blur radius by shot size, fog, where focus sits |
| outlines | line width at 1080 wide, colour, which edges get lines |
| characters | proportions, line weight, expressions per minute, blink rate, how acting lands against the word |
| pacing | words per second, gaps over 0.25 s, how the hook and the pivot are built (from transcripts) |

## Done criteria

- Every topic file has reference numbers from at least ten references, ours beside them, and a
  recipe a crew role can act on.
- `LOOK.md` names a target for each topic and the ten biggest gaps.

## Edge cases

- **Captions burned into a reference:** mask their band before any statistic, and never read a
  caption outline as an ink line.
- **A measuring tool can't see slow motion** (integer phase correlation misses moves under about
  4 px/f): fit sub-pixel, and check any "the camera holds" finding by eye on a contact sheet.
- **A finding contradicts another topic's notes:** the measurement wins; say so in both files.

## Fallback behavior

- A spawn errors or returns no handoff: re-spawn once, then report to Robin.
- No references named: stop and ask Robin; never pick them on his behalf.

## Observability

`RUN_DIR/log.md` records each spawn and each topic's top gap. The topic files carry the scripts'
paths so a later run can re-measure.

## Steps

Spawn per `agents/orchestrator.md § How to spawn an agent`, model from `RUN_DIR/model-routing.json`.

0. **The Conductor** — set up → `brief.md`, `state.json`, `log.md`
   The references Robin named, where their frames live, our latest master, the topics table.
   Pull 30 fps contact sheets (one sheet per 2 s of video) for every reference into `RUN_DIR/sheets/`.

1. **The Cleric** (Look analyst, **strong**) — one spawn per topic, up to three at a time → `tools/devweb-kit/look/<topic>.md`
   Mode file `agents/modes/crew-look.md`. Each owns one topic file and its scripts folder
   `RUN_DIR/look/<topic>/`, nothing else.

2. **The Conductor** — write the summary → `tools/devweb-kit/LOOK.md`
   Targets per topic from the topic files, verbatim numbers, and the ten biggest gaps. Commit on
   the series branch and open a PR.
