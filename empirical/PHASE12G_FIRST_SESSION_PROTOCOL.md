# Phase 12G first-session protocol — E1 / E2 / E11

Purpose: collect representative **human** observations from the real production DEMO01-DEMO05 build. Automated runtime facts are not human evidence.

## Tester eligibility

- Prefer a player who has not read the design docs, solution envelopes, repo tests or authored solutions.
- Use a pseudonymous `tester_id`; do not store name/email in empirical evidence.
- Record `naive=true` only when the tester is genuinely unfamiliar with the game rules before the session.

## Prepare and launch

For one tester:

```bash
python3 scripts/phase12g_first_session_operator.py prepare \
  --tester-id T001 --session-id S001

python3 scripts/phase12g_first_session_operator.py launch \
  --session-dir .phase12g-first-sessions/S001 \
  --godot /path/to/godot
```

For a planned representative batch, create blank packets in one deliberate step instead of hand-copying session IDs:

```bash
python3 scripts/phase12g_first_session_batch.py prepare \
  --count 8 --tester-prefix NAIVE-T --session-prefix FIRST-S \
  --build-id <exact-demo-build-id>

python3 scripts/phase12g_first_session_batch.py status \
  --manifest .phase12g-first-sessions/batch-manifest.json
```

The batch helper only prepares blank per-tester packets and reports readiness states (`PREPARED`, `AWAITING_OBSERVER`, `READY_TO_FINALIZE`, `FINALIZED_LOCAL`). It never fills observer outcomes and never appends repository evidence. A planned packet is not a participant and does not count toward sample adequacy until a real session is observed and deliberately appended.

The launcher always starts `DEMO01` and writes raw telemetry to the session directory. Raw telemetry records timing facts such as correspondence use, the first detected broken requirement and DEMO05 completion. It **never** decides comprehension, prediction success or human “aha”.

## Observer procedure

Do not coach the solution. The tester should operate the normal production UI.

### E1 — map -> world comprehension

Within the first three minutes, at a natural pause after the tester has seen the map and world react, ask once:

> “In your own words, what are you changing, and why does the world change?”

Mark `e1_success=true` only if the answer communicates the causal direction: the player edits authoritative/official map facts and the world is derived from those facts. Exact wording is not required. Record the elapsed second when this understanding was demonstrated. If it was not demonstrated, mark success false and record the elapsed second of the assessment.

### E2 — second-order prediction

In DEMO02, **before the tester commits the first edit they expect to help the courier**, ask the fixed prompt `DEMO02_PRE_EDIT_SECOND_ORDER_01`:

> “Besides the courier, what direction do you expect this map change to push the other visible journey?”

Do not tell the tester which answer is desired. Mark success only from the prediction made before the consequence is shown. `e2_packet_completed` means the tester reached and completed the intended initial prediction packet; it is not inferred from generic clicks.

### E11 — demo timing / genuine collateral aha

Start timing is generated automatically when the empirical session begins. During the demo, record the first moment the tester **genuinely recognizes that one authoritative map change produced an important collateral consequence**. This may be verbalized spontaneously or demonstrated clearly in explanation/action; a raw `collateral_consequence_seen` telemetry event alone is not an aha.

- If an aha is observed: `first_collateral_aha_observed=true` and record elapsed seconds.
- If no genuine aha is observed: set `first_collateral_aha_observed=false` and `first_collateral_aha_seconds=-1`.
- DEMO05 completion time is taken from raw telemetry when present. `session_end_seconds` is still required so incomplete sessions have a factual end time.

## Finalize locally

Fill `.phase12g-first-sessions/S001/observer.json`, then:

```bash
python3 scripts/phase12g_first_session_operator.py finalize \
  --session-dir .phase12g-first-sessions/S001
```

This creates `completed-E1.jsonl`, `completed-E2.jsonl` and `completed-E11.jsonl` in the session directory. It does **not** append them to repository evidence.

Validate each completed file before deliberate append:

```bash
python3 scripts/phase12g_collect_completed_rows.py --input .phase12g-first-sessions/S001/completed-E1.jsonl
python3 scripts/phase12g_collect_completed_rows.py --input .phase12g-first-sessions/S001/completed-E1.jsonl --append
```

Repeat for E2 and E11. E1/E2 threshold status is computed by the evidence harness. E11 remains PENDING until an evidence-backed qualitative disposition is explicitly recorded. Never turn a missing tester, incomplete observation or automated runtime fact into a human PASS.
