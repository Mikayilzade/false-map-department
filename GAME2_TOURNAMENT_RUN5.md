# GAME #002 — TOURNAMENT RUN 5: FINAL THREE-WAY DUEL

Last updated: 2026-08-18
Factory run: **5**
Phase: **2 — Concept Tournament / FINAL SELECTION**
Final concept selected: **YES — False Map Department**

Purpose: apply the same final packet to the three surviving concepts, concretize each existential issue enough to compare implementation burden and hour-10 depth, and select a winner only if the paper evidence is strong enough that a three-prototype duel would be wasteful.

---

## Fresh market checks used in this run

### Cartography / representation
`Map Map — A Game About Maps` released 2026-05-28 and is currently Very Positive on Steam. Its core is making maps that represent explored islands; it does **not** use map edits as direct causal edits to reality. This strengthens the belief that players can understand cartography as a primary verb while leaving ontological cartography mechanically distinct.

Source: https://store.steampowered.com/app/2702260/

A visible negative-review pattern around Map Map is also useful: players can become disappointed when a strong mapping mechanic stops being the center of play and gets diluted by ordinary exploration/content. Implication for Game #002: if False Map Department wins, the map/world rewrite interaction must remain the game for the whole campaign rather than becoming framing around unrelated adventure content.

Source: https://steamcommunity.com/app/2702260

### Weather tactics
`Tide Of Tactics` released 2026-08-07 and uses forecasted weather changes that modify terrain, visibility and movement. It does not make weather fronts the player's army, but it confirms that forecast-as-tactical-information is already understandable in current grid tactics. This helps readability but weakens novelty of forecast UI by itself.

Source: https://store.steampowered.com/app/4005630/Tide_Of_Tactics/

### Expressive movement warning
Current 2026 action coverage around highly stylized stunt games reinforces that spectacle without mechanical consistency is dangerous. A movement finalist must deliver authentic player-authored mastery rather than scripted spectacle. For Orbit Graffiti this raises, rather than lowers, the importance of feel/camera/controller graybox proof.

Reference: https://www.pcgamer.com/games/action/denshattack-review/

---

# 1. Final packet — FALSE MAP DEPARTMENT

## One-sentence Steam pitch
**Redraw the official map and the tiny world must obey: move roads, borders, rivers and landmarks to solve civic problems without creating worse consequences elsewhere.**

## 10-second muted trailer beat
0–2 s: split view, map left / living town right; courier blocked by river.
2–4 s: player stamps one bridge symbol on the map.
4–6 s: matching bridge physically grows in the town; courier starts moving.
6–8 s: escaped livestock immediately crosses too and enters a protected garden.
8–10 s: player erases a road junction; livestock reroutes while courier remains served.

The hook, consequence and second-order depth are visible without text or audio.

## Exact first 15 minutes
0–2: one bridge symbol changes world immediately.
2–4: erase road to redirect one agent.
4–6: border ownership changes gate access.
6–8: first two-objective tradeoff: help courier, protect garden.
8–10: introduce causality highlight: last edit -> world facts changed -> agents affected.
10–12: first case where the obvious bridge solution satisfies local goal but violates a protected invariant; player must alter route topology instead.
12–15: first compact dossier with road + bridge + border, three agents, two goals, one invariant, and optional mastery for <=3 final interventions. End screen asks player to explain one consequence by selecting its causal chain, reinforcing model-building rather than blind testing.

No walking avatar, dialogue quest, inventory or detached minigame appears. The mapping verb remains central.

## Canonical map conventions for the core game
The first shippable vocabulary is deliberately mundane and universally legible:
1. **Road segment** — creates/removes traversable route for road-using agents.
2. **Bridge symbol** — creates a crossing at legal snapped water/road intersection.
3. **Border line** — assigns enclosed cells/landmarks to one jurisdiction.
4. **Waterway segment** — changes water-connected traversal and blocks ordinary roads unless bridged.
5. **Landmark name/marker** — changes named destination resolution for agents with semantic targets.
6. **Restricted-zone hatch** — denies specified agent classes while remaining traversable for permitted classes.

Later depth comes from agents and objectives interpreting these same conventions differently, not from dozens of magical symbols.

## Anti-bruteforce architecture
Brute-force undo is the existential risk. The solution is **not** to punish experimentation harshly.

Rules:
- every edit resolves immediately and remains freely undoable for baseline completion;
- mature scenarios have multiple locally-valid edits with remote/second-order consequences, making one-step try/undo insufficient;
- goals are conjunctions across 2–4 systems plus protected invariants, not single binary target lights;
- agents cycle deterministically after every edit and can expose delayed consequences in 2–5 simulation beats;
- an optional mastery score counts **final intervention footprint**, not raw experimentation history, so players are encouraged to learn without save-scumming punishment;
- some cases include a `Stability` requirement: after final edit, the district must survive N deterministic cycles with all invariants intact;
- causality tools explain what happened, but never enumerate legal edits or rank candidate solutions.

Graybox rejection remains: if exhaustive legal-edit enumeration is faster than reasoning on mature boards, kill the concept.

## Hour-10 mastery example
A regional dossier contains three linked district maps plus one higher-level transit map. A player must:
- keep two hospitals reachable from all residential zones;
- preserve a wetland with no new road adjacency;
- route a festival procession through exactly two jurisdictions;
- maintain tax ownership of a market that funds a ferry;
- prevent livestock from reaching a schoolyard;
- keep total final intervention footprint <=5 for Gold.

The elegant solution renames one landmark so two courier classes share a destination, shifts one border to move gate ownership, removes one redundant local road, adds one bridge, and moves one regional connector. The player predicts that the border shift changes market ownership, which keeps the ferry funded; the regional connector then reroutes deliveries without touching the wetland. Mastery is compact causal reasoning across layers, not handling twenty new mechanics.

## Minimum shippable scope
- PC/Steam first.
- 35–45 authored dossiers, not hundreds.
- 6 canonical map conventions.
- 8–10 reusable agent rule archetypes.
- 10–12 objective/invariant families.
- 3 visual district themes reusing symbolic map language.
- deterministic simulation; no procedural campaign required.
- no freehand precision: all edits snap to graph/grid primitives.
- no open-world walking, dialogue tree, economy sim, multiplayer or user-generated content at 1.0.

A 5–8 hour first completion with optional Gold constraints is acceptable if interaction density remains high.

## One-week graybox plan
Day 1: dual map/world 8×8 graph, road add/remove, one courier.
Day 2: bridge + water + immediate world mutation + undo.
Day 3: border ownership + gate rules + causal highlight.
Day 4: three agents, two goals, one protected invariant; six micro-scenarios.
Day 5: add 3-cycle Stability and intervention-footprint scoring.
Day 6: naive playtest script; capture verbal predictions before edits.
Day 7: adversarial enumeration test: compare human hypothesis solving against exhaustive legal-edit trial behavior.

## Kill threshold
Kill or radically rethink if **any two** occur after one tuning pass:
- fewer than 80% of testers understand map->world causality by minute 3;
- fewer than 70% can predict direction of a second-order consequence by scenario 6;
- >35% of successful mature actions are blind probes with no stated hypothesis;
- exhaustive legal-edit testing reliably beats reasoning time;
- UI needs freehand precision or dense text to explain ordinary edits;
- testers describe it as “a level editor where I guess what the designer wants” rather than “I change the map and reason about the world.”

## Most likely negative Steam review
“Fantastic idea, but later levels feel like hunting for the designer's one intended combination and constantly undoing tiny changes until every checkbox is green.”

Design response: preserve multiple valid solutions where possible, avoid exact hidden-state targets, show causal consequences clearly, score elegance optionally rather than requiring unique minimal solutions.

## Strongest defensible advantage over known analogues
Existing cartography games primarily ask players to **represent** or navigate a world. False Map Department makes representation **authoritative over reality**. The same edit is both UI action and world action; the second-order consequences are the content engine.

## Solo/small-team burden
- Art: Low–Medium.
- UI/interaction clarity: High.
- Deterministic simulation: Medium–High.
- Content authoring: Medium–High.
- QA/solvability: High.
- Physics/animation feel dependency: Low.
- Bespoke narrative/audio dependency: Low.

Critical risk is logical/UX quality, not expensive asset production.

## Final judgement
**PASS / strongest winner.** The existential problem is difficult but design-addressable and testable with primitive shapes. Failure can be discovered in a one-week graybox before major production. The hook survives mute trailer, first 15 minutes, hour 10 and minimum-scope compression.

---

# 2. Final packet — ORBIT GRAFFITI

## One-sentence Steam pitch
**Sketch a temporary gravity rail around tiny planets, snap onto your own curve, and surf its exact tangent through deliveries and stunt chains.**

## 10-second muted trailer beat
Draw glowing arc -> character catches it -> accelerates -> launches from tangent -> threads ring -> draws another arc in slow time -> catches moon orbit.

This is the strongest pure-motion clip of the finalists.

## Exact first 15 minutes
0–3: draw one snapped arc, catch, launch.
3–5: two-planet transfer.
5–7: limited ink prevents full safe circle.
7–10: delivery object changes momentum/capture forgiveness.
10–12: rotating hazard forces timing.
12–15: optional stunt ring + instant ghost replay of authored line.

## Movement / assist model
- character remains in real-time motion;
- holding Draw slows simulation to 25% rather than pausing;
- mouse: click-drag spline constrained to max curvature/minimum distance from planet;
- controller: radial aim chooses tangent start, stick sweeps an arc with snapable curvature presets; shoulder button flips curvature direction;
- keyboard: 8-direction tangent aim plus `tight / medium / wide` arc primitives;
- capture has visible funnel and generous magnet radius at baseline;
- near-miss assist may pull the character toward rail only if approach angle is within a readable cone;
- launch direction is exact rail tangent, while launch speed is current rail speed with capped assist normalization at beginner difficulty.

This can make controller viable, but it needs feel proof, not more paper design.

## Hour-10 mastery example
Player chains five temporary rails through a rotating three-planet pocket while carrying fragile cargo. They intentionally draw a short wide arc to gain a shallow tangent, use natural gravity to cross a hazard gap, catch a tiny reverse arc, shed speed before the fragile delivery, then launch into an optional score ring and finish with 8% ink remaining. Ghost comparison shows line geometry, not merely time.

## Minimum shippable scope
- 25–35 compact handcrafted pockets;
- 5 planet/hazard archetypes;
- 4 cargo modifiers;
- completion + score/ink medals;
- mouse/keyboard/controller support;
- no procedural galaxy, combat campaign, online leaderboards required at 1.0.

## One-week graybox
Two circles, spline rail, capture cone, tangent launch, one goal, one hazard, one cargo, slow-time draw, controller primitives, retry/ghost.

## Kill threshold
Kill if after tuning:
- controller remains materially less expressive than mouse;
- drawing consumes >45% active play time;
- >70% successful routes converge on safe semicircle/circle patterns;
- missed captures feel arbitrary;
- camera readability fails at the speed required for fun;
- players say “I draw routes and the character follows” rather than “I surf what I draw.”

## Most likely negative Steam review
“Cool for twenty minutes, but the safest arc always works and drawing breaks the flow every few seconds.”

## Strongest defensible advantage
The player authors the exact surface that immediately becomes movement physics; line creation and execution are one expressive skill rather than a level-editor phase.

## Solo/small-team burden
- Art: Low–Medium.
- UI: Medium.
- Physics/movement/camera feel: **Very High existentially**.
- Content: Medium.
- QA/input variance: High.

## Final judgement
**RUNNER-UP / prototype-dependent.** Potentially the most exciting game if feel is exceptional, but its core cannot be de-risked on paper. The factory would be committing to a high-variance action project whose primary risk is implementation craftsmanship rather than specification quality.

---

# 3. Final packet — POCKET WEATHER WAR

## One-sentence Steam pitch
**Fight a tiny deterministic tactics war with warm, cold and wet fronts instead of soldiers—steer collisions to rain on your farms and freeze the enemy's routes.**

## 10-second muted trailer beat
Warm red-pattern front advances -> player raises hill -> forecast arrows bend -> cold front collides -> rain band forms over farm -> river freezes on enemy side -> objective flips.

## Representative discrete front rules
Board uses cells, not fluids.

Each front token has: `type {warm,cold,moist}`, `strength 1..3`, `heading`, `moisture 0..2`.
Terrain has: elevation 0..2, water yes/no, roughness 0..1.
Global wind has one of 8 headings.

Resolution per turn:
1. player and opposition each spend influence on max two interventions;
2. forecast computes deterministic intents;
3. fronts choose next cell by score: wind alignment + gradient attraction - elevation cost - opposing pressure;
4. ties resolve by fixed clockwise priority seeded per map and shown in forecast;
5. simultaneous front contact resolves by table:
   - warm + cold -> precipitation band; stronger front persists at strength-1;
   - moist + cold -> snow/freeze effect;
   - moist + warm -> fog/rain depending elevation;
6. objective tiles score from resulting state;
7. fronts decay if no gradient/opposition interaction sustains them.

No hidden random roll is needed.

## Turn / forecast semantics
The player always sees the complete next-turn forecast before confirming. Interventions update it live. Opposition intent is either fully telegraphed (campaign baseline) or selected from a small visible policy set on advanced challenges. The tactical question is choosing which forecasted consequence to accept, not guessing RNG.

## Low-cost opposition model
Campaign uses authored **climate doctrines**, not a general chess-strength AI:
- Aggressor: maximize front strength toward nearest enemy objective.
- Irrigator: prioritize rain value on owned farms.
- Denial: alter forecast to prevent opponent scoring even at own low gain.
- Splitter: maintain two medium fronts rather than one extreme.
- Scripted puzzle turns may use fixed first actions then doctrine.

This keeps QA bounded and creates readable opponent personality.

## Exact first 15 minutes
0–3: heat one cell, read one-step forecast.
3–5: warm/cold collision makes rain.
5–7: hill redirects one front.
7–10: objective shifts from occupancy to irrigation.
10–12: telegraphed enemy intervention creates counterplay.
12–15: first map with two objectives where deliberate collision helps both sides differently.

## Hour-10 mastery example
On a 10×10 basin the player needs rain on two farms, open visibility on a pass, and a frozen river for exactly one turn. They intentionally weaken their warm front so it loses a collision but produces precipitation at the right elevation, use one hill to bend the surviving cold front toward the river, then exploit opponent Irrigator doctrine to bring moisture into the basin. Mastery is forecast manipulation and adversarial use of collision products.

## Minimum shippable scope
- 30–40 compact tactical maps;
- 3 front types, 4 terrain effects, 5 interventions;
- 4 climate doctrines;
- 8 objective families;
- deterministic forecast UI;
- no multiplayer or full fluid simulation.

## One-week graybox
7×7 grid, three front types, fixed wind, heat/cool + hill interventions, forecast arrows, four objective tiles, one scripted opponent then two simple doctrines.

## Kill threshold
Kill if any two:
- <70% predict next destination after tutorial;
- same first two actions dominate >60% seeds;
- forecast needs numeric meteorology to understand;
- deterministic results are still perceived as luck;
- opposition doctrines feel either trivial or arbitrary;
- front collisions visually read as status effects rather than armies interacting.

## Most likely negative Steam review
“Into-the-Breach-looking weather math where I stare at arrows for five minutes, then watch the obvious resolution.”

## Strongest defensible advantage
Weather is not modifier or event: fronts are the tactical pieces, and collision products are both attacks and resources.

## Solo/small-team burden
- Art: Low–Medium.
- UI/forecast readability: High.
- Simulation: Medium.
- Content: Medium.
- Balance/AI/seed QA: High.

## Final judgement
**THIRD.** Strong systemic tactics candidate and less feel-sensitive than Orbit Graffiti, but the hook requires more explanation and risks becoming forecast arithmetic. Current tactics already normalize weather forecasts as modifiers, so the concept's novelty depends on front-as-unit readability surviving graybox.

---

# 4. Final comparative score

Scale 1–10; higher is better except burden/risk rows where higher means easier/lower risk.

| Criterion | False Map Department | Orbit Graffiti | Pocket Weather War |
|---|---:|---:|---:|
| One-sentence hook | 9 | 9 | 8 |
| Muted 10-second clarity | 10 | 10 | 7 |
| First-15-minute teaching | 9 | 7 | 7 |
| Hour-10 systemic depth | 9 | 8 | 9 |
| Scope compression | 9 | 8 | 8 |
| Solo/small-team implementation predictability | 8 | 5 | 7 |
| Asset burden | 9 | 8 | 9 |
| Controller/input risk | 9 | 5 | 9 |
| QA/solvability manageability | 6 | 6 | 6 |
| Market differentiation | 9 | 8 | 8 |
| Portfolio diversity vs Game #001 | 8 | 10 | 9 |
| Graybox can cheaply kill existential risk | 10 | 8 | 9 |
| **Total** | **105** | **95** | **97** |

The scores are not the decision by themselves. The decisive factor is where the existential risk lives:
- False Map Department: in interaction clarity and brute-force resistance, both cheaply testable and substantially design-addressable.
- Orbit Graffiti: in movement feel/camera/controller craft, expensive and implementation-dependent.
- Pocket Weather War: in forecast readability and tactical non-collapse, testable but less immediately marketable.

---

# 5. Selection decision

## WINNER: FALSE MAP DEPARTMENT

Reasoning:
1. It is the only finalist whose complete promise is visible in one tiny before/after map edit **and** naturally contains second-order consequences for long-term depth.
2. It preserves a compact production profile without relying on exceptional physics feel, networking, animation volume, dialogue or large asset libraries.
3. Its closest current cartography analogue validates “maps as primary gameplay” but does not occupy “representation rewrites reality.”
4. The strongest current warning from a cartography analogue—diluting the mapping mechanic with unrelated exploration—can be converted directly into a non-negotiable scope rule.
5. The existential failure mode can be falsified in a primitive one-week graybox before major production.
6. It is structurally distinct enough from Organism Cargo: edits are immediate and reversible; there is no plan/commit/watch transit loop.

## Runner-up preservation
Orbit Graffiti and Pocket Weather War remain documented as rejected finalists, not future default concepts. They may be revisited only as new numbered factory cycles with fresh evidence, not silently merged into Game #002.

Phase 2 is now complete. Phase 3 may begin immediately.