#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

SCHEMA = "fmd.phase12g.external-acquisition-bundle.v1"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def fail(code: str, detail: str = "") -> None:
    print(json.dumps({"ok": False, "code": code, "detail": detail}, sort_keys=True))
    raise SystemExit(2)


def verify(root: Path) -> dict:
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
    required = {"SOURCE_HEAD.txt", "OPERATOR-GUIDE.md", "BUNDLE-VERIFY.py"}
    if not required.issubset(seen):
        fail("bundle_required_file_missing", ",".join(sorted(required - seen)))
    archives = [name for name in seen if name.endswith(".tar.gz")]
    if len(archives) != 1:
        fail("bundle_source_archive_count_invalid", str(len(archives)))
    return {"ok": True, "source_head": source_head, "verified_files": len(rows), "source_archive": archives[0], "evidence_appended": False}


def main() -> None:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
    print(json.dumps(verify(root), sort_keys=True))


if __name__ == "__main__":
    main()
