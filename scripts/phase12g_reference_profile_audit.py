#!/usr/bin/env python3
from __future__ import annotations

import copy
import importlib.util
import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RUNNER = ROOT / "tests/phase12g_reference_profile_runner.gd"
INGEST = ROOT / "scripts/phase12g_reference_profile_ingest.py"
SOURCE = "a" * 40


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"PHASE12G T8-44 ACQUISITION AUDIT FAIL: {message}")


def load_ingest_module():
    spec = importlib.util.spec_from_file_location("phase12g_reference_profile_ingest", INGEST)
    require(spec is not None and spec.loader is not None, "unable to load ingest module")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def fixture_packet(disposition: str, attestation: str) -> dict:
    return {
        "packet_version": 1,
        "source_head": SOURCE,
        "hardware_attestation": attestation,
        "profiling_disposition": disposition,
        "profile_row": {
            "schema_version": 1,
            "gate_id": "T8-44",
            "hardware_id": "AUDIT-HW",
            "build_id": "AUDIT-BUILD",
            "dossier_id": "D39",
            "sample_count": 3,
            "typical_edit_median_ms": 1.0,
            "typical_edit_p95_ms": 2.0,
            "late_game_edit_p99_ms": 3.0,
            "stability_cycle_p95_ms": 4.0,
            "profiling_disposition": disposition,
        },
        "raw_samples_us": {
            "typical_edit": [1000, 1000, 2000],
            "late_game_edit": [2000, 3000, 3000],
            "stability_cycle": [3000, 4000, 4000],
        },
        "evidence_appended": False,
        "synthetic_audit_only": True,
    }


def expect_module_rejection(module, packet: dict, marker: str) -> None:
    try:
        module.validate_packet(packet, SOURCE, allow_audit_fixture=True)
    except SystemExit as exc:
        require(marker in str(exc), f"rejection must name integrity cause {marker}: {exc}")
        return
    require(False, f"tampered audit packet unexpectedly accepted: {marker}")


def main() -> None:
    runner = RUNNER.read_text(encoding="utf-8")
    for marker in [
        "ProductionPlaytestController",
        "ReferenceHardwareProfiler",
        'dossier_id = "D39"',
        "Time.get_ticks_usec()",
        'disposition == "reference_run"',
        'attestation != "actual_deck_class_reference"',
        '"evidence_appended": false',
    ]:
        require(marker in runner, f"runner missing contract marker: {marker}")

    ingest_text = INGEST.read_text(encoding="utf-8")
    for marker in [
        'REFERENCE_ATTESTATION = "actual_deck_class_reference"',
        'disposition != "reference_run"',
        "--expected-source-head",
        "--append",
        "percentile_ms",
        "require_metric_match",
        "raw_summary_consistency_verified",
        "gate_disposition_inferred",
    ]:
        require(marker in ingest_text, f"ingest missing contract marker: {marker}")

    module = load_ingest_module()
    audit_packet = fixture_packet("audit_fixture", "synthetic_audit")
    audit_row = module.validate_packet(audit_packet, SOURCE, allow_audit_fixture=True)
    require(audit_row["gate_id"] == "T8-44", "audit helper must preserve T8-44 identity")

    tampered_metric = copy.deepcopy(audit_packet)
    tampered_metric["profile_row"]["typical_edit_p95_ms"] = 1.5
    expect_module_rejection(module, tampered_metric, "does not match raw_samples_us")

    extra_raw_sample = copy.deepcopy(audit_packet)
    extra_raw_sample["raw_samples_us"]["late_game_edit"].append(999999)
    expect_module_rejection(module, extra_raw_sample, "exactly sample_count values")

    with tempfile.TemporaryDirectory(prefix="fmd-t8-audit-") as temp_dir:
        temp = Path(temp_dir)
        packet_path = temp / "packet.json"
        evidence_root = temp / "evidence"

        diagnostic = fixture_packet("diagnostic_run", "")
        packet_path.write_text(json.dumps(diagnostic, indent=2) + "\n", encoding="utf-8")
        rejected = subprocess.run(
            [sys.executable, str(INGEST), "--packet", str(packet_path), "--expected-source-head", SOURCE, "--evidence-root", str(evidence_root)],
            cwd=ROOT, capture_output=True, text=True, check=False,
        )
        require(rejected.returncode != 0, "diagnostic packet must never enter empirical evidence")
        require(not (evidence_root / "T8-44.jsonl").exists(), "diagnostic rejection must not mutate evidence")

        wrong_source = fixture_packet("reference_run", "actual_deck_class_reference")
        packet_path.write_text(json.dumps(wrong_source, indent=2) + "\n", encoding="utf-8")
        rejected_source = subprocess.run(
            [sys.executable, str(INGEST), "--packet", str(packet_path), "--expected-source-head", "b" * 40, "--evidence-root", str(evidence_root)],
            cwd=ROOT, capture_output=True, text=True, check=False,
        )
        require(rejected_source.returncode != 0, "wrong-source reference packet must reject")
        require(not (evidence_root / "T8-44.jsonl").exists(), "wrong-source rejection must not mutate evidence")

        tampered_reference = fixture_packet("reference_run", "actual_deck_class_reference")
        tampered_reference["profile_row"]["stability_cycle_p95_ms"] = 0.1
        packet_path.write_text(json.dumps(tampered_reference, indent=2) + "\n", encoding="utf-8")
        rejected_metric = subprocess.run(
            [sys.executable, str(INGEST), "--packet", str(packet_path), "--expected-source-head", SOURCE, "--evidence-root", str(evidence_root), "--append"],
            cwd=ROOT, capture_output=True, text=True, check=False,
        )
        require(rejected_metric.returncode != 0, "reference-attested packet with tampered summary must reject")
        require("does not match raw_samples_us" in (rejected_metric.stdout + rejected_metric.stderr), "tampered summary rejection must be explicit")
        require(not (evidence_root / "T8-44.jsonl").exists(), "tampered summary rejection must preserve evidence bytes")

    print("Phase 12G T8-44 acquisition audit: PASS (source pin + reference attestation + exact raw-sample cardinality + recomputed median/p95/p99 integrity + non-reference/tamper rejection; audit data never touched repository evidence)")


if __name__ == "__main__":
    main()
