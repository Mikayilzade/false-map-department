#!/usr/bin/env python3
from __future__ import annotations

import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOOL = ROOT / "scripts/phase12g_human_field_kit.py"
ARTIFACT = ROOT / "scripts/phase12g_build_artifact_contract.py"
SOURCE_HEAD = "0123456789abcdef0123456789abcdef01234567"


def fail(message: str) -> None: raise SystemExit(f"PHASE12G FIELD KIT AUDIT FAIL: {message}")
def run(args: list[str], ok: bool = True, cwd: Path | None = None) -> subprocess.CompletedProcess[str]:
    result=subprocess.run(args,cwd=cwd or ROOT,text=True,capture_output=True)
    if ok and result.returncode!=0: fail(f"command failed: {' '.join(args)}\n{result.stdout}\n{result.stderr}")
    if not ok and result.returncode==0: fail(f"command unexpectedly succeeded: {' '.join(args)}")
    return result
def load(path: Path) -> dict: return json.loads(path.read_text(encoding="utf-8"))
def bind(root: Path, role: str, build_id: str) -> tuple[Path,Path]:
    package=root/f"{role}.pck"; package.write_bytes((f"FMD-{role}-{build_id}").encode())
    record=root/f"{role}.binding.json"
    run([sys.executable,str(ARTIFACT),"create","--source-head",SOURCE_HEAD,"--role",role,"--build-id",build_id,"--artifact",str(package),"--output",str(record)])
    return package,record

def prepare(root: Path, demo: tuple[Path,Path], production: tuple[Path,Path]) -> dict:
    result=run([sys.executable,str(TOOL),"prepare","--source-head",SOURCE_HEAD,"--demo-build-id","audit-demo-build","--production-build-id","audit-production-build","--demo-build-artifact",str(demo[0]),"--demo-build-artifact-record",str(demo[1]),"--production-build-artifact",str(production[0]),"--production-build-artifact-record",str(production[1]),"--first-count","1","--mature-count","1","--output-dir",str(root)])
    return json.loads(result.stdout)
def main() -> None:
    with tempfile.TemporaryDirectory(prefix="fmd-phase12g-field-kit-") as temp:
        root=Path(temp); demo=bind(root,"demo","audit-demo-build"); production=bind(root,"production","audit-production-build"); kit=root/"kit"
        summary=prepare(kit,demo,production)
        if summary.get("status")!="PREPARED" or summary.get("append_ready") is not True: fail("bound kit must be PREPARED/append_ready")
        manifest=load(kit/"field-kit-manifest.json")
        if manifest.get("field_kit_version")!=5 or manifest.get("acquisition_build_bytes_required") is not True: fail("field kit must use v5 byte-binding contract")
        bindings=manifest.get("build_artifacts",{})
        for role in ("demo","production"):
            snap=bindings.get(role,{})
            if len(str(snap.get("binding_id","")))!=64 or len(str(snap.get("artifact_sha256","")))!=64 or snap.get("acquisition_bytes_frozen") is not True: fail(f"{role} build binding incomplete")
        relocated=root/"relocated"; shutil.copytree(kit,relocated); shutil.rmtree(kit)
        verified=run([sys.executable,str(relocated/"FIELD-KIT-VERIFY.py"),"--kit-dir","."],cwd=relocated)
        payload=json.loads(verified.stdout)
        if payload.get("status")!="VERIFIED_OFFLINE" or payload.get("acquisition_build_bytes_verified") is not True: fail("offline verify must rehash both frozen packaged builds")
        # Byte drift must fail closed before any human finalization can become append-ready.
        demo_path=relocated/str(bindings["demo"]["packet_artifact_path"]); demo_path.write_bytes(demo_path.read_bytes()+b"tamper")
        rejected=run([sys.executable,str(relocated/"FIELD-KIT-VERIFY.py"),"--kit-dir","."],ok=False,cwd=relocated)
        if "packaged build bytes changed" not in (rejected.stdout+rejected.stderr): fail("packaged-build byte drift must be rejected")
        # A production record cannot be substituted for a demo role during preparation.
        bad=root/"bad-kit"
        mismatch=run([sys.executable,str(TOOL),"prepare","--source-head",SOURCE_HEAD,"--demo-build-id","audit-demo-build","--production-build-id","audit-production-build","--demo-build-artifact",str(production[0]),"--demo-build-artifact-record",str(production[1]),"--production-build-artifact",str(production[0]),"--production-build-artifact-record",str(production[1]),"--first-count","1","--mature-count","1","--output-dir",str(bad)],ok=False)
        if "role mismatch" not in (mismatch.stdout+mismatch.stderr) and "build_id mismatch" not in (mismatch.stdout+mismatch.stderr): fail("role/build substitution must fail closed")
    print("Phase 12G human field-kit audit: PASS (source/build/role bound to exact packaged bytes + portable offline rehash + drift/substitution rejection; no human outcome inferred)")
if __name__=="__main__": main()
