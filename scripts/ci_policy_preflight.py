#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WORKFLOW_DIR = ROOT / ".github" / "workflows"
STATUS_FILE = ROOT / "IMPLEMENTATION_STATUS.md"
AUTOMATIC_TRIGGERS = {"push", "pull_request", "pull_request_target", "schedule"}


def fail(message: str) -> None:
    raise SystemExit(f"CI POLICY FAIL: {message}")


def top_level_on_block(text: str) -> list[str]:
    lines = text.splitlines()
    in_on = False
    triggers: list[str] = []
    for raw in lines:
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        indent = len(raw) - len(raw.lstrip(" "))
        stripped = raw.strip()
        if indent == 0 and stripped == "on:":
            in_on = True
            continue
        if in_on and indent == 0:
            break
        if in_on and indent == 2 and stripped.endswith(":"):
            triggers.append(stripped[:-1])
    return triggers


def main() -> None:
    if not WORKFLOW_DIR.exists():
        print("CI policy preflight: PASS (no workflows)")
        return

    workflows = sorted(list(WORKFLOW_DIR.glob("*.yml")) + list(WORKFLOW_DIR.glob("*.yaml")))
    if not workflows:
        print("CI policy preflight: PASS (no workflows)")
        return

    status = STATUS_FILE.read_text(encoding="utf-8") if STATUS_FILE.exists() else ""
    phase12b_complete = "- 12B Vertical Slice: **COMPLETE" in status

    manual_count = 0
    automatic_count = 0
    for workflow in workflows:
        text = workflow.read_text(encoding="utf-8")
        triggers = top_level_on_block(text)
        automatic = sorted(set(triggers) & AUTOMATIC_TRIGGERS)
        if automatic:
            if not phase12b_complete:
                fail(f"{workflow.relative_to(ROOT)} enables automatic CI before 12B is complete")
            if automatic != ["push"]:
                fail(f"{workflow.relative_to(ROOT)} has unsupported automatic trigger(s): {', '.join(automatic)}")
            for marker in [
                "paths:",
                "runtime-evidence/phase12c/latest",
                "[skip ci]",
                "exit 0",
                "cancel-in-progress: true",
            ]:
                if marker not in text:
                    fail(f"{workflow.relative_to(ROOT)} lacks notification-safe automatic CI marker: {marker}")
            if "src/**" not in text or "tests/**" not in text or "scripts/**" not in text:
                fail(f"{workflow.relative_to(ROOT)} automatic paths are not scoped to implementation changes")
            automatic_count += 1
            continue

        if "workflow_dispatch" not in triggers:
            fail(f"{workflow.relative_to(ROOT)} must be manual workflow_dispatch or approved post-12B automatic push CI")
        manual_count += 1

    if automatic_count > 1:
        fail("Only one notification-safe automatic baseline workflow is allowed")
    print(
        "CI policy preflight: PASS "
        f"({manual_count} manual workflow(s), {automatic_count} notification-safe automatic workflow(s))"
    )


if __name__ == "__main__":
    main()
