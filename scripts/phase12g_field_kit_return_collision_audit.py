#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT_DIR = ROOT / "scripts"
sys.path.insert(0, str(SCRIPT_DIR))
import phase12g_field_kit_ingest as ingest  # noqa: E402


def fail(message: str) -> None:
    raise SystemExit(f"PHASE12G FIELD KIT RETURN COLLISION AUDIT FAIL: {message}")


def write_rows(path: Path, rows: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(json.dumps(row, sort_keys=True) + "\n" for row in rows), encoding="utf-8")


def row(*, namespace: str, receipt: str, contract: str, build_id: str, outcome: bool) -> dict:
    return {
        "schema_version": 1,
        "gate_id": "E1",
        "tester_id": "NAIVE-T0001",
        "naive": True,
        "session_id": namespace.split(":", 1)[1],
        "understood_within_seconds": 42.0,
        "success": outcome,
        "evidence_provenance_version": 1,
        "source_head": "a" * 40,
        "source_build_id": build_id,
        "acquisition_channel": ingest.FIELD_KIT_CHANNEL,
        "field_kit_return_namespace": namespace,
        "field_kit_packet_kind": "first_session",
        "field_kit_contract_hash": contract,
        "field_kit_finalization_receipt_sha256": receipt,
    }


def expect_collision(evidence_root: Path, proposed: list[dict]) -> None:
    try:
        ingest.ensure_return_identity_compatible(evidence_root, proposed)
    except SystemExit as exc:
        if "return namespace collision with existing evidence" not in str(exc):
            fail(f"conflicting finalized return rejected for the wrong reason: {exc}")
    else:
        fail("distinct finalized return reused an existing namespace without collision rejection")


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="fmd-phase12g-return-collision-") as temp:
        evidence_root = Path(temp) / "evidence"
        namespace = "first_session:FIRST-S0001"
        original = row(
            namespace=namespace,
            receipt="1" * 64,
            contract="2" * 64,
            build_id="return-collision-demo-a",
            outcome=True,
        )
        write_rows(evidence_root / "E1.jsonl", [original])
        before = (evidence_root / "E1.jsonl").read_bytes()

        exact_retry = dict(original)
        ingest.ensure_return_identity_compatible(evidence_root, [exact_retry])
        if (evidence_root / "E1.jsonl").read_bytes() != before:
            fail("identity compatibility check must never mutate evidence bytes")

        conflicting_receipt = row(
            namespace=namespace,
            receipt="3" * 64,
            contract="2" * 64,
            build_id="return-collision-demo-a",
            outcome=False,
        )
        expect_collision(evidence_root, [conflicting_receipt])
        if (evidence_root / "E1.jsonl").read_bytes() != before:
            fail("receipt collision rejection must preserve existing evidence bytes")

        conflicting_build = row(
            namespace=namespace,
            receipt="1" * 64,
            contract="2" * 64,
            build_id="return-collision-demo-b",
            outcome=False,
        )
        expect_collision(evidence_root, [conflicting_build])
        if (evidence_root / "E1.jsonl").read_bytes() != before:
            fail("build collision rejection must preserve existing evidence bytes")

        proposed_internal_conflict = [
            row(namespace="first_session:FIRST-S0002", receipt="4" * 64, contract="5" * 64, build_id="build-a", outcome=True),
            row(namespace="first_session:FIRST-S0002", receipt="6" * 64, contract="5" * 64, build_id="build-a", outcome=False),
        ]
        try:
            ingest.ensure_return_identity_compatible(evidence_root, proposed_internal_conflict)
        except SystemExit as exc:
            if "proposed field-kit rows conflict under return namespace" not in str(exc):
                fail(f"intra-return namespace collision rejected for the wrong reason: {exc}")
        else:
            fail("conflicting proposed rows under one return namespace were accepted")

    print(
        "Phase 12G field-kit return collision audit: PASS — isolated durable-identity fixtures prove exact retry compatibility, "
        "existing/proposed namespace collision rejection and zero evidence mutation without bypassing production append destination rules"
    )


if __name__ == "__main__":
    main()
