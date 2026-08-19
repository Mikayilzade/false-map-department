# False Map Department

**Design status:** `DESIGN COMPLETE = YES` / specification frozen.
**Implementation status:** not started; Phase 12A Technical Bootstrap queued.

This repository is the complete implementation home for False Map Department.

## New implementation chat — read first
1. `IMPLEMENTATION_START_HERE.md`
2. `CI_NOTIFICATION_POLICY.md`
3. `IMPLEMENTATION_STATUS.md`
4. `GAME2_PHASE11_FINAL_FREEZE.md`
5. the canonical design files named by the final freeze/handoff.

Highest implementation-sensitive gameplay authority: `GAME2_PHASE11_FINAL_FREEZE.md`.

The implementation chat should resume exactly from `NEXT ACTION` in `IMPLEMENTATION_STATUS.md`, work in small verifiable increments, test before committing, and update status after every substantial run.

Do not casually redesign gameplay during implementation. A real contradiction must be recorded and reconciled into canonical design before behavior changes.

## CI / notification rule
Do not create unstable push-triggered GitHub Actions that repeatedly fail. During bootstrap/early vertical slice, run tests locally/headlessly where possible; if remote CI is needed before the baseline is green, keep it manual (`workflow_dispatch`). Enable automatic push/PR CI only once the baseline is consistently passing. See `CI_NOTIFICATION_POLICY.md`.
