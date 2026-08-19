# GAME #002 — FALSE MAP DEPARTMENT — TECHNICAL IMPLEMENTATION SPECIFICATION

Last updated: 2026-08-18
Factory run: **10**
Phase: **8 — Technical Implementation Specification**
Product thesis: **LOCKED**
Mechanical architecture: **COMPLETE ON PAPER**
Content architecture: **COMPLETE ON PAPER**
UX / presentation architecture: **COMPLETE ON PAPER**
Economy / commercial model: **COMPLETE ON PAPER**
DESIGN COMPLETE: **NO**

This file is the canonical Phase-8 technical contract for False Map Department. It specifies how another implementation session can build the frozen design without inventing gameplay. It deliberately contains no production game code.

When technical convenience conflicts with canonical gameplay, the earlier canonical gameplay/UX rule wins unless the smallest affected design phase is explicitly reopened.

---

# 1. Technical design goals

The implementation must make these properties structural rather than aspirational:

1. **Authoritative map facts are the only editable source of world topology/ownership/semantic truth.**
2. **Every accepted edit resolves deterministically.** Same content version + same pre-edit state + same edit command must produce byte-equivalent canonical domain output.
3. **Presentation never owns gameplay state.** Scenes animate/query domain results; they do not decide route legality, objectives, ownership, tie-breaks or consequences.
4. **Undo/Redo restores exact domain checkpoints, not approximate visual state.**
5. **Content is data-driven and validated before it can ship.** No dossier-specific script may quietly override canonical primitive or agent semantics.
6. **Save/recovery is designed around interruption and corruption, not merely normal exit.**
7. **Input is action-based and device-agnostic.** Mouse, keyboard-only and controller-only all drive the same semantic commands.
8. **Linked maps remain explicit one-way authority projections.** No cyclic hidden synchronization.
9. **Simulation is cheap enough that correctness beats clever incremental optimization.** Full or affected-subgraph recomputation is acceptable whenever it reduces ambiguity.
10. **The headless deterministic test harness is a first-class product subsystem.**

---

# 2. Engine / runtime direction

## 2.1 Frozen direction

**Godot 4.7.1-stable, standard build, GDScript-first, 2D Control/Canvas architecture.**

As of 2026-08-18, Godot 4.7.1 is the current stable maintenance release; Godot 4.8 is still a development series. Production should pin an exact stable engine patch in the repository/tooling rather than following `latest` automatically.

Official references checked 2026-08-18:
- Godot release archive: https://godotengine.org/download/archive/
- Godot 4.7.1 maintenance release: https://godotengine.org/article/maintenance-release-godot-4-7-1/
- Godot release policy: https://docs.godotengine.org/en/latest/about/release_policy.html

## 2.2 Why Godot fits this product

False Map Department needs:
- deterministic small 2D graph/state simulation;
- heavy UI and split-view interaction;
- custom symbolic map/world rendering;
- fast iteration on data-driven authored puzzles;
- keyboard/controller remapping;
- localization/pseudolocalization;
- headless test execution;
- desktop/Steam Deck export without 3D production burden.

These are native strengths of a lightweight Godot 2D project. The game does not need a physics-heavy runtime, proprietary server stack, ECS framework or high-end 3D renderer.

## 2.3 Rendering direction

Default implementation target: **2D CanvasItem/Control rendering with the Compatibility renderer unless a later measured feature need requires Mobile.**

No gameplay rule may depend on shader precision, render FPS, physics frames or GPU behavior. World morphs are presentation only.

## 2.4 Language boundary

GDScript is the default for domain + presentation because the state space is small and iteration speed matters more than native throughput.

Native/C#/GDExtension code is allowed only behind adapters if required for a platform SDK (for example Steam integration) or if profiling proves a real bottleneck. A rewrite for performance is forbidden without a measured failure against Phase-8 budgets.

---

# 3. Project architecture and ownership boundaries

The project should be organized around **domain purity**, not scene-tree convenience.

## 3.1 Layer A — Domain Core

Pure deterministic data + algorithms. No UI nodes, animations, audio, OS time, frame delta, random calls, Steam API or filesystem access.

Responsibilities:
- canonical map state;
- edit legality;
- map mutation;
- derived-world rebuild;
- route graphs;
- agent target resolution;
- reaction beats;
- objective/invariant evaluation;
- Stability cycles;
- causal event graph;
- intervention footprint;
- deterministic state hashing/canonical serialization helpers.

The Domain Core accepts explicit input structs and returns explicit result structs.

## 3.2 Layer B — Application Services

Owns session orchestration around Domain Core:
- current dossier session;
- edit command construction;
- Undo/Redo history;
- checkpoint/recovery coordination;
- campaign progression;
- demo import;
- save envelopes/version migration;
- content loading/validation;
- localization token access;
- platform storage/achievements abstraction.

Application Services may call the filesystem/platform adapters but may not change the rules of domain resolution.

## 3.3 Layer C — Presentation

Godot scenes/nodes for:
- Department Desk;
- dossier brief;
- map pane;
- world pane;
- case rail;
- causal ribbon;
- history UI;
- Stability UI;
- completion/settings/accessibility/help.

Presentation submits semantic `PlayerCommand`s and consumes immutable `ViewSnapshot`s / `ResolutionPresentationPlan`s.

It may interpolate animation, pan/zoom and play sounds. It may never move an agent to a gameplay node, decide whether a border is valid, or write progress directly.

## 3.4 Layer D — Platform Adapters

Replaceable boundary for:
- local filesystem;
- Steam Cloud/Remote Storage integration if used;
- Steam Achievements;
- input glyph source / Steam Input integration if later selected;
- build/platform metadata.

The base game must still run locally when the Steam adapter is absent (development build, offline mode, non-Steam QA).

---

# 4. Canonical runtime state model

## 4.1 Immutable content definition

`DossierDefinition` is immutable after load and identified by:
- `dossier_id`
- `content_schema_version`
- `dossier_content_version`
- `ruleset_version`
- `content_hash`

A running session references exact versions; it never silently substitutes a changed definition into an old active session.

## 4.2 Authoritative mutable session

`DossierSessionState` conceptually contains:

- `dossier_id`
- exact version tuple/hash above;
- `session_id` (persistence identity only; no gameplay semantics);
- `session_revision` monotonic integer;
- `map_state_by_layer`
- `agent_state_by_id`
- `objective_state_by_id`
- `invariant_state_by_id`
- `stability_state`
- `intervention_footprint_state`
- `last_transaction_id`
- `history_cursor`
- `causal_graph_current`
- `completion_state`

The canonical map state plus explicit agent state is sufficient to reconstruct all other derived facts.

## 4.3 Map state

For each layer:

`MapAuthorityState`
- sorted active road edge IDs;
- sorted active bridge crossing-slot IDs;
- sorted active water edge IDs;
- canonical border ownership mapping `cell_id -> jurisdiction_id` or equivalent edge representation;
- landmark semantic labels `landmark_id -> semantic_token`;
- restricted-zone active-cell sets by policy;
- authoritative linked facts owned by this layer only.

No presentation coordinates are authoritative gameplay data.

## 4.4 Derived world state

`DerivedWorldState`
- road traversal graph by relevant movement/permission class;
- water traversal graph;
- bridge validity/crossing relations;
- jurisdiction membership lookup;
- landmark semantic index;
- restricted-zone permissions;
- portal/projection facts;
- per-agent currently reachable targets and route inputs.

This can be cached but is disposable. A debug command must be able to discard caches and rebuild from authoritative state, producing the same canonical result.

## 4.5 Agent state

`AgentState`
- stable `agent_id`;
- archetype ID A1..A10;
- current node/cell;
- canonical target reference/query;
- task flags defined by content schema;
- movement status enum;
- trapped/blocked metadata;
- current resolved route as derived/cache data, not source truth unless needed for presentation checkpointing.

No agent exists mid-edge in the domain simulation.

## 4.6 Objective state

Objective and invariant instances are definition + evaluation result:
- `predicate_id/family_id`
- current boolean/status enum;
- machine-readable subjects/targets;
- first failing fact reference when false;
- causal event IDs that explain the latest status transition.

The localized sentence is presentation data, never the predicate implementation.

## 4.7 Causal graph

Each accepted edit or Stability cycle creates a finite directed acyclic event graph.

`CausalEvent`
- `event_id` assigned monotonically inside transaction;
- `transaction_id`;
- `event_type` from frozen registry;
- `subject_stable_id`;
- typed before/after payload using canonical IDs/integers/enums;
- `parent_event_ids[]` sorted;
- `phase` from resolution order;
- `beat_index` when applicable;
- `objective/invariant_relevance_tags[]` derived after evaluation.

The graph records **material causes**, not every read performed by code. It must be sufficient to answer Phase-6 questions such as “Why is this courier going there?” and “Which edit first caused this invariant to break?”

---

# 5. Determinism contract

## 5.1 Forbidden nondeterministic inputs in gameplay domain

Domain code must not read:
- wall-clock time;
- OS locale;
- frame delta;
- floating-point physics contacts;
- hash-map iteration order;
- random number generator without an explicit frozen seed (base campaign currently needs no RNG);
- unordered scene-tree child order;
- platform/Steam identity;
- animation completion timing.

## 5.2 Numeric policy

Gameplay topology, edge costs, counters, cycle windows, priority, mastery thresholds and objective values use integers/enums wherever possible.

Presentation coordinates may use floats. They cannot feed back into domain decisions.

If a future domain value truly needs fractional math, represent it as fixed-point integer units with a documented scale and explicit rounding rule rather than ambient float comparison.

## 5.3 Ordering policy

Every operation over a set that can affect output uses an explicit stable sort:
1. primary game rule priority;
2. stable ID tie-break as frozen in Phase 4;
3. no fallback to container insertion/hash order.

## 5.4 Canonical serialization/hash

The test harness defines a canonical domain serialization:
- stable field order;
- sorted stable-ID collections;
- explicit enum strings/integers;
- no volatile timestamps/session UI metadata;
- normalized UTF-8 strings for semantic tokens;
- no engine object instance IDs.

A cryptographic or strong deterministic digest of this canonical form is used for test fixtures and corruption checks. The exact hash algorithm is implementation-flexible if stable and versioned; changing it increments `canonical_hash_version`.

## 5.5 Replay determinism

A replay fixture consists of:
- exact content/rules version tuple;
- initial canonical state hash;
- ordered semantic player edit commands;
- explicit Stability commands/steps;
- expected transaction hashes and final state hash.

Replaying the fixture in a headless build must reproduce every expected hash.

---

# 6. Edit command and transaction architecture

## 6.1 Semantic command

Presentation never sends “mouse at x/y.” It constructs one semantic command:

`EditCommand`
- `command_id` local unique persistence ID;
- `primitive_family`;
- `operation` (add/remove/toggle/relabel/move-boundary as defined by Phase 4);
- `layer_id`;
- exact candidate stable IDs/endpoints/cell transfer;
- semantic label/policy token where required;
- `expected_pre_state_hash`.

The expected pre-state hash prevents stale double-commit if UI input repeats while a transaction is resolving.

## 6.2 Commit protocol

1. Application receives command only while session is in editable state.
2. Verify `expected_pre_state_hash == current canonical state hash`.
3. Run Phase-4 legality pipeline without mutation.
4. If illegal: return typed rejection; no revision/history change.
5. If legal: clone/build candidate authoritative map state.
6. Run the exact Phase A–G resolution order from Phase 4.
7. Produce new immutable domain checkpoint + causal graph.
8. Increment `session_revision` exactly once.
9. Persist safe checkpoint before UI considers the edit durable.
10. Append one history entry representing the player edit; derived consequences remain children of it.
11. Presentation animates already-decided results.

Double input with the same `command_id` after a successful commit returns the already-known transaction result or an idempotent “already applied” outcome; it never applies twice.

## 6.3 Transaction identity

`transaction_id` is deterministic within a session: e.g. session identity + committed revision, not a random value used by gameplay.

Only one domain transaction may commit at a time.

## 6.4 Resolution phases

Implementation names may differ, but observable order is exactly Phase 4:
A. map mutation;
B. structural derivation;
C. dependent validity cleanup;
D. agent query rebuild;
E. stranded/trapped adjudication;
F. bounded reaction beats with simultaneous intent/apply;
G. objective/invariant evaluation;
H. Stability eligibility/continuation;
I. presentation release.

A debug trace must print phase + event IDs so a failing fixture can be explained.

---

# 7. Reaction-beat implementation contract

Each beat uses a strict two-buffer approach:

1. Build immutable `BeatStartSnapshot`.
2. In stable agent-ID order, compute each intent from that same snapshot.
3. Collect intents; do not mutate positions during intent calculation.
4. Resolve conflicts using Phase-4 priority/tie-break semantics.
5. Apply accepted moves/state transitions simultaneously into next state buffer.
6. Apply arrival/service/ownership consequences in frozen order.
7. Evaluate affected facts and append causal events.
8. Commit next state as new beat state.

This prevents a low-ID agent from accidentally changing the world seen by a later agent in the same beat.

---

# 8. Linked-map authority architecture

## 8.1 Authority graph

Loaded dossier content compiles linked authority relations into a directed acyclic graph.

Validation rejects:
- any cycle;
- two source facts claiming authority over the same target fact;
- missing source/target stable IDs;
- projection whose target layer can directly edit the projected fact;
- projection semantics not in the frozen registry.

## 8.2 Recompute order

After a source edit:
1. resolve local source layer;
2. propagate projection facts in topological authority order;
3. rebuild affected target derived state;
4. only then rebuild agents whose queries depend on affected layers.

The UI may animate source/target later, but domain propagation is one atomic transaction.

## 8.3 Four-layer ceiling

Technical tooling hard-validates the Phase-5 maximum of four layers per dossier. No content author can bypass this by nesting sub-scenes.

---

# 9. Undo / Redo / checkpoints

## 9.1 History unit

One accepted **player edit** equals one history entry. Illegal attempts create none. Derived consequences do not create separate entries.

A history entry contains:
- semantic `EditCommand`;
- canonical pre-edit checkpoint/hash;
- canonical post-edit checkpoint/hash;
- transaction causal graph;
- intervention-footprint delta;
- version metadata.

## 9.2 Snapshot strategy

Because dossiers are intentionally compact, the preferred 1.0 implementation is **full canonical domain checkpoint per accepted edit**, optionally compressed, rather than a complex inverse-delta system.

Reason: correctness, recovery and deterministic Undo matter more than memory micro-optimization. Phase-8 budget allows this comfortably.

## 9.3 Undo

Undo restores the exact pre-edit checkpoint of the current history entry, including:
- map state;
- agent state;
- objective/invariant state;
- Stability state;
- intervention footprint;
- causal graph/history cursor.

It does not rerun “inverse gameplay.”

## 9.4 Redo

Redo is valid only while the linear branch is intact. It may restore the exact stored post-edit checkpoint after verifying content/rules version + pre-state hash, or deterministically replay the stored semantic command and assert the stored post-hash. Debug/test builds should favor replay+assert; release may restore checkpoint if equivalent.

## 9.5 Branching

Making a new accepted edit after Undo truncates the redo branch in active history. The discarded branch may remain in non-authoritative debug logs but is not player state.

## 9.6 Stability checkpoints

Starting/stepping Stability does not create normal intervention history entries.

The application keeps a **pre-Stability recovery checkpoint** at the latest accepted edit state. If Stability fails, the resulting failed state and causal graph remain inspectable; Undo returns to the relevant pre-edit history checkpoint according to Phase 6, while `Exit Stability` returns to the pre-Stability edit state without counting as an intervention.

If the game is quit mid-Stability, the current deterministic cycle state + cycle index are persisted so Continue can resume exactly or reconstruct from the pre-Stability checkpoint plus stored Stability step count and assert the same hash.

---

# 10. Save / profile model

## 10.1 Separate save domains

Use separate logical documents so frequently changing session data does not rewrite all long-lived data:

1. `settings` — accessibility, audio, language, remaps, display preferences.
2. `profile_progress` — cleared dossiers, mastery marks, tutorial tags, remix unlock facts, achievements mirrored locally, demo import receipts.
3. `active_session` — optional current dossier checkpoint/history/recovery state.
4. `recovery_backup` — previous valid generation of each mutable document.

Steam Cloud documentation recommends keeping cloud files small and separating frequently changing data where practical. Reference checked 2026-08-18: https://partner.steamgames.com/doc/features/cloud

## 10.2 Save envelope

Every document is wrapped in:
- `format_id`;
- `save_schema_version`;
- `profile_id`;
- `document_type`;
- `generation` monotonic integer;
- `created_by_build_version`;
- `rules/content version` where relevant;
- canonical payload;
- payload checksum/hash;
- optional diagnostic write timestamp (never used for gameplay or monotonic progression merge).

## 10.3 Atomic-ish durable write protocol

Godot provides `FileAccess` for user files and `DirAccess.rename()` for file replacement/rename. Official stable references checked 2026-08-18:
- https://docs.godotengine.org/en/stable/classes/class_fileaccess.html
- https://docs.godotengine.org/en/stable/classes/class_diraccess.html

Required application protocol:
1. serialize next envelope to `*.tmp`;
2. flush/close;
3. read it back through the same parser and verify checksum/schema;
4. preserve current valid primary as `*.bak` generation where possible;
5. rename validated temp to primary;
6. only after success report checkpoint durable to application session.

The design does **not** claim filesystem rename is crash-atomic on every platform. Recovery therefore always scans primary + backup + valid temp remnants and selects the highest valid generation under the rules below.

## 10.4 Load/recovery selection

For each document type:
1. enumerate recognized primary/backup/temp candidates;
2. reject invalid checksum/schema/profile mismatch;
3. migrate supported older schema in memory;
4. choose highest valid generation;
5. if equal generation payloads differ, treat as conflict/corruption and preserve both for diagnostics rather than silently choosing by file iteration order;
6. rewrite a clean primary after successful recovery.

If no valid `settings` exists: use defaults.
If no valid `active_session` exists: return to Department Desk; profile progress is not lost.
If `profile_progress` is corrupt and no backup/migratable copy exists: enter Recovery UI and never overwrite the bad files automatically until user starts a fresh profile/export workflow.

---

# 11. Save schema migration

## 11.1 Versioning rule

Every persistent schema change requires a monotonic migration function `N -> N+1`. Loading may chain supported migrations. No migration may depend on scene objects or localized display strings.

## 11.2 Content changes versus save schema changes

Save schema version and dossier/rules version are separate.

- **schema migration** changes representation of save data;
- **content compatibility** decides whether an active dossier session can still be resumed under changed rules/content.

## 11.3 Active dossier compatibility

An active session resumes only if its exact `dossier_content_version`, `ruleset_version` and required canonical-hash version are supported.

If not:
- preserve profile progress;
- archive incompatible active session;
- explain `This in-progress case was created with an older rules version and cannot be resumed safely`;
- offer restart of that dossier from canonical initial state;
- never attempt a best-effort reinterpretation that could change puzzle outcomes.

Already recorded baseline clears/mastery remain unless an explicit migration marks a historical record invalid for a documented reason. Default is monotonic preservation.

---

# 12. Steam Cloud and cross-device merge semantics

## 12.1 Platform independence

Domain saves are plain application data under the `PlatformStorageAdapter`. The design does not require Steam APIs for correctness.

Steam Cloud is a target, not the authoritative gameplay engine.

Official Steam Cloud reference checked 2026-08-18:
https://partner.steamgames.com/doc/features/cloud

## 12.2 What is cloud-eligible

Cloud target:
- `profile_progress`;
- `settings` excluding machine-specific graphics/window placement;
- `active_session` if conflict/recovery testing passes before release.

Do not cloud:
- logs;
- caches;
- generated thumbnails;
- machine-specific graphics/device identity;
- temporary recovery files unless specifically required by the chosen Cloud adapter.

## 12.3 Semantic merge for progress

Whenever two valid `profile_progress` envelopes are available to the application (Cloud conflict recovery, import, backup reconciliation), merge by facts rather than last-writer overwrite:

- baseline clear = boolean OR by exact compatible dossier record;
- tutorial tag = set union;
- remix unlock = derived again from merged baseline clears;
- mastery = union of legitimately earned authored mastery IDs; if a mastery definition version changed incompatibly, preserve historical record separately and revalidate only when canonical migration says compatible;
- achievement-local mirror = union, with platform service remaining external authority for platform achievement state;
- demo import receipt IDs = set union;
- no currency/max-level conflict exists because Phase 7 forbids progression currency/power.

The merged document receives a new generation and records both parent envelope hashes for diagnostics.

## 12.4 Settings merge

Accessibility-critical preferences should not be silently reset by a stale device.

When two settings documents are available:
- per-setting values carry a `setting_revision` and optional diagnostic changed timestamp;
- higher explicit setting revision wins;
- if revisions tie with different values, keep the currently active local device value and record a recoverable conflict marker; do not use wall-clock time as sole authority.

Machine-specific settings are local-only.

## 12.5 Active-session conflict

Active dossier sessions can be auto-merged only when one is a strict deterministic descendant of the other:
- same `session_id`;
- same content/rules versions;
- one history command sequence is an exact prefix of the other;
- all shared checkpoint hashes match.

Then keep the descendant.

If branches diverge or session IDs differ:
- never synthesize a hybrid puzzle state;
- preserve both candidates when platform adapter exposes both;
- present a compact recovery choice using dossier, history length and last safe generation, while profile progression remains merged separately.

If the chosen Steam Cloud integration cannot expose both conflicting candidates reliably, release must rely on Steam's own conflict resolution plus local primary/backup recovery; Phase 13 QA must document this limitation rather than pretending app-level merge exists.

## 12.6 Cross-platform paths

Cloud path configuration must be tested for Deck/desktop cross-platform behavior. Steam documentation notes Auto-Cloud roots can partition by OS if configured separately; configuration must intentionally support the desired cross-platform save behavior.

---

# 13. Demo -> full-game identity/import

## 13.1 Separate application, shared logical format

The demo and full game use the same **logical profile-progress schema family** but different app/build identifiers.

The full game has an explicit `DemoImportService`; it never simply copies arbitrary demo files into the full save directory.

## 13.2 Import record

A demo export/import candidate contains:
- `demo_profile_id`;
- demo build/content/rules versions;
- settings subset;
- exact demo dossier/substrate clear records;
- mastery records only for canonical-equivalent dossier versions;
- checksum;
- `demo_import_receipt_id` deterministically derived from candidate identity/hash.

## 13.3 Import semantics

1. Validate format/checksum.
2. Map demo records through an explicit versioned `demo_to_full_mapping` table.
3. Import compatible settings.
4. Add compatible baseline clears monotonically.
5. Import mastery only if the exact canonical dossier/mastery contract is declared equivalent.
6. Record receipt ID.
7. Repeating the same import is a no-op except confirmation.
8. Import never deletes fuller progress or locks content.
9. Unknown/incompatible clear records are skipped with human-readable explanation; settings can still import.

No demo-exclusive power/content is created.

---

# 14. Input abstraction

Godot's InputMap supports named actions mapped to keyboard, mouse and joypad events and can be modified in code, which fits the Phase-6 semantic input model.

Official references checked 2026-08-18:
- https://docs.godotengine.org/en/stable/classes/class_inputmap.html
- https://docs.godotengine.org/en/4.7/tutorials/inputs/input_examples.html

## 14.1 Semantic action layer

Presentation code consumes actions such as:
- `ui_focus_next/previous`;
- `map_focus_north/south/east/west`;
- `confirm`;
- `cancel`;
- `inspect`;
- `toggle_map_world_focus`;
- `cycle_tool_prev/next`;
- `cycle_layer_prev/next`;
- `undo`;
- `redo`;
- `correspondence_focus`;
- `stability_start_pause`;
- `stability_step`;
- `history_prev/next`;
- `zoom_in/out`;
- `pan_*` or analog pan vector.

Physical device events never directly invoke domain edits.

## 14.2 Logical focus graph

Keyboard/controller navigation uses stable focusable candidate IDs + directional neighbor queries precomputed from map presentation geometry. It does not emulate a hidden mouse cursor.

For two-endpoint edits, the focus graph filters to legal second endpoints after first selection.

## 14.3 Remapping

Remaps are stored as portable action-event descriptors where feasible. Reserved OS/platform shortcuts and impossible conflicts are rejected with explanation.

The UI always has a recover-default-controls action accessible without needing the broken binding itself.

## 14.4 Steam Deck constraints

Steam's current Deck compatibility documentation recommends/supports 1280×800 and requires all functionality to be accessible through the default controller configuration for Verified status; it also defines text legibility requirements. References checked 2026-08-18:
- https://partner.steamgames.com/doc/steamhardware/recommendations
- https://partner.steamgames.com/doc/steamhardware/compat

Technical acceptance target:
- 1280×800 primary Deck layout;
- no mandatory text typing in gameplay (landmark names are token selection);
- all required commands controller reachable;
- glyph switching must not change focus state;
- 9 px character height is an absolute compatibility floor, but project UI target is materially larger, aiming at >=12 px equivalent minimum for ordinary essential text at 1280×800 before user scaling;
- 44 logical px target requirement from Phase 6 remains.

---

# 15. Localization/content text pipeline

## 15.1 Tokenized text

Content definitions reference stable localization tokens, never player-facing English as logic keys.

Examples:
- `DOSSIER_D12_TITLE`
- `OBJ_KEEP_HOSPITAL_REACHABLE`
- `AGENT_ROLE_EMERGENCY_SERVICE`
- semantic map label token IDs distinct from translated display strings.

Changing translation never changes gameplay semantic identity.

## 15.2 Format direction

Preferred localization workflow: gettext `.po` or another Godot-supported version-control-friendly translation format. Godot supports PO/MO, translation resources, runtime locale selection and pseudolocalization.

Official references checked 2026-08-18:
- https://docs.godotengine.org/en/stable/tutorials/i18n/internationalizing_games.html
- https://docs.godotengine.org/en/latest/tutorials/i18n/localization_using_gettext.html

## 15.3 Validation

Build validation fails on:
- missing required localization token in source language;
- duplicate token with incompatible context;
- machine predicate using translated/display text as an ID;
- unescaped/invalid placeholders;
- UI critical string missing pseudolocalization coverage.

Pseudolocalization + ~35% expansion is a mandatory Phase-6 layout test. RTL/CJK scope depends on final supported languages, but layout/data structures must not prevent later support.

---

# 16. Content authoring and compilation pipeline

## 16.1 Source-of-truth content

Dossier content should live in human-reviewable versioned source files (Godot Resources, JSON-like source, or another text-friendly structured format) with a deterministic compiler/validator step.

The exact authoring syntax is implementation-flexible; the **compiled logical schema is not**.

## 16.2 Content compiler outputs

For each dossier:
- canonical normalized definition;
- content hash;
- all stable ID registries;
- authority DAG;
- precomputed snap/focus candidates;
- initial derived-world validation result;
- objective/invariant registry;
- tutorial tags/prerequisites;
- mastery contracts;
- optional known-solution fixtures for validation only (never shipped as solver hints unless explicit Solution Guidance data is authored separately).

## 16.3 Validation levels

### Structural validation
- stable IDs unique;
- all references resolve;
- candidate topology valid;
- no malformed borders/crossings;
- no linked-authority cycle/double owner;
- layer count <=4;
- agent count/content ceilings obey Phase 5;
- objective clauses within ceilings;
- editable primitive permissions legal;
- semantic label vocabularies nonempty where required.

### Rule validation
- initial state is legal;
- every archetype configuration matches A1..A10 schema;
- objective family parameters valid;
- reaction beats <=5;
- Stability cycles <=5;
- no dossier-specific behavior script hook exists.

### Progression validation
- D01–D40 IDs/act placement valid;
- prerequisite/tutorial tag graph has no cycle;
- D40 reachable with zero mastery marks;
- remix packs unlock exactly by D08/D24/D40 rules;
- no optional mastery required for baseline progression.

### Solution-envelope validation
Every authored campaign dossier must have at least one known baseline-clearing command sequence for the exact content/rules version. This fixture proves solvability, not uniqueness.

Where practical, bounded search tooling should probe for trivial brute-force/dominant shortcuts and flag unexpectedly tiny solution spaces, but failure to exhaustively solve late dossiers is not itself invalid if authored fixtures + adversarial tests are strong.

---

# 17. Deterministic dossier test harness

## 17.1 Headless execution

Godot supports `--headless`, suitable for CI/script execution. Official reference checked 2026-08-18:
https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html

The implementation repo must provide one command that runs all domain/content tests headlessly with nonzero exit on failure.

## 17.2 Required fixture classes

1. **Primitive legality fixtures** — every add/remove/toggle/relabel legality edge.
2. **Resolution-order fixtures** — verify Phase A–I observable ordering.
3. **Agent archetype fixtures** — A1..A10 target/path/permission semantics.
4. **Simultaneous conflict fixtures** — agent order cannot leak into same-beat intent.
5. **Causal ancestry fixtures** — expected parent/first-cause chain.
6. **Undo/Redo fixtures** — hash returns exactly to stored pre/post checkpoints.
7. **Stability fixtures** — clean window and first-failure behavior.
8. **Linked authority fixtures** — one-way projection/topological propagation.
9. **Save/recovery fixtures** — primary/temp/backup corruption combinations.
10. **Migration fixtures** — every supported save schema hop.
11. **Demo import fixtures** — idempotency/compatibility/monotonicity.
12. **Campaign graph fixtures** — no mastery gate, tutorial prerequisites valid.
13. **Accessibility/input smoke fixtures** — every mandatory semantic command mapped/reachable in each required control mode.
14. **Golden replay fixtures** — deterministic command sequence -> expected transaction/final hashes.

## 17.3 Metamorphic tests

Useful invariants:
- rebuild-all derived state equals incremental affected rebuild;
- Undo(Edit(S)) == S exactly;
- Redo(Undo(Edit(S))) == Edit(S) exactly while branch intact;
- applying same committed `command_id` twice does not advance revision twice;
- presentation animation speed/reduced-motion setting does not alter domain hash;
- localization language does not alter domain hash;
- input device producing same semantic command yields same domain hash.

---

# 18. Performance and memory budgets

This is a small deterministic puzzle game. Budgets exist to prevent architectural bloat, not because the design is computationally demanding.

## 18.1 Domain simulation

Release target on minimum-supported desktop and Steam Deck-class hardware:
- typical accepted edit domain resolution: **<=8 ms median, <=25 ms p95** excluding presentation animation;
- worst authored late-game accepted edit: **<=50 ms p99** in normal release build;
- one Stability cycle: **<=16 ms p95**;
- no visible multi-frame hitch from serialization after ordinary edit.

If full recomputation exceeds these budgets, optimize affected subsystems while preserving equivalence tests.

## 18.2 Presentation

- target 60 FPS at 1280×800 Deck layout and common desktop resolutions;
- 30 FPS must remain mechanically usable if device throttles, because domain is not frame-dependent;
- split map/world panes use lightweight 2D rendering; no scene requires thousands of animated agents;
- world-side agent ceiling follows Phase 5 (normally <=10), so object count is not a justification for complex pooling/ECS prematurely.

## 18.3 Memory

Design target:
- runtime working set comfortably below **1 GB** on Deck/desktop, with aspirational typical substantially lower;
- all Undo checkpoints for one dossier should normally remain below **64 MB** uncompressed equivalent; if a pathological dossier exceeds this, compress/canonical-delta storage may be introduced without changing history semantics;
- save/profile files target kilobytes to low megabytes, not large binary snapshots/assets.

## 18.4 Load times

- Department Desk to ordinary dossier interactive: target <=2 s on SSD/Deck-class storage after initial asset warmup;
- save checkpoint write should be short enough that edits do not feel gated by disk; async preparation is allowed, but a transaction is not considered durable until safe checkpoint commit completes.

These are engineering targets, not gameplay rules; Phase 13 profiling may adjust exact thresholds if user experience remains equivalent.

---

# 19. Failure handling

## 19.1 Illegal edit
Typed rejection, no mutation, no history revision.

## 19.2 Unexpected domain assertion
In development/test: fail loudly with dossier, command, pre-state hash and deterministic trace.
In release: preserve last safe checkpoint, cancel uncommitted transaction, show recoverable error and return to latest safe state rather than saving a partial result.

## 19.3 Incomplete transaction on crash
Because durable save happens only after full domain transaction produces a checkpoint, recovery loads either the previous valid revision or the fully written next revision. A partial in-memory transaction has no authority.

## 19.4 Corrupted active session
Archive/retain corrupt candidate, try backup. If unavailable, keep profile progress and restart only the active dossier.

## 19.5 Corrupted profile progress
Never silently reset and overwrite. Try backups/migrations; if none valid, enter Recovery UI and preserve originals.

## 19.6 Unsupported old active-session version
Do not reinterpret under new rules. Preserve/archive and restart dossier from canonical initial state while retaining compatible profile progression.

## 19.7 Missing content referenced by progress
Historical clear/mastery record remains a tagged orphan record until migration decides its mapping. It must not crash Department Desk or unlock unrelated content accidentally.

## 19.8 Platform/Steam unavailable
Local save, progression and game remain functional. Platform achievement/cloud actions queue/reconcile when adapter returns; they never block dossier completion.

---

# 20. Implementation order / vertical slice

This is an implementation handoff plan, not production work in the factory.

## Slice 0 — Domain test skeleton
Build stable IDs, canonical serialization/hash, minimal DossierDefinition loader, headless test command.

Exit: one trivial domain state hashes identically across repeated runs.

## Slice 1 — Road-only executable map
Implement:
- single layer;
- road add/remove legality;
- Direct Courier A1;
- one reachability objective;
- deterministic reaction beat;
- semantic command;
- map/world presentation with correspondence;
- Undo/Redo full snapshots.

Exit: a D01-like case is playable mouse + keyboard and passes replay fixture.

## Slice 2 — Full local causal loop
Add:
- bridge/water crossing relation;
- border ownership;
- restricted zones;
- multiple agents;
- protected invariant;
- causal event graph/ribbon;
- Stability 1–2 cycles;
- save/recovery primary+backup.

Exit: a D08-like synthesis case proves the product hook end to end, including controller-only basic completion.

## Slice 3 — Remaining primitive semantics
Add:
- landmark semantic labels;
- editable waterways;
- Ferry/Semantic Seeker/remaining local archetypes;
- all objective families through Act III;
- full input remapping/accessibility scaffolding.

## Slice 4 — Linked authority
Add:
- authority DAG;
- multiple layers/portals;
- A10;
- O12;
- linked-map UX.

## Slice 5 — Campaign/profile/demo/platform
Add:
- complete progression graph;
- mastery/remixes;
- durable profile/save migrations;
- demo import service;
- Steam adapter/cloud/achievements integration;
- localization pipeline.

## Slice 6 — Full content population
Only after systems validate, author/import all 40 dossiers + 12 remixes through validated data pipeline.

This order intentionally proves the existential map->world causality/anti-opacity risk before large content production.

---

# 21. Release-mode observability and debugging

The domain should expose opt-in developer diagnostics:
- current canonical state hash;
- loaded content/rules versions;
- current transaction/revision;
- causal trace export;
- route decision explanation;
- save candidate/generation report;
- content validation report.

Player-facing builds may hide raw IDs behind a support export, but crash/support logs must never include unnecessary personal/Steam account data.

A `replay bundle` for QA may contain dossier/version tuple, initial hash and semantic commands, allowing deterministic bug reproduction without sending a screenshot/video.

---

# 22. Explicit technical non-goals

Do not introduce for 1.0 unless canonical design is reopened:
- continuous physics-based agent movement as gameplay truth;
- real GIS geometry;
- navmesh pathfinding dependent on float geometry;
- procedural campaign generator;
- online authoritative backend;
- multiplayer synchronization;
- ECS/data-oriented rewrite for scale;
- generic scripting language embedded in dossier content;
- arbitrary user text as landmark semantic identity;
- freehand geometry recognition;
- Workshop/UGC editor architecture;
- cloud requirement for offline play;
- telemetry requirement for completion.

---

# 23. Technical risks and gates

## T8-R1 — Domain/presentation leakage
Risk: scene nodes become source of agent positions/topology.
Gate: headless replay without presentation scenes produces identical final hashes to interactive semantic command fixtures.

## T8-R2 — Content hardcoding
Risk: late dossier requires special-case script.
Gate: all shipped dossiers instantiate only frozen primitives/archetypes/objective/projection schemas; validator rejects arbitrary behavior hooks.

## T8-R3 — Determinism drift
Risk: dictionary iteration/floats/frame timing alter paths.
Gate: golden replay fixtures run repeatedly/headlessly and across target OS builds where practical with identical canonical hashes.

## T8-R4 — Undo memory bloat
Risk: full snapshots become unexpectedly large.
Gate: worst planned late dossier measured; if checkpoint history exceeds 64 MB typical ceiling, compress/delta internally while exact restore tests remain mandatory.

## T8-R5 — Cloud conflict data loss
Risk: older device overwrites progress.
Gate: semantic profile merge tests + documented Steam adapter conflict behavior; active branch never auto-merges divergent histories.

## T8-R6 — Demo/full mismatch
Risk: transfer grants invalid clears or duplicates progress.
Gate: versioned mapping + import receipt idempotency fixtures.

## T8-R7 — Linked-map circularity
Risk: two layers recursively rewrite each other.
Gate: authority DAG validated at content compile/load; cycle is hard error.

## T8-R8 — Deck control regression
Risk: a new UI feature is mouse-only.
Gate: semantic-action reachability checklist and controller-only full-dossier QA required before phase closure.

## T8-R9 — Localization changes logic
Risk: translated labels become semantic IDs.
Gate: language switch during same replay cannot change domain hash; logic stores tokens/stable IDs only.

## T8-R10 — Save crash window
Risk: a failed replacement corrupts only copy.
Gate: primary/temp/backup fault-injection fixtures at each write step recover highest valid generation or safely fall back.

---

# 24. Phase-8 acceptance tests

### Engine / boundaries
- **T8-01** — Project pins an exact stable Godot version; upgrading requires explicit test pass, never ambient `latest`.
- **T8-02** — Domain Core can execute a dossier fixture headlessly without loading gameplay presentation scenes.
- **T8-03** — Presentation cannot mutate canonical domain collections except by submitting semantic commands.
- **T8-04** — Steam/platform adapter absence does not prevent local play/save/completion.

### Determinism
- **T8-05** — Same definition + pre-state + semantic edit command yields identical canonical post-state hash across 100 repeated runs.
- **T8-06** — Agent same-beat intent is invariant to internal iteration/container order after explicit stable sorting.
- **T8-07** — Reduced motion, animation speed, locale and input device cannot alter domain state hash for equivalent command sequence.
- **T8-08** — Full derived-state rebuild equals any optimized incremental rebuild for canonical hash/output.

### Transaction / history
- **T8-09** — Stale `expected_pre_state_hash` rejects command without revision advance.
- **T8-10** — Duplicate committed `command_id` cannot apply twice.
- **T8-11** — Illegal edit creates no transaction/history/save generation.
- **T8-12** — One accepted player edit increments session revision/history exactly once regardless of number of derived consequences.
- **T8-13** — Undo restores exact pre-edit canonical hash.
- **T8-14** — Redo on intact branch reproduces exact stored post-edit hash.
- **T8-15** — New edit after Undo truncates redo branch without corrupting canonical state.

### Mechanics / causal graph
- **T8-16** — Resolution observable order matches Phase A–I contract.
- **T8-17** — Simultaneous beat uses one start snapshot for all intent calculations.
- **T8-18** — Causal graph can return first relevant ancestor for a newly broken invariant.
- **T8-19** — Agent route explanation uses canonical rule/tie-break data rather than reverse-engineering animation.
- **T8-20** — Linked authority cycle or double owner is rejected before dossier becomes playable.

### Persistence
- **T8-21** — Primary corrupt + backup valid loads backup without losing profile progress.
- **T8-22** — Temp complete but primary old selects highest valid generation according to recovery rules.
- **T8-23** — Equal-generation divergent payloads are surfaced as conflict/corruption, never selected by filename iteration.
- **T8-24** — Unsupported active-session rules/content version preserves profile and offers dossier restart rather than unsafe reinterpretation.
- **T8-25** — Every supported save schema migration fixture produces expected canonical next schema.
- **T8-26** — Settings loss uses defaults without affecting progress.
- **T8-27** — Platform outage does not block safe local save.

### Cloud/demo
- **T8-28** — Merging two compatible profile-progress candidates is monotonic: no baseline clear/tutorial tag/mastery record is lost.
- **T8-29** — Active sessions auto-select descendant only when history prefix and shared hashes prove ancestry.
- **T8-30** — Divergent active-session branches are never combined into a synthetic state.
- **T8-31** — Reimporting same demo receipt is idempotent.
- **T8-32** — Incompatible demo clear is skipped while compatible settings may still import.

### Input/accessibility/localization
- **T8-33** — Mouse+keyboard, keyboard-only and controller-only can produce every required semantic dossier command.
- **T8-34** — No gameplay primitive requires text typing/freehand precision.
- **T8-35** — 1280×800 Deck layout keeps all mandatory controls reachable and essential text above compatibility floor at default project scale.
- **T8-36** — Reset Controls is reachable after a deliberately broken remap.
- **T8-37** — Missing source localization token fails validation.
- **T8-38** — Pseudolocalization pass exposes no clipped mandatory dossier requirement/control at supported UI scales.

### Content pipeline
- **T8-39** — All shipped dossier definitions pass stable-ID/reference/schema validation.
- **T8-40** — Campaign prerequisite graph is acyclic and D40 remains reachable with zero mastery marks.
- **T8-41** — Every authored campaign dossier has at least one exact-version baseline solution fixture.
- **T8-42** — Dossier exceeding layer/agent/reaction/Stability/clause ceilings fails validation.
- **T8-43** — Dossier cannot register arbitrary behavior code that overrides canonical A1..A10/primitive semantics.

### Performance/failure
- **T8-44** — Representative late-game edit meets target domain-resolution budget on Deck-class reference hardware or triggers profiling before content expansion.
- **T8-45** — Fault injection at each save-write stage leaves at least one recognized valid generation or safely reports unrecoverable corruption without overwriting evidence.
- **T8-46** — Forced failure during an uncommitted domain transaction recovers the last durable checkpoint, never a partial map/agent hybrid.
- **T8-47** — A replay support bundle reproduces the reported canonical final hash in a headless QA run.

---

# 25. Phase-8 closure decision

- Engine/runtime direction frozen enough for implementation: **YES — Godot 4.7.1-stable, GDScript-first, 2D**
- Domain/presentation ownership boundary frozen: **YES**
- Conceptual data model frozen: **YES**
- Deterministic transaction architecture frozen: **YES**
- Undo/Redo/checkpoint semantics frozen: **YES**
- Save/profile/recovery/versioning semantics frozen: **YES**
- Steam Cloud semantic merge policy frozen at application level: **YES, with explicit adapter limitation handling**
- Demo/full import semantics frozen: **YES**
- Input abstraction/Deck constraints frozen: **YES**
- Localization/content pipeline frozen: **YES**
- Headless validation/replay harness frozen: **YES**
- Performance budgets defined: **YES**
- Implementation/vertical-slice order defined: **YES**
- Failure handling defined: **YES**
- Phase-8 acceptance tests: **47**
- Production implementation started: **NO**
- Earlier canonical phase reopened: **NO**
- Phase 8 Technical Implementation Specification: **COMPLETE ON PAPER**
- DESIGN COMPLETE: **NO**

## Technical contradiction review

No true contradiction was found requiring Phase 3–7 reopening.

Two implementation-sensitive caveats are deliberately explicit rather than hidden:
1. filesystem rename is not assumed universally crash-atomic; multi-generation recovery is the actual safety contract;
2. app-level Cloud merge is guaranteed only when the selected Steam integration exposes both candidates; otherwise Steam conflict selection + local backup recovery is the documented boundary, never a fabricated merge guarantee.

## NEXT PHASE

**Phase 9 — Whole-Game Simulation on Paper.**

The next run must walk the canonical game end-to-end through first boot, first 5 minutes, first 30–60 minutes, end of each campaign act, first linked-map dossier, D40 synthesis, remix/mastery replay, demo->full transition, interrupted save/recovery, controller/Deck path and hostile/unusual player behavior. It must record contradictions/boring loops/opacity risks and repair only the smallest canonical phase when genuinely necessary.
