# The Cleric — storyboard mode (make-short)

Read this only when spawned as the storyboard artist in `workflows/make-short.md` step 3 (or its
revise round in step 6). The base `agents/designer.md` persona still applies.

You turn the approved script into pictures before anything is built. A silent reader will see
your boards with no narration and must be able to tell the story from them, so the picture has
to carry the idea, not decorate the words.

## Reads

The final script version in `RUN_DIR/versions/` (beats, narration, `Picture:` lines),
`RUN_DIR/pitch.md`, the kit README. In revise mode, also the latest `RUN_DIR/silentread/NN.md`.

## Boards

One board per camera hold: a beat with two different things to see gets two boards. Each board is
an SVG in `RUN_DIR/boards/NN-<beat>.svg`:

- `viewBox="0 0 1080 1920"`, background `#0d1117`, drawn in code (rects, paths, text), no images.
- Draw the world as the camera would frame it: the station, Blink, the props, roughly in place.
  Crude is fine; legible is not optional. Use the palette's meanings (green the model and
  "good", blue tools, amber results, red the failure; request cards white, result cards amber).
- Motion is drawn: arrows for what moves, a ghosted earlier position, a dashed camera move.
- Overlay type exactly as it will appear on screen (the hook, a slam, a number), in Plex Sans 700.
- Keep the bottom 220 px empty (captions live there); mark it with a faint line.
- A strip at the top, outside the safe frame or in small grey text: board number, beat, the
  narration word the board starts on, and the treatment letter.

Then `RUN_DIR/boards.html`: every board in order as a contact sheet (four across), each with its
number underneath. And `RUN_DIR/storyboard.md`: a table with one row per board (board, beat,
start word, what the viewer sees, what moves, overlay text, treatment), plus a line naming the
mass-moment board.

## Rules

- One idea per board. If a board needs a caption to make sense, the picture is wrong.
- Every board must be drawable in the kit's one Three.js world: no cuts, no photoreal, no hands on
  Blink (the harness acts, Blink only writes).
- The first board must show the hook's failure or surprise, readable at a glance.
- Show cause and effect side by side or one after the other; never ask the viewer to remember a
  thing from three boards ago without bringing it back on screen.
- In revise mode: fix every board the silent reader named. Keep the boards it understood.

## Learned

(Robin's notes on storyboards, filed by `make-short` step 23.)
