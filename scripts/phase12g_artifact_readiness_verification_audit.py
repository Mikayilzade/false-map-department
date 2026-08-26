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
SCRIPTS = ROOT / "scripts"
COLLECTOR = SCRIPTS / "phase12g_collect_completed_rows.py"
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))
import phase12g_build_artifact_contract as artifact_contract

FORCE_CHANNEL_ENV = "FMD_PHASE12G_REQUIRE_CANONICAL_ACQUISITION_CHANNEL"
FORCE_ARTIFACT_ENV = "FMD_PHASE12G_REQUIRE_BUILD_ARTIFACT_BYTES"


def fail(message: str) -> None:
    raise SystemExit(f"PHASE12G ARTIFACT READINESS VERIFICATION AUDIT FAIL: {message}")


def run_collector(root: Path, name: str, row: dict, *, record: Path | None, artifact: Path | None, expect_ok: bool, expected_text: str = "") -> dict | None:
    input_path = root / f"{name}.jsonl"
    evidence_root = root / f"evidence-{name}"
    input_path.write_text(json.dumps(row, sort_keys=True) + "\n", encoding="utf-8")
    env = os.environ.copy()
    env[FORCE_CHANNEL_ENV] = "1"
    env[FORCE_ARTIFACT_ENV] = "1"
    if record is None:
        env.pop("FMD_PHASE12G_BUILD_ARTIFACT_RECORD", None)
    else:
        env["FMD_PHASE12G_BUILD_ARTIFACT_RECORD"] = str(record)
    if artifact is None:
        env.pop("FMD_PHASE12G_BUILD_ARTIFACT_PATH", None)
    else:
        env["FMD_PHASE12G_BUILD_ARTIFACT_PATH"] = str(artifact)
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
        fail(f"{name}: expected rejection but dry-run reported success")
    if expected_text and expected_text not in output:
        fail(f"{name}: expected diagnostic containing {expected_text!r}, got: {output}")
    if not expect_ok:
        return None
    try:
        return json.loads(completed.stdout)
    except json.JSONDecodeError as exc:
        fail(f"{name}: success output was not JSON: {exc}")


def make_e2_row(record: dict) -> dict:
    return {
        "schema_version": 1,
        "gate_id": "E2",
        "tester_id": "T01",
        "naive": True,
        "session_id": "S01",
        "packet_completed": True,
        "prediction_prompt_id": "DEMO02_PRE_EDIT_SECOND_ORDER_01",
        "success": True,
        "acquisition_channel": "human_field_kit_v4",
        "source_head": record["source_head"],
        "source_build_id": record["build_id"],
        "source_build_role": record["role"],
        "build_artifact_sha256": record["artifact_sha256"],
        "build_artifact_bytes": record["artifact_bytes"],
        "build_artifact_binding_id": record["binding_id"],
        "build_artifact_filename": record["artifact_filename"],
        "build_artifact_bytes_verified": True,
    }


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="fmd-phase12g-artifact-readiness-") as tmp:
        root = Path(tmp)
        artifact = root / "demo-build.zip"
        artifact.write_bytes(b"synthetic packaged build bytes for readiness audit\n")
        record = artifact_contract.make_record(
            source_head="a" * 40,
            role="demo",
            build_id="BUILD_A",
            artifact_path=artifact,
        )
        record_path = root / "artifact-record.json"
        record_path.write_text(json.dumps(record, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        row = make_e2_row(record)

        missing_env = run_collector(root, "missing-env", row, record=None, artifact=None, expect_ok=True)
        if missing_env is None or missing_env.get("append_ready") is not False or missing_env.get("build_artifact_bytes_verified") is not False:
            fail("dry-run without packaged-build inputs must report append_ready=false and bytes_verified=false")

        valid = run_collector(root, "valid-bytes", row, record=record_path, artifact=artifact, expect_ok=True)
        if valid is None or valid.get("append_ready") is not True or valid.get("build_artifact_bytes_verified") is not True:
            fail("dry-run with matching record + packaged bytes must verify them before reporting append_ready=true")

        tampered_artifact = root / "tampered-build.zip"
        tampered_artifact.write_bytes(artifact.read_bytes() + b"tamper")
        run_collector(
            root,
            "tampered-bytes",
            row,
            record=record_path,
            artifact=tampered_artifact,
            expect_ok=False,
            expected_text="packaged build artifact bytes do not match recorded digest/size",
        )

        conflicting_row = dict(row)
        conflicting_row["build_artifact_sha256"] = "b" * 64
        run_collector(
            root,
            "row-provenance-conflict",
            conflicting_row,
            record=record_path,
            artifact=artifact,
            expect_ok=False,
            expected_text="packaged build provenance conflict for build_artifact_sha256",
        )

        wrong_record = dict(record)
        wrong_record["source_head"] = "c" * 40
        unhashed = dict(wrong_record)
        unhashed.pop("binding_id", None)
        wrong_record["binding_id"] = artifact_contract.canonical_hash(unhashed)
        wrong_record_path = root / "wrong-record.json"
        wrong_record_path.write_text(json.dumps(wrong_record, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        run_collector(
            root,
            "wrong-source-record",
            row,
            record=wrong_record_path,
            artifact=artifact,
            expect_ok=False,
            expected_text="build artifact source_head mismatch",
        )

    print(
        "Phase 12G artifact readiness verification audit: PASS "
        "(dry-run append_ready requires actual record/packaged-byte verification; missing inputs stay not-ready; tamper/source/provenance conflicts reject; synthetic-only)"
    )


if __name__ == "__main__":
    main()
