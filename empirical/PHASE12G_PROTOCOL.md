# Phase 12G empirical evidence protocol

This phase must separate implementation facts from human, hardware, and market evidence. No gate may be marked PASS because an automated test merely proves the UI or telemetry exists.

## Evidence storage

Raw observations are append-only JSON Lines files under `empirical/evidence/<GATE_ID>.jsonl`. Each row must contain every field declared by `empirical/phase12g_gate_registry.json`. Tester/respondent identifiers should be pseudonymous and contain no unnecessary personal data.

Run `python3 scripts/phase12g_evidence_harness.py` to validate rows and produce a current summary. Run `bash scripts/run_phase12g_preconditions.sh` before collecting evidence to verify the registry and instrumentation are still aligned with the frozen design.

## Playable telemetry packet

The playable presentation probe is opt-in and inactive during ordinary play. Before a controlled empirical session set:
- `FMD_EMPIRICAL_TESTER_ID` to the pseudonymous tester ID;
- `FMD_EMPIRICAL_SESSION_ID` to the session ID;
- `FMD_EMPIRICAL_DEMO_BUILD_ID` when the run is a demo build;
- `FMD_EMPIRICAL_TELEMETRY_PATH` to a writable path for the raw session telemetry snapshot.

The probe automatically timestamps session start, first use of map/world correspondence, and first observed broken objective after an accepted edit. Those are instrumentation facts only. They do **not** prove comprehension, prediction success, or a genuine human `aha`.

Use `EmpiricalTelemetryService.make_e1_observation`, `make_e2_observation`, and `make_e11_observation` only after an observer/test protocol supplies the corresponding human outcome. The service preserves that explicit outcome and does not infer it from clicks or objective state.

## T8-44 reference profiler packet

`ReferenceHardwareProfiler.make_t8_44_row` converts raw microsecond sample families into the exact registry fields for reference-hardware evidence: typical edit median/p95, late-game edit p99, Stability-cycle p95 and sample count. Empty sample families reject instead of producing a partial profile. `profiling_disposition` must identify whether the row is a reference run, a diagnostic/profile run, or another explicit disposition.

Run `GODOT_BIN=<Godot-4.7.1> bash scripts/run_phase12g_instrumentation.sh` to validate the registry, anti-fabrication rules, telemetry schema, and profiler output before collecting sessions.

## Gate execution order

1. E1 map->world comprehension and E2 second-order prediction on naive first-session testers.
2. E3 mature reasoning versus deliberate legal-edit enumeration after rules are known.
3. E4 campaign repetition over D13-D22 and D29-D36.
4. E5 linked-authority comprehension and E6 causal readability on late linked dossiers.
5. E7 full 1280x800/controller/reduced-motion/non-color/no-audio capture + interaction sweep for shippable dossiers.
6. E9 remix distinctness and E10 agent distinctness after relevant mechanics are taught.
7. E11 genuine demo timing using the actual DEMO01-DEMO05 build.
8. T8-44 on Deck-class reference hardware using representative late-game transactions and Stability cycles.
9. E8 marketing expectation when representative store/trailer assets exist.
10. E12 only near release, with current market comparables and near-final build scope.

## Disposition rules

E1 passes only at >=80% eligible naive comprehension within 180 seconds. E2 passes only at >=70% eligible prediction success. E7 requires 100% of the tested shippable-dossier/device-mode rows to complete interaction and pass capture review. T8-44 uses the frozen 8 ms median / 25 ms p95 typical-edit, 50 ms p99 late-game, and 16 ms p95 Stability-cycle targets on reference hardware.

Gates without a frozen numeric threshold require an explicit evidence-backed disposition. A FAIL reopens only the smallest affected content/rule/presentation instance. Missing evidence is PENDING, not PASS and not FAIL.
