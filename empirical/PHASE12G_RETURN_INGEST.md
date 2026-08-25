# Phase 12G returned-packet ingest contract

This document is acquisition infrastructure only. It does not create, infer, or change any empirical gate outcome.

## Trust boundary

A returned packet is acceptable only when all applicable packet/kit verification succeeds and its exact `source_head` matches the repository checkout used for ingest. Build identity and acquisition channel must survive into the append-only evidence row. Missing evidence remains PENDING.

Never copy observations manually into `empirical/evidence/*.jsonl`. Use the gate-specific ingest path so duplicate-return checks, provenance checks, packet integrity checks and dry-run defaults remain active.

## Human field-kit return — E1-E6, E9-E11

1. Checkout the exact source commit recorded by the returned field kit.
2. Run the offline verifier on the returned kit before ingest.
3. Run `python3 scripts/phase12g_field_kit_ingest.py <RETURNED_KIT>` without append first.
4. Inspect the dry-run result and confirm source/build attribution and completed-row counts.
5. Only for genuine reviewed observations, repeat with the ingest tool's explicit append option.
6. Run `python3 scripts/phase12g_evidence_harness.py` and `python3 scripts/phase12g_gate_dashboard.py` after deliberate append.

## Marketing packet return — E8

1. Checkout the exact packet `source_head`.
2. Keep the immutable five-role asset set and respondent return together.
3. Run `python3 scripts/phase12g_marketing_expectation_ingest.py <RETURNED_PACKET>` in dry-run mode first.
4. Append only genuine respondent observations after asset/respondent/source/build checks pass.
5. Re-run the evidence harness/dashboard.

## Deck-class reference return — T8-44

1. Checkout the exact reference packet `source_head`.
2. Require actual Deck-class hardware attestation, Godot 4.7.1, exact build ID and raw timing samples.
3. Run `python3 scripts/phase12g_reference_profile_ingest.py <RETURNED_PROFILE>` in dry-run mode first.
4. Append only when raw samples, recomputed summary, source/build identity and reference-hardware attestation all validate.
5. Re-run the evidence harness/dashboard.

Hosted CI, synthetic timings, blank kits, generated packets, dry-run output, bundle verification and acquisition-readiness audits are not empirical evidence and must not change a PENDING gate disposition.
