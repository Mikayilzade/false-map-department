# GAME #002 — FALSE MAP DEPARTMENT — PHASE 11 FINAL SPECIFICATION FREEZE

Last updated: 2026-08-19
Factory run: **13**
Phase: **11 — Specification Freeze**
Status: **FINAL CANONICAL FREEZE / DESIGN COMPLETE**
Production implementation started: **NO**

This file closes the design stage for Game #002. It adds no seventh primitive and no new product layer. Its purpose is to reconcile the complete Phase-3..10 specification, make the Phase-10 repairs authoritative, remove the last implementation-sensitive ambiguity, and prove that a fresh implementation session can build the game without inventing important gameplay.

---

# 1. Final decision

- Product thesis internally consistent: **YES**
- Mechanical architecture deterministic enough to implement: **YES**
- Content architecture bounded and data-contract defined: **YES**
- UX/input/accessibility paths specified: **YES**
- Economy/retention/commercial boundaries specified: **YES**
- Technical/persistence architecture specified: **YES**
- Whole-game simulation complete: **YES**
- Adversarial review complete: **YES**
- Phase-10 repairs reconciled: **YES**
- Fresh-session implementation-readiness audit: **PASS — 32/32 deterministic**
- Remaining uncertainty limited to empirical prototype/playtest gates: **YES**
- Specification freeze: **YES**
- **DESIGN COMPLETE: YES**
- Dedicated implementation repository migration: **NOT YET — NEXT RUN**
- Production implementation started: **NO**

The factory is therefore allowed to proceed to the migration gate, but it must not delete Game #002 files from the factory until the dedicated repository has been populated and verified.

---

# 2. Final authority order

For any implementation-sensitive conflict, use this precedence:

1. `GAME2_PHASE11_FINAL_FREEZE.md`
2. `GAME2_ADVERSARIAL_REVIEW.md` — especially canonical repairs P10-R1..P10-R10
3. `GAME2_MECHANICAL_ARCHITECTURE.md`
4. `GAME2_CONTENT_ARCHITECTURE.md`
5. `GAME2_UX_PRESENTATION_ARCHITECTURE.md`
6. `GAME2_ECONOMY_COMMERCIAL.md`
7. `GAME2_TECHNICAL_SPEC.md`
8. `GAME2_PRODUCT_THESIS.md`
9. `GAME2_WHOLE_GAME_SIMULATION.md` as validation history and worked-through experience evidence
10. tournament/research files as selection/history evidence only

Where a Phase-10 repair narrows earlier wording, the repair wins. Tournament examples, old pacing sketches, and obsolete demo wording are historical only and never override this authority chain.

---

# 3. Frozen product identity

Working title: **False Map Department**.

One-sentence hook:

> **Redraw the official map and the tiny world must obey: move roads, borders, rivers and landmarks to solve civic problems without creating worse consequences elsewhere.**

Non-negotiable differentiation rule:

> **The map is not a representation of the world. The map is an executable authority over the world.**

The game is a premium single-player systemic/causal cartography puzzle for PC/Steam first. It is not a city builder, management sim, freeform map editor, GIS simulation, god game, automation game, narrative adventure, or multiplayer service.

The 1.0 player edit vocabulary contains exactly six primitive families:
1. road segment;
2. bridge symbol;
3. border line;
4. waterway segment;
5. landmark semantic marker/name;
6. restricted-zone hatch.

No implementation session may add a seventh primitive merely because it is convenient or interesting.

---

# 4. Frozen gameplay semantics

## 4.1 Source of truth
Authoritative map facts are the only player-editable source of topology, ownership, semantic naming, water connectivity and zone policy. The world is derived from those facts. Presentation state never owns gameplay truth.

## 4.2 Snapped edits only
Every edit resolves to authored graph/grid/cell/crossing/landmark candidates. Freehand precision, stroke recognition and arbitrary geometry are not gameplay requirements.

## 4.3 Legal versus bad edits
A structurally illegal edit is rejected before mutation with an exact reason. A structurally legal edit that harms objectives or traps agents **commits normally**, resolves deterministically, teaches through consequences, and may be undone.

The engine must never reject an edit simply because it is strategically bad.

## 4.4 Primitive semantics
- Road toggles authored road connectivity; ordinary road traversal cannot cross active water except through a valid bridge relation.
- Bridge grants a crossing at an authored crossing slot; it does not remove water or independently change ownership.
- Border assigns authored cells/faces to jurisdictions; it is not inherently a physical wall.
- Waterway toggles authored water connectivity; no free fluid/hydrology simulation exists in 1.0.
- Landmark relabel changes semantic destination resolution while preserving stable object identity; labels come from authored localized token vocabularies, not arbitrary player text.
- Restricted zone changes permission by agent tags over authored candidate cells/faces; it does not erase roads or change jurisdiction ownership.

## 4.5 Deterministic accepted-edit resolution order
Observable semantics follow the frozen A–I order:
A. apply exactly one authoritative map mutation;
B. rebuild affected structural/derived facts;
C. resolve dependent crossing/bridge validity cleanup;
D. rebuild affected agent queries/routes/targets;
E. adjudicate trapped/displaced state;
F. run bounded deterministic reaction beats using same-start-snapshot intent and simultaneous apply;
G. evaluate objectives/invariants;
H. update Stability eligibility/state;
I. release presentation/control.

Implementation may optimize internally only if observable canonical output is identical to full deterministic resolution.

## 4.6 Agent time model
Agents exist on canonical nodes/cells between beats, never mid-edge as authoritative state. Inspection time does not advance simulation. Time advances only through accepted edit reaction beats and explicit Stability verification.

## 4.7 Agent archetypes
The base design ceiling remains A1..A10 from Phase 4/5. Their interpretation rules are canonical, not dossier-scripted. If prototype evidence later proves two archetypes behaviorally indistinct, the smaller canonical amendment path is merge/cut — not adding exceptions.

## 4.8 Tie-breaks
All route, target and movement ties that can affect gameplay resolve by explicit priority plus stable-ID ordering. No container/hash/scene order or hidden RNG decides gameplay.

## 4.9 Trapped state
Permission/topology edits do not teleport agents for convenience. If the current node remains physically valid but becomes forbidden, the agent can become `TRAPPED` and may leave toward legal space according to canonical rules. Base content avoids deleting an occupied physical node.

## 4.10 Causal ancestry
Every committed edit/Stability transaction produces a finite material-cause DAG sufficient to explain requirement changes and agent intent. It records meaningful causal events, not every internal read.

Default requirement-focused causal presentation obeys P10-R6: <=5 visible material nodes and <=2 visible sibling branches, with extra effects collapsed behind explicit expansion. Presentation may collapse equivalent intermediate same-family derivation but may not fabricate, reverse or reorder parentage.

---

# 5. Undo / Redo / intervention footprint

Undo is unlimited and free for baseline play and learning. It restores an exact pre-edit canonical checkpoint; it is not inverse gameplay simulation. Redo restores/replays the stored exact transaction only while the linear branch remains valid. A new accepted edit after Undo truncates the active Redo branch.

Derived consequences are children of the player edit and never count as separate player interventions.

**Experiment history is not score.** Raw edit count, Undo count, failed probes and elapsed time are not judged for baseline completion or mastery.

Optional `Clean Intervention` uses the canonical **final intervention footprint** defined by the design/content data, not the player's exploratory history.

No later implementation may add Undo charges, cooldowns, consumables, mastery penalties or anti-save-scumming punishment to solve brute-force risk.

---

# 6. Stability semantics and persistence reconciliation

Stability is explicit player-triggered verification, not an automatic long post-submit simulation.

A dossier with `stability_required_cycles > 1` must satisfy P10-R3:
- declare one canonical `stability_reason_tag` tied to an existing temporal state transition;
- known valid solution-envelope validation proves at least one relevant non-idle transition during the window;
- identical idle waiting for N cycles is invalid content.

Stability is never a seventh mechanic family; it verifies already-defined agent/service/sequence/linked-state behavior.

## Interrupted Stability — final rule
P10-R8 is authoritative:
- Stability persists only at transaction boundaries;
- if process death occurs during an incomplete Stability verification transaction, recovery restores the **exact pre-verification checkpoint**;
- verification is marked interrupted/not completed;
- player's committed map edits remain preserved;
- no partially advanced Stability beat is authoritative across process death;
- successful full verification + completion/progression persists atomically.

Human-readable recovery message is required; schema jargon is not.

---

# 7. Campaign / progression freeze

Base campaign target: **40 authored dossiers, D01–D40**, within the already-defined production tolerance only by deliberate canonical amendment before implementation content lock.

Campaign baseline progress is clear-driven and tutorial-tag/prerequisite driven. There is no currency, XP shop, energy, lives, grind gate or mastery gate.

D40 must be reachable with **zero optional mastery marks** provided required predecessor/tutorial prerequisites are baseline-cleared.

## Teaching order
- D01–D02: roads;
- D03–D04: bridge/water crossing relationship;
- D05–D06: border/jurisdiction;
- D07–D08: restricted zones and first synthesis;
- D09–D10: semantic landmark labeling;
- D11–D12: editable waterway connectivity;
- D13+: no seventh primitive; depth comes from recombination, agent interpretation, objectives/invariants, Stability and linked authority.

Late linked authority follows Phase-5 act ceilings. Four layers is the absolute 1.0 dossier ceiling, and at most two editing surfaces are shown simultaneously.

## Progression prerequisites
- D01–D08 use the defined teaching sequence and predecessor clears.
- From Act II onward, a dossier may expose alongside peers only when all of its explicit prerequisite/tutorial tags have been demonstrated by cleared predecessors.
- Progression code must consume content data/prerequisite tags; it must not hardcode a second contradictory unlock graph in UI scenes.
- D40 baseline completion never depends on mastery or remix completion.

---

# 8. Phase-10 authoring repairs are frozen acceptance rules

## P10-R1 — reasoning-transformation diversity
From D13 onward, every dossier has one dominant reasoning-transformation tag from the frozen list:
- topology restructuring;
- ownership reinterpretation;
- semantic-target reinterpretation;
- permission asymmetry;
- cross-network dependency;
- temporal/Stability dependency;
- linked-authority dependency;
- causal-compression/elegance.

No consecutive 3-dossier window may contain only one transformation. No consecutive 5-dossier window may contain fewer than 3 distinct transformations.

## P10-R2 — semantic relabel non-dominance
Whenever relabeling is editable, content validation probes every legal initial single relabel and each such relabel plus the cheapest one additional intervention. If this bypasses the dossier's declared central causal lesson, the content fails validation. No more than two consecutive D13–D40 dossiers may principally resolve through semantic relabeling.

## P10-R3 — Stability justification
Already frozen in section 6.

## P10-R4 — mastery distinction proof
Every authored mastery instance contains internal `mastery_distinction_note` and must require a qualitatively different causal insight, meaningful compression, meaningful additional civic preservation, or stronger Stability containing an actual temporal transition. Arbitrary threshold shaving is invalid content.

## P10-R5 — linked-authority readability
D25–D32: understanding the selected/first-broken required chain may require inspection of at most one remote target layer; the default required chain stays within the Phase-10 cross-layer budget.

D33–D40: mechanically broad effects are allowed, but each required objective/invariant has one explainable material chain with at most 3 cross-layer projection edges and a uniquely inspectable authoritative source.

Authority graph is always one-way/acyclic and never uses circular synchronization.

## P10-R6 — causal presentation budget
Already frozen in section 4.10.

## P10-R7 — deterministic authored focus graph
Every editable layer compiles a deterministic logical navigation graph for required focusable candidate states. Auto-generation may draft it; author overrides are allowed. Required candidates must be reachable. Directional navigation may not depend on current zoom, frame layout, float-nearest ambiguity, hash iteration or accidental scene order.

## P10-R8 — interrupted Stability recovery
Already frozen in section 6.

## P10-R9 — demo sequence
The 1.0 demo uses exactly five authored demo nodes:
1. `DEMO01` road add/remove causality;
2. `DEMO02` road tradeoff + Undo learning;
3. `DEMO03` bridge + water crossing;
4. `DEMO04` collateral connectivity consequence;
5. `DEMO05` compressed border-ownership teaching + synthesis.

Demo exclusions: restricted-zone editing, landmark relabeling, editable waterways, Ferry, Procession, Commercial chains, Stability>1 and linked maps.

Demo target remains 15–25 minutes. `DEMO05` teaches the same border semantic rule as campaign D05 but does not automatically equal D05 for progress import.

## P10-R10 — remix changed dependency
There are 12 planned 1.0 remix cases in the three frozen packs. Every remix declares `source_substrate_id`, changed inputs, an actual changed causal dependency and expected new reasoning transformation. A remix that only moves starts or thresholds while preserving the same causal insight fails validation. Every four-case pack uses at least 3 reasoning transformations.

---

# 9. Mastery / remixes / achievements / commercial boundaries

Mastery families remain:
- Clean Intervention;
- Civic Care;
- Stable Authority.

They never gate campaign ending or mechanical power. Accessibility settings never invalidate mastery merely because they are accessibility settings.

Puzzle hints change information/help only, not deterministic mechanics. Baseline completion remains possible after any hint depth. No default “no hints” prestige requirement is part of 1.0.

Remix unlocks remain milestone-based, permanent and non-FOMO. No dailies, streaks, rotating case shop, battle pass, energy, ads, gacha, microtransactions, paid hints or recurring live-service dependence.

Working design-time US list-price band remains **$14.99–$19.99**, center hypothesis **$17.99**, explicitly subject to release-time market recheck. Price is not gameplay canon.

Working achievement target remains **20–24**, center 22, with no accessibility-denial or grind achievements.

---

# 10. Demo -> full import freeze

Demo and full game maintain separate versioned progress envelopes/mappings.

Import rules:
- monotonic: never remove stronger/full-game progress;
- idempotent: applying the same import receipt twice changes nothing the second time;
- settings may transfer independently when safe;
- tutorial tags / baseline clears transfer only through explicit versioned mapping metadata;
- a demo node never auto-clears campaign D05 merely because it teaches the same border rule;
- campaign dossier clear transfer requires explicit proven content-equivalence mapping;
- incompatible active demo session state is never synthesized into changed full-game content;
- compatible durable facts may still import according to the mapping contract.

No implementation session may infer equivalence from IDs/names alone.

---

# 11. Input / accessibility freeze

Required gameplay must be completable through:
- mouse + keyboard;
- keyboard-only;
- controller-only;
- Steam Deck built-in controls at 1280×800 target layout.

Gameplay actions are remappable. There is no mandatory hover, freehand precision, right-click, mouse wheel, drag-only gesture, timed reflex input, color-only information, audio-only information, animation-only causal fact, or inaccessible tiny simultaneous four-map view.

At 1280×800 the two-surface rule and slide-over/collapsible case UI apply. Critical selection/correspondence/requirement state uses redundant shape/pattern/icon/text, not hue alone.

Reduced motion removes sweeps/swoops/large morph dependence but must preserve discrete before/after correspondence. Flash reduction, no-audio play, UI scaling and controller glyph presentation must preserve complete playability.

P10-R7 authored focus navigation is mandatory acceptance, not an optional polish item.

---

# 12. Technical/persistence freeze

Technical direction for the migrated implementation repository:
- **Godot 4.7.1-stable** pinned unless a deliberate pre-production upgrade is separately evaluated and recorded before codebase lock;
- GDScript-first;
- deterministic 2D domain separated from presentation;
- domain does not read wall clock, frame delta, OS locale, platform identity, uncontrolled RNG, physics contact ordering, hash iteration or scene-tree order;
- gameplay math uses integers/enums/fixed-point if fractional state is ever required;
- explicit stable sorting for all result-affecting sets;
- content is immutable/versioned per active session;
- semantic commands contain stable IDs and expected pre-state hash;
- stale/double command handling is idempotent;
- one committed player edit = one canonical transaction/history entry;
- persistence uses versioned envelopes, atomic generation strategy and corruption checks;
- newest valid compatible generation wins local corruption recovery;
- divergent active Cloud branches are not synthesized; durable monotonic progress may merge, while active dossier branch requires one chosen compatible branch according to technical spec;
- headless validation/replay/hash testing is a first-class implementation subsystem.

Exact cryptographic hash algorithm, scene composition, tween style, file compression library, Steam wrapper and non-gameplay storage implementation remain implementation-flexible if they preserve canonical contracts and version appropriately.

---

# 13. Content validation obligations

The implementation/content pipeline must validate before content can ship:
- schema completeness;
- stable-ID uniqueness;
- primitive candidate references;
- semantic-label vocabulary validity;
- agent archetype/schema validity;
- objective/invariant family validity;
- campaign prerequisite/tutorial tags;
- authority DAG acyclicity and unique authority ownership;
- four-layer ceiling;
- focus-graph reachability/determinism;
- known solution-envelope regression fixtures;
- canonical replay/hash determinism;
- P10-R1 reasoning-diversity windows;
- P10-R2 semantic non-dominance checks where computationally bounded;
- P10-R3 Stability reason/transition metadata;
- P10-R4 mastery distinction metadata;
- P10-R5 linked-chain readability metadata;
- P10-R6 required-chain compressibility to the default causal presentation budget;
- P10-R10 remix changed-dependency metadata.

Manual playtesting remains required; tooling is not permission to ship content that passes schemas but is boring or unreadable.

---

# 14. Frozen rules versus empirical prototype obligations

The following are **not missing design decisions**. They are empirical gates whose rules are already defined enough to implement and test.

## E1 — map->world comprehension
At least ~80% of representative naive testers should understand the causal map->world relationship within the first ~3 minutes after reasonable tutorial tuning.

## E2 — second-order prediction
By the end of the initial graybox/tutorial packet, at least ~70% should predict the direction of a representative second-order consequence.

## E3 — mature reasoning beats blind enumeration
Representative mature content must not be reliably easier/faster through deliberate legal-edit enumeration than through causal reasoning after rules are known.

## E4 — campaign repetition
D13–D22 and D29–D36 must not be predominantly described as repetitions of the same trick; re-author content before adding mechanics.

## E5 — linked authority comprehension
Before shipping 3–4-layer content, representative players must identify the authority-owning layer for a currently broken selected requirement using the UI without relying on tutorial memory.

## E6 — causal readability
Late-game players should answer `What caused this selected requirement to break?` from normal causal ribbon/Inspect UX without raw debug-event reading.

## E7 — accessibility/device sweep
Every shippable dossier passes 1280×800/controller/reduced-motion/grayscale-or-non-color/no-audio capture and interaction checks.

## E8 — marketing expectation
Store/trailer testing should produce expectations of `civic puzzle by changing authoritative map facts`, not freeform city building/map drawing.

## E9 — remix distinctness
Post-campaign testers should identify remixes as changed causal problems, not only harder/recycled layouts.

## E10 — agent distinctness
If two taught archetypes cannot produce predictably distinguishable responses for representative players, merge/cut through deliberate canonical amendment instead of adding exception prose.

## E11 — demo timing
The genuine collateral-consequence “aha” should arrive within the target demo window; if it consistently lands too late, repace demo content rather than fake capabilities.

## E12 — perceived value / final pricing
Final release price must be checked against real completion time, polish, replay value, current market comparables and localization breadth near release.

Failure of an empirical gate may reopen the minimum affected rule/content instance later. It does not mean today's implementation specification is incomplete.

---

# 15. Intentionally implementation-flexible choices

The following may be decided during implementation without inventing gameplay, provided all frozen contracts above remain true:
- internal class/file/folder names;
- exact Godot scene-tree composition;
- whether derived caches are rebuilt globally or incrementally when outputs match;
- exact stable/versioned hash algorithm;
- checkpoint compression format;
- exact filesystem/Steam Cloud adapter library;
- exact tween/easing, VFX, sound samples and decorative paper animation;
- exact non-gameplay font choice within readability/localization requirements;
- exact layout percentages inside Phase-6 safe bounds;
- exact controller glyph art and button defaults, because actions are remappable and semantics are frozen;
- exact localized wording while preserving machine predicates and plain-language meaning;
- exact production order inside a later implementation phase, so long as deterministic core/content validation is built early enough to prevent content debt;
- final store price/launch discount/trading-card decision near release, because these do not alter gameplay.

These are harmless freedoms. None requires an implementer to decide what a primitive means, how an agent behaves, what counts as completion, how progression works, how Stability recovers, what demo teaches, or how the simulation resolves.

---

# 16. Fresh-session implementation-readiness audit — 32/32

A new implementation session, reading only the final authority chain, can answer all of the following without inventing important gameplay:

1. What fantasy/product is being built and what genres must it not drift into? **YES**
2. What are the exact six player edit families? **YES**
3. How does each primitive mutate authoritative map/world facts? **YES**
4. What makes an edit structurally illegal versus merely strategically bad? **YES**
5. What is authoritative map state versus derived world/presentation state? **YES**
6. What is the deterministic A–I resolution order? **YES**
7. How do reaction beats compute intent and apply simultaneous outcomes? **YES**
8. How are path/target/movement ties resolved? **YES**
9. Can gameplay use hidden RNG, frame time, physics contacts or unordered iteration? **NO; explicitly forbidden**
10. Where can agents exist between beats and what happens when permission/connectivity changes under them? **YES**
11. What do A1..A10 mean and may dossiers override their logic? **YES; no arbitrary override**
12. How are objectives/invariants represented/evaluated and when may a bad edit commit? **YES**
13. What exactly does Undo restore and what does Redo mean? **YES**
14. Does experimentation/Undo count affect baseline/mastery? **NO; exact rule frozen**
15. What is the intervention footprint conceptually used for? **YES**
16. When is Stability allowed/meaningful and how does it run? **YES**
17. What happens if the process dies during Stability verification? **YES — pre-verification rollback**
18. What is the D01–D40 teaching/progression structure and can mastery gate D40? **YES; mastery cannot gate D40**
19. What are the campaign complexity/layer ceilings? **YES**
20. How do linked maps own/project facts and can authority cycle? **YES; one-way DAG only**
21. What readability budgets apply to required linked chains? **YES**
22. What is the default causal-ribbon budget and what may collapsing do? **YES**
23. What focus-navigation semantics are mandatory for keyboard/controller? **YES**
24. Can the game require color/audio/motion/freehand/timed input? **NO; explicitly forbidden**
25. What exactly does the demo teach and exclude? **YES — DEMO01..05 frozen**
26. How may demo progress import into full game? **YES — explicit versioned monotonic/idempotent mapping only**
27. What are the three mastery families and can they grant power/gate ending? **YES; no power/no ending gate**
28. What makes a valid 1.0 remix rather than a recycled substrate? **YES — changed causal dependency required**
29. What must content validation/tooling prove before ship? **YES**
30. How do local save corruption, stale commands and divergent cloud active branches behave? **YES**
31. Which remaining questions are prototype/playtest gates rather than undefined design? **YES**
32. Which choices may implementation safely make without canonical design amendment? **YES**

**Result: 32/32 implementation-sensitive questions are deterministic or deliberately harmlessly flexible.**

---

# 17. No-new-design rule after freeze

From this freeze forward, implementation must treat this design as a contract.

Do not casually add:
- a seventh primitive;
- economy/currency/upgrades;
- new agent interpretation families;
- freehand map drawing;
- procedural campaign dependence;
- multiplayer;
- city-builder systems;
- combat;
- Workshop/UGC requirement;
- live-service retention;
- new campaign acts beyond the frozen content shape;
- new demo-only mechanics.

If implementation reveals a real contradiction, record the exact contradiction and amend the minimum canonical rule deliberately before changing gameplay behavior.

---

# 18. Migration gate — exact next action

The design stage is complete, but the factory completion condition is **not** yet satisfied because Game #002 has not been safely migrated.

Next run must:
1. create/use a dedicated repository for False Map Department, preferably `Mikayilzade/false-map-department` unless an existing repository already owns that name;
2. copy all canonical Game #002 files plus relevant research/tournament/validation history required for recovery;
3. preserve contents/hashes where practical and verify the Phase-11 freeze exists identically in the destination;
4. add a dedicated `README.md` / design-status pointer as needed;
5. add detailed `IMPLEMENTATION_START_HERE.md` with autonomous Phase 12A–12H implementation ladder;
6. add live `IMPLEMENTATION_STATUS.md`, initially pointing to 12A Technical Bootstrap;
7. verify the destination authority chain locally within that repository;
8. update `GAME_INDEX.md` to `DESIGN COMPLETE / migrated` with the dedicated repo;
9. only after successful verification, remove Game #002-specific files from `gpt-game-autonomy` and reset factory `STATUS.md` for Game #003;
10. then and only then may the factory report this game's design cycle as completed and disable the current Game #002 design automation.
