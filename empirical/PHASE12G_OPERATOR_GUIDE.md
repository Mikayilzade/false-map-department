# Phase 12G operator guide

This guide is for collecting real empirical evidence after the automated implementation/precondition suite is green. Generated templates are not evidence until every required observation field is completed.

## 1. Earliest practical batch: E1 / E2 / E11

Use the dedicated first-session protocol in `empirical/PHASE12G_FIRST_SESSION_PROTOCOL.md`.

Prepare one pseudonymous tester/session packet:

```bash
python3 scripts/phase12g_first_session_operator.py prepare \
  --tester-id T001 --session-id S001
```

Launch the real production DEMO01-DEMO05 GUI build:

```bash
python3 scripts/phase12g_first_session_operator.py launch \
  --session-dir .phase12g-first-sessions/S001 \
  --godot /path/to/godot
```

Fill the generated `observer.json` only from actual observation, then finalize:

```bash
python3 scripts/phase12g_first_session_operator.py finalize \
  --session-dir .phase12g-first-sessions/S001
```

The operator deliberately keeps human outcomes separate from raw telemetry. In particular, a raw collateral-consequence event is never treated as human comprehension or a genuine “aha”. Finalize writes local completed E1/E2/E11 rows only; it never appends repository evidence automatically.

## 2. Prepare mature/capture session packets

Run:

```bash
python3 scripts/phase12g_prepare_session_packets.py
```

Templates are written to `.phase12g-session-packets/`. Do not copy blank templates into `empirical/evidence/`.

## 3. Complete real observations

Fill only what was actually observed. Preserve pseudonymous tester/respondent IDs. Do not infer comprehension, prediction success, causal understanding, capture pass, marketing expectation, value perception, or hardware performance from automated implementation facts.

## 4. Validate before append

Dry-run a completed file first:

```bash
python3 scripts/phase12g_collect_completed_rows.py --input completed-E3.jsonl
```

If validation passes, append it deliberately:

```bash
python3 scripts/phase12g_collect_completed_rows.py --input completed-E3.jsonl --append
```

The collector rejects blank required fields and skips exact duplicate observations.

## 5. E1/E2 also require representative-sample adequacy

The canonical E1/E2 rules say **representative testers**, but they do not freeze a minimum sample size. Do not invent a minimum N, and do not let one successful tester become a gate PASS merely because the percentage math is 100%.

After a real E1/E2 batch has been collected and its recruitment/sampling is judged representative enough for the intended prototype decision, record that judgment against the exact current evidence file:

```bash
python3 scripts/phase12g_set_sample_adequacy.py \
  --gate E1 \
  --confirmed true \
  --rationale "Explain why this recruited batch is representative for the prototype decision." \
  --evidence-ref E1.jsonl:1-12
```

This records the exact evidence SHA-256 and row count. If any row is later appended/changed, the adequacy confirmation becomes stale and E1/E2 return to `PENDING` until the updated batch is reviewed again.

Sample adequacy **does not override** the frozen thresholds. Once confirmed, E1 still needs >=80% qualifying naive comprehension within 180 seconds and E2 still needs >=70% qualifying prediction success. `--confirmed false` records that the current batch is not yet representative and therefore remains PENDING.

## 6. Qualitative gates need a disposition

For E3, E4, E5, E6, E8, E9, E10, E11 and E12, evidence rows alone remain `PENDING`. After reviewing the evidence, record an explicit PASS/FAIL/BLOCKED disposition with a rationale and concrete evidence references:

```bash
python3 scripts/phase12g_set_disposition.py \
  --gate E3 \
  --status PASS \
  --rationale "Representative comparison supports the causal-reasoning gate." \
  --evidence-ref E3.jsonl:1-12
```

Numeric/threshold gates E1, E2, E7 and T8-44 cannot be manually overridden by this tool; the harness computes them from evidence. E1/E2 sample-adequacy confirmation only unlocks evaluation of their fixed percentage thresholds.

Every qualitative decision updates `dispositions.json` and appends an immutable audit row to `disposition_history.jsonl`.

## 7. Render current state

Run:

```bash
python3 scripts/phase12g_evidence_harness.py --output .phase12g-summary.json
python3 scripts/phase12g_gate_dashboard.py --output .phase12g-dashboard.md
```

The dashboard is an operational view only. 12G is an exit candidate only when all 13 registered gates are PASS. Missing evidence remains PENDING; malformed evidence becomes BLOCKED; observed threshold failure becomes FAIL; an E1/E2 percentage result cannot become PASS/FAIL until the exact current sample has an evidence-backed representativeness adequacy record.
