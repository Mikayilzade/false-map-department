#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PACKET = ROOT / "scripts/phase12g_marketing_expectation_packet.py"
INGEST = ROOT / "scripts/phase12g_marketing_expectation_ingest.py"
PROVENANCE_INTEGRITY = ROOT / "scripts/phase12g_e8_evidence_provenance_integrity.py"
SOURCE_HEAD = "1" * 40
WRONG_HEAD = "2" * 40
ROLES = (
    ("store_key_art", ".png"),
    ("gameplay_map_world", ".png"),
    ("gameplay_consequence", ".png"),
    ("late_game_linked", ".png"),
    ("trailer", ".mp4"),
)


def run(args: list[str], expect_ok: bool = True) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(args, cwd=ROOT, text=True, capture_output=True)
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


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="fmd-e8-ingest-audit-") as raw:
        temp = Path(raw)
        media = temp / "media"
        media.mkdir()
        asset_args: list[str] = []
        for role, suffix in ROLES:
            path = media / f"{role}{suffix}"
            path.write_bytes((f"SYNTHETIC-AUDIT-ASSET:{role}\n").encode("utf-8"))
            asset_args += ["--asset", f"{role}={path}"]

        packet_root = temp / "packet"
        run([
            sys.executable,
            str(PACKET),
            "prepare",
            "--asset-version", "AUDIT-ASSET-V1",
            "--build-id", "AUDIT-BUILD",
            "--source-head", SOURCE_HEAD,
            *asset_args,
            "--representative-attestation",
            "--respondents", "2",
            "--output", str(packet_root),
        ])

        respondents_path = packet_root / "respondents.json"
        respondents = json.loads(respondents_path.read_text(encoding="utf-8"))
        respondents["rows"][0].update({
            "expected_play_category": "systemic puzzle",
            "freeform_builder_expectation": False,
            "notes": "synthetic audit observation A; not empirical evidence",
        })
        respondents["rows"][1].update({
            "expected_play_category": "map puzzle",
            "freeform_builder_expectation": False,
            "notes": "synthetic audit observation B; not empirical evidence",
        })
        respondents_path.write_text(json.dumps(respondents, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        run([sys.executable, str(PACKET), "finalize", "--packet", str(packet_root)])

        receipt_path = packet_root / "completion-receipt.json"
        asset_set_path = packet_root / "asset-set.json"
        if not receipt_path.is_file():
            raise SystemExit("E8 finalize did not emit completion-receipt.json")
        expected_receipt_sha = sha256(receipt_path)
        expected_asset_set_sha = sha256(asset_set_path)
        asset_set = json.loads(asset_set_path.read_text(encoding="utf-8"))
        expected_role_hashes = {item["role"]: item["sha256"] for item in asset_set["assets"]}
        expected_role_sizes = {item["role"]: item["bytes"] for item in asset_set["assets"]}

        finalized_state = json.loads(run([sys.executable, str(PACKET), "status", "--packet", str(packet_root)]).stdout)
        if finalized_state.get("status") != "FINALIZED" or finalized_state.get("completion_receipt_verified") is not True:
            raise SystemExit(f"E8 status did not verify finalized receipt: {finalized_state}")
        rewrite = run([sys.executable, str(PACKET), "finalize", "--packet", str(packet_root)], expect_ok=False)
        if "already finalized" not in (rewrite.stderr + rewrite.stdout):
            raise SystemExit("E8 finalizer did not reject rewriting an already finalized respondent return")

        evidence_root = temp / "evidence"
        target = evidence_root / "E8.jsonl"
        dry = run([
            sys.executable, str(INGEST),
            "--packet", str(packet_root),
            "--expected-source-head", SOURCE_HEAD,
            "--evidence-root", str(evidence_root),
        ])
        dry_result = json.loads(dry.stdout)
        if dry_result.get("mode") != "dry_run" or dry_result.get("new_rows") != 2:
            raise SystemExit(f"unexpected E8 dry-run result: {dry_result}")
        if dry_result.get("completion_receipt_verified") is not True:
            raise SystemExit("E8 dry-run did not report completion receipt verification")
        if dry_result.get("durable_packet_provenance_schema") != "fmd.phase12g.e8.evidence-packet-provenance.v1":
            raise SystemExit("E8 dry-run did not expose durable packet provenance schema")
        if target.exists():
            raise SystemExit("E8 ingest dry-run mutated evidence")

        run([
            sys.executable, str(INGEST),
            "--packet", str(packet_root),
            "--expected-source-head", SOURCE_HEAD,
            "--evidence-root", str(evidence_root),
            "--append",
        ])
        rows = evidence_rows(target)
        if len(rows) != 2 or any(row.get("gate_id") != "E8" for row in rows):
            raise SystemExit("E8 append did not produce exactly two validated rows")
        for index, row in enumerate(rows, start=1):
            durable = row.get("e8_packet_provenance")
            if not isinstance(durable, dict):
                raise SystemExit(f"E8 row {index} did not persist durable packet provenance")
            if durable.get("source_head") != SOURCE_HEAD or durable.get("build_id") != "AUDIT-BUILD" or durable.get("asset_version") != "AUDIT-ASSET-V1":
                raise SystemExit(f"E8 row {index} durable packet identity mismatch")
            if durable.get("asset_set_sha256") != expected_asset_set_sha:
                raise SystemExit(f"E8 row {index} did not preserve exact asset-set digest")
            if durable.get("completion_receipt_sha256") != expected_receipt_sha:
                raise SystemExit(f"E8 row {index} did not preserve exact completion-receipt digest")
            if durable.get("frozen_assets_sha256_by_role") != expected_role_hashes:
                raise SystemExit(f"E8 row {index} did not preserve exact shown asset hashes by role")
            if durable.get("frozen_assets_bytes_by_role") != expected_role_sizes:
                raise SystemExit(f"E8 row {index} did not preserve exact shown asset sizes by role")

        integrity = run([sys.executable, str(PROVENANCE_INTEGRITY), "--evidence", str(target)])
        if "validated_rows=2" not in integrity.stdout:
            raise SystemExit("E8 live-style provenance integrity did not validate appended audit rows")

        repeat = run([
            sys.executable, str(INGEST),
            "--packet", str(packet_root),
            "--expected-source-head", SOURCE_HEAD,
            "--evidence-root", str(evidence_root),
            "--append",
        ])
        repeat_result = json.loads(repeat.stdout)
        if repeat_result.get("new_rows") != 0 or len(evidence_rows(target)) != 2:
            raise SystemExit("repeat E8 ingest was not idempotent")

        wrong = run([
            sys.executable, str(INGEST),
            "--packet", str(packet_root),
            "--expected-source-head", WRONG_HEAD,
            "--evidence-root", str(evidence_root),
        ], expect_ok=False)
        if "source_head mismatch" not in (wrong.stderr + wrong.stdout):
            raise SystemExit("E8 ingest did not reject wrong expected source head")

        # Prove the repository evidence remains self-describing even if the external
        # packet is later unavailable. Exact asset hashes/source/build/receipt identity
        # must still be reviewable from E8.jsonl alone.
        preserved_rows = evidence_rows(target)
        shutil.rmtree(packet_root)
        post_removal = run([sys.executable, str(PROVENANCE_INTEGRITY), "--evidence", str(target)])
        if "validated_rows=2" not in post_removal.stdout or evidence_rows(target) != preserved_rows:
            raise SystemExit("E8 durable evidence provenance depended on the external packet remaining present")

        # Build a second packet for tamper tests because the first was deliberately removed.
        packet_root = temp / "tamper-packet"
        run([
            sys.executable,
            str(PACKET),
            "prepare",
            "--asset-version", "AUDIT-ASSET-TAMPER",
            "--build-id", "AUDIT-BUILD",
            "--source-head", SOURCE_HEAD,
            *asset_args,
            "--representative-attestation",
            "--respondents", "1",
            "--output", str(packet_root),
        ])
        respondents_path = packet_root / "respondents.json"
        tamper_respondents = json.loads(respondents_path.read_text(encoding="utf-8"))
        tamper_respondents["rows"][0].update({
            "expected_play_category": "systemic puzzle",
            "freeform_builder_expectation": False,
            "notes": "synthetic tamper audit; not evidence",
        })
        respondents_path.write_text(json.dumps(tamper_respondents, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        run([sys.executable, str(PACKET), "finalize", "--packet", str(packet_root)])

        completed_path = packet_root / "completed-E8.jsonl"
        tampered_completed = [json.loads(line) for line in completed_path.read_text(encoding="utf-8").splitlines() if line.strip()]
        tampered_completed[0]["expected_play_category"] = "tampered category"
        completed_path.write_text("".join(json.dumps(row, sort_keys=True) + "\n" for row in tampered_completed), encoding="utf-8")
        mismatch = run([
            sys.executable, str(INGEST),
            "--packet", str(packet_root),
            "--expected-source-head", SOURCE_HEAD,
            "--evidence-root", str(evidence_root),
        ], expect_ok=False)
        if "completion receipt" not in (mismatch.stderr + mismatch.stdout).lower():
            raise SystemExit("E8 ingest did not reject completed-row tampering against finalization receipt")

        tampered_respondents = json.loads(respondents_path.read_text(encoding="utf-8"))
        tampered_respondents["rows"][0]["expected_play_category"] = "tampered category"
        respondents_path.write_text(json.dumps(tampered_respondents, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        coordinated = run([
            sys.executable, str(INGEST),
            "--packet", str(packet_root),
            "--expected-source-head", SOURCE_HEAD,
            "--evidence-root", str(evidence_root),
        ], expect_ok=False)
        if "completion receipt" not in (coordinated.stderr + coordinated.stdout).lower():
            raise SystemExit("E8 ingest accepted coordinated post-finalize respondent/completed-row tampering")

        tampered_state = json.loads(run([sys.executable, str(PACKET), "status", "--packet", str(packet_root)]).stdout)
        if tampered_state.get("status") != "INVALID_PACKET" or "receipt" not in str(tampered_state.get("reason", "")).lower():
            raise SystemExit(f"E8 status did not expose post-finalize receipt mismatch: {tampered_state}")

    print("Phase 12G E8 ingest audit: PASS — source/assets + digest-bound finalization + durable self-contained packet provenance survives external packet removal + dry-run/append/idempotency/tamper rejection; synthetic audit data never touched repository evidence")


if __name__ == "__main__":
    main()
