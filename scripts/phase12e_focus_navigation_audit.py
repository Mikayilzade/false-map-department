#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REGISTRY = ROOT / "content/registry.json"
LINKS = ("up", "down", "left", "right", "next", "previous")
CARDINAL = ("up", "down", "left", "right")
SIX = {"road", "bridge", "border", "waterway", "landmark", "restricted_zone"}


def fail(message: str) -> None:
    raise SystemExit(f"PHASE12E FOCUS FAIL: {message}")


def load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def validate_dossier(dossier: dict) -> tuple[set[str], int]:
    did = dossier.get("dossier_id", "")
    metadata = dossier.get("validation_metadata", {})
    focus_by_layer = metadata.get("focus_graph_by_layer", {})
    families = set(dossier.get("editable_primitive_permissions", []))
    editable_layers = 0
    for layer in dossier.get("map_layers", []):
        editable = sorted(layer.get("editable_candidates", []))
        if not editable:
            continue
        editable_layers += 1
        lid = layer.get("layer_id", "")
        authored = focus_by_layer.get(lid)
        if not isinstance(authored, dict):
            fail(f"{did}:{lid} missing authored focus metadata")
        required = sorted(authored.get("required_focusable_candidate_ids", []))
        graph = authored.get("neighbors_by_candidate_id", {})
        if required != editable:
            fail(f"{did}:{lid} focusable candidates differ from editable candidates")
        if not isinstance(graph, dict) or set(graph) != set(required):
            fail(f"{did}:{lid} graph identity must exactly match required candidates")
        for candidate in required:
            neighbors = graph.get(candidate)
            if not isinstance(neighbors, dict):
                fail(f"{did}:{lid}:{candidate} malformed neighbor record")
            for key in CARDINAL:
                if key not in neighbors:
                    fail(f"{did}:{lid}:{candidate} missing cardinal key {key}")
            for key in LINKS:
                target = str(neighbors.get(key, ""))
                if target and target not in graph:
                    fail(f"{did}:{lid}:{candidate} points to unknown focus target {target}")
        seen = {required[0]}
        queue = [required[0]]
        while queue:
            current = queue.pop(0)
            for key in LINKS:
                target = str(graph[current].get(key, ""))
                if target and target not in seen:
                    seen.add(target)
                    queue.append(target)
        missing = set(required) - seen
        if missing:
            fail(f"{did}:{lid} unreachable authored focus candidates {sorted(missing)}")
    if editable_layers > 2:
        fail(f"{did} exposes {editable_layers} editable layers; two-surface ceiling exceeded")
    return families, editable_layers


def main() -> None:
    registry = load(REGISTRY)
    entries = list(registry.get("campaign", [])) + list(registry.get("demo", []))
    if len(entries) != 45:
        fail(f"expected 45 campaign+demo dossiers, got {len(entries)}")
    seen_families: set[str] = set()
    multi_layer_cases = 0
    validated_layers = 0
    for entry in entries:
        path = ROOT / str(entry.get("path", "")).replace("res://", "")
        if not path.exists():
            fail(f"registry path missing: {path}")
        families, editable_layers = validate_dossier(load(path))
        seen_families |= families
        validated_layers += editable_layers
        if editable_layers == 2:
            multi_layer_cases += 1
    if seen_families != SIX:
        fail(f"focus sweep must cover exact six primitive families; got {sorted(seen_families)}")
    if multi_layer_cases == 0:
        fail("focus sweep did not exercise any two-editable-layer dossier")

    navigator = (ROOT / "src/presentation/authored_focus_navigator.gd").read_text(encoding="utf-8")
    for marker in (
        "focus_graph_by_layer",
        "required_focusable_candidate_ids",
        "neighbors_by_candidate_id",
        "cycle_layer",
        "cycle_linear",
        "focus_required_unreachable",
        "focus_edit_surface_ceiling_exceeded",
    ):
        if marker not in navigator:
            fail(f"navigator contract marker missing: {marker}")
    forbidden = ("global_position", "get_global_rect", "distance_to", "zoom", "scene")
    lowered = navigator.lower()
    for marker in forbidden:
        if marker in lowered:
            fail(f"navigator must not derive logical focus from presentation geometry/order: {marker}")

    print(
        "Phase 12E authored focus audit: PASS "
        f"(45 dossiers, {validated_layers} editable layers, six primitive families, authored stable-ID navigation)"
    )


if __name__ == "__main__":
    main()
