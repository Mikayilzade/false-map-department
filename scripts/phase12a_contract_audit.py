#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def fail(message: str) -> None:
    raise SystemExit(f"PHASE12A AUDIT FAIL: {message}")


def read(relative: str) -> str:
    path = ROOT / relative
    if not path.is_file():
        fail(f"missing required file: {relative}")
    return path.read_text(encoding="utf-8")


def require_tokens(relative: str, tokens: list[str]) -> None:
    text = read(relative)
    missing = [token for token in tokens if token not in text]
    if missing:
        fail(f"{relative} missing contract token(s): {', '.join(missing)}")


def main() -> None:
    project = read("project.godot")
    for token in [
        'run/main_scene="res://src/presentation/main.tscn"',
        'renderer/rendering_method="gl_compatibility"',
        "viewport_width=1280",
        "viewport_height=800",
    ]:
        if token not in project:
            fail(f"project.godot missing bootstrap contract: {token}")

    domain_dir = ROOT / "src" / "domain"
    forbidden_domain_fragments = [
        "res://src/presentation",
        "FileAccess",
        "DirAccess",
        "Input.",
        "OS.",
        "Time.",
        "RandomNumberGenerator",
        "randf(",
        "randi(",
        "get_tree(",
        "_process(",
        "_physics_process(",
        "Steam",
    ]
    domain_files = sorted(domain_dir.glob("*.gd"))
    if not domain_files:
        fail("Domain Core is empty")
    for path in domain_files:
        text = path.read_text(encoding="utf-8")
        hits = [fragment for fragment in forbidden_domain_fragments if fragment in text]
        if hits:
            fail(f"domain purity violation in {path.name}: {', '.join(hits)}")

    require_tokens(
        "src/application/player_command.gd",
        [
            '"road"',
            '"bridge"',
            '"border"',
            '"waterway"',
            '"landmark"',
            '"restricted_zone"',
            "expected_pre_state_hash",
            "candidate_ids",
        ],
    )
    command_text = read("src/application/player_command.gd")
    if "seventh_primitive" in command_text:
        fail("semantic command vocabulary contains a seventh primitive marker")

    require_tokens(
        "src/application/command_gate.gd",
        ["stale_pre_state", "expected_pre_state_hash", "current_pre_state_hash"],
    )
    require_tokens(
        "src/application/input_actions.gd",
        ["InputEventKey", "InputEventJoypadButton", "InputMap.action_add_event"],
    )
    require_tokens(
        "src/application/persistence_service.gd",
        ["SAVE_SCHEMA_VERSION", "payload_hash", "CanonicalJson.sha256"],
    )
    require_tokens(
        "src/application/content_loader.gd",
        ["Missing required field", "Malformed stable ID", "four-layer ceiling", "Unknown primitive family"],
    )

    presentation = read("src/presentation/main.gd")
    if "Steam" in presentation:
        fail("bootstrap presentation must run without Steam/platform services")

    tests = read("tests/test_runner.gd")
    required_test_groups = [
        "_test_stable_ids()",
        "_test_canonical_serialization()",
        "_test_semantic_command()",
        "_test_content_validator()",
        "_test_persistence_envelope()",
        "_test_domain_dependency_boundary()",
        "_test_session_command_gate()",
    ]
    missing_groups = [group for group in required_test_groups if group not in tests]
    if missing_groups:
        fail("headless suite is missing bootstrap group(s): " + ", ".join(missing_groups))

    fetch_helper = read("scripts/fetch_pinned_godot.sh")
    for token in [
        'VERSION="4.7.1-stable"',
        'ARCHIVE="Godot_v4.7.1-stable_linux.x86_64.zip"',
        'SHA512-SUMS.txt',
        'sha512sum -c -',
        'github.com/godotengine/godot/releases/download',
        'FMD_GODOT_ARCHIVE',
        'FMD_GODOT_SHA512_MANIFEST',
        'copy_offline_inputs',
    ]:
        if token not in fetch_helper:
            fail(f"pinned runtime fetch helper missing verification contract: {token}")

    workflow = read(".github/workflows/manual-godot-baseline.yml")
    forbidden_triggers = ["\n  push:", "\n  pull_request:", "\n  pull_request_target:", "\n  schedule:"]
    if any(trigger in workflow for trigger in forbidden_triggers):
        fail("manual baseline contains an automatic bootstrap trigger")
    for token in [
        "workflow_dispatch:",
        "scripts/fetch_pinned_godot.sh",
        "bash scripts/run_phase12a_runtime.sh",
        "phase12a-runtime-evidence",
        "if: always()",
    ]:
        if token not in workflow:
            fail(f"manual baseline missing orchestration contract: {token}")

    runtime_runner = read("scripts/run_phase12a_runtime.sh")
    for token in [
        "scripts/fetch_pinned_godot.sh",
        "FMD_FETCH_PINNED_GODOT",
        "runtime-fetch.log",
        "scripts/ci_policy_preflight.py",
        "scripts/bootstrap_preflight.py",
        "scripts/phase12a_contract_audit.py",
        "--editor --quit",
        "--script res://tests/test_runner.gd",
        "--headless --path . --quit-after 2",
        'write_manifest "BLOCKED"',
        'write_manifest "FAIL"',
        'write_manifest "PASS"',
        "environment.log",
        "runtime-blocker.log",
    ]:
        if token not in runtime_runner:
            fail(f"runtime runner missing verification/evidence contract: {token}")

    print(f"Phase 12A contract audit: PASS ({len(domain_files)} domain files checked)")


if __name__ == "__main__":
    main()
