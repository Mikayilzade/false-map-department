#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import re

SHA40 = re.compile(r"^[0-9a-f]{40}$")
ROLES = {"demo", "production"}
SCHEMA = "fmd.phase12g.source-bound-build.v1"


def normalize_source_head(value: str) -> str:
    source_head = str(value).strip().lower()
    if not SHA40.fullmatch(source_head):
        raise ValueError("source_head must be an exact 40-character lowercase Git commit SHA")
    return source_head


def normalize_build_id(value: object) -> str:
    build_id = str(value).strip()
    if not build_id:
        raise ValueError("build_id must be non-empty")
    return build_id


def normalize_role(value: str) -> str:
    role = str(value).strip().lower()
    if role not in ROLES:
        raise ValueError(f"unsupported build role: {role}")
    return role


def binding_id(source_head: str, role: str, build_id: object) -> str:
    payload = {
        "schema": SCHEMA,
        "role": normalize_role(role),
        "source_head": normalize_source_head(source_head),
        "build_id": normalize_build_id(build_id),
    }
    encoded = json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def identity_record(source_head: str, role: str, build_id: object) -> dict[str, str]:
    source_head = normalize_source_head(source_head)
    role = normalize_role(role)
    build_id = normalize_build_id(build_id)
    return {
        "schema": SCHEMA,
        "role": role,
        "source_head": source_head,
        "build_id": build_id,
        "binding_id": binding_id(source_head, role, build_id),
    }


def validate_identity(record: object, *, source_head: str, role: str, build_id: object) -> dict[str, str]:
    if not isinstance(record, dict):
        raise ValueError("build identity record must be an object")
    expected = identity_record(source_head, role, build_id)
    if record != expected:
        raise ValueError(
            "build identity mismatch: expected exact source/build/role binding "
            f"{expected['binding_id']}, got {record.get('binding_id', '<missing>')}"
        )
    return expected
