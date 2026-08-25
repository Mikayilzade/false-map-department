# Phase 12G E8 marketing-expectation protocol

E8 asks whether representative marketing material creates the correct expectation for the implemented game. This is a market/human evidence gate. Automated checks may prepare and validate an asset packet, but they cannot determine what a respondent expected.

## Evidence boundary

- A generated asset manifest is **not evidence**.
- A blank respondent packet is **not evidence**.
- A completion receipt is **integrity metadata, not evidence**: it proves which finalized response bytes were transported, not whether those responses imply PASS/FAIL.
- Asset hashes prove only which files were shown.
- `representative_asset_attestation=true` is an operator assertion that the packet is intended to represent the current product presentation; it is not a respondent outcome and does not pass E8.
- `source_head` pins the exact repository commit represented by the packet; it does not prove the assets are representative or that respondents understood them.
- E8 remains PENDING until real respondents see the exact frozen asset version and the required fields are deliberately recorded and appended through the normal evidence harness.

## Required representative asset set

Do not run E8 on placeholder-only copy or a single debug screenshot. One exact asset version must contain all five roles:

1. `store_key_art` — key/capsule-style still that sets the product tone without inventing features.
2. `gameplay_map_world` — readable real gameplay showing the authoritative map and derived world correspondence.
3. `gameplay_consequence` — real gameplay after an accepted edit where a bounded consequence/requirement change is visible.
4. `late_game_linked` — real late-game linked-authority presentation showing escalation beyond the tutorial without exceeding the two-surface UI contract.
5. `trailer` — representative motion asset showing the same implemented interaction fantasy rather than a concept-only animatic.

The packet tool rejects missing roles, empty files and unsupported media extensions. Every accepted file is copied into `packet/assets/` under a role-stable filename and SHA-256 pinned into `asset-set.json`. `status` and `finalize` re-hash those packet-owned files and reject any mutation, deletion, replacement or manifest drift. **Show respondents only the frozen files under `packet/assets/`**; the original source paths used during `prepare` are not the evidence-bearing presentation set after preparation.

## Capability-safe claims

The default packet copy is limited to frozen/implemented product facts:

- premium single-player systemic puzzle;
- executable official-map -> world causality;
- snapped authored road/bridge/border/waterway/landmark/restricted-zone edits;
- explicitly **not a freeform map builder**;
- 40 authored campaign dossiers + 12 bounded remix cases as the frozen 1.0 content scope;
- required mouse+keyboard, keyboard-only and controller-only paths with 1280x800 Deck target presentation.

Do not add claims for multiplayer, city-building, freeform editing, procedural campaign, UGC/Workshop, endless play or live-service features. If custom claims are supplied, they must still include the explicit non-freeform-builder statement and remain within implemented/frozen capability.

## Preparing a packet

Use real current assets, a current build identifier and the exact 40-character Git commit SHA represented by them:

```bash
python3 scripts/phase12g_marketing_expectation_packet.py prepare \
  --asset-version STORE-V1 \
  --build-id <exact-build-id> \
  --source-head <40-character-git-commit-sha> \
  --representative-attestation \
  --asset store_key_art=/path/key.png \
  --asset gameplay_map_world=/path/map-world.png \
  --asset gameplay_consequence=/path/consequence.png \
  --asset late_game_linked=/path/linked.png \
  --asset trailer=/path/trailer.webm \
  --respondents 5 \
  --output /path/e8-packet
```

Preparation refuses to overwrite an existing packet. This avoids silently replacing a packet after respondents have started seeing it. `respondents.json` is created with `expected_play_category`, `freeform_builder_expectation` and `notes` all `null`. The tool never infers these values from the asset files, claims, build metadata, source head or respondent ID.

Before the first respondent and again before each resumed collection session, run:

```bash
python3 scripts/phase12g_marketing_expectation_packet.py status --packet /path/e8-packet
```

Proceed only when `frozen_assets_verified=true`. `INVALID_PACKET` means the shown asset set can no longer be tied to the prepared hashes; prepare a new asset version rather than repairing the old packet in place.

## Respondent procedure

Show every respondent the same exact files from `packet/assets/` without explaining the intended category first. After exposure, record:

- `expected_play_category`: the respondent's own concise description of what they think the game is/does;
- `freeform_builder_expectation`: boolean answering whether they expect a broad freeform map/city-building/editor experience rather than authored systemic puzzles;
- `notes`: enough observer context to interpret the answer, including ambiguity or mismatch.

Do not coach the answer toward “puzzle,” “systemic,” or “not a builder.” If a respondent expected a builder/editor, record that as observed rather than correcting the row.

## Finalization, transport integrity and evidence append

After all prepared rows contain genuinely observed answers:

```bash
python3 scripts/phase12g_marketing_expectation_packet.py status --packet /path/e8-packet
python3 scripts/phase12g_marketing_expectation_packet.py finalize --packet /path/e8-packet
python3 scripts/phase12g_marketing_expectation_packet.py status --packet /path/e8-packet
```

`finalize` verifies the pinned manifest **and every frozen asset file** before writing local `completed-E8.jsonl`. It also writes `completion-receipt.json`, whose SHA-256/size records bind the finalized `asset-set.json`, completed `respondents.json`, and `completed-E8.jsonl` to the exact `asset_version`, `build_id`, and `source_head`. A finalized packet is write-once: rerunning `finalize` is rejected rather than silently replacing an already finalized response set. After finalization, `status` must report `FINALIZED` with `completion_receipt_verified=true`; any mutation of either respondent source rows or completed rows becomes `INVALID_PACKET`.

This closes a transport-integrity gap: comparing `respondents.json` with `completed-E8.jsonl` alone is insufficient because both files could otherwise be changed together after finalization. Repository ingest therefore requires and verifies the completion receipt before it accepts the rows. If a genuine correction is needed after finalization, prepare a new asset/response version rather than editing a finalized packet in place.

Finalization still does **not** append repository evidence automatically. Deliberately review the rows, then use the source-pinned repository ingest path (dry-run first, explicit `--append` only after review):

```bash
python3 scripts/phase12g_marketing_expectation_ingest.py \
  --packet /path/e8-packet \
  --expected-source-head <the packet source_head>

python3 scripts/phase12g_marketing_expectation_ingest.py \
  --packet /path/e8-packet \
  --expected-source-head <the packet source_head> \
  --append
```

The ingest re-verifies immutable assets, exact source/build provenance, the finalization receipt, respondent/completed-row equality, duplicate/idempotency rules, and then delegates to the normal append-only evidence collector. It does not infer a market outcome or gate disposition.

## Explicit interpretation and disposition after ingest

E8 has no frozen numeric threshold, so response rows alone never become PASS/FAIL automatically. After real E8 rows have been appended and deliberately reviewed, record the interpretation explicitly with the qualitative-disposition recorder:

```bash
python3 scripts/phase12g_qualitative_disposition.py E8 \
  --status PASS \
  --rationale "<evidence-backed interpretation of what respondents expected>" \
  --evidence-ref "<reviewable packet/evidence reference>" \
  --reviewer-id "<pseudonymous reviewer/operator id>"
```

The recorder refuses empty evidence and threshold-evaluated gates. It writes `empirical/evidence/dispositions.json` using schema `fmd.phase12g.qualitative-dispositions.v2` and binds the interpretation to the exact current `E8.jsonl` SHA-256 and row count. It is write-once by default; if later evidence is appended, the existing disposition becomes stale and the Phase 12G precondition path rejects it before the evidence harness/dashboard can consume it. Re-review the complete new evidence set and use `--replace` only for a deliberate replacement.

Run the full Phase 12G preconditions after recording or replacing a qualitative disposition. `phase12g_qualitative_disposition_integrity.py` rejects unbound, malformed, threshold-gate, or stale qualitative dispositions. This integrity check does **not** decide the outcome and never derives a market interpretation from response values; the status/rationale/reviewer are explicit inputs from the actual review.

E8 remains **PENDING** until genuine representative media exist, real respondents have supplied evidence rows, and an explicit evidence-backed interpretation has been recorded for those exact evidence bytes. Missing representative assets or respondents means PENDING, not FAIL and not PASS.
