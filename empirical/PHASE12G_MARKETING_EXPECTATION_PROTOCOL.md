# Phase 12G E8 marketing-expectation protocol

E8 asks whether representative marketing material creates the correct expectation for the implemented game. This is a market/human evidence gate. Automated checks may prepare and validate an asset packet, but they cannot determine what a respondent expected.

## Evidence boundary

- A generated asset manifest is **not evidence**.
- A blank respondent packet is **not evidence**.
- Asset hashes prove only which files were shown.
- `representative_asset_attestation=true` is an operator assertion that the packet is intended to represent the current product presentation; it is not a respondent outcome and does not pass E8.
- E8 remains PENDING until real respondents see the exact hashed asset version and the required fields are deliberately recorded and appended through the normal evidence harness.

## Required representative asset set

Do not run E8 on placeholder-only copy or a single debug screenshot. One exact asset version must contain all five roles:

1. `store_key_art` — key/capsule-style still that sets the product tone without inventing features.
2. `gameplay_map_world` — readable real gameplay showing the authoritative map and derived world correspondence.
3. `gameplay_consequence` — real gameplay after an accepted edit where a bounded consequence/requirement change is visible.
4. `late_game_linked` — real late-game linked-authority presentation showing escalation beyond the tutorial without exceeding the two-surface UI contract.
5. `trailer` — representative motion asset showing the same implemented interaction fantasy rather than a concept-only animatic.

The packet tool rejects missing roles, empty files and unsupported media extensions. Every accepted file is SHA-256 pinned into `asset-set.json` so the respondent answers can be tied to one exact asset version.

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

Use real current assets and a current build identifier:

```bash
python3 scripts/phase12g_marketing_expectation_packet.py prepare \
  --asset-version STORE-V1 \
  --build-id <exact-build-or-commit-id> \
  --representative-attestation \
  --asset store_key_art=/path/key.png \
  --asset gameplay_map_world=/path/map-world.png \
  --asset gameplay_consequence=/path/consequence.png \
  --asset late_game_linked=/path/linked.png \
  --asset trailer=/path/trailer.webm \
  --respondents 5 \
  --output /path/e8-packet
```

`respondents.json` is created with `expected_play_category`, `freeform_builder_expectation` and `notes` all `null`. The tool never infers these values from the asset files, claims, build metadata or respondent ID.

## Respondent procedure

Show every respondent the same exact asset version without explaining the intended category first. After exposure, record:

- `expected_play_category`: the respondent's own concise description of what they think the game is/does;
- `freeform_builder_expectation`: boolean answering whether they expect a broad freeform map/city-building/editor experience rather than authored systemic puzzles;
- `notes`: enough observer context to interpret the answer, including ambiguity or mismatch.

Do not coach the answer toward “puzzle,” “systemic,” or “not a builder.” If a respondent expected a builder/editor, record that as observed rather than correcting the row.

## Finalization and evidence append

After all prepared rows contain genuinely observed answers:

```bash
python3 scripts/phase12g_marketing_expectation_packet.py status --packet /path/e8-packet
python3 scripts/phase12g_marketing_expectation_packet.py finalize --packet /path/e8-packet
```

`finalize` verifies that the pinned asset manifest has not changed and writes local `completed-E8.jsonl`. It still does **not** append repository evidence automatically. Deliberately review the rows, then append valid observations to `empirical/evidence/E8.jsonl` using the repository's controlled evidence workflow and rerun the evidence harness/dashboard.

E8 has no frozen numeric threshold. Its PASS/FAIL/BLOCKED disposition therefore requires an explicit evidence-backed interpretation after real responses exist. Missing representative assets or respondents means **PENDING**, not FAIL and not PASS.
