#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
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
ROLES = (
    ("store_key_art", ".png"),
    ("gameplay_map_world", ".png"),
    ("gameplay_consequence", ".png"),
    ("late_game_linked", ".png"),
    ("trailer", ".mp4"),
)

sys.path.insert(0, str(SCRIPT_DIR))
import phase12g_audit_build_fixture as build_fixture  # noqa: E402
import phase12g_marketing_completion_receipt as receipt_tools  # noqa: E402
import phase12g_marketing_expectation_packet as packet_tools  # noqa: E402


def fail(message: str) -> None:
    raise SystemExit(f"PHASE12G E8 FINALIZATION BINDING FAIL: {message}")


def run(args: list[str], expect_ok: bool = True) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(args, cwd=ROOT, text=True, capture_output=True)
    if expect_ok and result.returncode != 0:
        fail(f"command failed: {' '.join(args)}\nstdout={result.stdout}\nstderr={result.stderr}")
    if not expect_ok and result.returncode == 0:
        fail(f"command unexpectedly succeeded: {' '.join(args)}")
    return result


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def file_record(root: Path, path: Path) -> dict:
    resolved = path.resolve()
    return {
        "path": resolved.relative_to(root.resolve()).as_posix(),
        "sha256": sha256(resolved),
        "bytes": resolved.stat().st_size,
    }


def asset_args(root: Path) -> list[str]:
    root.mkdir(parents=True, exist_ok=True)
    args: list[str] = []
    for role, suffix in ROLES:
        path = root / f"{role}{suffix}"
        path.write_bytes(f"SYNTHETIC-E8-FINALIZATION-AUDIT:{role}\n".encode("utf-8"))
        args += ["--asset", f"{role}={path}"]
    return args


def prepare_and_finalize(temp: Path, artifact: Path, record: Path) -> Path:
    packet_root = temp / "packet"
    run([
        sys.executable,
        str(PREPARE),
        "--asset-version",
        "AUDIT-E8-FINALIZATION-V1",
        "--build-id",
        "AUDIT-BUILD",
        "--source-head",
        SOURCE_HEAD,
        *asset_args(temp / "media"),
        "--respondents",
        "2",
        "--production-build-artifact",
        str(artifact),
        "--production-build-artifact-record",
        str(record),
        "--output",
        str(packet_root),
    ])
    respondents_path = packet_root / "respondents.json"
    packet = json.loads(respondents_path.read_text(encoding="utf-8"))
    for index, row in enumerate(packet["rows"]):
        row["expected_play_category"] = "systemic puzzle" if index == 0 else "causal map puzzle"
        row["freeform_builder_expectation"] = False
        row["notes"] = f"synthetic finalization-binding declaration {index}; not empirical evidence"
    respondents_path.write_text(json.dumps(packet, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    run([sys.executable, str(PACKET), "finalize", "--packet", str(packet_root)])
    return packet_root


def assert_no_evidence(evidence_root: Path) -> None:
    target = evidence_root / "E8.jsonl"
    if target.exists() and target.read_text(encoding="utf-8").strip():
        fail("synthetic rebound attack appended E8 empirical evidence")


def verify_clean(packet_root: Path) -> dict:
    asset_set, respondents = packet_tools.load_and_verify_packet(packet_root)
    completed_path = packet_root / "completed-E8.jsonl"
    result = receipt_tools.verify_receipt(packet_root, asset_set, respondents, completed_path)
    if not result.get("ok", False):
        fail(f"clean finalized E8 receipt did not verify: {result}")
    if result.get("finalization_binding_scope") != "finalization_snapshot_only":
        fail("clean receipt did not expose finalization_snapshot_only scope")
    if result.get("declaration_only") is not True or result.get("proves_human_truth_or_representativeness") is not False:
        fail("clean receipt weakened the empirical evidence boundary")
    return result


def main() -> None:
    if len(SOURCE_HEAD) != 40:
        fail("repository source head must be an exact Git SHA")
    with tempfile.TemporaryDirectory(prefix="fmd-e8-finalization-binding-") as raw:
        temp = Path(raw)
        artifact, record = build_fixture.create_bound_artifact(
            temp / "build",
            source_head=SOURCE_HEAD,
            role="production",
            build_id="AUDIT-BUILD",
        )
        packet_root = prepare_and_finalize(temp, artifact, record)
        baseline = verify_clean(packet_root)
        if not baseline.get("finalized_outcome_sha256") or int(baseline.get("finalized_outcome_row_count", 0)) != 2:
            fail("clean receipt did not bind both finalized E8 outcome rows")

        respondents_path = packet_root / "respondents.json"
        completed_path = packet_root / "completed-E8.jsonl"
        receipt_path = packet_root / "completion-receipt.json"
        originals = {
            respondents_path: respondents_path.read_bytes(),
            completed_path: completed_path.read_bytes(),
            receipt_path: receipt_path.read_bytes(),
        }

        respondents = json.loads(respondents_path.read_text(encoding="utf-8"))
        respondents["rows"][0]["expected_play_category"] = "freeform city builder"
        respondents["rows"][0]["freeform_builder_expectation"] = True
        respondents["rows"][0]["notes"] = "synthetic rebound mutation; not empirical evidence"
        respondents_path.write_text(json.dumps(respondents, indent=2, sort_keys=True) + "\n", encoding="utf-8")

        completed_rows: list[dict] = []
        for raw_line in completed_path.read_text(encoding="utf-8").splitlines():
            if raw_line.strip():
                completed_rows.append(json.loads(raw_line))
        completed_rows[0] = dict(respondents["rows"][0])
        completed_path.write_text(
            "".join(json.dumps(row, sort_keys=True) + "\n" for row in completed_rows),
            encoding="utf-8",
        )

        # Simulate the specific rebound class left open by ordinary digest-only
        # finalization: refresh mutable file digest/size records, but do not touch
        # the independent declaration snapshot created at the original finalization.
        receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
        receipt["respondents"] = file_record(packet_root, respondents_path)
        receipt["completed_rows"] = file_record(packet_root, completed_path)
        receipt_path.write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n", encoding="utf-8")

        asset_set, rebound_respondents = packet_tools.load_and_verify_packet(packet_root)
        rebound = receipt_tools.verify_receipt(packet_root, asset_set, rebound_respondents, completed_path)
        if rebound.get("ok", False):
            fail("mutated E8 outcomes plus refreshed ordinary digest records bypassed independent finalization binding")
        if rebound.get("code") != "e8_finalized_outcome_binding_mismatch":
            fail(f"rebound was rejected at an unexpected boundary: {rebound}")

        evidence_root = temp / "evidence"
        ingest = run([
            sys.executable,
            str(INGEST),
            "--packet",
            str(packet_root),
            "--expected-source-head",
            SOURCE_HEAD,
            "--evidence-root",
            str(evidence_root),
        ], expect_ok=False)
        if "finalized_outcome_binding_mismatch" not in (ingest.stdout + ingest.stderr):
            fail("repository ingest did not surface independent E8 finalization binding rejection")
        assert_no_evidence(evidence_root)

        for path, data in originals.items():
            path.write_bytes(data)
        verify_clean(packet_root)
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
        if dry_result.get("mode") != "dry_run" or int(dry_result.get("new_rows", -1)) != 2:
            fail(f"restored canonical E8 packet did not return to clean dry-run state: {dry_result}")
        assert_no_evidence(evidence_root)

    print(
        "Phase 12G E8 finalization binding audit: PASS — prepared respondent identity remains authoritative; "
        "finalized category/builder/notes declarations have an independent declaration-only snapshot; "
        "digest-refresh rebound is rejected before ingest with zero empirical evidence; canonical packet restores cleanly"
    )


if __name__ == "__main__":
    main()
