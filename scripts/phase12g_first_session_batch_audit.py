#!/usr/bin/env python3
from __future__ import annotations

import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BATCH = ROOT / "scripts/phase12g_first_session_batch.py"


def fail(message: str) -> None:
    raise SystemExit(f"PHASE12G FIRST SESSION BATCH FAIL: {message}")


def run(args: list[str]) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(args, cwd=ROOT, text=True, capture_output=True)
    if result.returncode != 0:
        fail(f"command failed ({result.returncode}): {' '.join(args)}\n{result.stdout}\n{result.stderr}")
    return result


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="fmd-phase12g-first-batch-") as tmp:
        base = Path(tmp)
        root = base / "original"
        run([
            sys.executable,
            str(BATCH),
            "prepare",
            "--count",
            "3",
            "--start",
            "7",
            "--tester-prefix",
            "NAIVE-T",
            "--session-prefix",
            "FIRST-S",
            "--build-id",
            "audit-demo-build",
            "--output-dir",
            str(root),
        ])
        manifest_path = root / "batch-manifest.json"
        if not manifest_path.exists():
            fail("batch manifest was not created")
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        if manifest.get("batch_version") != 2 or manifest.get("path_contract") != "packet_paths_relative_to_batch_manifest":
            fail("batch manifest must declare portable relative-path contract")
        if manifest.get("packet_count") != 3:
            fail("expected exactly three prepared packets")
        if manifest.get("human_outcomes_required") is not True or manifest.get("templates_are_not_evidence") is not True:
            fail("batch manifest weakened human-evidence boundary")
        if manifest.get("repository_evidence_appended") is not False:
            fail("prepare must never claim repository evidence append")

        seen_testers: set[str] = set()
        seen_sessions: set[str] = set()
        for packet in manifest.get("packets", []):
            tester_id = str(packet.get("tester_id", ""))
            session_id = str(packet.get("session_id", ""))
            if tester_id in seen_testers or session_id in seen_sessions:
                fail("batch IDs must be unique")
            seen_testers.add(tester_id)
            seen_sessions.add(session_id)
            raw_session = Path(str(packet.get("session_dir", "")))
            if raw_session.is_absolute():
                fail("portable manifest must not store absolute session paths")
            session_dir = manifest_path.parent / raw_session
            observer = json.loads((session_dir / "observer.json").read_text(encoding="utf-8"))
            for field in (
                "naive",
                "e1_success",
                "e1_understood_at_seconds",
                "e2_packet_completed",
                "e2_success",
                "first_collateral_aha_observed",
                "first_collateral_aha_seconds",
                "session_end_seconds",
            ):
                if observer.get(field) is not None:
                    fail(f"prepared observer field must stay blank: {field}")
            for gate in ("E1", "E2", "E11"):
                if (session_dir / f"completed-{gate}.jsonl").exists():
                    fail("prepare must not generate completed human evidence rows")
            launch_env = (session_dir / "launch.env.txt").read_text(encoding="utf-8")
            if "FMD_PLAYTEST_DOSSIER_ID=DEMO01" not in launch_env:
                fail("prepared packet must launch exact demo sequence from DEMO01")
            if "audit-demo-build" not in launch_env:
                fail("prepared packet must preserve explicit build ID")

        moved = base / "relocated"
        shutil.copytree(root, moved)
        shutil.rmtree(root)
        moved_manifest = moved / "batch-manifest.json"
        status_path = moved / "status.json"
        run([
            sys.executable,
            str(BATCH),
            "status",
            "--manifest",
            str(moved_manifest),
            "--output",
            str(status_path),
        ])
        status = json.loads(status_path.read_text(encoding="utf-8"))
        if status.get("counts") != {"PREPARED": 3}:
            fail(f"relocated packets must report PREPARED only, got {status.get('counts')}")
        if status.get("human_outcomes_inferred") is not False or status.get("repository_evidence_appended") is not False:
            fail("status command must never infer human results or append evidence")
        if any(row.get("ready_to_finalize") for row in status.get("packets", [])):
            fail("blank packets cannot be ready to finalize")

        evidence_root = ROOT / "empirical/evidence"
        before = sorted(path.name for path in evidence_root.glob("E1.jsonl")) + sorted(path.name for path in evidence_root.glob("E2.jsonl")) + sorted(path.name for path in evidence_root.glob("E11.jsonl"))
        after = sorted(path.name for path in evidence_root.glob("E1.jsonl")) + sorted(path.name for path in evidence_root.glob("E2.jsonl")) + sorted(path.name for path in evidence_root.glob("E11.jsonl"))
        if before != after:
            fail("batch helper must not mutate repository evidence")

    print("Phase 12G first-session batch audit: PASS (3 blank human packets + relocatable manifest paths + DEMO01 launch + no completed/evidence rows + readiness-only status)")


if __name__ == "__main__":
    main()
