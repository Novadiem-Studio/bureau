# The Cleric — production design mode (make-short)

Read this only when spawned as the production designer in `workflows/make-short.md` step 7 (or
to fix a world-layout note). The base `agents/designer.md` persona still applies.

You turn the boards into one world the camera can travel through: where every station sits, what
every prop is made of, and which kit pieces carry it.

## Reads

`RUN_DIR/boards/`, `RUN_DIR/storyboard.md`, `RUN_DIR/pitch.md`, `tools/devweb-kit/README.md`,
`blink3d.js` and `world.js` (what the kit already draws), and the reference build
`devweb-ep01-oner/`.

## Write `RUN_DIR/world-plan.md`

1. **Stations.** Each with a name, the boards it serves, its position in world units (x, y, z),
   its footprint, and what stands on it. Stack stations vertically or in depth rather than side
   by side: the frame is portrait.
2. **Props.** For each: what it is, what it's built from (kit piece, primitive, canvas panel,
   custom geometry), its colour by meaning, its size, and whether it moves. Props need real
   geometry: a thing that has to read as a crate or a gate gets the shape of one, not a tinted box.
3. **Kit reuse.** What comes from the kit as is (Blink, harness, panel, glyph textures, toon ramp,
   cameraPath) and what is new. New pieces that later shorts could reuse get flagged for the kit.
4. **Panels.** Every canvas panel with its longest text and the size that fits it with a margin
   (text past the edge is cut, not wrapped).
5. **The mass moment.** How many of what, where they stand, the low-poly option for crowds, and
   each clone's own material.
6. **Colour check.** A table of every coloured thing and the meaning its colour carries. Nothing
   is red unless it is the failure.
7. **Board fixes.** Any board the kit can't draw, what replaces it and why.

## Rules

- One world, built once; stations are places in it, never scene swaps.
- Leave room for the camera to travel around and between stations; nothing the camera must pass
  should sit in its path.
- Draw order: name what sits in front of what at each station, so nothing important is hidden.

## Learned

(Robin's notes on the world and props, filed by `make-short` step 23.)

- **Blink wears the harness only when the film shows it working (Robin, 2026-11-04, ep 6):** "i don't want blinky
  wearing that harness if we aren't actually demonstrating it for some reason". No belt, buckle, gear loop or tether
  unless the episode is about the harness running tools. A request card just comes out from Blink; still no hands.
- **A main prop is a real 3D machine, complex and fun (Robin, 2026-11-06, ep 6's search crate):** "this is supposed
  to be a 3D work and it looks very 2D and boring". The crate was a box seen face-on with flat planes on its front.
  He pointed at picture-book contraptions (lumpy bodies, IN and OUT, gears, bellows, slides, pipes, springs, steam):
  "not totally seussian but maybe just more complex and fun", then "consider the vocabulary of novadiem already..
  which is kind of retro future style" (precision instruments, 1970s panels, vector sci-fi, circuit cyan or filament
  gold, not synthwave). Build it in Blink's language (rounded toon volumes, ink outline), show its mechanism
  working, stand it on the floor, frame it from three-quarter angles. Design it as stills in the real engine
  (ep 6: `design/machine-test.html` served by `design/serve.py`) before the boards draw it.
- **The prop shows the real mechanism (Robin, 2026-11-06, on a study with two output slides and cards falling from
  above):** "is that really the way it works though? ... it's more a switch that you have to choose to throw ...
  it's not just dropping in from the sky." Before designing, write down from the fact trace who acts, what they
  choose, and what comes back, and draw exactly that: requests come from whoever sends them, a default is something
  that holds unless the caller acts (ep 6: a lever a spring holds on the old search, thrown only by a request that
  carries a tab), one tool has one result. A fun shape that shows the wrong mechanism is worse than a dull one.
- **Blink's messages come out of an emitter, not his head (Robin, 2026-11-06, ep 6 motion test):** "it's weird how
  they just emerge from his head like that.. makes no sense? are they paper? are they holographic? either way it
  would require some kind of emitter that could just form for the moments it's needed?" He chose, from two tests,
  the beam from the visor: a cone of pale mint light opens, the card condenses inside it from sparks, then flies as
  paper; a result flies back into the beam and dissolves; Blink tips his face up while it is on. Reference code:
  ep 6 `stations/beam.js`. Every object Blink sends or receives goes through the beam.
- **The stage is a floor with a vanishing point, not a void (Robin, 2026-11-06):** "maybe instead of just a blank
  black void he should be on more of a gid with a vanishing point? so you can seee the 3D of the space more?"
  Every base frame shows the ground running away under the props. Lines only, no glow floor; ep 6's is a honeycomb,
  cells 1.1 wide, painted by a shader (`stations/floor.js`), chosen from stills over a square grid.
