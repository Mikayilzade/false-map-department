# Phase 12G returned-packet ingest contract

This document is acquisition infrastructure only. It does not create, infer, or change any empirical gate outcome.

## Trust boundary

A returned packet is acceptable only when all applicable packet/kit verification succeeds and its exact `source_head` matches the repository checkout used for ingest. Build identity and acquisition channel must survive into the append-only evidence row. Missing evidence remains PENDING.

Before extracting an external acquisition bundle, retain the intended 40-character source SHA through a trusted handoff outside the bundle itself and run the bundled verifier with `--expected-source-head <40_SHA>`. The verifier must reject a self-consistent bundle whose internal `source_head` differs from that independently supplied SHA. Bundle-internal `SOURCE_HEAD.txt` is a transport copy, not an independent source-of-truth for this check.

Immediately after extraction, and before using that tree to generate a human field kit, E8 packet, or T8-44 run, execute the bundle-root `EXTRACTED-SOURCE-VERIFY.py` against the extracted directory with the same independently retained `--expected-source-head <40_SHA>`. This verifier first revalidates the bundle, then compares the complete extracted tree to the verified archive byte-for-byte, including file set and executable-bit identity. It does not trust the extracted directory name or a copied `SOURCE_HEAD.txt` to establish source identity. Run it before acquisition tools create generated files inside the extracted tree.

For human field-kit ingest, the repository tool resolves the current checkout with `git rev-parse --verify HEAD` and requires that SHA to equal both `--expected-source-head` and the returned kit manifest `source_head`. The command-line value is therefore a confirmation, not a substitute for checking out the exact source commit. Ingest from a newer/older checkout must fail closed before any evidence append.

Never copy observations manually into `empirical/evidence/*.jsonl`. Use the gate-specific ingest path so duplicate-return checks, provenance checks, packet integrity checks, dry-run defaults and finalization-receipt checks remain active.

## Immutable packaged-build byte binding

`demo_build_id` and `production_build_id` are labels, not proof of executable/package identity. Before a genuine external Phase 12G observation can be appended to the repository evidence root, bind the exact packaged build file used for acquisition to source SHA + role + build label and re-verify those bytes at ingest time.

Create a non-evidence binding record next to the exact packaged artifact:

`python3 scripts/phase12g_build_artifact_contract.py create --source-head <40_SHA> --role demo|production --build-id <BUILD_LABEL> --artifact <BUILD_FILE> --output <ARTIFACT_RECORD.json>`

At repository ingest, make the exact same artifact bytes and binding record available and set both:
- `FMD_PHASE12G_BUILD_ARTIFACT_RECORD=<ARTIFACT_RECORD.json>`
- `FMD_PHASE12G_BUILD_ARTIFACT_PATH=<BUILD_FILE>`

The provenance layer recomputes SHA-256 and byte size from the supplied build file, verifies source/build/role binding, and persists the artifact digest metadata into staged evidence. The central collector independently re-verifies the same bytes before any append to the real `empirical/evidence` root. Human E1/E2/E11 require the `demo` role; human E3-E6/E9-E10, E8 and T8-44 require `production`.

If immutable packaged build bytes are not available, dry-run/readiness checks may continue but `append_ready` is false for the real evidence root and deliberate append fails closed. Do not invent a digest or treat a source-bound build label as packaged-build proof. Missing build bytes mean the empirical observation is not append-ready and its gate remains PENDING.

The artifact binding record and its digest are integrity/acquisition metadata, not empirical evidence and never imply a gate outcome.

## Human field-kit return — E1-E6, E9-E11

1. Checkout the exact source commit recorded by the returned field kit. If the acquisition tree came from an external bundle archive rather than a Git checkout, it must have passed `EXTRACTED-SOURCE-VERIFY.py` against the independently retained source SHA before field-kit generation.
2. Run the offline verifier on the returned kit before ingest.
3. Finalize every genuinely completed first/mature packet locally with the bundled `FIELD-KIT-FINALIZE.py`. Finalization writes `completed-*.jsonl` plus a packet-local `finalization-receipt.json` that binds the completed-file SHA-256/size to the exact field-kit contract, source SHA, demo/production build IDs and manifest-pinned finalizer hash.
4. Transport the completed rows and their receipt together. Do not edit a finalized `completed-*.jsonl`; if an observation correction is genuinely required, correct the observer packet and rerun the bundled finalizer so a new matching receipt is produced before ingest.
5. Run `python3 scripts/phase12g_field_kit_ingest.py --kit-dir <RETURNED_KIT> --expected-source-head <40_SHA>` without append first. Repository ingest resolves the actual checkout HEAD and rejects a mismatch before verification/collection; it also rejects any completed file that is missing a receipt binding, changed after finalization, bound by multiple receipts, or tied to different source/build/tool identity.
6. Inspect the dry-run result and confirm `repository_checkout_head`, source/build attribution, receipt verification and completed-row counts. For a real repository append, also confirm the exact packaged build artifact/record for the relevant demo or production role is available as described above.
7. Only for genuine reviewed observations, repeat with the ingest tool's explicit `--append` option while the packaged build artifact environment is set.
8. Run `python3 scripts/phase12g_evidence_harness.py` and `python3 scripts/phase12g_gate_dashboard.py` after deliberate append.

The receipt is an integrity/transport binding, not a cryptographic human attestation and not empirical evidence by itself. It detects completed-row changes between local finalization and repository ingest; it does not turn synthetic or unreviewed rows into valid observations.

## Marketing packet return — E8

1. Checkout the exact packet `source_head`; if the acquisition tree came from the external archive, verify that extracted tree first as described above.
2. Keep the immutable five-role asset set and respondent return together.
3. Run `python3 scripts/phase12g_marketing_expectation_ingest.py <RETURNED_PACKET>` in dry-run mode first.
4. Before real append, supply the exact production packaged build artifact + binding record through the build-artifact environment above; append only genuine respondent observations after asset/respondent/source/build/artifact-byte checks pass.
5. Re-run the evidence harness/dashboard.

## Deck-class reference return — T8-44

1. Checkout the exact reference packet `source_head`; if the profiling tree came from the external archive, verify that extracted tree first as described above.
2. Before the reference run, create a structured profile template with `python3 scripts/phase12g_reference_hardware_profile.py template --hardware-id <PSEUDONYMOUS_HW_ID> --output <HARDWARE_PROFILE.json>`. Replace every `FILL_ACTUAL_*` value and `memory_gib=0` with observed device facts, then run `python3 scripts/phase12g_reference_hardware_profile.py validate --profile <HARDWARE_PROFILE.json> --hardware-id <PSEUDONYMOUS_HW_ID>`. This is operator-observed acquisition metadata, not software proof that the machine is physically Deck-class.
3. Require genuine Deck-class reference hardware, Godot 4.7.1, exact production build ID, exact production package bytes and raw timing samples. Run the profiler with the same hardware ID, `FMD_T8_HARDWARE_PROFILE_PATH=<HARDWARE_PROFILE.json>`, `FMD_T8_DISPOSITION=reference_run` and `FMD_T8_REFERENCE_ATTESTATION=actual_deck_class_reference`. The runner rejects a missing/mismatched/non-reference profile before recording the packet.
4. Freeze the exact production package bytes in the packet directory with `phase12g_reference_profile_build_bind.py prepare`, then seal the returned profile packet with `phase12g_reference_profile_build_bind.py seal`. Sealing normalizes and hashes the structured hardware profile and binds that profile hash together with hardware ID, attestation, source SHA, build binding, dossier identity, summary metrics and raw samples. Post-capture hardware-profile substitution must fail verification.
5. Run `python3 scripts/phase12g_reference_profile_ingest.py --packet <RETURNED_PROFILE> --expected-source-head <40_SHA>` in dry-run mode first. Append only when raw samples, recomputed summary, source/build/artifact-byte identity, representative late-game Stability target, structured hardware profile and operator reference-hardware attestation all validate.
6. Re-run the evidence harness/dashboard after deliberate append.

A structured hardware profile improves attribution and prevents silent post-capture hardware relabeling; it still cannot independently prove physical hardware truth. The actual Deck-class condition remains a genuine operator-observed requirement, so no software-generated profile, CI environment or diagnostic run can move T8-44 out of PENDING.

Hosted CI, synthetic timings, blank kits, generated packets, finalization receipts, build labels without packaged bytes, build-artifact binding records by themselves, dry-run output, bundle verification, extracted-source verification and acquisition-readiness audits are not empirical evidence and must not change a PENDING gate disposition.
