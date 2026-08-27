#!/usr/bin/env python3
from __future__ import annotations

import argparse
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


def reference_template(hardware_id: str) -> dict[str, Any]:
    hardware_id = hardware_id.strip()
    if not hardware_id:
        raise ValueError("hardware_id must be non-empty")
    return {
        "schema": SCHEMA,
        "hardware_id": hardware_id,
        "hardware_class": REFERENCE_CLASS,
        "device_model": "FILL_ACTUAL_DEVICE_MODEL",
        "processor_or_apu": "FILL_ACTUAL_PROCESSOR_OR_APU",
        "memory_gib": 0,
        "os_name": "FILL_ACTUAL_OS_NAME",
        "os_version": "FILL_ACTUAL_OS_VERSION",
        "godot_version": "4.7.1.stable",
        "operator_attestation": REFERENCE_ATTESTATION,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Create or validate a structured T8-44 Deck-class reference-hardware profile. The profile is operator-observed acquisition metadata, not software proof of physical hardware.")
    sub = parser.add_subparsers(dest="command", required=True)
    template = sub.add_parser("template")
    template.add_argument("--hardware-id", required=True)
    template.add_argument("--output", type=Path, required=True)
    check = sub.add_parser("validate")
    check.add_argument("--profile", type=Path, required=True)
    check.add_argument("--hardware-id", default="")
    args = parser.parse_args()
    if args.command == "template":
        if args.output.exists():
            raise SystemExit("refusing to overwrite existing hardware profile")
        payload = reference_template(args.hardware_id)
        args.output.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        print(json.dumps({"status": "TEMPLATE_WRITTEN", "output": str(args.output), "requires_actual_values_before_reference_run": True}, sort_keys=True))
        return
    try:
        result = snapshot(load(args.profile), expected_hardware_id=args.hardware_id, reference_required=True)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        raise SystemExit(str(exc)) from exc
    print(json.dumps({"status": "VALID", "profile_sha256": result["profile_sha256"], "proves_physical_hardware_truth": False, "requires_operator_observation": True}, sort_keys=True))


if __name__ == "__main__":
    main()
