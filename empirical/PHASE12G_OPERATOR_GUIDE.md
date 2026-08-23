# Phase 12G operator guide

This guide is for collecting real empirical evidence after the automated implementation/precondition suite is green. Generated templates are not evidence until every required observation field is completed.

## 1. Prepare session packets

Run:

```bash
python3 scripts/phase12g_prepare_session_packets.py
```

Templates are written to `.phase12g-session-packets/`. Do not copy blank templates into `empirical/evidence/`.

## 2. Complete real observations

Fill only what was actually observed. Preserve pseudonymous tester/respondent IDs. Do not infer comprehension, prediction success, causal understanding, capture pass, marketing expectation, value perception, or hardware performance from automated implementation facts.

## 3. Validate before append

Dry-run a completed file first:

```bash
python3 scripts/phase12g_collect_completed_rows.py --input completed-E3.jsonl
```

If validation passes, append it deliberately:

```bash
python3 scripts/phase12g_collect_completed_rows.py --input completed-E3.jsonl --append
```

The collector rejects blank required fields and skips exact duplicate observations.

## 4. Qualitative gates need a disposition

For E3, E4, E5, E6, E8, E9, E10, E11 and E12, evidence rows alone remain `PENDING`. After reviewing the evidence, record an explicit PASS/FAIL/BLOCKED disposition with a rationale and concrete evidence references:

```bash
python3 scripts/phase12g_set_disposition.py \
  --gate E3 \
  --status PASS \
  --rationale "Representative comparison supports the causal-reasoning gate." \
  --evidence-ref E3.jsonl:1-12
```

Numeric/threshold gates E1, E2, E7 and T8-44 cannot be manually overridden by this tool; the harness computes them from evidence.

Every qualitative decision updates `dispositions.json` and appends an immutable audit row to `disposition_history.jsonl`.

## 5. Render current state

Run:

```bash
python3 scripts/phase12g_evidence_harness.py --output .phase12g-summary.json
python3 scripts/phase12g_gate_dashboard.py --output .phase12g-dashboard.md
```

The dashboard is an operational view only. 12G is an exit candidate only when all 13 registered gates are PASS. Missing evidence remains PENDING; malformed evidence becomes BLOCKED; observed threshold failure becomes FAIL.
