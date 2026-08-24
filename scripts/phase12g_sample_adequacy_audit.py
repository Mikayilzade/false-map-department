#!/usr/bin/env python3
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HARNESS = ROOT / "scripts" / "phase12g_evidence_harness.py"
SETTER = ROOT / "scripts" / "phase12g_set_sample_adequacy.py"


def run(command: list[str], expect: int = 0) -> subprocess.CompletedProcess[str]:
    completed = subprocess.run(command, cwd=ROOT, text=True, capture_output=True, check=False)
    if completed.returncode != expect:
        raise SystemExit(
            f"command rc={completed.returncode}, expected {expect}: {' '.join(command)}\n"
            f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
        )
    return completed


def summarize(root: Path) -> dict:
    output = root / "summary.json"
    run([sys.executable, str(HARNESS), "--evidence-root", str(root), "--output", str(output)])
    return json.loads(output.read_text(encoding="utf-8"))


def gate(summary: dict, gate_id: str) -> dict:
    return next(row for row in summary["gates"] if row["gate_id"] == gate_id)


def write_e1(path: Path, rows: list[dict]) -> None:
    path.write_text("".join(json.dumps(row, sort_keys=True) + "\n" for row in rows), encoding="utf-8")


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="fmd-phase12g-adequacy-") as raw_tmp:
        root = Path(raw_tmp)
        e1_path = root / "E1.jsonl"
        row = {
            "schema_version": 1,
            "gate_id": "E1",
            "tester_id": "T_AUDIT_01",
            "naive": True,
            "session_id": "S_AUDIT_01",
            "understood_within_seconds": 90.0,
            "success": True,
        }
        write_e1(e1_path, [row])

        initial = gate(summarize(root), "E1")
        if initial["status"] != "PENDING":
            raise SystemExit("one successful E1 row must not become PASS before representative sample adequacy is confirmed")
        if "representative sample adequacy" not in initial["detail"].get("reason", ""):
            raise SystemExit("E1 pending reason must name representative sample adequacy")
        if initial["detail"].get("threshold_preview_status") != "PASS":
            raise SystemExit("guard should expose threshold preview without promoting it to gate PASS")

        run([
            sys.executable,
            str(SETTER),
            "--gate", "E1",
            "--confirmed", "true",
            "--rationale", "Audit-only sampling rationale; exact batch intentionally bound by evidence digest.",
            "--evidence-ref", "E1.jsonl:1",
            "--evidence-root", str(root),
        ])
        confirmed = gate(summarize(root), "E1")
        if confirmed["status"] != "PASS" or confirmed["detail"].get("representative_sample_confirmed") is not True:
            raise SystemExit("confirmed exact E1 batch should evaluate the frozen 80% threshold")

        row2 = dict(row)
        row2["tester_id"] = "T_AUDIT_02"
        row2["session_id"] = "S_AUDIT_02"
        row2["success"] = False
        write_e1(e1_path, [row, row2])
        stale = gate(summarize(root), "E1")
        if stale["status"] != "PENDING" or "stale" not in stale["detail"].get("reason", ""):
            raise SystemExit("appending/changing rows must invalidate prior sample adequacy confirmation")

        invalid_gate = subprocess.run([
            sys.executable,
            str(SETTER),
            "--gate", "E7",
            "--confirmed", "true",
            "--rationale", "not allowed",
            "--evidence-ref", "E7.jsonl:1",
            "--evidence-root", str(root),
        ], cwd=ROOT, text=True, capture_output=True, check=False)
        if invalid_gate.returncode == 0:
            raise SystemExit("sample adequacy setter must be limited to representative human percentage gates E1/E2")

    print("Phase 12G sample adequacy audit: PASS (one-row PASS blocked; exact batch confirmation required; evidence changes invalidate confirmation; no invented minimum N)")


if __name__ == "__main__":
    main()
