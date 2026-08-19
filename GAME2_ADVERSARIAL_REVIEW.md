# GAME #002 — FALSE MAP DEPARTMENT — PHASE 10 ADVERSARIAL REVIEW

Last updated: 2026-08-19
Factory run: **12**
Phase: **10 — Adversarial Review**
DESIGN COMPLETE: **NO**

This file is the canonical Phase-10 destructive review of the specification through Phase 9. It adds no seventh primitive and starts no production code. Where a `REPAIR` below defines a narrower rule than an earlier file, this Phase-10 repair is authoritative until Phase 11 reconciles it into the final freeze.

---

# 1. Executive verdict

**PASS WITH NARROW REPAIRS AND EMPIRICAL GATES. No fatal design flaw found.**

The core product survives destructive review: the executable-map fantasy remains legible, the six primitive families still support sufficient causal depth, free Undo does not need punishment, linked authority remains implementable, and the campaign can remain compact without an economy or unrelated progression layer.

Phase 10 found **8 canonical repairs**, **7 implementation/playtest empirical gates**, and **0 FATAL findings**.

The principal remaining risk is not missing mechanics. It is content quality: the same compact grammar must repeatedly produce distinct reasoning transformations without devolving into checkbox pursuit, relabel shortcuts, or layer-management busywork.

Phase 11 may proceed after treating the repairs in section 18 as canonical supplements and checking that no earlier file still appears to grant contradictory freedom.

---

# 2. Classification key

- **PASS** — current specification is sufficient and internally defensible.
- **REPAIR** — a concrete ambiguity or exploitable authoring freedom exists; smallest canonical amendment is specified here.
- **EMPIRICAL GATE** — rules are specified, but prototype/playtest evidence is still required.
- **FATAL** — product thesis or core architecture fails and must be reopened. None found this run.

---

# 3. Fun / boredom / hour-10 repetition

## Attack
The player learns all six primitive families by D12. If later cases are mostly new themes over the same `make requirements green` pattern, the product can feel solved long before D40.

## Finding
The specification already has meaningful reasoning axes: topology, jurisdiction, semantic naming, permissions, water connectivity, temporal Stability and linked authority. The failure mode is authoring repetition, not vocabulary insufficiency.

## Classification
**REPAIR + EMPIRICAL GATE.**

### Canonical repair P10-R1 — reasoning-transformation diversity
For every **consecutive 3-dossier window from D13 onward**, content validation must assign one dominant reasoning-transformation tag to each dossier from this frozen list:
- topology restructuring;
- ownership reinterpretation;
- semantic-target reinterpretation;
- permission asymmetry;
- cross-network dependency;
- temporal/Stability dependency;
- linked-authority dependency;
- causal-compression/elegance.

No 3-dossier window may have the same dominant transformation on all three dossiers. No 5-dossier window may have fewer than **3 distinct** dominant transformations.

A theme swap, different agent skin, different threshold or moved starting position does not count as a different transformation.

### Empirical gate E10-1
After the full campaign graybox/content pass, players sampled around D13–D22 and D29–D36 should not predominantly describe consecutive cases as repetitions of the same trick. If they do, replace/re-author cases; do not add a seventh primitive as first response.

---

# 4. Brute-force Undo / dominant strategy

## Attack
Free Undo plus bounded legal candidates could encourage enumeration rather than understanding.

## Finding
Punishing Undo would damage the learning loop and violate the Product Thesis. Mature complexity can defeat one-step enumeration if cases include remote dependencies, multi-edit interactions and Stability.

## Classification
**PASS + EMPIRICAL GATE.**

No Undo cost, cooldown, limited charges, mastery penalty or anti-save-scumming rule may be added.

### Empirical gate E10-2
On representative mature dossiers, compare hypothesis-driven human solving against deliberate legal-edit enumeration. Reject/re-author a dossier family if blind enumeration is reliably faster/easier than causal reasoning after rules are known.

A mature dossier should normally have multiple locally plausible edits whose quality cannot be determined from one immediate requirement flip alone.

---

# 5. Semantic relabeling as repeated shortcut — P9-R6

## Attack
Relabeling can redirect agents without rebuilding topology. If broadly available, it may become the cheapest answer to route problems and undermine roads/borders/water.

## Finding
The mechanic is valuable and distinctive, but its availability needs stronger authoring validation.

## Classification
**REPAIR.**

### Canonical repair P10-R2 — semantic non-dominance
For every dossier/remix where landmark relabeling is editable:
1. validation must test every legal single relabel from the initial state;
2. validation must test relabel combined with the cheapest one additional intervention;
3. if those patterns satisfy baseline completion while bypassing the dossier's declared central causal lesson, the content fails validation;
4. across D13–D40, no more than **two consecutive dossiers** may have a solution envelope whose principal insight is semantic relabeling;
5. a relabel-centered dossier must make the semantic consequence itself the intended lesson, not use relabel as an incidental universal bypass.

This does not ban elegant relabel solutions. It prevents relabel from becoming the universal first move.

---

# 6. Stability passivity / misuse — P9-R1

## Attack
Stability can become a green-state waiting tax, especially if 3–5 cycles merely reconfirm an obvious static solution.

## Finding
Speed controls do not fix meaningless verification. Stability must exist only when time/cycles can reveal a state transition relevant to the reasoning.

## Classification
**REPAIR.**

### Canonical repair P10-R3 — Stability justification contract
Any dossier with `stability_required_cycles > 1` must declare a machine-readable `stability_reason_tag` from:
- agent progression/arrival;
- route contention/priority evolution;
- Procession sequence progression;
- service-state transition;
- linked-connector state propagation;
- other existing canonical temporal state transition approved in Phase-11 reconciliation.

Authoring validation must prove at least one relevant non-idle state transition occurs during the required window in a known valid solution envelope.

A dossier fails content review if Stability>1 only means `wait N identical cycles while all predicates remain unchanged`.

Stability remains explicit player-triggered verification and does not auto-run.

---

# 7. Mastery becoming checkbox cleanup — P9-R4

## Attack
`final footprint <= N` can become replaying the same solution with one fewer arbitrary map difference.

## Finding
The three mastery families are sufficient, but each mastery instance requires qualitative justification.

## Classification
**REPAIR.**

### Canonical repair P10-R4 — mastery distinction proof
Every authored mastery contract must include `mastery_distinction_note` for internal validation and satisfy at least one:
- requires a different causal insight from the most obvious baseline solution;
- compresses two or more baseline interventions through a known cross-system interaction;
- preserves an additional meaningful civic state, not an arbitrary numeric threshold;
- proves a longer/stronger Stability state whose added cycles contain a meaningful temporal transition.

A mastery condition that can be obtained by reproducing the ordinary baseline reasoning and shaving one arbitrary final difference fails authoring validation.

Mastery remains optional and never gates D40.

---

# 8. Linked-layer cognition / authority confusion — P9-R2

## Attack
Players may bounce between tabs after every edit, forget which layer owns a fact, or solve the UI rather than the civic problem.

## Finding
One-way authority, source stamps and causal jump are strong. The main risk is simultaneous relevant remote consequences.

## Classification
**REPAIR + EMPIRICAL GATE.**

### Canonical repair P10-R5 — linked-authority readability budget
For D25–D32:
- no accepted edit may require the player to inspect more than **one remote target layer** to understand the selected/first-broken requirement chain;
- the default selected requirement chain may cross layers at most **2 times** (`source -> target` or `source -> target -> source-like higher relation` is not allowed if it creates circular authority; authority graph remains acyclic).

For D33–D40:
- one edit may affect several layers mechanically, but each required objective/invariant must have one explainable material chain with at most **3 cross-layer projection edges**;
- content review must identify the authoritative source for every required chain without relying on memory.

The simulation may have broader side effects; this is an authoring/readability budget on required reasoning, not a domain truncation.

### Empirical gate E10-3
Before shipping any 3–4-layer dossier, representative testers must be able to identify the authority-owning layer for the currently broken selected requirement using the UI without tutorial recall.

---

# 9. Causal ancestry breadth / opacity — P9-R3

## Attack
With 6–10 agents, one edit can emit many descendants. A complete graph can be deterministic yet unusable.

## Finding
The UI's shortest-relevant-chain approach is correct but needs a hard presentation budget.

## Classification
**REPAIR + EMPIRICAL GATE.**

### Canonical repair P10-R6 — causal presentation budget
For the default causal ribbon attached to one selected requirement:
- show at most **5 material event nodes** before collapsing intermediate same-family derivations;
- show at most **2 sibling branches** at once;
- additional siblings are collapsed behind an explicit `More affected` affordance;
- the first broken requirement view must always fit without opening a raw debug graph;
- collapsed presentation may never fabricate or reorder causality; expansion reveals canonical parentage.

Content authoring must flag any required solution chain whose material explanation cannot be reduced to <=5 player-comprehensible nodes without losing the actual reason. Such a case is too opaque for 1.0 and must be re-authored.

### Empirical gate E10-4
In late-game graybox tests, players should be able to answer `What caused this selected requirement to break?` from the default ribbon/Inspect path without reading a raw event log.

---

# 10. Keyboard-only / controller-only focus predictability — P9-R5

## Attack
Runtime nearest-cardinal focus on irregular authored graphs can jump unpredictably. Shoulder buttons also have context-sensitive tool/layer roles.

## Finding
This is a real implementation ambiguity because geometry alone does not guarantee a stable intuitive focus graph.

## Classification
**REPAIR.**

### Canonical repair P10-R7 — authored deterministic focus graph
Each editable map layer must compile a deterministic logical-navigation graph for every focusable candidate state.

Rules:
- content/tooling may auto-generate a draft from geometry;
- authors/validators may override neighbors explicitly;
- every required focusable candidate has deterministic `up/down/left/right/next/previous` resolution or a documented unavailable direction;
- no navigation edge may depend on frame layout, current zoom, floating-point nearest comparisons or runtime hash iteration;
- validation rejects unreachable required candidates and unintentional focus cycles that prevent regional escape;
- context-sensitive bindings must expose current function in glyph/help text before activation;
- while an edit gesture is active, layer-switch bindings may not silently perform tool cycling, and vice versa.

This is an input/UX supplement, not a new mechanic.

---

# 11. Deck / reduced motion / non-color accessibility

## Attack
Dense patterns and miniature twin views may become unreadable at 1280×800; reduced motion could remove the very transformation that communicates causality.

## Finding
Phase 6 already requires redundant shape/pattern/icon/text and two-surface ceiling. Reduced motion must preserve discrete state change correspondence.

## Classification
**PASS + EMPIRICAL GATE.**

### Empirical gate E10-5
Every shippable dossier must pass a capture-based accessibility sweep at 1280×800 using:
- maximum supported UI scale that remains valid;
- grayscale/non-color inspection;
- reduced-motion mode;
- no-audio mode;
- controller glyph presentation.

Critical before/after state, selected source/target correspondence and requirement status must remain unambiguous without animation direction or color hue.

No new accessibility mode may alter deterministic rules.

---

# 12. Persistence / corruption / stale commands / Cloud / demo import — P9-T1

## Attack
Interrupted Stability remained implementation-flexible. Two implementations could resume mid-verification or roll back to pre-verification, producing different user experience and persistence complexity.

## Finding
Phase 11 should not leave this choice open because a fresh implementer should not decide persistence semantics ad hoc.

## Classification
**REPAIR.**

### Canonical repair P10-R8 — interrupted Stability recovery
Freeze the simpler 1.0 rule:

**Stability Preview persists only at transaction boundaries. If the process exits/crashes during an in-progress Stability verification transaction before the required window completes, recovery restores the exact pre-verification checkpoint and marks verification as interrupted/not completed.**

Consequences:
- no partially advanced Stability beat is authoritative across process death;
- completed successful Stability transaction persists atomically with completion/progression;
- a player may deliberately Pause/Exit Stability only through an explicit in-game command that returns control after a domain-defined boundary; normal saved editable state is then persisted;
- recovery notice is human-readable (`Stability verification was interrupted; your map edits were preserved.`);
- no half-cycle serialization is required for 1.0.

This does not change deterministic Stability outcomes; it removes needless persistence ambiguity.

All other Phase-8 rules survive: stale/double commands are idempotent; corruption uses newest valid compatible generation; Cloud never synthesizes divergent active branches; demo import is monotonic/idempotent.

---

# 13. Scope / production burden / content QA bottleneck

## Attack
40 authored dossiers + 12 remixes + data validation + multiple input modes can be QA-heavy even with low art burden.

## Finding
Scope is viable only if authoring tooling exists early. Hand-validating 52 cases by manual play alone is a production trap.

## Classification
**PASS WITH IMPLEMENTATION OBLIGATION.**

Phase-8 headless validation must become part of the first implementation milestones, not late polish. Tooling must support at minimum:
- content-schema validation;
- stable-ID uniqueness;
- authority DAG validation;
- campaign prerequisite/tutorial-tag validation;
- focus-graph reachability validation;
- semantic non-dominance probes for authored relabel cases where computationally bounded;
- replay fixture execution;
- canonical hash determinism;
- known-solution-envelope regression fixtures;
- mastery contract validation metadata;
- 3-dossier reasoning-tag diversity reports;
- remix changed-dependency metadata.

This is implementation architecture already permitted by Phase 8, not additional player-facing scope.

---

# 14. Demo promise versus canonical teaching order — P9-D1

## Attack
Earlier demo language promised `border or restricted-zone interpretation difference`, but canonical campaign introduces border D05–D06 and zones D07–D08. A 15–25 minute demo based only on D01–D04 cannot honestly deliver that promise.

## Finding
This is a packaging contradiction that needs one exact answer.

## Classification
**REPAIR.**

### Canonical repair P10-R9 — demo sequence freeze
The 1.0 demo is **not** an exact export of campaign D01–D04.

It uses five demo nodes `DEMO01–DEMO05` built from canonical mechanics and tutorial tags:
1. `DEMO01` — road add/remove causality;
2. `DEMO02` — road tradeoff / Undo learning;
3. `DEMO03` — bridge + water crossing;
4. `DEMO04` — collateral connectivity consequence;
5. `DEMO05` — **border ownership** as the single interpretation-difference mechanic and final synthesis.

`DEMO05` teaches the same border semantic rule as campaign D05 in compressed form; it does not unlock or teach restricted zones early.

Demo excludes restricted-zone editing, landmark relabeling, editable waterways, Ferry, Procession, Commercial chains, Stability>1 and linked maps.

Demo target remains 15–25 minutes. Full-game import maps validated demo tutorial tags and exact compatible substrate clears only through explicit versioned mapping; it must not auto-clear campaign D05 unless the full campaign D05 definition is proven content-equivalent by mapping metadata.

This resolves the promise without changing campaign teaching order.

---

# 15. Commercial / marketing promise versus actual play

## Attack
The Steam pitch may imply free creative map redrawing, city-building or broad reality manipulation, while the actual game uses snapped authored candidates and deterministic dossiers.

## Finding
The hook remains truthful if marketing shows actual snapped edits and immediate consequences rather than fake freehand drawing.

## Classification
**PASS + EMPIRICAL GATE.**

### Empirical gate E10-6
Trailer/store tests must verify that players describe expected play as `solve civic puzzles by changing authoritative map facts` rather than `freeform city/map editor` or `city builder`.

Marketing footage may stylize cursor/paper animation but must not depict capabilities absent from gameplay, especially arbitrary freehand roads/borders.

The first 15 minutes must reach a collateral consequence; otherwise the store promise of second-order consequences is delayed too long.

---

# 16. Remix exhaustion — P9-R7 extension

## Attack
Twelve remix cases can feel like recycled campaign boards with starts shuffled.

## Finding
Phase 5 bounded remix parameters are safe technically but insufficient as a value guarantee.

## Classification
**REPAIR + EMPIRICAL GATE.**

### Canonical repair P10-R10 — remix changed-dependency requirement
Every remix must declare:
- `source_substrate_id`;
- `changed_inputs[]`;
- `changed_causal_dependency` in plain internal authoring terms;
- `expected_new_reasoning_transformation`.

A remix fails validation if the optimal/typical causal insight is unchanged and only start positions, numeric thresholds or mastery limits move.

Within each pack of four remixes, at least **3 distinct reasoning transformations** from the P10-R1 list must appear.

### Empirical gate E10-7
Post-campaign testers should identify remixes as altered causal problems, not merely harder/recycled versions of campaign cases.

---

# 17. Agent-roster distinctness and hidden complexity

## Attack
A1 Courier vs A9 Semantic Seeker, or A3 Patrol vs A6 Commercial Carrier, could become visually/behaviorally indistinct and inflate explanation burden.

## Finding
Current semantics are distinct on paper, but implementation should not preserve a roster slot merely because it exists in documentation.

## Classification
**EMPIRICAL GATE.**

During vertical-slice/content prototyping, if representative players cannot predict the different response of two archetypes after their rule is taught, merge/cut the less distinctive archetype rather than adding exception text. Such a merge would require a deliberate canonical amendment because Phase 5 currently keeps all ten.

This is not a Phase-10 repair now because no contradiction exists yet.

---

# 18. Canonical repair register

The following repairs are authoritative supplements pending Phase-11 consolidation:

| ID | Area | Frozen repair |
|---|---|---|
| P10-R1 | Campaign repetition | 3/5-dossier reasoning-transformation diversity validation |
| P10-R2 | Semantic relabel | Non-dominance validation; no repeated universal relabel shortcut |
| P10-R3 | Stability | Stability>1 requires declared meaningful temporal reason + transition |
| P10-R4 | Mastery | Every mastery must prove qualitatively distinct insight/state |
| P10-R5 | Linked maps | Required-chain cross-layer readability budgets |
| P10-R6 | Causal ribbon | Default selected chain <=5 nodes, <=2 visible sibling branches |
| P10-R7 | Input focus | Authored/validated deterministic logical focus graph |
| P10-R8 | Persistence | Interrupted Stability rolls back to pre-verification checkpoint |
| P10-R9 | Demo | DEMO01–05; final demo mechanic is compressed border teaching |
| P10-R10 | Remixes | Every remix changes a causal dependency/reasoning transformation |

No repair changes the six primitive families, core loop, agent resolution semantics, free Undo philosophy, campaign baseline access, or product thesis.

---

# 19. Resolved-risk register

| Attack | Classification | Phase-10 result |
|---|---|---|
| Fun/hour-10 repetition | REPAIR + EMPIRICAL | Content diversity metric added; no new mechanic |
| Brute-force Undo | PASS + EMPIRICAL | Keep Undo free; test mature search dominance |
| D13–D22 exhaustion | REPAIR | Consecutive-window reasoning validation |
| Semantic relabel shortcut | REPAIR | Relabel non-dominance checks |
| Stability passivity | REPAIR | Temporal-meaning contract |
| Mastery checkbox cleanup | REPAIR | Distinction proof required |
| Linked-layer cognition | REPAIR + EMPIRICAL | Cross-layer chain budgets |
| Causal breadth | REPAIR + EMPIRICAL | Ribbon budget + re-author opaque cases |
| Keyboard/controller focus | REPAIR | Deterministic authored focus graph |
| Deck/non-color/reduced motion | PASS + EMPIRICAL | Capture-based accessibility sweep |
| Corruption/stale/double commands | PASS | Existing technical contract sufficient |
| Interrupted Stability | REPAIR | Pre-verification recovery frozen |
| Cloud divergence | PASS | Monotonic durable merge; no branch synthesis |
| Demo import | PASS after demo repair | Explicit versioned mapping only |
| Production/content QA | PASS WITH OBLIGATION | Early headless authoring validators mandatory |
| Demo teaching order | REPAIR | DEMO01–05 with compressed border capstone |
| Marketing mismatch | PASS + EMPIRICAL | Show real snapped edits; expectation test |
| Remix repetition | REPAIR + EMPIRICAL | Changed-dependency requirement |
| Scope creep | PASS | 1.0 exclusions remain intact |
| Executable-map fantasy dilution | STRONG PASS | Map authority remains central through D40 |

---

# 20. Implementation ambiguities audit

A fresh implementer must not decide these two ways after Phase-10 repairs:

1. **Freehand vs snapped edits:** snapped authored candidates only.
2. **Bad civic edit vs illegal map edit:** bad legal edit commits; structural illegality rejects before mutation.
3. **Map/world authority:** map facts authoritative; presentation/world never owns topology semantics.
4. **Reaction timing:** discrete bounded deterministic beats only.
5. **Agent mid-edge state:** never authoritative; agents live on nodes/cells between beats.
6. **Duplicate semantic labels:** allowed only when visible content permits; stable IDs remain unique.
7. **Tie-breaks:** deterministic and inspectable.
8. **Undo:** exact checkpoint restore; free for baseline/mastery learning history.
9. **Intervention footprint:** final authoritative differences, not raw edit/Undo count.
10. **Stability:** explicit verification; >1 requires meaningful temporal reason.
11. **Interrupted Stability:** rollback to exact pre-verification checkpoint.
12. **Linked facts:** one-way acyclic authority; projected target fact not directly editable there.
13. **Layer display:** at most two editing surfaces visible simultaneously.
14. **Causal UI:** explain occurred/current facts; never oracle untried edits.
15. **Focus navigation:** deterministic authored/validated logical graph, not runtime geometric guess only.
16. **Demo:** separate DEMO01–05 sequence; compressed border capstone; no restricted-zone early teaching.
17. **Demo import:** versioned monotonic mapping; no assumed equivalence.
18. **Campaign ending:** D40 reachable with zero mastery marks.
19. **Remixes:** bounded existing mechanics and changed causal dependency required.
20. **Content scope:** 40 campaign target + 12 remixes; no procedural campaign requirement.

Remaining implementation choices (scene composition, exact hash algorithm, visual tweening, storage library, Steam adapter details) are intentionally implementation-flexible only where they do not alter the gameplay/UX contracts.

---

# 21. Freeze blockers for Phase 11

Phase 10 leaves no fatal design blocker, but Phase 11 must explicitly close these before `DESIGN COMPLETE = YES`:

1. consolidate P10-R1..R10 into a final authority chain so earlier wording cannot appear contradictory;
2. produce a single implementation-readiness checklist spanning mechanics, content, UX, commercial, technical and persistence;
3. verify exact campaign/demo progression prerequisites and import mapping semantics are deterministic enough for a fresh session;
4. verify all required event/fact semantics needed by causal ancestry have canonical names/ownership or are intentionally implementation-flexible;
5. verify focus-graph validation and linked-authority readability budgets are included in acceptance criteria;
6. verify all empirical gates are labeled prototype obligations rather than unresolved design;
7. perform a fresh-session `can implementation answer without inventing gameplay?` audit;
8. define final authority precedence and set specification freeze only if that audit passes.

---

# 22. Phase-10 acceptance checklist

- [x] Fun/boredom/hour-10 attack completed.
- [x] Undo/bruteforce dominant strategy attacked without nerfing learning.
- [x] D13–D22 repetition attacked.
- [x] Semantic relabel shortcut attacked and repaired.
- [x] Stability passivity attacked and repaired.
- [x] Mastery shallowness attacked and repaired.
- [x] Linked-layer cognition attacked and bounded.
- [x] Causal ancestry breadth attacked and bounded.
- [x] Keyboard/controller focus ambiguity repaired.
- [x] Deck/reduced-motion/non-color accessibility attacked.
- [x] Persistence/corruption/stale command/Cloud/demo import attacked.
- [x] Interrupted Stability recovery semantics frozen.
- [x] Scope/content-authoring QA bottleneck attacked.
- [x] Demo teaching-order contradiction repaired.
- [x] Marketing promise attacked.
- [x] Remix exhaustion attacked and repaired.
- [x] Every P9-* finding resolved or promoted to explicit empirical gate.
- [x] No FATAL finding remains.
- [x] Production implementation not started.
- [ ] Phase 11 specification freeze not yet performed.

## Phase-10 closure decision

**PHASE 10 COMPLETE ON PAPER.**

- Fatal findings: **0**
- Canonical repairs: **10**
- Explicit empirical gates: **7**
- Earlier product thesis reopened: **NO**
- DESIGN COMPLETE: **NO**

## NEXT PHASE

**Phase 11 — Specification Freeze / fresh-session implementation-readiness audit.**

Phase 11 must reconcile the Phase-10 repairs into a final authority overlay or canonical homes, run a question-by-question fresh implementation audit, separate prototype empirical gates from frozen rules, and only then decide whether `DESIGN COMPLETE = YES` is justified.