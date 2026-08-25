#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any

REQUIRED_ASSET_ROLES = (
    "store_key_art",
    "gameplay_map_world",
    "gameplay_consequence",
    "late_game_linked",
    "trailer",
)
ALLOWED_EXTENSIONS = {
    "store_key_art": {".png", ".jpg", ".jpeg", ".webp"},
    "gameplay_map_world": {".png", ".jpg", ".jpeg", ".webp"},
    "gameplay_consequence": {".png", ".jpg", ".jpeg", ".webp"},
    "late_game_linked": {".png", ".jpg", ".jpeg", ".webp"},
    "trailer": {".mp4", ".webm", ".mov"},
}
CANONICAL_CLAIMS = [
    "Premium single-player systemic puzzle game.",
    "Redraw the official map and the tiny world must obey.",
    "Authoritative edits use snapped authored roads, bridges, borders, waterways, landmark labels and restricted zones; this is not a freeform map builder.",
    "The 1.0 content target is 40 authored campaign dossiers plus 12 bounded remix cases.",
    "Required play paths include mouse+keyboard, keyboard-only and controller-only, with a 1280x800 Steam Deck target layout.",
]


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def parse_asset(value: str) -> tuple[str, Path]:
    if "=" not in value:
        raise SystemExit(f"asset must be ROLE=PATH, got {value!r}")
    role, raw_path = value.split("=", 1)
    role = role.strip()
    path = Path(raw_path).expanduser().resolve()
    if role not in REQUIRED_ASSET_ROLES:
        raise SystemExit(f"unknown asset role {role!r}; required roles: {', '.join(REQUIRED_ASSET_ROLES)}")
    return role, path


def load_claims(path: Path | None) -> list[str]:
    if path is None:
        return CANONICAL_CLAIMS.copy()
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, list) or not data or not all(isinstance(item, str) and item.strip() for item in data):
        raise SystemExit("claims JSON must be a non-empty string array")
    claims = [item.strip() for item in data]
    unknown = [claim for claim in claims if claim not in CANONICAL_CLAIMS]
    if unknown:
        raise SystemExit(f"custom E8 claims must be selected verbatim from the canonical capability-safe claim set; unknown: {unknown}")
    if CANONICAL_CLAIMS[2] not in claims:
        raise SystemExit("claims must explicitly include the snapped-authored / not-freeform-builder statement")
    return claims


def validate_assets(raw_assets: list[str]) -> list[dict[str, Any]]:
    by_role: dict[str, Path] = {}
    for raw in raw_assets:
        role, path = parse_asset(raw)
        if role in by_role:
            raise SystemExit(f"duplicate asset role: {role}")
        if not path.is_file():
            raise SystemExit(f"asset does not exist: {path}")
        if path.suffix.lower() not in ALLOWED_EXTENSIONS[role]:
            raise SystemExit(f"unsupported extension for {role}: {path.suffix}")
        if path.stat().st_size <= 0:
            raise SystemExit(f"asset is empty: {path}")
        by_role[role] = path
    missing = [role for role in REQUIRED_ASSET_ROLES if role not in by_role]
    if missing:
        raise SystemExit(f"representative E8 asset set incomplete; missing roles: {', '.join(missing)}")
    return [
        {
            "role": role,
            "filename": by_role[role].name,
            "sha256": sha256(by_role[role]),
            "bytes": by_role[role].stat().st_size,
        }
        for role in REQUIRED_ASSET_ROLES
    ]


def prepare(args: argparse.Namespace) -> None:
    if not args.asset_version.strip():
        raise SystemExit("asset_version is required")
    if not args.build_id.strip():
        raise SystemExit("build_id is required")
    if not args.representative_attestation:
        raise SystemExit("refusing E8 packet: representative asset attestation is required")
    assets = validate_assets(args.asset)
    claims = load_claims(Path(args.claims).resolve() if args.claims else None)
    out_dir = Path(args.output).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    manifest = {
        "schema": "fmd.phase12g.e8.asset-set.v1",
        "gate_id": "E8",
        "asset_version": args.asset_version,
        "build_id": args.build_id,
        "representative_asset_attestation": True,
        "claims": claims,
        "assets": assets,
        "evidence_boundary": "This asset manifest is acquisition material, not market evidence and not an E8 disposition.",
    }
    (out_dir / "asset-set.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    rows = []
    for index in range(args.respondents):
        rows.append({
            "respondent_id": f"{args.respondent_prefix}{index + 1:03d}",
            "asset_version": args.asset_version,
            "expected_play_category": None,
            "freeform_builder_expectation": None,
            "notes": None,
        })
    packet = {
        "schema": "fmd.phase12g.e8.respondent-packet.v1",
        "gate_id": "E8",
        "asset_version": args.asset_version,
        "build_id": args.build_id,
        "asset_set_sha256": sha256(out_dir / "asset-set.json"),
        "rows": rows,
        "status": "PREPARED",
        "evidence_appended": False,
        "interpretation": None,
        "evidence_boundary": "Prepared respondent rows are not observations. Human fields must remain null until a real respondent sees this exact asset version.",
    }
    (out_dir / "respondents.json").write_text(json.dumps(packet, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"Prepared E8 asset set {args.asset_version} with {len(assets)} representative roles and {len(rows)} blank respondent rows")


def status(args: argparse.Namespace) -> None:
    root = Path(args.packet).resolve()
    asset_path = root / "asset-set.json"
    respondent_path = root / "respondents.json"
    if not asset_path.is_file() or not respondent_path.is_file():
        print("MISSING_PACKET")
        return
    packet = json.loads(respondent_path.read_text(encoding="utf-8"))
    rows = packet.get("rows", [])
    completed = sum(
        1
        for row in rows
        if all(row.get(key) is not None for key in ("expected_play_category", "freeform_builder_expectation", "notes"))
    )
    if completed == 0:
        state = "PREPARED"
    elif completed < len(rows):
        state = "PARTIALLY_OBSERVED"
    else:
        state = "READY_TO_FINALIZE"
    print(json.dumps({"status": state, "completed_rows": completed, "total_rows": len(rows), "evidence_appended": False}, sort_keys=True))


def finalize(args: argparse.Namespace) -> None:
    root = Path(args.packet).resolve()
    asset_path = root / "asset-set.json"
    respondent_path = root / "respondents.json"
    if not asset_path.is_file() or not respondent_path.is_file():
        raise SystemExit("E8 packet missing asset-set.json/respondents.json")
    asset_set = json.loads(asset_path.read_text(encoding="utf-8"))
    packet = json.loads(respondent_path.read_text(encoding="utf-8"))
    if not asset_set.get("representative_asset_attestation", False):
        raise SystemExit("representative asset attestation missing")
    if sha256(asset_path) != packet.get("asset_set_sha256"):
        raise SystemExit("asset-set changed after respondent packet preparation")
    rows = packet.get("rows", [])
    if not rows:
        raise SystemExit("no respondents prepared")
    respondent_ids: set[str] = set()
    for index, row in enumerate(rows):
        for field in ("respondent_id", "asset_version", "expected_play_category", "freeform_builder_expectation", "notes"):
            if row.get(field) is None or (isinstance(row.get(field), str) and not row[field].strip()):
                raise SystemExit(f"respondent row {index} missing observed field {field}")
        respondent_id = str(row.get("respondent_id"))
        if respondent_id in respondent_ids:
            raise SystemExit(f"duplicate respondent_id: {respondent_id}")
        respondent_ids.add(respondent_id)
        if row.get("asset_version") != asset_set.get("asset_version"):
            raise SystemExit(f"respondent row {index} asset_version mismatch")
        if not isinstance(row.get("freeform_builder_expectation"), bool):
            raise SystemExit(f"respondent row {index} freeform_builder_expectation must be boolean")
    out = root / "completed-E8.jsonl"
    with out.open("w", encoding="utf-8") as handle:
        for row in rows:
            handle.write(json.dumps(row, sort_keys=True) + "\n")
    print(f"Finalized {len(rows)} local E8 observation rows; repository evidence was not appended")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Prepare/finalize Phase 12G E8 marketing-expectation acquisition packets without fabricating market outcomes")
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("prepare")
    p.add_argument("--asset-version", required=True)
    p.add_argument("--build-id", required=True)
    p.add_argument("--asset", action="append", default=[], help="ROLE=PATH; all five representative roles are required")
    p.add_argument("--claims")
    p.add_argument("--representative-attestation", action="store_true")
    p.add_argument("--respondents", type=int, default=5)
    p.add_argument("--respondent-prefix", default="E8R-")
    p.add_argument("--output", required=True)
    p.set_defaults(func=prepare)
    s = sub.add_parser("status")
    s.add_argument("--packet", required=True)
    s.set_defaults(func=status)
    f = sub.add_parser("finalize")
    f.add_argument("--packet", required=True)
    f.set_defaults(func=finalize)
    return parser


def main() -> None:
    args = build_parser().parse_args()
    if getattr(args, "respondents", 1) < 1:
        raise SystemExit("respondents must be >= 1")
    args.func(args)


if __name__ == "__main__":
    main()
