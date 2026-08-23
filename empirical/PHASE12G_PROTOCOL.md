# Phase 12G empirical evidence protocol

This phase must separate implementation facts from human, hardware, and market evidence. No gate may be marked PASS because an automated test merely proves the UI or telemetry exists.

## Evidence storage

Raw observations are append-only JSON Lines files under `empirical/evidence/<GATE_ID>.jsonl`. Each row must contain every field declared by `empirical/phase12g_gate_registry.json`. Tester/respondent identifiers should be pseudonymous and contain no unnecessary personal data.

Run `python3 scripts/phase12g_evidence_harness.py` to validate rows and produce a current summary. Run `bash scripts/run_phase12g_preconditions.sh` before collecting evidence to verify the registry is still aligned with the frozen design.

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
