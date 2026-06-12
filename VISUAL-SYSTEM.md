# Novadiem Studio Framework — Visual System v2

**Version:** 2.1  
**Purpose:** Primary poster family for the framework — process, structure, philosophy, and (proposed) outcomes.  
**Authority:** Poster composition and material language live here. Character species and appearance live in `VISUAL-CANON.md`. Mechanics live in `workflows/` and `agents/`. Lore lives in `LORE.md`.

**Supersedes as primary family:** Assembly Line poster · character grid as architecture diagram · workshop scene / annotated roster as flagship poster. Those explorations remain valid **reference** for tone and character locks; new commissions follow the trilogy first.

---

## The poster family

| # | Title | Subtitle | Answers | Status |
|---|---|---|---|---|
| I | **THE CURRENT** | FEATURE WORKFLOW | How does a feature move through the Society? | **Commission** |
| II | **THE HUB** | THE SOCIETY OF SPECIALISTS | How is the Society structured and routed? | **Commission** |
| III | **THE ENGINE** | THE GREAT ENGINE OF CREATION | What is the Society, philosophically? | **Commission** |
| IV | **THE FRONTIER** | OUTCOMES OF THE SOCIETY | What does the Society produce? | **Proposed** |

The trilogy explains **process**, **structure**, and **philosophy**. THE FRONTIER completes the set with **emergence** — what leaves the system.

**Commission order:** I → II → III first. IV after trilogy ships. Build Party sheet is a workflow companion, not a poster-family member.

**Do not merge** pieces in one prompt — same rule as character deliverables in `VISUAL-CANON.md`.

---

# I. THE CURRENT

**Subtitle:** FEATURE WORKFLOW

**Purpose:** Show how a feature moves through the Society.

**Replaces:** Assembly Line poster.

**Workflow source:** `workflows/feature.md` (plan workflow — produces spec, plan, prompts; build is `execute-plan`, not shown on this piece).

---

## Core concept

The Conductor is **not a step**.

The Conductor is the **routing current**.

The current runs continuously through the entire diagram. Specialists appear as **stations** connected to the current. The current is the visual representation of orchestration.

---

## Composition

Horizontal format.

Large Art Deco routing rail running left to right.

```
IDEA

══════════════════════════════════════════════
          THE CURRENT OF INTENT
══════════════════════════════════════════════

ANALIZER 2000
     ↓
THE ARCHITECT
     ↓
DESIGN-MODEL CHECKPOINT
     ↓
THE CHALLENGER  (round 1)
     ↓
THE CLERIC
     ↓
THE SPELLWRIGHT
     ↓
THE CHALLENGER  (round 2)

PROMPTS READY
```

---

## Artifact labels

| Station | Outputs |
|---|---|
| **Analizer 2000** | `spec.md` — Requirements |
| **The Architect** | `spec.md` — Architecture · `plan.md` |
| **Design-model gate** | `[DESIGN-MODEL CHECKPOINT]` — human go / model correction |
| **The Cleric** | `design/brief.md` · (external) · `design/manifest.md` |
| **The Spellwright** | `prompts.md` |
| **The Conductor** *(side-channel)* | `log.md` · `state.json` |

Conductor artifacts flow **beneath the rail** — continuous orchestration, not a box in the sequence.

Exit label: **`prompts.md` — vetted & scoped** (not `EXPORTS.MD`). Optional sublines: *execute-plan builds from here* · faint ghost arrow *→ shipped work* (points toward THE FRONTIER without duplicating it).

---

## Design branch

The Cleric node forks.

```
THE CLERIC
  │
  ├── NOT NEEDED ───────────► THE SPELLWRIGHT
  │
  └── DESIGN REQUIRED
          │
          ▼
     design/brief.md
          │
     [DESIGN HANDOFF]  (Visionary → Claude Design → export)
          │
     design/manifest.md
          ▼
     THE SPELLWRIGHT
```

---

## Feedback loops

- **Challenger round 1** → findings routed by Conductor to spec/plan owner (max 2×)
- **Challenger round 2** → findings routed by Conductor to Spellwright (max 2×)

Show as dashed return paths to the rail, not specialist-to-specialist arrows.

---

## Visual language

- Brass routing paths
- Deep Instrument background (`#0B1020`)
- Circuit Cyan current (`#3ECFCF`)
- Filament Gold labels (`#C9A227`)
- Sora + DM Mono
- Institutional control-board feeling

**Not:** fantasy · character art · BPMN · RPG UI · dark academia alchemical

**Feels like:** a World's Fair exhibit explaining a great machine.

---

# II. THE HUB

**Subtitle:** THE SOCIETY OF SPECIALISTS

**Purpose:** Show structure. Show relationships. Show routing.

**Not:** workflow · sequence · character portraits

**Replaces:** character grid as the primary architecture diagram.

---

## Core concept

The Conductor sits at the center. All routing flows through him. **No specialist communicates directly.** The Archive surrounds the system.

---

## Composition

Radial.

```
                ARCHIVE

      Architect       Challenger

 Analizer 2000           Spellwright

          \           /

            CONDUCTOR

          /           \

 Counselor             Cleric

      Mage         Systemsmith

             Mechanic

             Visionary
```

Visionary sits **outside** the specialist ring — intent enters; does not route.

---

## Routing rules

Displayed around the perimeter:

- One Visionary
- One Conductor
- Many Specialists
- One Archive
- Truth Before Comfort
- Quality Before Speed
- No Specialist-to-Specialist Communication
- Artifacts Move Through The Archive

---

## Archive ring

Outer ring contains seven illuminated collection nodes:

SPEC · PLAN · BRIEF · MANIFEST · PROMPTS · LOG · STATE

---

## Visual language

- Astronomical instrument
- Art Deco observatory
- Brass rings · orrery geometry
- Institutional seal · museum exhibit

**Not:** fantasy adventuring party · character grid with species art · workshop interior scene

Specialists may appear as **labels, sigils, or small abstract busts** — not full character commissions (see `VISUAL-CANON.md` process-poster rule).

---

# III. THE ENGINE

**Subtitle:** THE GREAT ENGINE OF CREATION

**Purpose:** Master poster. Philosophy piece. Internal flagship image. The iconic framework artifact.

**Replaces:** workshop scene / annotated roster as the primary flagship poster.

---

## Core concept

An enormous civic machine.

The Society is **not** depicted as workers at a table. The Society is depicted as **forces** operating a civilization-scale instrument.

- The Visionary provides intent
- The Conductor regulates flow
- The Specialists refine reality
- The Archive remembers
- The Build Party manifests *(execute-plan — Mage, Systemsmith, Mechanic)*

---

## Composition

Vertical. Three tiers.

### Tier one — THE VISIONARY

At the top. Outside the machine. Intent enters the system.

### Tier two — THE CONDUCTOR

Massive central rotunda. Split-spiral routing field. Alpha and Omega currents. The living regulator.

*(Character appearance: `VISUAL-CANON.md` § THE CONDUCTOR.)*

### Tier three — the Society

Arranged in concentric rings:

Analizer 2000 · Architect · Challenger · Cleric · Spellwright · Counselor · Mage · Systemsmith · Mechanic

### Base — THE ARCHIVE

SPEC · PLAN · BRIEF · MANIFEST · PROMPTS · LOG · STATE

The foundation of the machine.

---

## Footer *(workshop register — canon)*

**Header:** Clear Intent. Deep Expertise. Better Outcomes.

**Mission:** We turn ideas into finished work through coordinated specialists and a shared project record.

**Structure:** One Visionary. One Conductor. Many Specialists. One Archive.

**Flourish:** We build for human flourishing.

**Poster rule:** one mission statement per piece — mission block *or* flourish footer, not both stacked awkwardly. Full footer stack is correct for THE ENGINE.

---

## Visual language

Same Sacred Instrument material language as I and II, at **monumental scale** — TVA × Art Deco × World's Fair Futurism (`VISUAL-CANON.md` § Workshop environment v1.5).

Character depiction **allowed** on THE ENGINE only (flagship). Species locks still apply. Solo portraits remain the lock source for drift-prone members.

**Note:** THE ENGINE centers the **machine**. THE FRONTIER (below) inverts the hierarchy — outcomes dominate, Society is small.

---

# IV. THE FRONTIER *(proposed)*

**Subtitle:** OUTCOMES OF THE SOCIETY

**Purpose:** Show what emerges from the Society — the creation, not the institution.

**Status:** Proposed fourth poster. **Do not commission before the trilogy ships.**

**Workflow source:** Not one workflow — the **output** of `feature` → `execute-plan` → shipped artifact. Visually: intent enters a small instrument; finished work dominates the frame.

**Replaces:** legacy process-poster step 5 (OUTCOMES / luminous city) as a standalone piece.

**Public-site fit:** Strongest candidate for **material-language-only** credential art on novadiem.com — no Society characters required (`brand-brief-sacred-instrument.md`).

---

## Core concept

The framework is not about the specialists. It is about **what gets built**.

The Society appears **small** — a distant instrument silhouette, brass schematic, or compact hub glyph. The **frontier of creation** dominates: applications, products, communities, businesses, creative works, infrastructure emerging from the Archive and Build Party.

Idea → Society → **Product** (Society is the middle, not the subject).

---

## Composition

Horizontal or wide landscape (~2:1). Inverted hierarchy vs THE ENGINE.

```
[small]  INTENT
            ↓
[small]  INSTRUMENT SILHOUETTE  (Engine / Hub abstract — not character art)
            ↓
     ARCHIVE + BUILD PARTY
     (subtle — cyan traces from SPEC→PROMPTS→shipped)
            ↓
══════════════════════════════════════════════
         THE FRONTIER OF CREATION
══════════════════════════════════════════════

  [dominant field: outcomes at civic scale]

  · web applications / SaaS interfaces
  · community platforms / marketplaces
  · regulatory/compliance products
  · infrastructure / data systems
  · creative works / designed experiences
  · cities / institutions / lived environments

  (abstract or semi-abstract — World's Fair optimism, not product screenshots)
```

---

## What to show (outcome categories)

Render as **hopeful civic scale**, not a collage of logos:

| Category | Visual direction |
|---|---|
| Applications | Streamlined UI panels, instrument HUDs, clean product silhouettes |
| Communities | Networks, exchange flows, gathering spaces — abstract |
| Businesses | Operational systems, dashboards as civic infrastructure |
| Infrastructure | Data paths, deployment arcs, reliable backends as public works |
| Creative works | Designed artifacts, manifests made real |
| Built environment | Art Deco future city, frontier settlement, World's Fair skyline |

Real Novadiem work (Nutrifax, GrowOperative, FOAF, etc.) may inform **shape language** — do not use client logos or literal screenshots unless commissioned as case-study insets.

---

## Copy to render

**Title block:**
```
NOVADIEM STUDIO
THE FRONTIER
OUTCOMES OF THE SOCIETY
```

**Caption (optional):**
```
We turn ideas into finished work through coordinated specialists and a shared project record.
```

**Footer (minimal — one line):**
```
Better Outcomes.
```
or reuse structure line only: *One Visionary. One Conductor. Many Specialists. One Archive.* — not the full ENGINE footer stack.

---

## Visual language

Same Sacred Instrument palette and TVA × Art Deco × World's Fair Futurism.

- Deep Instrument field; **outcomes lit** in circuit cyan and warm gold
- Society/instrument **≤15%** of frame — lower corner or distant center
- No character art · no species · no tarot
- Feels like: the exhibit hall **after** the machine room — what the institution built for the world

**Not:** team shot · product marketing grid · cyberpunk city · dystopia

---

## Relationship to other pieces

| Piece | Subject | Hierarchy |
|---|---|---|
| THE CURRENT | Process | Rail + stations |
| THE HUB | Structure | Conductor center |
| THE ENGINE | Myth | Machine dominates |
| **THE FRONTIER** | **Emergence** | **Outcomes dominate** |

---

# Design rules across the family

| Rule | Value |
|---|---|
| Material language | Sacred Instrument |
| Architecture style | TVA × Art Deco × World's Fair Futurism |
| Field | Deep Instrument `#0B1020` |
| Current / trace | Circuit Cyan `#3ECFCF` |
| Labels / rules | Filament Gold `#C9A227` |
| Type | Sora + DM Mono |
| Public site | Material language only — see `novadiem.com/docs/brand-brief-sacred-instrument.md` |

**Avoid on all pieces:**

- Fantasy races visible *(THE ENGINE only — character depiction with species locks; never on CURRENT, HUB, FRONTIER)*
- Tarot references
- Comic-book captions
- RPG party framing
- Workflow-software / BPMN aesthetic
- Neon noir · synthwave · dark academia alchemical UI

**Target feeling:** a timeless institution devoted to transforming intent into reality.

---

## Secondary deliverables (still valid, not trilogy)

| Deliverable | Use |
|---|---|
| **Solo portrait** | Lock species before compositing into ENGINE |
| **Tarot deck** | Eleven solo cards — tarot never on poster-family pieces |
| **Workshop scene** | Character + environment reference; tone for ENGINE tier |
| **Annotated roster** | ENGINE + per-member blurbs (`VISUAL-CANON.md` § Member blurbs) |
| **Build Party sheet** | `execute-plan` workflow — companion to THE CURRENT, not yet a trilogy member |

---

## Reference file naming

| Piece | Suggested path |
|---|---|
| THE CURRENT | `reference/the-current-feature-v1.png` |
| THE HUB | `reference/the-hub-society-v1.png` |
| THE ENGINE | `reference/the-engine-creation-v1.png` |
| THE FRONTIER *(proposed)* | `reference/the-frontier-outcomes-v1.png` |
| Build Party companion | `reference/the-build-party-execute-plan-v1.png` |

## Theme variants — day / night (canon)

The site flips between day and night mode, and the hero art flips with it. So every
locked poster-family piece ships as a **pair**:

- **Night (master).** The default Sacred Instrument palette — Deep Instrument ground,
  Filament Gold, Circuit Cyan glow. This is the version that gets locked first and
  carries the `-v1.png` name.
- **Day (variant).** The *same composition relit*, saved beside the master as
  `…-v1-light.png`. Bright atrium light, ivory/parchment grounds, brass and gold
  holding their warmth, cyan surviving as accent rather than glow. Navy panels become
  ink linework on light surfaces.

**Same composition, different lighting — never two different pieces.** A theme toggle
that reflows the scene reads as a glitch, not a mode. Produce the day variant by
*relighting* the locked night master (image-edit: "same image, daylight version"),
not by commissioning fresh — relights preserve layout; regenerations don't.

Lock the night master before commissioning its day variant.

## Designer handoff

Full brief, composition checklists, exact copy, and image-gen prompts:

**`reference/designer-handoff-trilogy.md`** *(trilogy + proposed FRONTIER + Build Party)*

Legacy comp reviews (superseded visuals, salvageable IA):

- `reference/legacy-assembly-line-v1-notes.md`
- `reference/legacy-workshop-ensemble-v1-notes.md`

---

*Questions → Robin. Character locks → `VISUAL-CANON.md`. Workflow accuracy → `workflows/feature.md`.*
