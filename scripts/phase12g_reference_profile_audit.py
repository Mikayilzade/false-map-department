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
SCRIPT_DIR = ROOT / "scripts"
RUNNER = ROOT / "tests/phase12g_reference_profile_runner.gd"
INGEST = SCRIPT_DIR / "phase12g_reference_profile_ingest.py"
SOURCE = subprocess.run(["git", "rev-parse", "--verify", "HEAD"], cwd=ROOT, capture_output=True, text=True, check=True).stdout.strip().lower()
sys.path.insert(0, str(SCRIPT_DIR))
import phase12g_audit_build_fixture as build_fixture  # noqa: E402
import phase12g_reference_profile_build_bind as build_binding  # noqa: E402


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"PHASE12G T8-44 ACQUISITION AUDIT FAIL: {message}")


def load_ingest_module():
    spec = importlib.util.spec_from_file_location("phase12g_reference_profile_ingest_audit_module", INGEST)
    require(spec is not None and spec.loader is not None, "unable to load ingest module")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def fixture_packet(disposition: str, attestation: str, build_id: str = "AUDIT-BUILD") -> dict:
    return {
        "packet_version": 1,
        "source_head": SOURCE,
        "hardware_attestation": attestation,
        "profiling_disposition": disposition,
        "profile_row": {
            "schema_version": 1,
            "gate_id": "T8-44",
            "hardware_id": "AUDIT-HW",
            "build_id": build_id,
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
    require(len(SOURCE) == 40, "audit checkout source must resolve exact Git SHA")
    runner = RUNNER.read_text(encoding="utf-8")
    for marker in [
        "ProductionPlaytestController", "ReferenceHardwareProfiler", 'dossier_id = "D39"',
        "Time.get_ticks_usec()", 'disposition == "reference_run"',
        'attestation != "actual_deck_class_reference"', '"evidence_appended": false',
    ]:
        require(marker in runner, f"runner missing contract marker: {marker}")

    ingest_text = INGEST.read_text(encoding="utf-8")
    for marker in [
        'REFERENCE_ATTESTATION = "actual_deck_class_reference"',
        "phase12g_reference_profile_build_bind", "verify_sealed", "packet_path=packet_path",
        "raw_summary_consistency_verified", "acquisition_build_bytes_verified", "gate_disposition_inferred",
    ]:
        require(marker in ingest_text, f"ingest missing byte-bound contract marker: {marker}")

    module = load_ingest_module()
    require(module.repository_checkout_head() == SOURCE, "ingest must resolve actual test checkout HEAD")
    audit_packet = fixture_packet("audit_fixture", "synthetic_audit")
    audit_row = module.validate_packet(audit_packet, SOURCE, allow_audit_fixture=True)
    require(audit_row["gate_id"] == "T8-44", "unsealed synthetic helper path may validate metrics only for audit")

    tampered_metric = copy.deepcopy(audit_packet)
    tampered_metric["profile_row"]["typical_edit_p95_ms"] = 1.5
    expect_module_rejection(module, tampered_metric, "does not match raw_samples_us")
    extra_raw_sample = copy.deepcopy(audit_packet)
    extra_raw_sample["raw_samples_us"]["late_game_edit"].append(999999)
    expect_module_rejection(module, extra_raw_sample, "exactly sample_count values")

    wrong_expected = "0" * 40 if SOURCE != "0" * 40 else "1" * 40
    try:
        module.validate_packet(audit_packet, wrong_expected, allow_audit_fixture=True)
    except SystemExit as exc:
        require("repository checkout HEAD mismatch" in str(exc), "caller-supplied old SHA must fail against actual checkout")
    else:
        require(False, "caller-supplied old SHA bypassed actual checkout binding")

    with tempfile.TemporaryDirectory(prefix="fmd-t8-audit-") as raw:
        temp = Path(raw)
        artifact, record = build_fixture.create_bound_artifact(temp / "build", source_head=SOURCE, role="production", build_id="AUDIT-BUILD")
        packet_root = temp / "packet"
        snapshot = build_binding.prepare(packet_root, source_head=SOURCE, build_id="AUDIT-BUILD", artifact=artifact, record=record)
        packet_path = packet_root / "profile.json"
        packet_path.write_text(json.dumps(audit_packet, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        sealed = build_binding.seal(packet_path)
        require(sealed["binding_id"] == snapshot["binding_id"], "T8 seal must retain binding frozen before acquisition")
        sealed_packet = json.loads(packet_path.read_text(encoding="utf-8"))
        sealed_row = module.validate_packet(sealed_packet, SOURCE, allow_audit_fixture=True, packet_path=packet_path)
        require(sealed_row["t8_build_binding"]["artifact_sha256"] == snapshot["artifact_sha256"], "T8 validated row must carry acquisition-time package digest")

        frozen = packet_root / snapshot["packet_artifact_path"]
        frozen.write_bytes(frozen.read_bytes() + b"SUBSTITUTED-AFTER-SAMPLES")
        try:
            module.validate_packet(sealed_packet, SOURCE, allow_audit_fixture=True, packet_path=packet_path)
        except SystemExit as exc:
            require("packaged build acquisition binding invalid" in str(exc), "post-session substitution must fail at acquisition binding")
        else:
            require(False, "post-session packaged build substitution was accepted")

        unsealed = temp / "unsealed.json"
        reference_packet = fixture_packet("reference_run", "actual_deck_class_reference")
        unsealed.write_text(json.dumps(reference_packet, indent=2) + "\n", encoding="utf-8")
        rejected = subprocess.run(
            [sys.executable, str(INGEST), "--packet", str(unsealed), "--expected-source-head", SOURCE, "--evidence-root", str(temp / "evidence")],
            cwd=ROOT, capture_output=True, text=True, check=False,
        )
        require(rejected.returncode != 0 and "packet_version" in (rejected.stdout + rejected.stderr), "real reference ingest must reject an unsealed packet before evidence collection")
        require(not (temp / "evidence/T8-44.jsonl").exists(), "unsealed reference rejection must not mutate evidence")

        other_artifact, other_record = build_fixture.create_bound_artifact(temp / "wrong", source_head=SOURCE, role="demo", build_id="AUDIT-BUILD")
        try:
            build_binding.prepare(temp / "wrong-root", source_head=SOURCE, build_id="AUDIT-BUILD", artifact=other_artifact, record=other_record)
        except ValueError as exc:
            require("role" in str(exc), "T8 wrong-role package rejection must be explicit")
        else:
            require(False, "T8 accepted demo package as production reference package")

    print("Phase 12G T8-44 acquisition audit: PASS (actual checkout/source + raw-sample integrity + package bytes frozen before sample packet + sealed binding + post-session substitution/wrong-role/unsealed rejection; audit data never touched repository evidence)")


if __name__ == "__main__":
    main()
