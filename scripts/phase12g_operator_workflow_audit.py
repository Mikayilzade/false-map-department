#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
COLLECTOR = ROOT / "scripts/phase12g_collect_completed_rows.py"
SETTER = ROOT / "scripts/phase12g_set_disposition.py"
INTEGRITY = ROOT / "scripts/phase12g_qualitative_disposition_integrity.py"
HARNESS = ROOT / "scripts/phase12g_evidence_harness.py"
DASHBOARD = ROOT / "scripts/phase12g_gate_dashboard.py"


def fail(message: str) -> None:
    raise SystemExit(f"PHASE12G OPERATOR WORKFLOW FAIL: {message}")


def run(args: list[str], expect_ok: bool = True) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(args, cwd=ROOT, text=True, capture_output=True)
    if expect_ok and result.returncode != 0:
        fail(f"command failed ({result.returncode}): {' '.join(args)}\n{result.stdout}\n{result.stderr}")
    if not expect_ok and result.returncode == 0:
        fail(f"command unexpectedly succeeded: {' '.join(args)}")
    return result


def gate(summary: dict, gate_id: str) -> dict:
    for row in summary["gates"]:
        if row["gate_id"] == gate_id:
            return row
    fail(f"gate missing from summary: {gate_id}")
    return {}


def e3_row(tester_id: str, completion_seconds: float) -> dict:
    return {
        "gate_id": "E3",
        "tester_id": tester_id,
        "dossier_id": "D13",
        "method": "causal_reasoning",
        "completion_seconds": completion_seconds,
        "completed": True,
        "rule_knowledge_confirmed": True,
    }


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="fmd-phase12g-operator-") as tmp:
        root = Path(tmp)
        evidence = root / "evidence"
        blank = root / "blank-e3.jsonl"
        complete = root / "complete-e3.jsonl"
        second = root / "second-e3.jsonl"
        summary_before = root / "summary-before.json"
        summary_after = root / "summary-after.json"
        dashboard = root / "dashboard.md"

        blank.write_text(json.dumps({
            "gate_id": "E3",
            "tester_id": None,
            "dossier_id": "D13",
            "method": "causal_reasoning",
            "completion_seconds": None,
            "completed": None,
            "rule_knowledge_confirmed": None,
        }) + "\n", encoding="utf-8")
        run([sys.executable, str(COLLECTOR), "--input", str(blank), "--evidence-root", str(evidence)], expect_ok=False)
        if evidence.exists():
            fail("blank collector dry-run must not create evidence root")

        complete.write_text(json.dumps(e3_row("T001", 123.0)) + "\n", encoding="utf-8")
        run([sys.executable, str(COLLECTOR), "--input", str(complete), "--evidence-root", str(evidence), "--append"])
        first_text = (evidence / "E3.jsonl").read_text(encoding="utf-8")
        run([sys.executable, str(COLLECTOR), "--input", str(complete), "--evidence-root", str(evidence), "--append"])
        if (evidence / "E3.jsonl").read_text(encoding="utf-8") != first_text:
            fail("collector must not append exact duplicate observations")

        run([sys.executable, str(HARNESS), "--evidence-root", str(evidence), "--output", str(summary_before)])
        before = json.loads(summary_before.read_text(encoding="utf-8"))
        if gate(before, "E3")["status"] != "PENDING":
            fail("qualitative E3 must remain PENDING before explicit disposition")

        run([
            sys.executable, str(SETTER),
            "--gate", "E3",
            "--status", "PASS",
            "--rationale", "Representative comparison supports the causal-reasoning disposition.",
            "--evidence-ref", "E3.jsonl:1",
            "--reviewer-id", "SYNTHETIC_OPERATOR",
            "--evidence-root", str(evidence),
        ])
        if not (evidence / "disposition_history.jsonl").exists():
            fail("disposition history must be append-only auditable evidence")
        run([sys.executable, str(INTEGRITY), "--evidence-root", str(evidence)])

        run([sys.executable, str(HARNESS), "--evidence-root", str(evidence), "--output", str(summary_after)])
        after = json.loads(summary_after.read_text(encoding="utf-8"))
        e3 = gate(after, "E3")
        if e3["status"] != "PASS" or "rationale" not in e3["detail"]:
            fail("explicit E3 disposition was not surfaced by harness")

        run([
            sys.executable, str(SETTER),
            "--gate", "E1",
            "--status", "PASS",
            "--rationale", "manual override should be forbidden",
            "--evidence-ref", "E1.jsonl:1",
            "--reviewer-id", "SYNTHETIC_OPERATOR",
            "--evidence-root", str(evidence),
        ], expect_ok=False)

        run([sys.executable, str(DASHBOARD), "--evidence-root", str(evidence), "--output", str(dashboard)])
        text = dashboard.read_text(encoding="utf-8")
        if "E3 — mature reasoning beats blind enumeration | PASS" not in text:
            fail("dashboard does not expose evidence-backed qualitative PASS")
        if "12G exit candidate: **NO**" not in text:
            fail("partial evidence must never produce a 12G exit candidate")

        # The compatibility setter used to bind only a row count. Prove that its
        # current v2 output is instead exact-byte bound: a later append must make
        # the prior review stale until the operator deliberately re-reviews it.
        second.write_text(json.dumps(e3_row("T002", 150.0)) + "\n", encoding="utf-8")
        run([sys.executable, str(COLLECTOR), "--input", str(second), "--evidence-root", str(evidence), "--append"])
        stale = run([sys.executable, str(INTEGRITY), "--evidence-root", str(evidence)], expect_ok=False)
        if "stale" not in (stale.stdout + stale.stderr).lower():
            fail("legacy setter disposition must become explicitly stale after append-only evidence changes")
        stale_dashboard = run(
            [sys.executable, str(DASHBOARD), "--evidence-root", str(evidence), "--output", str(dashboard)],
            expect_ok=False,
        )
        if "stale" not in (stale_dashboard.stdout + stale_dashboard.stderr).lower():
            fail("operator dashboard must fail closed on the stale compatibility-setter review")

        run([
            sys.executable, str(SETTER),
            "--gate", "E3",
            "--status", "PASS",
            "--rationale", "Re-reviewed exact two-row batch still supports the causal-reasoning disposition.",
            "--evidence-ref", "E3.jsonl:1-2",
            "--reviewer-id", "SYNTHETIC_OPERATOR",
            "--evidence-root", str(evidence),
            "--replace",
        ])
        run([sys.executable, str(INTEGRITY), "--evidence-root", str(evidence)])
        run([sys.executable, str(DASHBOARD), "--evidence-root", str(evidence), "--output", str(dashboard)])
        if "E3 — mature reasoning beats blind enumeration | PASS" not in dashboard.read_text(encoding="utf-8"):
            fail("operator dashboard must recover only after deliberate exact-byte re-review")

    print("Phase 12G operator workflow audit: PASS (blank-row rejection + append dedupe + exact-byte qualitative disposition + stale-review rejection + dashboard)")


if __name__ == "__main__":
    main()
