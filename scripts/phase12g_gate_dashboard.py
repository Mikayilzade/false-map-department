#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
HARNESS = ROOT / "scripts/phase12g_evidence_harness.py"
QUALITATIVE_INTEGRITY = ROOT / "scripts/phase12g_qualitative_disposition_integrity.py"
DEFAULT_EVIDENCE_ROOT = ROOT / "empirical/evidence"


def detail_text(detail: dict) -> str:
    if "metric" in detail:
        value = detail.get("value")
        target = detail.get("target")
        return f"{detail['metric']}={value:.3f} target={target}" if isinstance(value, (int, float)) else str(detail)
    if "rationale" in detail:
        return str(detail["rationale"])
    if "reason" in detail:
        return str(detail["reason"])
    if "schema_failures" in detail:
        return "; ".join(detail["schema_failures"][:2])
    if "latest" in detail:
        return "latest profile vs frozen target"
    return ""


def main() -> None:
    parser = argparse.ArgumentParser(description="Render a compact Phase 12G empirical gate dashboard from validated evidence.")
    parser.add_argument("--evidence-root", type=Path, default=DEFAULT_EVIDENCE_ROOT)
    parser.add_argument("--output", type=Path, default=ROOT / ".phase12g-dashboard.md")
    args = parser.parse_args()

    # A qualitative disposition is an explicit review of exact evidence bytes.
    # Fail closed before rendering so a standalone dashboard can never present a
    # stale PASS/FAIL/BLOCKED after append-only evidence changes.
    subprocess.run(
        [
            sys.executable,
            str(QUALITATIVE_INTEGRITY),
            "--evidence-root",
            str(args.evidence_root),
        ],
        cwd=ROOT,
        check=True,
        stdout=subprocess.DEVNULL,
    )

    with tempfile.TemporaryDirectory(prefix="fmd-phase12g-dashboard-") as tmp:
        summary_path = Path(tmp) / "summary.json"
        subprocess.run(
            [sys.executable, str(HARNESS), "--evidence-root", str(args.evidence_root), "--output", str(summary_path)],
            cwd=ROOT,
            check=True,
            stdout=subprocess.DEVNULL,
        )
        summary = json.loads(summary_path.read_text(encoding="utf-8"))

    counts = summary["counts"]
    lines = [
        "# Phase 12G empirical gate dashboard",
        "",
        f"Status counts: PASS {counts['PASS']} · FAIL {counts['FAIL']} · PENDING {counts['PENDING']} · BLOCKED {counts['BLOCKED']}",
        "",
        "| Gate | Status | Rows | Evidence class | Detail |",
        "| --- | --- | ---: | --- | --- |",
    ]
    for gate in summary["gates"]:
        detail = detail_text(gate.get("detail", {})).replace("|", "\\|")
        lines.append(f"| {gate['gate_id']} — {gate['name']} | {gate['status']} | {gate['rows']} | {gate['evidence_class']} | {detail} |")

    complete = counts["PASS"] == len(summary["gates"])
    lines.extend([
        "",
        f"12G exit candidate: **{'YES' if complete else 'NO'}**",
        "",
        "A gate remains PENDING when evidence is absent or a qualitative evidence-backed disposition has not been recorded. This dashboard never upgrades missing evidence. Stale qualitative reviews are rejected before rendering.",
        "",
    ])
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text("\n".join(lines), encoding="utf-8")
    print(args.output)


if __name__ == "__main__":
    main()
