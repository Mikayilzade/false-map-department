# FALSE MAP DEPARTMENT — MIGRATION MANIFEST

Prepared: 2026-08-19
Source: `Mikayilzade/gpt-game-autonomy`
Destination: `Mikayilzade/false-map-department`
Status: **VERIFYING DIRECT MIGRATION**

## Required migrated package
- `GAME2_PHASE11_FINAL_FREEZE.md`
- `GAME2_ADVERSARIAL_REVIEW.md`
- `GAME2_MECHANICAL_ARCHITECTURE.md`
- `GAME2_CONTENT_ARCHITECTURE.md`
- `GAME2_UX_PRESENTATION_ARCHITECTURE.md`
- `GAME2_ECONOMY_COMMERCIAL.md`
- `GAME2_TECHNICAL_SPEC.md`
- `GAME2_PRODUCT_THESIS.md`
- `GAME2_WHOLE_GAME_SIMULATION.md`
- `GAME2_RESEARCH.md`
- `GAME2_TOURNAMENT.md`
- `GAME2_TOURNAMENT_RUN4.md`
- `GAME2_TOURNAMENT_RUN5.md`
- `IMPLEMENTATION_START_HERE.md`
- `IMPLEMENTATION_STATUS.md`
- `CI_NOTIFICATION_POLICY.md`

## Integrity requirement
The highest implementation-sensitive authority, `GAME2_PHASE11_FINAL_FREEZE.md`, must match source blob SHA `fc988f8eaa031507f5ae84d6e60316356bc6cb2a`.

Canonical design files are transferred from source blobs without reinterpretation. Destination implementation handoff/status are intentionally destination-specific and include the CI/email-noise guardrail.

## Cleanup gate
Do not remove Game #002 files from the factory until:
1. the full package above is visible on destination `main`;
2. the final-freeze SHA is verified;
3. implementation handoff is self-contained;
4. implementation status points to Phase 12A;
5. factory `GAME_INDEX.md` is updated.
