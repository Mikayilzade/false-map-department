#!/usr/bin/env python3
from __future__ import annotations

import re

SHA40 = re.compile(r"^[0-9a-f]{40}$")
PROVENANCE_VERSION = 1


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


def enrich_row(row: dict, *, source_head: str, build_id: object, channel: str) -> dict:
    if not isinstance(row, dict):
        raise ValueError("row must be an object")
    expected = {
        "evidence_provenance_version": PROVENANCE_VERSION,
        "source_head": validate_source_head(source_head),
        "source_build_id": _required_text(build_id, "build_id"),
        "acquisition_channel": _required_text(channel, "channel"),
    }
    for key, value in expected.items():
        if key in row and row[key] != value:
            raise ValueError(f"provenance conflict for {key}")
    out = dict(row)
    out.update(expected)
    return out


def enrich_rows(rows: list[dict], *, source_head: str, build_id: object, channel: str) -> list[dict]:
    return [enrich_row(row, source_head=source_head, build_id=build_id, channel=channel) for row in rows]
