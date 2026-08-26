#!/usr/bin/env python3
from __future__ import annotations

# Synthetic integrity audit only. It must never append empirical evidence or alter gate dispositions.

import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
COLLECTOR = ROOT / "scripts/phase12g_collect_completed_rows.py"
FORCE_CHANNEL_ENV = "FMD_PHASE12G_REQUIRE_CANONICAL_ACQUISITION_CHANNEL"


def fail(message: str) -> None:
    raise SystemExit(f"PHASE12G ACQUISITION CHANNEL BINDING AUDIT FAIL: {message}")


def run_case(root: Path, name: str, row: dict, expect_ok: bool, expected_text: str = "") -> dict | None:
    input_path = root / f"{name}.jsonl"
    evidence_root = root / f"evidence-{name}"
    input_path.write_text(json.dumps(row, sort_keys=True) + "\n", encoding="utf-8")
    env = os.environ.copy()
    env[FORCE_CHANNEL_ENV] = "1"
    completed = subprocess.run(
        [sys.executable, str(COLLECTOR), "--input", str(input_path), "--evidence-root", str(evidence_root)],
        cwd=ROOT,
        env=env,
        text=True,
        capture_output=True,
        check=False,
    )
    output = (completed.stdout + completed.stderr).strip()
    if expect_ok and completed.returncode != 0:
        fail(f"{name}: expected success, got rc={completed.returncode}: {output}")
    if not expect_ok and completed.returncode == 0:
        fail(f"{name}: expected rejection but collector accepted row")
    if expected_text and expected_text not in output:
        fail(f"{name}: expected diagnostic containing {expected_text!r}, got: {output}")
    if not expect_ok:
        return None
    try:
        payload = json.loads(completed.stdout)
    except json.JSONDecodeError as exc:
        fail(f"{name}: collector success output was not JSON: {exc}")
    return payload


def base_provenance(channel: str) -> dict:
    return {
        "acquisition_channel": channel,
        "source_head": "a" * 40,
        "source_build_id": "BUILD_A",
        "source_build_role": "demo",
        "build_artifact_sha256": "b" * 64,
        "build_artifact_bytes": 123,
        "build_artifact_binding_id": "binding-a",
        "build_artifact_filename": "build.zip",
        "build_artifact_bytes_verified": True,
    }


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="fmd-phase12g-channel-audit-") as tmp:
        root = Path(tmp)

        valid_e2 = {
            "schema_version": 1,
            "gate_id": "E2",
            "tester_id": "T01",
            "naive": True,
            "session_id": "S01",
            "packet_completed": True,
            "prediction_prompt_id": "DEMO02_PRE_EDIT_SECOND_ORDER_01",
            "success": True,
            **base_provenance("human_field_kit_v4"),
        }
        result = run_case(root, "valid-e2", valid_e2, True)
        if result is None or result.get("canonical_acquisition_channel_checked") is not True:
            fail("valid E2 did not report canonical acquisition-channel enforcement")

        missing_channel = dict(valid_e2)
        missing_channel.pop("acquisition_channel")
        run_case(root, "missing-e2-channel", missing_channel, False, "must be human_field_kit_v4")

        relabeled_e2 = dict(valid_e2)
        relabeled_e2["acquisition_channel"] = "manual_observation"
        run_case(root, "relabeled-e2-channel", relabeled_e2, False, "cannot bypass provenance safeguards")

        valid_e8 = {
            "gate_id": "E8",
            "respondent_id": "R01",
            "asset_version": "ASSET_A",
            "expected_play_category": "systemic puzzle",
            "freeform_builder_expectation": False,
            "notes": "synthetic audit fixture only",
            **base_provenance("e8_marketing_packet"),
        }
        valid_e8["source_build_role"] = "production"
        run_case(root, "valid-e8", valid_e8, True)
        spoofed_e8 = dict(valid_e8)
        spoofed_e8["acquisition_channel"] = "human_field_kit_v4"
        run_case(root, "spoofed-e8", spoofed_e8, False, "must be e8_marketing_packet")

        valid_t8 = {
            "gate_id": "T8-44",
            "hardware_id": "DECK-AUDIT",
            "build_id": "BUILD_A",
            "dossier_id": "D40",
            "sample_count": 1,
            "typical_edit_median_ms": 1.0,
            "typical_edit_p95_ms": 1.0,
            "late_game_edit_p99_ms": 1.0,
            "stability_cycle_p95_ms": 1.0,
            "profiling_disposition": "reference_run",
            **base_provenance("t8_reference_profile"),
        }
        valid_t8["source_build_role"] = "production"
        run_case(root, "valid-t8", valid_t8, True)
        spoofed_t8 = dict(valid_t8)
        spoofed_t8["acquisition_channel"] = "diagnostic_profile"
        run_case(root, "spoofed-t8", spoofed_t8, False, "must be t8_reference_profile")

        e7 = {
            "gate_id": "E7",
            "dossier_id": "D01",
            "device_mode": "keyboard_only",
            "ui_scale": 1.0,
            "reduced_motion": False,
            "non_color": False,
            "no_audio": False,
            "interaction_complete": True,
            "capture_review_pass": True,
        }
        e7_result = run_case(root, "e7-unaffected", e7, True)
        if e7_result is None or e7_result.get("canonical_acquisition_channel_checked") is not False:
            fail("E7 should remain outside external acquisition-channel enforcement")

    print(
        "Phase 12G acquisition channel binding audit: PASS "
        "(external human/E8/T8 rows cannot remove or relabel acquisition_channel to bypass qualification/build provenance; E7 unaffected; synthetic-only)"
    )


if __name__ == "__main__":
    main()
