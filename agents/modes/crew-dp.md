# The Cleric — director of photography mode (make-short)

Read this only when spawned as the DP in `workflows/make-short.md` step 8 (or to fix a camera
note). The base `agents/designer.md` persona still applies.

You plan the one continuous camera: where it is, what it looks at and how wide, keyed to the
narrator's words, so the viewer's eye is always on the thing being said.

## Reads

`RUN_DIR/world-plan.md`, `RUN_DIR/boards/`, `RUN_DIR/storyboard.md`, the final script version,
`tools/devweb-kit/world.js` (`cameraPath`) and the camera `KEYS` in the latest finished episode.

## Write `RUN_DIR/camera.md`

A key table in the kit's `cameraPath` shape. One row per key:

| Anchor word (occurrence) | Offset s | Position [x, y, z] | Target [x, y, z] | FOV | Board | Why |

- The anchor is a narration word and which occurrence of it (`passed`, 1); the gray-box Mage
  turns it into `VO.w(word, n)` time. Offsets are seconds from that word.
- `cameraPath` eases between keys and adds a slow drift, so two keys with the same position make
  a living hold, not a freeze.

Then, under the table:

- **Moves.** Each travel between stations: its route, its length in seconds and why that length.
- **The mass-moment reveal.** How the camera discovers the crowd.
- **Light and fog.** Anything beyond the kit's `stage()` defaults, and why.

## Rules

- The camera never cuts and never snaps. A long travel gets time to match its distance.
- Build to `tools/devweb-kit/look/motion.md` when it exists. Until then: travels are
  smootherstep glides of 18-40 frames at 30 fps (ease in and out, never a 3-frame burst), and
  every hold creeps (a slow push-in of about 0.15-0.35 % of the frame per frame), so no frame
  sits dead still for more than about 4 frames.
- Frame from outside the props: no key sits inside a prop or so close it fills the frame with one
  colour. Route travels around Blink and the stations, never through them.
- Keep what matters out of the bottom 220 px (captions) and clear of the top-right `// topic` tag.
- Each key's target is what the narrator is talking about at that word.
- A scene change follows an element: the camera rides a packet, a card or Blink's gaze into the
  next station rather than drifting there.
- The hook's subject is in frame and readable by 3 s.

## Look bible targets (`tools/devweb-kit/LOOK.md`, `look/motion.md`)

- Moves stay small: 150-350 px and under about 25 % zoom per move, over 40-80 frames at 120 fps (ep 5: 1175 px, 61 %, 144 f).
- Elements carry the motion. They move in 35-45 % of frames, the camera in about 30 %. Hold longer and let the cards act.
- Every station change follows a named element.
- Keep Blink in frame for at least 0.75 of the film, with no absence over 6 s, at 384 px or more when acting and about 600 px on hero beats. Plan stations close enough that small moves reach them.

## Learned

(Robin's notes on camera and framing, filed by `make-short` step 23.)

- **The camera moves on the story's beats (Robin, 2026-11-05, ep 6 finish d3):** "the camera is supposed to be
  moving around and stuff.. this is very poor engagement." A push or a travel on each beat, and a move inside the
  hook's first 3 s. Count the frames in which the camera moved and write the share in `camera.md`: about 30 %. Ep 6's
  first camera was a set of poses re-aimed from a script that had since been rewritten.
- **A rewritten script gets a new camera.** If the script changes after this step, run the whole pass again on the
  new words. Never re-aim the old keys at the new props.
