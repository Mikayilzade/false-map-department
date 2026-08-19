#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def fail(message: str) -> None:
    raise SystemExit(f"PRECHECK FAIL: {message}")


def canonical_json(value: object) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def main() -> None:
    required = [
        ROOT / "project.godot",
        ROOT / ".godot-version",
        ROOT / "src/domain/canonical_json.gd",
        ROOT / "src/domain/stable_id.gd",
        ROOT / "src/application/player_command.gd",
        ROOT / "src/application/content_loader.gd",
        ROOT / "src/presentation/main.tscn",
        ROOT / "tests/test_runner.gd",
        ROOT / "tests/fixtures/tiny_dossier.json",
    ]
    missing = [str(path.relative_to(ROOT)) for path in required if not path.is_file()]
    if missing:
        fail("missing files: " + ", ".join(missing))

    if (ROOT / ".godot-version").read_text(encoding="utf-8").strip() != "4.7.1-stable":
        fail("engine pin must be exactly 4.7.1-stable")

    fixture = json.loads((ROOT / "tests/fixtures/tiny_dossier.json").read_text(encoding="utf-8"))
    if fixture.get("dossier_id") != "BOOT01":
        fail("tiny fixture dossier_id changed unexpectedly")
    if len(fixture.get("map_layers", [])) > 4:
        fail("fixture exceeds four-layer ceiling")

    canonical = canonical_json(fixture)
    reordered = dict(reversed(list(fixture.items())))
    if canonical != canonical_json(reordered):
        fail("canonical JSON is not key-order independent")
    digest = hashlib.sha256(canonical.encode("utf-8")).hexdigest()
    if len(digest) != 64:
        fail("SHA-256 digest malformed")

    command_source = (ROOT / "src/application/player_command.gd").read_text(encoding="utf-8")
    primitives = ["road", "bridge", "border", "waterway", "landmark", "restricted_zone"]
    if any(f'"{primitive}"' not in command_source for primitive in primitives):
        fail("semantic command does not expose all six frozen primitive families")
    if '"seventh_' in command_source:
        fail("unexpected seventh primitive marker")

    for source in (ROOT / "src/domain").glob("*.gd"):
        text = source.read_text(encoding="utf-8")
        if "res://src/presentation" in text:
            fail(f"domain depends on presentation: {source.name}")

    print("FMD bootstrap preflight: PASS")
    print(f"fixture_sha256={digest}")


if __name__ == "__main__":
    main()
