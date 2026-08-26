#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path

import phase12g_acquisition_build_binding as acquisition_binding

BINDING_FILENAME = "acquisition-build-binding.json"


def canonical_json(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


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


def seal(packet_path: Path) -> dict:
    packet_path = packet_path.resolve()
    root = packet_path.parent
    packet = load_packet(packet_path)
    if packet.get("evidence_appended") is not False:
        raise ValueError("T8-44 profile packet must remain non-evidence before sealing")
    source_head = str(packet.get("source_head", ""))
    row = packet.get("profile_row", {})
    if not isinstance(row, dict):
        raise ValueError("T8-44 profile_row missing/malformed")
    build_id = str(row.get("build_id", ""))
    snapshot = verify_prepared(root, source_head=source_head, build_id=build_id)
    if "acquisition_build_binding" in packet and canonical_json(packet["acquisition_build_binding"]) != canonical_json(snapshot):
        raise ValueError("T8-44 profile packet contains conflicting packaged build binding")
    packet["packet_version"] = 2
    packet["acquisition_build_binding"] = snapshot
    packet["acquisition_build_bytes_required"] = True
    packet_path.write_text(json.dumps(packet, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return snapshot


def verify_sealed(packet_path: Path, packet: dict | None = None) -> dict:
    packet_path = packet_path.resolve()
    root = packet_path.parent
    if packet is None:
        packet = load_packet(packet_path)
    if int(packet.get("packet_version", 0)) != 2:
        raise ValueError("T8-44 profile packet is NOT APPEND READY: acquisition packet_version 2 required")
    if packet.get("acquisition_build_bytes_required") is not True:
        raise ValueError("T8-44 profile packet is NOT APPEND READY: packaged build bytes not required")
    row = packet.get("profile_row", {})
    if not isinstance(row, dict):
        raise ValueError("T8-44 profile_row missing/malformed")
    source_head = str(packet.get("source_head", ""))
    build_id = str(row.get("build_id", ""))
    verified = verify_prepared(root, source_head=source_head, build_id=build_id)
    if canonical_json(packet.get("acquisition_build_binding")) != canonical_json(verified):
        raise ValueError("T8-44 sealed packet packaged build binding mismatch")
    return verified


def main() -> None:
    parser = argparse.ArgumentParser(description="Freeze production package bytes before T8-44 reference acquisition and seal the resulting profile packet to that exact package.")
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
    print(json.dumps({"status": status, "binding_id": snapshot["binding_id"], "artifact_sha256": snapshot["artifact_sha256"], "artifact_bytes": snapshot["artifact_bytes"], "evidence_appended": False}, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
