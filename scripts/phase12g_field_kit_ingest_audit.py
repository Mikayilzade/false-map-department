#!/usr/bin/env python3
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
KIT = ROOT / "scripts/phase12g_human_field_kit.py"
INGEST = ROOT / "scripts/phase12g_field_kit_ingest.py"


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


def main() -> None:
    source_head = repository_head()
    with tempfile.TemporaryDirectory(prefix="fmd-phase12g-ingest-") as temp:
        root = Path(temp)
        kit_root = root / "kit"
        evidence_root = root / "evidence"
        run([
            sys.executable, str(KIT), "prepare",
            "--source-head", source_head,
            "--demo-build-id", "ingest-audit-demo",
            "--production-build-id", "ingest-audit-production",
            "--first-count", "1",
            "--mature-count", "1",
            "--output-dir", str(kit_root),
        ])
        manifest = load(kit_root / "field-kit-manifest.json")
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
            sys.executable, str(finalizer), "--kit-dir", str(kit_root),
            "--first-session", str(packet["session_id"]),
        ], cwd=kit_root)
        finalized_result = json.loads(finalized.stdout)
        if finalized_result.get("completed_file_digests_bound") is not True:
            fail("audit setup must finalize observed rows with receipt bindings")

        dry = run([
            sys.executable, str(INGEST),
            "--kit-dir", str(kit_root),
            "--expected-source-head", source_head,
            "--evidence-root", str(evidence_root),
        ])
        dry_result = json.loads(dry.stdout)
        if dry_result.get("status") != "VALIDATED_DRY_RUN" or dry_result.get("append_requested") is not False:
            fail("default ingest must be a validated dry run")
        if dry_result.get("repository_checkout_head") != source_head:
            fail("dry run must expose and bind the actual repository checkout HEAD")
        if dry_result.get("completed_gate_ids") != ["E1", "E11", "E2"] and sorted(dry_result.get("completed_gate_ids", [])) != ["E1", "E11", "E2"]:
            fail("dry run must discover finalized E1/E2/E11 rows")
        if dry_result.get("finalization_receipts_verified") is not True or int(dry_result.get("completed_file_digests_verified", 0)) != 3:
            fail("dry run must verify receipt bindings for all finalized files")
        if evidence_root.exists() and any(evidence_root.glob("*.jsonl")):
            fail("dry run must not append evidence")

        wrong_source = "fedcba9876543210fedcba9876543210fedcba98"
        wrong = run([
            sys.executable, str(INGEST),
            "--kit-dir", str(kit_root),
            "--expected-source-head", wrong_source,
            "--evidence-root", str(evidence_root),
        ], ok=False)
        wrong_text = wrong.stdout + wrong.stderr
        if "repository checkout source-head mismatch" not in wrong_text or source_head not in wrong_text:
            fail("caller-supplied source SHA must not bypass actual repository checkout identity")

        appended = run([
            sys.executable, str(INGEST),
            "--kit-dir", str(kit_root),
            "--expected-source-head", source_head,
            "--evidence-root", str(evidence_root),
            "--append",
        ])
        append_result = json.loads(appended.stdout)
        if append_result.get("status") != "APPENDED" or append_result.get("human_outcomes_inferred") is not False:
            fail("explicit append must preserve no-inference boundary")
        if append_result.get("repository_checkout_head") != source_head:
            fail("append result must retain exact checkout attribution")
        for gate_id in ("E1", "E2", "E11"):
            target = evidence_root / f"{gate_id}.jsonl"
            if not target.exists() or len(target.read_text(encoding="utf-8").splitlines()) != 1:
                fail(f"explicit append must write exactly one validated {gate_id} row")

        before = {gate: (evidence_root / f"{gate}.jsonl").read_bytes() for gate in ("E1", "E2", "E11")}
        repeat = run([
            sys.executable, str(INGEST),
            "--kit-dir", str(kit_root),
            "--expected-source-head", source_head,
            "--evidence-root", str(evidence_root),
            "--append",
        ])
        repeat_result = json.loads(repeat.stdout)
        if any(int(item.get("new_rows", -1)) != 0 for item in repeat_result.get("results", [])):
            fail("repeat append must be idempotent at row level")
        for gate, content in before.items():
            if (evidence_root / f"{gate}.jsonl").read_bytes() != content:
                fail("repeat append must preserve evidence bytes")

        completed_e1 = session_dir / "completed-E1.jsonl"
        original = completed_e1.read_bytes()
        completed_e1.write_bytes(original + b"\n")
        transport_tamper = run([
            sys.executable, str(INGEST),
            "--kit-dir", str(kit_root),
            "--expected-source-head", source_head,
            "--evidence-root", str(evidence_root),
            "--append",
        ], ok=False)
        if "changed after offline finalization" not in (transport_tamper.stdout + transport_tamper.stderr):
            fail("post-finalization transport mutation must reject before collector append")
        for gate, content in before.items():
            if (evidence_root / f"{gate}.jsonl").read_bytes() != content:
                fail("receipt rejection must preserve existing evidence bytes exactly")

    print("Phase 12G field-kit ingest audit: PASS (offline verification + finalization receipt binding + actual checkout/source pin + dry-run default + deliberate append + cross-run idempotency + post-finalization tamper rejection with byte-preserving failure)")


if __name__ == "__main__":
    main()
