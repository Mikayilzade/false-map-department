#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import phase12g_acquisition_build_binding as acquisition_binding

BINDING_FILENAME = "acquisition-build-binding.json"
RESPONDENT_IDENTITY_SCHEMA = "fmd.phase12g.e8.respondent-identity-binding.v1"


def canonical_json(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _load_packet(root: Path) -> tuple[dict, dict]:
    # Delayed import avoids packet -> receipt -> binding -> packet circular import.
    import phase12g_marketing_expectation_packet as packet_tools
    return packet_tools.load_and_verify_packet(root)


def _respondent_ids(respondents: dict) -> list[str]:
    rows = respondents.get("rows", [])
    if not isinstance(rows, list) or not rows:
        raise ValueError("E8 respondent rows missing or malformed")
    ids: list[str] = []
    seen: set[str] = set()
    for index, row in enumerate(rows):
        if not isinstance(row, dict):
            raise ValueError(f"E8 respondent row {index} malformed")
        respondent_id = str(row.get("respondent_id", "")).strip()
        if not respondent_id:
            raise ValueError(f"E8 respondent row {index} missing respondent_id")
        if respondent_id in seen:
            raise ValueError(f"E8 respondent identity duplicate before acquisition: {respondent_id}")
        seen.add(respondent_id)
        ids.append(respondent_id)
    return ids


def make_respondent_identity_binding(respondents: dict) -> dict:
    ids = _respondent_ids(respondents)
    payload = {
        "schema": RESPONDENT_IDENTITY_SCHEMA,
        "respondent_ids": ids,
        "respondent_count": len(ids),
    }
    return {
        "schema": RESPONDENT_IDENTITY_SCHEMA,
        "respondent_count": len(ids),
        "respondent_ids_sha256": hashlib.sha256(canonical_json(payload).encode("utf-8")).hexdigest(),
    }


def verify_respondent_identity_binding(asset_set: dict, respondents: dict) -> dict:
    asset_binding = asset_set.get("respondent_identity_binding")
    respondent_binding = respondents.get("respondent_identity_binding")
    if not isinstance(asset_binding, dict) or not isinstance(respondent_binding, dict):
        raise ValueError("E8 packet is NOT APPEND READY: acquisition-time respondent identity binding missing")
    if canonical_json(asset_binding) != canonical_json(respondent_binding):
        raise ValueError("E8 respondent identity binding differs between immutable packet manifests")
    if asset_binding.get("schema") != RESPONDENT_IDENTITY_SCHEMA:
        raise ValueError("E8 respondent identity binding schema invalid")
    expected = make_respondent_identity_binding(respondents)
    if canonical_json(asset_binding) != canonical_json(expected):
        raise ValueError("E8 respondent identity changed after acquisition preparation")
    return expected


def bind_packet(root: Path, artifact: Path, record: Path) -> dict:
    root = root.resolve()
    asset_set, respondents = _load_packet(root)
    if (root / "completed-E8.jsonl").exists() or (root / "completion-receipt.json").exists():
        raise SystemExit("refusing to bind E8 packaged build after packet finalization")
    rows = respondents.get("rows", [])
    if not isinstance(rows, list):
        raise SystemExit("E8 respondent rows malformed")
    for row in rows:
        if not isinstance(row, dict):
            raise SystemExit("E8 respondent row malformed")
        if any(row.get(key) is not None for key in ("expected_play_category", "freeform_builder_expectation", "notes")):
            raise SystemExit("refusing to bind E8 packaged build after respondent observation started")

    try:
        respondent_identity = make_respondent_identity_binding(respondents)
    except ValueError as exc:
        raise SystemExit(str(exc)) from exc

    source_head = str(asset_set.get("source_head", ""))
    build_id = str(asset_set.get("build_id", ""))
    snapshot = acquisition_binding.freeze_into_root(
        root=root,
        source_head=source_head,
        role="production",
        build_id=build_id,
        artifact_path=artifact,
        record_path=record,
    )
    binding_path = root / BINDING_FILENAME
    binding_path.write_text(json.dumps(snapshot, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    asset_path = root / "asset-set.json"
    respondent_path = root / "respondents.json"
    asset_set = dict(asset_set)
    asset_set["acquisition_build_binding"] = snapshot
    asset_set["acquisition_build_bytes_required"] = True
    asset_set["respondent_identity_binding"] = respondent_identity
    asset_set["schema"] = "fmd.phase12g.e8.asset-set.v3"
    asset_path.write_text(json.dumps(asset_set, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    respondents = dict(respondents)
    respondents["acquisition_build_binding"] = snapshot
    respondents["acquisition_build_bytes_required"] = True
    respondents["respondent_identity_binding"] = respondent_identity
    respondents["schema"] = "fmd.phase12g.e8.respondent-packet.v3"
    respondents["asset_set_sha256"] = sha256(asset_path)
    respondent_path.write_text(json.dumps(respondents, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    verify_packet_binding(root, asset_set, respondents)
    return snapshot


def verify_packet_binding(root: Path, asset_set: dict | None = None, respondents: dict | None = None) -> dict:
    root = root.resolve()
    if asset_set is None or respondents is None:
        asset_set, respondents = _load_packet(root)
    if asset_set.get("acquisition_build_bytes_required") is not True or respondents.get("acquisition_build_bytes_required") is not True:
        raise ValueError("E8 packet is NOT APPEND READY: acquisition packaged build bytes are not required")
    verify_respondent_identity_binding(asset_set, respondents)
    asset_snapshot = asset_set.get("acquisition_build_binding")
    respondent_snapshot = respondents.get("acquisition_build_binding")
    if canonical_json(asset_snapshot) != canonical_json(respondent_snapshot):
        raise ValueError("E8 acquisition build binding differs between immutable packet manifests")
    binding_path = root / BINDING_FILENAME
    if not binding_path.is_file():
        raise ValueError("E8 acquisition build binding sidecar missing")
    sidecar = json.loads(binding_path.read_text(encoding="utf-8"))
    if canonical_json(sidecar) != canonical_json(asset_snapshot):
        raise ValueError("E8 acquisition build binding sidecar/manifest mismatch")
    return acquisition_binding.verify_frozen(
        root,
        sidecar,
        source_head=str(asset_set.get("source_head", "")),
        role="production",
        build_id=str(asset_set.get("build_id", "")),
    )


def main() -> None:
    parser = argparse.ArgumentParser(description="Freeze the exact production package and respondent identities into a prepared E8 acquisition packet before any respondent observation.")
    sub = parser.add_subparsers(dest="command", required=True)
    bind = sub.add_parser("bind")
    bind.add_argument("--packet", type=Path, required=True)
    bind.add_argument("--artifact", type=Path, required=True)
    bind.add_argument("--record", type=Path, required=True)
    verify = sub.add_parser("verify")
    verify.add_argument("--packet", type=Path, required=True)
    args = parser.parse_args()
    if args.command == "bind":
        snapshot = bind_packet(args.packet, args.artifact, args.record)
        print(json.dumps({"status": "BOUND", "binding_id": snapshot["binding_id"], "artifact_sha256": snapshot["artifact_sha256"], "artifact_bytes": snapshot["artifact_bytes"], "respondent_identity_bound": True, "evidence_appended": False}, indent=2, sort_keys=True))
    else:
        snapshot = verify_packet_binding(args.packet)
        print(json.dumps({"status": "VERIFIED", "binding_id": snapshot["binding_id"], "artifact_sha256": snapshot["artifact_sha256"], "artifact_bytes": snapshot["artifact_bytes"], "respondent_identity_bound": True, "evidence_appended": False}, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
