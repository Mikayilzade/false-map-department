# FALSE MAP DEPARTMENT — IMPLEMENTATION START HERE

Status: **DESIGN FROZEN / IMPLEMENTATION NOT STARTED**
Destination intended: `Mikayilzade/false-map-department`

This repository is the implementation home for False Map Department. The design is already complete. Implementation must follow the frozen design rather than inventing or casually simplifying gameplay.

## Required read order
1. `GAME2_PHASE11_FINAL_FREEZE.md`
2. `GAME2_ADVERSARIAL_REVIEW.md`
3. `GAME2_MECHANICAL_ARCHITECTURE.md`
4. `GAME2_CONTENT_ARCHITECTURE.md`
5. `GAME2_UX_PRESENTATION_ARCHITECTURE.md`
6. `GAME2_ECONOMY_COMMERCIAL.md`
7. `GAME2_TECHNICAL_SPEC.md`
8. `GAME2_PRODUCT_THESIS.md`
9. `GAME2_WHOLE_GAME_SIMULATION.md`
10. `GAME2_TOURNAMENT_RUN5.md` only for selection/history context
11. `GAME2_TOURNAMENT_RUN4.md`, `GAME2_TOURNAMENT.md`, `GAME2_RESEARCH.md` only when historical rationale is needed

When files disagree on implementation-sensitive behavior, obey the authority order in `GAME2_PHASE11_FINAL_FREEZE.md`.

## Autonomous implementation protocol
A continuation prompt means: read `IMPLEMENTATION_STATUS.md`, then the relevant frozen design files, perform the exact next substantial verifiable increment, test it, commit it, and update implementation status before ending. Never leave meaningful state only in chat.

One run is not one phase. A phase may require multiple runs. Prefer one coherent working increment with tests over a large partially implemented batch.

Every run must record:
- implementation phase/subphase;
- files/systems changed;
- tests or validation run;
- failures/blockers;
- exact next action;
- whether any canonical contradiction was discovered.

## Canonical-amendment rule
The design is a contract. Do not change gameplay because implementation is inconvenient.

If implementation reveals a real contradiction:
1. record the exact contradiction and affected canonical clauses;
2. stop the conflicting gameplay change;
3. amend the minimum canonical design rule deliberately;
4. update the final authority chain/status;
5. only then implement the changed behavior.

Do not casually add a seventh primitive, economy/currency/upgrades, new agent interpretation families, freehand map drawing, procedural-campaign dependence, multiplayer, city-builder systems, combat, UGC/Workshop dependence, live-service retention, extra campaign acts, or demo-only mechanics.

## CI / email-noise guardrail
Read `CI_NOTIFICATION_POLICY.md` before creating GitHub Actions workflows.

During unstable bootstrap and early vertical-slice work, **do not create push-triggered CI that is expected to fail repeatedly**. Run Godot/headless/unit tests locally in the implementation session whenever possible. If remote CI is needed before the baseline is stable, keep it manual with `workflow_dispatch`. Enable automatic push/PR CI only after the baseline suite is consistently green. If a CI change starts producing repeated failed runs, return it to manual-only until fixed.

GitHub email delivery itself is controlled by GitHub account/repository notification settings; this rule prevents the main avoidable source of spam: repeated failing Actions runs.

## Phase 12 implementation ladder

### 12A — Technical Bootstrap
Build the project shell and deterministic foundation before content volume.

Required work:
- pin/evaluate the frozen Godot 4.7.1-stable direction before codebase lock;
- establish GDScript-first project structure;
- separate Domain Core, Application Services, Presentation and Platform Adapters;
- define canonical stable-ID data types and immutable content-version envelope;
- implement canonical serialization/hash test helper;
- create semantic command interface with expected pre-state hash;
- create minimal content-schema loader/validator;
- create headless test entrypoint/CI-compatible command;
- create action-based input abstraction and persistence skeleton;
- create minimal runnable shell that boots without Steam/platform services.

Exit gate:
- project boots cleanly;
- headless tests execute;
- domain has no presentation dependency;
- canonical hash of a tiny fixture is reproducible;
- content validator can reject malformed stable IDs/schema;
- implementation status records exact bootstrap state.

### 12B — Vertical Slice
Implement one complete playable micro-dossier with tiny content, not the full campaign.

Minimum slice:
- dual map/world representation;
- snapped road add/remove;
- one Direct Courier;
- legal-vs-bad-edit distinction;
- deterministic A–I transaction order;
- one bounded reaction beat;
- one objective + one invariant where useful;
- causal ribbon/Inspect explanation;
- exact Undo/Redo checkpoint restoration;
- save/reload of active dossier;
- mouse+keyboard plus one non-mouse semantic path early enough to prove input architecture.

Exit gate:
- complete inspect -> edit -> consequence -> inspect -> revise -> clear loop is playable;
- same starting state + same commands reproduces identical transaction/final hashes;
- bad legal edit commits while structurally illegal edit does not;
- Undo returns byte-equivalent canonical pre-edit state;
- slice can be tested headlessly without presentation.

### 12C — Core Systems Complete
Implement the full frozen domain vocabulary and cross-system behavior before campaign population.

Required systems include:
- all six primitive families;
- exact legality pipeline;
- A–I resolution order;
- A1..A10 canonical archetypes;
- deterministic path/target/movement tie-breaks;
- trapped-state rules;
- simultaneous intent/apply reaction beats;
- objective/invariant families;
- Stability with P10-R3 temporal justification support;
- interrupted Stability rollback to exact pre-verification checkpoint;
- intervention-footprint semantics;
- causal DAG + P10-R6 presentation data budget support;
- linked-map one-way authority DAG;
- stale/double command idempotency;
- atomic/versioned persistence and corruption recovery;
- demo import mapping primitives;
- content validation obligations from the final freeze.

Exit gate:
- canonical mechanical acceptance fixtures pass headlessly;
- no gameplay result depends on frame time, physics contact order, scene order, hash iteration, OS locale, wall clock, platform identity or uncontrolled RNG;
- linked authority cannot cycle or double-own a target fact;
- persistence/recovery tests pass for edit, Undo/Redo and interrupted Stability.

### 12D — Content Population
Populate the frozen authored content structure using data, not dossier-specific rule scripts.

Required scope:
- D01–D40 campaign definitions and prerequisite/tutorial tags;
- 12 remix cases in three frozen packs;
- DEMO01–DEMO05 exact teaching sequence;
- 10 archetype roster within frozen use ceilings;
- 12 objective/invariant families only;
- four-layer absolute dossier ceiling;
- maximum two simultaneous editing surfaces in presentation contract;
- reasoning-transformation tags and diversity windows P10-R1;
- semantic non-dominance checks P10-R2;
- Stability reason/transition metadata P10-R3;
- mastery distinction metadata P10-R4;
- linked-chain readability metadata P10-R5;
- causal-chain compressibility P10-R6;
- deterministic focus graph P10-R7;
- remix changed-dependency metadata P10-R10;
- known solution-envelope regression fixtures.

Exit gate:
- all campaign/demo/remix content passes automated schema/authority/focus/prerequisite/replay/hash checks;
- D40 is reachable with zero mastery marks through baseline prerequisite clears;
- demo-to-full equivalence never inferred by name/ID alone;
- no dossier-specific script overrides canonical primitive or agent behavior.

### 12E — UX / Accessibility / Controller / Deck
Implement the complete frozen interaction and presentation contract.

Required paths:
- mouse+keyboard;
- keyboard-only;
- controller-only;
- Steam Deck built-in controls at 1280×800;
- remappable semantic gameplay actions;
- deterministic authored logical focus graph;
- dual map/world correspondence;
- case rail/goals/invariants;
- causal ribbon with <=5 default material nodes and <=2 visible siblings;
- Inspect routes/permissions/tie-break explanation;
- history/Undo/Redo UX;
- Stability controls and interruption messaging;
- linked-layer breadcrumb/authority source jumps;
- reduced motion/flashing;
- UI scaling;
- no-color/no-audio equivalents;
- localization-safe layouts.

Exit gate:
- every required gameplay path is completable with each required input mode;
- capture/interaction sweep passes 1280×800, grayscale/non-color, reduced motion and no-audio modes;
- no mandatory hover, right-click, wheel, drag-only, freehand, timed-reflex, color-only, audio-only or animation-only fact exists.

### 12F — Adversarial QA
Attack the implemented contract rather than merely replaying happy paths.

Required attacks:
- illegal versus harmful legal edits;
- duplicate/stale commands;
- rapid input during transaction presentation;
- Undo/Redo branch truncation;
- save corruption/newest-valid-generation recovery;
- process death during edit presentation and Stability verification;
- divergent Cloud active branches without illegal synthesis;
- demo import replay/idempotency/version mismatch;
- authority cycles/double ownership;
- focus-graph unreachable candidates;
- relabel universal-shortcut probes;
- blind enumeration versus causal reasoning fixtures;
- mastery/remix validation bypasses;
- linked-layer readability budgets;
- high-descendant causal graphs;
- controller/Deck dense-candidate navigation;
- performance and memory under maximum canonical dossier ceilings.

Exit gate:
- no known spec-breaking blocker remains;
- regression suite covers each fixed high-risk class;
- unresolved empirical questions are explicitly separated from bugs/spec violations.

### 12G — Empirical Design Gates
Run prototype/playtest obligations frozen in `GAME2_PHASE11_FINAL_FREEZE.md`.

At minimum evaluate E1–E12:
- map->world comprehension;
- second-order prediction;
- mature reasoning versus blind enumeration;
- campaign repetition;
- linked-authority comprehension;
- causal readability;
- accessibility/device sweep;
- marketing expectation;
- remix distinctness;
- agent distinctness;
- demo timing;
- perceived value/final pricing near release.

A failed empirical gate is not permission for broad redesign. Record evidence and reopen only the minimum affected canonical rule/content instance.

Exit gate:
- each empirical gate has evidence and disposition: pass, targeted canonical amendment implemented+retested, or explicit release blocker.

### 12H — Release Candidate
Prepare a reproducible candidate build and final release contract.

Required work:
- full regression/headless suite;
- deterministic replay fixture sweep;
- performance/compatibility checks;
- save migration/recovery regression;
- controller/Deck/accessibility regression;
- demo build + import compatibility;
- Steam Cloud/Achievements integration if still in frozen release scope;
- supported localization build checks;
- packaging/export reproducibility;
- release checklist/store capability claims matched to real implementation;
- final pricing/market comparison recheck near release.

Exit gate:
- release-candidate build exists and is reproducible;
- no known release-blocking canonical/test failure remains;
- IMPLEMENTATION COMPLETE may become YES only after all preceding gates pass.

## Hard implementation rules
- Keep simulation deterministic and testable outside presentation.
- Prefer full correctness/recomputation over clever incremental state mutation when outputs could diverge.
- Content must be data-driven within the frozen schemas and ceilings.
- Build validation tooling early; do not wait until 40 dossiers exist.
- One accepted player edit is one canonical transaction/history entry.
- Derived consequences never become separate intervention score/history actions.
- Experiment/Undo count is never baseline/mastery punishment.
- Stability interruption after process death rolls back to exact pre-verification checkpoint.
- Cloud never synthesizes divergent active dossier branches.
- Demo import is explicit, versioned, monotonic and idempotent.
- Accessibility settings never alter deterministic gameplay rules.

## Completion condition
Do not report the game finished because the core systems exist or the campaign loads.

`IMPLEMENTATION COMPLETE = YES` requires:
- 12A–12H exit gates satisfied;
- campaign/demo/remix content populated and validated;
- all required UX/input/accessibility paths working;
- persistence/recovery/Cloud/demo import verified;
- adversarial QA complete;
- empirical gates dispositioned;
- regression clean;
- a reproducible release candidate.
