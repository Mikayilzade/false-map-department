#!/usr/bin/env python3
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
INTEGRITY = ROOT / "scripts/phase12g_human_return_identity_integrity.py"


def fail(message: str) -> None:
    raise SystemExit(f"PHASE12G HUMAN RETURN IDENTITY AUDIT FAIL: {message}")


def run(evidence_root: Path, ok: bool) -> subprocess.CompletedProcess[str]:
    completed = subprocess.run(
        [sys.executable, str(INTEGRITY), "--evidence-root", str(evidence_root)],
        cwd=ROOT,
        text=True,
        capture_output=True,
    )
    if ok and completed.returncode != 0:
        fail(f"integrity unexpectedly failed:\n{completed.stdout}\n{completed.stderr}")
    if not ok and completed.returncode == 0:
        fail("integrity unexpectedly accepted a conflicting finalized return namespace")
    return completed


def write_rows(path: Path, rows: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(json.dumps(row, sort_keys=True) + "\n" for row in rows), encoding="utf-8")


def base_row(gate_id: str) -> dict:
    row = {
        "schema_version": 1,
        "gate_id": gate_id,
        "evidence_provenance_version": 1,
        "source_head": "0" * 40,
        "source_build_id": "audit-demo-build",
        "acquisition_channel": "human_field_kit_v4",
        "field_kit_return_namespace": "first_session:FIRST-S0001",
        "field_kit_packet_kind": "first_session",
        "field_kit_contract_hash": "1" * 64,
        "field_kit_finalization_receipt_sha256": "2" * 64,
    }
    if gate_id == "E1":
        row.update({
            "tester_id": "NAIVE-T0001",
            "naive": True,
            "session_id": "FIRST-S0001",
            "understood_within_seconds": 42.0,
            "success": True,
        })
    elif gate_id == "E2":
        row.update({
            "tester_id": "NAIVE-T0001",
            "session_id": "FIRST-S0001",
            "packet_completed": True,
            "prediction_prompt_id": "DEMO02_PRE_EDIT_SECOND_ORDER_01",
            "success": True,
        })
    else:
        fail(f"unsupported audit gate {gate_id}")
    return row


def mature_row(gate_id: str, suffix: str) -> dict:
    common = {
        "schema_version": 1,
        "gate_id": gate_id,
        "tester_id": "MATURE-T0001",
        "evidence_provenance_version": 1,
        "source_head": "a" * 40,
        "source_build_id": "audit-production-build",
        "acquisition_channel": "human_field_kit_v4",
        "field_kit_return_namespace": "mature_session:MATURE-T0001",
        "field_kit_packet_kind": "mature_session",
        "field_kit_contract_hash": "3" * 64,
        "field_kit_finalization_receipt_sha256": "4" * 64,
    }
    if gate_id == "E5":
        common.update({
            "dossier_id": f"D{suffix}",
            "requirement_id": f"REQ-{suffix}",
            "identified_authority_layer": "REGION",
            "correct": True,
            "tutorial_recall_used": False,
        })
    elif gate_id == "E6":
        common.update({
            "dossier_id": f"D{suffix}",
            "requirement_id": f"REQ-{suffix}",
            "answered_cause": "regional source controls projected fact",
            "used_raw_debug_log": False,
            "correct": True,
        })
    else:
        fail(f"unsupported mature audit gate {gate_id}")
    return common


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="fmd-phase12g-human-return-id-") as temp:
        evidence_root = Path(temp) / "evidence"

        # One exact first-session finalization legitimately emits several gate rows.
        write_rows(evidence_root / "E1.jsonl", [base_row("E1")])
        write_rows(evidence_root / "E2.jsonl", [base_row("E2")])
        accepted = run(evidence_root, ok=True)
        if "2 field-kit evidence rows, 1 finalized return namespaces" not in accepted.stdout:
            fail("same-return cross-gate rows were not recognized as one exact finalized namespace")

        # One mature finalization may likewise contribute multiple observations/gates.
        write_rows(evidence_root / "E5.jsonl", [mature_row("E5", "25")])
        write_rows(evidence_root / "E6.jsonl", [mature_row("E6", "33")])
        accepted_multi = run(evidence_root, ok=True)
        if "4 field-kit evidence rows, 2 finalized return namespaces" not in accepted_multi.stdout:
            fail("legitimate multi-row mature return was not accepted")

        # Reusing the first-session namespace for a different finalized receipt must fail.
        conflict = base_row("E2")
        conflict["field_kit_finalization_receipt_sha256"] = "5" * 64
        conflict["success"] = False  # novel outcome proves canonical-row dedupe alone is insufficient.
        write_rows(evidence_root / "E2.jsonl", [base_row("E2"), conflict])
        rejected = run(evidence_root, ok=False)
        if "return namespace collision" not in (rejected.stdout + rejected.stderr):
            fail("conflicting receipt reuse did not fail with an explicit namespace-collision reason")

        # Missing durable identity on a field-kit row must fail rather than silently grandfathering it.
        write_rows(evidence_root / "E2.jsonl", [base_row("E2")])
        missing = base_row("E1")
        missing.pop("field_kit_contract_hash")
        write_rows(evidence_root / "E1.jsonl", [missing])
        rejected_missing = run(evidence_root, ok=False)
        if "missing durable return identity" not in (rejected_missing.stdout + rejected_missing.stderr):
            fail("field-kit row missing durable return identity was not rejected")

    print("Phase 12G human return identity audit: PASS (exact finalized-return multi-row/cross-gate reuse accepted; conflicting receipt reuse and incomplete durable identity rejected)")


if __name__ == "__main__":
    main()
