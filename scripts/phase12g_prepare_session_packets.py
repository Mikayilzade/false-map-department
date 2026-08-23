#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import itertools
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROTOCOLS = ROOT / "empirical" / "phase12g_session_protocols.json"
REGISTRY = ROOT / "empirical" / "phase12g_gate_registry.json"


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def campaign_ids() -> list[str]:
    return [f"D{i:02d}" for i in range(1, 41)]


def demo_ids() -> list[str]:
    return [f"DEMO{i:02d}" for i in range(1, 6)]


def remix_ids() -> list[str]:
    return [f"REMIX{i:02d}" for i in range(1, 13)]


def campaign_definition(dossier_id: str) -> dict:
    return load_json(ROOT / "content" / "campaign" / f"{dossier_id}.json")


def blank_row(gate_id: str, required_fields: list[str], preset: dict | None = None) -> dict:
    row = {"gate_id": gate_id}
    for field in required_fields:
        row[field] = None
    if preset:
        row.update(preset)
    return row


def write_json(path: Path, payload: object) -> None:
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def write_jsonl(path: Path, rows: list[dict]) -> None:
    path.write_text("".join(json.dumps(row, sort_keys=True) + "\n" for row in rows), encoding="utf-8")


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", default=str(ROOT / ".phase12g-session-packets"))
    args = parser.parse_args()
    out = Path(args.output)
    out.mkdir(parents=True, exist_ok=True)

    protocols = load_json(PROTOCOLS)["protocols"]
    registry = load_json(REGISTRY)
    by_gate = {row["gate_id"]: row for row in registry["gates"]}

    # E3: counterbalanced comparative rows for representative mature dossiers.
    e3_rows: list[dict] = []
    for dossier_id in protocols["E3"]["representative_dossiers"]:
        for method in protocols["E3"]["methods"]:
            e3_rows.append(blank_row("E3", by_gate["E3"]["required_fields"], {
                "dossier_id": dossier_id,
                "method": method,
            }))
    write_jsonl(out / "E3_session_template.jsonl", e3_rows)

    # E4: one blank assessment row per frozen campaign window.
    e4_rows = [
        blank_row("E4", by_gate["E4"]["required_fields"], {
            "window_id": window_id,
            "dossier_ids": dossier_ids,
        })
        for window_id, dossier_ids in protocols["E4"]["windows"].items()
    ]
    write_jsonl(out / "E4_window_template.jsonl", e4_rows)

    # E5: discover every production campaign dossier with 3-4 map layers.
    e5_rows: list[dict] = []
    linked_dossiers: list[str] = []
    for dossier_id in campaign_ids():
        definition = campaign_definition(dossier_id)
        layer_count = len(definition.get("map_layers", []))
        if layer_count >= 3:
            linked_dossiers.append(dossier_id)
            e5_rows.append(blank_row("E5", by_gate["E5"]["required_fields"], {
                "dossier_id": dossier_id,
            }))
    write_jsonl(out / "E5_linked_authority_template.jsonl", e5_rows)

    # E6: late-game causal-readability rows.
    e6_rows = [
        blank_row("E6", by_gate["E6"]["required_fields"], {"dossier_id": dossier_id})
        for dossier_id in protocols["E6"]["representative_dossiers"]
    ]
    write_jsonl(out / "E6_causal_readability_template.jsonl", e6_rows)

    # E7: every shippable content ID x every required capture scenario.
    shippable_ids = campaign_ids() + demo_ids() + remix_ids()
    e7_rows: list[dict] = []
    for dossier_id in shippable_ids:
        for scenario in protocols["E7"]["capture_scenarios"]:
            e7_rows.append(blank_row("E7", by_gate["E7"]["required_fields"], {
                "dossier_id": dossier_id,
                "device_mode": scenario["device_mode"],
                "ui_scale": scenario["ui_scale"],
                "reduced_motion": scenario["reduced_motion"],
                "non_color": scenario["non_color"],
                "no_audio": scenario["no_audio"],
                "scenario_id": scenario["scenario_id"],
            }))
    write_jsonl(out / "E7_capture_matrix.jsonl", e7_rows)

    # E9: all remix/source pairs from production overlay metadata.
    e9_rows: list[dict] = []
    remix_pairs: dict[str, str] = {}
    for remix_id in remix_ids():
        overlay = load_json(ROOT / "content" / "remix" / f"{remix_id}.json")
        source_id = str(overlay.get("source_substrate_id", ""))
        remix_pairs[remix_id] = source_id
        e9_rows.append(blank_row("E9", by_gate["E9"]["required_fields"], {
            "remix_id": remix_id,
            "source_dossier_id": source_id,
        }))
    write_jsonl(out / "E9_remix_template.jsonl", e9_rows)

    # E10: discover all taught production archetypes and create every distinct pair.
    archetypes: set[str] = set()
    for dossier_id in campaign_ids():
        definition = campaign_definition(dossier_id)
        for agent in definition.get("agents", []):
            archetype = str(agent.get("archetype_id", ""))
            if archetype:
                archetypes.add(archetype)
    sorted_archetypes = sorted(archetypes)
    e10_rows: list[dict] = []
    for agent_a, agent_b in itertools.combinations(sorted_archetypes, 2):
        e10_rows.append(blank_row("E10", by_gate["E10"]["required_fields"], {
            "agent_a": agent_a,
            "agent_b": agent_b,
            "scenario_id": f"PAIR_{agent_a}__{agent_b}",
        }))
    write_jsonl(out / "E10_agent_pair_template.jsonl", e10_rows)

    files = sorted(out.glob("*.jsonl"))
    manifest = {
        "packet_version": 1,
        "templates_are_evidence": False,
        "copy_only_completed_rows_to": "empirical/evidence/<GATE_ID>.jsonl",
        "counts": {
            "E3_rows": len(e3_rows),
            "E4_rows": len(e4_rows),
            "E5_rows": len(e5_rows),
            "E6_rows": len(e6_rows),
            "E7_shippable_ids": len(shippable_ids),
            "E7_scenarios": len(protocols["E7"]["capture_scenarios"]),
            "E7_rows": len(e7_rows),
            "E9_rows": len(e9_rows),
            "E10_archetypes": len(sorted_archetypes),
            "E10_pairs": len(e10_rows),
        },
        "linked_dossiers": linked_dossiers,
        "agent_archetypes": sorted_archetypes,
        "remix_source_pairs": remix_pairs,
        "files": {path.name: sha256(path) for path in files},
    }
    write_json(out / "manifest.json", manifest)
    print(json.dumps(manifest, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
