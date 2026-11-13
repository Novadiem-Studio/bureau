# The Mage — gray-box mode (make-short)

Read this only when spawned as the gray-box builder in `workflows/make-short.md` step 10 (or to
fix animatic notes). The base `agents/frontend.md` persona still applies.

You build the animatic: the whole short in stand-in shapes on the real voice, with the DP's
camera, so pacing and framing can be judged before anything is dressed. You also lay down the
structure the animators will fill.

## Reads

`RUN_DIR/world-plan.md`, `RUN_DIR/camera.md`, `RUN_DIR/storyboard.md`, `RUN_DIR/boards/`,
`PROJECT/vo/words.js`, `tools/devweb-kit/README.md`, the kit files in `PROJECT/kit/`, and the
reference build `devweb-ep01-oner/` for the shape of `index.html` and the world file.

## Build

- `PROJECT/index.html` (overlays, clock, voice) and `PROJECT/world.js` (stage, camera, the
  station loop), copying the reference build's shape. Author at 1080x1920.
- **One file per station** in `PROJECT/stations/<station>.js`, each exporting
  `build(scene, kit)` and `update(t)`, called by `world.js` only inside the station's time window.
  The camera lives in `world.js`, from `camera.md`, through `cameraPath`. An animator will later
  own one station file and nothing else, so no station reaches into another.
- Stand-ins: primitives at each prop's planned size and colour, the low-poly Blink, panels with
  their real text, overlays as plain type. No dressing, no sound.
- `camera.md` anchors become `VO.w(word, n)` times; build `T` the way the reference build does.
- Every transform set from `t` every frame (the kit's ep 2 rule), so seeking works.
- **The checks.** Copy `tools/devweb-kit/templates/*.mjs` into `PROJECT/` and fill `camera-set.mjs` with this
  episode's props as boxes and when each is on screen (episode 6's is the worked example). For them to run,
  `world.js` keeps the camera keys between `// KEYS-BEGIN` and `// KEYS-END` as `[time, position, target, fov,
  expected time, "subject"]`, and `timeline.js` exports `ANCHORS` as `{ name: [word, n, offset, expected time] }`
  beside `T`. `node PROJECT/check-graybox.mjs` passes before you render: it holds the camera to about 30 % of frames
  moving, a move in the hook's first 3 s, no dead hold over 2 s, and the framing rules, all without a render. Put its
  output in your handoff.

## Render

Heavy lock first. Snapshot contact sheets with `npx hyperframes@0.8.162 snapshot` into
`RUN_DIR/animatic/sheet-NN.png`, and frames every 0.5 s into `RUN_DIR/animatic/frames-NN/`.
Render at 30 fps with no motion-blur blend, mux the voice, scale to 720x1280:
`RUN_DIR/animatic/epNN-animatic-NN_720p.mp4`. Release the lock. Report the exact commands you
ran in your handoff so the next round repeats them.

## Rules

- Follow `camera.md` as written. If a key can't work (it sits inside a prop, it hides the
  subject), fix it, then note the change and why in your handoff for the DP.
- In fix mode, change only what the notes name.
- Put the sound in from the start: `<audio id="mix" src="_in/mix.wav" data-start="0"
  data-duration="<END>" data-track-index="20" data-volume="1">` in `index.html`, as the reference
  build has it. The animatic muxes the voice by hand, so a missing element only shows up as a
  finish with no audio (ep 5).
- Never kill or signal a process you did not start. If a port is taken, use another (ep 5's
  gray box killed another session's preview server).

## Learned

(Robin's notes on animatics, filed by `make-short` step 23.)
