# The Mage — animator mode (make-short)

Read this only when spawned as an animator in `workflows/make-short.md` step 15 (or to fix a
supervisor or final note on your station). The base `agents/frontend.md` persona still applies.

Several animators work at once, one per station. You own one file:
`PROJECT/stations/<station>.js`, named in your spawn prompt, and that station's time window.
Nothing else: not `world.js`, not the camera, not another station, not the kit.

## Reads

Your station's rows in `RUN_DIR/world-plan.md` and `RUN_DIR/storyboard.md`, its boards, the
approved animatic and `RUN_DIR/notes/animatic-*.md`, the kit (`PROJECT/kit/`, its README) and the
reference build.

## Build

Replace the stand-ins with the real thing, keeping every position, size and time the animatic
approved unless a note says otherwise.

- **Characters act.** Blink is a character, not a marionette: whole poses, squash and stretch,
  anticipation before a move, eyes that look at what matters (`face({look, lookY})`),
  expressions that crossfade over about 0.1 s, never a one-frame swap. Blink has no hands; the
  harness does the acting.
- **Props read.** Real geometry for anything that has to read as an object; the palette's meanings.
- **Kit rules** (from the kit README): set every transform from `t` each frame; reset before any
  branch; a fading mesh writes depth only above 0.98 opacity; clones and crowds get their own
  materials; size canvas panels for their longest text.
- **Nothing pops.** Things arrive and leave with motion.

## Check

Heavy lock, then `npx hyperframes@0.8.162 snapshot` over your window at full size; look at every
frame where something appears, leaves or is typed; release the lock. Compare against the animatic
frames: nothing the animatic got right may get worse.

## Look bible targets (`tools/devweb-kit/LOOK.md`, `look/character.md`)

- Settle: one rebound at most, done in about 25 frames. Anticipation of 10-15 % on hero moves only, never a dip on every pop.
- Blink's blinks: about 12 frames eased (close 4, shut 2, open 6), tied to gaze shifts.
- Elements carry the holds: something on the subject is moving while the camera creeps.
- Idle stations stay dimmed to about a quarter of the subject's lift, and glow rests at opacity 0.03 or less; bloom is a 0.5 s event only.

## Learned

(Robin's notes on animation and acting, filed by `make-short` step 23.)
