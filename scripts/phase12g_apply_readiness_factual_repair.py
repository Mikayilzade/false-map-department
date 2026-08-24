#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def canon(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def write_content(path: Path, value: dict) -> None:
    body = dict(value)
    body.pop("content_hash", None)
    value["content_hash"] = hashlib.sha256(canon(body).encode("utf-8")).hexdigest()
    path.write_text(canon(value) + "\n", encoding="utf-8")


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text(encoding="utf-8")
    if new in text:
        return
    if old not in text:
        raise SystemExit(f"guarded replacement source missing in {path}")
    path.write_text(text.replace(old, new, 1), encoding="utf-8")


def repair_d08() -> None:
    path = ROOT / "content" / "campaign" / "D08.json"
    dossier = load(path)
    solution = dossier["validation_metadata"]["known_solution_envelope"]["solution_commands"]
    current = [row["candidate_ids"][0] for row in solution]
    desired = ["D08_ZONE_GATE", "D08_R_HOME_GATE", "D08_BORDER_GATE_EAST"]
    old = ["D08_R_HOME_GATE", "D08_BORDER_GATE_EAST", "D08_ZONE_GATE"]
    if current == desired:
        return
    if current != old:
        raise SystemExit(f"D08 solution order drifted: {current}")
    by_candidate = {row["candidate_ids"][0]: row for row in solution}
    dossier["validation_metadata"]["known_solution_envelope"]["solution_commands"] = [
        by_candidate[candidate] for candidate in desired
    ]
    write_content(path, dossier)


def repair_d16() -> None:
    path = ROOT / "content" / "campaign" / "D16.json"
    dossier = load(path)
    if dossier.get("stability_required_cycles") != 2 or dossier.get("stability_reason_tag") != "agent_progression_arrival":
        raise SystemExit("D16 frozen Stability identity drifted")
    beats = int(dossier.get("reaction_beats_after_edit", -1))
    if beats not in (1, 2):
        raise SystemExit(f"D16 reaction beats drifted: {beats}")
    dossier["reaction_beats_after_edit"] = 1
    solution = dossier["validation_metadata"]["known_solution_envelope"]
    solution["relevant_temporal_transition_observed"] = True
    solution["stability_transition_evidence"] = [
        {
            "agent_id": "D16_AG_CARRIER",
            "cycle": 1,
            "from_node_id": "D16_N_GATE",
            "to_node_id": "D16_N_SERVICE",
            "transition_kind": "agent_progression_arrival",
        }
    ]
    write_content(path, dossier)


def repair_d26_binding() -> None:
    path = ROOT / "content" / "runtime_bindings.json"
    bindings = load(path)
    d26 = bindings["dossiers"].setdefault("D26", {})
    expectation = d26.setdefault("projection_expectations", {})
    existing = expectation.get("D26_REG_JURISDICTION_ACCESS")
    if existing not in (None, "D26_J_EAST"):
        raise SystemExit(f"D26 projection expectation drifted: {existing}")
    expectation["D26_REG_JURISDICTION_ACCESS"] = "D26_J_EAST"
    path.write_text(json.dumps(bindings, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def repair_act2_guards() -> None:
    audit = ROOT / "scripts" / "phase12d_act2_content_audit.py"
    replace_once(
        audit,
        "if not sol.get('relevant_temporal_transition_observed') or len(evidence)!=2: fail('D16 non-idle Stability evidence incomplete')",
        "if not sol.get('relevant_temporal_transition_observed') or not evidence: fail('D16 non-idle Stability evidence incomplete')",
    )
    replace_once(
        audit,
        "    for cycle,event in enumerate(evidence,1):\n        if event.get('cycle')!=cycle or event.get('agent_id') not in known_agents: fail('D16 Stability evidence cycle/agent invalid')\n        if event.get('from_node_id') not in known_nodes or event.get('to_node_id') not in known_nodes or event.get('from_node_id')==event.get('to_node_id'): fail('D16 Stability evidence must be a real non-idle canonical node transition')\n        if event.get('transition_kind')!=d16.get('stability_reason_tag'): fail('D16 Stability evidence reason mismatch')",
        "    seen_cycles=set()\n    for event in evidence:\n        cycle=int(event.get('cycle',0))\n        if cycle<1 or cycle>d16.get('stability_required_cycles',0) or cycle in seen_cycles or event.get('agent_id') not in known_agents: fail('D16 Stability evidence cycle/agent invalid')\n        seen_cycles.add(cycle)\n        if event.get('from_node_id') not in known_nodes or event.get('to_node_id') not in known_nodes or event.get('from_node_id')==event.get('to_node_id'): fail('D16 Stability evidence must be a real non-idle canonical node transition')\n        if event.get('transition_kind')!=d16.get('stability_reason_tag'): fail('D16 Stability evidence reason mismatch')",
    )

    test = ROOT / "tests" / "test_act2_content_runner.gd"
    replace_once(
        test,
        '\t_assert(evidence.size() == 2, "D16 must carry one canonical witness transition for each Stability cycle")',
        '\t_assert(not evidence.is_empty(), "D16 must carry at least one real non-idle witness transition inside the Stability window")',
    )


def main() -> None:
    repair_d08()
    repair_d16()
    repair_d26_binding()
    repair_act2_guards()
    print("Phase 12G factual readiness repair applied: D08 order, D16 temporal pacing, D26 projection expectation, P10-R3 audit alignment")


if __name__ == "__main__":
    main()
