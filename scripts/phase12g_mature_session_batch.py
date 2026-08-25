#!/usr/bin/env python3
from __future__ import annotations

import argparse
import itertools
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROTOCOLS = ROOT / "empirical/phase12g_session_protocols.json"
REGISTRY = ROOT / "empirical/phase12g_gate_registry.json"
CAMPAIGN = ROOT / "content/campaign"
REMIX = ROOT / "content/remix"
DEFAULT_ROOT = ROOT / ".phase12g-mature-sessions"
BATCH_VERSION = 2
MATURE_GATES = ("E3", "E4", "E5", "E6", "E9", "E10")


def fail(message: str) -> None:
    raise SystemExit(message)


def load_json(path: Path) -> dict:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        fail(f"{path}: expected JSON object")
    return payload


def write_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def write_jsonl(path: Path, rows: list[dict]) -> None:
    path.write_text("".join(json.dumps(row, sort_keys=True) + "\n" for row in rows), encoding="utf-8")


def resolve_manifest_path(manifest_path: Path, value: object) -> Path:
    raw = Path(str(value))
    candidate = raw if raw.is_absolute() else manifest_path.parent / raw
    return candidate.resolve()


def campaign_definition(dossier_id: str) -> dict:
    return load_json(CAMPAIGN / f"{dossier_id}.json")


def all_campaign() -> list[dict]:
    return [load_json(path) for path in sorted(CAMPAIGN.glob("D[0-9][0-9].json"))]


def linked_dossiers() -> list[str]:
    result: list[str] = []
    for definition in all_campaign():
        if len(definition.get("map_layers", [])) >= 3:
            result.append(str(definition["dossier_id"]))
    return result


def taught_archetypes() -> list[str]:
    found: set[str] = set()
    for definition in all_campaign():
        for agent in definition.get("agents", []):
            if isinstance(agent, dict):
                archetype = str(agent.get("archetype_id", ""))
                if archetype:
                    found.add(archetype)
    return sorted(found)


def remix_pairs() -> list[tuple[str, str]]:
    result: list[tuple[str, str]] = []
    for path in sorted(REMIX.glob("REMIX[0-9][0-9].json")):
        definition = load_json(path)
        result.append((str(definition["dossier_id"]), str(definition["source_substrate_id"])))
    return result


def e10_pairs(archetypes: list[str]) -> list[tuple[str, str]]:
    if len(archetypes) < 2:
        fail("E10 requires at least two taught archetypes")
    return [(archetypes[index], archetypes[(index + 1) % len(archetypes)]) for index in range(len(archetypes))]


def blank_rows(tester_id: str, ordinal: int) -> dict[str, list[dict]]:
    protocols = load_json(PROTOCOLS)["protocols"]
    rows: dict[str, list[dict]] = {gate: [] for gate in MATURE_GATES}

    methods = list(protocols["E3"]["methods"])
    dossiers = list(protocols["E3"]["representative_dossiers"])
    for dossier_index, dossier_id in enumerate(dossiers):
        ordered = methods if (ordinal + dossier_index) % 2 == 0 else list(reversed(methods))
        for order_index, method in enumerate(ordered):
            rows["E3"].append({
                "gate_id": "E3",
                "tester_id": tester_id,
                "dossier_id": dossier_id,
                "method": method,
                "completion_seconds": None,
                "completed": None,
                "rule_knowledge_confirmed": None,
                "counterbalance_order": order_index + 1,
            })

    for window_id, dossier_ids in protocols["E4"]["windows"].items():
        rows["E4"].append({
            "gate_id": "E4",
            "tester_id": tester_id,
            "window_id": window_id,
            "dossier_ids": list(dossier_ids),
            "same_trick_assessment": None,
            "notes": None,
        })

    for dossier_id in linked_dossiers():
        rows["E5"].append({
            "gate_id": "E5",
            "tester_id": tester_id,
            "dossier_id": dossier_id,
            "requirement_id": None,
            "identified_authority_layer": None,
            "correct": None,
            "tutorial_recall_used": None,
        })

    for dossier_id in protocols["E6"]["representative_dossiers"]:
        rows["E6"].append({
            "gate_id": "E6",
            "tester_id": tester_id,
            "dossier_id": dossier_id,
            "requirement_id": None,
            "answered_cause": None,
            "used_raw_debug_log": None,
            "correct": None,
        })

    for remix_id, source_id in remix_pairs():
        rows["E9"].append({
            "gate_id": "E9",
            "tester_id": tester_id,
            "remix_id": remix_id,
            "source_dossier_id": source_id,
            "described_as_changed_causal_problem": None,
            "notes": None,
        })

    archetypes = taught_archetypes()
    for pair_index, (agent_a, agent_b) in enumerate(e10_pairs(archetypes), start=1):
        rows["E10"].append({
            "gate_id": "E10",
            "tester_id": tester_id,
            "agent_a": agent_a,
            "agent_b": agent_b,
            "scenario_id": f"E10_PAIR_{pair_index:02d}",
            "predicted_distinction": None,
            "correct": None,
        })
    return rows


def required_fields() -> dict[str, list[str]]:
    registry = load_json(REGISTRY)
    return {
        str(gate["gate_id"]): list(gate.get("required_fields", []))
        for gate in registry["gates"]
        if gate["gate_id"] in MATURE_GATES
    }


def missing_fields(row: dict, required: list[str]) -> list[str]:
    missing: list[str] = []
    for field in required:
        if field not in row:
            missing.append(field)
            continue
        value = row[field]
        if value is None or (isinstance(value, str) and not value.strip()) or (isinstance(value, list) and not value):
            missing.append(field)
    return missing


def packet_status(packet_dir: Path) -> dict:
    packet_path = packet_dir / "observer-packet.json"
    if not packet_path.exists():
        return {"status": "MISSING_PACKET", "ready_to_finalize": False}
    packet = load_json(packet_path)
    requirements = required_fields()
    total_rows = 0
    complete_rows = 0
    by_gate: dict[str, dict] = {}
    for gate_id in MATURE_GATES:
        gate_rows = packet.get("rows_by_gate", {}).get(gate_id, [])
        if not isinstance(gate_rows, list):
            fail(f"{packet_path}: {gate_id} rows must be an array")
        gate_complete = 0
        for row in gate_rows:
            if not isinstance(row, dict):
                fail(f"{packet_path}: {gate_id} row must be an object")
            total_rows += 1
            if not missing_fields(row, requirements[gate_id]):
                gate_complete += 1
                complete_rows += 1
        by_gate[gate_id] = {"rows": len(gate_rows), "complete_rows": gate_complete}
    finalized = all((packet_dir / f"completed-{gate_id}.jsonl").exists() for gate_id in MATURE_GATES)
    ready = total_rows > 0 and complete_rows == total_rows and not finalized
    if finalized:
        status = "FINALIZED_LOCAL"
    elif ready:
        status = "READY_TO_FINALIZE"
    elif complete_rows > 0:
        status = "PARTIALLY_OBSERVED"
    else:
        status = "PREPARED"
    return {
        "status": status,
        "ready_to_finalize": ready,
        "finalized": finalized,
        "total_rows": total_rows,
        "complete_rows": complete_rows,
        "rows_by_gate": by_gate,
        "human_outcomes_inferred": False,
        "repository_evidence_appended": False,
    }


def cmd_prepare(args: argparse.Namespace) -> None:
    if args.count < 1:
        fail("--count must be >= 1")
    output_root = Path(args.output_dir).resolve()
    output_root.mkdir(parents=True, exist_ok=True)
    packets: list[dict] = []
    width = max(3, len(str(args.start + args.count - 1)))
    for offset in range(args.count):
        ordinal = args.start + offset
        tester_id = f"{args.tester_prefix}{ordinal:0{width}d}"
        if any(ch.isspace() for ch in tester_id):
            fail("tester ID must not contain whitespace")
        packet_dir = output_root / tester_id
        packet = {
            "batch_version": BATCH_VERSION,
            "purpose": "E3_E4_E5_E6_E9_E10_real_mature_human_acquisition",
            "tester_id": tester_id,
            "build_id": args.build_id,
            "rules_known_before_session": None,
            "rows_by_gate": blank_rows(tester_id, ordinal),
            "templates_are_not_evidence": True,
            "human_outcomes_inferred": False,
            "repository_evidence_appended": False,
        }
        write_json(packet_dir / "observer-packet.json", packet)
        packets.append({
            "tester_id": tester_id,
            "packet_dir": tester_id,
            "observer_packet": f"{tester_id}/observer-packet.json",
            "finalize_command": f"python3 scripts/phase12g_mature_session_batch.py finalize --packet-dir <BATCH_DIR>/{tester_id}",
        })
    manifest = {
        "batch_version": BATCH_VERSION,
        "build_id": args.build_id,
        "path_contract": "packet_paths_relative_to_batch_manifest",
        "packet_count": len(packets),
        "packets": packets,
        "human_outcomes_required": True,
        "templates_are_not_evidence": True,
        "repository_evidence_appended": False,
    }
    write_json(output_root / args.manifest_name, manifest)
    print(f"Prepared {len(packets)} mature-session packets at {output_root}")
    print("No human outcome was inferred and no repository evidence was appended.")


def cmd_status(args: argparse.Namespace) -> None:
    manifest_path = Path(args.manifest).resolve()
    manifest = load_json(manifest_path)
    rows: list[dict] = []
    for packet in manifest.get("packets", []):
        packet_dir = resolve_manifest_path(manifest_path, packet["packet_dir"])
        status = packet_status(packet_dir)
        status["tester_id"] = str(packet.get("tester_id", ""))
        status["packet_dir"] = str(packet_dir)
        rows.append(status)
    counts: dict[str, int] = {}
    for row in rows:
        counts[row["status"]] = counts.get(row["status"], 0) + 1
    print(json.dumps({
        "batch_version": int(manifest.get("batch_version", 0)),
        "packet_count": len(rows),
        "counts": counts,
        "packets": rows,
        "human_outcomes_inferred": False,
        "repository_evidence_appended": False,
    }, indent=2, sort_keys=True))


def cmd_finalize(args: argparse.Namespace) -> None:
    packet_dir = Path(args.packet_dir).resolve()
    packet = load_json(packet_dir / "observer-packet.json")
    if packet.get("rules_known_before_session") is not True:
        fail("rules_known_before_session must be explicitly true before mature-human rows can be finalized")
    requirements = required_fields()
    for gate_id in MATURE_GATES:
        rows = packet.get("rows_by_gate", {}).get(gate_id, [])
        if not isinstance(rows, list) or not rows:
            fail(f"{gate_id}: packet has no rows")
        for index, row in enumerate(rows, start=1):
            missing = missing_fields(row, requirements[gate_id])
            if missing:
                fail(f"{gate_id} row {index}: missing observed fields: {', '.join(missing)}")
            if gate_id == "E6" and row.get("used_raw_debug_log") is not False:
                fail("E6 rows require used_raw_debug_log=false; raw debug logs are forbidden by the protocol")
        write_jsonl(packet_dir / f"completed-{gate_id}.jsonl", rows)
    print(f"Finalized mature-session rows locally at {packet_dir}")
    print("Rows were not appended to repository evidence; validate and append deliberately with phase12g_collect_completed_rows.py.")


def main() -> None:
    parser = argparse.ArgumentParser(description="Prepare/finalize real mature-human Phase 12G packets without fabricating empirical outcomes.")
    sub = parser.add_subparsers(dest="command", required=True)

    prepare = sub.add_parser("prepare")
    prepare.add_argument("--count", type=int, required=True)
    prepare.add_argument("--start", type=int, default=1)
    prepare.add_argument("--tester-prefix", default="MATURE-T")
    prepare.add_argument("--build-id", default="phase12g-production-build")
    prepare.add_argument("--output-dir", default=str(DEFAULT_ROOT))
    prepare.add_argument("--manifest-name", default="batch-manifest.json")
    prepare.set_defaults(func=cmd_prepare)

    status = sub.add_parser("status")
    status.add_argument("--manifest", required=True)
    status.set_defaults(func=cmd_status)

    finalize = sub.add_parser("finalize")
    finalize.add_argument("--packet-dir", required=True)
    finalize.set_defaults(func=cmd_finalize)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
