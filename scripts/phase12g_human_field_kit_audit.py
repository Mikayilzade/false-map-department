#!/usr/bin/env python3
from __future__ import annotations

import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOOL = ROOT / "scripts/phase12g_human_field_kit.py"
SOURCE_HEAD = "0123456789abcdef0123456789abcdef01234567"


def fail(message: str) -> None:
    raise SystemExit(f"PHASE12G FIELD KIT AUDIT FAIL: {message}")


def run(args: list[str], expect_ok: bool = True, cwd: Path | None = None) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(args, cwd=cwd or ROOT, text=True, capture_output=True)
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


def resolve_relative(base: Path, value: object) -> Path:
    raw = Path(str(value))
    if raw.is_absolute():
        fail(f"portable audit found unexpected absolute path: {raw}")
    return base / raw


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="fmd-phase12g-field-kit-") as temp:
        root = Path(temp)
        original = root / "kit-original"
        prepared = run([
            sys.executable, str(TOOL), "prepare",
            "--source-head", SOURCE_HEAD,
            "--demo-build-id", "audit-demo-build",
            "--production-build-id", "audit-production-build",
            "--first-count", "2",
            "--mature-count", "2",
            "--output-dir", str(original),
        ])
        summary = json.loads(prepared.stdout)
        if summary.get("status") != "PREPARED" or summary.get("repository_evidence_appended") is not False:
            fail("prepare must report a non-evidence PREPARED kit")
        if summary.get("offline_verifier_bundled") is not True:
            fail("prepare must report the self-contained verifier bundle")

        manifest = load_json(original / "field-kit-manifest.json")
        if manifest.get("field_kit_version") != 3 or manifest.get("source_head") != SOURCE_HEAD:
            fail("field kit must pin exact v3 source-head provenance")
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
        for section in ("first_session", "mature_session"):
            if Path(str(manifest[section]["batch_manifest"])).is_absolute():
                fail("field-kit batch manifests must be relative")
            if len(str(manifest[section].get("batch_manifest_sha256", ""))) != 64:
                fail("field-kit batch manifest must be hash-pinned")
        verifier_contract = manifest.get("offline_verifier", {})
        if not isinstance(verifier_contract, dict):
            fail("offline verifier manifest contract must be present")
        if verifier_contract.get("path") != "FIELD-KIT-VERIFY.py":
            fail("offline verifier must use the portable root-relative path")
        if len(str(verifier_contract.get("sha256", ""))) != 64:
            fail("offline verifier bytes must be SHA-256 pinned")
        if verifier_contract.get("requires_repository_checkout") is not False:
            fail("offline verifier must explicitly require no repository checkout")
        verifier_original = original / "FIELD-KIT-VERIFY.py"
        if not verifier_original.exists():
            fail("prepared kit must physically contain the offline verifier")
        instructions = (original / "FIELD-KIT-INSTRUCTIONS.txt").read_text(encoding="utf-8")
        if "python3 FIELD-KIT-VERIFY.py --kit-dir ." not in instructions:
            fail("field-kit instructions must expose the offline integrity command")

        # The kit must genuinely survive relocation with the original path removed.
        relocated = root / "kit-relocated"
        shutil.copytree(original, relocated)
        shutil.rmtree(original)
        verifier = relocated / "FIELD-KIT-VERIFY.py"
        offline = run([sys.executable, str(verifier), "--kit-dir", "."], cwd=relocated)
        offline_summary = json.loads(offline.stdout)
        if offline_summary.get("status") != "VERIFIED_OFFLINE" or offline_summary.get("portable_paths_verified") is not True:
            fail("relocated kit must verify using only its bundled verifier")
        if offline_summary.get("repository_evidence_appended") is not False:
            fail("offline verification must never append evidence")

        # Repository-side verify deliberately delegates to the same hash-pinned bundled verifier.
        verified = run([sys.executable, str(TOOL), "verify", "--kit-dir", str(relocated)])
        verify_summary = json.loads(verified.stdout)
        if verify_summary.get("status") != "VERIFIED" or verify_summary.get("offline_verifier_used") is not True:
            fail("repository verify must consume the bundled offline verifier")

        manifest = load_json(relocated / "field-kit-manifest.json")
        first_manifest_path = resolve_relative(relocated, manifest["first_session"]["batch_manifest"])
        first_manifest = load_json(first_manifest_path)
        first_session_dir = resolve_relative(first_manifest_path.parent, first_manifest["packets"][0]["session_dir"])

        # Human observation fields may legitimately change; offline verifier must still accept them.
        observer_path = first_session_dir / "observer.json"
        observer = load_json(observer_path)
        observer["naive"] = True
        observer_path.write_text(json.dumps(observer, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        run([sys.executable, str(verifier), "--kit-dir", "."], cwd=relocated)

        # Immutable packet identity/build metadata must be pinned. Tampering is rejected offline.
        session_manifest_path = first_session_dir / "session-manifest.json"
        session_manifest = load_json(session_manifest_path)
        original_session_manifest = dict(session_manifest)
        session_manifest["demo_build_id"] = "tampered-build"
        session_manifest_path.write_text(json.dumps(session_manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        rejected = run([sys.executable, str(verifier), "--kit-dir", "."], expect_ok=False, cwd=relocated)
        if "immutable contract changed" not in (rejected.stdout + rejected.stderr):
            fail("tampered immutable packet contract must fail offline with an integrity reason")
        session_manifest_path.write_text(json.dumps(original_session_manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")

        # The repository-side entrypoint must reject altered verifier bytes before executing them.
        verifier.write_text(verifier.read_text(encoding="utf-8") + "\n# tampered\n", encoding="utf-8")
        rejected_verifier = run([sys.executable, str(TOOL), "verify", "--kit-dir", str(relocated)], expect_ok=False)
        if "offline verifier hash mismatch" not in (rejected_verifier.stdout + rejected_verifier.stderr):
            fail("tampered bundled verifier must be rejected by its manifest hash")

        invalid = root / "invalid-head-kit"
        rejected_head = run([
            sys.executable, str(TOOL), "prepare",
            "--source-head", "audit-head-0123456789abcdef",
            "--demo-build-id", "audit-demo-build",
            "--production-build-id", "audit-production-build",
            "--first-count", "1",
            "--mature-count", "1",
            "--output-dir", str(invalid),
        ], expect_ok=False)
        if "40-character Git commit SHA" not in (rejected_head.stdout + rejected_head.stderr):
            fail("invalid source head must be rejected explicitly")

        evidence_root = ROOT / "empirical/evidence"
        if (evidence_root / "FIELD-KIT.jsonl").exists():
            fail("field kit audit must never invent repository evidence")

    print("Phase 12G human field-kit audit: PASS (E1-E6/E9-E11 portable packets + self-contained relocated verifier + exact source pinning + nested/immutable tamper rejection + mutable observer allowance + no evidence append)")


if __name__ == "__main__":
    main()
