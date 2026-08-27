#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any

SCHEMA = "fmd.phase12g.t8-reference-hardware-profile.v1"
REFERENCE_CLASS = "deck_class_reference"
REFERENCE_ATTESTATION = "actual_deck_class_reference"
REQUIRED_TEXT_FIELDS = (
    "hardware_id",
    "hardware_class",
    "device_model",
    "processor_or_apu",
    "os_name",
    "os_version",
    "godot_version",
    "operator_attestation",
)


def canonical_json(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def canonical_sha256(value: object) -> str:
    return hashlib.sha256(canonical_json(value).encode("utf-8")).hexdigest()


def load(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise ValueError("T8-44 hardware profile must be a JSON object")
    return payload


def validate(profile: dict[str, Any], *, expected_hardware_id: str = "", reference_required: bool = True) -> dict[str, Any]:
    if profile.get("schema") != SCHEMA:
        raise ValueError("T8-44 hardware profile schema unsupported")
    for field in REQUIRED_TEXT_FIELDS:
        value = profile.get(field)
        if not isinstance(value, str) or not value.strip():
            raise ValueError(f"T8-44 hardware profile field {field} must be non-empty text")
    hardware_id = str(profile["hardware_id"]).strip()
    if expected_hardware_id and hardware_id != expected_hardware_id.strip():
        raise ValueError("T8-44 hardware profile hardware_id mismatch")
    if reference_required:
        if str(profile["hardware_class"]).strip() != REFERENCE_CLASS:
            raise ValueError("T8-44 reference evidence requires hardware_class=deck_class_reference")
        if str(profile["operator_attestation"]).strip() != REFERENCE_ATTESTATION:
            raise ValueError("T8-44 reference evidence requires explicit actual Deck-class operator attestation")
    memory_gib = profile.get("memory_gib")
    if isinstance(memory_gib, bool) or not isinstance(memory_gib, (int, float)) or float(memory_gib) <= 0:
        raise ValueError("T8-44 hardware profile memory_gib must be a positive number")
    normalized = {
        "schema": SCHEMA,
        "hardware_id": hardware_id,
        "hardware_class": str(profile["hardware_class"]).strip(),
        "device_model": str(profile["device_model"]).strip(),
        "processor_or_apu": str(profile["processor_or_apu"]).strip(),
        "memory_gib": float(memory_gib),
        "os_name": str(profile["os_name"]).strip(),
        "os_version": str(profile["os_version"]).strip(),
        "godot_version": str(profile["godot_version"]).strip(),
        "operator_attestation": str(profile["operator_attestation"]).strip(),
        "attestation_scope": "operator_observed_hardware_identity_not_software_proof",
    }
    return normalized


def snapshot(profile: dict[str, Any], *, expected_hardware_id: str = "", reference_required: bool = True) -> dict[str, Any]:
    normalized = validate(profile, expected_hardware_id=expected_hardware_id, reference_required=reference_required)
    return {
        "schema": SCHEMA,
        "profile": normalized,
        "profile_sha256": canonical_sha256(normalized),
        "proves_physical_hardware_truth": False,
        "requires_operator_observation": True,
    }


def verify_snapshot(value: dict[str, Any], *, expected_hardware_id: str = "", reference_required: bool = True) -> dict[str, Any]:
    if not isinstance(value, dict) or not isinstance(value.get("profile"), dict):
        raise ValueError("T8-44 hardware profile snapshot missing/malformed")
    expected = snapshot(value["profile"], expected_hardware_id=expected_hardware_id, reference_required=reference_required)
    if canonical_json(value) != canonical_json(expected):
        raise ValueError("T8-44 hardware profile snapshot mismatch")
    return expected
