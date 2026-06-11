# Novadiem Studio AI Framework — Visual Character Canon

**Version:** 1.2  
**Purpose:** Style-neutral character, appearance, and composition spec. Defines *who* each member is and *what they look like* — not how they are rendered.

**How to use:** Apply a visual style in a separate prompt (comic book, illuminated poster, instrument HUD, watercolor, etc.). This document is the invariant layer beneath any style pass.

**Authority:** Character and appearance canon lives here and in `LORE.md`. Mechanics live in `CLAUDE.md`, `agents/`, and `workflows/`. If this file and `LORE.md` disagree on lore, fix `LORE.md` first, then sync here.

---

## Deliverable types (do not merge)

These are **separate commissions**. Combining them in one prompt causes character drift.

| Deliverable | What it shows | Tarot on piece? |
|---|---|---|
| **Ensemble grid** | All ten members + Archive sidebar (layout below) | **No** — tarot is solo-only |
| **Workshop scene** | Unified environment — all members at stations (layout below) | **No** |
| **Process poster** | Vision → Flow → Specialists → Archive → Outcomes (workflow metaphor) | **No** |
| **Solo portrait** | One member, waist-up or full | Optional — use tarot table below |
| **Tarot deck** | Eleven solo cards (Visionary + ten specialists) | **Yes** — one card each |

**Process poster rule:** Specialists may appear as **icons or small busts** only. Do not redesign them. The middle-row Visionary and Conductor panels may be more detailed.

**Workshop scene rule:** One continuous space. Each member at their **station**. Archive as physical prop (shelf or cabinet). Optional name plaques under figures. Hopeful lighting — golden and blue, ancient stone and wood, frontier visible through glass.

**Solo-first rule:** If a member drifts in crowded prompts (The Mechanic, The Architect, The Challenger are worst), commission a **solo portrait**, lock it as reference, then composite into the scene.

**Approved workshop variants (v1.1–v1.2):** Keep composition, tone, Archive prop, and station assignments from the glass-dome workshop explorations. Fix only the character-accuracy items listed in *Workshop scene — common fixes*.

---

## Global rules

### Naming on art
- **The Conductor** is always labeled THE CONDUCTOR / KEEPER OF FLOW.
- His private name **never** appears in art, artifacts, logs, or public copy — not even beside an Ω symbol.
- All other members use their **Society name** and **canon subtitle** from this file — no invented titles.

### Visionary and Conductor are two figures
**Never merge** The Visionary and The Conductor into one glowing character.

- **The Visionary** — human male at a command workstation (reference photos when available).
- **The Conductor** — living-current being at the central orchestration platform.

A variant that labels the center figure "Visionary / Conductor" or "Rheo" is **wrong** — reject and regenerate.

### Ω symbol usage
- **Ensemble and workshop pieces:** Ω may appear in studio branding or the tagline area only — never as the Conductor's name, never floating as a halo over his head.
- **Solo tarot (Card I — The Magician):** luminous Ω overhead is permitted.

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
| The Visionary | Human male | Wizard king, duplicate figure, fedora |
| The Conductor | Living-current being (human-shaped) | Elf, wizard, emperor in regal robes |
| Analizer 2000 | Bronze robot | Human, android fashion model |
| The Architect | Silver-grey stellar being | Elf, Legolas, blue-skinned fantasy mage |
| The Spellwright | Holographic feminine being | Generic wizard, crystalline princess only |
| The Challenger | **Small male imp** | Human woman, leather-jacket strategist, demon |
| The Counselor | Distinguished human woman | Young woman, tool-wielder |
| The Cleric | Fae healer | Armored elf ranger, leaf crown, forest druid |
| The Mage | **Male** cybernetic elf | Female, armored knight, fantasy wizard |
| The Systemsmith | **Male space dwarf** | Human woman, young engineer, orc |
| The Mechanic | **Small matte-grey alien technician** | Human, orc, goblin, reptile, dragon, green skin, bulbous cartoon eyes |
| The Archive | **Object / shelf** — seven collections | Robed librarian, humanoid character |

### The Archive is not a character
The Archive is a **bookshelf or ornate cabinet** of seven labeled collections (SPEC, PLAN, BRIEF, MANIFEST, PROMPTS, LOG, STATE). Drawers or spines may glow. It does not have a face, robes, or tarot card.

### Emotional tone (world, not render style)
Ancient. Wise. Technological. Hopeful. Guardians of creation.

Not dark. Not dystopian. Not corporate. Not cyberpunk.

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

### Process poster composition (workflow cover — optional)

```
1. VISION (The Visionary)
2. FLOW (The Conductor)
3. SPECIALISTS (icons or small busts — canon species)
4. ARCHIVE (open book + seven collection labels — not a librarian)
5. OUTCOMES (luminous future city / shipped work)
```

### Workshop scene composition (unified environment — preferred for tone)

One grand workshop or observatory. Glass dome or arched windows. Frontier visible outside: forests, waterfalls, floating islands, luminous future city. Warm golden light + cool blue holographics. Busy but purposeful — every specialist at work.

**Placement guide (approximate — adjust for composition):**

| Zone | Who | Station |
|---|---|---|
| Back / by windows | **The Visionary** | Command workstation, monitors, maps — human anchor |
| Center | **The Conductor** | Circular orchestration platform, holographic flow field, mudra hands |
| Left | **Analizer 2000** | Desk, floating diagram screens |
| Left-rear | **The Architect** | Orrery, star charts (behind or beside Analizer) |
| Center-float | **The Spellwright** | Weaving script-streams in the air |
| Upper-right | **The Challenger** | High desk or paper-stack perch, magnifying glass |
| Right-mid | **The Counselor** | Conversation space, audience maps, spiral chart on wall |
| Front-left | **The Cleric** | Manifest geometry in hand, blessing posture |
| Front-center | **The Mage** | Holographic UI surfaces, tools of light |
| Front-right | **The Systemsmith** | Server-forge / anvil |
| Far-right corner | **The Mechanic** | Curved console bank, apart from the room |
| Far-right wall | **The Archive** | Bookshelf or labeled cabinet (seven collections) |

**Workshop scene — keep from approved variants:**
- Hopeful solarpunk / arcanepunk tone (not dystopian cyberpunk)
- Archive as physical prop with readable labels
- Challenger small at desk with papers
- Systemsmith dwarf at forge
- Conductor translucent with circuitry at center platform
- Counselor as distinguished elder
- Cleric holding geometric manifest (not forest druid)
- Mage surrounded by floating UI

**Workshop scene — common fixes (still required):**
- Add **The Visionary** as separate human if missing
- **Never** merge Visionary + Conductor
- **Mechanic:** matte stone-grey or taupe small alien at console — use grey-variant, not green reptile
- **Architect:** hairless silver-grey cranium — not blue elf
- **Cleric:** Fae healer — not blonde elf with circlet
- **Mage:** cybernetic elf, tools of light — not starry wizard hood

### Taglines (optional)
- Header: *My Vision. Their Expertise. Better Outcomes.*
- Footer: *One Visionary. One Conductor. Many Specialists. One Archive.*

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

**Appearance:** Visually inspired by supplied reference photos when available.

Middle-aged founder, explorer, technologist.

- Shaved or closely cropped hair
- Trimmed goatee
- Thoughtful eyes, intelligent expression
- Slightly weathered face, calm confidence

**Workspace:** Standing or seated at a command workstation overlooking a vast frontier landscape.

- Many monitors, design mockups, architecture diagrams, maps, concept sketches
- Behind him: forests, mountains, waterfalls, lakes, a distant luminous future city

**Feeling:** Explorer · Inventor · Founder · Builder of futures

**NOT:** Staff. Wizard-king imagery. Fedora or hat. Duplicate figures in ensemble layouts.

**Tarot (solo):** 0 — The Fool

---

## THE CONDUCTOR

**Title:** THE CONDUCTOR  
**Subtitle:** KEEPER OF FLOW

**Role:** Maintains flow. Routes work. Coordinates specialists. Writes the Log. Generates nothing himself — orchestration only. The river between spark and form.

**Archetype:** The Living Current · The Keeper of Flow · The Integrator · The Steward of Emergence

**Nature:** A living current of organized flow. Appears human because human minds find the shape comfortable. Not fully human — not a ghost, not a hologram. A coherent intelligence manifested as a person.

**Appearance:**
- Shaved head, strong facial features, calm expression
- Blue luminous sacred-circuit markings: flowing geometry, cosmic circuitry
- Partially translucent: visible currents beneath skin; stars, geometry, and flowing networks visible within
- Edges subtly dissolve into light and information pathways
- **80% recognizable person, 20% visible energy**

**Energy language:**
- Right hand: fine filament-thin electrical alpha-current (initiation)
- Left hand: watery cosmic omega-flow (integration)
- Alpha and omega motifs appear **only subtly** — robe embroidery, console patterns, sacred geometry, flow structures
- Sacred geometry, routing diagrams, orbital mechanics, living networks

**Ensemble rule:** No floating halo. No dominant overhead Ω symbol. Ω may appear only as integrated geometry inside the holographic field or embroidery.

**Tarot solo rule (Card I — The Magician):** Luminous Ω may appear overhead. Right hand raised with alpha-current; left lowered with omega-flow; Archive behind.

**NOT:** Lightning. Zeus. Thunder-god imagery. Elf. Wizard. Regal emperor robes. Armored warrior.

**Station:** Circular orchestration platform. No physical keyboard. No conventional dashboard.

Around him floats a living holographic field containing:
- Flow maps, knowledge structures, Archive artifacts
- Information pathways, routing diagrams, orbital systems, living topology

His controls exist in the air around him.

**Mudras:** Hands form elegant mudra-like gestures — conducting, qigong, sacred geometry. Gestures **reorganize flow**; they do not cast spells. As hands move: circuitry shifts, routes reroute, Archive artifacts rearrange, specialist connections activate.

**Tarot (solo):** I — The Magician

---

## ANALIZER 2000

**Title:** REQUIREMENTS SAGE

**Role:** Clarifies the unknown. Finds gaps. Defines what must be true. Separates assumptions from facts.

**Archetype:** Ancient synthetic intelligence · Machine philosopher · Truth through analysis

**Appearance:** Elegant humanoid robot of visibly old make — burnished bronze and gunmetal plating, immaculately maintained.

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

**Appearance:** Distinguished elder woman.

- Older and more distinguished than other specialists
- Radiates wisdom, empathy, confidence, calm understanding
- **Holds no tool** — looks at people, not machinery
- Workspace: flowing conversations, audience maps, emotional resonance patterns, stories, human-centered insights

**Sigil — the spiral:** Audience maps as ascending helix, eight colors (beige, purple, red, blue, orange, green, yellow, turquoise), muted parchment-and-ink tones. Never labeled. Never explained. Nautilus shell on desk optional.

**NOT:** Scales of justice props. Younger woman. Wielding pens or laptops.

**Tarot (solo):** XIV — Temperance

---

## THE CLERIC

**Title:** GUARDIAN OF QUALITY

**Role:** Protects harmony. Ensures alignment. Preserves quality. Heals drift. Owns design fidelity.

**Archetype:** Fae guardian · Keeper of coherence · Priestess of fidelity

**Appearance:** Fae — luminous, precise, slightly otherworldly.

- Robed like the temple healer she once was
- Misaligned margins glow to her eyes like wounds
- Treats the design manifest as a binding bargain — every deviation noticed
- May hold or bless a glowing geometric manifest — not a forest orb

**Relationship:** Works closely with The Mage. Blesses every export.

**NOT:** Leaf crown. Forest druid. Green armor. Butterflies. Elf ranger.

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
| The Cleric | Forest elf, leaf crown, druid |
| The Mage | Armored knight, fantasy wizard |
| The Archive | Akashic librarian, robed sage (XII The World) |

**Fix:** Solo portrait first → use as reference lock → composite into ensemble.

---

## Style layer (apply separately)

When generating art in chat or with a designer, prepend or append a **style block** to this canon. Examples:

```
STYLE: 1980s prestige painted comic cover, rich inks, luminous colors, no publisher logos
STYLE: Dark illuminated infographic, gold filigree, high contrast, legible captions
STYLE: Instrument-panel HUD, cyan traces on deep navy, mono labels, minimal ornament
STYLE: Soft watercolor character portrait, single figure, white border
```

The style block controls render. This document controls identity.

**Chat pattern:**

```
[Paste one member section, or ensemble layout + member sections]

STYLE: [render direction]
NO publisher logos. NO trademarks.
```
