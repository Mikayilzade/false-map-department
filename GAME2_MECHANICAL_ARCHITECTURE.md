# GAME #002 — FALSE MAP DEPARTMENT — MECHANICAL ARCHITECTURE

Last updated: 2026-08-18
Factory run: **6**
Phase: **4 — Mechanical Architecture**
Product thesis: **LOCKED**
DESIGN COMPLETE: **NO**

This file is the canonical Phase-4 mechanical specification for False Map Department. It turns the Product Thesis into deterministic gameplay rules suitable for later content, UX and technical specification. No production code is started here.

---

# 1. Mechanical design contract

The central invariant is unchanged:

> **The map is not a representation of the world. The map is an executable authority over the world.**

Every player edit modifies authoritative map facts. Reality derives from those facts through deterministic rules. The player is never asked to guess an invisible random outcome, draw with pixel precision, wait through a long opaque simulation, or satisfy an undocumented exception.

The canonical edit vocabulary remains exactly six primitive families:
1. road segment;
2. bridge symbol;
3. border line;
4. waterway segment;
5. landmark marker/name;
6. restricted-zone hatch.

Phase 4 deliberately does **not** add magical one-off tools. Depth comes from different agents, goals and linked authority layers interpreting the same map facts differently.

---

# 2. Authoritative state model

A dossier owns one immutable `DossierDefinition` and one mutable `DossierState`.

## 2.1 DossierDefinition
Contains:
- one or more `MapLayerDefinition` objects;
- immutable topology bounds and snap points;
- editable primitive permissions by layer;
- jurisdictions and ownership identities;
- world entities/landmarks and stable IDs;
- agent archetypes and initial states;
- objective contracts;
- protected-invariant contracts;
- stability window length;
- mastery thresholds;
- linked-layer authority relations;
- deterministic tie-break ordering;
- dossier-specific legal-edit constraints only when explicitly authored and visible.

## 2.2 DossierState
Contains:
- authoritative current map primitives per layer;
- derived world topology;
- current jurisdiction assignment;
- current landmark semantic registry;
- current restricted-zone permissions;
- current agent states;
- current objective/invariant states;
- current stability-cycle counter;
- current intervention footprint for mastery;
- causal event graph for the latest edit and current stability sequence;
- undo/redo history cursor.

## 2.3 Stable identity rule
Every editable or simulated object has an immutable stable ID. Names are semantic properties, not IDs. Renaming `Hospital East` to `Depot` never changes the object's identity, only how semantic destination queries resolve.

## 2.4 Derived-state rule
The map primitives are authoritative. World roads, crossings, water connectivity, jurisdiction membership, landmark names and zone permissions are derived from the map after each accepted edit. Agent position/state is mutable simulation state, but the legal environment they use is always the latest derived world.

No world-side manual change may silently override map authority.

---

# 3. Spatial substrate and snapping

The default mechanical substrate is a bounded orthogonal or authored planar graph presented as a paper map and matching miniature world.

A layer exposes:
- `nodes`: legal junction/landmark/border vertices;
- `edges`: legal road/waterway candidates;
- `cells` or `faces`: jurisdiction/restricted-zone occupancy regions;
- `crossing_slots`: authored road-water crossing locations where bridges may exist;
- `landmark_slots`: stable semantic destinations;
- optional `portal_nodes`: links to another map scale.

Player interaction may look tactile, but edits snap to these primitives. The game never judges line-art resemblance or hand precision.

---

# 4. Canonical primitive semantics

## 4.1 Road segment

A road segment is an undirected traversable connection between two adjacent legal road nodes unless the dossier explicitly marks that candidate as one-way; one-way behavior is a property of the candidate edge, not a seventh player tool.

### Add road
Legal if:
- candidate road edge exists;
- road is currently absent;
- edge does not cross an active waterway except at a crossing slot with an active bridge;
- edge does not pass through a non-permitted hard geographic exclusion authored in the layer definition;
- linked-layer constraints, if any, allow local ownership of that edge.

Effect:
- `road_present(edge)=true`;
- road-using agent path graphs are invalidated and rebuilt;
- route-dependent objective facts are recomputed.

### Remove road
Legal if:
- road currently exists;
- it is editable in this dossier;
- it is not an immutable portal connector explicitly marked protected by dossier definition.

Effect:
- `road_present(edge)=false`;
- any bridge on that crossing remains as an object only if the crossing still has another legal road alignment; otherwise bridge validity is re-evaluated during derived-world validation.

Road removal may disconnect regions. Disconnection is **not automatically illegal**; it may be the intended puzzle action. Consequences are handled by agents/objectives.

## 4.2 Bridge symbol

A bridge is not free-standing terrain. It grants a crossing relation at one authored `crossing_slot` where a road candidate and active waterway intersect.

### Add bridge
Legal if:
- crossing slot exists;
- active waterway occupies the slot;
- at least one valid road alignment reaches both banks through that slot;
- no bridge currently exists there;
- bridge is editable.

Effect:
- corresponding road traversal across the active waterway becomes permitted for agent classes allowed by that bridge class; baseline bridges permit ordinary road users.

### Remove bridge
Legal if editable and present.

Effect:
- crossing becomes non-traversable for ordinary road users while waterway connectivity remains intact.

A bridge never deletes the waterway and never grants ownership by itself.

## 4.3 Border line

Borders partition authored cells/faces into jurisdictions. The player moves border edges only along legal boundary candidates; freeform polygons are forbidden.

### Border validity
After an edit:
- every jurisdiction that is required to exist must own at least one cell;
- each cell has exactly one jurisdiction owner unless explicitly marked neutral;
- border topology may not self-intersect;
- no dangling border segment may terminate in the interior unless an authored legal endpoint exists;
- jurisdiction connectivity is **not universally required**. A dossier/invariant may require contiguous territory, but disconnected ownership can be mechanically valid.

### Border consequence
Jurisdiction membership is recomputed for:
- cells;
- landmark slots;
- gates/ports/services with jurisdiction-aware behavior;
- agents whose permissions, taxes, patrols or targets depend on ownership.

Borders do not physically block traversal unless an agent archetype or restricted contract interprets jurisdiction change as a permission boundary.

## 4.4 Waterway segment

A waterway is a connected hydrological route on authored water edges. It blocks ordinary road traversal where the two cross unless an active legal bridge grants crossing.

### Add/reroute waterway
The player toggles authored water edges, not arbitrary fluid simulation.

Legal if:
- edge is an allowed water candidate;
- authored source/sink requirements remain satisfiable after the complete edit;
- no forbidden self-overlap occurs;
- map-layer authority permits local control.

### Remove waterway
Legal if editable. Removing a segment can split water connectivity; this is allowed unless a dossier contract forbids it.

### Effects
Recompute:
- water connectivity graph;
- ferry/boat path availability;
- road crossing legality;
- bridge validity;
- water-adjacency objective facts.

There is no simulated erosion, flooding or realistic hydrology in 1.0 unless later content uses a derived binary adjacency rule explicitly specified in Phase 5.

## 4.5 Landmark marker/name

A landmark has a stable object ID, fixed or editable physical slot, and a semantic `name_token` selected from a dossier-provided vocabulary.

Baseline player action is **rename/relabel**, not free-text arbitrary naming.

Why: arbitrary strings create localization, ambiguity and solver problems. A dossier provides 2–8 legal semantic labels such as `Hospital`, `Market`, `Depot`, `School`, `Gate A`, etc. Later content may permit moving a marker between authored landmark slots, but only if Phase 5 explicitly assigns that tool to the dossier.

### Rename effect
- stable landmark object remains the same;
- semantic destination registry is rebuilt;
- agents targeting a semantic name re-resolve their destination according to deterministic destination-selection rules;
- ownership and physical adjacency remain unchanged unless those systems separately depend on the landmark's semantic category.

Duplicate names are legal only when the dossier visibly allows them. If duplicates exist, agents use their archetype's deterministic selector, e.g. nearest reachable matching landmark then stable-ID tie-break.

## 4.6 Restricted-zone hatch

A restricted zone is a set of authored cells/faces tagged with a permission policy. Player editing toggles or reshapes the hatch along legal zone candidates; no freehand painting.

Each policy contains allowed/denied agent tags, e.g.:
- residents allowed, livestock denied;
- emergency allowed, commercial denied;
- patrol allowed, civilians denied.

Effects:
- path graphs for affected agent classes are rebuilt;
- zone membership objectives update;
- agents currently inside a newly forbidden zone enter the trapped/evacuation semantics defined below rather than teleporting.

Restricted zones do not change jurisdiction ownership and do not physically erase roads.

---

# 5. Edit legality pipeline

Every attempted edit passes the same deterministic pipeline before reality changes.

1. **Input snap** — resolve player intent to one exact candidate primitive.
2. **Permission check** — is that primitive/type editable in this dossier/layer?
3. **Structural check** — would the map itself violate topology rules (self-intersection, malformed border, impossible crossing, etc.)?
4. **Authority check** — does a higher/lower linked map own that fact?
5. **Semantic check** — names/policies use only visible allowed values.
6. **Commit candidate** — construct candidate authoritative map state.
7. **Derived-world validation** — recompute necessary world facts and bridge/crossing consistency.
8. If structurally valid, accept the edit even if it harms objectives or traps agents.
9. If invalid, reject before mutation and explain the exact structural reason.

Critical distinction:
- **Illegal edit** = malformed or outside the game's map grammar. It never commits.
- **Bad legal edit** = valid map change with undesirable civic consequences. It commits, resolves, teaches, and can be undone.

The game must never reject a legal edit merely because it would make the puzzle harder or temporarily fail an objective.

---

# 6. Deterministic post-edit resolution order

One accepted edit creates a `ResolutionTransaction` with one root event `MAP_EDIT_COMMITTED`.

The exact order is:

### Phase A — authoritative map mutation
Apply exactly one player edit to the current map state.

### Phase B — structural derivation
Rebuild only affected:
1. road topology;
2. water topology;
3. bridge crossing permissions;
4. jurisdiction assignment;
5. landmark semantic registry;
6. restricted-zone policies;
7. linked-layer portal facts.

Although implementation may optimize incrementally, observable behavior must equal a full deterministic recomputation.

### Phase C — validity cleanup
Resolve dependent validity in fixed order:
1. water mutation invalidates crossings;
2. bridge validity is evaluated against resulting water + road geometry;
3. invalid bridge becomes inactive-derived, not silently relocated;
4. road crossing availability is then finalized.

A player-owned bridge symbol that becomes structurally unsupported due to a waterway edit is automatically removed as part of the same transaction **only if** the resulting bridge has no legal crossing slot. This removal is shown as a derived consequence and is reversed by Undo with the parent edit. It does not count as a second player intervention.

### Phase D — agent query rebuild
For each agent in stable-ID order, rebuild its current legal traversal graph and semantic target resolution.

### Phase E — immediate stranded-state adjudication
Agents whose current position became illegal do not move yet. Mark them `DISPLACED_OR_TRAPPED` according to section 8.5.

### Phase F — bounded reaction beats
Run the dossier's configured `reaction_beats_after_edit`, baseline 1–3, maximum design ceiling 5.

Each beat:
1. agents compute intent from the same start-of-beat world snapshot;
2. conflicts are resolved deterministically using movement-priority rules;
3. movements/state transitions apply simultaneously;
4. arrival/service/ownership consequences apply;
5. objective/invariant facts update;
6. causal events are recorded.

No hidden RNG is used.

### Phase G — objective/invariant evaluation
After the bounded reaction window, evaluate all dossier goals and protected invariants.

### Phase H — stability handling
If all baseline completion conditions are currently satisfied, either:
- complete immediately if `stability_required_cycles=0`; or
- enter/continue Stability Preview until the required clean cycle window is proven.

### Phase I — presentation release
The UI finishes causal animation and returns control. Animation speed may be reduced/skipped without altering simulation state.

---

# 7. Time and agent movement model

False Map Department is not a continuous traffic simulator. World time advances in discrete deterministic **beats** caused by accepted edits and by explicit Stability Preview.

The player may inspect indefinitely without time advancing.

This protects puzzle reasoning and avoids accidental reflex pressure.

## 7.1 Agent state
Each agent contains:
- stable ID;
- archetype;
- current node/cell;
- semantic destination or policy objective;
- movement mode/tags;
- jurisdiction permission policy;
- zone permission policy;
- current route;
- service/cargo/task flags when relevant;
- state: `IDLE`, `MOVING`, `ARRIVED`, `BLOCKED`, `TRAPPED`, `WAITING`.

## 7.2 Route calculation
Unless an archetype says otherwise:
- shortest legal path by edge cost;
- edge costs are small authored integers, typically 1;
- ties resolve lexicographically by stable node ID after comparing total cost;
- no random wandering.

The UI can preview an agent's current intended route.

---

# 8. Reusable agent rule archetypes

Phase 4 freezes **10 mechanical archetypes** as the design ceiling for the base roster. Phase 5 may instantiate themed variants but must not invent substantially new interpretation logic without reopening Phase 4.

## A1 — Direct Courier
Uses roads/bridges. Targets a named landmark. Chooses shortest reachable legal route.

Interesting interpretation: landmark renames can redirect it; roads/bridges determine connectivity.

## A2 — Jurisdiction-Locked Resident
Uses roads but may not cross a border into a jurisdiction outside its allowed set.

Interesting interpretation: border edits can block or unlock an unchanged physical road.

## A3 — Patrol
Targets the nearest reachable location/landmark inside its assigned jurisdiction, or cycles between authored patrol targets. Border changes alter jurisdiction responsibility.

## A4 — Livestock / Unrestricted Roamer
Uses roads and bridges but ignores semantic road purpose; moves toward a simple attraction target such as nearest garden/food landmark. This creates collateral consequences from improved connectivity.

## A5 — Emergency Service
Uses ordinary roads and bridges but ignores specified restricted-zone bans and may receive route-priority in movement conflict resolution.

## A6 — Commercial Carrier
Targets a semantic service/market/warehouse and requires both route access and allowed jurisdiction/zone policy. Can model tax/service ownership without a city-builder economy.

## A7 — Ferry / Water Carrier
Uses connected waterway graph between docks. Ignores roads except embark/disembark portals.

## A8 — Procession / Route-Constrained Agent
Must traverse a route satisfying an authored predicate, e.g. cross exactly two jurisdictions, visit landmarks in semantic order, or avoid restricted zones.

## A9 — Semantic Seeker
Targets one semantic landmark name/category; when multiple matches exist selects nearest reachable then stable-ID tie-break. Primary vehicle for landmark relabel puzzles.

## A10 — Regional Connector Agent
Traverses portal nodes whose availability/cost depends on linked higher-level map facts. This is reserved for late-game linked-map dossiers.

### Agent interpretation principle
Two agents may see the exact same physical road differently because their permissions/target semantics differ. The map fact is shared; interpretation rule is archetype-specific and visible.

---

# 8.5 Agent trapped during an edit

The game never teleports an agent to preserve convenience.

If an accepted edit makes the agent's **current cell/node itself forbidden or structurally nonexistent**:

1. If its physical node still exists but permission changed (border/zone): agent becomes `TRAPPED` at that node. It may leave the forbidden area on the next beat if a legal outgoing move leads toward permitted space; entering deeper forbidden space is disallowed.
2. If its exact traversal edge disappears while the agent is represented at a node endpoint, it remains at that node and re-routes.
3. The simulation never stores agents mid-edge between beats, so deleting an edge cannot strand a half-positioned agent.
4. If a water/portal mutation removes the physical node on which an agent stands, such an edit is structurally illegal unless the dossier explicitly defines a persistent shore/portal node. Base game avoids node deletion; it toggles connectivity instead.

`TRAPPED` may violate an invariant or objective but does not itself invalidate the map edit.

---

# 9. Simultaneous movement and destination changes

At the start of each reaction beat all agents read the same authoritative state.

## 9.1 Destination changes
If a landmark rename or ownership edit changes an agent's target, it resolves the new destination before computing movement for that beat. It does not finish an old route first.

## 9.2 Movement conflicts
Baseline world nodes allow multiple non-vehicle agents to coexist unless a dossier explicitly uses capacity. To avoid turning the base game into traffic micromanagement, collision occupancy is not universally simulated.

Where a dossier enables capacity-1 route contention:
- Emergency Service priority > authored priority value > lower stable agent ID.
- losing agent enters `WAITING` for that beat.

This rule is visible in the dossier and cannot be a surprise global exception.

---

# 10. Objective contracts

Every dossier objective is a deterministic boolean or bounded quantitative predicate over current/derived world state.

Canonical objective families for Phase 4:
1. **Reachability** — specified origin/entity can reach destination/category.
2. **Non-reachability / containment** — specified agent cannot reach protected target.
3. **Jurisdiction membership** — landmark/cell belongs to required jurisdiction.
4. **Jurisdiction traversal count** — route crosses exactly/at most/at least N jurisdictions.
5. **Service coverage** — every member of set S has a legal route to service landmark.
6. **Route length bound** — path cost <= or >= threshold.
7. **Water connectivity** — water agent/docks connected or separated.
8. **Adjacency** — protected cell/landmark must/must not be adjacent to road/water/zone.
9. **Semantic destination** — specified agents resolve to the intended landmark category/name.
10. **Zone access** — class can/cannot reach/occupy a restricted area.
11. **Arrival/task state** — agent reaches/serves target within N beats.
12. **Stability** — conjunction remains true for required cycles.

Phase 5 may package these into themed civic requests but should reuse these contracts.

---

# 11. Protected invariants

An invariant is mechanically identical to an objective predicate but framed as a condition that must **never be broken at dossier completion** and may optionally be monitored during Stability.

Examples:
- wetland gains no road adjacency;
- school remains inside Jurisdiction Blue;
- hospital stays reachable from every residence;
- livestock cannot reach garden;
- ferry route remains connected.

Important rule: breaking an invariant during experimentation does **not** cause irreversible failure. The dossier remains editable unless an authored challenge mode explicitly says otherwise. Baseline game teaches through reversible failure.

---

# 12. Stability contract

Some dossiers require proof that a solution survives deterministic movement rather than only producing one green snapshot.

`stability_required_cycles` ranges 0–5. Phase-4 default ceiling is 5.

When all completion predicates are satisfied:
1. Stability Preview starts automatically or via one visible `Verify Stability` action depending on UX decision later;
2. player edits are temporarily locked while cycles simulate;
3. each cycle runs one normal agent beat and objective/invariant evaluation;
4. if any predicate fails, verification stops immediately at the **first failing cycle**;
5. causal review highlights the earliest material event causing the failure;
6. control returns with the evolved state visible;
7. player may Undo to exact pre-verification state or continue editing from the evolved failed state;
8. if all cycles pass, baseline dossier completes.

Stability uses no new random events.

---

# 13. Undo / redo / history semantics

Undo is a learning tool, not a scarce resource.

## 13.1 Atomic transaction
One player edit plus every derived world mutation and all bounded reaction beats caused by it form one atomic history transaction.

Undo restores the **exact authoritative map state and exact simulation state immediately before that edit**, including:
- agents;
- objective/invariant state;
- stability counter;
- automatically invalidated bridge restoration;
- causal graph cursor.

Thus Undo is exact, not a best-effort reverse simulation.

## 13.2 Redo
Redo reapplies the recorded deterministic transaction if the history branch remains unchanged. A new edit after Undo truncates the redo branch.

## 13.3 Stability history
A failed Stability Preview is one verification transaction separate from edits. Undo after failed verification restores the state exactly before verification began.

## 13.4 Mastery footprint
Raw Undo/Redo counts never hurt baseline completion and never count toward intervention mastery.

The optional `Final Intervention Footprint` is computed from the difference between the dossier's initial authoritative map and the final completed map:
- one changed road candidate = 1;
- one bridge presence difference = 1;
- one border candidate difference = 1 per changed canonical border edge, but authored border-shift macro may later normalize as one operation if Phase 6 presents it as atomic;
- one water edge difference = 1;
- one landmark semantic label difference = 1;
- one restricted-zone candidate difference = 1.

Phase 5 may set Bronze/Silver/Gold thresholds, but raw experimentation history stays unscored.

---

# 14. Causal ancestry model

Every accepted edit and resulting simulation creates a directed acyclic causal event graph.

Each event has:
- `event_id`;
- deterministic sequence index;
- event type;
- subject stable ID(s);
- before/after facts;
- one or more parent event IDs;
- presentation summary token.

Canonical event classes:
1. `MAP_EDIT_COMMITTED`;
2. `WORLD_FACT_CHANGED`;
3. `CROSSING_VALIDITY_CHANGED`;
4. `JURISDICTION_CHANGED`;
5. `SEMANTIC_DESTINATION_CHANGED`;
6. `ZONE_PERMISSION_CHANGED`;
7. `ROUTE_CHANGED`;
8. `AGENT_STATE_CHANGED`;
9. `AGENT_MOVED`;
10. `OBJECTIVE_CHANGED`;
11. `INVARIANT_CHANGED`;
12. `STABILITY_FAILED` / `STABILITY_PASSED`.

## 14.1 Material ancestry rule
The UI should not show every bookkeeping recomputation. For explanation, follow material parent links from failed/succeeded objective back to the earliest player map edit and compress non-changing technical nodes.

Example:
`Border moved` -> `Market jurisdiction Blue -> Red` -> `Commercial Carrier no longer permitted` -> `route becomes unreachable` -> `Hospital supply invariant fails`.

## 14.2 Multiple simultaneous causes
If an objective change requires multiple facts, event ancestry may have multiple parents. Parents are ordered by event sequence then stable ID for deterministic presentation. The game must not invent a single fake cause where the predicate is conjunctive.

## 14.3 First-failure rule
For Stability failure, explanation defaults to the earliest failing invariant/objective by cycle index, then authored objective priority, then stable contract ID. Player may inspect others afterward.

---

# 15. Linked-map / multi-scale authority

Late-game linked maps are permitted only under a strict authority model.

## 15.1 Layer types
- **Local layer**: streets, local waterways, local borders/zones/landmarks.
- **Regional layer**: inter-district connectors, regional waterways, jurisdiction relations, named regional destinations.

A fact has exactly one **owning authority layer**. Other layers may display derived projections but cannot independently edit the same fact.

## 15.2 Portal contract
A `portal_node` maps one local endpoint to one regional endpoint. Regional connector presence determines whether that portal connects to another district. Local roads determine whether agents can reach the portal.

## 15.3 Propagation order
When an edit affects linked maps:
1. mutate owning layer;
2. recompute its derived facts;
3. propagate only explicit projection contracts outward;
4. update portal availability/cost;
5. rebuild affected local/regional routes;
6. run bounded reactions.

No circular authority is allowed.

## 15.4 Conflict prevention
A dossier definition is invalid if two layers claim editable authority over the same canonical fact. This is a content-validation error, not a player puzzle.

## 15.5 Multi-scale editing rule
Player may switch layers freely while paused in inspection. An accepted edit on either authority layer triggers one shared resolution transaction across all linked layers.

## 15.6 Late-game readability ceiling
Base campaign should not exceed:
- 4 simultaneously linked local districts;
- 1 regional layer;
- 5 total visible authority layers in one dossier;
- 3 cross-layer causal hops in the primary required solution chain unless later playtests prove this readable.

This ceiling is a design guardrail, not a content target.

---

# 16. Anti-bruteforce architecture

The player is allowed to experiment freely. The game must therefore become resistant to naive enumeration through **state structure**, not punishment.

## 16.1 Branching-factor target
Mature dossiers should typically expose 12–40 immediately legal primitive edits across visible layers, with multi-edit solutions of 2–7 final footprint. Exact numbers are Phase-5 content targets, but a mature dossier with only 3 binary legal moves is suspect.

## 16.2 Locally-good ambiguity
At least some mature dossiers should contain >=3 edits that improve one visible goal immediately while only causal understanding reveals which preserve remote invariants.

## 16.3 Delayed deterministic consequence
Important second-order consequences resolve within 1–5 beats. Delay must be long enough to defeat one-click green-light search but short enough to remain explainable.

## 16.4 Multiple valid solutions
Where practical, baseline completion accepts any state satisfying contracts. The system never compares against one hidden designer-authored exact map.

## 16.5 No answer oracle
Causal tools may answer:
- what changed;
- which agent rule caused this route;
- why a predicate failed.

They may not answer:
- which edit to make next;
- rank candidate edits;
- highlight the intended solution.

## 16.6 Optional optimization
Gold/medal criteria may reward lower final footprint, stronger stability or lower collateral change. They must never be required to unlock the main campaign unless later progression design explicitly and cautiously chooses a limited mastery gate.

## 16.7 Enumeration rejection gate
During graybox, if a simple exhaustive legal-edit search repeatedly reaches valid solutions faster than a human who understands the rules on mature representative dossiers, the design must be revised. Raising arbitrary edit costs is not an acceptable fix.

---

# 17. Win, fail and continuation states

## 17.1 Baseline win
A dossier wins when:
- every required objective is true;
- every protected invariant is true;
- required Stability cycles pass;
- no unresolved structural invalidity exists (structurally invalid maps cannot be committed anyway).

## 17.2 Temporary failure
There is no ordinary hard fail from a bad legal edit. Instead the dossier enters an unsatisfied state with visible broken contracts and remains editable.

## 17.3 Hard fail
Reserved for optional challenge variants only, such as authored "no invariant may break during verification" conditions. Phase 4 does not require any hard-fail campaign dossier.

## 17.4 Reset
Player may reset dossier to exact initial state at any time with confirmation if progress would be discarded.

## 17.5 Completion persistence
Later technical spec must save best completion/mastery separately from current in-progress state so revisiting a completed dossier cannot erase historical completion.

---

# 18. Mastery scoring contract

Baseline completion is binary and sufficient for progression unless Phase 7 changes commercial/progression framing.

Optional mastery may use up to three transparent dimensions:
1. `Footprint` — number of final map differences from initial state;
2. `Collateral` — authored non-required world-fact changes at completion, when a dossier meaningfully defines them;
3. `Stability Margin` — optional extra clean cycles beyond baseline or stronger route bounds where explicitly defined.

No hidden weighted score. A dossier presents exact thresholds before/after completion.

Phase 5 should avoid giving every dossier all three dimensions. One or two are enough.

---

# 19. Balance knobs

Mechanical balance is tuned primarily through authored dossier parameters, not global stat inflation.

Core knobs:
- number of legal editable candidates by primitive type;
- number of active primitive families;
- agent count;
- agent archetype diversity;
- number of simultaneous objectives;
- number of protected invariants;
- reaction beats after edit (1–5);
- stability cycles (0–5);
- route edge costs;
- zone/jurisdiction permission sets;
- semantic landmark duplicates;
- capacity contention enabled/disabled;
- number of linked layers/portals;
- final-footprint medal thresholds;
- objective route-length thresholds;
- visibility of route/causal previews (difficulty/accessibility setting may add explanation, never alter underlying determinism).

Difficulty should rise mostly by **interaction density and causal distance**, not by hiding information.

---

# 20. Edge-case decisions

## 20.1 Disconnected regions
Legal by default. Agents with no path become `BLOCKED`; objectives update accordingly. Jurisdiction disconnectedness is legal unless an explicit contract says otherwise.

## 20.2 Conflicting authority
Impossible in a valid dossier. Exactly one layer owns each editable fact. Content validator must reject ambiguous ownership before shipping.

## 20.3 Invalid landmark names
Player cannot enter arbitrary invalid text in baseline game. Names come from visible allowed tokens. Duplicate semantic names follow explicit duplicate policy and deterministic target selector.

## 20.4 Border self-intersection
Structurally illegal; edit is rejected before world mutation with highlighted intersection.

## 20.5 Bridge/water mutation ordering
Water topology resolves first, bridge structural validity second, road crossing permission third. Unsupported bridge auto-removal is a derived child of the water edit and undone atomically with it.

## 20.6 Agent trapped during edit
Agent remains at a stable node, becomes `TRAPPED`, may evacuate outward if legal, never teleports. See section 8.5.

## 20.7 Simultaneous destination changes
All semantic targets re-resolve at Phase D before any agent moves. Agents then compute intents from the same start-of-beat snapshot.

## 20.8 Road and water candidate overlap
A crossing exists only at authored crossing slots. Else the candidate map grammar prevents both occupying an illegal planar intersection simultaneously.

## 20.9 Removing final route to a required portal
Legal as a bad edit. Regional/local connectivity fails visibly.

## 20.10 Renaming landmark while agent already arrived
At the next resolution rebuild, if its task is persistent semantic service, it may acquire a new target; if its authored task marks `complete_on_arrival`, completed task state remains. This behavior is an agent/task data field and must be visible in dossier rules.

## 20.11 Border moves across an agent
Physical agent stays put; jurisdiction membership of its cell changes immediately. Permission consequences apply before the next movement intent.

## 20.12 Undo after auto-removed bridge
Restores water edit parent state and exact bridge state as part of the same transaction.

---

# 21. Mechanical acceptance tests

The later implementation must be able to express these as deterministic automated tests.

## Primitive semantics
M4-01 Add road creates exactly one intended road edge and updates route availability.
M4-02 Remove road can disconnect a region without being structurally rejected.
M4-03 Bridge is legal only on active authored crossing slot with valid road approach.
M4-04 Removing bridge preserves water connectivity.
M4-05 Water edit invalidating a bridge removes/deactivates it deterministically in the same transaction.
M4-06 Border edit cannot self-intersect and rejected edit leaves state byte-equivalent/semantically identical to prior state.
M4-07 Border edit can change ownership without physically blocking a permission-agnostic agent.
M4-08 Landmark rename changes semantic target resolution without changing landmark stable ID.
M4-09 Restricted-zone edit changes permission graph without deleting road geometry.

## Resolution
M4-10 Repeating the same initial state + same accepted edit produces identical derived world and agent state.
M4-11 All agents compute movement intent from same start-of-beat snapshot.
M4-12 Destination changes resolve before movement intent.
M4-13 Stable-ID tie-break yields identical route/movement result across runs.
M4-14 No hidden RNG is needed for campaign resolution.

## Undo/history
M4-15 Undo restores exact pre-edit authoritative and agent state after multi-beat reaction.
M4-16 Redo restores exact deterministic post-edit state when history branch is unchanged.
M4-17 New edit after Undo truncates redo branch.
M4-18 Undo of water edit restores any bridge auto-removed by that transaction.
M4-19 Failed Stability verification can be undone to exact pre-verification state.

## Agents/objectives
M4-20 Each of A1–A10 can explain its route/target choice from visible map facts.
M4-21 Unreachable agent becomes BLOCKED/TRAPPED per rules rather than teleporting.
M4-22 Multiple matching landmark names resolve by documented deterministic selector.
M4-23 Objective and invariant predicates are pure deterministic functions of defined world/agent state.

## Causality
M4-24 Every objective/invariant state change has ancestry to one or more material parent events.
M4-25 Stability failure exposes earliest failing contract and causal ancestry.
M4-26 Multiple material causes remain representable as multiple parents.

## Linked maps
M4-27 Every canonical fact has exactly one owning authority layer.
M4-28 Regional edit propagates through explicit portal/projection contracts only.
M4-29 No circular authority relation is valid content.
M4-30 Undo of cross-layer edit restores all affected layers atomically.

## Anti-bruteforce/content guardrails
M4-31 Baseline completion never counts raw Undo usage.
M4-32 Mastery footprint depends on initial-vs-final authoritative map difference, not edit history.
M4-33 Baseline solver accepts any final state satisfying contracts, not one hidden target map.
M4-34 Causal inspection never enumerates/ranks candidate solution edits.

---

# 22. Phase-4 internal coherence review

## Potential contradiction: immediate rewrite vs reaction delay
Resolved: world fact mutation is immediate; autonomous agents respond in short deterministic beats after each edit. There is no long submit/watch phase.

## Potential contradiction: free Undo vs anti-bruteforce
Resolved mechanically by mature branching factor, multi-system conjunctions, delayed remote consequences and multiple locally-good actions. No punitive Undo cost is introduced.

## Potential contradiction: landmark names vs arbitrary language
Resolved by semantic token vocabulary rather than arbitrary player text. Presentation can still look like stamping/typing bureaucratic labels.

## Potential contradiction: waterway editing vs realistic hydrology
Resolved by explicit graph connectivity, not fluid simulation.

## Potential contradiction: borders as physical walls
Resolved: border is ownership/permission fact. Physical blockage only emerges through an agent's visible jurisdiction rule.

## Potential contradiction: linked maps editing same road twice
Resolved by single owning authority layer and projection-only derivatives.

## Potential contradiction: bad edit trapping agent
Resolved: trapping is a legal consequence, not structural invalidity; agent remains in stable physical state and can be explained/undone.

---

# 23. Empirical / prototype gates still open

These are implementation-validation obligations, not missing rules:

1. >=80% naive testers understand map->world causality within 3 minutes.
2. >=70% can predict direction of a second-order consequence by end of initial graybox packet.
3. Mature successful edits should be predominantly hypothesis-driven rather than blind probes.
4. Exhaustive legal-edit enumeration must not reliably beat causal reasoning at mature complexity.
5. Dual map/world presentation must make ownership, path and semantic changes readable without dense text.
6. 1–5 reaction beats must feel immediate enough that editing remains the central verb.
7. Linked maps must remain understandable at the stated ceiling; if not, reduce layer count rather than add explanation clutter.
8. Ten archetypes are a ceiling, not a quota. Phase 5 should cut/merge any archetype that does not create distinct decisions.

---

# 24. Phase-4 acceptance decision

- Six canonical primitive semantics defined: **YES**
- Authoritative state model defined: **YES**
- Legal/illegal edit distinction defined: **YES**
- Deterministic resolution ordering defined: **YES**
- Reusable agent interpretation architecture defined: **YES — 10 archetype ceiling**
- Objective families defined: **YES**
- Protected-invariant contract defined: **YES**
- Stability semantics defined: **YES**
- Exact Undo/Redo semantics defined: **YES**
- Causal ancestry/event model defined: **YES**
- Linked-map authority model defined: **YES**
- Anti-bruteforce architecture defined: **YES**
- Win/fail/mastery/balance knobs defined: **YES**
- Requested edge cases resolved: **YES**
- Mechanical acceptance-test index defined: **YES — M4-01 through M4-34**
- Production implementation started: **NO**

**Phase 4 Mechanical Architecture: COMPLETE on paper, pending later whole-game/adversarial/prototype validation.**

## NEXT PHASE
Phase 5 — Content Architecture.

Next run should convert the mechanical grammar into a bounded content plan: dossier progression curve, exact content families/count targets, which agent archetypes survive, convention introduction order, jurisdiction/landmark/zone data schemas, objective/invariant family distribution, linked-map late-game placement, district themes, authored-vs-remix strategy, solvability/content-validation rules, tutorial/demo subset, mastery variants and anti-repetition constraints. Do not expand scope beyond the Product Thesis or add new core primitive families without reopening Phase 4.
