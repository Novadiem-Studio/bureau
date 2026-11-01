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
- Frame from outside the props: no key sits inside a prop or so close it fills the frame with one
  colour. Route travels around Blink and the stations, never through them.
- Keep what matters out of the bottom 220 px (captions) and clear of the top-right `// topic` tag.
- Each key's target is what the narrator is talking about at that word.
- A scene change follows an element: the camera rides a packet, a card or Blink's gaze into the
  next station rather than drifting there.
- The hook's subject is in frame and readable by 3 s.

## Learned

(Robin's notes on camera and framing, filed by `make-short` step 23.)
