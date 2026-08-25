#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import io
import json
import shutil
import subprocess
import sys
import tarfile
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


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
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


def rewrite_archive_with_extra_member(archive_path: Path, member: tarfile.TarInfo, data: bytes = b"") -> None:
    rewritten = archive_path.with_suffix(".rewrite.tar.gz")
    with tarfile.open(archive_path, "r:gz") as source, tarfile.open(rewritten, "w:gz") as target:
        for existing in source.getmembers():
            fileobj = source.extractfile(existing) if existing.isfile() else None
            target.addfile(existing, fileobj)
        member.size = len(data)
        target.addfile(member, io.BytesIO(data) if data else None)
    rewritten.replace(archive_path)


def refresh_archive_manifest(manifest_path: Path, archive_path: Path, member_delta: int) -> None:
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    manifest["archive_contract"]["member_count"] = int(manifest["archive_contract"]["member_count"]) + member_delta
    found = False
    for row in manifest["files"]:
        if row.get("path") == archive_path.name:
            row["bytes"] = archive_path.stat().st_size
            row["sha256"] = sha256(archive_path)
            found = True
            break
    if not found:
        raise SystemExit("archive file row missing while preparing adversarial portable-path fixture")
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")


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
        if manifest.get("schema") != "fmd.phase12g.external-acquisition-bundle.v3":
            raise SystemExit("portable bundle must use the hardened v3 schema")
        required_safety_flags = {
            "forbid_links",
            "forbid_special_file_types",
            "forbid_absolute_or_parent_paths",
            "forbid_backslash_or_control_paths",
            "forbid_windows_unsafe_components",
            "forbid_duplicate_member_paths",
            "forbid_portable_path_collisions",
        }
        contract = manifest.get("archive_contract", {})
        if any(contract.get(flag) is not True for flag in required_safety_flags):
            raise SystemExit("bundle manifest is missing a mandatory portable archive-safety contract flag")
        if manifest.get("gate_dispositions_changed") is not False or manifest.get("evidence_appended") is not False:
            raise SystemExit("bundle manifest may not claim empirical disposition/evidence mutation")
        archive = bundle / str(verify_payload.get("source_archive", ""))
        if not archive.is_file() or archive.stat().st_size <= 0:
            raise SystemExit("source archive missing from verified bundle")

        original_manifest = manifest_path.read_text(encoding="utf-8")
        pristine_archive = temp / "pristine-source.tar.gz"
        shutil.copy2(archive, pristine_archive)

        # Contract-only corruption still rejects even when archive bytes are untouched.
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

        # Simulate a recomputed manifest around structurally dangerous archive bytes.
        # This proves the verifier's extraction-safety checks are independent of hashes.
        backslash = tarfile.TarInfo(expected_root + "scripts\\portable-escape.py")
        rewrite_archive_with_extra_member(archive, backslash, b"unsafe")
        refresh_archive_manifest(manifest_path, archive, 1)
        run_rejected([sys.executable, str(VERIFY), str(bundle)], "bundle_archive_unsafe_portable_member_path")
        shutil.copy2(pristine_archive, archive)
        manifest_path.write_text(original_manifest, encoding="utf-8")

        duplicate = tarfile.TarInfo(expected_root + "IMPLEMENTATION_START_HERE.md")
        rewrite_archive_with_extra_member(archive, duplicate, b"duplicate")
        refresh_archive_manifest(manifest_path, archive, 1)
        run_rejected([sys.executable, str(VERIFY), str(bundle)], "bundle_archive_duplicate_member_path")
        shutil.copy2(pristine_archive, archive)
        manifest_path.write_text(original_manifest, encoding="utf-8")

        case_collision = tarfile.TarInfo(expected_root + "implementation_start_here.md")
        rewrite_archive_with_extra_member(archive, case_collision, b"collision")
        refresh_archive_manifest(manifest_path, archive, 1)
        run_rejected([sys.executable, str(VERIFY), str(bundle)], "bundle_archive_portable_path_collision")
        shutil.copy2(pristine_archive, archive)
        manifest_path.write_text(original_manifest, encoding="utf-8")

        special = tarfile.TarInfo(expected_root + "portable-fifo")
        special.type = tarfile.FIFOTYPE
        rewrite_archive_with_extra_member(archive, special)
        refresh_archive_manifest(manifest_path, archive, 1)
        run_rejected([sys.executable, str(VERIFY), str(bundle)], "bundle_archive_special_file_forbidden")
        shutil.copy2(pristine_archive, archive)
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
        "(exact-source archive + offline hash/root/link/type/portable-path collision safety + adversarial rejection + zero evidence/disposition mutation)"
    )


if __name__ == "__main__":
    main()
