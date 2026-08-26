#!/usr/bin/env python3
from __future__ import annotations

import re

SHA40 = re.compile(r"^[0-9a-f]{40}$")
ROLES = {"demo", "production"}
SCHEMA = "fmd.phase12g.source-bound-build.v1"


def normalize_source_head(value: str) -> str:
    source_head = str(value).strip().lower()
    if not SHA40.fullmatch(source_head):
        raise ValueError("source_head must be an exact 40-character lowercase Git commit SHA")
    return source_head


def expected_build_id(source_head: str, role: str) -> str:
    source_head = normalize_source_head(source_head)
    role = str(role).strip().lower()
    if role not in ROLES:
        raise ValueError(f"unsupported build role: {role}")
    return f"fmd-{role}-src-{source_head}"


def validate_build_id(build_id: str, source_head: str, role: str) -> str:
    expected = expected_build_id(source_head, role)
    actual = str(build_id).strip()
    if actual != expected:
        raise ValueError(
            f"{role} build_id/source_head mismatch: expected {expected}, got {actual or '<blank>'}"
        )
    return actual


def identity_record(source_head: str, role: str, build_id: str | None = None) -> dict[str, str]:
    source_head = normalize_source_head(source_head)
    role = str(role).strip().lower()
    expected = expected_build_id(source_head, role)
    if build_id is not None:
        validate_build_id(build_id, source_head, role)
    return {
        "schema": SCHEMA,
        "role": role,
        "source_head": source_head,
        "build_id": expected,
    }
