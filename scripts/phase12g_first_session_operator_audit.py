#!/usr/bin/env python3
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OPERATOR = ROOT / "scripts" / "phase12g_first_session_operator.py"
EVIDENCE_ROOT = ROOT / "empirical" / "evidence"


def run(*args: str, expect: int = 0) -> subprocess.CompletedProcess[str]:
    completed = subprocess.run(
        [sys.executable, str(OPERATOR), *args],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )
    if completed.returncode != expect:
        raise SystemExit(
            f"operator {' '.join(args)} rc={completed.returncode}, expected {expect}\n"
            f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
        )
    return completed


def load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def main() -> None:
    before = {path.name: path.read_bytes() for path in EVIDENCE_ROOT.glob("*") if path.is_file()}
    with tempfile.TemporaryDirectory(prefix="fmd-phase12g-first-session-") as raw_tmp:
        tmp = Path(raw_tmp)
        run(
            "prepare",
            "--tester-id", "T_AUDIT_01",
            "--session-id", "S_AUDIT_01",
            "--build-id", "BUILD_AUDIT",
            "--output-dir", str(tmp),
        )
        session = tmp / "S_AUDIT_01"
        manifest = load(session / "session-manifest.json")
        observer = load(session / "observer.json")
        if manifest.get("raw_collateral_event_is_not_human_aha") is not True:
            raise SystemExit("manifest must explicitly reject raw collateral -> human aha inference")
        if observer.get("e1_success") is not None or observer.get("e2_success") is not None:
            raise SystemExit("prepared observer outcomes must remain blank")

        telemetry = {
            "schema_version": 1,
            "tester_id": "T_AUDIT_01",
            "session_id": "S_AUDIT_01",
            "demo_build_id": "BUILD_AUDIT",
            "session_started_ms": 5000,
            "events": [
                {"event_type": "session_started", "elapsed_seconds": 0.0, "payload": {}},
                {"event_type": "collateral_consequence_seen", "elapsed_seconds": 12.0, "payload": {"consequence_id": "RAW_ONLY"}},
                {"event_type": "demo_completed", "elapsed_seconds": 1000.0, "payload": {}},
            ],
        }
        (session / "telemetry.json").write_text(json.dumps(telemetry), encoding="utf-8")
        observer.update({
            "naive": True,
            "e1_success": True,
            "e1_understood_at_seconds": 95.0,
            "e2_packet_completed": True,
            "e2_success": True,
            "first_collateral_aha_observed": True,
            "first_collateral_aha_seconds": 420.0,
            "session_end_seconds": 1005.0,
        })
        (session / "observer.json").write_text(json.dumps(observer), encoding="utf-8")
        run("finalize", "--session-dir", str(session))

        e1 = json.loads((session / "completed-E1.jsonl").read_text(encoding="utf-8"))
        e2 = json.loads((session / "completed-E2.jsonl").read_text(encoding="utf-8"))
        e11 = json.loads((session / "completed-E11.jsonl").read_text(encoding="utf-8"))
        if e1["understood_within_seconds"] != 95.0 or e1["success"] is not True:
            raise SystemExit("E1 must use explicit observer outcome/time")
        if e2["prediction_prompt_id"] != "DEMO02_PRE_EDIT_SECOND_ORDER_01" or e2["success"] is not True:
            raise SystemExit("E2 must preserve fixed pre-consequence prompt and explicit observer success")
        if e11["first_collateral_aha_seconds"] != 420.0:
            raise SystemExit("E11 aha must come from observer, never raw collateral telemetry")
        if e11["completion_seconds"] != 1000.0 or e11["completed"] is not True:
            raise SystemExit("E11 completion should use raw demo_completed timing")

        # Negative guard: no-aha sessions must use the explicit -1 sentinel, not a raw collateral time.
        observer["first_collateral_aha_observed"] = False
        observer["first_collateral_aha_seconds"] = 12.0
        (session / "observer.json").write_text(json.dumps(observer), encoding="utf-8")
        failed = subprocess.run(
            [sys.executable, str(OPERATOR), "finalize", "--session-dir", str(session)],
            cwd=ROOT,
            text=True,
            capture_output=True,
            check=False,
        )
        if failed.returncode == 0 or "first_collateral_aha_seconds=-1" not in (failed.stdout + failed.stderr):
            raise SystemExit("operator must reject raw-event-style aha substitution on no-aha sessions")

    after = {path.name: path.read_bytes() for path in EVIDENCE_ROOT.glob("*") if path.is_file()}
    if before != after:
        raise SystemExit("operator audit must never mutate empirical/evidence")
    print("Phase 12G first-session operator audit: PASS (observer outcomes explicit; raw collateral != human aha; no repository evidence mutation)")


if __name__ == "__main__":
    main()
