#!/usr/bin/env python3
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RECORDER = ROOT / "scripts/phase12g_qualitative_disposition.py"
INTEGRITY = ROOT / "scripts/phase12g_qualitative_disposition_integrity.py"
HARNESS = ROOT / "scripts/phase12g_evidence_harness.py"


def run(args: list[str], *, expect_ok: bool = True) -> subprocess.CompletedProcess[str]:
    completed = subprocess.run(args, cwd=ROOT, text=True, capture_output=True)
    if expect_ok and completed.returncode != 0:
        raise SystemExit(f"command failed: {' '.join(args)}\nSTDOUT:\n{completed.stdout}\nSTDERR:\n{completed.stderr}")
    if not expect_ok and completed.returncode == 0:
        raise SystemExit(f"command unexpectedly passed: {' '.join(args)}")
    return completed


def harness_status(root: Path, gate_id: str) -> str:
    result = run([sys.executable, str(HARNESS), "--evidence-root", str(root)])
    payload = json.loads(result.stdout)
    for gate in payload["gates"]:
        if gate["gate_id"] == gate_id:
            return gate["status"]
    raise SystemExit(f"missing {gate_id} in harness output")


def write_e8(path: Path, respondent_id: str, builder: bool) -> None:
    row = {
        "gate_id": "E8",
        "respondent_id": respondent_id,
        "asset_version": "SYNTHETIC-AUDIT-ASSET",
        "expected_play_category": "civic puzzle",
        "freeform_builder_expectation": builder,
        "notes": "synthetic audit row; never repository evidence",
    }
    with path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(row, sort_keys=True) + "\n")


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="fmd-phase12g-disposition-audit-") as temp:
        root = Path(temp)
        evidence = root / "E8.jsonl"
        dispositions = root / "dispositions.json"
        write_e8(evidence, "SYNTHETIC_R1", False)

        if harness_status(root, "E8") != "PENDING":
            raise SystemExit("E8 with rows but no explicit disposition must remain PENDING")

        run([
            sys.executable,
            str(RECORDER),
            "E8",
            "--status", "PASS",
            "--rationale", "Synthetic explicit interpretation for provenance audit only.",
            "--evidence-ref", "synthetic:E8.jsonl",
            "--reviewer-id", "SYNTHETIC_REVIEWER",
            "--evidence-root", str(root),
            "--output", str(dispositions),
        ])
        run([sys.executable, str(INTEGRITY), "--evidence-root", str(root), "--dispositions", str(dispositions)])
        if harness_status(root, "E8") != "PASS":
            raise SystemExit("explicit disposition should become visible to the harness only after rows exist")

        # Recorder is write-once by default: a changed/reconsidered interpretation must be deliberate.
        run([
            sys.executable, str(RECORDER), "E8",
            "--status", "FAIL",
            "--rationale", "Should not overwrite without explicit replacement.",
            "--evidence-ref", "synthetic:E8.jsonl",
            "--reviewer-id", "SYNTHETIC_REVIEWER",
            "--evidence-root", str(root),
            "--output", str(dispositions),
        ], expect_ok=False)

        # Appending evidence invalidates the recorded interpretation until the new bytes are re-reviewed.
        write_e8(evidence, "SYNTHETIC_R2", True)
        stale = run([sys.executable, str(INTEGRITY), "--evidence-root", str(root), "--dispositions", str(dispositions)], expect_ok=False)
        if "stale" not in (stale.stdout + stale.stderr).lower():
            raise SystemExit("post-disposition evidence mutation must fail explicitly as stale")

        run([
            sys.executable, str(RECORDER), "E8",
            "--status", "FAIL",
            "--rationale", "Synthetic re-review after evidence changed.",
            "--evidence-ref", "synthetic:E8.jsonl",
            "--reviewer-id", "SYNTHETIC_REVIEWER",
            "--evidence-root", str(root),
            "--output", str(dispositions),
            "--replace",
        ])
        run([sys.executable, str(INTEGRITY), "--evidence-root", str(root), "--dispositions", str(dispositions)])
        if harness_status(root, "E8") != "FAIL":
            raise SystemExit("deliberately replaced disposition must reflect the newly reviewed evidence batch")

        # Threshold gates may never be manually dispositioned through this path.
        e7 = root / "E7.jsonl"
        e7.write_text('{"gate_id":"E7"}\n', encoding="utf-8")
        run([
            sys.executable, str(RECORDER), "E7",
            "--status", "PASS",
            "--rationale", "forbidden",
            "--evidence-ref", "synthetic:E7.jsonl",
            "--reviewer-id", "SYNTHETIC_REVIEWER",
            "--evidence-root", str(root),
            "--output", str(dispositions),
        ], expect_ok=False)

    print("Phase 12G qualitative disposition audit: PASS (explicit review + exact evidence digest/row binding + stale rejection + deliberate replacement + threshold-gate guard)")


if __name__ == "__main__":
    main()
