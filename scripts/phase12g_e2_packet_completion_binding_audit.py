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
HARNESS = SCRIPT_DIR / "phase12g_evidence_harness.py"


def fail(message: str) -> None:
    raise SystemExit(f"PHASE12G E2 PACKET COMPLETION BINDING AUDIT FAIL: {message}")


def run(args: list[str], ok: bool = True, cwd: Path = ROOT) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(args, cwd=cwd, text=True, capture_output=True)
    if ok and result.returncode != 0:
        fail(f"command failed: {' '.join(args)}\n{result.stdout}\n{result.stderr}")
    if not ok and result.returncode == 0:
        fail(f"command unexpectedly succeeded: {' '.join(args)}")
    return result


def load(path: Path) -> dict:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        fail(f"{path}: expected object")
    return value


def write(path: Path, value: dict) -> None:
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def repository_head() -> str:
    result = run(["git", "rev-parse", "--verify", "HEAD"])
    head = result.stdout.strip().lower()
    if len(head) != 40 or any(ch not in "0123456789abcdef" for ch in head):
        fail(f"invalid repository HEAD: {head!r}")
    return head


def main() -> None:
    harness = HARNESS.read_text(encoding="utf-8")
    if 'eligible = [r for r in rows if bool(r.get("packet_completed", False))]' not in harness:
        fail("E2 disposition no longer uses packet_completed as eligibility; re-audit threat model")

    source_head = repository_head()
    with tempfile.TemporaryDirectory(prefix="fmd-phase12g-e2-packet-completion-") as temp:
        root = Path(temp)
        kit_root = root / "kit"
        build_args = kit_build_args(
            root / "source-builds",
            source_head=source_head,
            demo_build_id="e2-completion-demo",
            production_build_id="e2-completion-production",
        )
        run([
            sys.executable,
            str(KIT),
            "prepare",
            "--source-head",
            source_head,
            "--demo-build-id",
            "e2-completion-demo",
            "--production-build-id",
            "e2-completion-production",
            *build_args,
            "--first-count",
            "1",
            "--mature-count",
            "1",
            "--output-dir",
            str(kit_root),
        ])

        manifest = load(kit_root / "field-kit-manifest.json")
        first_batch_path = kit_root / str(manifest["first_session"]["batch_manifest"])
        first_batch = load(first_batch_path)
        packet = first_batch["packets"][0]
        session_dir = (first_batch_path.parent / str(packet["session_dir"])).resolve()
        session_manifest = load(session_dir / "session-manifest.json")
        observer = load(session_dir / "observer.json")

        # A genuine observer may explicitly record that the second-order packet was not
        # completed. That makes the resulting E2 row ineligible in the numeric harness.
        # The attack changes only the finalized row and its mutable completed-file receipt
        # digest; it does not change the packet-local observer declaration.
        observer.update({
            "naive": True,
            "e1_success": True,
            "e1_understood_at_seconds": 40.0,
            "e2_packet_completed": False,
            "e2_success": True,
            "first_collateral_aha_observed": True,
            "first_collateral_aha_seconds": 280.0,
            "session_end_seconds": 850.0,
        })
        write(session_dir / "observer.json", observer)
        write(session_dir / "telemetry.json", {
            "tester_id": session_manifest["tester_id"],
            "session_id": session_manifest["session_id"],
            "demo_build_id": session_manifest["demo_build_id"],
            "session_started_ms": 123456789,
            "events": [{"event_type": "demo_completed", "elapsed_seconds": 850.0}],
        })

        finalizer = kit_root / "FIELD-KIT-FINALIZE.py"
        run([
            sys.executable,
            str(finalizer),
            "--kit-dir",
            str(kit_root),
            "--first-session",
            str(packet["session_id"]),
        ], cwd=kit_root)

        verifier = kit_root / "FIELD-KIT-VERIFY.py"
        baseline = run([sys.executable, str(verifier), "--kit-dir", str(kit_root)], cwd=kit_root)
        baseline_result = json.loads(baseline.stdout)
        if baseline_result.get("finalized_semantic_eligibility_verified") is not True:
            fail("baseline verifier did not report finalized semantic eligibility verification")

        completed_e2 = session_dir / "completed-E2.jsonl"
        receipt_path = session_dir / "finalization-receipt.json"
        original_e2 = completed_e2.read_bytes()
        original_receipt = receipt_path.read_bytes()
        rows = [json.loads(line) for line in completed_e2.read_text(encoding="utf-8").splitlines() if line.strip()]
        if len(rows) != 1 or rows[0].get("packet_completed") is not False or rows[0].get("gate_id") != "E2":
            fail("E2 completion attack fixture did not begin with finalized packet_completed=false")
        if observer.get("e2_packet_completed") is not False:
            fail("packet-local observer declaration must remain e2_packet_completed=false")

        rows[0]["packet_completed"] = True
        completed_e2.write_text(json.dumps(rows[0], sort_keys=True) + "\n", encoding="utf-8")
        receipt = load(receipt_path)
        rebound = False
        for entry in receipt.get("completed_files", []):
            if isinstance(entry, dict) and Path(str(entry.get("path", ""))).name == "completed-E2.jsonl":
                entry["sha256"] = sha256_file(completed_e2)
                entry["bytes"] = completed_e2.stat().st_size
                rebound = True
        if not rebound:
            fail("could not rebind mutated completed-E2 bytes inside finalization receipt")
        write(receipt_path, receipt)

        attacked = run([sys.executable, str(verifier), "--kit-dir", str(kit_root)], ok=False, cwd=kit_root)
        attacked_text = (attacked.stdout + attacked.stderr).lower()
        if "finalized e2 packet completion mismatch" not in attacked_text:
            fail("receipt-rebound E2 packet_completed=false->true mutation did not fail at packet-completion boundary")
        if "observer declares e2_packet_completed=false" not in attacked_text:
            fail("packet-completion rejection did not identify the packet-local observer declaration")

        completed_e2.write_bytes(original_e2)
        receipt_path.write_bytes(original_receipt)
        restored = run([sys.executable, str(verifier), "--kit-dir", str(kit_root)], cwd=kit_root)
        if json.loads(restored.stdout).get("status") != "VERIFIED_OFFLINE":
            fail("canonical finalized packet did not verify again after attack restoration")

    print(
        "Phase 12G E2 packet completion binding audit: PASS — finalized packet_completed=false cannot be rebound to true by changing only completed-E2 bytes and its receipt digest; canonical packet restores cleanly"
    )


if __name__ == "__main__":
    main()
