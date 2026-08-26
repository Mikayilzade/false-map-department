#!/usr/bin/env python3
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))

import phase12g_build_identity as identity  # noqa: E402
import phase12g_build_identity_contract as contract  # noqa: E402


def fail(message: str) -> None:
    raise SystemExit(f"PHASE12G BUILD IDENTITY AUDIT FAIL: {message}")


def write(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def expect_failure(fn, label: str) -> None:
    try:
        fn()
    except SystemExit:
        return
    fail(f"expected rejection: {label}")


def main() -> None:
    head = subprocess.check_output(["git", "rev-parse", "--verify", "HEAD"], cwd=ROOT, text=True).strip().lower()
    head = identity.normalize_source_head(head)
    manifest = contract.create_manifest(head, "demo-build-alpha", "production-build-alpha")
    contract.verify_manifest(manifest)
    if manifest["demo"]["binding_id"] == manifest["production"]["binding_id"]:
        fail("demo and production bindings must differ")
    if identity.binding_id(head, "production", "production-build-alpha") != manifest["production"]["binding_id"]:
        fail("production binding must be deterministic")

    with tempfile.TemporaryDirectory(prefix="fmd-phase12g-build-id-") as raw:
        root = Path(raw)
        human = root / "human"
        write(human / "field-kit-manifest.json", {
            "source_head": head,
            "demo_build_id": "demo-build-alpha",
            "production_build_id": "production-build-alpha",
        })
        if contract.verify_human(manifest, human)["bindings_verified"] != 2:
            fail("human kit must verify both build roles")

        e8 = root / "e8"
        write(e8 / "asset-set.json", {"source_head": head, "build_id": "production-build-alpha"})
        write(e8 / "respondents.json", {"source_head": head, "build_id": "production-build-alpha"})
        if contract.verify_e8(manifest, e8)["bindings_verified"] != 2:
            fail("E8 packet must verify both source/build carriers")

        t8 = root / "t8.json"
        write(t8, {"source_head": head, "profile_row": {"build_id": "production-build-alpha"}})
        if contract.verify_t8(manifest, t8)["bindings_verified"] != 1:
            fail("T8-44 profile must verify production build binding")

        wrong_head = "0" * 40 if head != "0" * 40 else "1" * 40
        write(root / "bad-t8.json", {"source_head": wrong_head, "profile_row": {"build_id": "production-build-alpha"}})
        expect_failure(lambda: contract.verify_t8(manifest, root / "bad-t8.json"), "cross-tree T8 profile")

        write(e8 / "respondents.json", {"source_head": head, "build_id": "production-build-other"})
        expect_failure(lambda: contract.verify_e8(manifest, e8), "E8 build-id drift")

        tampered = json.loads(json.dumps(manifest))
        tampered["production"]["build_id"] = "production-build-other"
        expect_failure(lambda: contract.verify_manifest(tampered), "identity record tamper")

    print("Phase 12G build/source identity audit: PASS (exact checkout binding + human/E8/T8 cross-tree drift rejection; no empirical outcomes inferred)")


if __name__ == "__main__":
    main()
