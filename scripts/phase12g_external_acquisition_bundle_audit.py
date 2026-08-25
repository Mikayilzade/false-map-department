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
BUILDER = ROOT / "scripts" / "phase12g_external_acquisition_bundle.py"
VERIFY = ROOT / "scripts" / "phase12g_external_acquisition_bundle_verify.py"
EVIDENCE = ROOT / "empirical" / "evidence"


def digest_tree(root: Path) -> str:
    digest = hashlib.sha256()
    for path in sorted(root.rglob("*")):
        if not path.is_file():
            continue
        digest.update(path.relative_to(root).as_posix().encode())
        digest.update(b"\0")
        digest.update(path.read_bytes())
        digest.update(b"\0")
    return digest.hexdigest()


def run(command: list[str], *, expect: int = 0) -> subprocess.CompletedProcess[str]:
    completed = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, check=False)
    if completed.returncode != expect:
        raise SystemExit(
            f"command returncode mismatch: expected {expect}, got {completed.returncode}\n"
            f"cmd={command}\nstdout={completed.stdout}\nstderr={completed.stderr}"
        )
    return completed


def run_rejected(command: list[str], expected_code: str) -> None:
    completed = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, check=False)
    if completed.returncode == 0 or expected_code not in completed.stdout:
        raise SystemExit(
            f"expected verifier rejection {expected_code}\ncmd={command}\n"
            f"stdout={completed.stdout}\nstderr={completed.stderr}"
        )


def main() -> None:
    head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    evidence_before = digest_tree(EVIDENCE)
    with tempfile.TemporaryDirectory(prefix="fmd-phase12g-external-bundle-") as raw:
        temp = Path(raw)
        bundle = temp / "bundle"
        built = run([sys.executable, str(BUILDER), "--source-head", head, "--output", str(bundle)])
        payload = json.loads(built.stdout.strip().splitlines()[-1])
        if not payload.get("ok") or payload.get("source_head") != head or int(payload.get("archive_member_count", 0)) < 1:
            raise SystemExit("builder did not preserve exact current source head/archive member contract")

        verified = run([sys.executable, str(VERIFY), str(bundle)])
        verify_payload = json.loads(verified.stdout.strip().splitlines()[-1])
        expected_root = f"false-map-department-{head[:12]}/"
        if not verify_payload.get("ok") or verify_payload.get("evidence_appended") is not False:
            raise SystemExit("fresh external acquisition bundle failed offline verification/evidence boundary")
        if verify_payload.get("archive_root") != expected_root:
            raise SystemExit("offline verifier did not preserve the exact archive root contract")
        if int(verify_payload.get("archive_member_count", 0)) != int(payload.get("archive_member_count", -1)):
            raise SystemExit("builder/verifier archive member counts disagree")
        if int(verify_payload.get("required_archive_files", 0)) < 10:
            raise SystemExit("offline verifier did not check the acquisition-critical archive file set")

        manifest_path = bundle / "bundle-manifest.json"
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        if manifest.get("gate_dispositions_changed") is not False or manifest.get("evidence_appended") is not False:
            raise SystemExit("bundle manifest may not claim empirical disposition/evidence mutation")
        archive = bundle / str(verify_payload.get("source_archive", ""))
        if not archive.is_file() or archive.stat().st_size <= 0:
            raise SystemExit("source archive missing from verified bundle")

        # Manifest is intentionally human-readable rather than signed; structural
        # checks must still reject a wrong extraction root/member contract even
        # when the archive bytes themselves were not changed.
        original_manifest = manifest_path.read_text(encoding="utf-8")
        malformed_manifest = json.loads(original_manifest)
        malformed_manifest["archive_contract"]["archive_root"] = "wrong-root/"
        manifest_path.write_text(json.dumps(malformed_manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        run_rejected([sys.executable, str(VERIFY), str(bundle)], "bundle_archive_member_outside_root")
        manifest_path.write_text(original_manifest, encoding="utf-8")

        malformed_manifest = json.loads(original_manifest)
        malformed_manifest["archive_contract"]["member_count"] = int(malformed_manifest["archive_contract"]["member_count"]) + 1
        manifest_path.write_text(json.dumps(malformed_manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        run_rejected([sys.executable, str(VERIFY), str(bundle)], "bundle_archive_member_count_changed")
        manifest_path.write_text(original_manifest, encoding="utf-8")

        guide = bundle / "OPERATOR-GUIDE.md"
        guide.write_text(guide.read_text(encoding="utf-8") + "tamper\n", encoding="utf-8")
        run_rejected([sys.executable, str(VERIFY), str(bundle)], "bundle_file_")

        wrong = "0" * 40 if head != "0" * 40 else "1" * 40
        wrong_out = temp / "wrong"
        wrong_run = subprocess.run(
            [sys.executable, str(BUILDER), "--source-head", wrong, "--output", str(wrong_out)],
            cwd=ROOT,
            capture_output=True,
            text=True,
            check=False,
        )
        if wrong_run.returncode == 0 or "source-head mismatch" not in (wrong_run.stdout + wrong_run.stderr):
            raise SystemExit("builder did not reject a non-checkout source head")
        shutil.rmtree(bundle, ignore_errors=True)
    evidence_after = digest_tree(EVIDENCE)
    if evidence_before != evidence_after:
        raise SystemExit("external bundle audit mutated empirical evidence")
    print(
        "Phase 12G external acquisition bundle audit: PASS "
        "(exact-source archive + offline hash/structure/root/link safety verification + tamper rejection + zero evidence/disposition mutation)"
    )


if __name__ == "__main__":
    main()
