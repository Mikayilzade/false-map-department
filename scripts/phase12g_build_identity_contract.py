#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT_DIR = Path(__file__).resolve().parent

import sys
sys.path.insert(0, str(SCRIPT_DIR))
import phase12g_build_identity as identity  # noqa: E402

SCHEMA = "fmd.phase12g.build-identity-manifest.v1"


def fail(message: str) -> None:
    raise SystemExit(f"PHASE12G BUILD IDENTITY FAIL: {message}")


def checkout_head() -> str:
    completed = subprocess.run(
        ["git", "rev-parse", "--verify", "HEAD"],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )
    if completed.returncode != 0:
        fail("unable to resolve repository checkout HEAD")
    try:
        return identity.normalize_source_head(completed.stdout.strip())
    except ValueError as exc:
        fail(str(exc))


def canonical_hash(payload: dict) -> str:
    import hashlib
    encoded = json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def load_json(path: Path) -> dict:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        fail(f"{path}: expected JSON object")
    return value


def create_manifest(source_head: str, demo_build_id: str, production_build_id: str) -> dict:
    source_head = identity.normalize_source_head(source_head)
    actual = checkout_head()
    if actual != source_head:
        fail(f"source_head must equal checkout HEAD at identity generation: expected {actual}, got {source_head}")
    payload = {
        "schema": SCHEMA,
        "source_head": source_head,
        "demo": identity.identity_record(source_head, "demo", demo_build_id),
        "production": identity.identity_record(source_head, "production", production_build_id),
        "evidence_boundary": "This manifest binds external acquisition build labels to one exact repository source tree; it is acquisition metadata, not empirical evidence.",
    }
    payload["contract_hash"] = canonical_hash(payload)
    return payload


def verify_manifest(manifest: dict, *, require_checkout: bool = True) -> dict:
    if manifest.get("schema") != SCHEMA:
        fail("unsupported build identity manifest schema")
    source_head = identity.normalize_source_head(str(manifest.get("source_head", "")))
    if require_checkout and checkout_head() != source_head:
        fail(f"build identity source_head {source_head} does not match current checkout HEAD {checkout_head()}")
    for role in ("demo", "production"):
        record = manifest.get(role)
        if not isinstance(record, dict):
            fail(f"missing {role} build identity record")
        try:
            identity.validate_identity(
                record,
                source_head=source_head,
                role=role,
                build_id=record.get("build_id", ""),
            )
        except ValueError as exc:
            fail(str(exc))
    claimed = str(manifest.get("contract_hash", ""))
    unhashed = dict(manifest)
    unhashed.pop("contract_hash", None)
    actual_hash = canonical_hash(unhashed)
    if claimed != actual_hash:
        fail("build identity contract_hash mismatch")
    return manifest


def verify_pair(manifest: dict, *, source_head: object, build_id: object, role: str, label: str) -> None:
    source = identity.normalize_source_head(str(source_head))
    if source != manifest["source_head"]:
        fail(f"{label} source_head mismatch: identity={manifest['source_head']} artifact={source}")
    record = manifest[role]
    if str(build_id).strip() != record["build_id"]:
        fail(f"{label} build_id mismatch for {role}: identity={record['build_id']} artifact={build_id}")
    try:
        identity.validate_identity(record, source_head=source, role=role, build_id=build_id)
    except ValueError as exc:
        fail(f"{label}: {exc}")


def verify_human(manifest: dict, kit_dir: Path) -> dict:
    kit = load_json(kit_dir / "field-kit-manifest.json")
    verify_pair(manifest, source_head=kit.get("source_head"), build_id=kit.get("demo_build_id"), role="demo", label="human field kit demo")
    verify_pair(manifest, source_head=kit.get("source_head"), build_id=kit.get("production_build_id"), role="production", label="human field kit production")
    return {"kind": "human", "source_head": manifest["source_head"], "bindings_verified": 2}


def verify_e8(manifest: dict, packet_dir: Path) -> dict:
    asset = load_json(packet_dir / "asset-set.json")
    respondents = load_json(packet_dir / "respondents.json")
    verify_pair(manifest, source_head=asset.get("source_head"), build_id=asset.get("build_id"), role="production", label="E8 asset set")
    verify_pair(manifest, source_head=respondents.get("source_head"), build_id=respondents.get("build_id"), role="production", label="E8 respondent packet")
    return {"kind": "e8", "source_head": manifest["source_head"], "bindings_verified": 2}


def verify_t8(manifest: dict, packet_path: Path) -> dict:
    packet = load_json(packet_path)
    row = packet.get("profile_row", {})
    if not isinstance(row, dict):
        fail("T8-44 profile_row missing/malformed")
    verify_pair(manifest, source_head=packet.get("source_head"), build_id=row.get("build_id"), role="production", label="T8-44 profile packet")
    return {"kind": "t8-44", "source_head": manifest["source_head"], "bindings_verified": 1}


def main() -> None:
    parser = argparse.ArgumentParser(description="Create/verify one exact source↔build identity contract across Phase 12G external acquisition paths.")
    sub = parser.add_subparsers(dest="command", required=True)

    create = sub.add_parser("create")
    create.add_argument("--source-head", required=True)
    create.add_argument("--demo-build-id", required=True)
    create.add_argument("--production-build-id", required=True)
    create.add_argument("--output", type=Path, required=True)

    verify = sub.add_parser("verify")
    verify.add_argument("--identity", type=Path, required=True)
    verify.add_argument("--human-kit", type=Path)
    verify.add_argument("--e8-packet", type=Path)
    verify.add_argument("--t8-packet", type=Path)

    args = parser.parse_args()
    if args.command == "create":
        payload = create_manifest(args.source_head, args.demo_build_id, args.production_build_id)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        if args.output.exists():
            fail("refusing to overwrite existing build identity manifest")
        args.output.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        print(json.dumps({"status": "CREATED", "source_head": payload["source_head"], "contract_hash": payload["contract_hash"], "evidence_appended": False}, sort_keys=True))
        return

    manifest = verify_manifest(load_json(args.identity))
    selected = [args.human_kit is not None, args.e8_packet is not None, args.t8_packet is not None]
    if sum(selected) != 1:
        fail("verify requires exactly one of --human-kit, --e8-packet, --t8-packet")
    if args.human_kit is not None:
        result = verify_human(manifest, args.human_kit.resolve())
    elif args.e8_packet is not None:
        result = verify_e8(manifest, args.e8_packet.resolve())
    else:
        result = verify_t8(manifest, args.t8_packet.resolve())
    result.update({"status": "VERIFIED", "contract_hash": manifest["contract_hash"], "evidence_appended": False, "gate_disposition_inferred": False})
    print(json.dumps(result, sort_keys=True))


if __name__ == "__main__":
    main()
