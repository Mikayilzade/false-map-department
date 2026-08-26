#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import shutil
from pathlib import Path
from typing import Any

import phase12g_build_artifact_contract as artifact_contract

SCHEMA = "fmd.phase12g.acquisition-build-binding.v1"


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _safe_relative(root: Path, relative: str, label: str) -> Path:
    raw = Path(relative)
    if raw.is_absolute() or ".." in raw.parts:
        raise ValueError(f"{label} must remain relative to acquisition root")
    candidate = (root / raw).resolve()
    try:
        candidate.relative_to(root.resolve())
    except ValueError as exc:
        raise ValueError(f"{label} escapes acquisition root") from exc
    return candidate


def freeze_into_root(
    *,
    root: Path,
    source_head: str,
    role: str,
    build_id: str,
    artifact_path: Path,
    record_path: Path,
) -> dict[str, Any]:
    root = root.resolve()
    artifact_path = artifact_path.resolve()
    record_path = record_path.resolve()
    record = artifact_contract.verify_record(
        artifact_contract.load_record(record_path),
        artifact_path=artifact_path,
        source_head=source_head,
        build_id=build_id,
        role=role,
    )
    store = root / "build-artifacts"
    store.mkdir(parents=True, exist_ok=True)
    suffix = artifact_path.suffix
    frozen_artifact = store / f"{role}-package{suffix}"
    frozen_record = store / f"{role}-binding.json"
    if frozen_artifact.exists() or frozen_record.exists():
        raise ValueError(f"refusing to overwrite frozen {role} build binding")
    shutil.copy2(artifact_path, frozen_artifact)
    shutil.copy2(record_path, frozen_record)
    verified = artifact_contract.verify_record(
        artifact_contract.load_record(frozen_record),
        artifact_path=frozen_artifact,
        source_head=source_head,
        build_id=build_id,
        role=role,
    )
    return {
        "schema": SCHEMA,
        "source_head": verified["source_head"],
        "role": verified["role"],
        "build_id": verified["build_id"],
        "binding_id": verified["binding_id"],
        "artifact_sha256": verified["artifact_sha256"],
        "artifact_bytes": verified["artifact_bytes"],
        "artifact_filename": verified["artifact_filename"],
        "packet_artifact_path": frozen_artifact.relative_to(root).as_posix(),
        "packet_record_path": frozen_record.relative_to(root).as_posix(),
        "acquisition_bytes_frozen": True,
        "evidence_appended": False,
    }


def verify_frozen(root: Path, snapshot: object, *, source_head: str, role: str, build_id: str) -> dict[str, Any]:
    if not isinstance(snapshot, dict) or snapshot.get("schema") != SCHEMA:
        raise ValueError("acquisition build binding snapshot missing or unsupported")
    for key, expected in {
        "source_head": source_head,
        "role": role,
        "build_id": build_id,
    }.items():
        if str(snapshot.get(key, "")) != str(expected):
            raise ValueError(f"acquisition build binding {key} mismatch")
    artifact = _safe_relative(root, str(snapshot.get("packet_artifact_path", "")), "packet artifact path")
    record_path = _safe_relative(root, str(snapshot.get("packet_record_path", "")), "packet binding record path")
    record = artifact_contract.verify_record(
        artifact_contract.load_record(record_path),
        artifact_path=artifact,
        source_head=source_head,
        build_id=build_id,
        role=role,
    )
    for key in ("binding_id", "artifact_sha256", "artifact_bytes", "artifact_filename"):
        if snapshot.get(key) != record.get(key):
            raise ValueError(f"acquisition build binding snapshot drift: {key}")
    if snapshot.get("acquisition_bytes_frozen") is not True or snapshot.get("evidence_appended") is not False:
        raise ValueError("acquisition build binding boundary flags invalid")
    if sha256_file(artifact) != str(snapshot.get("artifact_sha256", "")):
        raise ValueError("frozen acquisition artifact digest mismatch")
    return dict(snapshot)
