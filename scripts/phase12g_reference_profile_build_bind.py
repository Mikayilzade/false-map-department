#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import phase12g_acquisition_build_binding as acquisition_binding
import phase12g_reference_hardware_profile as hardware_profile
import phase12g_reference_profile_target as profile_target

BINDING_FILENAME = "acquisition-build-binding.json"
CAPTURE_SCHEMA = "fmd.phase12g.t8-reference-capture-binding.v2"


def canonical_json(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def canonical_sha256(value: object) -> str:
    return hashlib.sha256(canonical_json(value).encode("utf-8")).hexdigest()


def load_packet(path: Path) -> dict:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise ValueError("T8-44 profile packet must be a JSON object")
    return payload


def prepare(root: Path, *, source_head: str, build_id: str, artifact: Path, record: Path) -> dict:
    root = root.resolve()
    root.mkdir(parents=True, exist_ok=True)
    sidecar_path = root / BINDING_FILENAME
    if sidecar_path.exists():
        raise ValueError("refusing to overwrite T8-44 acquisition build binding")
    snapshot = acquisition_binding.freeze_into_root(
        root=root,
        source_head=source_head,
        role="production",
        build_id=build_id,
        artifact_path=artifact,
        record_path=record,
    )
    sidecar_path.write_text(json.dumps(snapshot, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return snapshot


def verify_prepared(root: Path, *, source_head: str, build_id: str) -> dict:
    sidecar_path = root.resolve() / BINDING_FILENAME
    if not sidecar_path.is_file():
        raise ValueError("T8-44 acquisition packet is NOT APPEND READY: packaged build binding missing")
    snapshot = json.loads(sidecar_path.read_text(encoding="utf-8"))
    return acquisition_binding.verify_frozen(
        root,
        snapshot,
        source_head=source_head,
        role="production",
        build_id=build_id,
    )


def _hardware_snapshot(packet: dict, *, reference_required: bool) -> dict:
    row = packet.get("profile_row", {})
    if not isinstance(row, dict):
        raise ValueError("T8-44 profile_row missing/malformed")
    hardware_id = str(row.get("hardware_id", ""))
    existing = packet.get("hardware_profile_snapshot")
    if isinstance(existing, dict):
        return hardware_profile.verify_snapshot(
            existing,
            expected_hardware_id=hardware_id,
            reference_required=reference_required,
        )
    raw = packet.get("hardware_profile")
    if not isinstance(raw, dict):
        raise ValueError("T8-44 reference capture requires structured hardware_profile")
    return hardware_profile.snapshot(
        raw,
        expected_hardware_id=hardware_id,
        reference_required=reference_required,
    )


def capture_payload(packet: dict) -> dict:
    row = packet.get("profile_row", {})
    if not isinstance(row, dict):
        raise ValueError("T8-44 profile_row missing/malformed")
    raw = packet.get("raw_samples_us", {})
    if not isinstance(raw, dict):
        raise ValueError("T8-44 raw_samples_us missing/malformed")
    profile_snapshot = packet.get("hardware_profile_snapshot")
    if not isinstance(profile_snapshot, dict):
        raise ValueError("T8-44 hardware profile snapshot missing before capture binding")
    return {
        "source_head": str(packet.get("source_head", "")),
        "hardware_attestation": str(packet.get("hardware_attestation", "")),
        "hardware_profile_snapshot": profile_snapshot,
        "profiling_disposition": str(packet.get("profiling_disposition", "")),
        "hardware_id": str(row.get("hardware_id", "")),
        "build_id": str(row.get("build_id", "")),
        "dossier_id": str(row.get("dossier_id", "")),
        "profile_row": row,
        "raw_samples_us": raw,
        "acquisition_build_binding": packet.get("acquisition_build_binding", {}),
    }


def make_capture_binding(packet: dict) -> dict:
    payload = capture_payload(packet)
    return {
        "schema": CAPTURE_SCHEMA,
        "payload_sha256": canonical_sha256(payload),
        "source_head": payload["source_head"],
        "hardware_id": payload["hardware_id"],
        "hardware_attestation": payload["hardware_attestation"],
        "hardware_profile_sha256": str(payload["hardware_profile_snapshot"].get("profile_sha256", "")),
        "build_id": payload["build_id"],
        "dossier_id": payload["dossier_id"],
    }


def verify_capture_binding(packet: dict) -> dict:
    actual = packet.get("reference_capture_binding")
    if not isinstance(actual, dict):
        raise ValueError("T8-44 sealed packet missing reference capture identity/attestation binding")
    if actual.get("schema") != CAPTURE_SCHEMA:
        raise ValueError("T8-44 reference capture binding schema unsupported")
    expected = make_capture_binding(packet)
    if canonical_json(actual) != canonical_json(expected):
        raise ValueError("T8-44 reference capture identity/attestation/hardware-profile binding mismatch")
    return expected


def validate_packet_target(packet: dict) -> dict:
    row = packet.get("profile_row", {})
    if not isinstance(row, dict):
        raise ValueError("T8-44 profile_row missing/malformed")
    return profile_target.validate_reference_target(str(row.get("dossier_id", "")))


def seal(packet_path: Path) -> dict:
    packet_path = packet_path.resolve()
    root = packet_path.parent
    packet = load_packet(packet_path)
    if packet.get("evidence_appended") is not False:
        raise ValueError("T8-44 profile packet must remain non-evidence before sealing")
    target = validate_packet_target(packet)
    source_head = str(packet.get("source_head", ""))
    row = packet.get("profile_row", {})
    if not isinstance(row, dict):
        raise ValueError("T8-44 profile_row missing/malformed")
    build_id = str(row.get("build_id", ""))
    snapshot = verify_prepared(root, source_head=source_head, build_id=build_id)
    if "acquisition_build_binding" in packet and canonical_json(packet["acquisition_build_binding"]) != canonical_json(snapshot):
        raise ValueError("T8-44 profile packet contains conflicting packaged build binding")
    reference_required = str(packet.get("profiling_disposition", "")) == "reference_run"
    profile_snapshot = _hardware_snapshot(packet, reference_required=reference_required)
    packet["packet_version"] = 3
    packet["acquisition_build_binding"] = snapshot
    packet["acquisition_build_bytes_required"] = True
    packet["reference_target_contract"] = target
    packet["hardware_profile_snapshot"] = profile_snapshot
    packet.pop("hardware_profile", None)
    packet["reference_capture_binding"] = make_capture_binding(packet)
    packet_path.write_text(json.dumps(packet, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return snapshot


def verify_sealed(packet_path: Path, packet: dict | None = None) -> dict:
    packet_path = packet_path.resolve()
    root = packet_path.parent
    if packet is None:
        packet = load_packet(packet_path)
    if int(packet.get("packet_version", 0)) != 3:
        raise ValueError("T8-44 profile packet is NOT APPEND READY: acquisition packet_version 3 required")
    if packet.get("acquisition_build_bytes_required") is not True:
        raise ValueError("T8-44 profile packet is NOT APPEND READY: packaged build bytes not required")
    target = validate_packet_target(packet)
    row = packet.get("profile_row", {})
    if not isinstance(row, dict):
        raise ValueError("T8-44 profile_row missing/malformed")
    source_head = str(packet.get("source_head", ""))
    build_id = str(row.get("build_id", ""))
    verified = verify_prepared(root, source_head=source_head, build_id=build_id)
    if canonical_json(packet.get("acquisition_build_binding")) != canonical_json(verified):
        raise ValueError("T8-44 sealed packet packaged build binding mismatch")
    reference_required = str(packet.get("profiling_disposition", "")) == "reference_run"
    _hardware_snapshot(packet, reference_required=reference_required)
    verify_capture_binding(packet)
    if canonical_json(packet.get("reference_target_contract")) != canonical_json(target):
        raise ValueError("T8-44 sealed packet representative target contract mismatch")
    return verified


def main() -> None:
    parser = argparse.ArgumentParser(description="Freeze production package bytes before T8-44 reference acquisition and seal the resulting profile packet to that exact package, structured hardware profile, representative late-game Stability target, and hardware-attested capture payload.")
    sub = parser.add_subparsers(dest="command", required=True)
    prep = sub.add_parser("prepare")
    prep.add_argument("--root", type=Path, required=True)
    prep.add_argument("--source-head", required=True)
    prep.add_argument("--build-id", required=True)
    prep.add_argument("--artifact", type=Path, required=True)
    prep.add_argument("--record", type=Path, required=True)
    seal_parser = sub.add_parser("seal")
    seal_parser.add_argument("--packet", type=Path, required=True)
    verify = sub.add_parser("verify")
    verify.add_argument("--packet", type=Path, required=True)
    args = parser.parse_args()
    if args.command == "prepare":
        snapshot = prepare(args.root, source_head=args.source_head, build_id=args.build_id, artifact=args.artifact, record=args.record)
        status = "PREPARED"
    elif args.command == "seal":
        snapshot = seal(args.packet)
        status = "SEALED"
    else:
        snapshot = verify_sealed(args.packet)
        status = "VERIFIED"
    print(json.dumps({"status": status, "binding_id": snapshot["binding_id"], "artifact_sha256": snapshot["artifact_sha256"], "artifact_bytes": snapshot["artifact_bytes"], "reference_capture_binding_verified": status in {"SEALED", "VERIFIED"}, "reference_hardware_profile_verified": status in {"SEALED", "VERIFIED"}, "reference_target_contract_verified": status in {"SEALED", "VERIFIED"}, "evidence_appended": False}, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
