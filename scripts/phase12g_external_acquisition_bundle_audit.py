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


def main() -> None:
    head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    evidence_before = digest_tree(EVIDENCE)
    with tempfile.TemporaryDirectory(prefix="fmd-phase12g-external-bundle-") as raw:
        temp = Path(raw)
        bundle = temp / "bundle"
        built = run([sys.executable, str(BUILDER), "--source-head", head, "--output", str(bundle)])
        payload = json.loads(built.stdout.strip().splitlines()[-1])
        if not payload.get("ok") or payload.get("source_head") != head:
            raise SystemExit("builder did not preserve exact current source head")
        verified = run([sys.executable, str(VERIFY), str(bundle)])
        verify_payload = json.loads(verified.stdout.strip().splitlines()[-1])
        if not verify_payload.get("ok") or verify_payload.get("evidence_appended") is not False:
            raise SystemExit("fresh external acquisition bundle failed offline verification/evidence boundary")
        manifest = json.loads((bundle / "bundle-manifest.json").read_text(encoding="utf-8"))
        if manifest.get("gate_dispositions_changed") is not False or manifest.get("evidence_appended") is not False:
            raise SystemExit("bundle manifest may not claim empirical disposition/evidence mutation")
        archive = bundle / str(verify_payload.get("source_archive", ""))
        if not archive.is_file() or archive.stat().st_size <= 0:
            raise SystemExit("source archive missing from verified bundle")
        guide = bundle / "OPERATOR-GUIDE.md"
        guide.write_text(guide.read_text(encoding="utf-8") + "tamper\n", encoding="utf-8")
        tampered = subprocess.run([sys.executable, str(VERIFY), str(bundle)], cwd=ROOT, capture_output=True, text=True, check=False)
        if tampered.returncode == 0 or "bundle_file_" not in tampered.stdout:
            raise SystemExit("offline verifier did not reject tampered acquisition material")
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
        "(exact-source archive + offline hash verification + tamper rejection + zero evidence/disposition mutation)"
    )


if __name__ == "__main__":
    main()
