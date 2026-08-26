#!/usr/bin/env python3
from __future__ import annotations

import copy
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
SCRIPT_DIR = ROOT / "scripts"
sys.path.insert(0, str(SCRIPT_DIR))

import phase12g_e8_acquisition_build_bind as binding  # noqa: E402


def fail(message: str) -> None:
    raise SystemExit(f"PHASE12G E8 RESPONDENT IDENTITY FAIL: {message}")


def expect_rejected(asset_set: dict, respondents: dict, label: str) -> None:
    try:
        binding.verify_respondent_identity_binding(asset_set, respondents)
    except ValueError:
        return
    fail(f"{label} was not rejected")


def main() -> None:
    respondents = {
        "rows": [
            {
                "respondent_id": "E8R-001",
                "asset_version": "AUDIT-E8",
                "expected_play_category": None,
                "freeform_builder_expectation": None,
                "notes": None,
            },
            {
                "respondent_id": "E8R-002",
                "asset_version": "AUDIT-E8",
                "expected_play_category": None,
                "freeform_builder_expectation": None,
                "notes": None,
            },
        ]
    }
    immutable = binding.make_respondent_identity_binding(respondents)
    asset_set = {"respondent_identity_binding": copy.deepcopy(immutable)}
    packet = copy.deepcopy(respondents)
    packet["respondent_identity_binding"] = copy.deepcopy(immutable)

    verified = binding.verify_respondent_identity_binding(asset_set, packet)
    if verified != immutable:
        fail("clean acquisition-time identity binding did not verify exactly")

    observed_fields = copy.deepcopy(packet)
    observed_fields["rows"][0]["expected_play_category"] = "systemic puzzle"
    observed_fields["rows"][0]["freeform_builder_expectation"] = False
    observed_fields["rows"][0]["notes"] = "Observed response"
    if binding.verify_respondent_identity_binding(asset_set, observed_fields) != immutable:
        fail("legitimate observation fields must not invalidate immutable respondent identity")

    changed_id = copy.deepcopy(packet)
    changed_id["rows"][0]["respondent_id"] = "E8R-999"
    expect_rejected(asset_set, changed_id, "post-preparation respondent_id substitution")

    changed_id_and_self_claim = copy.deepcopy(changed_id)
    changed_id_and_self_claim["respondent_identity_binding"] = binding.make_respondent_identity_binding(changed_id_and_self_claim)
    expect_rejected(asset_set, changed_id_and_self_claim, "respondent-side identity digest rewrite")

    reordered = copy.deepcopy(packet)
    reordered["rows"].reverse()
    expect_rejected(asset_set, reordered, "respondent slot reorder")

    duplicate = copy.deepcopy(packet)
    duplicate["rows"][1]["respondent_id"] = "E8R-001"
    expect_rejected(asset_set, duplicate, "duplicate respondent identity")

    missing = copy.deepcopy(packet)
    missing["rows"][0]["respondent_id"] = ""
    expect_rejected(asset_set, missing, "missing respondent identity")

    receipt_text = (SCRIPT_DIR / "phase12g_marketing_completion_receipt.py").read_text(encoding="utf-8")
    ingest_text = (SCRIPT_DIR / "phase12g_marketing_expectation_ingest.py").read_text(encoding="utf-8")
    prepare_text = (SCRIPT_DIR / "phase12g_marketing_acquisition_prepare.py").read_text(encoding="utf-8")
    if "verify_packet_binding" not in receipt_text:
        fail("completion receipt does not transitively enforce acquisition packet binding")
    if "verify_receipt" not in ingest_text:
        fail("repository ingest does not require completion-receipt verification")
    if "phase12g_e8_acquisition_build_bind.py" not in prepare_text:
        fail("real acquisition preparation does not use the identity/build binder")

    print(
        "Phase 12G E8 respondent identity binding audit: PASS "
        "(respondent slots frozen before observation; outcome fields remain editable; "
        "ID substitution/rewrite/reorder/duplicate/missing attacks rejected; receipt+ingest enforcement chained; synthetic non-evidence)"
    )


if __name__ == "__main__":
    main()
