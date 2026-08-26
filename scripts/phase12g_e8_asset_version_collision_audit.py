#!/usr/bin/env python3
from __future__ import annotations

import copy
import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT_DIR = ROOT / "scripts"
INTEGRITY = SCRIPT_DIR / "phase12g_e8_evidence_provenance_integrity.py"
INGEST = SCRIPT_DIR / "phase12g_marketing_expectation_ingest.py"
SOURCE_HEAD = "a" * 40
ROLES = (
    "store_key_art",
    "gameplay_map_world",
    "gameplay_consequence",
    "late_game_linked",
    "trailer",
)

sys.path.insert(0, str(SCRIPT_DIR))
import phase12g_e8_evidence_provenance_integrity as integrity  # noqa: E402


def packet(asset_set_digest: str = "1" * 64) -> dict:
    return {
        "schema": integrity.EXPECTED_SCHEMA,
        "asset_version": "COLLISION-AUDIT-V1",
        "build_id": "COLLISION-AUDIT-BUILD",
        "source_head": SOURCE_HEAD,
        "asset_set_sha256": asset_set_digest,
        "respondents_sha256": "2" * 64,
        "completed_rows_sha256": "3" * 64,
        "completion_receipt_sha256": "4" * 64,
        "frozen_assets_sha256_by_role": {role: "5" * 64 for role in ROLES},
        "frozen_assets_bytes_by_role": {role: 64 for role in ROLES},
    }


def row(respondent_id: str, provenance: dict) -> dict:
    return {
        "gate_id": "E8",
        "respondent_id": respondent_id,
        "asset_version": provenance["asset_version"],
        "expected_play_category": "synthetic audit only",
        "freeform_builder_expectation": False,
        "notes": "synthetic collision audit; never empirical evidence",
        "source_head": provenance["source_head"],
        "source_build_id": provenance["build_id"],
        "acquisition_channel": "e8_marketing_packet",
        "e8_packet_provenance": provenance,
    }


def write_rows(path: Path, values: list[dict]) -> None:
    path.write_text("".join(json.dumps(value, sort_keys=True) + "\n" for value in values), encoding="utf-8")


def expect_rejected(callable_obj, phrase: str) -> None:
    try:
        callable_obj()
    except SystemExit as exc:
        if phrase not in str(exc):
            raise SystemExit(f"unexpected rejection: {exc}") from exc
        return
    raise SystemExit("conflicting E8 asset_version identity was unexpectedly accepted")


def main() -> None:
    base_packet = packet()
    conflict_packet = copy.deepcopy(base_packet)
    conflict_packet["asset_set_sha256"] = "9" * 64
    conflict_packet["completion_receipt_sha256"] = "8" * 64

    with tempfile.TemporaryDirectory(prefix="fmd-e8-collision-audit-") as raw:
        temp = Path(raw)
        evidence = temp / "E8.jsonl"

        # Multiple respondent rows from one exact finalized packet are legitimate.
        write_rows(evidence, [row("R1", base_packet), row("R2", base_packet)])
        accepted = integrity.validate_packet_identity_compatibility(evidence, base_packet)
        if not accepted.get("existing_same_packet"):
            raise SystemExit("same finalized E8 packet was not recognized as compatible")
        live = subprocess.run(
            [sys.executable, str(INTEGRITY), "--evidence", str(evidence)],
            cwd=ROOT,
            text=True,
            capture_output=True,
        )
        if live.returncode != 0 or "unique_asset_versions=1" not in live.stdout:
            raise SystemExit(f"same-packet multi-respondent integrity failed: {live.stdout}\n{live.stderr}")

        # A later ingest that reuses the same asset_version for a different frozen
        # packet must fail before the generic collector can append anything.
        expect_rejected(
            lambda: integrity.validate_packet_identity_compatibility(evidence, conflict_packet),
            "asset_version collision",
        )

        # Live repository integrity must also detect a historical/manual conflict.
        conflicting_evidence = temp / "E8-conflicting.jsonl"
        write_rows(conflicting_evidence, [row("R1", base_packet), row("R3", conflict_packet)])
        rejected = subprocess.run(
            [sys.executable, str(INTEGRITY), "--evidence", str(conflicting_evidence)],
            cwd=ROOT,
            text=True,
            capture_output=True,
        )
        if rejected.returncode == 0 or "asset_version collision" not in (rejected.stdout + rejected.stderr):
            raise SystemExit("live E8 provenance integrity did not reject conflicting packet identity reuse")

    ingest_text = INGEST.read_text(encoding="utf-8")
    guard_marker = "validate_packet_identity_compatibility(target_evidence, packet_provenance)"
    stage_marker = 'staged = root / ".repository-ingest-E8.jsonl"'
    if guard_marker not in ingest_text:
        raise SystemExit("E8 ingest does not call the repository asset-version identity collision guard")
    if ingest_text.index(guard_marker) > ingest_text.index(stage_marker):
        raise SystemExit("E8 asset-version collision guard must run before collector staging")

    print(
        "Phase 12G E8 asset-version collision audit: PASS — one asset_version is bound to one exact finalized packet; "
        "multiple respondents from that packet remain valid and conflicting later packet reuse is rejected before append"
    )


if __name__ == "__main__":
    main()
