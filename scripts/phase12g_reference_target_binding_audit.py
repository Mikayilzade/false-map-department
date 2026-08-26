#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT_DIR = ROOT / "scripts"
SOURCE = subprocess.run(
    ["git", "rev-parse", "--verify", "HEAD"],
    cwd=ROOT,
    capture_output=True,
    text=True,
    check=True,
).stdout.strip().lower()
sys.path.insert(0, str(SCRIPT_DIR))

import phase12g_audit_build_fixture as build_fixture  # noqa: E402
import phase12g_reference_profile_build_bind as build_binding  # noqa: E402
import phase12g_reference_profile_target as target  # noqa: E402

INGEST = SCRIPT_DIR / "phase12g_reference_profile_ingest.py"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"PHASE12G T8-44 TARGET AUDIT FAIL: {message}")


def expect_target_rejection(dossier_id: str, marker: str) -> None:
    try:
        target.validate_reference_target(dossier_id)
    except ValueError as exc:
        require(marker in str(exc), f"{dossier_id} rejection must name {marker}: {exc}")
        return
    require(False, f"nonrepresentative T8 target unexpectedly accepted: {dossier_id}")


def load_ingest_module():
    spec = importlib.util.spec_from_file_location("phase12g_reference_profile_ingest_target_audit", INGEST)
    require(spec is not None and spec.loader is not None, "unable to load T8 ingest module")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def packet(dossier_id: str) -> dict:
    return {
        "packet_version": 1,
        "source_head": SOURCE,
        "hardware_attestation": "synthetic_audit",
        "profiling_disposition": "audit_fixture",
        "profile_row": {
            "schema_version": 1,
            "gate_id": "T8-44",
            "hardware_id": "AUDIT-HW",
            "build_id": "AUDIT-BUILD",
            "dossier_id": dossier_id,
            "sample_count": 3,
            "typical_edit_median_ms": 1.0,
            "typical_edit_p95_ms": 2.0,
            "late_game_edit_p99_ms": 3.0,
            "stability_cycle_p95_ms": 4.0,
            "profiling_disposition": "audit_fixture",
        },
        "raw_samples_us": {
            "typical_edit": [1000, 1000, 2000],
            "late_game_edit": [2000, 3000, 3000],
            "stability_cycle": [3000, 4000, 4000],
        },
        "evidence_appended": False,
        "synthetic_audit_only": True,
    }


def main() -> None:
    require(len(SOURCE) == 40, "checkout source must be an exact Git SHA")

    d38 = target.validate_reference_target("D38")
    d39 = target.validate_reference_target("D39")
    require(d38["act_index"] == 5 and d38["stability_required_cycles"] == 2, "D38 must remain a valid Act V multi-cycle reference target")
    require(d39["act_index"] == 5 and d39["stability_required_cycles"] == 5, "D39 must remain a valid Act V five-cycle reference target")
    require(d38["temporal_transition_count"] >= 1 and d39["temporal_transition_count"] >= 1, "accepted targets must carry canonical non-idle Stability transition evidence")

    expect_target_rejection("D01", "Act V")
    expect_target_rejection("D37", "multi-cycle Stability")
    expect_target_rejection("D40", "multi-cycle Stability")
    expect_target_rejection("../D39", "canonical campaign dossier ID")
    expect_target_rejection("NOT_A_DOSSIER", "canonical campaign dossier ID")

    ingest = load_ingest_module()
    accepted = ingest.validate_packet(packet("D39"), SOURCE, allow_audit_fixture=True)
    require(accepted["dossier_id"] == "D39", "metrics-only audit path must still accept representative D39")
    try:
        ingest.validate_packet(packet("D01"), SOURCE, allow_audit_fixture=True)
    except SystemExit as exc:
        require("reference target invalid" in str(exc) and "Act V" in str(exc), "ingest must fail closed on early-game caller-controlled dossier_id")
    else:
        require(False, "T8 ingest accepted early-game D01 as representative reference evidence")

    with tempfile.TemporaryDirectory(prefix="fmd-t8-target-audit-") as raw:
        temp = Path(raw)
        artifact, record = build_fixture.create_bound_artifact(
            temp / "build",
            source_head=SOURCE,
            role="production",
            build_id="AUDIT-BUILD",
        )
        packet_root = temp / "packet"
        build_binding.prepare(
            packet_root,
            source_head=SOURCE,
            build_id="AUDIT-BUILD",
            artifact=artifact,
            record=record,
        )

        invalid_path = packet_root / "invalid-profile.json"
        invalid_path.write_text(json.dumps(packet("D37"), indent=2, sort_keys=True) + "\n", encoding="utf-8")
        try:
            build_binding.seal(invalid_path)
        except ValueError as exc:
            require("multi-cycle Stability" in str(exc), "sealing must reject an Act V dossier that cannot produce the row's Stability samples")
        else:
            require(False, "T8 sealing accepted non-Stability D37")
        invalid_payload = json.loads(invalid_path.read_text(encoding="utf-8"))
        require(int(invalid_payload.get("packet_version", 0)) == 1, "failed target validation must not upgrade packet_version")
        require("reference_capture_binding" not in invalid_payload, "failed target validation must not seal capture identity")

        valid_path = packet_root / "valid-profile.json"
        valid_path.write_text(json.dumps(packet("D38"), indent=2, sort_keys=True) + "\n", encoding="utf-8")
        build_binding.seal(valid_path)
        valid_payload = json.loads(valid_path.read_text(encoding="utf-8"))
        target_contract = valid_payload.get("reference_target_contract", {})
        require(target_contract.get("dossier_id") == "D38", "sealed packet must persist canonical representative target contract")
        require(target_contract.get("stability_required_cycles") == 2, "sealed target contract must preserve canonical Stability cycles")
        build_binding.verify_sealed(valid_path, valid_payload)

    print(
        "Phase 12G T8-44 representative-target audit: PASS "
        "(D38/D39 accepted; early-game/non-Stability/path-like IDs rejected at target validation; "
        "sealing fails closed before capture binding; representative target contract persists in sealed packet; no evidence appended)"
    )


if __name__ == "__main__":
    main()
