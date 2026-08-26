#!/usr/bin/env python3
from __future__ import annotations

import os
import re
from pathlib import Path

SHA40 = re.compile(r"^[0-9a-f]{40}$")
PROVENANCE_VERSION = 2
ARTIFACT_RECORD_ENV = "FMD_PHASE12G_BUILD_ARTIFACT_RECORD"
ARTIFACT_PATH_ENV = "FMD_PHASE12G_BUILD_ARTIFACT_PATH"
EXTERNAL_CHANNELS = {"human_field_kit_v4", "e8_marketing_packet", "t8_reference_profile"}


def validate_source_head(value: str) -> str:
    source_head = str(value).strip().lower()
    if not SHA40.fullmatch(source_head):
        raise ValueError("source_head must be an exact 40-character lowercase Git commit SHA")
    return source_head


def _required_text(value: object, label: str) -> str:
    text = str(value).strip()
    if not text:
        raise ValueError(f"{label} must be non-empty")
    return text


def _artifact_fields(*, source_head: str, build_id: str, channel: str) -> dict:
    record_value = os.environ.get(ARTIFACT_RECORD_ENV, "").strip()
    artifact_value = os.environ.get(ARTIFACT_PATH_ENV, "").strip()
    if not record_value and not artifact_value:
        return {}
    if not record_value or not artifact_value:
        raise ValueError(
            f"{ARTIFACT_RECORD_ENV} and {ARTIFACT_PATH_ENV} must be supplied together"
        )
    try:
        import phase12g_build_artifact_contract as artifact_contract
        record = artifact_contract.load_record(Path(record_value).expanduser().resolve())
        verified = artifact_contract.verify_record(
            record,
            artifact_path=Path(artifact_value).expanduser().resolve(),
            source_head=source_head,
            build_id=build_id,
        )
    except (OSError, ValueError) as exc:
        raise ValueError(f"build artifact verification failed: {exc}") from exc
    return {
        "source_build_role": str(verified["role"]),
        "build_artifact_sha256": str(verified["artifact_sha256"]),
        "build_artifact_bytes": int(verified["artifact_bytes"]),
        "build_artifact_binding_id": str(verified["binding_id"]),
        "build_artifact_filename": str(verified["artifact_filename"]),
        "build_artifact_bytes_verified": True,
    }


def enrich_row(row: dict, *, source_head: str, build_id: object, channel: str) -> dict:
    if not isinstance(row, dict):
        raise ValueError("row must be an object")
    normalized_source = validate_source_head(source_head)
    normalized_build = _required_text(build_id, "build_id")
    normalized_channel = _required_text(channel, "channel")
    expected = {
        "evidence_provenance_version": PROVENANCE_VERSION,
        "source_head": normalized_source,
        "source_build_id": normalized_build,
        "acquisition_channel": normalized_channel,
    }
    artifact_fields = _artifact_fields(
        source_head=normalized_source,
        build_id=normalized_build,
        channel=normalized_channel,
    )
    expected.update(artifact_fields)
    for key, value in expected.items():
        if key in row and row[key] != value:
            raise ValueError(f"provenance conflict for {key}")
    out = dict(row)
    out.update(expected)
    if normalized_channel in EXTERNAL_CHANNELS and not artifact_fields:
        # Missing packaged bytes is a valid dry-run/readiness state, never append-ready evidence.
        out["build_artifact_bytes_verified"] = False
    return out


def enrich_rows(rows: list[dict], *, source_head: str, build_id: object, channel: str) -> list[dict]:
    return [enrich_row(row, source_head=source_head, build_id=build_id, channel=channel) for row in rows]
