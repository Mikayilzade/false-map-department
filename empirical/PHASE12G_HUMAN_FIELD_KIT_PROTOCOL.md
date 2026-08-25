# Phase 12G human field kit — E1-E6 / E9-E11

Purpose: package the existing first-session and mature-human acquisition flows into one integrity-pinned field kit for genuine external sessions. The kit is logistics infrastructure only. Blank/prepared packets are not participants and are not empirical evidence.

## Prepare one acquisition kit

Use exact immutable identifiers for the repository source and the actual builds participants will run:

```bash
python3 scripts/phase12g_human_field_kit.py prepare \
  --source-head <exact-commit-sha> \
  --demo-build-id <exact-demo-build-id> \
  --production-build-id <exact-production-build-id> \
  --first-count 8 \
  --mature-count 6 \
  --output-dir .phase12g-human-field-kit
```

This invokes the existing hardened packet generators for:
- E1 / E2 / E11 naive first-session acquisition;
- E3 / E4 / E5 / E6 / E9 / E10 mature-human acquisition.

The resulting `field-kit-manifest.json` records:
- exact source head;
- exact demo and production build IDs;
- participant/session identities;
- SHA-256 of immutable first-session manifests;
- structural fingerprints for mature scheduling/task identity;
- explicit non-evidence flags.

No human outcome is inferred. No row is appended to `empirical/evidence`.

## Run real sessions

Follow `PHASE12G_FIRST_SESSION_PROTOCOL.md` and `PHASE12G_MATURE_SESSION_PROTOCOL.md` exactly. Do not coach toward authored solutions, inspect known-solution envelopes, or replace a human judgment with telemetry/runtime state.

Observer files are intentionally mutable because genuine observations must be entered there. The field-kit verifier therefore does **not** reject changes to human outcome fields. It does reject changes to immutable acquisition identity such as tester/session IDs, build IDs, first-session manifests, mature task/dossier/method schedules, remix/source pairings, or E10 comparison identities.

## Verify returned kit integrity

Before finalizing/importing returned observations:

```bash
python3 scripts/phase12g_human_field_kit.py verify \
  --kit-dir .phase12g-human-field-kit
```

A successful verify means acquisition identity/build contracts still match the prepared kit. It does **not** mean the human results are correct, sufficient, representative, or passing.

## Finalize and append deliberately

Use the existing first-session/mature finalizers to create local `completed-E*.jsonl` files only after required human fields are genuinely observed. Then dry-run each completed file through:

```bash
python3 scripts/phase12g_collect_completed_rows.py --input <completed-E*.jsonl>
```

Appending remains a separate deliberate action:

```bash
python3 scripts/phase12g_collect_completed_rows.py --input <completed-E*.jsonl> --append
```

After append, run the evidence harness/dashboard. Missing observations stay PENDING. Qualitative gates require explicit evidence-backed disposition; packet preparation or integrity verification can never create PASS/FAIL by itself.

## Scope boundary

This field kit does not cover:
- E7, which already has its automated mixed capture+interaction evidence path;
- E8, which requires representative store/trailer assets and real respondents through its dedicated protocol;
- T8-44, which requires actual Deck-class reference hardware;
- E12, which remains a near-release market/pricing recheck.
