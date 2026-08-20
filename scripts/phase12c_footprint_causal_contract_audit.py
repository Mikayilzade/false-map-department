#!/usr/bin/env python3
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DIRECT_VARIANT_GET_INFERENCE = re.compile(
    r'^\s*var\s+\w+\s*:=\s*[A-Za-z_]\w*(?:\[[^\]]+\])?\.get\(',
    re.MULTILINE,
)
DIRECT_JSON_PARSE_INFERENCE = re.compile(
    r'^\s*var\s+\w+\s*:=\s*JSON\.parse_string\(',
    re.MULTILINE,
)

def fail(message: str) -> None:
    raise SystemExit(f"PHASE12C FOOTPRINT/CAUSAL FAIL: {message}")

def main() -> None:
    footprint_path = ROOT / "src/domain/intervention_footprint_engine.gd"
    causal_path = ROOT / "src/domain/causal_explanation_engine.gd"
    session_path = ROOT / "src/application/canonical_session_service.gd"
    codec_path = ROOT / "src/application/core_state_codec.gd"
    test_path = ROOT / "tests/test_footprint_causal_runner.gd"
    runtime_path = ROOT / "scripts/run_phase12a_runtime.sh"

    files = [footprint_path, causal_path, session_path, codec_path, test_path, runtime_path]
    for path in files:
        if not path.exists():
            fail(f"missing footprint/causal artifact: {path.relative_to(ROOT)}")

    footprint = footprint_path.read_text(encoding="utf-8")
    causal = causal_path.read_text(encoding="utf-8")
    session = session_path.read_text(encoding="utf-8")
    codec = codec_path.read_text(encoding="utf-8")
    test = test_path.read_text(encoding="utf-8")
    runtime = runtime_path.read_text(encoding="utf-8")

    for marker in [
        "intervention_reference_map_state_by_layer",
        "changed_fact_keys",
        "changed_primitive_count",
        "changed_count_by_family",
        "added_fact_keys",
        "removed_fact_keys",
        "restricted_zone",
    ]:
        if marker not in footprint:
            fail(f"footprint engine missing canonical marker: {marker}")

    for marker in [
        "MAX_VISIBLE_NODES := 5",
        "MAX_VISIBLE_SIBLINGS := 2",
        "requirement_relevance_tags",
        "full_chain_event_ids",
        "collapsed_event_ids",
        "visible_sibling_event_ids",
        "hidden_sibling_count",
        "canonical_parent_ids_by_event_id",
        "causal_parent_missing_or_reordered",
    ]:
        if marker not in causal:
            fail(f"causal explanation engine missing P10-R6 marker: {marker}")

    for marker in [
        "intervention_footprint_state",
        "intervention_footprint_delta",
        "causal_graph_current",
        "requirement_explanations_by_tag",
        "restore_checkpoint",
        "execute_stability",
    ]:
        if marker not in session:
            fail(f"canonical session service missing marker: {marker}")

    for marker in ["intervention_footprint_state", "causal_graph_current", "decode_checkpoint"]:
        if marker not in codec:
            fail(f"core state persistence codec missing extended checkpoint marker: {marker}")

    for marker in [
        "Final footprint must return to zero after restoring the authored reference",
        "Clean Intervention must never score raw edit history",
        "Derived consequences must not appear as player intervention footprint",
        "Undo + replay must reproduce exact post-state hash",
        "Persistence round-trip must preserve extended canonical session hash",
        "P10-R6 default explanation must expose at most five material nodes",
        "Compaction must preserve the complete canonical parent map instead of fabricating shortcut parentage",
    ]:
        if marker not in test:
            fail(f"headless footprint/causal acceptance missing: {marker}")

    if "phase12c-footprint-causal-contract" not in runtime:
        fail("runtime wrapper must execute footprint/causal contract audit")
    if "test_footprint_causal_runner.gd" not in runtime:
        fail("runtime wrapper must execute footprint/causal headless suite")

    for path, source in [
        (footprint_path, footprint),
        (causal_path, causal),
        (session_path, session),
        (codec_path, codec),
        (test_path, test),
    ]:
        match = DIRECT_VARIANT_GET_INFERENCE.search(source)
        if match:
            line = source.count("\n", 0, match.start()) + 1
            fail(f"direct Variant inference from Dictionary.get in {path.relative_to(ROOT)}:{line}")
        match = DIRECT_JSON_PARSE_INFERENCE.search(source)
        if match:
            line = source.count("\n", 0, match.start()) + 1
            fail(f"direct Variant inference from JSON.parse_string in {path.relative_to(ROOT)}:{line}")

    print("Phase 12C footprint/causal audit: PASS (final footprint + canonical DAG + P10-R6 projection)")

if __name__ == "__main__":
    main()
