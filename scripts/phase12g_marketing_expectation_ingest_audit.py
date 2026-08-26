#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT_DIR = ROOT / "scripts"
PREPARE = SCRIPT_DIR / "phase12g_marketing_acquisition_prepare.py"
PACKET = SCRIPT_DIR / "phase12g_marketing_expectation_packet.py"
INGEST = SCRIPT_DIR / "phase12g_marketing_expectation_ingest.py"
PROVENANCE_INTEGRITY = SCRIPT_DIR / "phase12g_e8_evidence_provenance_integrity.py"
SOURCE_HEAD = subprocess.run(["git", "rev-parse", "--verify", "HEAD"], cwd=ROOT, capture_output=True, text=True, check=True).stdout.strip().lower()
WRONG_HEAD = "0" * 40 if SOURCE_HEAD != "0" * 40 else "1" * 40
ROLES = (
    ("store_key_art", ".png"),
    ("gameplay_map_world", ".png"),
    ("gameplay_consequence", ".png"),
    ("late_game_linked", ".png"),
    ("trailer", ".mp4"),
)
sys.path.insert(0, str(SCRIPT_DIR))
import phase12g_audit_build_fixture as build_fixture  # noqa: E402


def run(args: list[str], expect_ok: bool = True, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(args, cwd=ROOT, text=True, capture_output=True, env=env)
    if expect_ok and result.returncode != 0:
        raise SystemExit(f"command failed: {' '.join(args)}\nstdout={result.stdout}\nstderr={result.stderr}")
    if not expect_ok and result.returncode == 0:
        raise SystemExit(f"command unexpectedly succeeded: {' '.join(args)}")
    return result


def evidence_rows(path: Path) -> list[dict]:
    if not path.exists():
        return []
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    digest.update(path.read_bytes())
    return digest.hexdigest()


def asset_args(root: Path) -> list[str]:
    root.mkdir(parents=True, exist_ok=True)
    args: list[str] = []
    for role, suffix in ROLES:
        path = root / f"{role}{suffix}"
        path.write_bytes((f"SYNTHETIC-AUDIT-ASSET:{role}\n").encode("utf-8"))
        args += ["--asset", f"{role}={path}"]
    return args


def prepare_bound(temp: Path, name: str, version: str, artifact: Path, record: Path, respondents: int = 2) -> Path:
    root = temp / name
    run([
        sys.executable, str(PREPARE),
        "--asset-version", version,
        "--build-id", "AUDIT-BUILD",
        "--source-head", SOURCE_HEAD,
        *asset_args(temp / f"{name}-media"),
        "--respondents", str(respondents),
        "--production-build-artifact", str(artifact),
        "--production-build-artifact-record", str(record),
        "--output", str(root),
    ])
    return root


def complete(root: Path) -> None:
    path = root / "respondents.json"
    packet = json.loads(path.read_text(encoding="utf-8"))
    for index, row in enumerate(packet["rows"]):
        row.update({
            "expected_play_category": "systemic puzzle" if index == 0 else "map puzzle",
            "freeform_builder_expectation": False,
            "notes": f"synthetic audit observation {index}; not empirical evidence",
        })
    path.write_text(json.dumps(packet, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    run([sys.executable, str(PACKET), "finalize", "--packet", str(root)])


def main() -> None:
    if len(SOURCE_HEAD) != 40:
        raise SystemExit("E8 audit checkout source must resolve to exact Git SHA")
    with tempfile.TemporaryDirectory(prefix="fmd-e8-ingest-audit-") as raw:
        temp = Path(raw)
        artifact, record = build_fixture.create_bound_artifact(temp / "build", source_head=SOURCE_HEAD, role="production", build_id="AUDIT-BUILD")
        packet_root = prepare_bound(temp, "packet", "AUDIT-ASSET-V3", artifact, record)
        complete(packet_root)

        receipt_path = packet_root / "completion-receipt.json"
        asset_set_path = packet_root / "asset-set.json"
        expected_receipt_sha = sha256(receipt_path)
        expected_asset_set_sha = sha256(asset_set_path)
        asset_set = json.loads(asset_set_path.read_text(encoding="utf-8"))
        expected_role_hashes = {item["role"]: item["sha256"] for item in asset_set["assets"]}
        expected_role_sizes = {item["role"]: item["bytes"] for item in asset_set["assets"]}
        expected_binding = asset_set["acquisition_build_binding"]

        finalized_state = json.loads(run([sys.executable, str(PACKET), "status", "--packet", str(packet_root)]).stdout)
        if finalized_state.get("status") != "FINALIZED" or finalized_state.get("completion_receipt_verified") is not True:
            raise SystemExit(f"E8 status did not verify byte-bound finalized receipt: {finalized_state}")

        evidence_root = temp / "evidence"
        target = evidence_root / "E8.jsonl"
        dry = run([
            sys.executable, str(INGEST), "--packet", str(packet_root), "--expected-source-head", SOURCE_HEAD,
            "--evidence-root", str(evidence_root),
        ])
        dry_result = json.loads(dry.stdout)
        if dry_result.get("mode") != "dry_run" or dry_result.get("new_rows") != 2 or dry_result.get("completion_receipt_verified") is not True:
            raise SystemExit(f"unexpected E8 dry-run result: {dry_result}")
        if target.exists():
            raise SystemExit("E8 ingest dry-run mutated evidence")

        env = os.environ.copy()
        env["FMD_PHASE12G_BUILD_ARTIFACT_PATH"] = str(artifact)
        env["FMD_PHASE12G_BUILD_ARTIFACT_RECORD"] = str(record)
        run([
            sys.executable, str(INGEST), "--packet", str(packet_root), "--expected-source-head", SOURCE_HEAD,
            "--evidence-root", str(evidence_root), "--append",
        ], env=env)
        rows = evidence_rows(target)
        if len(rows) != 2:
            raise SystemExit("E8 append did not produce exactly two validated rows")
        for index, row in enumerate(rows, start=1):
            durable = row.get("e8_packet_provenance")
            if not isinstance(durable, dict):
                raise SystemExit(f"E8 row {index} did not persist durable packet provenance")
            if durable.get("asset_set_sha256") != expected_asset_set_sha or durable.get("completion_receipt_sha256") != expected_receipt_sha:
                raise SystemExit(f"E8 row {index} did not preserve exact finalized packet digests")
            if durable.get("frozen_assets_sha256_by_role") != expected_role_hashes or durable.get("frozen_assets_bytes_by_role") != expected_role_sizes:
                raise SystemExit(f"E8 row {index} did not preserve exact shown media bytes")
            if row.get("build_artifact_binding_id") != expected_binding["binding_id"] or row.get("build_artifact_sha256") != expected_binding["artifact_sha256"]:
                raise SystemExit(f"E8 row {index} packaged build provenance differs from acquisition-time binding")

        integrity = run([sys.executable, str(PROVENANCE_INTEGRITY), "--evidence", str(target)])
        if "validated_rows=2" not in integrity.stdout:
            raise SystemExit("E8 durable provenance integrity did not validate appended audit rows")
        repeat = json.loads(run([
            sys.executable, str(INGEST), "--packet", str(packet_root), "--expected-source-head", SOURCE_HEAD,
            "--evidence-root", str(evidence_root), "--append",
        ], env=env).stdout)
        if repeat.get("new_rows") != 0:
            raise SystemExit("repeat E8 ingest was not idempotent")

        wrong = run([
            sys.executable, str(INGEST), "--packet", str(packet_root), "--expected-source-head", WRONG_HEAD,
            "--evidence-root", str(evidence_root),
        ], expect_ok=False)
        if "repository checkout HEAD mismatch" not in (wrong.stderr + wrong.stdout):
            raise SystemExit("E8 ingest did not reject caller-supplied old source against actual checkout")

        preserved = evidence_rows(target)
        shutil.rmtree(packet_root)
        post = run([sys.executable, str(PROVENANCE_INTEGRITY), "--evidence", str(target)])
        if "validated_rows=2" not in post.stdout or evidence_rows(target) != preserved:
            raise SystemExit("E8 durable evidence provenance depended on external packet remaining present")

        tamper_root = prepare_bound(temp, "tamper", "AUDIT-ASSET-TAMPER-V3", artifact, record, respondents=1)
        complete(tamper_root)
        frozen_package = tamper_root / json.loads((tamper_root / "asset-set.json").read_text(encoding="utf-8"))["acquisition_build_binding"]["packet_artifact_path"]
        frozen_package.write_bytes(frozen_package.read_bytes() + b"POST-FINALIZE-SUBSTITUTION")
        mismatch = run([
            sys.executable, str(INGEST), "--packet", str(tamper_root), "--expected-source-head", SOURCE_HEAD,
            "--evidence-root", str(evidence_root),
        ], expect_ok=False)
        if "build" not in (mismatch.stderr + mismatch.stdout).lower() and "artifact" not in (mismatch.stderr + mismatch.stdout).lower():
            raise SystemExit("E8 ingest did not reject post-finalize packaged-build substitution")

    print("Phase 12G E8 ingest audit: PASS — exact checkout/source + immutable media + acquisition-time packaged bytes + digest-bound receipt + durable provenance + dry-run/append/idempotency/substitution rejection; synthetic audit data never touched repository evidence")


if __name__ == "__main__":
    main()
