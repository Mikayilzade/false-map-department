#!/usr/bin/env python3
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
KIT = ROOT / "scripts/phase12g_human_field_kit.py"
FINALIZER_SOURCE = ROOT / "scripts/phase12g_field_kit_offline_finalize.py"
INGEST = ROOT / "scripts/phase12g_field_kit_ingest.py"


def fail(message: str) -> None:
    raise SystemExit(f"PHASE12G FINALIZATION RECEIPT AUDIT FAIL: {message}")


def run(args: list[str], *, cwd: Path = ROOT, ok: bool = True) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(args, cwd=cwd, text=True, capture_output=True)
    if ok and result.returncode != 0:
        fail(f"command failed: {' '.join(args)}\n{result.stdout}\n{result.stderr}")
    if not ok and result.returncode == 0:
        fail(f"command unexpectedly succeeded: {' '.join(args)}")
    return result


def repository_head() -> str:
    result = run(["git", "rev-parse", "--verify", "HEAD"])
    head = result.stdout.strip().lower()
    if len(head) != 40 or any(ch not in "0123456789abcdef" for ch in head):
        fail(f"invalid repository HEAD from git: {head!r}")
    return head


def load(path: Path) -> dict:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        fail(f"{path}: expected object")
    return value


def write(path: Path, payload: dict) -> None:
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def main() -> None:
    source_head = repository_head()
    with tempfile.TemporaryDirectory(prefix="fmd-phase12g-finalization-receipt-") as temp:
        root = Path(temp)
        kit_root = root / "kit"
        evidence_root = root / "evidence"
        run([
            sys.executable, str(KIT), "prepare",
            "--source-head", source_head,
            "--demo-build-id", "receipt-audit-demo",
            "--production-build-id", "receipt-audit-production",
            "--first-count", "1",
            "--mature-count", "1",
            "--output-dir", str(kit_root),
        ])
        manifest = load(kit_root / "field-kit-manifest.json")
        batch_path = kit_root / str(manifest["first_session"]["batch_manifest"])
        batch = load(batch_path)
        session_info = batch["packets"][0]
        session_dir = (batch_path.parent / str(session_info["session_dir"])).resolve()
        session_manifest = load(session_dir / "session-manifest.json")
        observer = load(session_dir / "observer.json")
        observer.update({
            "naive": True,
            "e1_success": True,
            "e1_understood_at_seconds": 42.0,
            "e2_packet_completed": True,
            "e2_success": True,
            "first_collateral_aha_observed": True,
            "first_collateral_aha_seconds": 300.0,
            "session_end_seconds": 900.0,
        })
        write(session_dir / "observer.json", observer)
        write(session_dir / "telemetry.json", {
            "tester_id": session_manifest["tester_id"],
            "session_id": session_manifest["session_id"],
            "demo_build_id": session_manifest["demo_build_id"],
            "session_started_ms": 123456789,
            "events": [{"event_type": "demo_completed", "elapsed_seconds": 900.0}],
        })

        finalizer = kit_root / "FIELD-KIT-FINALIZE.py"
        finalized = run([
            sys.executable, str(finalizer), "--kit-dir", str(kit_root),
            "--first-session", str(session_info["session_id"]),
        ], cwd=kit_root)
        summary = json.loads(finalized.stdout)
        if summary.get("status") != "FINALIZED_LOCAL_OFFLINE" or summary.get("completed_file_digests_bound") is not True:
            fail("offline finalization must report receipt-bound completed files")
        receipt_path = kit_root / str(summary.get("finalization_receipt", ""))
        receipt = load(receipt_path)
        if receipt.get("schema") != "fmd.phase12g.field-kit-finalization-receipt.v1":
            fail("receipt schema missing")
        if receipt.get("source_head") != source_head or receipt.get("field_kit_contract_hash") != manifest.get("contract_hash"):
            fail("receipt must bind exact source and field-kit contract")
        if receipt.get("demo_build_id") != "receipt-audit-demo" or receipt.get("production_build_id") != "receipt-audit-production":
            fail("receipt must bind both build identities")
        if receipt.get("finalizer_sha256") != manifest["offline_finalizer"]["sha256"]:
            fail("receipt must bind the manifest-pinned offline finalizer")
        bindings = receipt.get("completed_files", [])
        if not isinstance(bindings, list) or len(bindings) != 3:
            fail("first-session receipt must bind exactly E1/E2/E11 completed files")

        dry = run([
            sys.executable, str(INGEST),
            "--kit-dir", str(kit_root),
            "--expected-source-head", source_head,
            "--evidence-root", str(evidence_root),
        ])
        dry_summary = json.loads(dry.stdout)
        if dry_summary.get("status") != "VALIDATED_DRY_RUN" or dry_summary.get("finalization_receipts_verified") is not True:
            fail("repository dry-run ingest must verify finalization receipt")
        if dry_summary.get("repository_checkout_head") != source_head:
            fail("repository dry-run ingest must bind the actual checkout HEAD")
        if int(dry_summary.get("completed_file_digests_verified", 0)) != 3:
            fail("repository dry-run ingest must verify all three completed-file digests")
        if evidence_root.exists() and any(evidence_root.glob("*.jsonl")):
            fail("receipt dry-run must not append empirical evidence")

        completed_e1 = session_dir / "completed-E1.jsonl"
        original = completed_e1.read_bytes()
        completed_e1.write_bytes(original + b"\n")
        tampered = run([
            sys.executable, str(INGEST),
            "--kit-dir", str(kit_root),
            "--expected-source-head", source_head,
            "--evidence-root", str(evidence_root),
        ], ok=False)
        if "changed after offline finalization" not in (tampered.stdout + tampered.stderr):
            fail("post-finalization completed-row mutation must reject with receipt integrity reason")
        completed_e1.write_bytes(original)

        receipt["source_head"] = "fedcba9876543210fedcba9876543210fedcba98"
        write(receipt_path, receipt)
        tampered_receipt = run([
            sys.executable, str(INGEST),
            "--kit-dir", str(kit_root),
            "--expected-source-head", source_head,
            "--evidence-root", str(evidence_root),
        ], ok=False)
        if "finalization receipt source_head mismatch" not in (tampered_receipt.stdout + tampered_receipt.stderr):
            fail("receipt source tamper must reject")

        if not FINALIZER_SOURCE.exists():
            fail("repository finalizer source unexpectedly missing")

    print("Phase 12G finalization-receipt audit: PASS (actual checkout/source pin + offline finalized rows source/build/tool/digest bound + repository dry-run verifies full coverage + post-finalization transport mutation rejected + zero evidence append)")


if __name__ == "__main__":
    main()
