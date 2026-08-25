#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
ROOT = SCRIPT_DIR.parent
COLLECTOR = SCRIPT_DIR / "phase12g_collect_completed_rows.py"
SHA40 = re.compile(r"^[0-9a-f]{40}$")

sys.path.insert(0, str(SCRIPT_DIR))
import phase12g_marketing_expectation_packet as packet_tools  # noqa: E402
import phase12g_provenance as provenance  # noqa: E402


def canonical(row: dict) -> str:
    return json.dumps(row, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def load_jsonl(path: Path) -> list[dict]:
    rows: list[dict] = []
    for line_no, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if not raw.strip():
            continue
        value = json.loads(raw)
        if not isinstance(value, dict):
            raise SystemExit(f"{path}:{line_no}: completed E8 row must be an object")
        rows.append(value)
    return rows


def validate_packet(root: Path, expected_source_head: str) -> tuple[dict, dict, Path, list[dict]]:
    expected = expected_source_head.strip().lower()
    if not SHA40.fullmatch(expected):
        raise SystemExit("expected-source-head must be an exact 40-character lowercase Git commit SHA")

    asset_set, respondents = packet_tools.load_and_verify_packet(root)
    actual = str(asset_set.get("source_head", "")).lower()
    if actual != expected:
        raise SystemExit(f"E8 packet source_head mismatch: expected {expected}, got {actual}")
    if respondents.get("source_head") != expected:
        raise SystemExit("E8 respondent packet source_head does not match expected source commit")
    if not asset_set.get("representative_asset_attestation", False):
        raise SystemExit("E8 packet lacks representative asset attestation")

    completed_path = root / "completed-E8.jsonl"
    if not completed_path.is_file():
        raise SystemExit("E8 packet has not been finalized: completed-E8.jsonl is missing")
    completed = load_jsonl(completed_path)
    prepared = respondents.get("rows", [])
    if not isinstance(prepared, list) or not prepared:
        raise SystemExit("E8 respondent rows missing or malformed")
    if len(completed) != len(prepared):
        raise SystemExit("completed-E8 row count does not match the source-pinned respondent packet")

    expected_rows: list[str] = []
    respondent_ids: set[str] = set()
    for index, raw in enumerate(prepared):
        if not isinstance(raw, dict):
            raise SystemExit(f"respondent row {index} is malformed")
        row = raw
        for field in ("respondent_id", "asset_version", "expected_play_category", "freeform_builder_expectation", "notes"):
            value = row.get(field)
            if value is None or (isinstance(value, str) and not value.strip()):
                raise SystemExit(f"respondent row {index} is not fully observed: {field}")
        if not isinstance(row.get("freeform_builder_expectation"), bool):
            raise SystemExit(f"respondent row {index} freeform_builder_expectation must be boolean")
        respondent_id = str(row.get("respondent_id", ""))
        if respondent_id in respondent_ids:
            raise SystemExit(f"duplicate respondent_id in respondent packet: {respondent_id}")
        respondent_ids.add(respondent_id)
        if row.get("asset_version") != asset_set.get("asset_version"):
            raise SystemExit(f"respondent row {index} asset_version mismatch")
        expected_rows.append(canonical(row))

    actual_rows = [canonical(row) for row in completed]
    if actual_rows != expected_rows:
        raise SystemExit("completed-E8.jsonl does not exactly match the finalized source-pinned respondent rows")

    collector_rows: list[dict] = []
    for row in completed:
        out = dict(row)
        out["gate_id"] = "E8"
        collector_rows.append(out)
    try:
        collector_rows = provenance.enrich_rows(
            collector_rows,
            source_head=actual,
            build_id=asset_set.get("build_id", ""),
            channel="e8_marketing_packet",
        )
    except ValueError as exc:
        raise SystemExit(f"E8 evidence provenance invalid: {exc}") from exc
    return asset_set, respondents, completed_path, collector_rows


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Verify and ingest a finalized immutable E8 marketing-expectation packet without inferring respondent outcomes."
    )
    parser.add_argument("--packet", type=Path, required=True)
    parser.add_argument("--expected-source-head", required=True)
    parser.add_argument("--evidence-root", type=Path, default=ROOT / "empirical/evidence")
    parser.add_argument("--append", action="store_true", help="Append validated novel E8 rows. Default is dry-run only.")
    args = parser.parse_args()

    root = args.packet.resolve()
    asset_set, respondents, _, rows = validate_packet(root, args.expected_source_head)

    staged = root / ".repository-ingest-E8.jsonl"
    staged.write_text("".join(json.dumps(row, sort_keys=True, ensure_ascii=False) + "\n" for row in rows), encoding="utf-8")
    try:
        command = [
            sys.executable,
            str(COLLECTOR),
            "--input",
            str(staged),
            "--evidence-root",
            str(args.evidence_root.resolve()),
        ]
        if args.append:
            command.append("--append")
        completed = subprocess.run(command, cwd=ROOT, text=True, capture_output=True)
        if completed.returncode != 0:
            detail = completed.stderr.strip() or completed.stdout.strip()
            raise SystemExit(f"E8 collector rejected finalized packet: {detail}")
        result = json.loads(completed.stdout)
    finally:
        staged.unlink(missing_ok=True)

    result.update({
        "asset_version": asset_set.get("asset_version"),
        "build_id": asset_set.get("build_id"),
        "source_head": asset_set.get("source_head"),
        "respondent_count": len(respondents.get("rows", [])),
        "frozen_assets_verified": True,
        "respondent_packet_match_verified": True,
        "provenance_persisted_in_rows": True,
        "evidence_boundary": "Validated respondent observations only; no market outcome or E8 disposition was inferred.",
    })
    print(json.dumps(result, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
