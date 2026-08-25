#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
COLLECTOR = ROOT / "scripts/phase12g_collect_completed_rows.py"
REFERENCE_ATTESTATION = "actual_deck_class_reference"


def fail(message: str) -> None:
    raise SystemExit(f"PHASE12G T8-44 INGEST FAIL: {message}")


def load_json(path: Path) -> dict:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        fail("packet must be a JSON object")
    return payload


def validate_sha(value: str, label: str) -> str:
    value = value.strip().lower()
    if len(value) != 40 or any(ch not in "0123456789abcdef" for ch in value):
        fail(f"{label} must be an exact 40-character commit SHA")
    return value


def validate_packet(packet: dict, expected_source_head: str, allow_audit_fixture: bool = False) -> dict:
    if int(packet.get("packet_version", 0)) != 1:
        fail("unsupported packet_version")
    packet_source = validate_sha(str(packet.get("source_head", "")), "packet source_head")
    if packet_source != expected_source_head:
        fail(f"packet source_head mismatch: expected {expected_source_head}, got {packet_source}")

    disposition = str(packet.get("profiling_disposition", ""))
    attestation = str(packet.get("hardware_attestation", ""))
    if not allow_audit_fixture:
        if disposition != "reference_run":
            fail("only profiling_disposition=reference_run may enter T8-44 evidence")
        if attestation != REFERENCE_ATTESTATION:
            fail("reference_run packet lacks actual Deck-class hardware attestation")
    else:
        if disposition not in {"reference_run", "audit_fixture"}:
            fail("audit fixture has unsupported disposition")

    row = packet.get("profile_row")
    if not isinstance(row, dict):
        fail("profile_row missing/malformed")
    if str(row.get("gate_id", "")) != "T8-44":
        fail("profile_row must target T8-44")
    if str(row.get("profiling_disposition", "")) != disposition:
        fail("packet/profile disposition mismatch")
    required = [
        "hardware_id", "build_id", "dossier_id", "sample_count",
        "typical_edit_median_ms", "typical_edit_p95_ms", "late_game_edit_p99_ms",
        "stability_cycle_p95_ms", "profiling_disposition",
    ]
    blank = [name for name in required if name not in row or row.get(name) in (None, "")]
    if blank:
        fail("profile_row missing required fields: " + ", ".join(blank))
    if int(row.get("sample_count", 0)) <= 0:
        fail("profile_row sample_count must be positive")
    for metric in [
        "typical_edit_median_ms", "typical_edit_p95_ms",
        "late_game_edit_p99_ms", "stability_cycle_p95_ms",
    ]:
        value = row.get(metric)
        if isinstance(value, bool) or not isinstance(value, (int, float)) or float(value) < 0:
            fail(f"{metric} must be a non-negative number")

    raw = packet.get("raw_samples_us")
    if not isinstance(raw, dict):
        fail("raw_samples_us missing/malformed")
    for family in ["typical_edit", "late_game_edit", "stability_cycle"]:
        values = raw.get(family)
        if not isinstance(values, list) or len(values) < int(row["sample_count"]):
            fail(f"raw sample family {family} is incomplete")
        if any(isinstance(v, bool) or not isinstance(v, int) or v < 0 for v in values):
            fail(f"raw sample family {family} contains invalid values")
    if packet.get("evidence_appended") is not False:
        fail("profile packet must remain non-evidence until deliberate repository append")
    return row


def main() -> None:
    parser = argparse.ArgumentParser(description="Validate and deliberately ingest a source-pinned real Deck-class T8-44 profile packet.")
    parser.add_argument("--packet", type=Path, required=True)
    parser.add_argument("--expected-source-head", required=True)
    parser.add_argument("--evidence-root", type=Path, default=ROOT / "empirical/evidence")
    parser.add_argument("--append", action="store_true")
    args = parser.parse_args()

    expected = validate_sha(args.expected_source_head, "--expected-source-head")
    packet = load_json(args.packet)
    row = validate_packet(packet, expected)

    temp_jsonl = args.packet.with_suffix(args.packet.suffix + ".validated.jsonl")
    try:
        temp_jsonl.write_text(json.dumps(row, sort_keys=True, ensure_ascii=False) + "\n", encoding="utf-8")
        command = [
            sys.executable,
            str(COLLECTOR),
            "--input", str(temp_jsonl),
            "--evidence-root", str(args.evidence_root),
        ]
        if args.append:
            command.append("--append")
        completed = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, check=False)
        if completed.returncode != 0:
            fail((completed.stdout + completed.stderr).strip() or "collector rejected validated row")
        result = json.loads(completed.stdout)
    finally:
        temp_jsonl.unlink(missing_ok=True)

    print(json.dumps({
        "status": "APPENDED" if args.append else "VALIDATED_DRY_RUN",
        "source_head": expected,
        "hardware_id": row["hardware_id"],
        "build_id": row["build_id"],
        "dossier_id": row["dossier_id"],
        "sample_count": row["sample_count"],
        "collector": result,
        "gate_disposition_inferred": False,
    }, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
