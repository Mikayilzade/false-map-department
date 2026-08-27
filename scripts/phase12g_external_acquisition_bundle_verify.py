#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import tarfile
import unicodedata
from pathlib import Path, PurePosixPath

SCHEMA = "fmd.phase12g.external-acquisition-bundle.v5"
WINDOWS_FORBIDDEN_CHARS = set('<>:"|?*')
WINDOWS_RESERVED_NAMES = {
    "CON", "PRN", "AUX", "NUL",
    *(f"COM{i}" for i in range(1, 10)),
    *(f"LPT{i}" for i in range(1, 10)),
}
REQUIRED_SOURCE_BINDINGS = {
    "BUNDLE-VERIFY.py": "scripts/phase12g_external_acquisition_bundle_verify.py",
    "EXTRACTED-SOURCE-VERIFY.py": "scripts/phase12g_extracted_source_verify.py",
    "FIELD-KIT-VERIFY.py": "scripts/phase12g_field_kit_offline_verify.py",
    "FIELD-KIT-FINALIZE.py": "scripts/phase12g_field_kit_offline_finalize.py",
    "T8-HARDWARE-PROFILE.py": "scripts/phase12g_reference_hardware_profile.py",
    "RETURN-INGEST.md": "empirical/PHASE12G_RETURN_INGEST.md",
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def fail(code: str, detail: str = "") -> None:
    print(json.dumps({"ok": False, "code": code, "detail": detail}, sort_keys=True))
    raise SystemExit(2)


def validate_expected_source_head(value: str) -> str:
    source_head = value.strip().lower()
    if len(source_head) != 40 or any(ch not in "0123456789abcdef" for ch in source_head):
        fail("bundle_expected_source_head_invalid", source_head)
    return source_head


def member_is_within_root(name: str, archive_root: str) -> bool:
    return name == archive_root.rstrip("/") or name.startswith(archive_root)


def portable_component_key(component: str) -> str:
    normalized = unicodedata.normalize("NFC", component)
    return normalized.casefold().rstrip(" .")


def validate_portable_member_name(name: str, archive_root: str) -> str:
    if not name or "\\" in name or any(ord(ch) < 32 or ord(ch) == 127 for ch in name):
        fail("bundle_archive_unsafe_portable_member_path", repr(name))
    pure = PurePosixPath(name)
    if pure.is_absolute() or ".." in pure.parts:
        fail("bundle_archive_unsafe_member_path", name)
    if not member_is_within_root(name, archive_root):
        fail("bundle_archive_member_outside_root", name)
    portable_parts: list[str] = []
    for component in pure.parts:
        if component in {"", "."}:
            continue
        if component.endswith((" ", ".")) or any(ch in WINDOWS_FORBIDDEN_CHARS for ch in component):
            fail("bundle_archive_windows_unsafe_component", repr(component))
        stem = component.split(".", 1)[0].upper()
        if stem in WINDOWS_RESERVED_NAMES:
            fail("bundle_archive_windows_reserved_component", repr(component))
        portable_parts.append(portable_component_key(component))
    return "/".join(portable_parts)


def verify_archive(path: Path, contract: dict) -> dict:
    archive_root = str(contract.get("archive_root", ""))
    if not archive_root or archive_root.startswith("/") or ".." in PurePosixPath(archive_root).parts or not archive_root.endswith("/"):
        fail("bundle_archive_root_invalid", archive_root)
    required = contract.get("required_regular_files", [])
    if not isinstance(required, list) or not required:
        fail("bundle_archive_required_files_missing")
    expected_count = int(contract.get("member_count", -1))
    if expected_count < 1:
        fail("bundle_archive_member_count_invalid", str(expected_count))
    required_flags = (
        "forbid_links",
        "forbid_special_file_types",
        "forbid_absolute_or_parent_paths",
        "forbid_backslash_or_control_paths",
        "forbid_windows_unsafe_components",
        "forbid_duplicate_member_paths",
        "forbid_portable_path_collisions",
    )
    if any(contract.get(flag) is not True for flag in required_flags):
        fail("bundle_archive_safety_contract_invalid")

    required_members = {archive_root + str(rel) for rel in required}
    seen_files: set[str] = set()
    seen_names: set[str] = set()
    portable_keys: dict[str, str] = {}
    member_count = 0
    try:
        with tarfile.open(path, "r:gz") as archive:
            for member in archive.getmembers():
                member_count += 1
                name = member.name
                portable_key = validate_portable_member_name(name, archive_root)
                if name in seen_names:
                    fail("bundle_archive_duplicate_member_path", name)
                seen_names.add(name)
                previous = portable_keys.get(portable_key)
                if previous is not None and previous != name:
                    fail("bundle_archive_portable_path_collision", f"{previous!r} vs {name!r}")
                portable_keys[portable_key] = name
                if member.issym() or member.islnk():
                    fail("bundle_archive_link_forbidden", name)
                if not (member.isfile() or member.isdir()):
                    fail("bundle_archive_special_file_forbidden", name)
                if member.isfile():
                    seen_files.add(name)
    except tarfile.TarError as exc:
        fail("bundle_archive_malformed", str(exc))

    if member_count != expected_count:
        fail("bundle_archive_member_count_changed", f"expected={expected_count}, actual={member_count}")
    missing = sorted(required_members - seen_files)
    if missing:
        fail("bundle_archive_required_member_missing", ",".join(missing))
    return {
        "archive_root": archive_root,
        "archive_member_count": member_count,
        "required_archive_files": len(required_members),
        "required_regular_files": [str(item) for item in required],
    }


def read_archive_member(archive_path: Path, archive_root: str, source_path: str) -> bytes:
    member_name = archive_root + source_path
    try:
        with tarfile.open(archive_path, "r:gz") as archive:
            try:
                member = archive.getmember(member_name)
            except KeyError:
                fail("bundle_source_binding_archive_member_missing", source_path)
            if not member.isfile():
                fail("bundle_source_binding_archive_member_not_file", source_path)
            handle = archive.extractfile(member)
            if handle is None:
                fail("bundle_source_binding_archive_member_unreadable", source_path)
            return handle.read()
    except tarfile.TarError as exc:
        fail("bundle_archive_malformed", str(exc))
    return b""


def verify_source_bindings(root: Path, archive_path: Path, archive_result: dict, manifest: dict) -> int:
    rows = manifest.get("source_bindings", [])
    if not isinstance(rows, list):
        fail("bundle_source_bindings_malformed")
    by_bundle: dict[str, dict] = {}
    for index, raw in enumerate(rows):
        if not isinstance(raw, dict):
            fail("bundle_source_binding_entry_malformed", str(index))
        bundle_path = str(raw.get("bundle_path", ""))
        if not bundle_path or bundle_path in by_bundle:
            fail("bundle_source_binding_bundle_path_invalid", bundle_path)
        by_bundle[bundle_path] = raw
    if set(by_bundle) != set(REQUIRED_SOURCE_BINDINGS):
        missing = sorted(set(REQUIRED_SOURCE_BINDINGS) - set(by_bundle))
        extra = sorted(set(by_bundle) - set(REQUIRED_SOURCE_BINDINGS))
        fail("bundle_source_binding_set_mismatch", f"missing={missing}, extra={extra}")

    required_archive_paths = set(archive_result.get("required_regular_files", []))
    for bundle_path, expected_source_path in sorted(REQUIRED_SOURCE_BINDINGS.items()):
        row = by_bundle[bundle_path]
        source_path = str(row.get("source_archive_path", ""))
        if source_path != expected_source_path:
            fail("bundle_source_binding_source_path_mismatch", f"{bundle_path}:{source_path}")
        if source_path not in required_archive_paths:
            fail("bundle_source_binding_not_required_archive_member", source_path)
        target = root / bundle_path
        if not target.is_file():
            fail("bundle_source_binding_file_missing", bundle_path)
        root_bytes = target.read_bytes()
        archive_bytes = read_archive_member(archive_path, str(archive_result["archive_root"]), source_path)
        expected_hash = str(row.get("sha256", ""))
        expected_bytes = int(row.get("bytes", -1))
        if expected_bytes != len(root_bytes) or expected_bytes != len(archive_bytes):
            fail("bundle_source_binding_size_mismatch", bundle_path)
        root_hash = sha256_bytes(root_bytes)
        archive_hash = sha256_bytes(archive_bytes)
        if not expected_hash or root_hash != expected_hash or archive_hash != expected_hash or root_bytes != archive_bytes:
            fail("bundle_source_binding_hash_mismatch", bundle_path)
    return len(REQUIRED_SOURCE_BINDINGS)


def verify(root: Path, expected_source_head: str) -> dict:
    manifest_path = root / "bundle-manifest.json"
    if not manifest_path.is_file():
        fail("bundle_manifest_missing")
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except Exception as exc:
        fail("bundle_manifest_malformed", str(exc))
    if manifest.get("schema") != SCHEMA:
        fail("bundle_schema_unsupported", str(manifest.get("schema")))
    source_head = str(manifest.get("source_head", ""))
    if len(source_head) != 40 or any(ch not in "0123456789abcdef" for ch in source_head):
        fail("bundle_source_head_invalid", source_head)
    if source_head != expected_source_head:
        fail("bundle_expected_source_head_mismatch", f"expected={expected_source_head}, bundle={source_head}")
    source_file = root / "SOURCE_HEAD.txt"
    if not source_file.is_file() or source_file.read_text(encoding="utf-8").strip() != source_head:
        fail("bundle_source_head_file_mismatch")
    if manifest.get("evidence_appended") is not False or manifest.get("gate_dispositions_changed") is not False:
        fail("bundle_evidence_boundary_invalid")
    rows = manifest.get("files", [])
    if not isinstance(rows, list) or not rows:
        fail("bundle_files_missing")
    seen: set[str] = set()
    for index, row in enumerate(rows):
        if not isinstance(row, dict):
            fail("bundle_file_entry_malformed", str(index))
        name = str(row.get("path", ""))
        if not name or name in seen or "/" in name or "\\" in name or name in {".", ".."}:
            fail("bundle_file_path_invalid", name)
        seen.add(name)
        path = root / name
        if not path.is_file():
            fail("bundle_file_missing", name)
        if path.stat().st_size != int(row.get("bytes", -1)):
            fail("bundle_file_size_changed", name)
        if sha256(path) != str(row.get("sha256", "")):
            fail("bundle_file_hash_changed", name)
    required = {"SOURCE_HEAD.txt", "OPERATOR-GUIDE.md", *REQUIRED_SOURCE_BINDINGS.keys()}
    if not required.issubset(seen):
        fail("bundle_required_file_missing", ",".join(sorted(required - seen)))
    archives = [name for name in seen if name.endswith(".tar.gz")]
    if len(archives) != 1:
        fail("bundle_source_archive_count_invalid", str(len(archives)))
    archive_name = archives[0]
    archive_path = root / archive_name
    archive_result = verify_archive(archive_path, manifest.get("archive_contract", {}))
    binding_count = verify_source_bindings(root, archive_path, archive_result, manifest)
    return {
        "ok": True,
        "source_head": source_head,
        "expected_source_head": expected_source_head,
        "verified_files": len(rows),
        "source_archive": archive_name,
        "archive_root": archive_result["archive_root"],
        "archive_member_count": archive_result["archive_member_count"],
        "required_archive_files": archive_result["required_archive_files"],
        "source_binding_count": binding_count,
        "evidence_appended": False,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Verify a Phase 12G external acquisition bundle against an independently known exact source commit.")
    parser.add_argument("root", nargs="?", default=".")
    parser.add_argument("--expected-source-head", required=True)
    args = parser.parse_args()
    expected_source_head = validate_expected_source_head(args.expected_source_head)
    print(json.dumps(verify(Path(args.root).resolve(), expected_source_head), sort_keys=True))


if __name__ == "__main__":
    main()
