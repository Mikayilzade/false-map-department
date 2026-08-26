#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path

SHA40 = re.compile(r"^[0-9a-f]{40}$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")
ROLES = {"demo", "production"}
SCHEMA = "fmd.phase12g.build-artifact-binding.v1"


def fail(message: str) -> None:
    raise SystemExit(f"PHASE12G BUILD ARTIFACT FAIL: {message}")


def canonical_hash(payload: dict) -> str:
    encoded = json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def normalize_source_head(value: object) -> str:
    source = str(value).strip().lower()
    if not SHA40.fullmatch(source):
        raise ValueError("source_head must be an exact 40-character lowercase Git commit SHA")
    return source


def normalize_build_id(value: object) -> str:
    build_id = str(value).strip()
    if not build_id:
        raise ValueError("build_id must be non-empty")
    return build_id


def normalize_role(value: object) -> str:
    role = str(value).strip().lower()
    if role not in ROLES:
        raise ValueError(f"unsupported build role: {role}")
    return role


def digest_file(path: Path) -> tuple[str, int]:
    if not path.is_file():
        raise ValueError(f"build artifact is not a regular file: {path}")
    h = hashlib.sha256()
    size = 0
    with path.open("rb") as handle:
        while True:
            chunk = handle.read(1024 * 1024)
            if not chunk:
                break
            h.update(chunk)
            size += len(chunk)
    return h.hexdigest(), size


def make_record(*, source_head: object, role: object, build_id: object, artifact_path: Path) -> dict:
    source = normalize_source_head(source_head)
    normalized_role = normalize_role(role)
    normalized_build = normalize_build_id(build_id)
    digest, size = digest_file(artifact_path)
    payload = {
        "schema": SCHEMA,
        "source_head": source,
        "role": normalized_role,
        "build_id": normalized_build,
        "artifact_filename": artifact_path.name,
        "artifact_sha256": digest,
        "artifact_bytes": size,
        "evidence_boundary": "This record binds one build label/source/role to exact packaged artifact bytes. It is acquisition metadata, not empirical evidence.",
    }
    payload["binding_id"] = canonical_hash(payload)
    return payload


def load_record(path: Path) -> dict:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ValueError(f"unreadable build artifact record: {exc}") from exc
    if not isinstance(value, dict):
        raise ValueError("build artifact record must be a JSON object")
    return value


def verify_record(
    record: object,
    *,
    artifact_path: Path,
    source_head: object,
    build_id: object,
    role: object | None = None,
) -> dict:
    if not isinstance(record, dict):
        raise ValueError("build artifact record must be an object")
    if record.get("schema") != SCHEMA:
        raise ValueError("unsupported build artifact record schema")
    source = normalize_source_head(source_head)
    build = normalize_build_id(build_id)
    if str(record.get("source_head", "")) != source:
        raise ValueError("build artifact source_head mismatch")
    if str(record.get("build_id", "")) != build:
        raise ValueError("build artifact build_id mismatch")
    record_role = normalize_role(record.get("role", ""))
    if role is not None and record_role != normalize_role(role):
        raise ValueError("build artifact role mismatch")
    digest = str(record.get("artifact_sha256", ""))
    if not SHA256.fullmatch(digest):
        raise ValueError("build artifact record has invalid SHA-256")
    size = record.get("artifact_bytes")
    if isinstance(size, bool) or not isinstance(size, int) or size < 0:
        raise ValueError("build artifact record has invalid byte size")
    actual_digest, actual_size = digest_file(artifact_path)
    if actual_digest != digest or actual_size != size:
        raise ValueError("packaged build artifact bytes do not match recorded digest/size")
    claimed_binding = str(record.get("binding_id", ""))
    unhashed = dict(record)
    unhashed.pop("binding_id", None)
    actual_binding = canonical_hash(unhashed)
    if claimed_binding != actual_binding:
        raise ValueError("build artifact binding_id mismatch")
    if artifact_path.name != str(record.get("artifact_filename", "")):
        raise ValueError("build artifact filename mismatch")
    return dict(record)


def main() -> None:
    parser = argparse.ArgumentParser(description="Create or verify exact packaged-build byte bindings for Phase 12G acquisition.")
    sub = parser.add_subparsers(dest="command", required=True)

    create = sub.add_parser("create")
    create.add_argument("--source-head", required=True)
    create.add_argument("--role", choices=sorted(ROLES), required=True)
    create.add_argument("--build-id", required=True)
    create.add_argument("--artifact", type=Path, required=True)
    create.add_argument("--output", type=Path, required=True)

    verify = sub.add_parser("verify")
    verify.add_argument("--record", type=Path, required=True)
    verify.add_argument("--source-head", required=True)
    verify.add_argument("--role", choices=sorted(ROLES), required=True)
    verify.add_argument("--build-id", required=True)
    verify.add_argument("--artifact", type=Path, required=True)

    args = parser.parse_args()
    try:
        if args.command == "create":
            if args.output.exists():
                fail("refusing to overwrite existing build artifact record")
            payload = make_record(
                source_head=args.source_head,
                role=args.role,
                build_id=args.build_id,
                artifact_path=args.artifact.resolve(),
            )
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
            print(json.dumps({
                "status": "CREATED",
                "binding_id": payload["binding_id"],
                "artifact_sha256": payload["artifact_sha256"],
                "artifact_bytes": payload["artifact_bytes"],
                "evidence_appended": False,
            }, sort_keys=True))
            return
        payload = verify_record(
            load_record(args.record),
            artifact_path=args.artifact.resolve(),
            source_head=args.source_head,
            build_id=args.build_id,
            role=args.role,
        )
        print(json.dumps({
            "status": "VERIFIED",
            "binding_id": payload["binding_id"],
            "artifact_sha256": payload["artifact_sha256"],
            "artifact_bytes": payload["artifact_bytes"],
            "evidence_appended": False,
            "gate_disposition_inferred": False,
        }, sort_keys=True))
    except ValueError as exc:
        fail(str(exc))


if __name__ == "__main__":
    main()
