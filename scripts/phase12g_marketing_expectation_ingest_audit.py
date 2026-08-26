#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT_DIR = ROOT / "scripts"
PREPARE = SCRIPT_DIR / "phase12g_marketing_acquisition_prepare.py"
PACKET = SCRIPT_DIR / "phase12g_marketing_expectation_packet.py"
INGEST = SCRIPT_DIR / "phase12g_marketing_expectation_ingest.py"
SOURCE_HEAD = subprocess.run(
    ["git", "rev-parse", "--verify", "HEAD"],
    cwd=ROOT,
    capture_output=True,
    text=True,
    check=True,
).stdout.strip().lower()
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
        sys.executable,
        str(PREPARE),
        "--asset-version",
        version,
        "--build-id",
        "AUDIT-BUILD",
        "--source-head",
        SOURCE_HEAD,
        *asset_args(temp / f"{name}-media"),
        "--respondents",
        str(respondents),
        "--production-build-artifact",
        str(artifact),
        "--production-build-artifact-record",
        str(record),
        "--output",
        str(root),
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


def assert_no_evidence(root: Path) -> None:
    if root.exists() and any(root.glob("*.jsonl")):
        raise SystemExit("isolated E8 audit evidence root must remain unmodified")


def main() -> None:
    if len(SOURCE_HEAD) != 40:
        raise SystemExit("E8 audit checkout source must resolve to exact Git SHA")
    with tempfile.TemporaryDirectory(prefix="fmd-e8-ingest-audit-") as raw:
        temp = Path(raw)
        artifact, record = build_fixture.create_bound_artifact(
            temp / "build",
            source_head=SOURCE_HEAD,
            role="production",
            build_id="AUDIT-BUILD",
        )
        packet_root = prepare_bound(temp, "packet", "AUDIT-ASSET-V4", artifact, record)
        complete(packet_root)

        receipt_path = packet_root / "completion-receipt.json"
        asset_set_path = packet_root / "asset-set.json"
        expected_receipt_sha = sha256(receipt_path)
        expected_asset_set_sha = sha256(asset_set_path)
        if not expected_receipt_sha or not expected_asset_set_sha:
            raise SystemExit("finalized E8 packet must expose stable receipt/asset-set digests")

        finalized_state = json.loads(
            run([sys.executable, str(PACKET), "status", "--packet", str(packet_root)]).stdout
        )
        if finalized_state.get("status") != "FINALIZED" or finalized_state.get("completion_receipt_verified") is not True:
            raise SystemExit(f"E8 status did not verify byte-bound finalized receipt: {finalized_state}")

        evidence_root = temp / "evidence"
        dry = run([
            sys.executable,
            str(INGEST),
            "--packet",
            str(packet_root),
            "--expected-source-head",
            SOURCE_HEAD,
            "--evidence-root",
            str(evidence_root),
        ])
        dry_result = json.loads(dry.stdout)
        if dry_result.get("mode") != "dry_run" or dry_result.get("new_rows") != 2 or dry_result.get("completion_receipt_verified") is not True:
            raise SystemExit(f"unexpected E8 dry-run result: {dry_result}")
        if dry_result.get("source_head") != SOURCE_HEAD or dry_result.get("repository_checkout_head") != SOURCE_HEAD:
            raise SystemExit("E8 dry-run must bind packet source to actual repository checkout")
        if dry_result.get("durable_packet_provenance_schema") != "fmd.phase12g.e8.evidence-packet-provenance.v1":
            raise SystemExit("E8 dry-run must still compile durable finalized-packet provenance")
        assert_no_evidence(evidence_root)

        env = os.environ.copy()
        env["FMD_PHASE12G_BUILD_ARTIFACT_PATH"] = str(artifact)
        env["FMD_PHASE12G_BUILD_ARTIFACT_RECORD"] = str(record)
        redirected_append = run([
            sys.executable,
            str(INGEST),
            "--packet",
            str(packet_root),
            "--expected-source-head",
            SOURCE_HEAD,
            "--evidence-root",
            str(evidence_root),
            "--append",
        ], expect_ok=False, env=env)
        redirected_text = redirected_append.stdout + redirected_append.stderr
        if "append evidence destination must be the canonical repository root" not in redirected_text:
            raise SystemExit("E8 real append must reject a caller-controlled noncanonical evidence root")
        assert_no_evidence(evidence_root)

        wrong = run([
            sys.executable,
            str(INGEST),
            "--packet",
            str(packet_root),
            "--expected-source-head",
            WRONG_HEAD,
            "--evidence-root",
            str(evidence_root),
        ], expect_ok=False)
        if "repository checkout HEAD mismatch" not in (wrong.stderr + wrong.stdout):
            raise SystemExit("E8 ingest did not reject caller-supplied old source against actual checkout")
        assert_no_evidence(evidence_root)

        tamper_root = prepare_bound(temp, "tamper", "AUDIT-ASSET-TAMPER-V4", artifact, record, respondents=1)
        complete(tamper_root)
        tamper_asset_set = json.loads((tamper_root / "asset-set.json").read_text(encoding="utf-8"))
        frozen_package = tamper_root / tamper_asset_set["acquisition_build_binding"]["packet_artifact_path"]
        frozen_package.write_bytes(frozen_package.read_bytes() + b"POST-FINALIZE-SUBSTITUTION")
        mismatch = run([
            sys.executable,
            str(INGEST),
            "--packet",
            str(tamper_root),
            "--expected-source-head",
            SOURCE_HEAD,
            "--evidence-root",
            str(evidence_root),
        ], expect_ok=False)
        mismatch_text = (mismatch.stderr + mismatch.stdout).lower()
        if "build" not in mismatch_text and "artifact" not in mismatch_text:
            raise SystemExit("E8 ingest did not reject post-finalize packaged-build substitution")
        assert_no_evidence(evidence_root)

    print(
        "Phase 12G E8 ingest audit: PASS — finalized media/source/build validation remains dry-run-isolated; "
        "production append rejects noncanonical evidence destinations before mutation; source and packaged-build tamper still fail closed"
    )


if __name__ == "__main__":
    main()
