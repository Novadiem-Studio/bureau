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
