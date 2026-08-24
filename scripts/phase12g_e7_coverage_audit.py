#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HARNESS = ROOT / "scripts" / "phase12g_evidence_harness.py"
THRESHOLD = {"metric": "shippable_dossiers_pass_rate", "operator": "==", "value": 1.0}


def load_harness():
    spec = importlib.util.spec_from_file_location("phase12g_evidence_harness", HARNESS)
    if spec is None or spec.loader is None:
        raise SystemExit("E7 COVERAGE AUDIT FAIL: unable to load evidence harness")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"E7 COVERAGE AUDIT FAIL: {message}")


def completed_rows(module) -> list[dict]:
    rows: list[dict] = []
    for expected in module.e7_expected_matrix().values():
        row = dict(expected)
        row["interaction_complete"] = True
        row["capture_review_pass"] = True
        rows.append(row)
    return rows


def main() -> None:
    module = load_harness()
    rows = completed_rows(module)
    require(len(rows) == 285, f"canonical E7 matrix must be exactly 285 rows, got {len(rows)}")

    status, detail = module.evaluate_e7_exhaustive(rows[:5], THRESHOLD)
    require(status == "PENDING", f"5/5 partial rows must remain PENDING, got {status}")
    require(detail.get("observed_unique_rows") == 5, "partial coverage should report five unique rows")
    require(detail.get("expected_unique_rows") == 285, "partial coverage should require 285 unique rows")

    status, detail = module.evaluate_e7_exhaustive(rows[:284], THRESHOLD)
    require(status == "PENDING", f"284/285 rows must remain PENDING, got {status}")
    require(detail.get("missing_unique_rows") == 1, "284-row batch must report one missing signature")

    status, detail = module.evaluate_e7_exhaustive(rows, THRESHOLD)
    require(status == "PASS", f"complete 285/285 all-pass matrix must PASS, got {status}")
    require(detail.get("observed_unique_rows") == 285, "complete matrix should report 285 unique rows")
    require(detail.get("passing_unique_rows") == 285, "complete all-pass matrix should report 285 passing rows")

    one_fail = [dict(row) for row in rows]
    one_fail[-1]["capture_review_pass"] = False
    status, detail = module.evaluate_e7_exhaustive(one_fail, THRESHOLD)
    require(status == "FAIL", f"complete matrix with one failing row must FAIL, got {status}")
    require(detail.get("failing_unique_rows") == 1, "one-fail matrix should report one failing signature")

    # Append-only reruns are allowed: the latest row for one exact matrix signature
    # is the current disposition while the older attempt remains auditable history.
    rerun_rows = [dict(row) for row in rows]
    failed_rerun = dict(rows[0])
    failed_rerun["interaction_complete"] = False
    rerun_rows.append(failed_rerun)
    status, detail = module.evaluate_e7_exhaustive(rerun_rows, THRESHOLD)
    require(status == "FAIL", "latest failed rerun must supersede the older pass for current evaluation")
    require(detail.get("observed_unique_rows") == 285, "duplicate rerun must not inflate matrix coverage")
    recovered_rerun = dict(rows[0])
    rerun_rows.append(recovered_rerun)
    status, detail = module.evaluate_e7_exhaustive(rerun_rows, THRESHOLD)
    require(status == "PASS", "later repaired rerun must restore current matrix disposition")
    require(detail.get("raw_evidence_rows") == 287, "append-only reruns should remain visible in raw row count")

    unknown = dict(rows[0])
    unknown["dossier_id"] = "D99"
    status, _ = module.evaluate_e7_exhaustive(rows + [unknown], THRESHOLD)
    require(status == "BLOCKED", "unknown dossier/scenario signature must BLOCK E7 evaluation")

    print("Phase 12G E7 coverage audit: PASS (5/285 and 284/285 stay PENDING; exact 285 required; latest rerun wins without inflating coverage)")


if __name__ == "__main__":
    main()
