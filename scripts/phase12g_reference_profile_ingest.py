#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import math
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT_DIR = Path(__file__).resolve().parent
COLLECTOR = ROOT / "scripts/phase12g_collect_completed_rows.py"
REFERENCE_ATTESTATION = "actual_deck_class_reference"

sys.path.insert(0, str(SCRIPT_DIR))
import phase12g_provenance as provenance  # noqa: E402
import phase12g_reference_profile_build_bind as profile_build_binding  # noqa: E402


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


def repository_checkout_head() -> str:
    completed = subprocess.run(
        ["git", "rev-parse", "--verify", "HEAD"],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )
    if completed.returncode != 0:
        fail("unable to resolve repository checkout HEAD")
    return validate_sha(completed.stdout.strip(), "repository checkout HEAD")


def percentile_ms(samples_us: list[int], fraction: float) -> float:
    values = sorted(samples_us)
    index = max(0, min(len(values) - 1, math.ceil(fraction * len(values)) - 1))
    return values[index] / 1000.0


def require_metric_match(row: dict, field: str, expected: float) -> None:
    actual = float(row[field])
    if not math.isclose(actual, expected, rel_tol=0.0, abs_tol=1e-9):
        fail(f"{field} does not match raw_samples_us: claimed {actual}, recomputed {expected}")


def validate_packet(packet: dict, expected_source_head: str, allow_audit_fixture: bool = False, packet_path: Path | None = None) -> dict:
    expected_version = 1 if allow_audit_fixture and packet_path is None else 2
    if int(packet.get("packet_version", 0)) != expected_version:
        fail(f"unsupported packet_version; expected {expected_version}")
    expected = validate_sha(expected_source_head, "expected source_head")
    checkout_head = repository_checkout_head()
    if checkout_head != expected:
        fail(f"repository checkout HEAD mismatch: expected packet source checkout {expected}, got {checkout_head}")
    packet_source = validate_sha(str(packet.get("source_head", "")), "packet source_head")
    if packet_source != expected:
        fail(f"packet source_head mismatch: expected {expected}, got {packet_source}")

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
    sample_count = int(row["sample_count"])
    samples_by_family: dict[str, list[int]] = {}
    for family in ["typical_edit", "late_game_edit", "stability_cycle"]:
        values = raw.get(family)
        if not isinstance(values, list) or len(values) != sample_count:
            fail(f"raw sample family {family} must contain exactly sample_count values")
        if any(isinstance(v, bool) or not isinstance(v, int) or v < 0 for v in values):
            fail(f"raw sample family {family} contains invalid values")
        samples_by_family[family] = list(values)

    typical = samples_by_family["typical_edit"]
    late = samples_by_family["late_game_edit"]
    stability = samples_by_family["stability_cycle"]
    require_metric_match(row, "typical_edit_median_ms", percentile_ms(typical, 0.50))
    require_metric_match(row, "typical_edit_p95_ms", percentile_ms(typical, 0.95))
    require_metric_match(row, "late_game_edit_p99_ms", percentile_ms(late, 0.99))
    require_metric_match(row, "stability_cycle_p95_ms", percentile_ms(stability, 0.95))

    if packet.get("evidence_appended") is not False:
        fail("profile packet must remain non-evidence until deliberate repository append")
    if packet_path is not None:
        try:
            binding = profile_build_binding.verify_sealed(packet_path, packet)
        except (OSError, ValueError, json.JSONDecodeError) as exc:
            fail(f"packaged build acquisition binding invalid: {exc}")
        row = dict(row)
        row["t8_build_binding"] = {
            "binding_id": binding["binding_id"],
            "artifact_sha256": binding["artifact_sha256"],
            "artifact_bytes": binding["artifact_bytes"],
            "artifact_filename": binding["artifact_filename"],
            "role": binding["role"],
        }
    return row


def main() -> None:
    parser = argparse.ArgumentParser(description="Validate and deliberately ingest a source-pinned, packaged-build-bound real Deck-class T8-44 profile packet.")
    parser.add_argument("--packet", type=Path, required=True)
    parser.add_argument("--expected-source-head", required=True)
    parser.add_argument("--evidence-root", type=Path, default=ROOT / "empirical/evidence")
    parser.add_argument("--append", action="store_true")
    args = parser.parse_args()

    expected = validate_sha(args.expected_source_head, "--expected-source-head")
    packet_path = args.packet.resolve()
    packet = load_json(packet_path)
    row = validate_packet(packet, expected, packet_path=packet_path)
    try:
        row = provenance.enrich_row(
            row,
            source_head=expected,
            build_id=row.get("build_id", ""),
            channel="t8_reference_profile",
        )
    except ValueError as exc:
        fail(f"profile evidence provenance invalid: {exc}")

    temp_jsonl = packet_path.with_suffix(packet_path.suffix + ".validated.jsonl")
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

    binding = row["t8_build_binding"]
    print(json.dumps({
        "status": "APPENDED" if args.append else "VALIDATED_DRY_RUN",
        "source_head": expected,
        "repository_checkout_head": repository_checkout_head(),
        "hardware_id": row["hardware_id"],
        "build_id": row["build_id"],
        "dossier_id": row["dossier_id"],
        "sample_count": row["sample_count"],
        "build_binding_id": binding["binding_id"],
        "artifact_sha256": binding["artifact_sha256"],
        "artifact_bytes": binding["artifact_bytes"],
        "raw_summary_consistency_verified": True,
        "acquisition_build_bytes_verified": True,
        "provenance_persisted_in_rows": True,
        "collector": result,
        "gate_disposition_inferred": False,
    }, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
