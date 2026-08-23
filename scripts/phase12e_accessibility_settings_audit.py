#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
SERVICE = ROOT / "src/application/accessibility_settings_service.gd"
PRESENTATION = ROOT / "src/presentation/presentation_contract.gd"
INPUT_ACTIONS = ROOT / "src/application/input_actions.gd"
MAPPING = ROOT / "content/demo/demo_to_full_mapping.json"
TEST = ROOT / "tests/test_phase12e_accessibility_settings_runner.gd"
WRAPPER = ROOT / "scripts/run_phase12a_runtime.sh"


def fail(message: str) -> None:
    print(f"Phase 12E accessibility settings audit: FAIL — {message}", file=sys.stderr)
    raise SystemExit(1)


for path in [SERVICE, PRESENTATION, INPUT_ACTIONS, MAPPING, TEST, WRAPPER]:
    if not path.is_file():
        fail(f"missing {path.relative_to(ROOT)}")

service = SERVICE.read_text(encoding="utf-8")
presentation = PRESENTATION.read_text(encoding="utf-8")
input_actions = INPUT_ACTIONS.read_text(encoding="utf-8")
test = TEST.read_text(encoding="utf-8")
wrapper = WRAPPER.read_text(encoding="utf-8")
mapping = json.loads(MAPPING.read_text(encoding="utf-8"))

required_service_tokens = [
    'DOCUMENT_TYPE := "accessibility_settings"',
    'PAYLOAD_VERSION := 2',
    'UI_SCALE_MIN_PERCENT := 80',
    'UI_SCALE_MAX_PERCENT := 150',
    '"reduced_motion"',
    '"flash_reduction"',
    '"color_safe_patterns"',
    '"audio_independent_presentation"',
    '"controller_glyph_preference"',
    '"gameplay_remaps"',
    'func save(',
    'func load(',
    'func apply_to_runtime(',
    'func demo_transfer_subset(',
    'func merge_imported_subset(',
    'deterministic_mechanics_affected',
    'mastery_validity_affected',
    'PRIMARY_PATH',
    'TEMP_PATH',
    'BACKUP_PATH',
]
for token in required_service_tokens:
    if token not in service:
        fail(f"service missing contract token {token!r}")

for forbidden in [
    'ProfileProgressService',
    'ObjectiveInvariantEngine',
    'StabilityVerificationEngine',
    'CoreTransactionCoordinator',
    'mastery_contracts',
]:
    if forbidden in service:
        fail(f"settings service must not own gameplay/progression semantics: {forbidden}")

if 'runtime_accessibility_contract' not in presentation:
    fail("presentation contract is not wired to normalized accessibility settings")
for token in [
    '"audio_independent_presentation": true',
    '"color_safe_patterns": true',
    '"animation_carries_unique_information": false',
    '"audio_carries_unique_information": false',
    '"gameplay_semantics_affected": false',
]:
    if token not in presentation:
        fail(f"presentation runtime accessibility contract missing {token}")

if 'replace_bindings' not in input_actions or 'binding_descriptors' not in input_actions:
    fail("semantic remap boundary is missing from input actions")

expected_demo_keys = ["flash_reduction", "language", "reduced_motion", "ui_scale_percent"]
if mapping.get("compatible_setting_keys") != expected_demo_keys:
    fail("demo->full compatible setting whitelist changed unexpectedly")
for key in expected_demo_keys:
    if key not in service:
        fail(f"settings service does not support mapped demo key {key}")

required_test_tokens = [
    '_test_defaults_and_normalization',
    '_test_save_reload_runtime_application',
    '_test_payload_migration',
    '_test_backup_recovery',
    '_test_demo_to_full_settings_whitelist',
    'mastery_validity_affected',
    'master_volume_percent',
]
for token in required_test_tokens:
    if token not in test:
        fail(f"Godot acceptance missing {token}")

if 'phase12e-accessibility-settings-contract' not in wrapper:
    fail("aggregate wrapper missing accessibility settings static gate")
if 'phase12e-accessibility-settings-suite' not in wrapper:
    fail("aggregate wrapper missing accessibility settings Godot suite")

print("Phase 12E persisted accessibility settings audit: PASS (versioned save/defaults/migration/remaps/demo whitelist)")
