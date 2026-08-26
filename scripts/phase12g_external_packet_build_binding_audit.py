#!/usr/bin/env python3
from __future__ import annotations

import copy
import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT_DIR = ROOT / "scripts"
sys.path.insert(0, str(SCRIPT_DIR))

import phase12g_audit_build_fixture as build_fixture  # noqa: E402
import phase12g_e8_acquisition_build_bind as e8_binding  # noqa: E402
import phase12g_marketing_completion_receipt as e8_receipt  # noqa: E402
import phase12g_marketing_expectation_packet as e8_packet  # noqa: E402
import phase12g_reference_profile_build_bind as t8_binding  # noqa: E402
import phase12g_reference_profile_ingest as t8_ingest  # noqa: E402

SOURCE = subprocess.run(["git", "rev-parse", "--verify", "HEAD"], cwd=ROOT, capture_output=True, text=True, check=True).stdout.strip().lower()


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"PHASE12G EXTERNAL PACKET BUILD BINDING AUDIT FAIL: {message}")


def expect_error(fn, marker: str) -> None:
    try:
        fn()
    except (SystemExit, ValueError, OSError, json.JSONDecodeError) as exc:
        require(marker.lower() in str(exc).lower(), f"rejection should mention {marker!r}: {exc}")
        return
    require(False, f"expected rejection did not occur: {marker}")


def make_assets(root: Path) -> list[str]:
    specs = [
        ("store_key_art", ".png"),
        ("gameplay_map_world", ".png"),
        ("gameplay_consequence", ".png"),
        ("late_game_linked", ".png"),
        ("trailer", ".webm"),
    ]
    args: list[str] = []
    for role, suffix in specs:
        path = root / f"{role}{suffix}"
        path.write_bytes(f"SYNTHETIC-NON-EVIDENCE-{role}\n".encode())
        args += ["--asset", f"{role}={path}"]
    return args


def run_packet(args: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run([sys.executable, str(SCRIPT_DIR / "phase12g_marketing_expectation_packet.py"), *args], cwd=ROOT, text=True, capture_output=True, check=False)


def prepare_e8(root: Path, media: Path, artifact: Path, record: Path) -> None:
    command = [
        sys.executable, str(SCRIPT_DIR / "phase12g_marketing_acquisition_prepare.py"),
        "--asset-version", "AUDIT-E8-BYTEBOUND",
        "--build-id", "AUDIT-PROD",
        "--source-head", SOURCE,
        *make_assets(media),
        "--respondents", "1",
        "--production-build-artifact", str(artifact),
        "--production-build-artifact-record", str(record),
        "--output", str(root),
    ]
    completed = subprocess.run(command, cwd=ROOT, text=True, capture_output=True, check=False)
    require(completed.returncode == 0, f"byte-bound E8 preparation failed: {completed.stdout}{completed.stderr}")


def t8_fixture(build_id: str = "AUDIT-PROD") -> dict:
    return {
        "packet_version": 1,
        "source_head": SOURCE,
        "hardware_attestation": "synthetic_audit",
        "profiling_disposition": "audit_fixture",
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
    require(len(SOURCE) == 40, "checkout must resolve exact source SHA")
    with tempfile.TemporaryDirectory(prefix="fmd-external-byte-binding-") as raw:
        temp = Path(raw)
        artifact, record = build_fixture.create_bound_artifact(temp / "build", source_head=SOURCE, role="production", build_id="AUDIT-PROD")

        # E8 real-acquisition preparation freezes package bytes before any response.
        e8_root = temp / "e8"
        media = temp / "media"
        media.mkdir()
        prepare_e8(e8_root, media, artifact, record)
        asset_set, respondents = e8_packet.load_and_verify_packet(e8_root)
        binding = e8_binding.verify_packet_binding(e8_root, asset_set, respondents)
        require(binding["artifact_sha256"] and binding["binding_id"], "E8 packet must expose central package binding")
        require(asset_set.get("acquisition_build_bytes_required") is True, "E8 immutable manifest must require package bytes")

        rows = respondents["rows"]
        rows[0].update({
            "expected_play_category": "systemic puzzle",
            "freeform_builder_expectation": False,
            "notes": "synthetic integrity fixture only; not market evidence",
        })
        (e8_root / "respondents.json").write_text(json.dumps(respondents, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        finalized = run_packet(["finalize", "--packet", str(e8_root)])
        require(finalized.returncode == 0, f"bound E8 packet must finalize: {finalized.stdout}{finalized.stderr}")
        receipt_result = e8_receipt.verify_receipt(e8_root, asset_set, respondents, e8_root / "completed-E8.jsonl")
        require(receipt_result.get("ok") is True and receipt_result.get("build_binding_id") == binding["binding_id"], "E8 receipt must bind exact package")

        receipt_path = e8_root / e8_receipt.RECEIPT_FILENAME
        receipt_payload = json.loads(receipt_path.read_text(encoding="utf-8"))
        receipt_payload["acquisition_build_binding"]["artifact_sha256"] = "0" * 64
        receipt_path.write_text(json.dumps(receipt_payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        rejected_receipt = e8_receipt.verify_receipt(e8_root, asset_set, respondents, e8_root / "completed-E8.jsonl")
        require(rejected_receipt.get("ok") is False and "build_binding" in str(rejected_receipt.get("code", "")), "E8 receipt binding tamper must fail closed")

        # A fresh E8 packet rejects package-byte drift and wrong role/build records.
        drift_root = temp / "e8-drift"
        drift_media = temp / "media-drift"
        drift_media.mkdir()
        prepare_e8(drift_root, drift_media, artifact, record)
        frozen = drift_root / binding["packet_artifact_path"]
        frozen.write_bytes(frozen.read_bytes() + b"DRIFT")
        expect_error(lambda: e8_binding.verify_packet_binding(drift_root), "artifact")
        wrong_artifact, wrong_record = build_fixture.create_bound_artifact(temp / "wrong", source_head=SOURCE, role="demo", build_id="AUDIT-PROD")
        raw_root = temp / "e8-wrong-role"
        proc = run_packet([
            "prepare", "--asset-version", "AUDIT-WRONG", "--build-id", "AUDIT-PROD", "--source-head", SOURCE,
            *make_assets(temp / "wrong-media"), "--representative-attestation", "--respondents", "1", "--output", str(raw_root),
        ])
        require(proc.returncode == 0, "low-level E8 packet fixture should prepare")
        expect_error(lambda: e8_binding.bind_packet(raw_root, wrong_artifact, wrong_record), "role")

        # T8 binding exists before timing packet and the sealed result must retain it.
        t8_root = temp / "t8"
        t8_snapshot = t8_binding.prepare(t8_root, source_head=SOURCE, build_id="AUDIT-PROD", artifact=artifact, record=record)
        t8_path = t8_root / "profile.json"
        t8_path.write_text(json.dumps(t8_fixture(), indent=2, sort_keys=True) + "\n", encoding="utf-8")
        sealed = t8_binding.seal(t8_path)
        require(sealed["binding_id"] == t8_snapshot["binding_id"], "T8 seal must retain pre-acquisition package binding")
        packet = json.loads(t8_path.read_text(encoding="utf-8"))
        row = t8_ingest.validate_packet(packet, SOURCE, allow_audit_fixture=True, packet_path=t8_path)
        require(row["t8_build_binding"]["artifact_sha256"] == t8_snapshot["artifact_sha256"], "T8 validation must persist exact package digest")

        frozen_t8 = t8_root / t8_snapshot["packet_artifact_path"]
        frozen_t8.write_bytes(frozen_t8.read_bytes() + b"POST-SESSION-SUBSTITUTION")
        expect_error(lambda: t8_binding.verify_sealed(t8_path), "artifact")

        mismatch_root = temp / "t8-mismatch"
        other_artifact, other_record = build_fixture.create_bound_artifact(temp / "other", source_head=SOURCE, role="production", build_id="OTHER-BUILD")
        expect_error(lambda: t8_binding.prepare(mismatch_root, source_head=SOURCE, build_id="AUDIT-PROD", artifact=other_artifact, record=other_record), "build")

    print("Phase 12G external packet packaged-byte binding audit: PASS (E8 packet/receipt + T8 pre-run/sealed packet exact production bytes; drift/substitution/role/build/binding tamper rejected; synthetic fixtures are non-evidence)")


if __name__ == "__main__":
    main()
