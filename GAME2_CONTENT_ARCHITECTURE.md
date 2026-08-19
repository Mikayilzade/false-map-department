# GAME #002 — FALSE MAP DEPARTMENT — CONTENT ARCHITECTURE

Last updated: 2026-08-18
Factory run: **7**
Phase: **5 — Content Architecture**
Product thesis: **LOCKED**
Mechanical architecture: **COMPLETE ON PAPER**
DESIGN COMPLETE: **NO**

This file is the canonical Phase-5 content specification for False Map Department. It defines what content exists, how it is introduced and recombined, the data contracts that content authors must fill, the campaign complexity curve, demo slice, validation requirements, mastery variants, and the hard 1.0 content ceiling. It does not add a seventh map primitive or a new agent interpretation mechanic.

---

# 1. Content strategy contract

False Map Department must feel deeper because the same small map vocabulary acquires more consequences, not because the player receives endless new tools.

The content strategy therefore obeys six rules:

1. **Six primitive families remain the entire 1.0 player edit vocabulary.** Road, bridge, border, waterway, landmark semantic label, restricted zone.
2. **Difficulty grows through interpretation density.** More agents, objectives, invariants, linked authority and short deterministic reaction chains are preferred over new exceptions.
3. **Each dossier has one central causal lesson.** Secondary twists may combine systems, but no dossier may require the player to discover multiple undocumented rules at once.
4. **Multiple valid final states are preferred.** Authored content defines goals and constraints, not one hidden target map.
5. **Visual themes change context, not physics.** A coastal, upland or civic-core district may look and read differently while using the same canonical semantics.
6. **Campaign content is authored and validated.** Challenge/remix content may reuse authored substrates and parameter swaps, but 1.0 does not depend on unconstrained procedural generation.

---

# 2. 1.0 campaign shape

## 2.1 Final target count

**40 authored dossiers** is the Phase-5 target and design ceiling for the base campaign.

Allowed production adjustment before specification freeze: **36–42** only if playtest pacing proves necessary. The canonical planning structure assumes 40.

A first clear should target roughly **5–8 hours**, with large variance by player reasoning speed. Optional mastery can extend play without mandatory grind.

## 2.2 Five-act curve

The campaign is divided into five internal acts of eight dossiers each. Act labels are production structure, not necessarily literal player-facing chapter names.

### Act I — Local Authority, D01–D08
Goal: make map -> world causality obvious and pleasurable.

Complexity ceiling:
- one map layer;
- 1–3 editable primitive families per dossier;
- 1–3 agents;
- one primary goal plus at most one invariant;
- reaction window 1–2 beats;
- no linked maps;
- no Stability longer than 1 cycle.

### Act II — Competing Interpretations, D09–D16
Goal: show that identical physical map facts are interpreted differently by agent classes and jurisdictions.

Complexity ceiling:
- one map layer;
- 3–5 primitive families available;
- 2–5 agents;
- 2 goals or 1 goal + 2 invariants;
- reaction window 1–3 beats;
- Stability 0–2 cycles;
- semantic relabeling and permission conflicts become normal.

### Act III — Civic Chains, D17–D24
Goal: make second-order consequences routine without becoming opaque.

Complexity ceiling:
- one main map layer plus optional simple linked inset in D23–D24;
- all six primitive families may appear, but normally only 4–5 are editable in one dossier;
- 4–7 agents;
- 2–3 goals plus 1–2 invariants;
- reaction window 2–4 beats;
- Stability 1–3 cycles;
- route, ownership, service and restricted-access chains intersect.

### Act IV — Linked Authority, D25–D32
Goal: introduce scale ownership and remote consequences deliberately.

Complexity ceiling:
- 2 linked layers normally; never more than 3 in Act IV;
- all primitive families possible;
- 5–9 agents across layers;
- 3 goals/invariants total at D25, rising to 4–5 by D32;
- reaction window 2–5 beats;
- Stability 2–4 cycles;
- Regional Connector appears;
- every cross-layer fact has explicit one-way authority.

### Act V — Department Cases, D33–D40
Goal: prove mastery through compact causal reasoning rather than feature escalation.

Complexity ceiling:
- 2–4 linked map layers, with **4 absolute maximum for 1.0**;
- no new primitive families;
- 6–10 agents, but only if silhouettes/routes remain readable;
- 3–4 completion goals plus up to 2 protected invariants;
- reaction window maximum 5 beats;
- Stability maximum 5 cycles;
- late dossiers combine semantic, jurisdiction, route and cross-layer authority deliberately.

D40 is a synthesis case, not a boss with bespoke mechanics.

---

# 3. Primitive introduction and recombination order

The six primitive families are introduced in this order because each expands causal reasoning while preserving legibility.

## D01–D02 — Road
- D01: add one road to make a direct courier route.
- D02: remove/reroute a road to prevent an undesirable route while preserving another.

Lesson: map geometry is executable and route changes are immediate.

## D03–D04 — Bridge + water relationship
- D03: place a bridge on a legal crossing.
- D04: a bridge helps one agent while creating collateral connectivity for another.

Lesson: a beneficial connection can create second-order access.

## D05–D06 — Border
- D05: move jurisdiction ownership to unlock/deny a gate or resident path.
- D06: route and ownership objectives conflict.

Lesson: a line need not be a physical wall to change reality.

## D07–D08 — Restricted zone
- D07: restrict one agent class while preserving another.
- D08: first compact synthesis: road + bridge + border + zone; first optional mastery.

Lesson: shared topology can have class-specific permissions.

## D09–D10 — Landmark semantic label
- D09: relabel one landmark to redirect a Semantic Seeker or Courier.
- D10: duplicate/competing semantic targets demonstrate deterministic nearest/stable-ID resolution visibly.

Lesson: words on the official map are executable facts.

## D11–D12 — Waterway editing
- D11: reroute/toggle water connectivity for Ferry access.
- D12: water edit invalidates/changes a road crossing and forces a multi-system solution.

Lesson: changing one network can mutate validity of another without hidden simulation.

## D13 onward — no new primitive family
From D13, all difficulty comes from recombination, agent interpretation, objectives/invariants, Stability and later linked layers.

---

# 4. Agent roster decision

Phase 4 defined ten archetypes as the maximum mechanical ceiling. Phase 5 keeps all ten mechanically valid, but does not expose all of them equally.

## Core campaign roster — eight common archetypes

1. **A1 Direct Courier** — survives unchanged. Bread-and-butter route + semantic target learner.
2. **A2 Jurisdiction-Locked Resident** — survives unchanged. Primary border-permission learner.
3. **A3 Patrol** — survives; used sparingly because nearest-in-jurisdiction behavior can create visual route noise.
4. **A4 Livestock / Unrestricted Roamer** — survives and is important for collateral connectivity/comedic consequence.
5. **A5 Emergency Service** — survives; contrasts restricted-zone rules and priority.
6. **A6 Commercial Carrier** — survives, but any tax/funding fiction remains a visible binary service dependency, never a city economy.
7. **A7 Ferry / Water Carrier** — survives as the canonical water-network interpreter.
8. **A9 Semantic Seeker** — survives; primary landmark-label specialist.

## Specialist roster — controlled use

9. **A8 Procession / Route-Constrained Agent** — survives as authored specialist. It appears first in Act III and never carries more than one route predicate plus one visible exception in a dossier. Avoid turning it into a bespoke logic-script engine.

10. **A10 Regional Connector Agent** — reserved for Act IV/V only. It exists solely to make linked-map authority concrete and must never appear before the player understands one-layer causality.

## Merge/rejection decision
No Phase-4 archetype is deleted because each currently has a unique visible interpretation role. However:
- themed variants do not count as new archetypes;
- Patrol and Commercial Carrier may share art rigs but not logic;
- Direct Courier and Semantic Seeker must remain distinguishable: Courier may have an exact named task/destination, Semantic Seeker resolves semantic class/name queries and duplicate matches;
- if prototype testing shows either pair is not behaviorally legible, Phase 10 must merge rather than add explanatory complexity.

---

# 5. Canonical content data schema

Content must be data-driven enough that implementation can validate every dossier without hardcoding case logic.

## 5.1 `DossierContentDefinition`
Required fields:
- `dossier_id`
- `act_index`
- `title_token`
- `brief_text_token`
- `theme_id`
- `tutorial_tags[]`
- `map_layers[]`
- `jurisdictions[]`
- `landmarks[]`
- `restricted_zone_policies[]`
- `agents[]`
- `objectives[]`
- `protected_invariants[]`
- `reaction_beats_after_edit`
- `stability_required_cycles`
- `editable_primitive_permissions`
- `semantic_label_vocabulary[]`
- `linked_authority_relations[]`
- `mastery_contracts[]`
- `validation_metadata`
- `hint_contracts[]` reserved for Phase 6 UX specification; content may identify causal lesson but not encode answer moves.

## 5.2 `MapLayerContent`
Fields:
- `layer_id`
- `display_scale_type {district, subdistrict, regional, inset}`
- `nodes[]`
- `candidate_road_edges[]`
- `candidate_water_edges[]`
- `cells[]`
- `crossing_slots[]`
- `landmark_slots[]`
- `portal_nodes[]`
- `immutable_features[]`
- `initial_primitives`
- `editable_candidates`
- `visual_bounds`
- `authority_owner_by_fact_family`

## 5.3 `JurisdictionContent`
Fields:
- `jurisdiction_id`
- `display_name_token`
- `pattern/icon`
- `initial_owned_cells[]`
- `required_exist`
- `allowed_border_candidates[]`

No economy or numeric tax simulation field is permitted. Funding/service relationships are authored binary facts expressed through objective/agent rules already supported mechanically.

## 5.4 `LandmarkContent`
Fields:
- `landmark_id`
- `slot_id`
- `initial_semantic_label`
- `allowed_semantic_labels[]`
- `physical_category_visual`
- `jurisdiction_sensitive yes/no`
- `service_tags[]` drawn only from already defined agent/objective vocabulary.

The physical object does not transform merely because its semantic label changes unless an existing visible rule explicitly queries the label.

## 5.5 `RestrictedZonePolicyContent`
Fields:
- `policy_id`
- `allowed_agent_tags[]`
- `denied_agent_tags[]`
- `display_pattern/icon`
- `candidate_cells[]`
- `initial_cells[]`

## 5.6 `AgentContent`
Fields:
- `agent_id`
- `archetype_id A1..A10`
- `start_node_or_cell`
- `semantic_target`
- `allowed_jurisdictions[]`
- `movement_tags[]`
- `zone_permission_tags[]`
- `priority_class`
- `task_flags`
- `procession_predicate` only for A8
- `portal_contract` only for A10
- `visual_variant_id`

No dossier-specific behavior script may override the archetype's canonical interpretation semantics.

## 5.7 `ObjectiveContent`
Fields:
- `objective_id`
- `family_id`
- `subject_ids/tags`
- `target_ids/tags`
- `predicate_parameters`
- `evaluation_timing {post_reaction, stability_cycle, final}`
- `required yes/no`
- `player_visible_text_token`
- `status_explanation_token`

## 5.8 `LinkedAuthorityRelation`
Fields:
- `source_layer_id`
- `source_fact_id/family`
- `target_layer_id`
- `target_projection_id`
- `projection_semantics`
- `direction one-way`
- `portal_ids[]`

Validation must reject cycles or double ownership of the same authoritative fact.

---

# 6. Objective and invariant families

The base game targets **12 reusable families**. A dossier may theme them differently but may not invent hidden evaluation logic.

## O1 — Reachability
A subject agent/class must be able to reach a target landmark/zone.

## O2 — Non-Reachability / Exclusion
A subject must not be able to reach or enter a protected target.

## O3 — Route Length / Service Time Bound
A visible route must be at or below an authored edge-cost threshold.

## O4 — Jurisdiction Membership
Specified cells/landmarks/agents must lie in, remain in or avoid a named jurisdiction.

## O5 — Permission Compliance
Specified agent class must have a legal route respecting jurisdiction/zone permission.

## O6 — Water Connectivity
Named docks/ports must be connected or separated on the water graph.

## O7 — Semantic Destination
A named/semantic agent must resolve to a required destination or category.

## O8 — Visit/Sequence Constraint
A8 must pass through a visible sequence or exact jurisdiction-count predicate.

## O9 — Protected Adjacency
A protected feature must not gain specified road/water/zone adjacency, or must retain required adjacency.

## O10 — Network Continuity
A designated network subset must remain connected, or specific components must remain separated.

## O11 — Stable Service State
A conjunction of route + ownership/permission/service facts must remain true across N Stability cycles.

## O12 — Cross-Layer Connector State
A portal/route at one scale must remain available or resolve to a target state determined by another authoritative layer.

### Distribution rule
- Act I uses O1/O2/O4/O5 primarily.
- Act II adds O3/O6/O7/O9.
- Act III adds O8/O10/O11.
- Act IV introduces O12.
- Act V recombines all families but adds none.

No dossier may use more than **five required evaluation clauses** before D33, or **six** in D33–D40. A conjunction inside one player-facing objective may contain multiple machine predicates only if the UI explains them as one coherent civic requirement.

---

# 7. Protected invariant philosophy

An invariant exists to make an easy local fix incomplete, not to create gotcha failure.

Required rules:
- every invariant is visible before the player edits;
- its current truth state is inspectable;
- when broken, causal ancestry points to the first relevant edit/consequence;
- early invariants are local and immediate;
- delayed/remote invariants appear only after the player has learned Stability;
- no hidden optional condition may silently become required for completion.

Common invariant templates:
- keep hospital reachable;
- keep wetland road-adjacency at zero;
- keep jurisdiction non-empty;
- keep livestock out of school/garden zone;
- keep ferry route connected;
- keep emergency route <= threshold;
- preserve one protected bridge/corridor;
- keep portal service active across Stability window.

---

# 8. Visual/theme families

1.0 uses **four** visual district families, sharing exact mechanical symbol grammar.

## T1 — Canal Borough
Visual cues: canals, low bridges, quays, gardens, market lanes.
Good for: road/bridge/water/ferry interactions.

## T2 — Civic Core
Visual cues: administrative blocks, hospitals, schools, plazas, gates, denser road lattice.
Good for: borders, restricted zones, semantic landmarks, emergency routing.

## T3 — Upland Counties
Visual cues: villages, winding authored graph geometry, pastures, reservoirs, sparse junctions.
Good for: jurisdiction, livestock collateral, longer route tradeoffs, protected adjacency.

## T4 — Regional Ledger
Visual cues: stylized atlas sheet, multiple inset districts, rail/road portal abstractions, stamps and filing overlays.
Good for: linked-map authority in Acts IV/V.

### Theme rule
Theme may change art, dossier fiction, landmark nouns and layout geometry. It may not change what a road, bridge, border, waterway, semantic label or restricted zone means mechanically.

A fifth theme is explicitly out of scope for 1.0 unless replacing one above.

---

# 9. Authored versus remix/challenge content

## 9.1 Main campaign
All 40 dossiers are authored and have validated solution envelopes.

## 9.2 Remix cases
After completing selected campaign milestones, the player may unlock **12 remix cases** built from existing validated substrates.

A remix may change only a bounded parameter set:
- initial primitive state;
- agent start nodes;
- semantic target assignments;
- allowed semantic label vocabulary;
- jurisdiction initial ownership within prevalidated border candidates;
- optional mastery threshold;
- objective selection from a prevalidated family set.

A remix may not:
- invent new graph topology;
- invent an agent script;
- invent a new primitive;
- create linked authority not present in the substrate;
- randomly choose parameters without solvability validation.

## 9.3 Daily/procedural content
Not required for 1.0. No live service or daily challenge dependency.

## 9.4 Replay value
Replay is driven by:
- alternative valid final states;
- optional mastery contracts;
- causal comprehension;
- remix cases;
- revisiting dossiers after later systems are understood.

The game does not need grind currency, random loot or repeated farming.

---

# 10. Linked-map placement and complexity curve

Linked maps are deliberately late because they multiply representation cost.

- D01–D22: **one authoritative layer only**.
- D23: first non-editable inset preview showing that a local connector projects upward. Teaching only; no two-layer edit choice.
- D24: first authored one-way local -> regional projection, but edits remain local.
- D25: first true two-layer dossier with exactly one editable fact family on the regional layer.
- D26–D28: two layers; one or two cross-layer projections.
- D29–D32: two to three layers; maximum three linked relations relevant to one solution chain.
- D33–D36: up to three layers.
- D37–D40: up to four layers, but at most **two layers visible/editable simultaneously**; player switches/focuses between paired views.

Absolute 1.0 ceilings:
- four layers in one dossier;
- six portal relations;
- four cross-layer authoritative projections;
- no authority cycle;
- each fact has exactly one owner.

If usability testing shows players cannot explain one remote consequence in D25–D28, Act V may not increase the layer count; content must compress instead.

---

# 11. Content solvability and validation

Every dossier must pass both structural validation and solution validation before being shippable.

## 11.1 Static structural checks
Automated checks should reject:
- invalid initial border topology;
- orphaned required jurisdiction;
- candidate road/water edges that violate authored planar constraints;
- bridge crossing slots without valid road/water candidate geometry;
- semantic label references not in allowed vocabulary;
- duplicate stable IDs;
- agent start on nonexistent node/cell;
- objective references to nonexistent content;
- illegal restricted-zone policies;
- linked authority cycles;
- multiple authoritative owners for one fact;
- portal target missing;
- reaction/stability count outside Phase-4 ceilings;
- unsupported A8/A10 specialist fields on other archetypes.

## 11.2 Initial-state checks
The dossier must intentionally declare whether it starts:
- currently failing one or more goals;
- currently satisfying an invariant;
- with agents blocked/trapped.

No accidental already-complete dossier is allowed unless it is an explicit tutorial demonstrating consequence from the first edit.

## 11.3 Solvability proof
Each authored campaign dossier stores at least:
- one known baseline-valid final map state or deterministic action path;
- expected required objective/invariant truth state;
- expected Stability outcome;
- proof that every required player edit is structurally legal under canonical mechanics.

The stored solution is validation evidence, **not** an in-game answer oracle.

## 11.4 Alternative-solution search
For mature dossiers, build-time tooling should enumerate or sample reachable legal states within bounded depth where feasible to detect:
- unintended trivial one-edit solution;
- unique brittle pixel-like solution;
- dominant repeated template;
- impossible mastery threshold;
- brute-force branching collapse.

Full exhaustive solving is not required for all late dossiers if state space is too large, but every dossier requires automated structural validation plus targeted authored/adversarial solver tests.

## 11.5 Anti-template validation
No sequence of three consecutive campaign dossiers may be solved primarily by the same pattern, such as:
- always add bridge;
- always move border toward target;
- always relabel nearest landmark;
- always isolate livestock;
- always preserve maximum connectivity.

Content review tags each dossier with its intended `primary_reasoning_pattern`; adjacent duplicates require explicit justification.

---

# 12. Tutorial and first 15–25 minute demo slice

## 12.1 Tutorial philosophy
Tutorial is playable consequence, not a manual.

Rules:
- one new primitive concept at a time;
- show world consequence before giving a long explanation;
- require prediction immediately after demonstration;
- the player can undo from tutorial step one;
- no full terminology dump;
- no dense bureaucracy comedy before the causal hook is understood.

## 12.2 Demo structure
Target first-time demo: **20–25 minutes median**, with a fast player able to finish in ~15.

Demo content:
1. **D01 Bridge to Work** — road/bridge causal spectacle compressed tutorial.
2. **D02 Wrong Turn** — road removal/reroute.
3. **D03 The Garden Problem** — beneficial bridge creates livestock collateral.
4. **D05 Border Hours** — border changes permission without physical wall.
5. **D07 Quiet Zone** — restricted-zone class difference.
6. **D08 First Dossier** — compact synthesis with two goals, one invariant and optional mastery.

The demo may renumber these internally for presentation, but production should preserve campaign mapping metadata for save import if later commercial design chooses transferable progress.

## 12.3 Demo must communicate
Before demo end, player must have experienced:
- map fact creates immediate world fact;
- one locally helpful edit creates collateral harm;
- border semantics are non-physical but causal;
- at least two agents interpret the same topology differently;
- Undo is safe;
- one causal-chain explanation;
- optional elegance/mastery without punishment for experimentation.

## 12.4 Excluded from demo
Do not include:
- landmark semantic relabeling;
- waterway editing beyond static water needed for bridges;
- Ferry;
- Procession;
- Commercial Carrier service chains;
- linked maps;
- Regional Connector;
- long Stability >1;
- more than four simultaneous agent silhouettes.

Reason: the demo sells the ontological-map hook, not the entire rulebook.

---

# 13. Mastery / medal architecture

Baseline completion is binary: all required goals/invariants pass through required Stability.

Optional mastery uses **three independent badge families**, never a mandatory currency ladder.

## M1 — Clean Intervention
Measured from final intervention footprint, not raw undo/history.
Examples:
- final changed primitive count <= threshold;
- no unnecessary retained change outside causal solution set.

## M2 — Civic Care
Measured by optional protected conditions beyond baseline.
Examples:
- preserve an extra route;
- keep collateral agent delay below threshold;
- retain optional habitat adjacency rule.

These conditions are visible before attempt and never silently required.

## M3 — Stable Authority
A harder Stability window or robustness variant.
Examples:
- survive 5 cycles instead of 2;
- keep all optional service routes active throughout.

### Medal rule
A dossier may offer at most **two** mastery badges in the campaign. Late challenge/remix cases may offer all three.

No badge may require:
- zero undo;
- no experimentation;
- time pressure;
- hidden solution uniqueness;
- exact click sequence.

Mastery is optional evidence of understanding, not punishment for learning.

---

# 14. Anti-repetition architecture

Each dossier receives tags:
- `primary_primitive_focus`
- `secondary_primitive_focus`
- `primary_agent_interpretation`
- `objective_family_mix`
- `primary_reasoning_pattern`
- `collateral_type`
- `linked_layer_depth`
- `stability_depth`

Campaign assembly rules:
1. never introduce two new primitive families in the same dossier;
2. after D12, no more than two consecutive dossiers may share the same primary primitive focus;
3. no more than two consecutive dossiers may feature the same primary agent archetype;
4. every four-dossier block after D12 must include at least three objective families;
5. every Act III+ block of four must include at least one solution where **removing** or relabeling is better than adding infrastructure;
6. every Act III+ block of four must contain at least one case where maximum connectivity is harmful;
7. Act IV/V must alternate local-causal and remote-causal emphasis so linked maps do not become constant bookkeeping;
8. comedic collateral (livestock etc.) must not become the default joke every case.

---

# 15. Representative campaign spine

This is not the full final level script but locks introduction/function expectations.

| Dossier | Main lesson / combination |
|---|---|
| D01 | Road creates route; immediate map/world twin |
| D02 | Remove road to redirect |
| D03 | Bridge crossing basics |
| D04 | Bridge creates collateral access |
| D05 | Border changes permission/ownership |
| D06 | Border + route tradeoff |
| D07 | Restricted-zone class permission |
| D08 | First synthesis + invariant + mastery |
| D09 | Landmark relabel redirects semantic target |
| D10 | Duplicate semantic destination resolution |
| D11 | Water connectivity + Ferry |
| D12 | Water edit changes bridge/road validity |
| D13 | Emergency ignores one zone restriction |
| D14 | Commercial carrier needs route + permission/service |
| D15 | Protected adjacency versus connectivity |
| D16 | First 2-cycle Stability dossier |
| D17 | Patrol jurisdiction shift creates remote route change |
| D18 | Procession exact jurisdiction-count route |
| D19 | Water + semantic destination chain |
| D20 | Multi-agent conflict with emergency priority |
| D21 | Network continuity with deliberate local isolation |
| D22 | Three-system causal chain, one-layer mastery exam |
| D23 | Linked-map inset preview only |
| D24 | Local edit projects to fixed regional connector |
| D25 | First editable two-layer authority case |
| D26 | Two layers, route + jurisdiction projection |
| D27 | Two layers, semantic target changes connector destination |
| D28 | Two layers, water/ferry dependency across portal |
| D29 | Three-layer introduction with only one remote chain active |
| D30 | Regional Connector competes with local invariant |
| D31 | Cross-layer Stability |
| D32 | Act IV synthesis, four evaluation clauses |
| D33 | Compact three-layer optimization, no new rules |
| D34 | Semantic relabel beats infrastructure expansion |
| D35 | Maximum connectivity is explicitly wrong |
| D36 | Border move solves three systems but harms optional mastery |
| D37 | Four-layer case, only two views editable at once |
| D38 | Portal authority + Procession route requirement |
| D39 | Multi-solution civic synthesis with 5-cycle Stability optional mastery |
| D40 | Final department case: 3–4 layers, all learned grammar, no bespoke boss mechanic |

---

# 16. Narrative/framing content ceiling

Narrative exists to give civic meaning and tone to mechanical facts.

Allowed:
- 1–3 short dossier paragraphs;
- one-line objective/invariant labels;
- department stamps, margin notes, absurd bureaucratic case names;
- short completion annotations;
- environmental miniature-world details.

Not required:
- voiced dialogue;
- branching conversations;
- named cast arcs with cutscenes;
- collectible lore logs required for understanding mechanics.

Narrative text may never hide a rule needed for deterministic solution.

---

# 17. 1.0 hard content ceiling

The following are frozen Phase-5 maximums unless a later review explicitly reopens content scope:

- 40 target authored campaign dossiers; 42 hard planning ceiling.
- 12 remix cases.
- 6 player primitive families, no more.
- 10 mechanical agent archetypes, no more; 8 common + 2 specialist.
- 12 objective/invariant families, no more without Phase-4/5 reopen.
- 4 visual district families.
- 4 linked map layers maximum in any dossier.
- 10 agents maximum in one dossier.
- 6 required evaluation clauses maximum in late game.
- 5 reaction beats maximum.
- 5 Stability cycles maximum.
- 8 legal semantic labels in one dossier.
- no procedural infinite campaign.
- no Workshop/UGC dependency.
- no multiplayer/co-op.
- no city-builder economy.

Expansion/DLC may add authored dossiers, themes and combinations primarily from the same grammar. A true seventh primitive or eleventh agent interpretation is a mechanical expansion and must not be slipped into 1.0 polish.

---

# 18. Content-production risks

## R5-01 — Solvability/QA cost: HIGH
Linked deterministic puzzles can accumulate large state spaces. Mitigation: strict graph bounds, authored known solutions, static validators, targeted state search and hard late-game complexity ceilings.

## R5-02 — Semantic/UI overload: HIGH
Ten agents are too many if introduced as ten rule cards. Mitigation: eight common archetypes introduced gradually; specialists late; strong visual route/permission previews deferred to Phase 6.

## R5-03 — Repetition: MEDIUM-HIGH
Forty dossiers can feel like checkbox variations if content authors overuse bridge/route fixes. Mitigation: campaign tagging and anti-template rules above.

## R5-04 — Linked-map bookkeeping: HIGH
Remote authority is potentially brilliant or exhausting. Mitigation: no true two-layer edit until D25, four-layer absolute ceiling, only two editable views simultaneously, empirical readability gate.

## R5-05 — Authoring burden: MEDIUM-HIGH
Each mature dossier needs validation and causal clarity. Mitigation: data-driven schema, reusable theme/agent vocabulary, no bespoke scripted exceptions.

## R5-06 — Demo over-teaching: MEDIUM
The full system is too large for a demo. Mitigation: demo excludes semantic/water editing and linked maps; sells immediate causality + first collateral consequence.

---

# 19. Phase-5 acceptance tests

### Structure/content contract
- **C5-01** Campaign planning target is 40 authored dossiers and does not exceed 42 without reopening scope.
- **C5-02** Every campaign dossier uses only the six Phase-4 primitive families.
- **C5-03** Every agent instance maps to A1–A10 with no dossier-specific behavior override.
- **C5-04** All themed variants preserve canonical primitive semantics.
- **C5-05** Every player-facing required condition maps to one of O1–O12 or an explicit conjunction of them.

### Introduction/pacing
- **C5-06** No dossier introduces two previously unseen primitive families simultaneously.
- **C5-07** Landmark relabeling does not appear before road/bridge/border/zone fundamentals have been demonstrated.
- **C5-08** Editable waterway behavior appears only after static bridge/water relationship is understood.
- **C5-09** A8 Procession appears no earlier than Act III.
- **C5-10** A10 Regional Connector appears no earlier than Act IV.
- **C5-11** True editable linked-map authority begins no earlier than D25.

### Validation
- **C5-12** Every dossier passes stable-ID and reference validation.
- **C5-13** Every border initial state is structurally valid.
- **C5-14** Every bridge crossing slot has valid authored road/water geometry.
- **C5-15** Every linked authority graph is acyclic and has one owner per fact.
- **C5-16** Every campaign dossier stores at least one known valid completion proof.
- **C5-17** Every mastery threshold has at least one known satisfying solution/evidence path.
- **C5-18** Initial-state accidental completion is detected automatically.

### Anti-repetition/bruteforce
- **C5-19** No three consecutive dossiers share the same primary reasoning pattern.
- **C5-20** Act III+ four-dossier blocks include at least one anti-max-connectivity case.
- **C5-21** Act III+ four-dossier blocks include at least one case whose elegant solution removes or relabels instead of only adding infrastructure.
- **C5-22** Mature dossier validation explicitly checks for unintended trivial one-edit solutions.
- **C5-23** Mature dossier review checks whether legal-edit enumeration outperforms causal reasoning.

### Complexity ceilings
- **C5-24** No dossier exceeds four linked layers.
- **C5-25** No dossier exceeds ten active agents.
- **C5-26** No dossier exceeds Phase-4 reaction/stability ceilings.
- **C5-27** At most two layers are editable/visible as active editing surfaces simultaneously in four-layer content.

### Demo/mastery
- **C5-28** Demo delivers map->world causality, collateral consequence, border semantics, agent interpretation difference, safe Undo and causal explanation within its 15–25 minute slice.
- **C5-29** Demo excludes true linked maps and late specialist agent logic.
- **C5-30** No mastery contract scores raw Undo count or blind experimentation history.
- **C5-31** Campaign dossiers offer at most two optional mastery badge families each.

### Content closure
- **C5-32** A fresh Phase-6 designer can determine campaign count, content fields, rule-introduction order, agent roster, objective families, linked-map curve, demo boundary and validation obligations without inventing new content architecture.

---

# 20. Phase-5 closure decision

- Campaign count/curve defined: **YES**
- Primitive introduction/recombination order defined: **YES**
- Agent roster survival/specialist policy defined: **YES**
- Content data schema defined: **YES**
- Objective/invariant families defined: **YES**
- Visual/theme families defined: **YES**
- Authored/remix strategy defined: **YES**
- Linked-map complexity curve defined: **YES**
- Solvability/validation requirements defined: **YES**
- Tutorial/demo slice defined: **YES**
- Mastery variants and anti-repetition rules defined: **YES**
- 1.0 content ceiling defined: **YES**
- Content-production risks recorded: **YES**
- Phase-5 acceptance tests defined: **YES — C5-01..C5-32**
- Production implementation started: **NO**
- Phase 5 complete on paper: **YES**
- DESIGN COMPLETE: **NO**

## NEXT PHASE
**Phase 6 — UX / Presentation Architecture.**

The next run must define the exact screen/state hierarchy, map/world presentation contract, controls for mouse+keyboard / keyboard-only / controller / Steam Deck, selection/snapping interactions for all six primitives, causal feedback, dossier brief/objective display, Undo/Redo history presentation, agent inspection, Stability Preview presentation, linked-map navigation, onboarding/tutorial delivery, accessibility modes, animation/audio redundancy, pause/settings/save/load/failure/recovery flows, first-session experience and Phase-6 acceptance tests. It must preserve the Phase-5 demo boundary and must not solve readability problems by adding hidden rules or mandatory freehand precision.