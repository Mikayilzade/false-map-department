#!/usr/bin/env python3
from __future__ import annotations
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

REQUIRED = {
    "src/application/remix_overlay_validator.gd": [
        "p10_r10_causal_dependency_unchanged",
        "p10_r10_reasoning_transformation_unchanged",
        "remix_safety_flag_missing",
    ],
    "src/application/remix_registry_service.gd": [
        "REMIX12",
        "p10_r10_pack_diversity_failed",
        "remix_registry_overlay_invalid",
    ],
    "tests/test_phase12f_persistence_recovery_adversarial_runner.gd": [
        "Uncommitted in-memory edit must never become authoritative after process death",
        "Interrupted Stability must restore exact pre-verification state",
        "All-invalid profile generations must enter explicit recovery",
    ],
    "tests/test_phase12f_profile_demo_adversarial_runner.gd": [
        "Cloud/profile merge must never synthesize divergent active dossier branches",
        "Repeated demo receipt must be idempotent",
        "Unsupported demo export version must reject before mutation",
    ],
    "tests/test_phase12f_authority_focus_content_adversarial_runner.gd": [
        "Authority cycle must reject",
        "Disconnected required focus candidate must reject",
        "Relabel universal-shortcut bypass must fail production validation",
        "Production remix registry must expose exact REMIX01-REMIX12",
    ],
}


def fail(message: str) -> None:
    raise SystemExit(f"PHASE12F BROAD ADVERSARIAL FAIL: {message}")


def main() -> None:
    for rel, markers in REQUIRED.items():
        path = ROOT / rel
        if not path.exists():
            fail(f"missing artifact: {rel}")
        text = path.read_text(encoding="utf-8")
        for marker in markers:
            if marker not in text:
                fail(f"missing marker in {rel}: {marker}")

    durable_session = (ROOT / "src/application/durable_session_service.gd").read_text(encoding="utf-8")
    durable_profile = (ROOT / "src/application/durable_profile_progress_service.gd").read_text(encoding="utf-8")
    profiles = (ROOT / "src/application/profile_progress_service.gd").read_text(encoding="utf-8")
    demo = (ROOT / "src/application/demo_import_service.gd").read_text(encoding="utf-8")
    linked = (ROOT / "src/domain/linked_authority_engine.gd").read_text(encoding="utf-8")
    focus = (ROOT / "src/presentation/authored_focus_navigator.gd").read_text(encoding="utf-8")
    validator = (ROOT / "src/application/frozen_content_validator.gd").read_text(encoding="utf-8")
    runtime = (ROOT / "scripts/run_phase12a_runtime.sh").read_text(encoding="utf-8")

    for marker in ["STABILITY_IN_PROGRESS", "pre_verification_state", "RECOVERY_NOTICE", "payload_version"]:
        if marker not in durable_session:
            fail(f"durable session recovery contract missing: {marker}")
    for marker in ["PRIMARY_PATH", "TEMP_PATH", "BACKUP_PATH", "profile_progress_equal_generation_conflict", "recovery_before_save_required"]:
        if marker not in durable_profile:
            fail(f"profile recovery contract missing: {marker}")
    if "active_session_state" in profiles:
        fail("durable profile merge must not own active dossier session state")
    for marker in ["already_imported", "demo_import_checksum_invalid", "compatible_setting_keys"]:
        if marker not in demo:
            fail(f"demo boundary contract missing: {marker}")
    for marker in ["linked_authority_cycle", "linked_authority_double_ownership", "linked_authority_projected_fact_editable_on_target"]:
        if marker not in linked:
            fail(f"authority adversarial guard missing: {marker}")
    for marker in ["focus_required_unreachable", "focus_edit_surface_ceiling_exceeded"]:
        if marker not in focus:
            fail(f"focus adversarial guard missing: {marker}")
    for marker in ["p10_r2_central_lesson_bypass", "p10_r4_mastery_distinction_note_missing", "p10_r5_remote_layer_budget_exceeded", "p10_r6_material_node_budget_exceeded", "d40_mastery_gate_forbidden"]:
        if marker not in validator:
            fail(f"content adversarial guard missing: {marker}")

    for marker in [
        "phase12f-broad-adversarial-contract",
        "phase12f-persistence-recovery-adversarial-suite",
        "phase12f-profile-demo-adversarial-suite",
        "phase12f-authority-focus-content-adversarial-suite",
    ]:
        if marker not in runtime:
            fail(f"aggregate runtime missing broad 12F gate: {marker}")

    print("Phase 12F broad adversarial audit: PASS (persistence + process death + profile/demo + authority/focus/content)")


if __name__ == "__main__":
    main()
