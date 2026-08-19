# GAME #002 — FALSE MAP DEPARTMENT — ECONOMY / RETENTION / COMMERCIAL MODEL

Last updated: 2026-08-18
Factory run: **9**
Phase: **7 — Economy / Retention / Commercial Model**
Product thesis: **LOCKED**
Mechanical architecture: **COMPLETE ON PAPER**
Content architecture: **COMPLETE ON PAPER**
UX / presentation architecture: **COMPLETE ON PAPER**
DESIGN COMPLETE: **NO**

This file is the canonical Phase-7 commercial/progression contract. It does not add gameplay primitives or alter deterministic rules. If a commercial idea would require changing the six edit families, agent semantics, dossier ceilings or UX accessibility guarantees, that earlier phase must be explicitly reopened instead of silently changed here.

---

# 1. Commercial thesis

False Map Department is a **premium single-player systemic puzzle game**, not a retention service.

The product earns value from:
- a distinctive executable-map hook;
- 40 authored campaign dossiers with escalating causal depth;
- 12 bounded remix cases using existing validated systems;
- optional mastery marks that reward elegant final states without punishing experimentation;
- replay driven by understanding, alternative solutions and self-improvement;
- a strong demo that demonstrates the map->reality causal fantasy quickly.

It must not manufacture engagement through currencies, grind, daily obligations, artificial scarcity or recurring monetization.

---

# 2. Price-position hypothesis

## 2.1 Current reference snapshot — August 2026

Current Steam list-price references used for positioning:
- **Map Map — A Game About Maps**: US list price **$14.99**, released 2026-05-28. It is the closest current thematic/cartography reference, though mechanically different.
- **Strange Horticulture**: US list price **$15.99**; compact premium single-player investigation/puzzle-adjacent experience with a strong desk/interface fantasy and demo.
- **Paper Trail**: US list price **$19.99**; polished authored puzzle adventure with Steam Achievements, Steam Cloud and controller support.
- **A Monster's Expedition**: US list price **$19.99**; premium authored systemic puzzle game with broad language support, achievements and cloud saves.
- **Viewfinder**: US list price **$24.99**; higher-production reality-rewriting puzzle/adventure whose presentation burden and 3D production are materially above this project.

Sources checked 2026-08-18:
- https://store.steampowered.com/app/2702260/Map_Map__A_Game_About_Maps/
- https://store.steampowered.com/app/1574580/Strange_Horticulture/
- https://store.steampowered.com/app/1889740/Paper_Trail/
- https://store.steampowered.com/app/1052990/A_Monsters_Expedition/
- https://store.steampowered.com/app/1382070/Viewfinder/

## 2.2 Positioning hypothesis

**Design-time target list-price band: US $14.99–$19.99.**

**Working center hypothesis: $17.99**, contingent on final polish, campaign length, localization breadth and playtest-perceived value.

Reasoning:
- $14.99 is defensible if final scope lands near the lower campaign-duration bound or production presentation is deliberately minimal.
- $17.99 better signals a substantial premium puzzle product if 40 dossiers + 12 remixes sustain 5–8 strong first-clear hours plus mastery.
- $19.99 is defensible only if late-game depth, polish, controller/Deck UX, localization and demo conversion all support the comparison with established premium puzzle titles.
- $24.99 is not the current design target because the game deliberately avoids Viewfinder-scale 3D spectacle and content production.

This is a **hypothesis, not a release-time price lock**. Final pricing must be rechecked against the market near release.

## 2.3 Discount philosophy

No launch-discount percentage is frozen in design. Discount cadence is commercial release work. The design requirement is simply that the base game be complete and fairly priced without requiring a permanent sale to appear viable.

---

# 3. Progression without economy

There is **no spendable progression currency** in 1.0.

No coins, XP shop, stars-as-currency, tool upgrades, energy, lives or consumable hints are permitted.

Campaign progression is knowledge-gated and milestone-gated:
- clearing a dossier records baseline completion;
- optional mastery marks are prestige/goal records, not keys required for ordinary campaign completion;
- future dossiers unlock through authored predecessor clears, never repeated farming;
- all six canonical primitives unlock through campaign teaching order, not purchase or grinding.

## 3.1 Campaign unlock graph

To keep navigation flexible without allowing tutorial skips that break comprehension:

- **D01–D04:** strict sequential unlock.
- **D05–D08:** each unlocks when the immediately preceding dossier is cleared.
- **Act II (D09–D16):** D09 unlocks on D08 clear; thereafter two-dossier local choice windows are allowed: clearing either dossier in a pair can expose the next pair only after both prerequisite teaching tags needed by that next pair are satisfied.
- **Acts III–V:** campaign may present 2–3 simultaneously available dossiers, but every dossier has explicit prerequisite `tutorial_tags`; no dossier may unlock unless all required tags have been demonstrated in cleared predecessors.
- **D40:** requires baseline clear of all required Act-V synthesis prerequisite dossiers, not every mastery mark.

Phase 8 must encode this as data, not hardcoded menu logic.

## 3.2 No mastery gate for baseline ending

A player can reach and clear D40 with **zero optional mastery marks** as long as required campaign dossiers are baseline-cleared.

This is non-negotiable. Mastery must never become disguised grind.

---

# 4. Optional mastery structure

Phase 6 established three mastery families. Phase 7 freezes their commercial/retention role:

1. **Clean Intervention** — satisfy an authored final-intervention-footprint threshold.
2. **Civic Care** — satisfy an authored collateral/protected-state excellence condition beyond baseline.
3. **Stable Authority** — satisfy an authored stronger stability condition using the same deterministic rules.

Rules:
- not every dossier needs all three;
- no mastery condition may score raw Undo count, elapsed time or failed experiments;
- mastery checks final solution/result state, not learning history;
- mastery never grants stronger tools or mechanical power;
- mastery may unlock cosmetic Department Desk stamps/badges and achievement progress, but not campaign-critical content;
- dossiers may be replayed instantly after completion to pursue mastery.

Target campaign distribution:
- D01–D07: 0–1 mastery marks each, mostly hidden/subordinate until introduced;
- D08–D16: 1–2 each;
- D17–D40: 2–3 each where meaningful;
- remixes may expose 1–3 authored mastery marks.

The exact total number of obtainable marks is content-data output, not a currency balance.

---

# 5. Remix-case unlock policy

Phase 5 permits exactly **12 remix cases** in 1.0. Phase 7 freezes them as three packs of four using existing validated substrates and allowed parameter changes only.

## Pack R-A — Local Revisions (R01–R04)
Unlock condition: **clear D08**.
Purpose: replay early vocabulary with altered starting topology/agents/objectives after all local primitive concepts introduced in Act I are understood.

## Pack R-B — Department Appeals (R05–R08)
Unlock condition: **clear D24**.
Purpose: remix one-layer/early linked-system causal chains after Acts II–III are complete.

## Pack R-C — Atlas Corrections (R09–R12)
Unlock condition: **clear D40**.
Purpose: post-campaign expert remixes using linked authority within the Phase-5 ceiling.

Rules:
- no mastery threshold unlocks a remix pack;
- no random daily seed or time-limited rotation exists;
- every remix is permanently available once unlocked;
- remixes may not introduce a seventh primitive, new agent archetype or hidden rule;
- remix clears are optional and never required for campaign credits/ending;
- replay/reset is unlimited and cost-free.

---

# 6. Retention strategy

Retention means **players wanting another causal problem**, not obligation engineering.

Primary retention drivers:
- short 5–20 minute dossier cadence;
- regular interpretive escalation using familiar primitives;
- multiple valid final states where feasible;
- optional mastery after baseline clear;
- late linked-map authority that changes reasoning scale without changing core identity;
- 12 permanent remix cases;
- replay to discover cleaner or surprising alternate solutions;
- compact achievement goals that encourage underused legitimate play styles.

Explicitly forbidden:
- dailies;
- streaks;
- login rewards;
- battle passes;
- rotating shops;
- limited-time cases;
- FOMO events;
- energy/lives;
- push-notification engagement loops;
- endless procedural filler presented as required value.

There is no design KPI such as “daily active users” that may override puzzle quality.

---

# 7. Difficulty and assist philosophy

Accessibility and challenge are separate systems.

## 7.1 Accessibility

All Phase-6 accessibility/input guarantees are available at every challenge setting and **never reduce achievement/mastery legitimacy merely because they are used**:
- UI scaling;
- remapping;
- non-color redundancy;
- reduced motion/flashing;
- no-audio equivalents;
- keyboard-only/controller-only paths;
- pause/step controls;
- readable Deck layouts.

These are access features, not cheats.

## 7.2 Puzzle assists

The game uses one canonical ruleset. Assist options change **information/help**, not deterministic world semantics.

Three hint depths are available per dossier after its causal lesson has been introduced:
- **Rule Reminder** — restates the relevant known rule(s) and highlights the relevant requirement/subjects, not a move.
- **Conflict Focus** — identifies which systems are currently in causal conflict and which map layer contains an authoritative relevant fact.
- **Directional Hint** — may identify the primitive family or region worth reconsidering, but does not prescribe the complete edit sequence.

A final optional **Solution Guidance** mode may provide stepwise authored guidance for players who explicitly request it. It is never activated automatically and is not required for accessibility compliance.

Rules:
- baseline completion remains available after any hint depth;
- ordinary campaign achievements cannot be permanently blocked by using hints;
- mastery records may remain earnable because mastery verifies final state, not whether help was consulted;
- if the team later wants a “no hints” prestige achievement, Phase 10 must reject it unless it demonstrably adds value without shaming access needs. Default is **no such achievement**.

## 7.3 No hidden difficulty mutation

No assist silently changes:
- agent route logic;
- tie-breaks;
- edit legality;
- Stability cycles;
- objective predicates;
- map authority.

If an easier alternate dossier variant is ever needed, it must be separately authored/validated and is outside the frozen 1.0 target unless substituted for another content slot.

---

# 8. Demo-to-full-game boundary

Steam's current developer documentation describes demos as small playable portions intended to demonstrate core mechanics and support purchase decisions; demos are separate apps associated with the base game, and Steam Next Fest centers playable demos. This reinforces the existing Phase-5/6 decision that the demo must prove the actual hook rather than act as a detached prologue.

Current Steamworks references checked 2026-08-18:
- https://partner.steamgames.com/doc/store/application/demos
- https://partner.steamgames.com/doc/marketing/upcoming_events/nextfest
- https://partner.steamgames.com/doc/marketing/tools

## 8.1 Demo content

Target: **15–25 minutes** for a typical first-time player.

Use a curated demo sequence derived from early campaign substrates, equivalent in rules to **D01–D04 plus one compact synthesis case**, with pacing trimmed for demo clarity.

Must demonstrate:
1. direct road edit -> world change;
2. bridge/water crossing correspondence;
3. border or restricted-zone interpretation difference;
4. one beneficial edit causing a collateral problem;
5. causal ancestry explanation;
6. one multi-system success where the player forms a hypothesis rather than follows a tutorial script.

Demo excludes the Phase-6 exclusions: landmark relabeling, editable waterways, Ferry, Procession, Commercial chains and linked maps.

## 8.2 Demo progression transfer

Preferred implementation contract for Phase 8:
- demo stores a compact versioned completion record and settings profile;
- full game may import compatible demo settings and baseline clears for exact matching campaign dossiers/substrates;
- import is monotonic/idempotent and never removes fuller progress;
- if content/rules versions are incompatible, settings may still transfer while dossier clears do not;
- demo never grants mastery that was not actually validated against the same canonical dossier version.

This avoids forcing repeat play while keeping migration safe.

## 8.3 Demo ending

The demo ends after the first genuine second-order “aha,” not after a cliffhanger cutscene. End communication should emphasize escalation: later cases combine jurisdictions, semantic labels, services and linked maps at multiple scales.

No demo-exclusive mechanical content exists.

---

# 9. Steam / platform feature scope

## 9.1 Required for Steam 1.0

- single-player base game;
- full controller support in practice according to Phase 6;
- Steam Deck-targeted layout/support;
- **Steam Cloud** for progress/settings where technical architecture permits reliable conflict handling;
- **Steam Achievements**;
- demo app associated with base game;
- Family Sharing compatibility unless a platform constraint outside design prevents it;
- localized store/game text for the final supported language set chosen during production.

Steam's current documentation recommends clouded saves for games expected to move between Deck/PC, and Steam Cloud is the natural default for this project. Achievements are supported as persistent Steam-account rewards and can be used to encourage different play styles. Sources checked 2026-08-18:
- https://partner.steamgames.com/doc/features/cloud
- https://partner.steamgames.com/doc/features/achievements
- https://partner.steamgames.com/doc/steamdeck/recommendations

## 9.2 Explicit 1.0 exclusions

- Steam Workshop / user-generated dossier editor;
- online leaderboards;
- multiplayer/Remote Play Together as a designed mode;
- inventory items/trading economy;
- marketable items;
- trading-card dependency in design;
- community-market monetization;
- server backend;
- mandatory account outside Steam;
- live events.

Trading cards/profile extras may be considered near release only if trivial and platform-appropriate, but are not implementation requirements or retention pillars.

---

# 10. Achievement philosophy

Achievements should celebrate learning, completion and varied legitimate solution styles, not repetitive chores.

## 10.1 Target count

**20–24 Steam achievements** for 1.0, working target **22**.

This is intentionally bounded. A compact puzzle game does not need an achievement for every dossier.

## 10.2 Families

Suggested distribution:
- 5 act-completion milestones;
- 1 campaign completion achievement;
- 3–4 primitive/causal-discovery achievements tied to meaningful first use or consequence, not tutorial clicks;
- 4 mastery-family achievements based on accumulating representative Clean Intervention / Civic Care / Stable Authority accomplishments;
- 3 remix-pack / remix-completion achievements;
- 3–5 playful systemic achievements for unusual but legitimate causal outcomes that do not require grinding or opaque secrets.

Rules:
- no achievement requires login streaks or cumulative meaningless repetition;
- no achievement requires speedrunning/timing by default;
- no achievement requires playing without accessibility features;
- no achievement should incentivize intentionally corrupting save/history state;
- hidden achievements are reserved for genuine discovery/spoiler protection, not arbitrary obscurity;
- achievements do not unlock mechanical power.

---

# 11. Monetization and expansion boundary

## 11.1 Base game monetization

One premium purchase.

Explicit exclusions:
- microtransactions;
- cosmetic shop;
- paid hints;
- loot boxes/gacha;
- paid currencies;
- season pass dependency;
- subscription;
- ads;
- paid “energy” or retry systems.

## 11.2 DLC / expansion

No DLC is required to make 1.0 feel complete.

A future paid expansion is acceptable only after the base game proves demand and only if it provides a coherent substantial new casebook rather than withheld base content.

Preferred expansion shape:
- a new authored dossier set using the existing six primitives and core causal grammar;
- at most one deliberately designed new interpretation layer/family if it creates enough depth to justify reopening canonical design;
- new visual district theme(s) allowed if production budget supports them;
- no power creep or compatibility-breaking progression.

Bad expansion shapes:
- selling isolated puzzle cases one by one;
- paid map tools that make base puzzles easier;
- consumable hint packs;
- cosmetic bureaucracy store;
- live-season cadence.

---

# 12. Scope and commercial risks

## C7-R1 — Price/value mismatch
Risk: 40 dossiers may still feel short if too many are tutorial-thin or solved in one obvious edit.
Gate: pricing review must use actual median first-clear time, replay/mastery engagement and qualitative value perception near release.

## C7-R2 — “Cozy” positioning dilutes challenge identity
Risk: map aesthetic may attract relaxing-game buyers who then hit late causal complexity.
Gate: store/demo messaging must show both charm and second-order consequence reasoning before purchase.

## C7-R3 — Puzzle enthusiasts perceive unique-solution hunting
Risk: optional intervention mastery could imply one designer-approved answer.
Gate: representative late dossiers should retain multiple valid baseline states where mechanics permit; mastery is optional and framed as one style of excellence.

## C7-R4 — Demo over-teaches and undersells depth
Risk: a frictionless tutorial demo communicates novelty but not the real game.
Gate: demo must contain at least one genuine collateral consequence and one independent multi-system solution.

## C7-R5 — Remix content feels like padding
Risk: parameter-swapped cases appear as cheap duplication.
Gate: every remix must alter the dominant causal question, not merely move starts or tighten a number.

## C7-R6 — Achievements become grind surrogate
Risk: commercial checklist pressures design toward repetition.
Gate: every achievement must be satisfiable through meaningful campaign/remix/mastery play without farming arbitrary counts.

## C7-R7 — Hint system becomes spoiler oracle
Risk: retention improves short-term while core reasoning fantasy collapses.
Gate: first three hint depths never prescribe full move sequences; Solution Guidance is explicit opt-in and authored separately.

## C7-R8 — Platform feature creep
Risk: Workshop, leaderboards or online systems expand QA/backend burden before core game proves itself.
Gate: all such systems remain excluded from 1.0 unless a later explicit scope reopening replaces equivalent cost elsewhere.

---

# 13. Empirical commercial gates

These are prototype/release validation obligations, not undefined gameplay:

1. **Perceived value:** representative target players should consider the eventual list price fair after seeing actual scope/polish; price is rechecked near launch.
2. **Demo hook comprehension:** >=80% of representative demo testers can state that changing the official map changes reality, without prompting.
3. **Demo depth signal:** >=60% of representative demo testers can describe at least one second-order/collateral consequence they intentionally reasoned about.
4. **Demo desire:** qualitative exit interviews should show curiosity about later semantic/jurisdiction/linked-map escalation, not only satisfaction with the tutorial novelty.
5. **No grind dependency:** median campaign progression never requires replaying a cleared dossier unless the player voluntarily seeks mastery.
6. **Remix distinctness:** each remix should be judged by internal review as requiring a materially different causal hypothesis from its source substrate.
7. **Achievement quality:** no achievement survives final review if its only purpose is increasing hours played.
8. **Store positioning truth:** trailer/capsules/description must not imply city-builder, sandbox, open world or management depth excluded by Product Thesis.

---

# 14. Phase-7 acceptance tests

## E7-01 — Premium-only
The 1.0 design contains one premium purchase and no gameplay microtransaction system.

## E7-02 — Price hypothesis labeled
The design-time $14.99–$19.99 band and $17.99 center remain explicitly hypotheses subject to release-time market/value review.

## E7-03 — No currency
No campaign unlock, hint, retry, mastery or remix requires earning/spending a progression currency.

## E7-04 — No mastery gate
A clean new profile can reach D40 through baseline campaign clears with zero optional mastery marks.

## E7-05 — Knowledge prerequisites
Every nontrivial campaign unlock is explainable by authored predecessor/tutorial-tag prerequisites rather than XP or repeated clears.

## E7-06 — Remix exact count
Exactly 12 remix cases exist in the 1.0 content ceiling unless Phase 5 is explicitly reopened.

## E7-07 — Remix pack A
R01–R04 unlock permanently when D08 baseline clear is recorded.

## E7-08 — Remix pack B
R05–R08 unlock permanently when D24 baseline clear is recorded.

## E7-09 — Remix pack C
R09–R12 unlock permanently when D40 baseline clear is recorded.

## E7-10 — No FOMO
No dossier/remix/mastery is time-limited, rotated daily, tied to a login streak or removed after unlock.

## E7-11 — Experiment-safe mastery
Undo count, elapsed time and failed experiments never reduce baseline completion or authored final-state mastery eligibility.

## E7-12 — Accessibility neutrality
Using Phase-6 accessibility options never blocks baseline progress, mastery or ordinary achievements.

## E7-13 — Deterministic assists
Puzzle assist settings do not change map authority, agent route logic, tie-breaks, objective predicates or simulation randomness.

## E7-14 — Hint depth 1
Rule Reminder provides known-rule/context information but no candidate edit ranking.

## E7-15 — Hint depth 2
Conflict Focus identifies conflicting systems/authority context without prescribing a move.

## E7-16 — Hint depth 3
Directional Hint may identify a primitive family/region but not the full edit sequence.

## E7-17 — Demo core identity
A demo run necessarily demonstrates at least one direct map->world rewrite and one second-order/collateral consequence.

## E7-18 — Demo advanced exclusions
The demo contains no landmark relabeling, editable waterways, Ferry, Procession, Commercial chain or linked-map mechanic.

## E7-19 — Demo import monotonicity
Importing compatible demo progress/settings into a full profile never deletes or downgrades fuller progress.

## E7-20 — Demo incompatibility safety
A rules/content version mismatch can refuse dossier-clear import while still permitting compatible settings import; it never invents clears.

## E7-21 — Achievement bound
1.0 ships with 20–24 achievements unless a later explicit commercial review changes the count with documented reason.

## E7-22 — No grind achievements
No achievement requires an arbitrary high count of repeated edits, undos, dossier restarts, launches or play-days.

## E7-23 — No anti-access achievements
No achievement requires disabling accessibility features or using a particular input device.

## E7-24 — Steam Cloud target
Save architecture in Phase 8 must support a reliable Steam Cloud strategy or document a concrete technical reason to exclude it before specification freeze.

## E7-25 — No workshop dependency
Workshop/UGC is absent from the 1.0 implementation requirement.

## E7-26 — No leaderboard dependency
Online leaderboards are absent from the 1.0 implementation requirement.

## E7-27 — No external account
Ordinary single-player progress requires no proprietary online account.

## E7-28 — Full base game
All 40 campaign dossiers and 12 remixes are part of the premium base-game scope; no planned base campaign case is withheld as launch DLC.

## E7-29 — Expansion integrity
Any future paid expansion is optional substantial new casebook content and cannot sell mechanical power over the base game.

## E7-30 — Retention quality
If a proposed retention feature cannot be justified as improving puzzle learning, alternate solution exploration, mastery or meaningful optional content, it is rejected.

---

# 15. Closure decision

- Premium commercial frame: **FROZEN FOR DESIGN**
- Exact release price: **INTENTIONALLY NOT FROZEN; hypothesis recorded**
- Progression economy: **NO CURRENCY / NO GRIND**
- Campaign unlock philosophy: **FROZEN**
- Remix unlock policy: **FROZEN**
- Mastery role: **FROZEN**
- Difficulty/assist philosophy: **FROZEN**
- Demo boundary/transfer intent: **FROZEN ENOUGH FOR TECH SPEC**
- Steam 1.0 feature scope: **FROZEN**
- Achievement target/philosophy: **FROZEN**
- Monetization exclusions: **FROZEN**
- Retention philosophy: **FROZEN**
- Earlier phase reopened: **NO**
- Phase 7: **COMPLETE ON PAPER**
- DESIGN COMPLETE: **NO**

## NEXT PHASE
**Phase 8 — Technical Implementation Specification.**

Phase 8 must turn the existing design into deterministic implementation contracts: engine/runtime direction, scene/state boundaries, authoritative map/simulation data model, transaction ordering, save/checkpoint schema, demo/full migration identity, Steam Cloud merge/recovery semantics, input abstraction, localization/content pipelines, validation tooling, performance ceilings, deterministic test harnesses, implementation slices and acceptance tests. It must not start production implementation.