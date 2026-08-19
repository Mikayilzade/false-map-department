# GAME #002 — FALSE MAP DEPARTMENT — UX / PRESENTATION ARCHITECTURE

Last updated: 2026-08-18
Factory run: **8**
Phase: **6 — UX / Presentation Architecture**
Product thesis: **LOCKED**
Mechanical architecture: **COMPLETE ON PAPER**
Content architecture: **COMPLETE ON PAPER**
DESIGN COMPLETE: **NO**

This file is the canonical Phase-6 interaction and presentation contract. It presents the existing Phase-4/5 rules without inventing new gameplay. When presentation and mechanics conflict, `GAME2_MECHANICAL_ARCHITECTURE.md` wins unless that phase is explicitly reopened.

---

# 1. UX goals

The interface must make five things continuously legible:
1. what map fact the player is about to change;
2. which world fact is causally paired with it;
3. why an edit is legal or structurally illegal;
4. what changed because of an accepted edit;
5. why the current dossier does or does not satisfy its requirements.

The desired interaction rhythm is **inspect -> hypothesize -> edit -> watch bounded consequence -> inspect ancestry -> revise**, with no submit button and no hidden time pressure.

The interface must never make the player solve cursor precision, remember undocumented icon meanings, or infer a failure from animation alone.

---

# 2. Application and screen-state hierarchy

## 2.1 Boot flow
`Boot -> accessibility-first setup on first launch -> title -> profile/save selection if needed -> Department Desk -> dossier -> completion/replay`.

First-launch setup exposes before gameplay:
- text/UI scale;
- reduced motion;
- flash reduction;
- color-vision-safe patterns enabled by default;
- subtitle/text-event presentation;
- controller glyph family / automatic input detection.

No cinematic is required before the player can interact.

## 2.2 Title
Primary actions:
- Continue;
- Department Desk;
- Settings;
- Accessibility;
- Credits;
- Quit on desktop.

`Continue` loads the latest safe dossier checkpoint or Department Desk if no dossier is active.

## 2.3 Department Desk
The campaign selection surface is a compact filing desk / case ledger, not a walkable hub.

Each dossier card shows:
- dossier number/title;
- cleared / uncleared;
- mastery marks earned, if any;
- new-system teaching tag only when relevant;
- replay availability.

Locked future dossiers show only the minimum progression requirement; no fake currencies or grind gates.

## 2.4 Dossier state machine
`Brief -> Inspect/Edit -> Resolution -> Inspect/Edit -> Stability Preview when eligible -> Completion`.

Pause can overlay any non-transition state. Resolution may be visually accelerated/reduced but the deterministic transaction must finish before another edit commits.

## 2.5 Completion
Completion shows:
- baseline clear;
- optional mastery results: Clean Intervention / Civic Care / Stable Authority only when authored for that dossier;
- final intervention footprint;
- one compact causal summary of the decisive final edit or stability chain;
- Replay / Next Dossier / Department Desk.

Raw Undo count, failed experiments and time spent are not scored.

---

# 3. Canonical dossier layout

## 3.1 Desktop default
Default landscape layout:
- **map pane**: 50–55% width;
- **world pane**: 30–35%;
- **case rail**: 15–20%, collapsible;
- persistent top utility strip for history, Stability and pause/settings.

The map is the primary editing surface. The miniature world is not decorative: it is an inspectable causal twin.

A draggable divider may adjust map/world proportion inside safe minimums, but layout choice never changes simulation.

## 3.2 Focus modes
Player may focus Map or World to ~75–85% of usable area. The paired pane remains as a live thumbnail unless explicitly hidden by an accessibility option. Selecting an object in either pane selects its causal counterpart in the other.

A `Correspondence` command instantly frames the selected pair on both sides.

## 3.3 Steam Deck 1280×800
Default Deck layout uses map ~58%, world ~42%, with the case rail as a slide-over panel. Persistent goals collapse to status chips. Minimum interactive target is 44 logical px; essential text must remain readable at the default scale without horizontal scrolling.

No dossier may require simultaneous reading of four tiny linked maps.

---

# 4. Visual correspondence grammar

Every authoritative primitive has the same identity token across map and world:
- road: line + road icon;
- bridge: bridge glyph + matching crossing highlight;
- border: patterned boundary + jurisdiction crest;
- waterway: directional/segment line + wave glyph;
- landmark: marker silhouette + semantic label token;
- restricted zone: hatch pattern + permission icon.

On hover/focus/select:
1. source primitive receives a solid selection outline;
2. its world counterpart receives the same shape-coded pulse;
3. a thin transient correspondence tether may connect panes when it does not cross critical text;
4. accessible text states `Map: Border B12 -> World: North/South jurisdiction boundary` or equivalent.

Color is supplemental only. Shape, pattern, icon and text carry meaning.

---

# 5. Input model

All six primitives must be fully operable by mouse+keyboard, keyboard-only and controller-only. There is no mandatory freehand input.

## 5.1 Mouse + keyboard
- pointer selects candidate/node/cell;
- left click confirms/selects;
- right click cancels/back;
- wheel zooms focused pane;
- middle drag or Space+drag pans;
- number/tool hotkeys may select available primitive family;
- Ctrl/Cmd+Z Undo, Ctrl/Cmd+Y or Shift+Ctrl/Cmd+Z Redo;
- Tab cycles major regions;
- F focuses correspondence pair;
- Space pauses/steps Stability when context permits.

Exact bindings remain remappable.

## 5.2 Keyboard-only
The map exposes a logical focus graph, not pixel cursor emulation.
- arrows/D-pad-equivalent move between nearest legal candidates in cardinal direction;
- Tab/Shift+Tab move between UI regions;
- Enter/Space select/confirm;
- Escape cancels/back;
- tool-family commands cycle only dossier-available primitives;
- a `Next affected object` command cycles causal descendants after resolution.

When a tool needs two endpoints, focus first endpoint -> confirm -> legal second endpoints become focusable -> confirm.

## 5.3 Controller
- left stick/D-pad moves logical map focus;
- right stick pans focused pane; triggers zoom;
- A confirm/select;
- B cancel/back;
- X opens Inspect/causal detail;
- Y toggles Map/World focus;
- LB/RB cycle available primitive families or linked layers depending context;
- LT/RT may cycle history / causal events when no edit gesture is active;
- Menu pauses.

All bindings are remappable and glyphs update to active device.

## 5.4 Primitive interaction patterns
Road/waterway: select legal edge or first/second snapped node depending authored candidate representation; preview exact resulting segment before commit.

Bridge: focus legal crossing slot; confirm add/remove.

Border: select a legal boundary segment/cell transfer affordance; preview resulting ownership pattern before commit. No polygon drawing.

Landmark: select landmark, then choose allowed semantic label from a short radial/list selector; no arbitrary typing.

Restricted zone: toggle authored candidate cell/region through focus selection; preview hatch delta before commit.

---

# 6. Selection, snapping and edit preview

## 6.1 Three candidate states
- **legal candidate**: normal snap affordance;
- **selected preview**: strong outline plus ghosted before/after state;
- **structurally illegal candidate**: may be inspectable but cannot commit; reason is available immediately.

Objective-harming edits are never shown as structurally illegal merely because they are bad solutions.

## 6.2 Preview scope
Before commit, preview only direct authoritative/structural result that follows without advancing agents: e.g. road present/absent, jurisdiction ownership, bridge support, semantic label. Do **not** preview the full future solution or enumerate all downstream agent consequences; those remain the reasoning game.

## 6.3 Invalid feedback
A rejected edit gives:
- no state mutation;
- short non-punitive visual refusal;
- text reason tied to the exact rule, e.g. `No legal crossing slot here`;
- focus remains on the attempted candidate.

No buzzer-only explanation.

---

# 7. Dossier brief and requirement display

The Brief contains:
- one-sentence civic situation;
- primary goals;
- protected invariants explicitly separated from goals;
- available edit families;
- any dossier-visible special permission/authority rule;
- optional mastery contracts in a secondary section.

During play the case rail shows compact requirement rows with four states:
- satisfied;
- currently broken;
- stability pending;
- not yet evaluable.

A row expands to plain-language predicate explanation and relevant subjects/targets. Maximum presentation follows Phase-5 clause ceilings; the UI must not decompose one coherent civic requirement into a wall of machine predicates.

Mastery is visually subordinate until baseline requirements are understood.

---

# 8. Agent inspection

Selecting an agent opens an Inspect card containing only mechanically relevant facts:
- name/icon/archetype-readable role;
- current state;
- current semantic target;
- current jurisdiction and permission status;
- zone permission tags in plain language;
- intended route highlighted on the relevant map/world network;
- if blocked/trapped, the first blocking fact;
- deterministic tie-break explanation when multiple destinations/routes are plausible.

The card must answer `Why is this agent going there?` without exposing implementation jargon.

Example explanation hierarchy:
`Courier seeks Hospital -> two Hospital labels exist -> East Hospital is nearest reachable -> route uses Bridge B3.`

---

# 9. Causal feedback and ancestry

## 9.1 Resolution presentation
After an accepted edit:
1. edited map primitive flashes once;
2. directly changed world facts animate/pulse;
3. affected agents show short reaction beats;
4. requirement rows update;
5. control returns after configured bounded resolution.

Animations are serialized enough to read but may overlap where causal independence is obvious. Simulation semantics remain simultaneous per Phase 4.

## 9.2 Causal ribbon
The latest transaction is summarized as a horizontal/vertical causal ribbon:
`Your edit -> derived fact -> agent interpretation -> movement/state -> objective/invariant effect`.

Only the shortest relevant chain is shown initially. Expand reveals siblings/alternate descendants.

If an invariant breaks, the UI pins the **first relevant broken invariant** and its ancestry rather than dumping every changed fact.

## 9.3 No spoiler oracle
Causal tools explain events that have occurred/current derived facts. They may show an agent's current intended route. They may not:
- rank untried edits;
- reveal hidden known solutions;
- enumerate every legal move;
- forecast arbitrary multi-edit futures.

---

# 10. Undo / Redo and history

The top history strip represents accepted player edits as discrete cards/icons. Derived consequences live inside the parent edit and never appear as separate player interventions.

Undo:
- restores authoritative map, simulation state, causal graph and Stability state to the exact pre-edit checkpoint;
- is immediate except for a short optional reverse transition;
- never costs mastery by itself.

Redo reapplies the exact undone edit transaction when history has not branched. Making a new edit after Undo discards the redo branch after confirmation only if losing a meaningful branch would surprise the player; otherwise standard linear-history semantics apply.

Two counters are deliberately separate:
- **Experiment history**: UI history for navigation/learning; never scored.
- **Final intervention footprint**: canonical final-state intervention metric from Phase 4/5; used only by authored mastery contracts.

Completion never displays `You used 27 undos` as judgment.

---

# 11. Stability Preview

When all baseline requirements are currently satisfied and the dossier requires Stability cycles, the Stability control becomes prominent but does not auto-run without clear player intent.

Controls:
- Start/Resume;
- Pause;
- Step one beat/cycle unit as defined by mechanics;
- speed 1× / 2× / 4×;
- reduced-animation instant presentation while still exposing textual causal events.

During Stability:
- editing is disabled until paused/exited;
- requirement states remain visible;
- progress reads `Stable 2 / 4 cycles`;
- first broken requirement pauses the preview by default and opens its causal ancestry;
- player may Undo back to the prior edit checkpoint.

Successful required window transitions directly to completion after a short confirmation beat. No reflex input is required.

---

# 12. Linked-map UX

Linked maps are introduced only according to Phase 5.

## 12.1 Layer navigator
A persistent layer breadcrumb shows scale and authority, e.g. `Region > Canal Borough`. Each layer has a stable icon/name. Authority-owned facts display a small `authoritative here` stamp; projected facts display `derived from Region` and link to source.

## 12.2 Two-surface ceiling
At most two editing surfaces are visible simultaneously. When a dossier contains 3–4 layers, remaining layers are tabs/breadcrumb destinations, never four tiny simultaneous maps.

## 12.3 Cross-layer consequence
A change that projects to another layer triggers:
- source-layer edit highlight;
- target-layer tab badge;
- optional picture-in-picture pulse;
- causal ribbon entry `Regional connector changed -> District portal availability changed`.

Selecting that event jumps to and frames the affected target fact.

No cross-layer relation may require remembering which layer owns a fact; ownership is always inspectable.

---

# 13. First-session onboarding

Tutorials are embedded in dossiers, not a separate lecture.

D01 sequence:
1. blocked courier/world and matching map route are already visible;
2. one legal road edit target is highlighted after brief observation;
3. player commits it;
4. world correspondence animates immediately;
5. player is asked to inspect the courier route once;
6. next micro-problem requires removing/changing a road without a step-by-step answer.

Teaching rules:
- teach one interaction, then require transfer;
- tooltips disappear once demonstrated and remain recoverable in Help;
- no modal text longer than a short paragraph during active puzzle flow;
- hints explain causal rules before suggesting a location;
- final hint tier may identify the conflicting requirement/system but does not prescribe the full move sequence unless accessibility/easy-assist mode later explicitly allows it.

---

# 14. Demo UX contract

Demo target remains 15–25 minutes and obeys Phase-5 content boundary.

Demo must visibly deliver:
1. immediate road/map -> world causality;
2. bridge/water correspondence;
3. border or restricted-zone interpretation difference;
4. one collateral consequence where helping one agent harms another requirement;
5. causal ancestry explaining that consequence;
6. one satisfying multi-system dossier clear.

Demo excludes landmark relabeling, editable waterways, Ferry, Procession, Commercial chains and linked maps.

End card sells the escalation in concepts, not a feature checklist: `Later cases connect districts, jurisdictions and maps at different scales.`

---

# 15. Accessibility contract

Required for 1.0:
- UI scale presets plus safe custom range where feasible;
- readable default at 1280×800;
- no color-only state; jurisdiction/zone/status use pattern+icon+text redundancy;
- reduced motion mode removes camera swoops, tether sweeps and large world morphs while preserving state transitions;
- flash reduction limits high-contrast pulses and repeated flashes;
- all essential audio events duplicated visually/textually;
- master/music/SFX/UI volume independently adjustable;
- subtitles/text event log for any voiced or meaningful sound cue;
- remappable keyboard/controller actions;
- keyboard-only and controller-only completion;
- hold/toggle options where continuous input exists;
- no mandatory timed input;
- pause during all reasoning states and Stability Preview;
- font designed for clear mixed-case reading; avoid tiny all-caps bureaucratic styling for body text;
- tooltip/help text supports localization expansion; layouts must tolerate at least ~35% text expansion without clipping.

Patterns must remain distinguishable in grayscale screenshots.

---

# 16. Audio and animation language

Audio supports causality but never carries unique information.

Map side:
- paper/stamp/pencil/filing tactile sounds per primitive family.

World side:
- compact physical confirmation sounds for road/bridge/water/border/permission changes;
- agent acknowledgement/state sounds kept short and non-overlapping.

Causal chain:
- root edit has one signature cue;
- direct derived changes share a softer related cue;
- broken invariant uses a distinct but non-alarming cue paired with visible text/icon.

Animation budget:
- accepted edit direct transformation ideally readable in <1 s;
- each reaction beat normally 0.3–0.8 s at 1× presentation;
- full bounded resolution should not feel like waiting; speed/reduced-animation settings must preserve semantics.

World transformations should favor readable symbolic morphs over expensive bespoke cinematics.

---

# 17. Pause, settings, save/load and recovery UX

## 17.1 Pause
Pause menu:
- Resume;
- Restart Dossier;
- Settings;
- Accessibility;
- Help / Rule Glossary;
- Department Desk;
- Quit.

Restart and leaving an active dossier require confirmation only when unsaved active-state loss would occur.

## 17.2 Autosave presentation
Autosave indicator appears unobtrusively after safe state changes. Persistence semantics are finalized in Phase 8, but UX requires recovery at least at safe dossier checkpoints and must never imply an edit is saved before persistence succeeds.

## 17.3 Recovery
If an interrupted session can be restored exactly, `Continue` states dossier and checkpoint. If corruption/version mismatch prevents exact restore, the game falls back to the last verified safe checkpoint and explains this plainly; it never fabricates a partially reconstructed state.

## 17.4 Failure
There is no punitive game-over screen for ordinary broken requirements. A legal bad edit leaves the dossier active, marks the broken requirement, and offers ancestry/Undo. A dossier becomes `not currently completable` only if the authored rules explicitly allow such a legal state; Restart remains available.

---

# 18. Help / rule glossary

The glossary is generated from canonical rule vocabulary and unlocked as concepts are introduced. Each entry contains:
- symbol;
- plain-language mechanical meaning;
- what it does not mean where ambiguity is likely;
- one tiny non-solution example;
- links to agent archetypes that interpret it specially.

The glossary never contains dossier solution walkthroughs by default.

---

# 19. Presentation risks and empirical gates

## R6-1 — Split attention overload
Risk: players watch only map or only world.
Gate: in graybox, >=80% of naive testers should correctly identify the paired world consequence of a highlighted map edit after D01 without prompting.

## R6-2 — Causal ribbon becomes spoiler/noise
Gate: testers should use it to explain failures without reporting that it solves the next move for them; if it becomes an oracle, collapse to occurred-event ancestry only.

## R6-3 — Controller graph navigation friction
Gate: controller-only tester can complete D01–D04 without pointer emulation and without >2 accidental candidate selections per dossier median after tutorial.

## R6-4 — Deck density
Gate: 1280×800 default UI keeps all critical requirement text, selected-agent reason and edit affordances readable without mandatory magnification.

## R6-5 — Late linked-map memory burden
Gate: testers can answer `which layer owns this fact?` correctly in >=90% of sampled Act-IV graybox moments using UI alone.

## R6-6 — Resolution feels slow
Gate: repeated edits should return meaningful control fast enough that testers do not describe the reaction sequence as waiting; presentation speed controls must not change results.

These are implementation/playtest gates, not permission to leave interaction semantics undefined.

---

# 20. Phase-6 acceptance tests

**U6-01** First boot exposes accessibility before mandatory gameplay.
**U6-02** Dossier can be entered from Department Desk without a walkable hub.
**U6-03** Every editable map object can frame its world counterpart and vice versa.
**U6-04** No critical state relies on color alone.
**U6-05** All six primitives are editable mouse+keyboard without freehand precision.
**U6-06** All six primitives are editable keyboard-only through logical focus.
**U6-07** All six primitives are editable controller-only without virtual mouse requirement.
**U6-08** Structurally illegal edit never mutates state and exposes exact reason.
**U6-09** Legal but harmful edit commits normally and is not styled as input error.
**U6-10** Pre-commit preview shows direct structural delta but not a multi-step solution forecast.
**U6-11** Goal and invariant are visually distinguishable and inspectable before editing.
**U6-12** Optional mastery never obscures baseline completion requirements.
**U6-13** Agent inspect answers target, permissions, intended route and first blocking fact.
**U6-14** Duplicate semantic target resolution can be explained in UI using deterministic rule.
**U6-15** Accepted edit presentation preserves Phase-4 resolution semantics independent of animation speed.
**U6-16** First broken invariant can open causal ancestry rooted at the responsible player edit.
**U6-17** Derived consequence is nested under parent history edit and does not count as player intervention.
**U6-18** Undo restores exact prior inspectable state; Redo restores exact undone transaction when branch is intact.
**U6-19** Experiment history is never used as mastery score.
**U6-20** Stability Preview supports pause, step and speed changes without changing deterministic result.
**U6-21** Stability failure identifies first broken requirement and offers ancestry/Undo.
**U6-22** Linked-map UI always identifies authoritative source versus projection.
**U6-23** No more than two editable map surfaces are simultaneously presented.
**U6-24** Cross-layer causal event can navigate from source to affected target.
**U6-25** D01 teaches correspondence through action, then requires unprompted transfer.
**U6-26** Demo includes a second-order collateral consequence within 15–25 minute target.
**U6-27** Demo contains none of the Phase-5 excluded advanced systems.
**U6-28** Deck 1280×800 layout is playable with case rail collapsed/expanded and no required horizontal scrolling.
**U6-29** Reduced-motion mode preserves all causal information.
**U6-30** No-audio play preserves all goals, warnings and causal explanations.
**U6-31** Critical actions are remappable for keyboard and controller.
**U6-32** Pause/settings/help are reachable during reasoning without advancing simulation.
**U6-33** Ordinary bad edits never trigger punitive game-over; player can inspect, Undo or Restart.
**U6-34** Recovery messaging never claims an unsafely reconstructed state is exact.
**U6-35** Glossary explains canonical rules but does not reveal dossier solutions.
**U6-36** Localization-safe layouts tolerate approximately 35% text expansion in critical panels.

---

# 21. Phase-6 closure decision

- Screen/state hierarchy defined: **YES**
- Map/world correspondence defined: **YES**
- Desktop/Deck layout contract defined: **YES**
- Mouse+keyboard defined: **YES**
- Keyboard-only defined: **YES**
- Controller-only defined: **YES**
- Six primitive interaction patterns defined: **YES**
- Snapping/preview/invalid semantics defined: **YES**
- Goals/invariants/mastery presentation defined: **YES**
- Agent inspection defined: **YES**
- Causal feedback/ancestry defined: **YES**
- Undo/Redo presentation defined: **YES**
- Stability Preview UX defined: **YES**
- Linked-map UX defined within Phase-5 ceiling: **YES**
- First-session/demo UX defined: **YES**
- Accessibility/no-audio/reduced-motion defined: **YES**
- Pause/settings/recovery/failure flows defined: **YES**
- Audio/animation language defined: **YES**
- UX acceptance tests defined: **YES — U6-01..U6-36**
- Earlier gameplay phase reopened: **NO**
- Phase 6 complete on paper: **YES**
- DESIGN COMPLETE: **NO**

## NEXT PHASE
**Phase 7 — Economy / Retention / Commercial Model.**

The next run should research current premium indie puzzle pricing/store/demo expectations where useful, then freeze price-position hypothesis, campaign unlock structure, mastery/replay incentives, remix unlocks, achievements, difficulty/assist philosophy, demo-to-full conversion boundary, Steam/platform feature scope, monetization exclusions, retention without grind, commercial scope risks and Phase-7 acceptance tests. Do not add a progression currency, daily system, live-service loop or gameplay mechanic merely to manufacture retention.