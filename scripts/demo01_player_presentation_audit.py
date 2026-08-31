#!/usr/bin/env python3
from pathlib import Path
import re
import json

ROOT = Path(__file__).resolve().parents[1]
visual = (ROOT / "src/presentation/demo01_visual.gd").read_text(encoding="utf-8")
rules = (ROOT / "PRODUCT_ACCEPTANCE_RULES.md").read_text(encoding="utf-8")
entrypoint = (ROOT / "src/presentation/entrypoint.gd").read_text(encoding="utf-8")
windows_build = (ROOT / "scripts/build_windows_playtest.ps1").read_text(encoding="utf-8")

forbidden = [
    r"DEMO\d\d_(?:R|B|AG|N|OBJ|INV|LM|L1|C|J)_",
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
    "OFFICIAL MAP", "LIVING DISTRICT", "CASE CONDITIONS",
    "MAP EDIT", "WORLD CHANGES", "ROUTE REACTS", "CONDITIONS UPDATE",
    "candidate_activated.emit", "stability_requested.emit", "next_case_requested.emit",
    "THE GARDEN SHORTCUT", "THE PAPER BRIDGE", "TWO SIDES OF THE CANAL", "A LINE IS NOT A WALL",
    '"GOAL"', '"PROTECT"', "CONFIRM DISTRICT", "NEXT CASE",
    "DEMO COMPLETE", "WORKPLACE",
    "NOT YET CHECKED", "presentation_settled", "active_candidate_evidence", "condition_evidence",
    "draw_multiline_string", "Agent status lives above the actor",
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
    'Assert-CleanGodotRuntimeLog $Log',
    'Capture-DemoState $Dossier 0 "initial"',
    'Capture-DemoState $Dossier $SolutionSteps[$Dossier] "solved"',
]:
    source = entrypoint if "call_deferred" in marker else windows_build
    if marker not in source:
        raise SystemExit(f"DEMO01 PLAYER PRESENTATION AUDIT FAIL: lifecycle/runtime-log guard missing: {marker}")

for marker in [
    'return "PENDING"',
    'await demo01_visual.presentation_settled',
    'settled=true active=%s',
    'lane_offset: float',
    'rendered_by_stability',
]:
    source = visual if marker in {'return "PENDING"', 'lane_offset: float'} else (ROOT / "src/presentation/production_playtest.gd").read_text(encoding="utf-8")
    if marker not in source:
        raise SystemExit(f"DEMO PLAYER PRESENTATION AUDIT FAIL: semantic screenshot guard missing: {marker}")
if 'if values.is_empty():\n\t\treturn true' in visual:
    raise SystemExit("DEMO PLAYER PRESENTATION AUDIT FAIL: unevaluated condition must never render as MET")
for marker in ["$InitialActive", "$SolvedActive", "$ConsequenceActive", "$InitialConditions", "$SolvedConditions", "$ConsequenceConditions", "initial and solved screenshots are byte-identical", '"--resolution", "1280x800"', "PNG does not match its recorded runtime viewport", "runtime viewport is too small", "$ObservedCaptureSizes"]:
    if marker not in windows_build:
        raise SystemExit(f"DEMO PLAYER PRESENTATION AUDIT FAIL: built-runtime evidence check missing: {marker}")

copy = json.loads((ROOT / "content/demo/playtest_copy.json").read_text(encoding="utf-8"))["dossiers"]
for number in range(1, 6):
    dossier_id = f"DEMO{number:02d}"
    dossier = json.loads((ROOT / f"content/demo/{dossier_id}.json").read_text(encoding="utf-8"))
    canonical_ids = {row["objective_id"] for row in dossier["objectives"]}
    canonical_ids.update(row["invariant_id"] for row in dossier["protected_invariants"])
    copy_ids = set(copy[dossier_id]["requirements"])
    if copy_ids != canonical_ids:
        raise SystemExit(f"DEMO PLAYER PRESENTATION AUDIT FAIL: {dossier_id} copy contradicts canonical requirement IDs")

print("DEMO01-DEMO05 player presentation audit: PASS (dual views, direct edits, causal stages, canonical copy, no internal UI IDs)")
