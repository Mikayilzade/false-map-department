# GAME #002 — PRODUCT THESIS LOCK

Last updated: 2026-08-18
Factory run: **5**
Phase: **3 — Product Thesis Lock**
Concept: **False Map Department**
Product thesis locked: **YES**
DESIGN COMPLETE: **NO**

This file locks the identity of Game #002. Later phases may refine implementation details, counts, balance and content, but must not quietly turn the game into a different product.

---

## 1. Working title

**False Map Department**

Working title status: strong enough for design. Final trademark/store-name review is implementation/release work.

---

## 2. One-sentence hook

**Redraw the official map and the tiny world must obey: move roads, borders, rivers and landmarks to solve civic problems without creating worse consequences elsewhere.**

---

## 3. Product fantasy

You are a bureaucratic cartographer in a world where the official map is causally authoritative. A line on paper is not a description. It is an order reality executes.

The fantasy is not “make accurate maps.” It is **govern reality by editing representation**, then understand the collateral effects of your edits better than the system does.

---

## 4. Target player

Primary:
- players of compact systemic puzzle games;
- players who enjoy causality, route logic, spatial reasoning and elegant multi-objective solutions;
- players who like discovering consequences rather than solving arithmetic worksheets;
- PC/Steam players comfortable with 10–30 minute focused puzzle sessions.

Secondary:
- cozy/relaxing puzzle players attracted by maps and miniature worlds, provided difficulty modes and causality tools prevent late-game opacity;
- optimization players who want optional low-intervention mastery without forcing all players into minimum-move play.

Not targeted as a primary audience:
- action/reflex players;
- large-world exploration players;
- narrative-adventure players expecting dialogue-heavy roleplay;
- hardcore automation/sandbox players expecting open-ended factory construction.

---

## 5. Platform / commercial frame

- PC/Steam first.
- Premium single-player.
- No F2P economy, energy timers, gacha, ads or live-service dependency.
- Controller support required; mouse must not be mandatory.
- Steam Deck compatibility is a design target because the dual-view interface can fit a compact puzzle format if text/UI scaling is handled deliberately.
- A demo is desirable and should contain the hook, first tradeoff and one second-order consequence within 15–25 minutes.

Exact price is intentionally not frozen in Phase 3; later commercial research may set it from scope and current comparables.

---

## 6. Genre framing

Primary genre: **systemic puzzle / causal cartography puzzle**.

Supporting descriptors:
- deterministic;
- spatial;
- route/ownership logic;
- miniature simulation;
- multi-objective;
- low-pressure unless optional mastery chosen.

Avoid marketing it as:
- city builder;
- map-making simulator;
- management sim;
- god game;
- automation game;
- open-world exploration.

Those frames create expectations outside the scope.

---

## 7. Core loop

1. **Read the dossier** — understand civic goals, protected invariants and visible world state.
2. **Inspect map/world correspondence** — hover/select a symbol or world object to see its causal twin.
3. **Edit one canonical map primitive** — road, bridge, border, waterway, landmark or restricted zone.
4. **Watch immediate deterministic reality rewrite** — the world changes at once and affected agents react through a short bounded resolution.
5. **Inspect causal consequences** — see which facts and agents changed because of the edit.
6. **Revise** — keep, undo or make another edit based on a hypothesis.
7. **Stabilize the district** — satisfy all goals and protected invariants through the required deterministic cycle window.
8. **Complete / optionally optimize** — finish baseline dossier; pursue Gold-style low-intervention or collateral-damage mastery only if desired.

There is no separate “submit map and watch a long simulation” phase. The feedback loop is immediate.

---

## 8. Non-negotiable differentiation rule

**The map is not a representation of the world. The map is an executable authority over the world.**

Every important gameplay layer must preserve this.

If a feature could function identically without the map/reality causal relationship, it is suspect and must justify its existence.

---

## 9. Canonical initial vocabulary

The game is built around six ordinary map conventions whose consequences recombine:

1. Road segment.
2. Bridge symbol.
3. Border line.
4. Waterway segment.
5. Landmark marker/name.
6. Restricted-zone hatch.

These are not decorative tools. Each has deterministic world semantics and can affect multiple agent/objective systems.

Later design may add narrowly scoped derived states or modifiers, but Phase 4 must resist expanding into dozens of magical symbols.

---

## 10. Session structure

Typical dossier:
- 5–20 minutes first-clear depending on complexity;
- immediate retry/undo within dossier;
- no consumable punishment for experimentation;
- optional mastery target after baseline completion.

Typical play session:
- 20–60 minutes, usually 2–6 dossiers.

Campaign target:
- approximately 35–45 authored dossiers before challenge/remix variants;
- roughly 5–8 hours for first completion if final content density supports it;
- optional mastery/replay can extend this substantially without mandatory grind.

Counts remain Phase-5 adjustable, but the product must stay compact rather than becoming a 100-hour management sim.

---

## 11. Progression thesis

Progression comes from **interpretive depth**, not stat power.

Early game:
- one map convention at a time;
- one obvious agent rule;
- immediate local consequence.

Midgame:
- conventions interact;
- several agents interpret the same edit differently;
- goals conflict;
- ownership/routing chains cross systems.

Late game:
- linked map scales;
- remote second-order consequences;
- 3–4 simultaneous goals/invariants;
- stability over several deterministic cycles;
- elegant low-intervention solutions.

The player becomes better because they understand the causal grammar, not because they buy stronger map tools.

---

## 12. Failure / recovery philosophy

Failure must teach.

Required principles:
- ordinary experimentation is reversible;
- undo is fast and safe;
- failed stability highlights the first relevant broken invariant and its causal ancestry;
- the game never hides an RNG roll behind a map consequence;
- no dossier should require pixel hunting or undocumented exception knowledge;
- baseline completion does not penalize raw experimentation history;
- optional mastery scores final solution footprint/stability/collateral impact rather than shaming learning attempts.

The game must not turn into save-scumming against opaque rules.

---

## 13. Anti-bruteforce thesis

Brute-force is defeated by **meaningful consequence structure**, not scarcity of undo.

Mature dossiers must:
- have multiple locally plausible edits;
- combine at least two world systems;
- include protected invariants;
- expose delayed/remote deterministic consequences over short cycles;
- make causal understanding reduce search much faster than enumerating legal edits.

If Phase-4 mechanical design cannot maintain this, the concept must be reopened rather than hiding the weakness behind edit limits.

---

## 14. Presentation thesis

Visual identity:
- split or tightly linked dual representation: official map + living miniature district;
- edits visibly animate across the boundary so correspondence is unmistakable;
- map side is tactile, clean, iconographic, bureaucratic;
- world side is charming and legible rather than realistic;
- agents are readable silhouettes/icons with strong route/ownership feedback.

Tone:
- lightly absurd civic bureaucracy;
- consequences can be funny, but comedy never makes rules arbitrary;
- no requirement for expensive voice acting or cutscene production.

A screenshot must ideally show a map edit highlighted on one side and its transformed world consequence on the other.

---

## 15. Accessibility / input thesis

Phase 6 must fully specify acceptance tests, but Product Thesis locks these constraints now:
- no mandatory freehand precision;
- every edit snaps to legal graph/grid primitives;
- full game completable mouse+keyboard, keyboard-only and controller-only;
- no color-only information;
- critical map/world correspondence has shape/icon/pattern plus text where useful;
- scalable UI and readable Deck-sized presentation;
- no timing/reflex requirement for ordinary puzzle completion;
- animations may be sped up or reduced without losing causal information.

---

## 16. Scope ceiling / explicit exclusions

### In scope
- authored deterministic dossiers;
- compact reusable agent simulation;
- optional mastery constraints;
- linked map scales in late game if proven readable;
- lightweight story framing through dossier text/environmental tone;
- demo.

### Out of scope for 1.0
- open-world walking/exploration;
- city-builder economy;
- procedural infinite campaign;
- multiplayer/co-op;
- user-generated map editor/workshop;
- long branching dialogue trees;
- combat system;
- real geospatial/GIS simulation;
- realistic hydrology/traffic simulation;
- AI-generated maps/content dependency;
- freehand art-recognition mechanics.

These exclusions are protective. They may not be reintroduced casually in later phases.

---

## 17. What success feels like

The intended player thought is:

> “I changed one innocent line on the map, realized it changed three systems at once, then found a cleaner edit that made the whole district click.”

Not:
- “I finally guessed the designer's answer.”
- “I spammed undo until everything turned green.”
- “I spent five minutes drawing precisely.”
- “I waited for a simulation to finish.”

---

## 18. Product-level empirical gates inherited into implementation

These are not missing design decisions; they are future prototype obligations:
- >=80% naive testers understand map->world causality within 3 minutes;
- >=70% can predict the direction of a second-order consequence by the end of the initial graybox packet;
- mature successful play should predominantly contain hypothesis-driven edits rather than blind probes;
- exhaustive legal-edit enumeration must not beat causal reasoning as dossier complexity grows;
- players should describe the fantasy as changing reality through the map, not merely editing a level graph;
- the mapping verb must remain central through later content instead of being diluted by unrelated exploration/minigames.

---

## 19. Phase-3 acceptance decision

- Target player locked: **YES**
- Platform/commercial frame locked enough for design: **YES**
- Genre framing locked: **YES**
- One-sentence hook locked: **YES**
- Core fantasy locked: **YES**
- Core loop locked: **YES**
- Non-negotiable differentiator locked: **YES**
- Session structure locked: **YES**
- Progression thesis locked: **YES**
- Scope ceiling locked: **YES**
- Production implementation started: **NO**
- Product thesis lock: **YES**
- DESIGN COMPLETE: **NO**

## NEXT PHASE
**Phase 4 — Mechanical Architecture.**

The next run must define deterministic edit/world semantics, state model, agent rule archetypes, resolution ordering, dossier goals/invariants, stability, undo/history, causal ancestry, valid/invalid edits, multi-scale map behavior, anti-bruteforce mechanics, win/fail states, balancing knobs and Phase-4 acceptance tests before expanding content.