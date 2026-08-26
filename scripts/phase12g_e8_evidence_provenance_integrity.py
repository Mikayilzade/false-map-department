#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_EVIDENCE = ROOT / "empirical/evidence/E8.jsonl"
EXPECTED_SCHEMA = "fmd.phase12g.e8.evidence-packet-provenance.v1"
REQUIRED_ROLES = (
    "store_key_art",
    "gameplay_map_world",
    "gameplay_consequence",
    "late_game_linked",
    "trailer",
)
SHA40 = re.compile(r"^[0-9a-f]{40}$")
SHA64 = re.compile(r"^[0-9a-f]{64}$")


def fail(message: str) -> None:
    raise SystemExit(f"PHASE12G E8 PROVENANCE INTEGRITY FAIL: {message}")


def rows(path: Path) -> list[dict]:
    if not path.exists():
        return []
    result: list[dict] = []
    for line_no, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if not raw.strip():
            continue
        try:
            value = json.loads(raw)
        except json.JSONDecodeError as exc:
            fail(f"{path}:{line_no}: invalid JSON: {exc}")
        if not isinstance(value, dict):
            fail(f"{path}:{line_no}: row must be an object")
        result.append(value)
    return result


def validate_row(row: dict, index: int) -> None:
    if row.get("gate_id") != "E8":
        fail(f"row {index}: gate_id must be E8")
    if row.get("acquisition_channel") != "e8_marketing_packet":
        fail(f"row {index}: acquisition_channel must be e8_marketing_packet")
    source_head = str(row.get("source_head", ""))
    build_id = str(row.get("source_build_id", ""))
    asset_version = str(row.get("asset_version", ""))
    if not SHA40.fullmatch(source_head):
        fail(f"row {index}: invalid source_head")
    if not build_id or not asset_version:
        fail(f"row {index}: source_build_id and asset_version must be non-empty")

    packet = row.get("e8_packet_provenance")
    if not isinstance(packet, dict):
        fail(f"row {index}: e8_packet_provenance missing/malformed")
    if packet.get("schema") != EXPECTED_SCHEMA:
        fail(f"row {index}: unsupported e8 packet provenance schema")
    if packet.get("source_head") != source_head:
        fail(f"row {index}: packet source_head does not match row provenance")
    if str(packet.get("build_id", "")) != build_id:
        fail(f"row {index}: packet build_id does not match row provenance")
    if str(packet.get("asset_version", "")) != asset_version:
        fail(f"row {index}: packet asset_version does not match respondent observation")

    for field in (
        "asset_set_sha256",
        "respondents_sha256",
        "completed_rows_sha256",
        "completion_receipt_sha256",
    ):
        if not SHA64.fullmatch(str(packet.get(field, ""))):
            fail(f"row {index}: invalid/missing {field}")

    hashes = packet.get("frozen_assets_sha256_by_role")
    sizes = packet.get("frozen_assets_bytes_by_role")
    if not isinstance(hashes, dict) or tuple(hashes.keys()) != REQUIRED_ROLES:
        fail(f"row {index}: frozen asset hash roles must exactly match required E8 roles/order")
    if not isinstance(sizes, dict) or tuple(sizes.keys()) != REQUIRED_ROLES:
        fail(f"row {index}: frozen asset byte roles must exactly match required E8 roles/order")
    for role in REQUIRED_ROLES:
        if not SHA64.fullmatch(str(hashes.get(role, ""))):
            fail(f"row {index}: invalid asset digest for {role}")
        size = sizes.get(role)
        if not isinstance(size, int) or isinstance(size, bool) or size <= 0:
            fail(f"row {index}: invalid asset byte size for {role}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Validate durable self-contained provenance on repository E8 evidence rows.")
    parser.add_argument("--evidence", type=Path, default=DEFAULT_EVIDENCE)
    args = parser.parse_args()

    observed = rows(args.evidence)
    for index, row in enumerate(observed, start=1):
        validate_row(row, index)

    print(
        "Phase 12G E8 evidence provenance integrity: PASS "
        f"(validated_rows={len(observed)}, durable_packet_identity={'present' if observed else 'not-yet-observed'})"
    )


if __name__ == "__main__":
    main()
