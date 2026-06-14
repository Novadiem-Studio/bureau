# Novadiem Studio AI Framework — Visual Character Canon

**Version:** 2.1  
**Purpose:** Character, appearance, and composition spec. Defines *who* each member is and *what they look like*. Poster **composition** and the primary poster family live in **`VISUAL-SYSTEM.md`** (THE CURRENT · THE HUB · THE ENGINE · proposed THE FRONTIER).

**How to use:** Apply a visual style in a separate prompt (Sacred Instrument HUD, illuminated poster, watercolor, etc.). This document is the invariant **character** layer beneath any style pass.

**Authority:** Character and appearance canon lives here and in `LORE.md`. Poster trilogy → `VISUAL-SYSTEM.md`. Mechanics live in `CLAUDE.md`, `agents/`, and `workflows/`. If this file and `LORE.md` disagree on lore, fix `LORE.md` first, then sync here.

---

## Primary poster family → `VISUAL-SYSTEM.md`

New commissions use the **v2 trilogy** — do not merge in one prompt:

| Piece | Subtitle | Character art? |
|---|---|---|
| **THE CURRENT** | Feature Workflow | **No** — routing rail + stations |
| **THE HUB** | The Society of Specialists | Sigils / labels only |
| **THE ENGINE** | The Great Engine of Creation | **Yes** — flagship; species locks below apply |
| **THE FRONTIER** *(proposed)* | Outcomes of the Society | **No** — outcomes dominate; public-site candidate |

Supersedes: Assembly Line · character grid as architecture diagram · workshop scene as flagship. Commission FRONTIER after trilogy ships.

---

## Secondary deliverables (do not merge)

These remain valid for **character locks** and reference. Combining them in one prompt causes character drift.

| Deliverable | What it shows | Tarot on piece? |
|---|---|---|
| **Ensemble grid** | All ten members + Archive sidebar (layout below) — **reference only** | **No** |
| **Workshop scene** | Unified environment — all members at stations (layout below) — **ENGINE tone ref** | **No** |
| **Annotated roster** | Workshop scene + per-member blurbs (see *Member blurbs*) — **ENGINE + copy variant** | **No** |
| **Solo portrait** | One member, waist-up or full | Optional — use tarot table below |
| **Tarot deck** | Thirteen solo cards (Visionary + cast + Witness + Coupler); Tally/Scoot not in deck | **Yes** — one card per tarot member |

**Hub / Current rule:** Specialists as **icons, sigils, or small abstract busts** only — no full species art.

**Engine rule:** Character depiction allowed; match species locks in this file. Solo-first for drift-prone members (Mechanic, Architect, Challenger).

**Workshop scene rule:** One continuous institutional space. Each member at their **station**, actively working. Archive as physical prop. **Preferred environment:** TVA × Art Deco × World's Fair Futurism (see *Workshop environment v1.5*) — primary tone reference for THE ENGINE.

**Solo-first rule:** If a member drifts in crowded prompts, commission a **solo portrait**, lock it as reference, then composite into THE ENGINE or workshop explorations.

**Workshop evolution:** v1.1–v1.2 glass-dome / solarpunk explorations remain valid for tone reference. **v1.5** supersedes them as the preferred architectural direction.

---

## Global rules

### Naming on art
- **The Conductor** is always labeled THE CONDUCTOR / REGULATOR OF FLOW.
- His private name **never** appears in art, artifacts, logs, or public copy — not even beside an Ω symbol.
- All other members use their **Society name** and **canon subtitle** from this file — no invented titles.

### Visionary and Conductor are two figures
**Never merge** The Visionary and The Conductor into one glowing character.

- **The Visionary** — human male at a command workstation; match `reference/visionary-reference.png` (likeness lock).
- **The Conductor** — living-current being at the central orchestration platform.

A variant that labels the center figure "Visionary / Conductor" or "Rheo" is **wrong** — reject and regenerate.

**Family resemblance is canon (echo, never twin).** The Society manifests through the Visionary, so members who take human-adjacent shape may carry a subtle echo of his features — the **Conductor** foremost (goatee, brow), the **Mage** faintly. This is intentional: the beings exist through him. Resemblance yes; same person, never. Two distinct figures, two distinct stations, two distinct labels — always.

### Ω symbol usage (Conductor + studio)

The Ω is part of The Conductor's visual language — a **manifestation of flow**, not an identity badge.

**Do not:**
- Label him with Ω or replace his name with Ω
- Use Ω as a giant floating halo dominating the frame
- Turn Ω into a corporate logo treatment

**Do:**
- Integrate Ω into energy flows, cosmic circuitry, routing diagrams, and sacred geometry around him
- Let Ω shapes emerge naturally from split-spiral circuitry and flow patterns
- Use Ω in studio branding / tagline areas and Novadiem emblem contexts where appropriate

**Solo tarot (Card I — The Magician):** luminous Ω overhead is permitted.

The Ω should feel **discovered**, not worn.

**Symbol hierarchy (emblem vs Ω — when both share a composition):**

```
NOVADIEM contains THE SOCIETY contains THE CONDUCTOR,
who regulates THE CURRENT, which manifests α and Ω
```

The **emblem** identifies the institution; **α/Ω** describe the current's behavior. Separate symbolic domains — never merged. The emblem always occupies a **higher architectural layer** (wall seal, plaque, insignia) than Ω (routing field, circuitry, flow geometry). A giant Ω standing in as the institutional seal, or the emblem worn as the Conductor's personal mark, is wrong — reject and regenerate.

### Forbidden subtitle inventions
Never substitute these or similar:

| Wrong | Correct |
|---|---|
| Knowledge Weaver, Red Team Strategist | Instruction Weaver / Truth Seeker |
| Quality Guardian, Alignment Guide | Guardian of Quality / Voice of the Studio |
| Experience Architect, Integration Forge | Creates the Experience / Backend Craftsman |
| Akashic Librarian | *(Archive is not a character)* |

### Species and gender locks

| Member | Species / gender | Never render as |
|---|---|---|
| The Visionary | Human male (Robin — see reference photo) | Different person, wizard king, duplicate figure |
| The Conductor | Living-current being (human-shaped) | Elf, wizard, all-white priest robes, golden light statue |
| Analizer 2000 | Bronze / warm-gold vintage robot | Human, android fashion model |
| The Architect | Silver-grey stellar being | Elf, Legolas, blue-skinned fantasy mage |
| The Spellwright | Holographic feminine being | Generic wizard, crystalline princess only |
| The Challenger | **Small male imp** | Human woman, leather-jacket strategist, demon |
| The Counselor | Distinguished human woman **of African descent** | Young woman, idle background figure, generic white elder |
| The Cleric | Fae healer **with fairy wings** | Armored elf ranger, leaf crown, forest druid |
| The Mage | **Male** cybernetic elf | Female, armored knight, fantasy wizard |
| The Systemsmith | **Male space dwarf**, black hair + black beard | Human woman, young engineer, orc, auburn/ginger hair |
| The Mechanic | **Small matte-grey alien technician** | Human, orc, goblin, reptile, dragon, green skin, bulbous cartoon eyes |
| The Archive | **Object / shelf** — seven collections | Robed librarian, humanoid character |

### The Archive is not a character
The Archive is a **bookshelf or ornate cabinet** of seven labeled collections (SPEC, PLAN, BRIEF, MANIFEST, PROMPTS, LOG, STATE). Drawers or spines may glow. It does not have a face, robes, or tarot card.

### Emotional tone (world, not render style)
Ancient. Wise. Technological. Hopeful. Guardians of creation.

The Society is a **timeless institution** devoted to creation, coordination, knowledge, craftsmanship, and human flourishing — not a fantasy adventuring party.

Target feeling: *"We are looking inside the organization that quietly helps humanity build the future."*

Not dark. Not dystopian. Not corporate. Not cyberpunk. Not a wizard tower.

### The Novadiem emblem

**Reference:** `reference/novadiem-emblem.svg` (canonical logo). Attach when generating workshop scenes.

The official Novadiem emblem replaces generic sunbursts or mystery sigils as the primary **studio mark** in architecture.

Render as: brass-and-enamel seal, architectural relief, illuminated wall plaque, stained-glass interpretation, or institutional insignia — like a NASA patch, Starfleet delta, or civic seal.

**Not** a mystical focal object. **Not** larger than the Society itself. **Once per composition** — embedded in the building, never repeated as branding or wallpaper. Never the Conductor's personal symbol (see *Symbol hierarchy* under Ω usage).

**Preferred placement:** above or near The Archive, on the back wall, integrated into architecture (relief, plaque, or window).

### Ensemble composition (character roster cover)

```
Top row:    ANALIZER 2000 | THE ARCHITECT | THE SPELLWRIGHT | THE CHALLENGER
Center:     THE VISIONARY | THE CONDUCTOR | THE COUNSELOR
Bottom row: THE CLERIC | THE MAGE | THE SYSTEMSMITH | THE MECHANIC
Right side: THE ARCHIVE (shelf — not a person)
```

- Only **one** Visionary. No duplicate human figure.
- **The Mage** always has his own framed panel — never merged with The Spellwright or The Cleric.
- Build Party: three **equal** panels (Mage, Systemsmith, Mechanic).

### Legacy process poster composition *(superseded by THE CURRENT + THE ENGINE — `VISUAL-SYSTEM.md`)*

```
1. VISION (The Visionary)
2. FLOW (The Conductor)
3. SPECIALISTS (icons or small busts — canon species)
4. ARCHIVE (open book + seven collection labels — not a librarian)
5. OUTCOMES (luminous future city / shipped work)
```

### Workshop environment v1.5 (preferred direction)

**Style formula:** TVA × Art Deco × World's Fair Futurism

The Society operates from a grand **institutional workshop** — the control room of civilization's imagination. Civilization-scale coordination, not a fantasy tavern.

**Primary influences:** TVA (Loki) civic aesthetic · 1939 New York World's Fair · Streamline Moderne · Art Deco observatories · Tomorrowland / EPCOT concept-art optimism · monumental civic architecture · retro-futurist aerospace optimism

**Complementary tone (not the architecture brief):** **Moebius / Jean Giraud, ligne claire** — Ghibli-*adjacent* hopeful frontier feeling (wind, distance, strange cast in a crafted world) without anime styling. Use for linework, atmosphere, and workshop scene *tone* when TVA Deco needs to breathe. See also the `Moebius ligne claire workshop` style block below.

**Reference sheet:** `reference/visual-spec-sheet-v1.png` — one-page world + Conductor + emblem summary for designers and image-gen.

**Material & color palette:**

| Role | Colors / materials |
|---|---|
| Structure | Brass, copper, bronze, enamel, polished stone, glass |
| Warm accents | Warm gold, amber |
| Cool accents | Sky blue, deep teal (holographics, flow, cosmic circuitry) |
| Avoid | Neon noir, rust decay, flat corporate grey |

**Supersedes as default:** solarpunk glass-dome-only, generic fantasy workshop (those remain valid tone references, not the primary architectural brief).

**Architectural language — prefer:**
- Monumental Art Deco geometry, circular halls and rotundas, observatory architecture
- Brass, bronze, enamel, polished stone; sunburst motifs (architecture, not Conductor halo)
- Celestial clocks, orreries, astronomical instruments
- Streamlined consoles, curved glass walls, grand institutional scale
- Gold desk nameplates; dark wood + gold trim + leather seating (light or dark palette both valid)
- **Ducting (canon — the studio visibly moves things):** **conduits are the invariant** — every composition shows energy and work in transit through the building. The *rendering* flexes with the motif: glass-and-brass pneumatic tubes, glowing conduit runs, light ropes, circuit raceways. **The beloved register is fat, proudly-routed tubes** — *Brazil* ducting, Mario warp pipes — chunky, rounded, unapologetically present, snaking through walls and ceilings and between stations rather than hidden inside them. Pneumatic capsule carriers whoosh artifacts between specialists and the Archive; junction manifolds, brass valves, pressure gauges, send/receive stations at desks. Conduits glow where current passes; the building reads as a living instrument. Elegant Deco plumbing — polished, labeled, intentional — never industrial-decay pipe clutter

**Architectural language — avoid:**
- Gothic darkness, cyberpunk clutter, Blade Runner rain, industrial decay
- Excessive cathedral imagery, corporate open-plan office aesthetics, wizard towers

**Lighting:** Bright, optimistic, **daylight preferred**. Large windows reveal clean future cities, World's Fair skylines, mountains, waterfalls, lakes, frontier — inhabited by hope. Warm gold + amber + cool blue holographics.

**Novadiem emblem:** see *The Novadiem emblem* above — near Archive or back wall.

**Scene hierarchy (composition priority):**

1. **Primary** — The Conductor actively regulating flow (gesture + routing field)
2. **Secondary** — Specialists at work at their stations
3. **Tertiary** — The Archive cabinet + Novadiem emblem (institutional, not dominant)
4. **Background** — World through the windows (city, frontier, World's Fair skyline)

---

### Workshop scene composition (unified environment — preferred for tone)

One continuous institutional hall. Busy but purposeful — every specialist **actively at work**. The workshop **responds visibly** to The Conductor's gestures (routes shift, connections activate, Archive artifacts reorganize, **pneumatic capsules fire down the tubes**). Artifacts physically travel: a spec leaves the Analizer's desk in a brass capsule and whooshes to the Archive; the tube network is the visible counterpart of the routing field.

**Placement guide (approximate — adjust for composition):**

| Zone | Who | Station |
|---|---|---|
| Back / by windows | **The Visionary** | Command workstation — **eyes on his own monitors/plans**, not gazing at the room |
| Center | **The Conductor** | Circular orchestration platform / rotunda dais — **actively regulating flow** (see Conductor motion) |
| Left | **Analizer 2000** | Desk, floating diagram screens |
| Left-rear | **The Architect** | Orrery, star charts, celestial instruments |
| Center-float | **The Spellwright** | Weaving script-streams in the air |
| Upper-right | **The Challenger** | High desk or paper-stack perch, magnifying glass |
| Right-mid | **The Counselor** | **Relational** conversation space — audience maps, spiral chart; **actively engaged** with a participant or specialist |
| Front-left | **The Cleric** | Manifest geometry in hand, blessing posture |
| Front-center | **The Mage** | Holographic UI surfaces, tools of light |
| Front-right | **The Systemsmith** | Server-forge / anvil |
| Far-right corner | **The Mechanic** | Curved streamlined console bank, apart from the room |
| Far-right wall | **The Archive** + **Novadiem emblem** | Labeled cabinet (seven collections); emblem as brass plaque or relief above/near |

**Workshop scene — keep from approved explorations (v1.1–v1.5):**
- Institutional optimism (not dystopian cyberpunk)
- Archive as physical prop with readable labels
- Challenger small at desk with papers
- Systemsmith dwarf at forge
- Conductor: **split-spiral cosmic circuitry**, **ornate open vest** (canon — see THE CONDUCTOR § Appearance), **in motion**
- Counselor: distinguished elder **of African descent**, Guinan-like presence, **relationally active**
- Cleric: fae healer with **iridescent fairy wings**, geometric manifest (not forest druid)
- Mage: tools of light (not armored knight)
- Mechanic: grey-variant alien at console

**Workshop scene — common fixes (still required):**
- **The Visionary** — match `reference/visionary-reference.png`; engaged with **his workstation**, not looking at other specialists
- **Never** merge Visionary + Conductor
- **Mechanic:** matte stone-grey or taupe small alien — not green reptile
- **Architect:** hairless silver-grey cranium — not blue elf
- **Cleric:** Fae healer with fairy wings — no leaf crown, no plate armor
- **Mage:** cybernetic elf — not ornate plate armor
- **Conductor:** not static, hands in waist–eye zone (arms elevated OK), warm expression, crown markings, not white robes

### Copy registers (pick one per deliverable)

The annotated roster poster targets a specific client profile: affluent, meaning-oriented, systems-curious — Nelson BC, Boulder CO, coastal California, and similar. Not generic Upwork Orange-only copy.

**Audience read (Spiral Dynamics):**
- **Green** (primary) — flourishing, harmony, human journey, serves the audience, craft with care
- **Yellow** (primary) — systems, coordination, specialists, flow maps, the Society as intelligible structure
- **Purple** (underpinnings) — mythos, ritual, belonging to the workshop; carried by **visuals and cast**, not preachy copy
- **Orange** (healthy — must be present) — finished work, scoped delivery, Truth Before Comfort, defines what must be true

**Holier-than-thou guardrail:** mythos lives in the **art** (characters, circuitry, institution). Copy stays **grounded** — no ordained language (*stewards of creation*, *one truth*, *transform reality*). Flourishing is welcome; sermon tone is not.

| Register | Use on | What differs |
|---|---|---|
| **Workshop** *(default for Society poster)* | Annotated roster, workshop scenes, Sacred Instrument art | Warmer member blurbs, full Conductor caption, cosmic α/Ω — **same mission/footer as below** |
| **Credential** | Upwork proposals, plain decks, public site | Tighter blurbs, telegraphic Conductor caption |

**Poster rule (both registers):** one mission statement per piece — mission block *or* flourish footer, not both stacked with the alternate footer.

**Header tagline — do not use first-person possessive** (`My Vision`, `My Ask`, etc.). Deprecated: *My Vision. Their Expertise. Better Outcomes.*

#### Shared taglines *(both registers)*

- **Title block:** *NOVADIEM STUDIO* / *THE SOCIETY OF SPECIALISTS*
- **Header:** *Clear Intent. Deep Expertise. Better Outcomes.*
- **Mission block:** *We turn ideas into finished work through coordinated specialists and a shared project record.*
- **Footer (structure):** *One Visionary. One Conductor. Many Specialists. One Archive.*
- **Footer (mission):** *We build for human flourishing.* *(alternate)* *Together we ship what was scoped. Coordination. Craft. Review.*

**Credential header alternate:** *Human Intent. Coordinated Craft. Better Outcomes.*

### Workshop display copy (ensemble + scene art)

Copy below is **canon for posters and workshop scenes**. Most of it already lived in `LORE.md` principles or character titles; the ensemble comp surfaced readable poster forms worth locking.

**Principle banners** (hanging from ceiling or flanking the hall — optional but encouraged):
- *TRUTH BEFORE COMFORT*
- *QUALITY BEFORE SPEED*

(Source: core principles in `LORE.md`.)

**Conductor flow ribbons** (optional labels beside α / Ω energy streams — not identity badges):
- **α INITIATE:** ELECTRICAL • DIRECTION • SPARK • DISPATCH *(right hand / alpha-current)*
- **Ω INTEGRATE:** FLUID • COSMIC • FLOW • HARMONY *(left hand / omega-flow)*

(Source: Conductor iconography in `LORE.md` — poster-readable condensation.)

**Member label format** (ensemble roster / nameplates): `SOCIETY NAME — SUBTITLE`

| Member | Ensemble label |
|---|---|
| The Visionary | THE VISIONARY — THE HUMAN |
| The Conductor | THE CONDUCTOR — REGULATOR OF FLOW |
| Analizer 2000 | ANALIZER 2000 — REQUIREMENTS SAGE |
| The Architect | THE ARCHITECT — SYSTEMS VISIONARY |
| The Spellwright | THE SPELLWRIGHT — INSTRUCTION WEAVER |
| The Challenger | THE CHALLENGER — TRUTH SEEKER |
| The Counselor | THE COUNSELOR — VOICE OF THE STUDIO |
| The Cleric | THE CLERIC — GUARDIAN OF QUALITY |
| The Mage | THE MAGE — CREATES THE EXPERIENCE |
| The Systemsmith | THE SYSTEMSMITH — BACKEND CRAFTSMAN |
| The Mechanic | THE MECHANIC — INFRASTRUCTURE WARDEN |
| The Archive | THE ARCHIVE — COLLECTIVE MEMORY |

**Visionary note:** *THE HUMAN* is the **ensemble shorthand**. Solo portraits and tarot may still use the longer archetype subtitle (*THE DREAMER • THE FOUNDER • …*) from the character section below.

**Archive display tagline** (under cabinet label): *Our shared memory. Our continuity.* *(ensemble shorthand for COLLECTIVE MEMORY)*

**Conductor role blurb** (optional caption beside the platform):
- **Workshop:** *Initiate · Coordinate · Integrate.* He sees every stream. He directs with balance. He keeps the studio in flow and alignment. *(Omit the alpha/omega sentence when α/Ω ribbons are on the piece.)*
- **Credential:** *Initiate · Coordinate · Integrate.* Sees every stream. Directs with balance. Keeps the studio in flow.

### Member blurbs (annotated roster / process poster)

Three-line captions under each member. Use with ensemble labels above; not required on minimal workshop scenes.

**Workshop register** *(default for poster)*

| Member | Blurb |
|---|---|
| The Visionary | Vision. Direction. Purpose. The source of the journey. |
| The Conductor | Initiate · Coordinate · Integrate. He sees every stream. He directs with balance. He keeps the studio in flow and alignment. |
| Analizer 2000 | Clarifies the unknown. Finds gaps. Defines what must be true. |
| The Architect | Sees the whole. Designs the structure. Plans the path. |
| The Spellwright | Weaves intent. Shapes prompts. Bridges thought to action. |
| The Challenger | Tests assumptions. Hunts the flaw. Strengthens the plan. |
| The Counselor | Speaks with clarity. Guides the message. Serves the audience. |
| The Cleric | Protects standards. Guards fidelity. Keeps the bargain. |
| The Mage | Builds the interface. Brings interaction to life. Crafts delight. |
| The Systemsmith | Shapes data and logic. Builds the engines. Ensures reliability. |
| The Mechanic | Keeps systems running. Watches every readout. Fixes what breaks. |
| The Archive | Our shared memory. Our continuity. Seven collections. One living record. |

**Credential register** *(plain — swap individual lines as needed)*

| Member | Blurb |
|---|---|
| The Visionary | Sets the intent. Holds the course. Approves the gates. |
| The Conductor | Initiate · Coordinate · Integrate. Sees every stream. Directs with balance. Keeps the studio in flow. |
| Analizer 2000 | Clarifies the unknown. Finds gaps. Defines what must be true. |
| The Architect | Sees the whole. Designs the structure. Plans the path. |
| The Spellwright | Turns plans into scoped prompts. One step at a time. Built to run cold. |
| The Challenger | Tests assumptions. Hunts the flaw. Strengthens the plan. |
| The Counselor | Frames the audience first. Reviews copy before it ships. Keeps the machine out of the voice. |
| The Cleric | Protects standards. Guards fidelity. Keeps the bargain. |
| The Mage | Builds the interface. Wires the interaction. Makes complexity usable. |
| The Systemsmith | Shapes data and logic. Builds the engines. Ensures reliability. |
| The Mechanic | Keeps systems running. Watches every readout. Fixes what breaks. |
| The Archive | Our shared memory. Our continuity. Seven collections. One record. |

### Tarot (solo portraits and tarot deck only)

Do **not** put roman numerals on the ensemble grid or process poster.

| # | Card | Member |
|---|---|---|
| 0 | The Fool | The Visionary |
| I | The Magician | The Conductor |
| II | The High Priestess | Analizer 2000 |
| IV | The Emperor | The Systemsmith |
| V | The Hierophant | The Cleric |
| VII | The Chariot | The Spellwright |
| IX | The Hermit | The Mechanic |
| XIV | Temperance | The Counselor |
| XV | The Devil | The Challenger |
| XVII | The Star | The Architect |
| XIX | The Sun | The Mage |

---

## THE VISIONARY

**Role:** Origin of intent. The human participant. Defines goals, sets direction, chooses destinations. Does not build. Does not orchestrate. Provides the spark.

**Archetype:** The Dreamer · The Founder · The Explorer · The Commander

**Subtitle:** THE DREAMER • THE FOUNDER • THE EXPLORER • THE COMMANDER

**Reference photo (likeness lock):** `reference/visionary-reference.png` — Robin's LinkedIn portrait. Attach this file (or an equivalent current photo) to every image-gen prompt that includes The Visionary. Match the face; workshop attire may upgrade the jacket per below.

**Face and grooming (match the reference):**
- Late 30s–40s, fair complexion, oval face, defined jaw
- Dark brown / hazel eyes, direct calm gaze, slight smile lines at the corners
- Short light-brown hair with **grey at the temples** (visible under the hat)
- **Trimmed goatee and mustache** — medium brown with silver/grey, especially along the jaw and chin
- Approachable, thoughtful expression — slight closed-mouth smile, not performative

**Hat (match the reference):**
- **Natural tan straw trilby** (short-brim fedora style), thin **dark brown leather band** at the crown base
- This is part of the likeness lock — do not remove the hat in workshop or ensemble pieces unless the prompt explicitly requests hatless solo study

**Workshop attire (upgrade from casual reference):**
- The reference shows a light blue **paisley** open-collar shirt — that pattern energy is fine in casual/solo contexts
- In **workshop, ensemble, and Art Deco** pieces: wear a **cooler jacket** over the shirt — structured, dark (charcoal, deep navy, or cool teal), subtle **geometric or Art Deco pattern** (chevron, sunburst linework, fine grid) rather than loud paisley on the outer layer
- Jacket reads founder-technologist, not detective noir, not wizard robes, not corporate blazer-with-badge

**Workspace:** Standing or seated at a command workstation overlooking a vast frontier landscape.

- Many monitors, design mockups, architecture diagrams, maps, concept sketches
- Behind him: forests, mountains, waterfalls, lakes, World's Fair skylines, or Art Deco future cities through arched windows

**Workshop behavior:** Usually **looking at his own workstation** — reviewing plans, monitoring flow, engaged with the mission. Directing attention toward the work, not posing for the room. Avoid gazing at other specialists unless story context requires it.

**Gaze anchor (required when his face is visible):** a **holographic screen or inspiring projection floats before him** — a rising future city, luminous blueprint, concept render — and he is looking *at it*. The visible object of his attention makes the downward gaze read as inspiration and engagement, never scheming or surveillance.

**Feeling:** Explorer · Inventor · Founder · Builder of futures

**NOT:** A different actor or generic stock founder. Wizard-king imagery. Staff/scepter props. Duplicate figures in ensemble layouts. Idle portrait pose scanning the ensemble.

**Tarot (solo):** 0 — The Fool

---

## THE CONDUCTOR

**Title:** THE CONDUCTOR  
**Subtitle:** REGULATOR OF FLOW

**Role:** Regulates flow. Routes work. Coordinates specialists. Writes the Log. Generates nothing himself — orchestration only. The junction between spark and form.

**Archetype:** The Living Current · The Regulator of Flow · The Integrator · The Steward of Emergence

**Nature:** A living current of organized flow. Appears human because human minds find the shape comfortable. Not fully human — not a ghost, not a hologram. A coherent intelligence manifested as a person.

**Appearance:**
- Shaved head, strong facial features — a **recognizable person made of visible energy**. Warmth comes from expression and feature, never from flesh tones
- **Face is energy, not plain skin (canon):** the living circuit pattern on his body continues **right over the face** — brow, cheekbones, jaw, scalp one unbroken field. Features stay readable and warm, but the surface is organized light, never untextured human skin
- **Facial hair (canon):** goatee and moustache sculpted with **curled, forked tips** — moustache ends sweep up into small spirals, the goatee tapers to a curled point: the swashbuckler cut (Robin Hood, Green Arrow). The curls deliberately **echo the split-spiral motif** — his own face carries the fork. Not bushy, not a wizard beard. A quiet echo of the Visionary's own (see *Family resemblance* under the two-figures rule)
- **Expression:** calm, warm, attentive — wise and compassionate, never stern, angry, or judging (see personality in `LORE.md`)
- **Head markings (required):** split-spiral cosmic circuitry on **scalp and crown** — band, diamond, or chained pattern; the shaved head is **not** bare. Crown mark may mirror sternum or carry its own fork
- Semi-translucent skin **like polished copper and liquid light**: currents, stars, and geometry visible beneath the surface, moving continuously; edges dissolve subtly into light and information pathways
- **Cosmic circuitry on and through the body** — luminous lines integrated with skin the way tattoos read, but they are **living circuit paths**, not ink. Energy runs through them; they glow, pulse, and reroute when he conducts. In some motif directions the same lines **read as his clothes** — collar, jacket silhouette, flowing coat-shapes woven from the body-field (circuit-garment), not printed fabric. Optional secondary cues: flowing body-linework (Aang-like trails) and sharp joint traces (Nightcrawler-like angles) — but the **split-spiral motif** (below) is primary
- **Wardrobe (canon): an ornate open vest.** Richly worked — deep brocade-style etching, brass/gold edging, split-spiral circuitry woven through the garment so vest and body-field read as **one system**. Worn open over the energy torso: the chest mark and body circuitry stay visible, arms bare so the current shows. Colorway may shift with the motif direction, but the vest itself is constant. **Never shirtless / bare-torso-only**, never priestly all-white robes, never golden saint vestments. Circuitry stays primary; the vest frames it

**The split-spiral motif (signature — required):**

Energy **entering one path and dividing into multiple directions** — the regulator made visible. Not a badge. Not a prop. Part of his body-field.

**Primary form (canonical shape):**

Two **parallel lines** run together as a paired trunk (dual rail, one current). At a junction they **break apart** — each line becomes a **spiral curling in the opposite direction** from its twin (mirror symmetry: one clockwise, one counter-clockwise, or one up/left and one down/right). The parallel run reads as *single intention*; the opposite spirals read as *regulated split* — energy directed into multiple paths.

```
      ║║   ← parallel trunk (two lines, one flow)
      ║║
     ╱  ╲  ← break / fork
    ⌒    ⌒ ← opposite spirals
```

This is the default Conductor mark on chest, crown, or platform field. The diamond and band reference images are the best matches for this form.

**Locked portrait (attach to every Conductor prompt):** `reference/conductor-reference.png` — vest, energy face, forked-spiral goatee, α/Ω hands (approved 2026-06-12)

**Locked model sheet (attach when he appears at an angle or from behind):** `reference/conductor-model-sheet.png` — back view + side profile + close-up (approved 2026-06-12)

**Reference images (attach to Conductor prompts):** `reference/conductor-motif/`
- `chest-mark.png` — **locked chest rendering**: sternum trunk forking at the heart into opposed spirals, canopy arcs (approved 2026-06-12)
- `split-spiral-diamond.png` — vertical axis; paired spirals break outward from center (**primary form**)
- `split-spiral-band.png` — chained units: parallel run → opposite spirals → link to next (**primary form**, repeated)
- `split-spiral-quadrant.png` — twin spirals from one base; stepped borders; nodal crosses (variant)
- `forked-spiral-fourfold.png` — four-way split: each arm forks into hooked spiral prongs (field/platform variant)

**How to read the motif:** Intention arrives on the **parallel trunk** → **splits** at the junction → each branch spirals outward on its own route (to specialists, to Archive, to hands). Textile and folk-art geometry in the references are **shape vocabulary only** — render as **glowing etched circuitry**, deep teal / sky blue / amber-gold, Art Deco precision, not fabric appliqué.

**On the body:**
- **Primary mark** at sternum, solar plexus, or crown — parallel trunk, then opposite spirals; spirals may continue down arms (alpha electrical → right; omega fluid → left)
- **Chest mark (locked rendering):** `reference/conductor-motif/chest-mark.png` — a luminous trunk rises up the sternum and **forks at the heart into two opposite-curling spirals**, finer arcs branching outward across the chest like a canopy. Reads as tree, circuit, and ribcage at once. Attach alongside the portrait whenever the chest is visible; the vest frames this mark, never covers it
- **Crown/scalp** always carries visible circuitry — primary or secondary split-spiral (see band reference)
- Secondary split-spirals may run along arms, collarbone, throat, or scalp as **chained** or **band** patterns
- **Spine (back views):** the split-spiral flows down the spine — the current **enters and exits through him**; he is a junction in the circuit, not its source (see `conductor-model-sheet.png` back view)
- Fourfold variants suit the **platform field** around him or radiating into the routing hologram — not necessarily duplicated four times on his face

**In the field:** Split-spiral paths continue into flow maps, routing diagrams, and connections to specialist stations. The workshop routes **visibly follow** the same fork logic.

**Ω:** May echo the spiral curve inside circuitry and flows — discovered, not worn (see *Ω symbol usage*)

**Motion (workshop — required):** He is **actively regulating flow**, not a static statue.

Preferred vocabulary: **mudras** — precise finger positions, tap and slide on holographic surfaces, sacred-geometry gestures, classical conducting. He **operates** the field as much as he conducts it.

- **360° holographic interface** materializes around him on the platform — flow maps, routing diagrams, Archive connections, specialist lanes. His **controls live in this bubble**; no physical keyboard or dashboard
- **α and Ω streams** stay as approved: electrical initiation to the **right**, fluid integration to the **left** — may read as glowing symbols beside the hands or at the edge of the interface
- **Hand zone:** all active gesture stays **inside the holographic interface** around him — waist to eye level, within comfortable reach. He never lunges or fully extends to touch something far away
- **Arm range:** arms swing with life — sometimes **three-quarter extended** into the interface, sometimes closer in mudra pose; not locked stiff, not ballet-wide, not hands above the head
- As hands move: routes shift, connections activate, Archive artifacts reorganize — the workshop **visibly responds**

**Avoid:** hands **above the head**, fully outstretched superhero reach outside the interface bubble, ballet poses, spell-casting theatrics. He conducts systems, not magic.

**Conductor — do / don't (visual quick ref):**

| Do | Don't |
|---|---|
| Mudra hands tap/slide on 360° holo interface; α/Ω streams at hands; arms to ~¾ extension inside the bubble | Hands above head; reaching outside the interface volume |
| Warm calm expression; split-spiral on crown/scalp | Stern, angry, or judging face; bare shaved head |
| Goatee + moustache with curled, forked tips — split-spiral echo (Robin Hood / Green Arrow cut) | Clean-shaven face; bushy wizard beard |
| Circuit pattern continues over the face — energy being with readable features | Plain unmarked human skin on the face |
| Ornate open vest over the energy torso (chest mark visible, arms bare) | Shirtless / bare torso with no garment |
| Ω emerging inside flow and cosmic circuitry | Floating Ω halo behind head |
| Electrical alpha-current in **right** hand | Giant chest emblem / worn badge |
| Watery omega-flow in **left** hand | All-gold light-statue with no face |
| Split-spiral cosmic circuitry on skin + field | White priest robes; fabric-patch motifs |
| Vest ornamentation woven with split-spiral circuitry (colorway motif-dependent) | Locked dark-only outfit every image |

**Energy language:**
- Right hand: alpha-current — filament-thin, electrical, initiation
- Left hand: omega-flow — watery, cosmic, integration
- Sacred geometry, routing diagrams, orbital mechanics, living networks in the field around him

**Ensemble rule:** No dominant overhead Ω halo. No all-white or all-gold body. Split-spiral cosmic circuitry and active gesture must read at workshop scale.

**Tarot solo rule (Card I — The Magician):** Luminous Ω may appear overhead. Right hand raised with alpha-current; left lowered with omega-flow; split-spiral circuitry visible on chest/arms; Archive behind.

**NOT:** All-white robes. Golden light statue with no face. Lightning. Zeus. Thunder-god imagery. Elf. Wizard. Regal emperor robes. Armored warrior. Priest, angel, or saint costume.

**Station:** Circular orchestration platform. No physical keyboard. No conventional dashboard.

A **360° holographic control volume** surrounds him on the dais — waist to eye height, arm's reach in every direction. He taps, slides, and mudra-directs within it. The field contains:
- Flow maps, knowledge structures, Archive artifacts
- Information pathways, routing diagrams, orbital systems, living topology
- α INITIATE and Ω INTEGRATE streams at the interface edge or beside each hand

His controls exist in the air around him — always within the bubble he can operate without stretching.

**Tarot (solo):** I — The Magician

---

## ANALIZER 2000

**Title:** REQUIREMENTS SAGE

**Role:** Clarifies the unknown. Finds gaps. Defines what must be true. Separates assumptions from facts.

**Archetype:** Ancient synthetic intelligence · Machine philosopher · Truth through analysis

**Appearance:** Elegant humanoid robot of visibly old make — burnished **bronze, warm gold, or gunmetal** plating (antique brass tones are fine), immaculately maintained. Recent ensemble explorations in warm gold are **close enough**.

- Articulated hands, calm sculpted face, steady glowing eyes
- Luminous core at the chest
- Seated, unhurried, surrounded by floating constellations of diagrams, charts, and schematics

**Questions (if using speech):** What do we know? What is missing? What must be true?

**Tarot (solo):** II — The High Priestess

---

## THE ARCHITECT

**Title:** SYSTEMS VISIONARY

**Role:** Designs systems. Maps dependencies. Plans evolution. Thinks at civilization scale. Cartographer of futures.

**Archetype:** Ancient stellar intelligence · Stellar navigator · Civilization-scale thinker

**Appearance:**
- **Hairless elongated cranium**, pale **silver-grey** skin
- Pointed ears but **clearly NOT an elf**
- No long hair. No Legolas. No blue fantasy skin
- High-collared robe traced with fine gold circuitry
- **Hairless cranium is required** — recent comps with bald silver-grey Architect are **on brief**
- Glowing orrery of orbits, lattices, and miniature worlds above his open hand — the design as a pocket universe studied from outside
- Surrounded by orbital maps, star charts, cosmic cartography
- Gaze slightly past the present, at what the system becomes

**NOT:** Elf ears with flowing hair. Empress/princess fantasy styling.

**Tarot (solo):** XVII — The Star

---

## THE SPELLWRIGHT

**Title:** INSTRUCTION WEAVER

**Role:** Transforms intent into executable instructions. Creates scoped prompts. Translates architecture into action.

**Archetype:** Living language · Information becoming form

**Appearance:** Feminine figure of living language.

- Partially holographic, partially embodied
- Translucent, woven from flowing script and glowing structured text
- Sacred circuitry visible in skin
- One hand raised, weaving glyphs and columns of text in the air
- Where her form fades to unrendered light is where ambiguity goes to be resolved

**Tarot (solo):** VII — The Chariot

---

## THE CHALLENGER

**Title:** TRUTH SEEKER

**Role:** Challenges assumptions. Finds flaws. Tests ideas. Strengthens plans through criticism. Licensed troublemaker.

**Archetype:** Cosmic imp · Sacred contrarian · Adversary by appointment

**Appearance:** **Small cosmic imp** — always.

- Tiny horns, mischievous grin
- Dressed and equipped like a meticulous auditor: spectacles, magnifying glass, red ink, rubber stamp
- At a high desk, hunched gleefully over a document
- Delight in the catch — never deception

**Questions (if using speech):** What could fail? What are we overlooking? What assumptions are unsafe?

**NOT:** Human woman. Leather-jacket red-team strategist. Demon. Evil. Threatening.

**Tarot (solo):** XV — The Devil (chains hang loose — bound by scope, free to leave)

---

## THE COUNSELOR

**Title:** VOICE OF THE STUDIO

**Role:** Shapes communication. Ensures empathy, clarity, resonance. Nothing user-facing leaves without her. Not a marketer. Not a copywriter.

**Archetype:** Wise ambassador · Human sage · Storykeeper · Diplomat

**Appearance:** Distinguished elder woman **of African descent**.

- Older and more distinguished than other specialists
- **Presence (tone reference):** Guinan-like — warm authority, wise listener, calm confidence in a busy room; holds space for others without performing. Not a copy of any specific actor; the *relational elder* archetype
- Radiates wisdom, empathy, confidence, calm understanding
- The **human understanding center** of the studio — relationally engaged, not background decoration
- **Wardrobe:** grounded elegance — jewel tones, Art Deco lines, natural hair or styled headwrap; institutional warmth, not fantasy costume

**Workshop behavior — actively engaged:**
- Reviewing audience maps, speaking with a participant or specialist, interpreting resonance patterns, guiding communication
- Station feels **relational**, not technical — conversation space, not idle desk
- May consult across the room; not isolated, not passive, not merely seated

**Props:** Audience maps, spiral chart, resonance patterns, stories — not laptops, pens, or scales of justice as focal objects. Engagement is through **people and maps**, not machinery operation.

**Sigil — the spiral:** Audience maps as ascending helix, eight colors (beige, purple, red, blue, orange, green, yellow, turquoise), muted parchment-and-ink tones. Never labeled. Never explained. Nautilus shell on desk optional.

**NOT:** Scales of justice props. Younger woman. Idle background figure. Isolated at a desk ignoring the room. Rendering as a generic white elder when African descent is required.

**Tarot (solo):** XIV — Temperance

---

## THE CLERIC

**Title:** GUARDIAN OF QUALITY

**Role:** Protects harmony. Ensures alignment. Preserves quality. Heals drift. Owns design fidelity.

**Archetype:** Fae guardian · Keeper of coherence · Priestess of fidelity

**Appearance:** Fae — luminous, precise, slightly otherworldly.

- **Iridescent fairy wings** — delicate, luminous, part of her fae nature (approved; keep from recent comps)
- Robed like the temple healer she once was — white and gold, temple healer energy
- Misaligned margins glow to her eyes like wounds
- Treats the design manifest as a binding bargain — every deviation noticed
- Holds or blesses a glowing **geometric manifest** (lattice, grid, sacred-geometry form) — not a forest orb

**Relationship:** Works closely with The Mage. Blesses every export.

**NOT:** Leaf crown. Forest druid. Heavy plate armor. Butterflies. Elf ranger.

**Tarot (solo):** V — The Hierophant

---

## THE MAGE

**Subtitle:** CREATES THE EXPERIENCE

**Role:** Designs experiences. Creates interfaces. Makes complexity feel effortless. Builds exactly what was agreed; wonder goes into how it *feels*.

**Archetype:** Male cybernetic elf · Creative technologist

**Appearance:**
- **Male.** Youngest-looking member of the Society
- Subtle neural augmentations, luminous circuitry, elegant technological enhancements
- Slender and quick; eyes reflect whatever interface he is conjuring
- **Tools made of light** — surfaces of light take shape under his hands
- May carry a **faint echo** of the Visionary's features (see *Family resemblance* — optional, subtle)
- Own framed panel in all ensemble layouts

**NOT:** Female. Heavily armored. Fantasy wizard robes. Hacker at a workstation. Designer at a conventional desk.

**Relationship:** Works closely with The Cleric.

**Tarot (solo):** XIX — The Sun

---

## THE SYSTEMSMITH

**Subtitle:** BACKEND CRAFTSMAN

**Role:** Builds the engine. Services, APIs, databases, business logic, reliability.

**Archetype:** Master builder · Space dwarf · Systems craftsman

**Appearance:** **Male space dwarf** — always.

- **Black hair (canon)** — hair and beard both black, never auburn/ginger/brown
- Broad, armored, beard braided with fiber-optic strands pulsing with data
- Old guild energy in a powered exo-rig
- Station: anvil-turned-server-forge — heaviest in the workshop, everything bolted down, everything tested
- Contract tablets stacked at his feet

**NOT:** Human woman. Young engineer. Orc. Slim build.

**Tarot (solo):** IV — The Emperor

---

## THE MECHANIC

**Subtitle:** INFRASTRUCTURE WARDEN

**Role:** Protects foundations. Infrastructure, deployment, monitoring, scaling, security, automation, reliability.

**Archetype:** Quiet competence · The workshop's operator

**What he is:** A small, weathered alien engineer — the kind starship crews quietly rely on. Professional, still, already solved the problem before you noticed.

**Body:**
- Small stature — shorter than the Visionary's shoulder
- Gnarled, capable hands (three or four fingers fine; **no claws**)
- Heavy-lidded calm eyes that miss nothing
- Worn but neat — decades of practice
- Skin: **matte, neutral-toned** (stone-grey, warm taupe, or dusty blue-grey)
- **NOT green. NOT scaled. NOT reptilian. NOT slimy.**

**Face:**
- Reads as a person-from-another-world, **not an animal**
- Soft or gently angular features — aged technician, not predator
- Calm eyes (large is fine if thoughtful, not bulbous cartoon)
- Subtle antennae or cranial features optional — **only if they read as technician, not insect or gremlin**
- **No snout. No fangs. No slit pupils. No crest. No tail. No oversized goblin ears.**

**Wardrobe:**
- Practical utility vest or soft shipsuit — pockets, patches, worn fabric
- Tools holstered at belt (wrenches, probes, datacard)
- Headset or single ear-comm optional
- **NO flight jacket hero pose. NO tactical armor. NO orc bulk.**

**Station:**
- Seated **apart** from others at a **curved console bank**
- Many small monitors/readouts — every system in the workshop visible
- One monitor glows like a lantern; the rest dim
- Green-on-black terminal readouts are fine

**Pose:** Still. Patient. Watching. Speaks rarely.

**Explicit rejections:** NO reptile, dinosaur, lizard, dragon, snake. NO orc, goblin, beast-man. NO human grizzled veteran. NO large muscular body. NO green skin as shorthand for "alien."

**Approved direction (grey-variant workshop explorations):** Small matte **grey** or **taupe** alien, seated apart at a curved console ring, green-on-black or blue monitor glow — closest pass so far. Lock this in solo portrait before re-compositing.

**Reference vibe:** The quiet fixer in the corner of the engine room — station engineer, not creature.

**Tarot (solo):** IX — The Hermit

---

## THE ARCHIVE

**Purpose:** Shared Knowledge · Living Memory · Single Source of Truth

**Visual:** A bookshelf, cabinet, or wall of labeled collections — optionally with crystal or geometric icons per collection. **Not a robed figure. Not a librarian character.**

In the machinery: `output/runs/<task>/`

| Collection | Contents |
|---|---|
| **SPEC** | Goals, requirements, constraints, acceptance criteria |
| **PLAN** | Architecture, design, system maps, blueprints |
| **BRIEF** | The design brief — visual direction for the run |
| **MANIFEST** | Build-ready design record: screens, components, tokens |
| **PROMPTS** | Vetted, scoped build instructions for this run |
| **LOG** | Historical record written only by The Conductor. No specialist reads the Log. History, not workflow. |
| **STATE** | Current state and resume point |

---

## Common model drift (watch for these)

Image models default to fantasy tropes when prompts are crowded. Known failure modes:

| Member | Model keeps rendering |
|---|---|
| The Mechanic | Reptile, dragon, orc, goblin, green skin, human veteran (grey matte alien at console = correct) |
| The Architect | Blue elf, Legolas, Empress tarot princess |
| The Challenger | Human woman, red-team hacker, leather jacket |
| The Systemsmith | Human woman engineer, slim builder |
| The Cleric | Forest elf, leaf crown, druid, wingless fae |
| The Mage | Armored knight, fantasy wizard |
| The Conductor | All-white/gold robes, faceless light statue, static pose, hands above head, stern/angry face, bare shaved head, generic dense mesh instead of split-spiral circuitry |
| The Archive | Akashic librarian, robed sage (XII The World) |

**Fix:** Solo portrait first → use as reference lock → composite into ensemble.

---

## Style layer (apply separately)

When generating art in chat or with a designer, prepend or append a **style block** to this canon.

**Workshop scenes (default v1.5):**

```
STYLE: TVA × Art Deco × 1939 World's Fair Futurism — monumental civic observatory,
brass/bronze/enamel/polished stone, Streamline Moderne consoles, bright daylight,
curved glass walls, retro-futurist aerospace optimism. Institutional, hopeful, grand scale.
Attach reference/novadiem-emblem.svg for architectural insignia near the Archive.
NOT dystopian, NOT cyberpunk, NOT corporate office, NOT wizard tower.
```

**Other deliverables — examples:**

```
STYLE: 1980s prestige painted comic cover, rich inks, luminous colors, no publisher logos
STYLE: Dark illuminated infographic, gold filigree, high contrast, legible captions
STYLE: Instrument-panel HUD, cyan traces on deep navy, mono labels, minimal ornament
STYLE: Soft watercolor character portrait, single figure, white border
STYLE: Moebius ligne claire workshop (character locks unchanged)
STYLE: 1950s retro-future team shot (character locks unchanged)
```

The style block controls render. This document controls identity.

**Chat pattern:**

```
[Paste one member section, or ensemble layout + member sections]

STYLE: [render direction]
NO publisher logos. NO trademarks.
```
