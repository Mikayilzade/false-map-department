#!/usr/bin/env python3
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
COLLECTOR = ROOT / "scripts/phase12g_collect_completed_rows.py"
FINALIZER = ROOT / "scripts/phase12g_field_kit_offline_finalize.py"
CHANNEL = "human_field_kit_v4"
SOURCE_HEAD = "1" * 40
BUILD_ID = "qualification-audit-build"


def run_collector(root: Path, row: dict, *, expect_ok: bool) -> subprocess.CompletedProcess[str]:
    source = root / "input.jsonl"
    source.write_text(json.dumps(row, sort_keys=True) + "\n", encoding="utf-8")
    completed = subprocess.run(
        [sys.executable, str(COLLECTOR), "--input", str(source), "--evidence-root", str(root / "evidence")],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )
    if expect_ok and completed.returncode != 0:
        raise SystemExit(f"qualification collector case unexpectedly failed: {(completed.stdout + completed.stderr).strip()}")
    if not expect_ok and completed.returncode == 0:
        raise SystemExit("qualification collector case unexpectedly passed")
    return completed


def provenance(gate_id: str) -> dict:
    return {
        "gate_id": gate_id,
        "source_head": SOURCE_HEAD,
        "source_build_id": BUILD_ID,
        "acquisition_channel": CHANNEL,
    }


def e2_row(naive_marker=...):
    row = {
        **provenance("E2"),
        "tester_id": "QUAL-T1",
        "session_id": "QUAL-S1",
        "packet_completed": True,
        "prediction_prompt_id": "DEMO02_PRE_EDIT_SECOND_ORDER_01",
        "success": True,
    }
    if naive_marker is not ...:
        row["naive"] = naive_marker
    return row


def e3_row(rules_marker=..., knowledge_marker=True):
    row = {
        **provenance("E3"),
        "tester_id": "QUAL-M1",
        "dossier_id": "D13",
        "method": "causal_reasoning",
        "completion_seconds": 10,
        "completed": True,
        "rule_knowledge_confirmed": knowledge_marker,
    }
    if rules_marker is not ...:
        row["rules_known_before_session"] = rules_marker
    return row


def e11_row(naive_marker):
    return {
        **provenance("E11"),
        "tester_id": "QUAL-T1",
        "naive": naive_marker,
        "demo_build_id": BUILD_ID,
        "start_timestamp": 1,
        "first_collateral_aha_seconds": 60,
        "completion_seconds": 600,
        "completed": True,
    }


def require_finalizer_markers() -> None:
    text = FINALIZER.read_text(encoding="utf-8")
    required = [
        '"E2":{"schema_version":1,"gate_id":"E2","tester_id":tester_id,"naive":naive',
        '"E11":{"schema_version":1,"gate_id":"E11","tester_id":tester_id,"naive":naive',
        'item["rules_known_before_session"]=True',
        'raw.get("rule_knowledge_confirmed") is not True',
        '"participant_qualification":qualification',
        '"proves_human_truth_or_timing":False',
    ]
    missing = [marker for marker in required if marker not in text]
    if missing:
        raise SystemExit(f"offline finalizer missing qualification-binding markers: {missing}")


def main() -> None:
    require_finalizer_markers()
    with tempfile.TemporaryDirectory(prefix="fmd-phase12g-qualification-audit-") as temp:
        root = Path(temp)

        # E2 is explicitly a representative-naive gate. The declaration must be
        # present and true before a field-kit row can enter evidence.
        run_collector(root, e2_row(True), expect_ok=True)
        missing_e2 = run_collector(root, e2_row(), expect_ok=False)
        if "naive" not in (missing_e2.stdout + missing_e2.stderr).lower():
            raise SystemExit("missing E2 naive qualification did not fail explicitly")
        non_naive_e2 = run_collector(root, e2_row(False), expect_ok=False)
        if "naive tester" not in (non_naive_e2.stdout + non_naive_e2.stderr).lower():
            raise SystemExit("non-naive E2 row did not fail as cohort-ineligible")

        # E11 shares the first-session packet but does not gain a new canonical
        # naive threshold. Preserve the declaration without pretending it decides E11.
        run_collector(root, e11_row(False), expect_ok=True)

        # Mature acquisition must preserve the packet declaration that rules were
        # known before the session. E3 additionally requires row-level confirmation.
        run_collector(root, e3_row(True, True), expect_ok=True)
        missing_mature = run_collector(root, e3_row(), expect_ok=False)
        if "rules_known_before_session" not in (missing_mature.stdout + missing_mature.stderr):
            raise SystemExit("missing mature qualification did not fail explicitly")
        false_knowledge = run_collector(root, e3_row(True, False), expect_ok=False)
        if "after rules are known" not in (false_knowledge.stdout + false_knowledge.stderr).lower():
            raise SystemExit("E3 without confirmed rule knowledge did not fail explicitly")

    print(
        "Phase 12G participant qualification binding audit: PASS "
        "(receipt-bound first-session naive declaration + E2 naive eligibility + mature rules-known declaration + E3 rule-knowledge guard; declarations do not prove human truth/timing)"
    )


if __name__ == "__main__":
    main()
