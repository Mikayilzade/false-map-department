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
SOURCE_HEAD = "0123456789abcdef0123456789abcdef01234567"


def fail(message: str) -> None:
    raise SystemExit(f"PHASE12G FIELD KIT INGEST AUDIT FAIL: {message}")


def run(args: list[str], ok: bool = True) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(args, cwd=ROOT, text=True, capture_output=True)
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


def write_jsonl(path: Path, rows: list[dict]) -> None:
    path.write_text("".join(json.dumps(row, sort_keys=True) + "\n" for row in rows), encoding="utf-8")


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="fmd-phase12g-ingest-") as temp:
        root = Path(temp)
        kit_root = root / "kit"
        evidence_root = root / "evidence"
        run([
            sys.executable, str(KIT), "prepare",
            "--source-head", SOURCE_HEAD,
            "--demo-build-id", "ingest-audit-demo",
            "--production-build-id", "ingest-audit-production",
            "--first-count", "1",
            "--mature-count", "1",
            "--output-dir", str(kit_root),
        ])
        manifest = load(kit_root / "field-kit-manifest.json")
        batch = load(kit_root / str(manifest["first_session"]["batch_manifest"]))
        session_dir = (kit_root / "first-session" / str(batch["packets"][0]["session_dir"])).resolve()
        session_manifest = load(session_dir / "session-manifest.json")
        completed = session_dir / "completed-E1.jsonl"
        write_jsonl(completed, [{
            "schema_version": 1,
            "gate_id": "E1",
            "tester_id": session_manifest["tester_id"],
            "naive": True,
            "session_id": session_manifest["session_id"],
            "understood_within_seconds": 42.0,
            "success": True,
        }])

        dry = run([
            sys.executable, str(INGEST),
            "--kit-dir", str(kit_root),
            "--expected-source-head", SOURCE_HEAD,
            "--evidence-root", str(evidence_root),
        ])
        dry_result = json.loads(dry.stdout)
        if dry_result.get("status") != "VALIDATED_DRY_RUN" or dry_result.get("append_requested") is not False:
            fail("default ingest must be a validated dry run")
        if dry_result.get("completed_gate_ids") != ["E1"] or int(dry_result.get("completed_file_count", 0)) != 1:
            fail("dry run must discover only the completed observed-row gate")
        if (evidence_root / "E1.jsonl").exists():
            fail("dry run must not append evidence")

        wrong = run([
            sys.executable, str(INGEST),
            "--kit-dir", str(kit_root),
            "--expected-source-head", "fedcba9876543210fedcba9876543210fedcba98",
            "--evidence-root", str(evidence_root),
        ], ok=False)
        if "source-head mismatch" not in (wrong.stdout + wrong.stderr):
            fail("mismatched source head must reject explicitly")

        appended = run([
            sys.executable, str(INGEST),
            "--kit-dir", str(kit_root),
            "--expected-source-head", SOURCE_HEAD,
            "--evidence-root", str(evidence_root),
            "--append",
        ])
        append_result = json.loads(appended.stdout)
        if append_result.get("status") != "APPENDED" or append_result.get("human_outcomes_inferred") is not False:
            fail("explicit append must preserve no-inference boundary")
        target = evidence_root / "E1.jsonl"
        if not target.exists() or len(target.read_text(encoding="utf-8").splitlines()) != 1:
            fail("explicit append must write exactly one validated row")

        repeat = run([
            sys.executable, str(INGEST),
            "--kit-dir", str(kit_root),
            "--expected-source-head", SOURCE_HEAD,
            "--evidence-root", str(evidence_root),
            "--append",
        ])
        repeat_result = json.loads(repeat.stdout)
        if any(int(item.get("new_rows", -1)) != 0 for item in repeat_result.get("results", [])):
            fail("repeat append must be idempotent at row level")
        if len(target.read_text(encoding="utf-8").splitlines()) != 1:
            fail("repeat append must not duplicate evidence")

    print("Phase 12G field-kit ingest audit: PASS (offline verification + exact source pin + dry-run default + deliberate append + idempotent rows)")


if __name__ == "__main__":
    main()
