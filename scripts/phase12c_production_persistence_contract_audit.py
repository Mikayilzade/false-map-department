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
    raise SystemExit(f"PHASE12C PRODUCTION PERSISTENCE FAIL: {message}")

def main() -> None:
    storage_path = ROOT / "src/platform/storage_adapter.gd"
    local_path = ROOT / "src/platform/local_storage_adapter.gd"
    migration_path = ROOT / "src/application/save_schema_migration_service.gd"
    durable_path = ROOT / "src/application/durable_profile_progress_service.gd"
    test_path = ROOT / "tests/test_profile_persistence_migration_runner.gd"
    runtime_path = ROOT / "scripts/run_phase12a_runtime.sh"

    files = [storage_path, local_path, migration_path, durable_path, test_path, runtime_path]
    for path in files:
        if not path.exists():
            fail(f"missing production persistence artifact: {path.relative_to(ROOT)}")

    storage = storage_path.read_text(encoding="utf-8")
    local = local_path.read_text(encoding="utf-8")
    migration = migration_path.read_text(encoding="utf-8")
    durable = durable_path.read_text(encoding="utf-8")
    test = test_path.read_text(encoding="utf-8")
    runtime = runtime_path.read_text(encoding="utf-8")

    for marker in ["remove_path", "rename_path"]:
        if marker not in storage:
            fail(f"storage adapter missing atomic-ish file operation: {marker}")
        if marker not in local:
            fail(f"local storage adapter missing operation: {marker}")
    for marker in ["file.flush()", "DirAccess.remove_absolute", "DirAccess.rename_absolute"]:
        if marker not in local:
            fail(f"local storage adapter missing durability marker: {marker}")

    for marker in [
        "MIN_SUPPORTED_SCHEMA_VERSION := 0",
        "CURRENT_SCHEMA_VERSION",
        "_migrate_v0_to_v1",
        "profile_progress:0->1",
        "save_schema_future_version_unsupported",
        "save_schema_payload_checksum_invalid",
        "migration_steps",
    ]:
        if marker not in migration:
            fail(f"save schema migration service missing marker: {marker}")

    for marker in [
        'PRIMARY_PATH := "profile_progress.json"',
        'TEMP_PATH := "profile_progress.tmp"',
        'BACKUP_PATH := "profile_progress.bak"',
        "LEGACY_SLOT_PATHS",
        "_write_validated_temp",
        "_promote_recovered_candidate",
        "profile_progress_generation_not_monotonic",
        "profile_progress_corrupt_primary_preserved",
        "profile_progress_equal_generation_conflict",
        "profile_progress_recovery_before_save_required",
        "_storage.rename_path(PRIMARY_PATH, BACKUP_PATH)",
        "_storage.rename_path(TEMP_PATH, PRIMARY_PATH)",
    ]:
        if marker not in durable:
            fail(f"durable profile production protocol missing marker: {marker}")

    for marker in [
        "Production save generation 1 must commit through temp to primary",
        "Backup must preserve previous valid primary generation",
        "Valid newer temp crash remnant must outrank older primary and backup",
        "Crash recovery must rewrite a clean primary from newest valid temp",
        "Recovery must never overwrite the only corrupt evidence",
        "New save must not overwrite an unresolved corrupt primary",
        "Supported save-schema N -> N+1 migration must preserve generation",
        "Migration chain must record the exact monotonic 0 -> 1 step",
        "Migration rewrite must preserve the original supported legacy envelope as backup evidence",
        "Previous alternating-slot profile saves must remain recoverable during production protocol migration",
        "Unsupported future save schema must not be guessed or silently downgraded",
    ]:
        if marker not in test:
            fail(f"production persistence acceptance coverage missing: {marker}")

    if "phase12c-production-persistence-contract" not in runtime:
        fail("runtime wrapper must execute production persistence contract audit")
    if "test_profile_persistence_migration_runner.gd" not in runtime:
        fail("runtime wrapper must execute production persistence/migration headless suite")

    for path, source in [
        (storage_path, storage),
        (local_path, local),
        (migration_path, migration),
        (durable_path, durable),
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

    print("Phase 12C production persistence audit: PASS (primary/tmp/bak + migration + corrupt-evidence preservation)")

if __name__ == "__main__":
    main()
