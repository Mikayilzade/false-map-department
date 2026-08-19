# GAME #002 — TOURNAMENT RUN 4: SEMIFINAL FALSIFICATION

Last updated: 2026-08-18
Factory run: **4**
Phase: **2 — Concept Tournament**
Final concept selected: **NO**

Purpose: turn the six Run-3 semifinalists into concrete playable session models, define existential graybox tests, attack dominant/boring strategies, prove compact-content depth, compare production burden, and reduce the field to 2–3 finalists.

This file is additive tournament evidence. `GAME2_TOURNAMENT.md` remains the Run-3 destructive packet.

---

# 1. Uniform semifinal test format

For every concept this run requires:
1. exact first 5-minute session;
2. representative mature 30-minute session;
3. smallest one-week-style graybox;
4. binary/observable kill thresholds;
5. dominant-strategy attack;
6. boring-valid-strategy attack;
7. compact vocabulary capable of >=20 meaningfully distinct situations;
8. burden estimate: art / UI / simulation / content / QA, each Low–Very High;
9. tournament decision.

A concept does not survive merely because the theme sounds marketable.

---

# 2. S1 — False Map Department

## 2.1 Exact first 5 minutes

**Premise shown without exposition:** left half is a municipal map; right half is a tiny living district. A courier cannot reach a post office because a canal cuts the road.

0:00–0:30 — player sees the courier fail and the matching map highlight pulse.

0:30–1:15 — only legal tool is `Bridge Symbol`. Place it on one snapped crossing point. The world immediately grows a bridge and courier crosses. No submit button.

1:15–2:00 — second micro-problem: erase one road segment to stop a runaway cart. World road disappears immediately; cart reroutes.

2:00–3:10 — introduce `Border`: moving the border changes which town owns a gate; ownership controls whether a patrol opens it.

3:10–4:20 — first tradeoff: adding a bridge helps courier but lets livestock reach a garden. Goal requires courier success **and** garden protection.

4:20–5:00 — player solves by moving a road junction instead of bridge-spamming. End state explicitly shows `map edit -> world mutation -> agent consequence` chain.

If this sequence is not readable and satisfying with primitive shapes, reject.

## 2.2 Representative mature 30-minute session

One dossier contains 4 linked districts and 6 map conventions: roads, waterways, borders, elevation marks, named landmarks and restricted zones. The player receives three simultaneous civic objectives plus one protected invariant.

Minute 0–5: inspect current simulation and causal overlays.
Minute 5–12: make reversible edits while agents react immediately.
Minute 12–18: discover a second-order consequence: moving a border changes tax ownership, which changes a ferry schedule and starves a warehouse route.
Minute 18–24: use layer view to reason about two linked maps at different scales.
Minute 24–28: converge on a low-edit solution.
Minute 28–30: optional mastery score compares edits used, collateral changes and stability.

The mature game remains active experimentation, not plan/commit/watch.

## 2.3 Smallest graybox

- 8×8 world grid and matching snapped map graph;
- 3 symbol types: road, bridge, border;
- 3 autonomous agents with deterministic route/ownership rules;
- undo stack;
- 6 handcrafted micro-scenarios;
- causal highlight showing which world fact changed from the last edit.

No art beyond icons and colored blocks.

## 2.4 Kill thresholds

**Kill immediately if any two are true:**
- after scenario 3, fewer than 4/5 naive testers can predict the *direction* of the next edit's world effect;
- >35% of successful actions in scenarios 4–6 are blind undo-driven probes rather than stated hypotheses;
- freeform drawing precision is needed for success;
- average tester cannot explain one second-order consequence after scenario 6;
- the strongest strategy is exhaustively testing each snapped legal edit because the branching factor is too small.

## 2.5 Dominant-strategy attack — brute-force undo

Main exploit: click every legal edit, observe, undo.

**Counter-design that preserves freedom:**
- objectives score `Intervention Cost`: edits and reversals consume optional mastery budget, but baseline completion never hard-locks experimentation;
- mature boards have combinatorial edits whose local immediate success can create delayed/remote failure, so single-step brute force does not solve state understanding;
- `Stability` objective requires the final world to survive a short deterministic simulation after the last edit;
- some scenarios expose several locally-good edits, forcing comparison rather than binary try/undo.

**Fatal warning:** if the game must punish undo heavily to stop brute force, reject. Reasoning must be intrinsically faster than exhaustive search at mature complexity.

## 2.6 Boring strategy attack

Boring play: edit until green checks appear, ignore world meaning.

Require every mature objective to reference at least two world systems and include one protected invariant. Causal overlays explain changes, but there is no raw numeric solver hint revealing the answer.

## 2.7 >=20-situation proof from compact vocabulary

Using only roads / bridges / borders / waterways / ownership / agents, already distinct scenario families exist:
1. reconnect courier route;
2. block runaway route;
3. create detour without isolating residents;
4. bridge helps one agent but enables predator/livestock crossing;
5. border changes gate access;
6. border changes tax/resource destination;
7. bridge changes patrol reach;
8. road removal changes market flow;
9. road addition overloads a junction;
10. waterway reroute isolates ferry;
11. two towns compete for one crossing;
12. emergency route must stay under N steps;
13. protected habitat cannot gain road adjacency;
14. school zone must remain inside jurisdiction;
15. agent with forbidden-border rule;
16. timed procession conflicts with delivery;
17. one-way road convention;
18. landmark renaming changes destination resolution;
19. map scale link causes local edit to change regional route;
20. paired-map contradiction where only one representation may be authoritative;
21. stability challenge with repeated agent cycles;
22. minimal-edit mastery challenge.

These are rule recombinations, not 22 bespoke mechanics.

## 2.8 Burden

- Art: **Low–Medium**
- UI: **High** — dual representation must be crystal clear
- Simulation: **Medium–High**
- Content authoring: **Medium–High**
- QA/solvability: **High**

**Run-4 verdict: FINALIST.** Strongest combination of hook, immediate causality, compact visuals and systemic depth. Primary existential risk remains brute-force search and representation clarity.

---

# 3. S2 — Orbit Graffiti

## 3.1 Exact first 5 minutes

0:00–0:20 — tiny astronaut/skater drifts near a small planet. Prompt: hold Draw and place a snapped curved rail segment around the planet.

0:20–0:50 — release; character magnetically catches the rail, accelerates along it, then launches off its tangent.

0:50–1:30 — draw second rail around another moon; chain catch-to-launch.

1:30–2:20 — delivery orb appears. Carry it through one ring and land on station.

2:20–3:20 — introduce a rail ink budget: safe full circles are impossible; player must choose exit angle.

3:20–4:20 — optional trick ring rewards a risky slingshot.

4:20–5:00 — replay ghost shows the exact authored rails and path, making authorship visible.

The player must feel that **drawing is movement**, not a planning interruption.

## 3.2 Representative mature 30-minute session

A 3-planet pocket contains rotating hazards, two deliveries, stunt gates and limited rail ink. Player alternates 1–3 second slow-motion drawing bursts with 5–15 second high-speed riding. Rails decay after use or time, preventing permanent infrastructure.

Mature mastery comes from:
- drawing exit tangents under pressure;
- deciding whether to spend ink on catch safety or speed;
- chaining planetary gravity/rail momentum;
- carrying cargo that changes mass/handling;
- revising lines after missed catches without restarting the whole level;
- score routes versus safe completion routes.

## 3.3 Smallest graybox

- 2 fixed circles as planets;
- cubic/spline rail drawing with strict max length;
- magnetic capture radius;
- tangent launch;
- one goal ring;
- one delivery target;
- one hazard;
- instant retry and ghost line.

No procedural worlds, progression or cosmetics.

## 3.4 Kill thresholds

Kill if any are true after tuning window:
- median tester spends >45% of active play time drawing/aiming rather than moving;
- controller rail authoring is materially worse than mouse and cannot be fixed with snap primitives;
- >70% of successful solutions converge on near-circular safe rails;
- missed rail capture feels arbitrary more than once per 10 attempts;
- testers describe the game as “drawing paths then watching” rather than “surfing lines I create.”

## 3.5 Dominant-strategy attack — safe rails

Exploit: draw thick/full safe orbits, crawl to objective.

Counter-rules:
- hard rail-length/ink cap;
- rails are one-use or rapidly decay after traversal;
- minimum exit velocity on some gates;
- optional mastery rewards continuous chains but baseline levels still allow moderate safety;
- planets/hazards rotate, invalidating static repeated circles;
- delivery mass can reduce capture radius or acceleration.

If fun requires precision punishment rather than expressive flow, kill.

## 3.6 Boring strategy attack

Boring play: stop, draw carefully, move, stop again.

Use time-slow rather than pause during drawing; cap continuous draw duration; permit simple snap arcs from controller; reward chaining but never require twitch drawing while at full speed.

## 3.7 >=20-situation proof

Compact vocabulary: planet gravity, temporary rails, ink, capture, tangent launch, cargo, rings, hazards.

1. single-planet launch;
2. two-planet transfer;
3. delivery with mass penalty;
4. ring sequence;
5. rotating hazard gap;
6. low-ink route;
7. one-use rail chain;
8. decaying rail return trip;
9. opposite-direction orbit target;
10. narrow capture corridor;
11. moving station;
12. fragile cargo limits impact speed;
13. cargo increases momentum;
14. split route safe vs score;
15. planet occludes line-of-sight drawing;
16. hazard erases rail sections;
17. slingshot without touching rail twice;
18. collect-and-return route;
19. ghost-time race;
20. minimal-ink medal;
21. continuous-chain medal;
22. rescue drifting object.

Depth is plausible without content explosion.

## 3.8 Burden

- Art: **Low–Medium**
- UI: **Medium**
- Simulation/physics feel: **Very High existentially**, even if technically small
- Content authoring: **Medium**
- QA: **High** due to physics/camera/input variance

**Run-4 verdict: FINALIST.** Best portfolio diversity and strongest mastery clips, but also highest feel risk. It must pass graybox before any large design investment.

---

# 4. S3 — Pocket Weather War

## 4.1 Exact first 5 minutes

Board: 7×7 terrain, your warm front at west, opposing cold front east.

0:00–0:45 — choose `Heat` on one tile; forecast arrows show warm front advancing next step.

0:45–1:30 — execute one short simultaneous turn. Fronts move; contact creates rain band.

1:30–2:20 — place a hill; forecast visibly bends wind/front around it.

2:20–3:10 — objective becomes capture two farms with favorable rain, not merely destroy enemy weather.

3:10–4:00 — enemy cools a corridor; player can intensify heat or redirect with terrain.

4:00–5:00 — first tactical reversal: player deliberately lets fronts collide to create rain over their farm while denying enemy farm.

No meteorological numeric panel in first five minutes.

## 4.2 Representative mature 30-minute session

A 10×10 board uses 3 terrain types, moisture, wind direction and 3 front states. Each turn player spends 2–3 influence points on local interventions, then sees a **previewable deterministic** forecast for the next resolution.

Objectives vary: irrigate, freeze river crossing, clear fog corridor, protect settlement, occupy pressure nodes, survive asymmetric climate. Opponent may be AI or authored tactical system; no multiplayer requirement.

The mature loop is interactive forecasting and counterplay, not watching long weather simulations.

## 4.3 Smallest graybox

- 7×7 discrete board;
- warm/cold/moist front tokens;
- deterministic cellular propagation;
- 2 interventions: heat/cool and hill redirect;
- next-turn forecast overlay;
- 4 objective tiles;
- simple scripted opponent.

## 4.4 Kill thresholds

Kill if any two are true:
- after 3 tutorial maps, <70% of players can correctly predict which of two tiles a front will enter;
- optimal play in >60% of test seeds starts with the same first two actions;
- forecast overlay requires numeric meteorology to explain outcomes;
- resolution takes >3 seconds of passive watching per turn in graybox;
- testers frame outcomes as luck despite deterministic rules.

## 4.5 Dominant-strategy attack — extreme climate / turtle

Exploit A: rush maximum heat/cold and overwhelm board.
Exploit B: create stable defensive climate behind mountains and wait.

Counter architecture:
- fronts consume gradients; extreme homogeneous climate loses steering power;
- objectives are distributed and time-sensitive, so turtling concedes map value;
- terrain interventions have opportunity cost and cannot create permanent impermeable walls;
- collision products (rain/fog/storm) can benefit the opponent, making raw intensity non-monotonic;
- influence replenishment favors interacting with objective zones rather than holding corners.

## 4.6 Boring strategy attack

Boring play: memorize fixed opening and repeat. Scenario generator/authored seeds must vary initial wind, objectives and terrain while preserving readable state. Campaign challenge families should explicitly invalidate repeated openings.

## 4.7 >=20-situation proof

Vocabulary: warm/cold/moist fronts, wind, hills, water, objectives, heat/cool/redirect.

1. irrigate farm;
2. deny enemy farm;
3. freeze crossing;
4. thaw crossing;
5. clear fog route;
6. create fog screen;
7. prevent storm over town;
8. intentionally create storm on hostile node;
9. split front around hills;
10. merge two weak fronts;
11. sacrifice one objective to redirect weather;
12. race for moving wind window;
13. asymmetric hot-side start;
14. asymmetric wet-side start;
15. limited intervention challenge;
16. no-terrain-modification challenge;
17. protect two separated towns;
18. pressure-node control;
19. front must arrive in exact turn window;
20. reverse prevailing wind once;
21. multi-objective score map;
22. survival against scripted cyclone pattern.

## 4.8 Burden

- Art: **Low–Medium**
- UI: **High** — forecast clarity is core
- Simulation: **High**
- Content authoring: **Medium**
- QA/balance: **Very High**

**Run-4 verdict: FINALIST.** Strong systemic whitespace and tactical identity. Its burden is balance/forecast legibility rather than art. It survives only if deterministic weather feels intuitive instead of abstract.

---

# 5. S4 — Echo Sculptor

## 5.1 Exact first 5 minutes

0:00–0:40 — emitter sends a visible pulse across a square room. Pulse dies before receiver.
0:40–1:20 — rotate one 45° reflective panel; pulse visibly bounces into receiver.
1:20–2:00 — replace panel material with absorber; player sees pulse energy disappear.
2:00–3:00 — two paths arrive at a resonator at different times; player changes path length.
3:00–4:00 — split pulse to activate two receivers.
4:00–5:00 — player solves one compact room using reflection + absorption.

Audio reinforces but never carries unique information.

## 5.2 Representative mature 30-minute session

A modular room network contains two emitters, reflectors, absorbers, resonators and timed gates. Player edits geometry/material and probes repeatedly. Mature challenge comes from timing, energy budget and multi-path interference-like rules.

## 5.3 Smallest graybox

Discrete 2D ray/grid model, not physical acoustics:
- emitter;
- receiver;
- reflector;
- absorber;
- split node;
- energy/time labels;
- 8 rooms.

## 5.4 Kill thresholds

Kill if:
- simplified model needs exceptions that contradict visual intuition;
- more than 25% of actions become trial-rotate-everything;
- visible wave overlay is sufficient but sound contributes almost no fantasy/pleasure;
- adding timing/resonance causes puzzle explanation to exceed the elegance of the core reflection game.

## 5.5 Dominant-strategy attack — mirror corridors

Limit reflector count/energy; receivers may require arrival windows; absorbers can be necessary to suppress unwanted paths. But if constraints feel artificial rather than naturally expressive, this is a warning.

## 5.6 >=20-situation proof

Possible through reflection, absorption, split, timing and moving gates. However many situations risk reading as variations of laser-routing puzzles with an audio skin.

Distinct families include single bounce, multi-bounce, split, energy threshold, delay matching, forbidden receiver, moving blocker, material swap, multi-emitter, resonance timing, etc. It clears 20 mechanically, but **perceived novelty across those 20 is less certain**.

## 5.7 Burden

- Art: **Low**
- UI: **Medium–High**
- Simulation: **Medium** if deliberately discrete
- Content: **High** handcrafted puzzle burden
- QA: **High** solvability/alternate solution checks

**Run-4 verdict: ELIMINATED.** It is elegant and buildable, but after concretization the compact model risks being perceived as laser-routing with sound vocabulary. Making acoustics richer enough to escape that comparison raises simulation and explanation burden sharply. Keep as a future seed, not Game #002 finalist.

---

# 6. S5 — Creature Costume Inspector

## 6.1 Exact first 5 minutes

0:00–1:00 — one creature in obvious costume; choose Brush test, revealing fur direction beneath paint.
1:00–2:00 — second subject: Shine Light reveals translucent ear silhouette.
2:00–3:00 — Heat test melts wax nose but also destroys scent clue; first explicit test-order tradeoff.
3:00–4:00 — compare evidence board against two candidate species.
4:00–5:00 — final subject has one misleading costume layer; player chooses only 2 of 4 tests and identifies creature.

## 6.2 Representative mature 30-minute session

Shift contains 6–8 subjects. Each has modular disguise layers and hidden species traits. Player has limited test supplies and must decide test order because tests transform or destroy evidence. Mistakes affect shift score/reputation, not branching narrative explosion.

## 6.3 Smallest graybox

- 4 species;
- 4 tests;
- 3 visible disguise layers;
- deterministic evidence reactions;
- 8 generated/modular subjects;
- evidence notebook.

## 6.4 Kill thresholds

Kill if:
- one test has highest expected information in >70% of generated subjects;
- optimal test order is fixed for more than half the roster;
- text reading becomes >50% of decision time;
- modular disguise combinations look too repetitive without bespoke animation/art;
- testers enjoy reveal comedy but cannot articulate deduction logic.

## 6.5 Dominant-strategy attack — fixed test order

Tests must have conditional costs: Heat destroys scent, Brush obscures powder residue, Light is blocked by metallic coating, Sound startles certain species and changes posture. Limited test budget prevents checklisting.

This creates a real deduction game but also multiplies authored reaction matrix and tutorial burden.

## 6.6 >=20-situation proof

Combinatorially easy to reach 20 through species × disguise × test-order interactions, but meaningful distinctness requires many reaction assets/rules. This is the semifinalist most likely to satisfy variety numerically while hiding production cost.

## 6.7 Burden

- Art/animation: **Very High relative to factory target**
- UI: **Medium**
- Simulation: **Low–Medium**
- Content authoring: **Very High**
- QA: **High** reaction matrix

**Run-4 verdict: ELIMINATED.** Excellent pitch and streamer reaction potential, but the concrete mature game depends on a large authored disguise/species/test matrix. A cheap modular version risks visible repetition; a rich version violates the preferred production profile.

---

# 7. S6 — One-Room Convoy

## 7.1 Exact first 5 minutes

0:00–0:45 — three autonomous units loop around one arena. Flip one junction to send blue unit to extraction.
0:45–1:30 — red hazard enters loop; redirect green unit around it.
1:30–2:20 — two units approach same junction; preview shows collision unless player changes route.
2:20–3:15 — junction lock lasts 3 seconds after flip, introducing commitment.
3:15–4:15 — objective needs two differently tagged units to reach stations in order.
4:15–5:00 — player recovers from near collision by using a temporary bypass.

## 7.2 Representative mature 30-minute session

A 6–10 minute run uses 5 autonomous agents, 6 junctions, hazards, role-specific destinations and combo objectives. Player continuously triages. A 30-minute session is several compact runs with mutated rules/objectives, not one exhausting half-hour board.

## 7.3 Smallest graybox

- one loop + two cross-links;
- 4 autonomous discs;
- 4 toggle junctions;
- one hazard;
- two destinations;
- route preview;
- optional slow mode.

## 7.4 Kill thresholds

Kill if:
- safe-loop/stalling strategy clears >50% of scenarios;
- optimal play regularly reduces to handling one unit at a time;
- >4 agents makes causal readability collapse;
- pause/slow mode trivializes challenge while real-time mode feels unfair;
- players compare it primarily to traffic routing rather than live tactical triage.

## 7.5 Dominant-strategy attack — safe loop/stalling

Objectives use deadlines/decaying value; junctions have cooldowns; some agents cannot share loops; hazards migrate. Yet anti-stall pressure risks turning the game into pure frantic APM.

## 7.6 >=20-situation proof

Easy from unit roles, destinations, hazards, locked junctions, deadlines and ordered arrivals. However many scenarios share the same perceptual pattern: watch discs, flip arrows before collision. Hour-10 expressive ceiling is less convincing than the three leading concepts.

## 7.7 Burden

- Art: **Low**
- UI: **Medium–High**
- Simulation/pathing: **Medium–High**
- Content: **Medium**
- QA: **High** deadlocks and edge states

**Run-4 verdict: ELIMINATED.** Very prototype-friendly, but mature play risks becoming either traffic optimization or high-APM junction whack-a-mole. The three finalists have clearer second-order identity.

---

# 8. Comparative production / risk matrix

Scale 1 = low burden/risk, 5 = extreme.

| Concept | Art | UI clarity | Simulation/feel | Content | QA/balance | Trailer/hook | Hour-10 depth confidence | Portfolio diversity |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| **False Map Department** | 2 | 4 | 3 | 4 | 4 | 5 | 5 | 4 |
| **Orbit Graffiti** | 2 | 3 | 5 | 3 | 4 | 5 | 4 | 5 |
| **Pocket Weather War** | 2 | 4 | 4 | 3 | 5 | 5 | 5 | 5 |
| Echo Sculptor | 2 | 3 | 3 | 4 | 4 | 4 | 3 | 4 |
| Creature Costume Inspector | 5 | 3 | 2 | 5 | 4 | 5 | 4 | 5 |
| One-Room Convoy | 2 | 4 | 3 | 3 | 4 | 4 | 3 | 5 |

The top three are not the three cheapest. They are the three where the extra risk buys a materially stronger product identity.

---

# 9. Finalist reduction

## FINALIST A — False Map Department
**Why it survives:** strongest one-sentence causal hook, works in primitive visuals, immediate feedback, deep rule recombination, low structural repetition versus Game #001.

**Must prove before selection:** reasoning must beat brute-force undo; world/map linkage must remain readable with multiple interacting conventions.

## FINALIST B — Orbit Graffiti
**Why it survives:** most different playstyle in the factory portfolio, exceptional clipability and mastery expression, low authored-content burden if movement feels good.

**Must prove before selection:** drawing and riding must feel like one continuous movement verb on mouse and controller; safe rails must not dominate.

## FINALIST C — Pocket Weather War
**Why it survives:** weather-as-army remains a distinct tactical proposition, deterministic fronts can generate systemic depth, compact boards and reusable rules fit scope.

**Must prove before selection:** forecast must be intuitively readable and openings must not collapse into extreme-climate/turtle patterns.

### Eliminated this run
- Echo Sculptor — elegant but risks laser-routing-with-audio perception unless complexity grows beyond efficient scope.
- Creature Costume Inspector — content/art reaction matrix becomes too expensive to sustain its promise.
- One-Room Convoy — mature identity risks collapsing toward traffic routing or frantic junction micromanagement.

---

# 10. Cross-finalist decision frame for Run 5

Do **not** choose by aggregate score alone. Run 5 must stage a final three-way duel around the thing each concept claims to uniquely own.

### A. False Map Department must answer
- What exactly are the 6–8 canonical map conventions at product scope?
- How does the game prevent exhaustive legal-edit search without punishing experimentation?
- What does hour 10 add besides more symbols?
- Can one screenshot visibly communicate “the map changes reality”?

### B. Orbit Graffiti must answer
- Exact movement equations/assists at conceptual level.
- Exact controller drawing grammar.
- How levels preserve flow while allowing authored rail expression.
- Whether score attack is optional mastery or required product identity.

### C. Pocket Weather War must answer
- Exact discrete front rules for one representative ruleset.
- Exact turn structure and forecast semantics.
- How AI/opposition works without requiring expensive strategic AI.
- How terrain/objectives prevent solved openings.

### Mandatory final duel
For each finalist, specify:
1. one-sentence Steam pitch;
2. 10-second muted trailer beat;
3. first 15 minutes;
4. hour-10 mastery example;
5. minimum shippable scope;
6. one-week graybox test plan;
7. kill threshold;
8. most likely negative Steam review;
9. strongest defensible advantage over known analogues;
10. implementation burden under a solo/small-team assumption.

Then choose **one** concept or, if evidence is genuinely tied, explicitly require a tiny prototype duel before Product Thesis lock.

No Product Thesis is locked in Run 4.
