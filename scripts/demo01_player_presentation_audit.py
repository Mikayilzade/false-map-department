#!/usr/bin/env python3
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
visual = (ROOT / "src/presentation/demo01_visual.gd").read_text(encoding="utf-8")
rules = (ROOT / "PRODUCT_ACCEPTANCE_RULES.md").read_text(encoding="utf-8")
entrypoint = (ROOT / "src/presentation/entrypoint.gd").read_text(encoding="utf-8")
windows_build = (ROOT / "scripts/build_windows_playtest.ps1").read_text(encoding="utf-8")

forbidden = [
    r"DEMO01_(?:R|AG|N|OBJ|LM|L1)_",
    r"subject_stable_id",
    r"event_type",
    r"candidate_id",
    r"node_id",
    r"LATEST CAUSAL EVENTS",
    r"PRODUCTION PLAYTEST",
]
for pattern in forbidden:
    if re.search(pattern, visual):
        raise SystemExit(f"DEMO01 PLAYER PRESENTATION AUDIT FAIL: normal visual contains {pattern}")

required = [
    "OFFICIAL MAP", "LIVING DISTRICT", "Connect the courier's home",
    "road_activated.emit()", "Courier waiting", "Courier delivered!",
]
for marker in required:
    if marker not in visual:
        raise SystemExit(f"DEMO01 PLAYER PRESENTATION AUDIT FAIL: missing {marker}")
if "cannot satisfy this gate" not in rules:
    raise SystemExit("DEMO01 PLAYER PRESENTATION AUDIT FAIL: product acceptance gate missing")
for marker in [
    "_route_to_scene.call_deferred(target)",
    '"--audio-driver", "Dummy"',
    '"(?m)^\\s*(?:SCRIPT )?ERROR:"',
    'Assert-CleanGodotRuntimeLog $InitialLog',
    'Assert-CleanGodotRuntimeLog $SolvedLog',
]:
    source = entrypoint if "call_deferred" in marker else windows_build
    if marker not in source:
        raise SystemExit(f"DEMO01 PLAYER PRESENTATION AUDIT FAIL: lifecycle/runtime-log guard missing: {marker}")

print("DEMO01 player presentation audit: PASS (visual/player gate + deferred entry route + strict Windows runtime logs)")
