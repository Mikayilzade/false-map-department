# FALSE MAP DEPARTMENT — IMPLEMENTATION STATUS

Last updated: 2026-08-24
Repository: `Mikayilzade/false-map-department`

## Master state
- Design frozen: **YES**
- Fresh-session design audit: **PASS — 32/32**
- Design migration: **COMPLETE / VERIFIED**
- Final-freeze integrity: **VERIFIED — blob SHA `fc988f8eaa031507f5ae84d6e60316356bc6cb2a` matches factory source**
- 12A Technical Bootstrap: **COMPLETE**
- 12B Vertical Slice: **COMPLETE**
- 12C Core Systems: **COMPLETE**
- 12D Content Population: **COMPLETE**
- 12E UX / Accessibility / Controller / Deck: **COMPLETE**
- 12F Adversarial QA: **COMPLETE — real-Godot runtime-green**
- 12G Empirical Gates: **IN PROGRESS — DEMO01-DEMO05 production acquisition path runtime-green; actual observations pending**
- 12H Release Candidate: **NO**
- IMPLEMENTATION COMPLETE: **NO**

## Latest implementation run — 2026-08-24

### Phase / subphase
**12G Empirical Design Gates / production demo acquisition readiness — RUNTIME GREEN**

### Completed before this packet
- Machine-readable E1-E12 + T8-44 registry and anti-fabrication evidence harness are implemented.
- E1/E2/E11 opt-in telemetry, T8-44 profiler, E3-E7/E9-E10 session/capture packet generation, safe evidence collector, qualitative dispositions and gate dashboard are implemented.
- E7 planning packet covers all **57 shippable IDs** across five Deck/accessibility scenarios = **285 blank capture rows**.
- E10 correctly represents the frozen ten mechanical families A1-A10 = 45 comparison pairs, while retaining themed raw variant IDs separately for auditability.
- All unobserved human/market/hardware gates remain PENDING by construction.

### Acquisition-readiness blocker found and repaired
- Before this packet, the only playable app presentation still loaded `content/vertical_slice/VS01.json` through `SliceInteractionController`. Production DEMO01-DEMO05 existed and validated as content, but a representative E11 run would have measured the wrong playable build.
- Added a guarded application entrypoint. Normal launch still routes to the legacy validated `main.tscn`; an explicit `FMD_PLAYTEST_DOSSIER_ID` routes to the production playtest scene. This prevents a requested empirical session from silently falling back to VS01.
- Added `ProductionDossierRuntimeAdapter` to translate authored production dossier schema into the existing deterministic `CoreTransactionCoordinator` runtime without guessing hidden geometry.
- Added explicit `content/runtime_bindings.json` for the currently necessary D05/DEMO05 node-to-cell and border-target bindings. Missing production geometry is rejected instead of inferred from stable-ID names.
- Added `ProductionPlaytestController` using the real transaction coordinator, Undo/Redo and `StabilityInteractionService`.
- Added a real 1280x800 production playtest scene for DEMO01-DEMO05 with official-map controls, derived-world state, visible requirements, causal events, controller/keyboard semantic input, correspondence, Undo/Redo, Stability and sequential demo progression.
- Added human-readable DEMO01-DEMO05 playtest copy. It exposes the frozen visible goals/lessons but contains no known-solution commands.
- Existing opt-in empirical telemetry is wired into the production scene: correspondence opening, first observed broken requirement and final DEMO05 completion are timed; human comprehension/prediction/aha success is still explicit observer evidence and is never inferred from clicks.

### Smallest content repair found by real runtime execution
- Real transaction execution exposed a contradiction in the introductory border lesson D05/DEMO05: West owned only HOME, while the frozen one-cell solution transfers HOME to East, yet West had been marked `required_exist=true`; the authority engine correctly rejects emptying a required jurisdiction.
- Re-authored only the smallest affected intro instances: D05 West and DEMO05 West are now non-required, allowing the taught ownership transfer. D06 remains `required_exist=true` for West and therefore retains the next lesson's explicit preserve-West constraint.
- Content hashes were recomputed; no new mechanic or solution command was introduced.

### Systemic validator repair found by the new acquisition suite
- The first production validation pass exposed an old false-positive in `FrozenContentValidator`: `_ids_from_collection` selected reference `node_id` before a landmark slot's own `landmark_slot_id` (and likewise could do so for portal nodes), producing false duplicate stable IDs.
- Fixed identity extraction to prefer each record's own identity (`edge_id`, `cell_id`, `crossing_slot_id`, `landmark_slot_id`, `portal_id`, `feature_id`, `candidate_id`) before fallback `node_id`.
- Phase 12G acquisition-readiness audit now statically locks that corrected priority, and real D05/DEMO05 validator assertions provide runtime regression coverage.

### Real production-path validation
- Added `test_phase12g_production_playtest_runner.gd`.
- It loads the exact production DEMO01-DEMO05 catalog and executes every authored `known_solution_envelope.solution_commands` through the real `CoreTransactionCoordinator`, rather than merely inspecting JSON.
- It verifies authored expected requirement truth, immediate completion where Stability is not required, real Stability completion for DEMO05, exact Undo/Redo state-hash restoration, authored bridge-candidate -> crossing-slot binding, and D05/DEMO05/D06 border-contract intent.
- Added a headless smoke launch with `FMD_PLAYTEST_DOSSIER_ID=DEMO01` so the actual production playtest scene must parse and boot.
- The pre-existing Phase 12A bootstrap audit was updated narrowly: it accepts the guarded entrypoint only when the explicit empirical selector and legacy `main.tscn` fallback are both present.

### Validation history for this packet
- PR #7 production acquisition path merged as `32386b9f81fe6f2bb35232d165565709a971b0ff`. First factual run correctly failed, revealing the stale Phase12A main-scene assertion, one test fixture ID typo and the frozen-validator false duplicate issue.
- PR #8 repaired the guarded-entrypoint audit and bridge fixture, merged as `3c69ec714b75d9095e1b456335d702a024f6de61`. Second factual run returned `runtime_rc=0` and `phase12a_contract_rc=0`; only the newly diagnosed frozen-validator bug remained.
- PR #9 repaired stable-identity extraction, merged as `c41da9eca0ded2e8c361ee170d1a88be524acf01`.
- Automatic baseline run `32695197454` targeted exactly `c41da9eca0ded2e8c361ee170d1a88be524acf01`.
- Final aggregate evidence: **PASS** — `runtime_rc=0`, `phase12a_contract_rc=0`, `phase12g_instrumentation_rc=0`, all bootstrap/CI/fetch checks zero.
- Detailed Phase 12G results: preconditions PASS; instrumentation audit PASS; session packet audit PASS; operator workflow audit PASS; acquisition readiness audit PASS; Godot 4.7.1 instrumentation tests PASS; **production DEMO01-DEMO05 playtest tests PASS**; production playtest scene smoke PASS.
- Empirical dashboard remains correctly **13 PENDING / 0 PASS / 0 FAIL / 0 BLOCKED** because these are acquisition-readiness facts, not human/hardware/market observations.

### Current empirical state
- E1/E2/E11: **production DEMO01-DEMO05 build is now technically ready for representative acquisition; actual tester rows remain PENDING**.
- E3-E6/E9-E10: protocols/templates exist, but representative campaign/remix production-playtest coverage still needs the necessary explicit runtime geometry/bindings before claiming acquisition readiness for those selected cases.
- E7: 285-row capture matrix exists, but this must not be confused with 57 production dossiers all being interactively capture-ready yet.
- T8-44: **PENDING Deck-class reference hardware evidence**.
- E8: **PENDING representative store/trailer expectation evidence**.
- E12: **PENDING near-release market/value recheck**.

### Failures / blockers
- **No known correctness blocker remains for the production DEMO01-DEMO05 acquisition path.**
- Actual E1/E2/E11 PASS/FAIL still requires representative human observations.
- Broader E3-E7/E9-E10 acquisition requires extending the production playtest adapter/bindings to the representative campaign/remix cases used by those protocols.
- T8-44 requires Deck-class reference hardware; E8/E12 require their appropriate external evidence stages.

## NEXT ACTION
Continue 12G acquisition readiness in a broad implementation packet: extend the production playtest path from DEMO01-DEMO05 to the representative E3-E6/E9-E10 campaign/remix cases selected by the existing session protocols, using explicit authored/runtime bindings rather than stable-ID-name inference; then add an executable E7 production capture harness for the shippable cases that are genuinely runtime-ready. Keep all human/capture-review/hardware/market outcomes PENDING until real evidence exists. In parallel, the now-ready DEMO01-DEMO05 build may be used for real E1/E2/E11 sessions. **Do not start 12H until all E1-E12 gates have evidence-backed dispositions or an explicit release blocker.**
