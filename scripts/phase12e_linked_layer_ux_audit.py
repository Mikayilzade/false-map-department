#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PRESENTER = ROOT / "src/presentation/linked_layer_presenter.gd"
RUNTIME = ROOT / "scripts/run_phase12a_runtime.sh"
CAMPAIGN = ROOT / "content/campaign"

def fail(message: str) -> None:
    raise SystemExit(f"PHASE12E LINKED UX FAIL: {message}")

def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))

def main() -> None:
    if not PRESENTER.exists():
        fail("linked-layer presenter missing")
    source = PRESENTER.read_text(encoding="utf-8")
    required_markers = [
        "LinkedAuthorityEngine",
        "PresentationContract.MAX_VISIBLE_EDIT_SURFACES",
        "linked_authority_relations",
        "breadcrumb_entries",
        "breadcrumb_text",
        "Authoritative here",
        "Derived from",
        "jump_to_authoritative_source",
        "consequence_badges",
        "jump_to_consequence",
        "cycle_layer",
        "target_projection_id",
        "source_fact_id",
    ]
    for marker in required_markers:
        if marker not in source:
            fail(f"presenter missing marker: {marker}")
    forbidden_markers = [
        "known_solution_envelope",
        "solution_commands",
        "OS.get_ticks",
        "Time.get_",
        "get_process_delta_time",
        "rand",
    ]
    for marker in forbidden_markers:
        if marker in source:
            fail(f"presenter contains forbidden gameplay/oracle dependency: {marker}")

    linked_count = 0
    four_layer_count = 0
    for index in range(1, 41):
        dossier = load(CAMPAIGN / f"D{index:02d}.json")
        layers = dossier.get("map_layers", [])
        relations = dossier.get("linked_authority_relations", [])
        if not relations:
            continue
        linked_count += 1
        if len(layers) > 4:
            fail(f"D{index:02d} exceeds four-layer ceiling")
        if len(layers) == 4:
            four_layer_count += 1
        layer_ids = [layer.get("layer_id") for layer in layers]
        if len(layer_ids) != len(set(layer_ids)):
            fail(f"D{index:02d} duplicate layer ids")
        editable_layers = [
            layer.get("layer_id")
            for layer in layers
            if layer.get("editable_candidates", [])
        ]
        if len(editable_layers) > 2:
            fail(f"D{index:02d} exceeds two simultaneous editing surfaces")
        target_keys = set()
        for relation in relations:
            if relation.get("direction") != "one-way":
                fail(f"D{index:02d} relation must remain one-way")
            src = relation.get("source_layer_id")
            dst = relation.get("target_layer_id")
            if src not in layer_ids or dst not in layer_ids or src == dst:
                fail(f"D{index:02d} relation layer invalid")
            if not relation.get("source_fact_id") or not relation.get("target_projection_id"):
                fail(f"D{index:02d} relation fact identity missing")
            key = (dst, relation.get("target_projection_id"))
            if key in target_keys:
                fail(f"D{index:02d} projected target double-owned")
            target_keys.add(key)
            if relation.get("target_projection_id") in next(
                layer for layer in layers if layer.get("layer_id") == dst
            ).get("editable_candidates", []):
                fail(f"D{index:02d} derived target is editable")

    if linked_count < 10:
        fail(f"expected broad linked campaign coverage, found only {linked_count}")
    if four_layer_count < 1:
        fail("four-layer linked content coverage missing")

    runtime = RUNTIME.read_text(encoding="utf-8")
    for marker in [
        "phase12e-linked-layer-ux-contract",
        "phase12e-linked-layer-ux-suite",
        "test_phase12e_linked_layer_ux_runner.gd",
    ]:
        if marker not in runtime:
            fail(f"runtime wrapper missing marker: {marker}")

    print(
        "Phase 12E linked-layer UX audit: PASS "
        f"({linked_count} linked dossiers; breadcrumbs/source jumps; <=2 editing surfaces)"
    )

if __name__ == "__main__":
    main()
