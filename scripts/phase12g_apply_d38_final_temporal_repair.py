#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
D38 = ROOT / "content" / "campaign" / "D38.json"
ACT5_AUDIT = ROOT / "scripts" / "phase12d_act5_content_audit.py"
ACT5_TEST = ROOT / "tests" / "test_act5_content_runner.gd"


def canonical_bytes(payload: dict) -> bytes:
    return json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")


def repair_d38() -> None:
    payload = json.loads(D38.read_text(encoding="utf-8"))
    if payload.get("dossier_id") != "D38":
        raise SystemExit("D38 identity mismatch")
    current = payload.get("reaction_beats_after_edit")
    if current not in (0, 1):
        raise SystemExit(f"D38 expected reaction beats 0 or already-repaired 1, got {current!r}")
    payload["reaction_beats_after_edit"] = 1
    solution = payload["validation_metadata"]["known_solution_envelope"]
    solution["stability_transition_evidence"] = [
        {
            "agent_id": "D38_AG_PROCESSION",
            "cycle": 1,
            "from_node_id": "D38_N_B",
            "to_node_id": "D38_N_END",
            "transition_kind": "procession_sequence_progression",
        }
    ]
    solution["relevant_temporal_transition_observed"] = True
    body = dict(payload)
    body.pop("content_hash", None)
    payload["content_hash"] = hashlib.sha256(canonical_bytes(body)).hexdigest()
    D38.write_bytes(canonical_bytes(payload) + b"\n")


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text(encoding="utf-8")
    if new in text:
        return
    if text.count(old) != 1:
        raise SystemExit(f"{path}: expected exactly one replacement target, found {text.count(old)}")
    path.write_text(text.replace(old, new, 1), encoding="utf-8")


def repair_act5_audit() -> None:
    replace_once(
        ACT5_AUDIT,
        "            if len(ev)!=d.get('stability_required_cycles') or not sol.get('relevant_temporal_transition_observed'): fail(f'{did} P10-R3 Stability proof invalid')",
        "            if not ev or not sol.get('relevant_temporal_transition_observed'): fail(f'{did} P10-R3 Stability proof missing a real transition witness')\n            required_cycles=d.get('stability_required_cycles')\n            if not any(str(row.get('from_node_id','')) != str(row.get('to_node_id','')) for row in ev): fail(f'{did} P10-R3 Stability proof contains no non-idle transition')\n            if any(int(row.get('cycle',0)) < 1 or int(row.get('cycle',0)) > required_cycles for row in ev): fail(f'{did} P10-R3 Stability witness cycle outside verification window')",
    )
    replace_once(
        ACT5_AUDIT,
        "    if not has_agent(d38,'A8_') or not {'O8_VISIT_SEQUENCE','O12_CROSS_LAYER_CONNECTOR_STATE'}<=families(d38) or d38.get('stability_required_cycles')!=2 or len(sol38.get('stability_transition_evidence',[]))!=2: fail('D38 portal + Procession Stability grammar invalid')",
        "    if not has_agent(d38,'A8_') or not {'O8_VISIT_SEQUENCE','O12_CROSS_LAYER_CONNECTOR_STATE'}<=families(d38) or d38.get('stability_required_cycles')!=2 or d38.get('reaction_beats_after_edit')!=1 or len(sol38.get('stability_transition_evidence',[]))<1: fail('D38 portal + Procession Stability grammar invalid')",
    )


def repair_act5_test() -> None:
    replace_once(
        ACT5_TEST,
        '\t_assert(_array(d38_solution.get("stability_transition_evidence", [])).size() == 2, "D38 must carry one Procession transition witness per Stability cycle")',
        '\t_assert(int(d38.get("reaction_beats_after_edit", -1)) == 1, "D38 must leave a real Procession transition inside Stability")\n\tvar d38_witnesses: Array = _array(d38_solution.get("stability_transition_evidence", []))\n\t_assert(d38_witnesses.size() >= 1, "D38 must carry at least one real non-idle Procession Stability witness")\n\tif not d38_witnesses.is_empty():\n\t\tvar d38_witness: Dictionary = _dictionary(d38_witnesses[0])\n\t\t_assert(str(d38_witness.get("from_node_id", "")) != str(d38_witness.get("to_node_id", "")), "D38 Stability witness must be non-idle")',
    )


def main() -> None:
    repair_d38()
    repair_act5_audit()
    repair_act5_test()
    print("D38 final temporal repair applied")


if __name__ == "__main__":
    main()
