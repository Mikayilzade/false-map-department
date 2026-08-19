#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WORKFLOW_DIR = ROOT / ".github" / "workflows"
FORBIDDEN_TOP_LEVEL_TRIGGERS = {"push", "pull_request", "pull_request_target", "schedule"}


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

    for workflow in workflows:
        text = workflow.read_text(encoding="utf-8")
        triggers = top_level_on_block(text)
        forbidden = sorted(set(triggers) & FORBIDDEN_TOP_LEVEL_TRIGGERS)
        if forbidden:
            fail(f"{workflow.relative_to(ROOT)} has forbidden bootstrap trigger(s): {', '.join(forbidden)}")
        if "workflow_dispatch" not in triggers:
            fail(f"{workflow.relative_to(ROOT)} is not manual workflow_dispatch-only during unstable bootstrap")

    print(f"CI policy preflight: PASS ({len(workflows)} manual workflow(s))")


if __name__ == "__main__":
    main()
