"""Rebuild the frozen pre-brake app that produced fixed_brake_legacy_outputs.json, and verify it.

Usage: python reconstruct_legacy_reference.py <repo-root> <new-dir> [--nitro-06-r3]

The reference is the parent of the GP-12 promotion commit (552d683ea^) with this folder's
before/ runtime sources (Session 2bc02a0f..., Trace 1c529262..., Main a6137c9c...) overlaid.
Every app script and data file in construction/loaded-source-pins.json must match its pinned
SHA-256 (Windows CRLF working-tree bytes; the LF form is also accepted), or the build fails.
--nitro-06-r3 then replaces app/physics/glow/carburetor.gd with the NITRO-06-R3 closed-form
root from 20662f264, the one later documented physics change that moves these outputs.
The copy reads res://../assets, so the caller places assets/ beside <new-dir>/app.
"""
import hashlib
import io
import json
import shutil
import subprocess
import sys
import tarfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
EVIDENCE = HERE.parent
BASE_COMMIT = "fa9f387f6"  # 552d683ea^: the tree the legacy oracle was captured on, before promotion
R3_COMMIT = "20662f264"  # NITRO-06-R3 closed-form carburettor root
R3_PARENT_CARBURETOR = "d3fe00763772ca36a9b86e240c7dfb0de6b239350b0930d6000651534956fd7c"
PIN_PREFIX = "C:\\DEVELOPMENT\\OpenRCsimulator\\"
# Pinned workspace bytes that differ from BASE_COMMIT, restored from retained byte-exact copies:
# the GP-12 input-role-replay reader (promoted in the same workspace before this review), and
# airfield_course.gd, whose content equals BASE_COMMIT but whose workspace copy had mixed line endings.
OVERLAYS = {
    "app/tools/flight_log_cli.gd": "docs/research/ground-physics/GP-12/evidence/input-role-replay/source/app/tools/flight_log_cli.gd",
    "app/physics/ground_vehicle/airfield_course.gd":
        "docs/research/wind-implementation/M5-W05d-R3/baseline-source/app/physics/ground_vehicle/airfield_course.gd",
}


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def matches(data: bytes, pin: str) -> bool:
    lf = data.replace(b"\r\n", b"\n")
    return pin in (sha(data), sha(lf), sha(lf.replace(b"\n", b"\r\n")))


def git(repo: Path, *args: str) -> bytes:
    return subprocess.run(["git", "-C", str(repo), *args], check=True, stdout=subprocess.PIPE).stdout


def main(repo: Path, out: Path, r3: bool) -> int:
    if out.exists():
        sys.exit("refusing existing " + str(out))
    out.mkdir(parents=True)
    with tarfile.open(fileobj=io.BytesIO(git(repo, "archive", "--format=tar", BASE_COMMIT, "app"))) as archive:
        archive.extractall(out, filter="data")
    for path in ["app/main.gd", "app/sim/flight_session.gd", "app/sim/trace.gd"]:
        shutil.copyfile(EVIDENCE / "before" / path, out / path)
    for path, source in OVERLAYS.items():
        shutil.copyfile(repo / source, out / path)
    pins = json.loads((HERE / "loaded-source-pins.json").read_text(encoding="utf-8"))
    checked, failed = 0, []
    for key, pin in list(pins["scripts"].items()) + list(pins["data"].items()):
        rel = key[len(PIN_PREFIX):].replace("\\", "/") if key.startswith(PIN_PREFIX) else key
        if not rel.startswith("app/"):
            continue  # detached candidate drafts under tmp/, not part of the old owner
        target = out / rel
        checked += 1
        if not target.exists() or not matches(target.read_bytes(), pin):
            failed.append(rel)
    if failed:
        sys.exit("reference does not reproduce %d pinned inputs: %s" % (len(failed), failed))
    carburetor = out / "app/physics/glow/carburetor.gd"
    if not matches(carburetor.read_bytes(), R3_PARENT_CARBURETOR):
        sys.exit("unexpected pre-R3 carburetor")
    if r3:
        carburetor.write_bytes(git(repo, "show", R3_COMMIT + ":app/physics/glow/carburetor.gd"))
    (out / "app/reference.json").write_text(json.dumps(dict(
        base_commit=BASE_COMMIT, before_sources="docs/research/ground-physics/GP-12/evidence/fixed-brake-input/before",
        pinned_inputs_verified=checked, nitro_06_r3=R3_COMMIT if r3 else None,
        carburetor_sha256=sha(carburetor.read_bytes())), indent=2) + "\n", encoding="utf-8")
    print("reference %s: %d pinned inputs verified%s" % (out, checked, ", NITRO-06-R3 applied" if r3 else ""))
    return 0


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if a != "--nitro-06-r3"]
    if len(args) != 2:
        sys.exit(__doc__)
    sys.exit(main(Path(args[0]).resolve(), Path(args[1]), "--nitro-06-r3" in sys.argv[1:]))
