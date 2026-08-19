#!/usr/bin/env python3
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

DIRECT_VARIANT_GET_INFERENCE = re.compile(
    r'^\s*var\s+\w+\s*:=\s*[A-Za-z_]\w*(?:\[[^\]]+\])?\.get\(',
    re.MULTILINE,
)


def fail(message: str) -> None:
    raise SystemExit(f"PHASE12B CONTRACT FAIL: {message}")


def main() -> None:
    session = (ROOT / "src/application/slice_session.gd").read_text(encoding="utf-8")
    view = (ROOT / "src/application/slice_view_snapshot.gd").read_text(encoding="utf-8")
    presentation = (ROOT / "src/presentation/main.gd").read_text(encoding="utf-8")
    scene = (ROOT / "src/presentation/main.tscn").read_text(encoding="utf-8")
    definition = json.loads((ROOT / "content/vertical_slice/VS01.json").read_text(encoding="utf-8"))

    required_history_markers = [
        "pre_checkpoint", "post_checkpoint", "pre_state_hash", "post_state_hash",
        "func undo()", "func redo()", "_history.resize(_history_cursor)",
        "redo_checkpoint_not_byte_equivalent",
    ]
    for marker in required_history_markers:
        if marker not in session:
            fail(f"missing history contract marker: {marker}")

    if "res://src/presentation" in session:
        fail("application history session may not depend on presentation")
    if "MicroSliceEngine" in presentation:
        fail("presentation must not invoke the domain engine directly")
    if "SliceViewSnapshot" not in presentation or "SliceSession" not in presentation:
        fail("presentation is not wired through application session/snapshot")
    if "OFFICIAL MAP" not in scene or "DERIVED WORLD" not in scene:
        fail("dual map/world presentation contract missing")

    edge_ids = sorted(definition["road_edges"])
    if edge_ids != ["E12", "E13", "E24", "E34", "EP"]:
        fail("vertical-slice road candidates drifted")
    if definition["agents"]["AG01"]["archetype"] != "A1_DIRECT_COURIER":
        fail("vertical slice must use the frozen A1 Direct Courier")
    if definition["reaction_beats_after_edit"] != 1:
        fail("vertical slice must retain one bounded reaction beat")

    # Godot 4.7.1 treats warnings as errors during our import gate. A direct
    # `var x := dictionary.get(...)` infers Variant and can therefore break the
    # runtime even when static Python checks are green. Require an explicit type
    # or a typed conversion for direct Dictionary.get assignments in early 12B.
    gdscript_roots = [ROOT / "src/domain", ROOT / "src/application", ROOT / "src/presentation"]
    for gdscript_root in gdscript_roots:
        for path in sorted(gdscript_root.glob("*.gd")):
            text = path.read_text(encoding="utf-8")
            match = DIRECT_VARIANT_GET_INFERENCE.search(text)
            if match:
                line_number = text.count("\n", 0, match.start()) + 1
                fail(
                    f"direct Variant inference from Dictionary.get in "
                    f"{path.relative_to(ROOT)}:{line_number}; add an explicit type"
                )

    print("Phase 12B contract audit: PASS")


if __name__ == "__main__":
    main()
