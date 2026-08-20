#!/usr/bin/env python3
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

DIRECT_VARIANT_GET_INFERENCE = re.compile(
    r'^\s*var\s+\w+\s*:=\s*[A-Za-z_]\w*(?:\[[^\]]+\])?\.get\(',
    re.MULTILINE,
)
DIRECT_JSON_PARSE_INFERENCE = re.compile(
    r'^\s*var\s+\w+\s*:=\s*JSON\.parse_string\(',
    re.MULTILINE,
)

def fail(message: str) -> None:
    raise SystemExit(f"PHASE12C PROFILE/DEMO FAIL: {message}")

def main() -> None:
    profile_path = ROOT / "src/application/profile_progress_service.gd"
    durable_path = ROOT / "src/application/durable_profile_progress_service.gd"
    demo_path = ROOT / "src/application/demo_import_service.gd"
    test_path = ROOT / "tests/test_profile_demo_runner.gd"
    runtime_path = ROOT / "scripts/run_phase12a_runtime.sh"

    files = [profile_path, durable_path, demo_path, test_path, runtime_path]
    for path in files:
        if not path.exists():
            fail(f"missing profile/demo artifact: {path.relative_to(ROOT)}")

    profile = profile_path.read_text(encoding="utf-8")
    durable = durable_path.read_text(encoding="utf-8")
    demo = demo_path.read_text(encoding="utf-8")
    test = test_path.read_text(encoding="utf-8")
    runtime = runtime_path.read_text(encoding="utf-8")

    for marker in [
        "clear_records_by_id",
        "tutorial_tags",
        "mastery_records_by_id",
        "historical_mastery_records_by_id",
        "achievement_local_ids",
        "remix_unlock_ids",
        "demo_import_receipt_ids",
        "merge_parent_hashes",
        "derive_remix_unlocks",
        "profile_record_identity_conflict",
    ]:
        if marker not in profile:
            fail(f"profile progress service missing marker: {marker}")

    for marker in [
        'DOCUMENT_TYPE := "profile_progress"',
        "profile_progress_equal_generation_conflict",
        "profile_progress_recovery_required",
        "RECOVERY_MESSAGE",
        "_slot_path",
        "payload_hash",
    ]:
        if marker not in durable:
            fail(f"durable profile service missing marker: {marker}")

    for marker in [
        "DEMO_FORMAT_ID",
        "demo_to_full_mapping",
        "mapping_version",
        "baseline_clear_equivalent",
        "mastery_equivalences_by_demo_mastery_id",
        "compatible_setting_keys",
        "demo_import_receipt_id",
        "already_imported",
        "demo_import_checksum_invalid",
    ]:
        if marker not in demo:
            fail(f"demo import service missing marker: {marker}")

    for marker in [
        "T8-28 compatible profile merge must succeed",
        "Corrupt newest profile_progress must fall back to newest older valid generation",
        "Equal-generation divergent valid profile copies must not be chosen by file iteration order",
        "No valid profile generation must require recovery instead of overwriting bad files",
        "DEMO05 must not auto-clear D05 merely because it teaches the same border rule",
        "T8-31 reimporting the same demo receipt must be idempotent",
        "T8-32 incompatible demo clear must be skipped",
        "T8-32 compatible settings must still import when clear mapping is incompatible",
    ]:
        if marker not in test:
            fail(f"profile/demo acceptance coverage missing: {marker}")

    if "phase12c-profile-demo-contract" not in runtime:
        fail("runtime wrapper must execute profile/demo contract audit")
    if "test_profile_demo_runner.gd" not in runtime:
        fail("runtime wrapper must execute profile/demo headless suite")

    for path, source in [
        (profile_path, profile),
        (durable_path, durable),
        (demo_path, demo),
        (test_path, test),
    ]:
        match = DIRECT_VARIANT_GET_INFERENCE.search(source)
        if match:
            line = source.count("\n", 0, match.start()) + 1
            fail(f"direct Variant inference from Dictionary.get in {path.relative_to(ROOT)}:{line}")
        match = DIRECT_JSON_PARSE_INFERENCE.search(source)
        if match:
            line = source.count("\n", 0, match.start()) + 1
            fail(f"direct Variant inference from JSON.parse_string in {path.relative_to(ROOT)}:{line}")

    print("Phase 12C profile/demo contract audit: PASS (T8-28/T8-31/T8-32 + recovery)")

if __name__ == "__main__":
    main()
