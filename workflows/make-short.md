# Workflow: make-short

**Objective:** a finished devweb short (narrated, vertical, one Three.js world, one continuous
camera) made by a crew of roles, each writing a file the next one reads and each judged cold, so
the picture is planned before it is built and Robin's notes land while they are cheap.

**When to use:** Robin wants the next devweb episode made end to end ("make episode 6", "run the
crew on D14", "make-short"). It contains `write-short-script` as its writers' room.

**When NOT to use:** only the narration (→ `write-short-script`); a long-form article
(→ `write-article`); a music video or client film (the `second-unit-video` /
`motion-graphics-music-video` skills); a fix to one already-approved shot (patch it in the
episode's own session).

**Type:** mixed. Phases 0-3 plan and build a gray-box animatic; phase 4 builds the finish. Run as
**direct Conductor**: Robin sits at two gates only (the animatic, step 14, and the final watch,
step 21). Every other gate is a cold reader's verdict.

## Inputs

The Conductor writes these to `RUN_DIR/brief.md` in step 0:

- **Episode number and topic.** The topic is the next unmade entry in
  `~/Code/novadiem/assistant/ideas/devweb-shorts/episodes-ranked.md`, or the one Robin names.
  Topics are already chosen: no role screens or rejects one (Robin, 2026-11-01).
- **Source:** the devweb article (`~/Code/novadiem/devweb/content/articles/<slug>.mdx`) and the
  candidate's line from `candidates-devweb.md` (hook, receipt, visual).
- **Series rules** from `~/Code/novadiem/assistant/ideas/devweb-shorts/README.md`: no product
  names in script or picture; it has to animate; hook in the first 3 s; facts traced; no URL on
  screen; the palette (bg `#0d1117`, green `#6ad08a` = the model and "good", blue `#4f93d6` =
  tools, amber `#d6a45a` = results, red `#e0675a` = the failure; a request card is always white,
  a result card always amber); one Three.js world, one camera that never cuts, one mass moment;
  type as an overlay; 1080x1920 at 60 fps with motion blur.
- **Length:** usually 60-120 s, up to the 3-minute platform cap for a deeper topic. Never cut a
  step the viewer needs. Seconds = words ÷ 2.85.
- **Kit:** `tools/devweb-kit/` in rheos/secondunit-videos; its `README.md` (the standard, the
  commands, every "Rules learned on episode N"). The crew reads the kit README before planning.
- **Reference build:** `devweb-ep01-oner/` (the approved oner) and the latest finished episode.
- **House QA rules:** `~/.claude/skills/video-production/references/review-checklist.md`.
- **Look bible:** `tools/devweb-kit/LOOK.md` and `tools/devweb-kit/look/<topic>.md`, measured from
  references Robin picked (`workflows/look-bible.md`). The DP, the animators and the gap pass
  build to its numbers.
- Out of scope: making the topic list, public release (uploads are unlisted), Instagram.

## Outputs

`RUN_DIR` is `<worktree>/.bureau/runs/<yyyymmdd>-devweb-epNN/`; `PROJECT` is
`<worktree>/devweb-epNN-<slug>/`.

- `RUN_DIR/brief.md`, `pitch.md`, `suggested-topics.md`.
- Writers' room: every `write-short-script` output (`angle.md`, `versions/`, `coldread/`,
  `facts.md`, `script.json`).
- Pre-production: `storyboard.md`, `boards/NN-<beat>.svg`, `boards.html`, `silentread/NN.md`,
  `world-plan.md`, `camera.md`.
- Animatic: `PROJECT/` gray-box build, `animatic/sheet-NN.png`, `animatic/epNN-animatic-NN_720p.mp4`,
  `firstwatch/NN.md`, `notes/animatic-NN.md` (Robin's notes, verbatim).
- Production: `PROJECT/stations/*.js`, `PROJECT/cues.json`, `PROJECT/sfx/`, the finish in
  `PROJECT/renders/`, `supervisor/NN.md`, `notes/final-NN.md`.
- Wrap: `wrap.md`; rule additions to the crew mode files (bureau PR) and the kit README
  (secondunit-videos PR).
- `RUN_DIR/log.md`, `RUN_DIR/state.json`.

## The crew

Each role is a mode file on the existing cast. The spawn prompt names the mode file; the base
persona still applies, the mode file's prose is authoritative for the job.

| Role | Cast | Mode file |
|---|---|---|
| Director | The Conductor | this file |
| Showrunner | The Counselor | `agents/modes/crew-showrunner.md` |
| Writers' room | The Counselor, The Scribe, The Challenger | `workflows/write-short-script.md` |
| Storyboard artist | The Cleric | `agents/modes/crew-storyboard.md` |
| Production designer | The Cleric | `agents/modes/crew-production-design.md` |
| Director of photography | The Cleric | `agents/modes/crew-dp.md` |
| Gray-box builder | The Mage | `agents/modes/crew-graybox.md` |
| Animator (one per station) | The Mage | `agents/modes/crew-animator.md` |
| Editor | The Mage | `agents/modes/crew-editor.md` |
| Sound designer | The Mage | `agents/modes/crew-sound.md` |
| Silent read, first watch, script supervisor, look gap | The Challenger | `agents/critic/short-film.md` |
| Look analyst (series look bible) | The Cleric | `agents/modes/crew-look.md`, via `workflows/look-bible.md` |

Every crew mode file ends with a **Learned** section. Step 23 adds Robin's notes there, so the
crew carries them to the next episode.

## Done criteria

- Writers' room: latest cold read `CLEAR`, `facts.md` has no `FLAG`.
- Silent read `CLEAR`: a reader who saw only the boards told the mechanism and the failure back.
- Robin watched the animatic and said go (his words in `notes/animatic-NN.md`).
- Script supervisor round 1 on the finish: forensics, probe and flashcheck pass; nothing Robin
  approved in the animatic got worse; every animatic note is done. Round 2 (look gap) scored
  against `LOOK.md`, its fix list in front of Robin.
- Robin watched the 720p finish in session and said go; it is uploaded unlisted with a public
  title, the link reached his Telegram, and only the latest draft's renders remain.
- `wrap.md` lists where each of Robin's notes was filed.

## Edge cases

- **A note changes the words after the VO is recorded.** A new VO take costs credits and moves
  every word time. Prefer moving the picture (the "audio frozen" rule in the review checklist);
  re-record only for a note about the words themselves, and log the spend.
- **The cold reader or silent reader never clears:** stop after the second `HOLD` (Robin,
  2026-11-02, after ep 5's four cold reads: two reads that raise the same doubt won't be cleared by a
  third). Carry the open items into the animatic package; Robin decides at step 14.
- **First watch or supervisor still `HOLD` after two rounds:** go to Robin's gate anyway, with the
  open items listed first. He is the gate, not the critic.
- **Robin drops the topic at the animatic.** Stop. Log the VO spend; keep the run dir and the
  gray box on the branch; the next episode starts a new run.
- **A crew role spots a better topic.** It goes in `suggested-topics.md`, never in place of the
  episode being made. Step 23 appends them to the series folder for Robin.
- **Another session is rendering.** Heavy steps (VO, snapshots, renders, ffmpeg, sound) take
  `mkdir /Users/robin/tmp/devweb-heavy.lock` first and `rm -r` it after. Only one video build
  renders on this Mac at a time.
- **A board shows something the kit can't draw** (it needs a full 3D render, hands on Blink, a
  cut). The production designer replaces it with a kit-drawable picture of the same idea and
  says so in `world-plan.md`.

## Fallback behavior

- A spawn errors or returns no handoff: log it per `docs/conventions/failure-signatures.md`,
  re-spawn once, then `[CHECKPOINT]` to Robin. Never retry silently.
- `vo.py` or the render fails: read the log, fix the cause once, retry once; on a second failure,
  stop and report the exact error. Never re-run a paid VO call just to read its error.
- Every board, version, report and render is numbered and kept until the wrap; a bad revise
  never loses the previous one.

## Observability

`RUN_DIR/log.md` records each spawn, every verdict with its open items, each heavy-lock take and
release, every paid call with its cost, both of Robin's gates and the wrap. `state.json` holds the
phase and the current round of each loop. Spend goes to `PROJECT/docs/SPEND.md`.

## Steps

Spawn per `agents/orchestrator.md § How to spawn an agent`, model from `RUN_DIR/model-routing.json`.
Sequential unless a step says parallel.

### Phase 0: prep

0. **The Conductor** — set up the episode → `brief.md`, `state.json`, `log.md`
   Worktree `_wt-devweb-epNN` of rheos/secondunit-videos on branch `film/devweb-epNN`;
   `tools/devweb-kit/sync.sh devweb-epNN-<slug>`; allowlist the folder in `.gitignore`; resolve
   `model-routing.json`; write `brief.md` from the Inputs. If `tools/devweb-kit/LOOK.md` is
   missing, stop and ask Robin which references to measure, then run `look-bible` first. `ListAgents` to see which other
   sessions are building.

1. **The Counselor** (Showrunner, **strong**) — what the world is and why it animates → `pitch.md`, `suggested-topics.md`
   Mode file `agents/modes/crew-showrunner.md`. Reads `brief.md`, the article and the kit README.

### Phase 1: writers' room

2. **The Conductor** — run `write-short-script` steps 1-8 in this `RUN_DIR` → `script.json`
   Add `pitch.md` to the inputs of its steps 1 and 2. Its step 9 is not Robin's gate here: when
   the cold read is `CLEAR` and `facts.md` has no `FLAG`, write `script.json` and go on. Here its
   cold-read loop stops after the second `HOLD`, not the third (Edge cases).

### Phase 2: pre-production

3. **The Cleric** (Storyboard, **strong**) — one board per camera hold → `storyboard.md`, `boards/`, `boards.html`
   Mode file `agents/modes/crew-storyboard.md`. Reads the final script version, `pitch.md`, the
   kit README.

4. **The Conductor** — copy only `boards/*.svg` and `boards.html` into `silentread/input-NN/`
   (no narration, no picture lines, no pitch, no notes), with every `<!-- -->` comment stripped.

5. **The Challenger** (Silent read, **standard**) — tell the story from the boards alone → `silentread/NN.md`
   A FRESH spawn every round, slice `agents/critic/short-film.md § silent-read`.

6. **Gate** — `CLEAR`: go to step 7. `HOLD`: re-spawn the storyboard Cleric with the report
   (revise mode), then step 4 again. If a beat can't be shown without changing the narration,
   the Scribe revises it (`write-short-script` step 6) and the cold read runs again. Stop after
   two `HOLD`s per Edge cases.

7. **The Cleric** (Production design, **strong**) — the one world: stations, props, colour → `world-plan.md`
   Mode file `agents/modes/crew-production-design.md`. Reads the boards, `storyboard.md`,
   `pitch.md`, the kit README and the reference build.

8. **The Cleric** (DP, **strong**) — the camera, keyed to narration words → `camera.md`
   Mode file `agents/modes/crew-dp.md`. Reads `world-plan.md`, the boards, the final script.

### Phase 3: animatic

9. **The Conductor** — record the voice → `PROJECT/vo/voice.mp3`, `PROJECT/vo/words.js`
   Copy `script.json` to `PROJECT/vo/`. Heavy lock. `python3 -I tools/devweb-kit/vo/vo.py PROJECT`
   (paid ElevenLabs, one take; log the cost in `PROJECT/docs/SPEND.md`), then
   `<viralvision venv python> -I tools/devweb-kit/vo/tighten.py PROJECT` (full-stop gaps to 0.22 s,
   comma gaps to 0.15 s; Robin, 2026-11-03), then
   `<viralvision venv python> -I tools/devweb-kit/vo/align.py PROJECT`. Release the lock. This is
   the only spend before Robin's gate.

10. **The Mage** (Gray box, **strong**) — the world in boxes on the real word times → `PROJECT/`, `animatic/`
    Mode file `agents/modes/crew-graybox.md`. Reads `world-plan.md`, `camera.md`, `storyboard.md`,
    `vo/words.js`, the kit. Builds the station-per-file structure the animators fill later.

11. **The Conductor** — copy only the frames every 0.5 s (`animatic/frames-NN/`) and the
    word-timed transcript (from `vo/words.js`) into `firstwatch/input-NN/`.

12. **The Challenger** (First watch, **standard**) — watch it once, cold → `firstwatch/NN.md`
    A FRESH spawn every round, slice `agents/critic/short-film.md § first-watch`.

13. **Gate** — `CLEAR`: go to step 14. `HOLD`: route each item to its owner (camera to the DP Cleric,
    station layout to the production-design Cleric, timing or build to the gray-box Mage), re-render the
    animatic, then step 14 with what was fixed and what is still open. One first watch only: Robin is
    the next gate, and ep 5's second watch mostly re-found the first one's items.

14. **Gate** — Robin watches the animatic. `[CHECKPOINT]`
    Open `animatic/epNN-animatic-NN_720p.mp4` in ONE VLC window. Give him, in this order: what's
    still open (if anything), the path to `boards.html`, the script as a fenced block, the
    first-watch verdict in two lines, and the crew's suggested topics. Save his notes verbatim to
    `notes/animatic-NN.md`. On notes: route each to its owner, re-render, and show him again
    unless his notes say go on. On go: phase 4.

### Phase 4: production

15. **The Mage** (Animator, **strong**) — one spawn per station, in parallel → `PROJECT/stations/<station>.js`
    Mode file `agents/modes/crew-animator.md`. Each owns one station file and its time window,
    nothing else. Snapshots take the heavy lock in turn.

16. **The Mage** (Editor, **standard**) — cues on words, overlay holds, captions, the close → `PROJECT/cues.json`
    Mode file `agents/modes/crew-editor.md`. Runs after every station is in.

17. **The Mage** (Sound, **standard**) — effects on events, mixed under the voice → `PROJECT/sfx/`
    Mode file `agents/modes/crew-sound.md`. Heavy lock.

18. **The Conductor** — border check, then the finish → `PROJECT/renders/`
    First a 30 fps draft (`render -f 30`, about 7 min) and forensics on it; route every border and
    spike fail to its owner (camera edges to the DP) before the expensive render. Ep 5's first
    finish failed forensics 25 times on frame edges and cost a second 41-minute render.
    Heavy lock. `CINETIC=<cinetic clone>/skills/cinetic/scripts tools/devweb-kit/finish.sh PROJECT devweb-epNN`
    (120 fps, blended to 60 with motion blur, BT.709 tags, probe, forensics, flashcheck), then a
    720p review cut. Read the probe line before going on: a probe FAIL (ep 5's master had no audio)
    is fixed here, not handed to the supervisor. Remux a missing track onto the master with
    `-c:v copy` and no `-shortest` (it trims the length and probe fails on duration).

19. **The Challenger** (Script supervisor, **standard**) — the finish against the animatic, the rules and the look bible → `supervisor/NN.md`
    Round 1: slice `agents/critic/short-film.md § supervisor`. Reads the finish's qa files, contact
    sheets, the approved animatic, `notes/animatic-*.md`, the kit README and the review checklist.
    Round 2: a FRESH spawn, slice `§ look-gap`, which scores the finish against `LOOK.md` and lists
    fixes by owner.

20. **Gate** — Round 1 `CLEAR`: step 19 round 2. Round 1 `HOLD`: route each item to its owner by
    resuming that owner's own agent (SendMessage keeps its context, which is cheaper than a fresh
    spawn), patch-render the affected span where the kit allows, else re-run step 18; then
    round 2. After round 2, go to step 21 with its fix list, `CLEAR` or `HOLD`: Robin decides
    which of those get fixed.

21. **Gate** — Robin's final watch. `[CHECKPOINT]`
    Open the 720p cut in ONE VLC window. Save his notes to `notes/final-NN.md`. On notes: route
    by owner, back to the step that owns them. On go: `secondunit-worker/yt_upload.py` uploads it
    UNLISTED with the hook as the public title (no episode or draft label), "devweb, episode N"
    as the description's first line and at most plain `devweb.org`; the link goes to Robin's
    Telegram (if the script says "Telegram not sent", use `mcp__rheo__notify_robin`). Move earlier
    drafts' renders and the 120 fps raws to `~/.Trash`. Commit explicit paths only, push, open
    the episode PR.

### Phase 5: wrap

22. **The Conductor** — append `suggested-topics.md` to
    `~/Code/novadiem/assistant/ideas/devweb-shorts/crew-suggestions.md` (dated, episode number).

23. **The Conductor** — file Robin's notes with their owners → `wrap.md`
    For each note in `notes/`: name the owning role and turn it into one rule with the date and
    his words. Crew rules go into that mode file's **Learned** section (bureau branch + PR, per
    `CLAUDE.md § Canonical copy and drift`); kit bugs and build rules go into the kit README's
    "Rules learned on episode N" (secondunit-videos PR). A note that only fits this episode is
    listed in `wrap.md` and filed nowhere.
