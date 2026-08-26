#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
import sys
import tarfile
from pathlib import Path, PurePosixPath

SHA40 = 40


def fail(code: str, detail: str = "") -> None:
    payload = {"ok": False, "code": code}
    if detail:
        payload["detail"] = detail
    print(json.dumps(payload, sort_keys=True))
    raise SystemExit(1)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def validate_expected_head(value: str) -> str:
    value = value.strip().lower()
    if len(value) != SHA40 or any(ch not in "0123456789abcdef" for ch in value):
        fail("extracted_expected_source_head_invalid")
    return value


def load_manifest(bundle: Path) -> dict:
    path = bundle / "bundle-manifest.json"
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        fail("extracted_bundle_manifest_unreadable", str(exc))
    if not isinstance(payload, dict):
        fail("extracted_bundle_manifest_malformed")
    return payload


def verify_bundle(bundle: Path, expected_head: str) -> dict:
    verifier = bundle / "BUNDLE-VERIFY.py"
    if not verifier.is_file():
        fail("extracted_bundle_verifier_missing")
    completed = subprocess.run(
        [sys.executable, str(verifier), str(bundle), "--expected-source-head", expected_head],
        cwd=bundle,
        text=True,
        capture_output=True,
        check=False,
    )
    if completed.returncode != 0:
        fail("extracted_bundle_verification_failed", (completed.stdout + completed.stderr).strip())
    try:
        result = json.loads(completed.stdout.strip().splitlines()[-1])
    except (json.JSONDecodeError, IndexError) as exc:
        fail("extracted_bundle_verifier_output_malformed", str(exc))
    if not isinstance(result, dict) or not result.get("ok"):
        fail("extracted_bundle_verifier_disposition_invalid")
    if result.get("expected_source_head") != expected_head:
        fail("extracted_bundle_expected_source_not_preserved")
    return result


def safe_relative(name: str, archive_root: str) -> str:
    root_member = archive_root.rstrip("/")
    if name == root_member:
        return ""
    if not name.startswith(archive_root):
        fail("extracted_archive_member_outside_root", name)
    rel = name[len(archive_root):].rstrip("/")
    if not rel:
        return ""
    pure = PurePosixPath(rel)
    if pure.is_absolute() or ".." in pure.parts or "\\" in rel:
        fail("extracted_archive_member_path_unsafe", name)
    return pure.as_posix()


def archive_contract(archive_path: Path, archive_root: str) -> tuple[dict[str, tuple[str, str, int]], set[str]]:
    files: dict[str, tuple[str, str, int]] = {}
    dirs: set[str] = set()
    try:
        archive = tarfile.open(archive_path, "r:gz")
    except (OSError, tarfile.TarError) as exc:
        fail("extracted_source_archive_unreadable", str(exc))
    with archive:
        for member in archive.getmembers():
            rel = safe_relative(member.name, archive_root)
            if not rel:
                continue
            if member.issym() or member.islnk() or not (member.isfile() or member.isdir()):
                fail("extracted_archive_member_type_forbidden", member.name)
            if member.isdir():
                dirs.add(rel)
                continue
            handle = archive.extractfile(member)
            if handle is None:
                fail("extracted_archive_member_unreadable", member.name)
            data = handle.read()
            files[rel] = (hashlib.sha256(data).hexdigest(), "file", member.mode & 0o111)
            parent = PurePosixPath(rel).parent
            while parent.as_posix() not in {".", ""}:
                dirs.add(parent.as_posix())
                parent = parent.parent
    return files, dirs


def filesystem_contract(root: Path) -> tuple[dict[str, tuple[str, str, int]], set[str]]:
    if not root.is_dir():
        fail("extracted_source_root_missing", str(root))
    files: dict[str, tuple[str, str, int]] = {}
    dirs: set[str] = set()
    for path in sorted(root.rglob("*")):
        rel = path.relative_to(root).as_posix()
        if path.is_symlink():
            fail("extracted_source_symlink_forbidden", rel)
        if path.is_dir():
            dirs.add(rel)
        elif path.is_file():
            files[rel] = (sha256_file(path), "file", os.stat(path).st_mode & 0o111)
        else:
            fail("extracted_source_special_file_forbidden", rel)
    return files, dirs


def main() -> None:
    parser = argparse.ArgumentParser(description="Verify that an extracted Phase 12G source tree is byte-for-byte the independently source-pinned bundle archive, without trusting its directory name or SOURCE_HEAD.txt")
    parser.add_argument("bundle_dir")
    parser.add_argument("extracted_source_dir")
    parser.add_argument("--expected-source-head", required=True)
    args = parser.parse_args()

    expected_head = validate_expected_head(args.expected_source_head)
    bundle = Path(args.bundle_dir).resolve()
    extracted = Path(args.extracted_source_dir).resolve()
    verify_result = verify_bundle(bundle, expected_head)
    manifest = load_manifest(bundle)
    if manifest.get("source_head") != expected_head:
        fail("extracted_manifest_source_head_mismatch")

    archive_name = str(verify_result.get("source_archive", ""))
    archive_root = str(verify_result.get("archive_root", ""))
    if not archive_name or not archive_root:
        fail("extracted_verified_archive_identity_missing")
    archive_path = bundle / archive_name
    if not archive_path.is_file():
        fail("extracted_source_archive_missing", archive_name)

    expected_files, expected_dirs = archive_contract(archive_path, archive_root)
    actual_files, actual_dirs = filesystem_contract(extracted)
    if set(actual_files) != set(expected_files):
        missing = sorted(set(expected_files) - set(actual_files))
        extra = sorted(set(actual_files) - set(expected_files))
        fail("extracted_source_file_set_mismatch", json.dumps({"missing": missing[:20], "extra": extra[:20]}, sort_keys=True))
    if actual_dirs != expected_dirs:
        missing = sorted(expected_dirs - actual_dirs)
        extra = sorted(actual_dirs - expected_dirs)
        fail("extracted_source_directory_set_mismatch", json.dumps({"missing": missing[:20], "extra": extra[:20]}, sort_keys=True))
    for rel in sorted(expected_files):
        expected_hash, _, expected_exec = expected_files[rel]
        actual_hash, _, actual_exec = actual_files[rel]
        if actual_hash != expected_hash:
            fail("extracted_source_file_hash_mismatch", rel)
        if bool(actual_exec) != bool(expected_exec):
            fail("extracted_source_executable_mode_mismatch", rel)

    print(json.dumps({
        "ok": True,
        "status": "EXTRACTED_SOURCE_VERIFIED",
        "expected_source_head": expected_head,
        "source_archive": archive_name,
        "archive_root": archive_root,
        "extracted_root_name_trusted": False,
        "source_head_text_trusted": False,
        "file_count": len(expected_files),
        "directory_count": len(expected_dirs),
        "evidence_appended": False,
        "gate_dispositions_changed": False,
    }, sort_keys=True))


if __name__ == "__main__":
    main()
