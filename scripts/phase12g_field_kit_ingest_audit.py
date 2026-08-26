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
sys.path.insert(0, str(SCRIPT_DIR))
from phase12g_audit_build_fixture import kit_build_args  # noqa: E402

KIT = SCRIPT_DIR / "phase12g_human_field_kit.py"
INGEST = SCRIPT_DIR / "phase12g_field_kit_ingest.py"


def fail(message: str) -> None:
    raise SystemExit(f"PHASE12G FIELD KIT INGEST AUDIT FAIL: {message}")


def run(args: list[str], ok: bool = True, cwd: Path = ROOT) -> subprocess.CompletedProcess[str]:
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


def write(path: Path, value: dict) -> None:
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def assert_no_evidence(root: Path) -> None:
    if root.exists() and any(root.glob("*.jsonl")):
        fail("isolated audit evidence root must remain unmodified")


def main() -> None:
    source_head = repository_head()
    with tempfile.TemporaryDirectory(prefix="fmd-phase12g-ingest-") as temp:
        root = Path(temp)
        kit_root = root / "kit"
        evidence_root = root / "evidence"
        build_args = kit_build_args(
            root / "source-builds",
            source_head=source_head,
            demo_build_id="ingest-audit-demo",
            production_build_id="ingest-audit-production",
        )
        run([
            sys.executable,
            str(KIT),
            "prepare",
            "--source-head",
            source_head,
            "--demo-build-id",
            "ingest-audit-demo",
            "--production-build-id",
            "ingest-audit-production",
            *build_args,
            "--first-count",
            "1",
            "--mature-count",
            "1",
            "--output-dir",
            str(kit_root),
        ])
        manifest = load(kit_root / "field-kit-manifest.json")
        if manifest.get("acquisition_build_bytes_required") is not True:
            fail("prepared ingest fixture must bind exact acquisition package bytes")

        batch_path = kit_root / str(manifest["first_session"]["batch_manifest"])
        batch = load(batch_path)
        packet = batch["packets"][0]
        session_dir = (batch_path.parent / str(packet["session_dir"])).resolve()
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
            sys.executable,
            str(finalizer),
            "--kit-dir",
            str(kit_root),
            "--first-session",
            str(packet["session_id"]),
        ], cwd=kit_root)
        finalized_result = json.loads(finalized.stdout)
        if finalized_result.get("completed_file_digests_bound") is not True or finalized_result.get("acquisition_build_bytes_bound") is not True:
            fail("audit setup must finalize observed rows against exact acquisition package bytes")

        dry = run([
            sys.executable,
            str(INGEST),
            "--kit-dir",
            str(kit_root),
            "--expected-source-head",
            source_head,
            "--evidence-root",
            str(evidence_root),
        ])
        dry_result = json.loads(dry.stdout)
        if dry_result.get("status") != "VALIDATED_DRY_RUN" or dry_result.get("append_requested") is not False:
            fail("alternate evidence roots must remain valid for isolated dry-run validation")
        if dry_result.get("repository_checkout_head") != source_head:
            fail("dry run must expose and bind the actual repository checkout HEAD")
        if sorted(dry_result.get("completed_gate_ids", [])) != ["E1", "E11", "E2"]:
            fail("dry run must discover finalized E1/E2/E11 rows")
        if dry_result.get("finalization_receipts_verified") is not True or int(dry_result.get("completed_file_digests_verified", 0)) != 3:
            fail("dry run must verify receipt bindings for all finalized files")
        assert_no_evidence(evidence_root)

        wrong_source = "fedcba9876543210fedcba9876543210fedcba98"
        wrong = run([
            sys.executable,
            str(INGEST),
            "--kit-dir",
            str(kit_root),
            "--expected-source-head",
            wrong_source,
            "--evidence-root",
            str(evidence_root),
        ], ok=False)
        wrong_text = wrong.stdout + wrong.stderr
        if "repository checkout source-head mismatch" not in wrong_text or source_head not in wrong_text:
            fail("caller-supplied source SHA must not bypass actual repository checkout identity")
        assert_no_evidence(evidence_root)

        redirected_append = run([
            sys.executable,
            str(INGEST),
            "--kit-dir",
            str(kit_root),
            "--expected-source-head",
            source_head,
            "--evidence-root",
            str(evidence_root),
            "--append",
        ], ok=False)
        redirected_text = redirected_append.stdout + redirected_append.stderr
        if "append evidence destination must be the canonical repository root" not in redirected_text:
            fail("real field-kit append must reject a caller-controlled noncanonical evidence root")
        assert_no_evidence(evidence_root)

        # Attack the finalized routing boundary, not merely a stale digest. The finalization
        # receipt is transport metadata and can itself be rewritten by a caller, so simulate
        # a relabelled E1 row plus a recomputed receipt size/hash. The immutable packet's
        # bundled verifier must still reject the row before repository ingest/collector use.
        completed_e1 = session_dir / "completed-E1.jsonl"
        receipt_path = session_dir / "finalization-receipt.json"
        original_e1 = completed_e1.read_bytes()
        original_receipt = receipt_path.read_bytes()
        e1_rows = [json.loads(line) for line in completed_e1.read_text(encoding="utf-8").splitlines() if line.strip()]
        if len(e1_rows) != 1 or e1_rows[0].get("gate_id") != "E1":
            fail("gate-routing attack fixture did not start from canonical finalized E1 row")
        e1_rows[0]["gate_id"] = "E2"
        completed_e1.write_text(json.dumps(e1_rows[0], sort_keys=True) + "\n", encoding="utf-8")
        receipt = load(receipt_path)
        rebound = False
        for entry in receipt.get("completed_files", []):
            if isinstance(entry, dict) and Path(str(entry.get("path", ""))).name == "completed-E1.jsonl":
                entry["sha256"] = sha256_file(completed_e1)
                entry["bytes"] = completed_e1.stat().st_size
                rebound = True
        if not rebound:
            fail("gate-routing attack could not locate receipt-bound E1 file")
        write(receipt_path, receipt)

        rerouted = run([
            sys.executable,
            str(INGEST),
            "--kit-dir",
            str(kit_root),
            "--expected-source-head",
            source_head,
            "--evidence-root",
            str(evidence_root),
        ], ok=False)
        rerouted_text = (rerouted.stdout + rerouted.stderr).lower()
        if "finalized row gate_id mismatch" not in rerouted_text or "route is e1" not in rerouted_text:
            fail("receipt-rebound finalized E1->E2 relabel did not fail at immutable packet routing boundary")
        assert_no_evidence(evidence_root)
        completed_e1.write_bytes(original_e1)
        receipt_path.write_bytes(original_receipt)

        restored = run([
            sys.executable,
            str(INGEST),
            "--kit-dir",
            str(kit_root),
            "--expected-source-head",
            source_head,
            "--evidence-root",
            str(evidence_root),
        ])
        if json.loads(restored.stdout).get("status") != "VALIDATED_DRY_RUN":
            fail("canonical finalized packet must validate again after routing-attack fixture restoration")
        assert_no_evidence(evidence_root)

        completed_e1.write_bytes(completed_e1.read_bytes() + b"\n")
        transport_tamper = run([
            sys.executable,
            str(INGEST),
            "--kit-dir",
            str(kit_root),
            "--expected-source-head",
            source_head,
            "--evidence-root",
            str(evidence_root),
        ], ok=False)
        if "changed after offline finalization" not in (transport_tamper.stdout + transport_tamper.stderr):
            fail("post-finalization transport mutation must reject during dry-run validation")
        assert_no_evidence(evidence_root)

    print(
        "Phase 12G field-kit ingest audit: PASS — source/build/receipt validation stays dry-run-isolated; "
        "receipt-rebound gate relabels fail at immutable packet routing; production append rejects noncanonical destinations; transport tamper fails closed"
    )


if __name__ == "__main__":
    main()
