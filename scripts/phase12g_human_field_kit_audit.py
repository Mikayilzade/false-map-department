#!/usr/bin/env python3
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOOL = ROOT / "scripts/phase12g_human_field_kit.py"


def fail(message: str) -> None:
    raise SystemExit(f"PHASE12G FIELD KIT AUDIT FAIL: {message}")


def run(args: list[str], expect_ok: bool = True) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(args, cwd=ROOT, text=True, capture_output=True)
    if expect_ok and result.returncode != 0:
        fail(f"command failed unexpectedly: {' '.join(args)}\n{result.stdout}\n{result.stderr}")
    if not expect_ok and result.returncode == 0:
        fail(f"command succeeded unexpectedly: {' '.join(args)}")
    return result


def load_json(path: Path) -> dict:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        fail(f"{path}: expected object")
    return payload


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="fmd-phase12g-field-kit-") as temp:
        root = Path(temp)
        kit = root / "kit"
        prepared = run([
            sys.executable, str(TOOL), "prepare",
            "--source-head", "audit-head-0123456789abcdef",
            "--demo-build-id", "audit-demo-build",
            "--production-build-id", "audit-production-build",
            "--first-count", "2",
            "--mature-count", "2",
            "--output-dir", str(kit),
        ])
        summary = json.loads(prepared.stdout)
        if summary.get("status") != "PREPARED" or summary.get("repository_evidence_appended") is not False:
            fail("prepare must report a non-evidence PREPARED kit")

        manifest = load_json(kit / "field-kit-manifest.json")
        if manifest.get("human_gates") != ["E1", "E2", "E3", "E4", "E5", "E6", "E9", "E10", "E11"]:
            fail("field kit must cover exact real-human acquisition gates")
        if manifest.get("prepared_packets_are_not_evidence") is not True:
            fail("field kit must explicitly mark prepared packets as non-evidence")
        if manifest.get("repository_evidence_appended") is not False:
            fail("field kit prepare must never append repository evidence")
        if int(manifest["first_session"]["packet_count"]) != 2 or int(manifest["mature_session"]["packet_count"]) != 2:
            fail("audit field kit packet counts must be deterministic")
        if not all(row.get("observer_initially_blank") is True for row in manifest["first_session"]["packets"]):
            fail("first-session human outcomes must start blank")
        if not all(row.get("rules_known_before_session_initially_blank") is True for row in manifest["mature_session"]["packets"]):
            fail("mature eligibility must start blank")

        verified = run([sys.executable, str(TOOL), "verify", "--kit-dir", str(kit)])
        verify_summary = json.loads(verified.stdout)
        if verify_summary.get("status") != "VERIFIED" or verify_summary.get("repository_evidence_appended") is not False:
            fail("untouched field kit must verify without evidence append")

        # Human observation fields may legitimately change; verify must still accept them.
        first_manifest = load_json(Path(str(manifest["first_session"]["batch_manifest"])))
        observer_path = Path(str(first_manifest["packets"][0]["session_dir"])) / "observer.json"
        observer = load_json(observer_path)
        observer["naive"] = True
        observer_path.write_text(json.dumps(observer, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        run([sys.executable, str(TOOL), "verify", "--kit-dir", str(kit)])

        # Immutable packet identity/build metadata must be pinned. Tampering is rejected.
        session_manifest_path = Path(str(first_manifest["packets"][0]["session_dir"])) / "session-manifest.json"
        session_manifest = load_json(session_manifest_path)
        session_manifest["demo_build_id"] = "tampered-build"
        session_manifest_path.write_text(json.dumps(session_manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        rejected = run([sys.executable, str(TOOL), "verify", "--kit-dir", str(kit)], expect_ok=False)
        if "immutable contract changed" not in (rejected.stdout + rejected.stderr):
            fail("tampered immutable packet contract must fail with an integrity reason")

        evidence_root = ROOT / "empirical/evidence"
        # Audit only used a temporary directory; it must not create any field-kit evidence files in the repo.
        if (evidence_root / "FIELD-KIT.jsonl").exists():
            fail("field kit audit must never invent repository evidence")

    print("Phase 12G human field-kit audit: PASS (E1-E6/E9-E11 portable packet orchestration + exact build/source pinning + mutable observer allowance + immutable contract tamper rejection + no evidence append)")


if __name__ == "__main__":
    main()
