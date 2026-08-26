#!/usr/bin/env python3
from __future__ import annotations

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
    raise SystemExit(f"PHASE12G FIELD KIT RETURN COLLISION AUDIT FAIL: {message}")


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


def prepare_finalize_first(kit_root: Path, source_head: str, demo_build: str, production_build: str, *, success: bool) -> str:
    build_args = kit_build_args(kit_root.parent / f"source-builds-{kit_root.name}", source_head=source_head, demo_build_id=demo_build, production_build_id=production_build)
    run([
        sys.executable, str(KIT), "prepare",
        "--source-head", source_head,
        "--demo-build-id", demo_build,
        "--production-build-id", production_build,
        *build_args,
        "--first-count", "1",
        "--mature-count", "1",
        "--output-dir", str(kit_root),
    ])
    manifest = load(kit_root / "field-kit-manifest.json")
    if manifest.get("acquisition_build_bytes_required") is not True:
        fail("collision fixture must use acquisition-bound packaged bytes")
    batch_path = kit_root / str(manifest["first_session"]["batch_manifest"])
    batch = load(batch_path)
    packet = batch["packets"][0]
    session_id = str(packet["session_id"])
    session_dir = (batch_path.parent / str(packet["session_dir"])).resolve()
    session_manifest = load(session_dir / "session-manifest.json")
    observer = load(session_dir / "observer.json")
    observer.update({
        "naive": True,
        "e1_success": success,
        "e1_understood_at_seconds": 42.0 if success else 179.0,
        "e2_packet_completed": True,
        "e2_success": success,
        "first_collateral_aha_observed": success,
        "first_collateral_aha_seconds": 300.0 if success else -1.0,
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
    finalized = run([sys.executable, str(finalizer), "--kit-dir", str(kit_root), "--first-session", session_id], cwd=kit_root)
    result = json.loads(finalized.stdout)
    if result.get("completed_file_digests_bound") is not True or result.get("acquisition_build_bytes_bound") is not True:
        fail("audit setup failed to bind completed rows to acquisition package bytes")
    return session_id


def ingest(kit_root: Path, evidence_root: Path, source_head: str, *, append: bool, ok: bool = True) -> subprocess.CompletedProcess[str]:
    args = [sys.executable, str(INGEST), "--kit-dir", str(kit_root), "--expected-source-head", source_head, "--evidence-root", str(evidence_root)]
    if append:
        args.append("--append")
    return run(args, ok=ok)


def main() -> None:
    source_head = repository_head()
    with tempfile.TemporaryDirectory(prefix="fmd-phase12g-return-collision-") as temp:
        root = Path(temp)
        evidence_root = root / "evidence"
        kit_a = root / "kit-a"
        kit_b = root / "kit-b"
        session_a = prepare_finalize_first(kit_a, source_head, "return-collision-demo-a", "return-collision-production-a", success=True)
        appended = ingest(kit_a, evidence_root, source_head, append=True)
        payload = json.loads(appended.stdout)
        if payload.get("return_identity_verified") is not True or payload.get("repository_checkout_head") != source_head:
            fail("first ingest did not report durable return-identity and checkout verification")
        namespaces = {str(item.get("return_namespace", "")) for item in payload.get("results", [])}
        if namespaces != {f"first_session:{session_a}"}:
            fail(f"first ingest emitted unexpected return namespace(s): {sorted(namespaces)}")
        before = {gate: (evidence_root / f"{gate}.jsonl").read_bytes() for gate in ("E1", "E2", "E11")}
        for gate in ("E1", "E2", "E11"):
            row = json.loads((evidence_root / f"{gate}.jsonl").read_text(encoding="utf-8").splitlines()[0])
            for key in ("field_kit_return_namespace", "field_kit_packet_kind", "field_kit_contract_hash", "field_kit_finalization_receipt_sha256"):
                if not str(row.get(key, "")).strip():
                    fail(f"{gate}: first ingest did not persist durable {key}")

        session_b = prepare_finalize_first(kit_b, source_head, "return-collision-demo-b", "return-collision-production-b", success=False)
        if session_b != session_a:
            fail("audit setup must intentionally reuse the same first-session namespace")
        rejected = ingest(kit_b, evidence_root, source_head, append=True, ok=False)
        detail = rejected.stdout + rejected.stderr
        if "return namespace collision with existing evidence" not in detail:
            fail(f"distinct finalized return reused namespace without explicit collision rejection:\n{detail}")
        for gate, content in before.items():
            if (evidence_root / f"{gate}.jsonl").read_bytes() != content:
                fail("collision rejection must preserve all existing evidence bytes")

        repeat = ingest(kit_a, evidence_root, source_head, append=True)
        repeat_payload = json.loads(repeat.stdout)
        if any(int(item.get("new_rows", -1)) != 0 for item in repeat_payload.get("results", [])):
            fail("exact finalized-return retry must remain row-idempotent")
        for gate, content in before.items():
            if (evidence_root / f"{gate}.jsonl").read_bytes() != content:
                fail("exact finalized-return retry must preserve evidence bytes")

    print("Phase 12G field-kit return collision audit: PASS (package-byte-bound finalizations + durable namespace collision rejection + exact retry idempotency)")


if __name__ == "__main__":
    main()
