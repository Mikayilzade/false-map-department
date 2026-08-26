#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
INGEST = ROOT / "scripts/phase12g_field_kit_ingest.py"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"PHASE12G PACKET IDENTITY BINDING AUDIT FAIL: {message}")


def load_ingest():
    spec = importlib.util.spec_from_file_location("phase12g_field_kit_ingest_identity_audit", INGEST)
    require(spec is not None and spec.loader is not None, "unable to load field-kit ingest")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def write_json(path: Path, value: dict) -> None:
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def expect_rejection(callable_, marker: str) -> None:
    try:
        callable_()
    except SystemExit as exc:
        require(marker in str(exc), f"rejection did not identify {marker!r}: {exc}")
        return
    require(False, f"tampered identity unexpectedly accepted; expected {marker!r}")


def main() -> None:
    module = load_ingest()
    source_text = INGEST.read_text(encoding="utf-8")
    for marker in (
        "verify_receipt_packet_identity",
        "verify_completed_row_identity",
        "receipt may bind completed files only inside its own immutable packet directory",
        "completed-row tester_id does not match immutable packet identity",
        "completed-row session_id does not match immutable first-session packet identity",
    ):
        require(marker in source_text, f"field-kit ingest missing fail-closed identity marker: {marker}")

    with tempfile.TemporaryDirectory(prefix="fmd-human-packet-identity-") as raw:
        root = Path(raw)
        first = root / "first"
        first.mkdir()
        write_json(first / "session-manifest.json", {
            "tester_id": "T-FIRST-01",
            "session_id": "S-FIRST-01",
            "demo_build_id": "DEMO-BUILD",
        })
        first_receipt = {
            "packet_kind": "first_session",
            "tester_id": "T-FIRST-01",
            "session_id": "S-FIRST-01",
        }
        identity = module.verify_receipt_packet_identity(first / "finalization-receipt.json", first_receipt)
        require(identity == {"tester_id": "T-FIRST-01", "session_id": "S-FIRST-01"}, "first-session receipt must resolve immutable packet identity")
        binding = {
            "packet_kind": "first_session",
            "packet_tester_id": identity["tester_id"],
            "packet_session_id": identity["session_id"],
        }
        module.verify_completed_row_identity(first / "completed-E1.jsonl", "E1", binding, [{"tester_id": "T-FIRST-01", "session_id": "S-FIRST-01"}])
        module.verify_completed_row_identity(first / "completed-E11.jsonl", "E11", binding, [{"tester_id": "T-FIRST-01"}])

        forged_receipt = dict(first_receipt)
        forged_receipt["tester_id"] = "T-SWAPPED"
        expect_rejection(
            lambda: module.verify_receipt_packet_identity(first / "finalization-receipt.json", forged_receipt),
            "receipt identity does not match immutable first-session packet identity",
        )
        expect_rejection(
            lambda: module.verify_completed_row_identity(first / "completed-E2.jsonl", "E2", binding, [{"tester_id": "T-FIRST-01", "session_id": "S-SWAPPED"}]),
            "completed-row session_id does not match immutable first-session packet identity",
        )
        expect_rejection(
            lambda: module.verify_completed_row_identity(first / "completed-E11.jsonl", "E11", binding, [{"tester_id": "T-SWAPPED"}]),
            "completed-row tester_id does not match immutable packet identity",
        )

        mature = root / "mature"
        mature.mkdir()
        write_json(mature / "observer-packet.json", {
            "tester_id": "T-MATURE-01",
            "rules_known_before_session": True,
            "rows_by_gate": {},
        })
        mature_receipt = {
            "packet_kind": "mature_session",
            "tester_id": "T-MATURE-01",
            "session_id": "",
        }
        mature_identity = module.verify_receipt_packet_identity(mature / "finalization-receipt.json", mature_receipt)
        mature_binding = {
            "packet_kind": "mature_session",
            "packet_tester_id": mature_identity["tester_id"],
            "packet_session_id": mature_identity["session_id"],
        }
        module.verify_completed_row_identity(mature / "completed-E6.jsonl", "E6", mature_binding, [{"tester_id": "T-MATURE-01"}])
        expect_rejection(
            lambda: module.verify_completed_row_identity(mature / "completed-E6.jsonl", "E6", mature_binding, [{"tester_id": "OTHER"}]),
            "completed-row tester_id does not match immutable packet identity",
        )
        expect_rejection(
            lambda: module.verify_completed_row_identity(mature / "completed-E1.jsonl", "E1", mature_binding, [{"tester_id": "T-MATURE-01"}]),
            "mature_session receipt cannot bind completed E1 rows",
        )

    print("Phase 12G human packet identity binding audit: PASS (receipt identity rechecked against immutable packet identity; completed-row tester/session and packet-kind/gate cross-binding enforced; no human outcome inferred)")


if __name__ == "__main__":
    main()
