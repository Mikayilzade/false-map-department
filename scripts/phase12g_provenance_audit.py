#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT_DIR = ROOT / "scripts"
COLLECTOR = SCRIPT_DIR / "phase12g_collect_completed_rows.py"

sys.path.insert(0, str(SCRIPT_DIR))
import phase12g_build_artifact_contract as artifact_contract  # noqa: E402
import phase12g_provenance as provenance  # noqa: E402

SOURCE = "1" * 40
BUILD = "BUILD-PROVENANCE-AUDIT"
CHANNEL = "audit_channel"


def fail(message: str) -> None:
    raise SystemExit(f"PHASE12G PROVENANCE AUDIT FAIL: {message}")


def expect(condition: bool, message: str) -> None:
    if not condition:
        fail(message)


def base_row(channel: str = CHANNEL) -> dict:
    return {
        "schema_version": 1,
        "gate_id": "E1",
        "tester_id": "AUDIT_TESTER",
        "naive": True,
        "session_id": "AUDIT_SESSION",
        "understood_within_seconds": 12,
        "success": True,
        "acquisition_channel": channel,
    }


def test_helper() -> dict:
    base = base_row()
    base.pop("acquisition_channel")
    enriched = provenance.enrich_row(base, source_head=SOURCE, build_id=BUILD, channel=CHANNEL)
    expect(enriched["source_head"] == SOURCE, "source_head was not persisted")
    expect(enriched["source_build_id"] == BUILD, "source_build_id was not persisted")
    expect(enriched["acquisition_channel"] == CHANNEL, "acquisition_channel was not persisted")
    expect(enriched["evidence_provenance_version"] == 2, "provenance version missing")
    expect(enriched["tester_id"] == base["tester_id"], "observation fields changed while enriching provenance")

    conflicted = dict(base)
    conflicted["source_head"] = "2" * 40
    try:
        provenance.enrich_row(conflicted, source_head=SOURCE, build_id=BUILD, channel=CHANNEL)
    except ValueError:
        pass
    else:
        fail("conflicting pre-existing source_head was accepted")

    for kwargs, label in [
        ({"source_head": "bad", "build_id": BUILD, "channel": CHANNEL}, "invalid source SHA"),
        ({"source_head": SOURCE, "build_id": "", "channel": CHANNEL}, "blank build ID"),
        ({"source_head": SOURCE, "build_id": BUILD, "channel": ""}, "blank channel"),
    ]:
        try:
            provenance.enrich_row(base, **kwargs)
        except ValueError:
            continue
        fail(f"{label} was accepted")
    return enriched


def test_collector_persistence(enriched: dict) -> None:
    with tempfile.TemporaryDirectory(prefix="fmd-phase12g-provenance-") as raw:
        root = Path(raw)
        input_path = root / "input.jsonl"
        evidence_root = root / "evidence"
        input_path.write_text(json.dumps(enriched, sort_keys=True) + "\n", encoding="utf-8")
        completed = subprocess.run(
            [sys.executable, str(COLLECTOR), "--input", str(input_path), "--evidence-root", str(evidence_root), "--append"],
            cwd=ROOT,
            text=True,
            capture_output=True,
        )
        expect(completed.returncode == 0, f"collector rejected enriched audit row: {(completed.stdout + completed.stderr).strip()}")
        target = evidence_root / "E1.jsonl"
        expect(target.is_file(), "collector did not create temporary evidence target")
        rows = [json.loads(line) for line in target.read_text(encoding="utf-8").splitlines() if line.strip()]
        expect(len(rows) == 1, "temporary append did not preserve exactly one row")
        stored = rows[0]
        for key in ["source_head", "source_build_id", "acquisition_channel", "evidence_provenance_version"]:
            expect(stored.get(key) == enriched.get(key), f"collector lost provenance field {key}")


def test_external_artifact_binding() -> None:
    with tempfile.TemporaryDirectory(prefix="fmd-phase12g-build-bytes-") as raw:
        root = Path(raw)
        artifact = root / "demo-build.pck"
        artifact.write_bytes(b"immutable-demo-build-bytes\x00v1")
        record_path = root / "artifact-record.json"
        record = artifact_contract.make_record(source_head=SOURCE, role="demo", build_id=BUILD, artifact_path=artifact)
        record_path.write_text(json.dumps(record, sort_keys=True) + "\n", encoding="utf-8")

        old_record = os.environ.get(provenance.ARTIFACT_RECORD_ENV)
        old_artifact = os.environ.get(provenance.ARTIFACT_PATH_ENV)
        try:
            os.environ[provenance.ARTIFACT_RECORD_ENV] = str(record_path)
            os.environ[provenance.ARTIFACT_PATH_ENV] = str(artifact)
            raw_row = base_row("human_field_kit_v4")
            raw_row.pop("acquisition_channel")
            enriched = provenance.enrich_row(raw_row, source_head=SOURCE, build_id=BUILD, channel="human_field_kit_v4")
        finally:
            if old_record is None:
                os.environ.pop(provenance.ARTIFACT_RECORD_ENV, None)
            else:
                os.environ[provenance.ARTIFACT_RECORD_ENV] = old_record
            if old_artifact is None:
                os.environ.pop(provenance.ARTIFACT_PATH_ENV, None)
            else:
                os.environ[provenance.ARTIFACT_PATH_ENV] = old_artifact

        expect(enriched.get("build_artifact_bytes_verified") is True, "external provenance did not verify packaged bytes")
        expect(enriched.get("source_build_role") == "demo", "external provenance lost build role")
        expect(enriched.get("build_artifact_sha256") == record["artifact_sha256"], "external provenance lost artifact digest")

        input_path = root / "external.jsonl"
        input_path.write_text(json.dumps(enriched, sort_keys=True) + "\n", encoding="utf-8")
        evidence_root = root / "evidence"
        force_env = {key: value for key, value in os.environ.items() if key not in {provenance.ARTIFACT_RECORD_ENV, provenance.ARTIFACT_PATH_ENV}}
        force_env["FMD_PHASE12G_REQUIRE_BUILD_ARTIFACT_BYTES"] = "1"
        without_env = subprocess.run(
            [sys.executable, str(COLLECTOR), "--input", str(input_path), "--evidence-root", str(evidence_root), "--append"],
            cwd=ROOT,
            text=True,
            capture_output=True,
            env=force_env,
        )
        expect(without_env.returncode != 0, "external append accepted source_build_id without packaged artifact bytes")
        expect(not (evidence_root / "E1.jsonl").exists(), "failed external append mutated evidence")

        bound_env = dict(os.environ)
        bound_env[provenance.ARTIFACT_RECORD_ENV] = str(record_path)
        bound_env[provenance.ARTIFACT_PATH_ENV] = str(artifact)
        bound_env["FMD_PHASE12G_REQUIRE_BUILD_ARTIFACT_BYTES"] = "1"
        with_env = subprocess.run(
            [sys.executable, str(COLLECTOR), "--input", str(input_path), "--evidence-root", str(evidence_root), "--append"],
            cwd=ROOT,
            text=True,
            capture_output=True,
            env=bound_env,
        )
        expect(with_env.returncode == 0, f"byte-bound external append rejected: {(with_env.stdout + with_env.stderr).strip()}")
        expect((evidence_root / "E1.jsonl").is_file(), "byte-bound external append did not persist evidence")

        artifact.write_bytes(b"tampered-packaged-build")
        tampered_root = root / "tampered-evidence"
        tampered = subprocess.run(
            [sys.executable, str(COLLECTOR), "--input", str(input_path), "--evidence-root", str(tampered_root), "--append"],
            cwd=ROOT,
            text=True,
            capture_output=True,
            env=bound_env,
        )
        expect(tampered.returncode != 0, "collector accepted packaged build bytes after digest-changing tamper")
        expect(not (tampered_root / "E1.jsonl").exists(), "tampered build append mutated evidence")


def test_ingest_wiring() -> None:
    required = {
        "phase12g_field_kit_ingest.py": ["phase12g_provenance", "human_field_kit_v4", "provenance_persisted_in_rows"],
        "phase12g_marketing_expectation_ingest.py": ["phase12g_provenance", "e8_marketing_packet", "provenance_persisted_in_rows"],
        "phase12g_reference_profile_ingest.py": ["phase12g_provenance", "t8_reference_profile", "provenance_persisted_in_rows"],
    }
    for name, markers in required.items():
        text = (SCRIPT_DIR / name).read_text(encoding="utf-8")
        missing = [marker for marker in markers if marker not in text]
        expect(not missing, f"{name} missing provenance wiring markers: {missing}")


def main() -> None:
    enriched = test_helper()
    test_collector_persistence(enriched)
    test_external_artifact_binding()
    test_ingest_wiring()
    print("Phase 12G evidence provenance audit: PASS (external append requires exact packaged build bytes; source/build/channel/digest persist)")


if __name__ == "__main__":
    main()
