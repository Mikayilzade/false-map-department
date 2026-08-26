# Phase 12G returned-packet ingest contract

This document is acquisition infrastructure only. It does not create, infer, or change any empirical gate outcome.

## Trust boundary

A returned packet is acceptable only when all applicable packet/kit verification succeeds and its exact `source_head` matches the repository checkout used for ingest. Build identity and acquisition channel must survive into the append-only evidence row. Missing evidence remains PENDING.

Before extracting an external acquisition bundle, retain the intended 40-character source SHA through a trusted handoff outside the bundle itself and run the bundled verifier with `--expected-source-head <40_SHA>`. The verifier must reject a self-consistent bundle whose internal `source_head` differs from that independently supplied SHA. Bundle-internal `SOURCE_HEAD.txt` is a transport copy, not an independent source-of-truth for this check.

Immediately after extraction, and before using that tree to generate a human field kit, E8 packet, or T8-44 run, execute the bundle-root `EXTRACTED-SOURCE-VERIFY.py` against the extracted directory with the same independently retained `--expected-source-head <40_SHA>`. This verifier first revalidates the bundle, then compares the complete extracted tree to the verified archive byte-for-byte, including file set and executable-bit identity. It does not trust the extracted directory name or a copied `SOURCE_HEAD.txt` to establish source identity. Run it before acquisition tools create generated files inside the extracted tree.

For human field-kit ingest, the repository tool resolves the current checkout with `git rev-parse --verify HEAD` and requires that SHA to equal both `--expected-source-head` and the returned kit manifest `source_head`. The command-line value is therefore a confirmation, not a substitute for checking out the exact source commit. Ingest from a newer/older checkout must fail closed before any evidence append.

Never copy observations manually into `empirical/evidence/*.jsonl`. Use the gate-specific ingest path so duplicate-return checks, provenance checks, packet integrity checks, dry-run defaults and finalization-receipt checks remain active.

## Human field-kit return — E1-E6, E9-E11

1. Checkout the exact source commit recorded by the returned field kit. If the acquisition tree came from an external bundle archive rather than a Git checkout, it must have passed `EXTRACTED-SOURCE-VERIFY.py` against the independently retained source SHA before field-kit generation.
2. Run the offline verifier on the returned kit before ingest.
3. Finalize every genuinely completed first/mature packet locally with the bundled `FIELD-KIT-FINALIZE.py`. Finalization writes `completed-*.jsonl` plus a packet-local `finalization-receipt.json` that binds the completed-file SHA-256/size to the exact field-kit contract, source SHA, demo/production build IDs and manifest-pinned finalizer hash.
4. Transport the completed rows and their receipt together. Do not edit a finalized `completed-*.jsonl`; if an observation correction is genuinely required, correct the observer packet and rerun the bundled finalizer so a new matching receipt is produced before ingest.
5. Run `python3 scripts/phase12g_field_kit_ingest.py --kit-dir <RETURNED_KIT> --expected-source-head <40_SHA>` without append first. Repository ingest resolves the actual checkout HEAD and rejects a mismatch before verification/collection; it also rejects any completed file that is missing a receipt binding, changed after finalization, bound by multiple receipts, or tied to different source/build/tool identity.
6. Inspect the dry-run result and confirm `repository_checkout_head`, source/build attribution, receipt verification and completed-row counts.
7. Only for genuine reviewed observations, repeat with the ingest tool's explicit `--append` option.
8. Run `python3 scripts/phase12g_evidence_harness.py` and `python3 scripts/phase12g_gate_dashboard.py` after deliberate append.

The receipt is an integrity/transport binding, not a cryptographic human attestation and not empirical evidence by itself. It detects completed-row changes between local finalization and repository ingest; it does not turn synthetic or unreviewed rows into valid observations.

## Marketing packet return — E8

1. Checkout the exact packet `source_head`; if the acquisition tree came from the external archive, verify that extracted tree first as described above.
2. Keep the immutable five-role asset set and respondent return together.
3. Run `python3 scripts/phase12g_marketing_expectation_ingest.py <RETURNED_PACKET>` in dry-run mode first.
4. Append only genuine respondent observations after asset/respondent/source/build checks pass.
5. Re-run the evidence harness/dashboard.

## Deck-class reference return — T8-44

1. Checkout the exact reference packet `source_head`; if the profiling tree came from the external archive, verify that extracted tree first as described above.
2. Require actual Deck-class hardware attestation, Godot 4.7.1, exact build ID and raw timing samples.
3. Run `python3 scripts/phase12g_reference_profile_ingest.py <RETURNED_PROFILE>` in dry-run mode first.
4. Append only when raw samples, recomputed summary, source/build identity and reference-hardware attestation all validate.
5. Re-run the evidence harness/dashboard.

Hosted CI, synthetic timings, blank kits, generated packets, finalization receipts, dry-run output, bundle verification, extracted-source verification and acquisition-readiness audits are not empirical evidence and must not change a PENDING gate disposition.
