# FALSE MAP DEPARTMENT — IMPLEMENTATION STATUS

Last updated: 2026-08-29
Repository: `Mikayilzade/false-map-department`

## Master state
- Design frozen: **YES**
- Fresh-session design audit: **PASS — 32/32**
- Design migration: **COMPLETE / VERIFIED**
- Final-freeze integrity: **VERIFIED**
- 12A Technical Bootstrap: **COMPLETE**
- 12B Vertical Slice: **COMPLETE**
- 12C Core Systems: **COMPLETE**
- 12D Content Population: **COMPLETE**
- 12E UX / Accessibility / Controller / Deck: **COMPLETE**
- 12F Adversarial QA: **COMPLETE — real-Godot runtime-green**
- 12G Empirical Gates: **IN PROGRESS — E7 exhaustive 285/285 PASS; remaining genuine human/market/reference-hardware evidence PENDING**
- 12H Release Candidate: **NO**
- IMPLEMENTATION COMPLETE: **NO**

## Latest owner-playtest build preparation — 2026-08-29

### Phase / scope
**Phase 12G support / owner smoke-playtest packaging — NOT Phase 12H and not empirical evidence**

### Completed
- Changed the ordinary project launch to route directly to the existing production demo scene with `DEMO01` as its default, while preserving the explicit environment-driven Phase 12G dossier routes. The legacy/bootstrap shell is no longer the no-environment launch target.
- Added startup markers emitted only after the production entry route is chosen and DEMO01 has successfully initialized through `ProductionPlaytestController`; these make an exported-artifact smoke distinguish production gameplay from the legacy/debug shell.
- Added a Godot `Windows Desktop` x86_64 release export preset. It creates one embedded-PCK executable at `build/windows/FalseMapDepartment.exe`.
- Added `scripts/build_windows_playtest.sh`, which obtains and checksum-verifies the pinned Godot 4.7.1 editor and official export templates, exports the Windows executable, and creates the portable `build/FalseMapDepartment-Windows-x86_64-owner-playtest.zip` package.
- Added `scripts/smoke_windows_playtest.sh`, which launches the actual exported PE under Wine in headless display mode and requires both the production-route and DEMO01-ready markers while rejecting Godot script/load/initialization errors.
- Added the notification-safe, PR-path-scoped `Windows Owner Playtest Build` workflow on native `windows-latest`. It checks out the exact PR head rather than GitHub's synthetic merge commit, verifies official Godot 4.7.1 editor/template SHA-512 hashes, exports and launches the actual Windows PE, packages the standalone executable, and uploads both the runnable owner ZIP and exact-head smoke logs. Concurrency cancellation prevents obsolete runs from creating CI noise.
- No gameplay, content, canonical rule, Phase 12G evidence, or gate disposition changed.

### Validation and concrete environment blocker
- Static entrypoint/export/build contracts pass locally.
- A real Windows build was attempted with `scripts/build_windows_playtest.sh`, but this container's outbound proxy rejected the official GitHub release download with HTTP 403 before the pinned editor/export templates could be acquired. There was no preinstalled Godot 4.7.1 or export-template cache. Therefore **no Windows artifact was produced and no artifact-launch success is claimed**.
- Native Windows PR validation is configured but its exact-head GitHub Actions result is still pending. Do not replace this line with PASS until the workflow run has completed successfully and its run ID, tested head SHA, smoke result and uploaded artifact have been inspected.
- Expected artifact paths after a successful build remain `build/windows/FalseMapDepartment.exe` and `build/FalseMapDepartment-Windows-x86_64-owner-playtest.zip`; neither path is evidence until the build and Wine smoke both pass.

### Canonical / phase impact
- **No canonical contradiction discovered.** Frozen gameplay is unchanged.
- This work is owner smoke/playtest build preparation only. It does not start Phase 12H, does not append empirical observations, and does not change the 12G dashboard.

## NEXT ACTION
Inspect the `Windows Owner Playtest Build` run triggered for the exact PR head. If it fails, repair only the concrete build/runtime failure and rerun once coherently. When it passes, record its exact head SHA, run ID/result, `FalseMapDepartment-Windows-x86_64-owner-playtest` artifact name and native-PE smoke result here. Mikayil's next action is then: open that successful exact-head Actions run, download the `FalseMapDepartment-Windows-x86_64-owner-playtest` artifact, extract the inner `FalseMapDepartment-Windows-x86_64-owner-playtest.zip`, extract that ZIP, and double-click `FalseMapDepartment.exe`; confirm DEMO01 appears first and manually play through `DEMO01 -> DEMO02 -> DEMO03 -> DEMO04 -> DEMO05`. Record this as owner smoke feedback only, not Phase 12G evidence, and keep Phase 12H closed.

## Previous autonomous run — 2026-08-27

### Phase / subphase
**12G Empirical Design Gates / T8-44 reference-hardware profile attribution + sealed-capture binding — EXACT-HEAD PASS**

### Progress saved this run
- Re-read `IMPLEMENTATION_START_HERE.md`, `CI_NOTIFICATION_POLICY.md`, this status file, `GAME2_PHASE11_FINAL_FREEZE.md`, `empirical/PHASE12G_PROTOCOL.md`, `empirical/phase12g_gate_registry.json`, and the T8-44 reference profile / representative-target / build-binding / ingest / external-bundle tooling before changing the acquisition path.
- Resumed exactly from the prior `NEXT ACTION` and found one distinct T8-44 acquisition-integrity gap: a real packet could carry only a free-form `hardware_id` plus the literal `actual_deck_class_reference` attestation. Existing sealing bound those strings, build bytes, source SHA, target and raw samples, but did not preserve a structured operator-observed hardware profile. That left hardware attribution too weak even though software still cannot independently prove physical hardware truth.
- Added `scripts/phase12g_reference_hardware_profile.py` with a versioned structured profile contract covering pseudonymous hardware ID, hardware class, device model, processor/APU, memory, OS, Godot version and explicit operator attestation. It provides template + validation commands and explicitly records that the profile is operator-observed metadata, **not software proof** of physical hardware.
- `tests/phase12g_reference_profile_runner.gd` now requires `FMD_T8_HARDWARE_PROFILE_PATH` for `reference_run`, rejects missing/mismatched/non-reference profile identity before timing capture, and writes the supplied structured profile into the non-evidence packet.
- `phase12g_reference_profile_build_bind.py` now upgrades sealed T8 packets to packet v3, normalizes/hashes the hardware profile and includes that snapshot/hash inside the sealed capture identity together with hardware ID, attestation, exact source, exact production build-byte binding, representative dossier identity, summary metrics and raw samples. Post-capture profile relabeling is therefore independently detectable.
- `phase12g_reference_profile_ingest.py` requires packet v3 for real ingest, persists the verified structured hardware profile into the staged evidence row, and explicitly reports `physical_hardware_truth_inferred=false`.
- Extended the existing synthetic T8 acquisition audit to attack hardware ID/profile/attestation/dossier rebinding, missing/non-reference profile claims and post-session package substitution. Legacy synthetic audit/diagnostic fixtures remain usable only through an explicit non-reference synthetic profile fallback and never become admissible evidence.
- Updated the exact-source external acquisition bundle and return-ingest handoff so the structured hardware profile is required archive content and the Deck operator path explains template -> observed values -> validation -> reference capture -> exact package-byte binding -> sealing -> dry-run ingest -> deliberate append.
- No gameplay/content/canonical rule, empirical threshold, genuine observation, or gate disposition was changed.

### Files / systems changed
- `scripts/phase12g_reference_hardware_profile.py`
- `tests/phase12g_reference_profile_runner.gd`
- `scripts/phase12g_reference_profile_build_bind.py`
- `scripts/phase12g_reference_profile_ingest.py`
- `scripts/phase12g_reference_profile_audit.py`
- `scripts/phase12g_external_acquisition_bundle.py`
- `empirical/PHASE12G_RETURN_INGEST.md`
- `IMPLEMENTATION_STATUS.md`

### Validation / factual exact-head evidence
- Final implementation head: `95420e423af11244bdebcd93029fd42614b1b36c`.
- Notification-safe automatic run: **33059821246 — completed / success** for exact head `95420e423af11244bdebcd93029fd42614b1b36c`.
- Committed evidence commit: `1bd0dd3f593a5dc3e7ce2507fba6f12a321b353f` (`Record automatic Godot baseline: PASS [skip ci]`).
- Committed run metadata explicitly records `head_sha=95420e423af11244bdebcd93029fd42614b1b36c`.
- Aggregate result: **PASS** (`runtime_rc=0`, `phase12g_instrumentation_rc=0`, `ci_policy_rc=0`, `bootstrap_preflight_rc=0`, `phase12a_contract_rc=0`, `fetch_godot_rc=0`).
- T8-44 acquisition audit: **PASS** — exact checkout/source, raw-sample consistency, exact production package bytes, structured hardware profile + attestation sealed into capture identity, post-capture hardware/profile/dossier substitution rejection, wrong-role/unsealed/post-session package-substitution rejection; audit data never touched empirical evidence.
- External acquisition bundle audit: **PASS** — exact-source v4 archive, independent source handoff, extracted-tree byte verification and zero evidence/disposition mutation remain intact with the T8 hardware-profile helper included in the required source archive.
- Current evidence harness remains **1 PASS / 12 PENDING / 0 FAIL / 0 BLOCKED**. E7 is still the sole empirical PASS at 285/285; T8-44 remains PENDING with zero Deck-class reference-hardware rows.
- Existing 12A-12F runtime gates, E7 evidence, human field-kit/E8 acquisition integrity, representative D38/D39 target binding, evidence destination/provenance checks and Phase-12G anti-fabrication baseline remained green in the same exact-head run.

### Current empirical-gate state
- **E7: PASS — 285/285 exhaustive frozen matrix.**
- **E1, E2, E3, E4, E5, E6, E8, E9, E10, E11, E12, T8-44: PENDING.**
- E1/E2/E11 require genuine first-session human observations.
- E3-E6/E9-E10 require genuine mature-human observations.
- E8 requires genuine representative five-role media/respondent observations.
- T8-44 requires an actual Deck-class reference-hardware run; hosted CI and diagnostic timings remain non-evidence.
- E12 remains intentionally near-release and must not be dispositioned early.
- Synthetic fixtures, audits, hashes, structured hardware profiles, readiness output, acquisition packets, build bindings and finalization receipts are acquisition/integrity metadata, not empirical outcomes.

### Failures / blockers
- **Autonomous implementation is now externally evidence-blocked for the remaining 12G dispositions.**
- No further distinct autonomous acquisition-integrity defect is currently identified without re-auditing already regression-covered mutation classes or fabricating observations.
- Software cannot prove real human identity/naivety/comprehension/reasoning/perception/timing/completion, respondent representativeness, or physical Deck-class hardware truth. Those are genuine external observations.
- 12H must remain closed.

### Canonical / empirical-gate impact
- **No canonical contradiction discovered.**
- T8-44 remains **PENDING**. The new structured hardware profile proves only stable acquisition attribution and resistance to silent post-capture relabeling; it does not prove the physical machine is genuinely Deck-class.
- No synthetic or diagnostic T8 row was appended to canonical evidence.
- All other unobserved empirical gates remain PENDING.

## Previous NEXT ACTION (superseded only for immediate build handoff)
Phase 12G now requires genuine external evidence before further autonomous implementation can legitimately advance gate disposition.

1. **T8-44:** on actual Deck-class reference hardware, use the exact-source external acquisition bundle; verify/extract the source, create and validate `phase12g_reference_hardware_profile.py` profile with observed device facts, run Godot 4.7.1 with `FMD_T8_DISPOSITION=reference_run`, `FMD_T8_REFERENCE_ATTESTATION=actual_deck_class_reference` and `FMD_T8_HARDWARE_PROFILE_PATH`, bind the exact production package bytes, seal the returned packet, then dry-run ingest before any deliberate append.
2. **E1-E6/E9-E11:** collect genuine first-session/mature human field-kit observations using the existing verified source/build-bound kits.
3. **E8:** collect genuine respondent observations against the required immutable representative five-role media set using the existing source/build/asset/respondent/finalization-bound packet path.
4. **E12:** leave pending until the product is genuinely near release.
5. When genuine returned observations exist, resume autonomous work with dry-run ingest, append only reviewed genuine rows, rerun the evidence harness/dashboard, and disposition each gate strictly from recorded evidence.
6. Keep E7 frozen at **285/285 PASS** and do not start **12H** until every remaining 12G gate has a genuine evidence-backed disposition or explicit release blocker.
