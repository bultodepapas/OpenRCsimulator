"""Rebuild the frozen pre-brake app that produced fixed_brake_legacy_outputs.json, and verify it.

Usage: python reconstruct_legacy_reference.py <repo-root> <new-dir> [--nitro-06-r3] [--focused-checkout]

The reference is the parent of the GP-12 promotion commit (552d683ea^) with this folder's
before/ runtime sources (Session 2bc02a0f..., Trace 1c529262..., Main a6137c9c...) overlaid.
Every app script and data file in construction/loaded-source-pins.json must match its pinned
SHA-256 (Windows CRLF working-tree bytes; the LF form is also accepted), or the build fails.
--nitro-06-r3 then replaces app/physics/glow/carburetor.gd with the NITRO-06-R3 closed-form
root from 20662f264, the one later documented physics change that moves these outputs.
The copy reads res://../assets, so the caller places assets/ beside <new-dir>/app.
--focused-checkout uses an isolated non-promisor object store and a path-limited
checkout; it requires the two pinned commits and their app/ blobs locally.
"""
import hashlib
import io
import json
import os
import shutil
import subprocess
import sys
import tarfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
EVIDENCE = HERE.parent
BASE_COMMIT = "fa9f387f6"  # 552d683ea^: the tree the legacy oracle was captured on, before promotion
R3_COMMIT = "20662f264"  # NITRO-06-R3 closed-form carburettor root
BASE_OID = "fa9f387f68f753d988456764f5723932eae64cea"
R3_OID = "20662f264acaed343b210d048f4ee7628ea5ee70"
ROOT_ATTRIBUTES_OID = "2bbe56293730deef6e66a0a3d26c438d2c308db5"
R3_CARBURETOR_OID = "bb06578fabf39c78f04ea91f2b1b4af5408961b4"
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
    return subprocess.run(["git", "-C", str(repo), *args], check=True, stdout=subprocess.PIPE, timeout=1100).stdout


def focused_checkout(repo: Path, out: Path) -> tuple[Path, dict[str, str]]:
    """Materialize exactly the frozen app tree without any lazy network fetch."""
    raw_objects = git(repo, "rev-parse", "--git-path", "objects").decode().strip()
    objects = Path(raw_objects)
    objects = (objects if objects.is_absolute() else repo / objects).resolve()
    if not objects.is_dir() or "\n" in str(objects) or "\r" in str(objects):
        sys.exit("invalid source Git object store")
    env = os.environ.copy()
    for key in list(env):
        if key.startswith(("GIT_CONFIG_KEY_", "GIT_CONFIG_VALUE_")) or key in {
            "GIT_CONFIG_COUNT", "GIT_CONFIG_PARAMETERS", "GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE",
            "GIT_COMMON_DIR", "GIT_OBJECT_DIRECTORY", "GIT_ALTERNATE_OBJECT_DIRECTORIES",
        }:
            env.pop(key, None)
    env.update(GIT_CONFIG_NOSYSTEM="1", GIT_ATTR_NOSYSTEM="1", GIT_CONFIG_GLOBAL=os.devnull, GIT_TERMINAL_PROMPT="0",
               GIT_NO_REPLACE_OBJECTS="1", GIT_ALLOW_PROTOCOL="file")
    isolated = out / ".reference-git"
    subprocess.run(["git", "-c", "init.templateDir=", "init", "--quiet", str(isolated)], check=True, env=env, timeout=1100)
    gitdir = isolated / ".git"
    (gitdir / "objects/info/alternates").write_bytes(objects.as_posix().encode("utf-8") + b"\n")

    def isolated_git(*args: str) -> bytes:
        return subprocess.run(["git", "--git-dir", str(gitdir), "--work-tree", str(out), *args],
                              check=True, env=env, stdout=subprocess.PIPE, timeout=1100).stdout

    attrs_entry = isolated_git("ls-tree", "-z", BASE_OID, "--", ".gitattributes")
    expected_attrs = f"100644 blob {ROOT_ATTRIBUTES_OID}\t.gitattributes\0".encode()
    if attrs_entry != expected_attrs:
        sys.exit("historical root attributes identity differs")
    attributes = isolated_git("cat-file", "blob", ROOT_ATTRIBUTES_OID)
    for line in attributes.decode("utf-8").splitlines():
        if line.strip() and not line.lstrip().startswith("#") and any(
                item in line for item in ("export-ignore", "export-subst", "filter=", "working-tree-encoding")):
            sys.exit("unsupported historical checkout attribute")
    (out / ".gitattributes").write_bytes(attributes)
    tree = {}
    for entry in isolated_git("ls-tree", "-r", "-z", BASE_OID, "--", "app").split(b"\0"):
        if not entry:
            continue
        left, path = entry.split(b"\t", 1)
        mode, kind, oid = left.split(b" ")
        if not path.startswith(b"app/") or path.endswith(b"/.gitattributes") or kind != b"blob" \
                or mode not in {b"100644", b"100755"} or path in tree:
            sys.exit("unsupported historical app tree entry")
        tree[path] = (mode, oid)
    if len(tree) != 4291:
        sys.exit("historical app tree must contain exactly 4291 files")
    carb_entry = isolated_git("ls-tree", "-z", R3_OID, "--", "app/physics/glow/carburetor.gd")
    expected_carb = f"100644 blob {R3_CARBURETOR_OID}\tapp/physics/glow/carburetor.gd\0".encode()
    if carb_entry != expected_carb:
        sys.exit("historical R3 carburetor object identity differs")
    wanted = sorted({oid for _, oid in tree.values()} | {ROOT_ATTRIBUTES_OID.encode(), R3_CARBURETOR_OID.encode()})
    present = subprocess.run(["git", "--git-dir", str(gitdir), "cat-file", "--batch-check=%(objectname) %(objecttype)"],
                             input=b"".join(oid + b"\n" for oid in wanted), check=True, env=env,
                             stdout=subprocess.PIPE, timeout=1100).stdout.splitlines()
    if present != [oid + b" blob" for oid in wanted]:
        sys.exit("historical focused checkout is missing a required blob")
    isolated_git("-c", "core.autocrlf=false", "-c", "core.hooksPath=" + os.devnull,
                 "checkout", BASE_OID, "--", "app")
    index = {}
    for entry in isolated_git("ls-files", "--stage", "-z").split(b"\0"):
        if not entry:
            continue
        left, path = entry.split(b"\t", 1)
        mode, oid, stage = left.split(b" ")
        if stage != b"0" or path in index:
            sys.exit("invalid historical checkout index")
        index[path] = (mode, oid)
    if index != tree:
        sys.exit("historical checkout does not match the complete app tree")
    return gitdir, env


def main(repo: Path, out: Path, r3: bool, focused: bool = False) -> int:
    if out.exists():
        sys.exit("refusing existing " + str(out))
    out.mkdir(parents=True)
    focused_source = focused_checkout(repo, out) if focused else None
    if not focused:
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
        if focused_source is None:
            carburetor.write_bytes(git(repo, "show", R3_COMMIT + ":app/physics/glow/carburetor.gd"))
        else:
            gitdir, env = focused_source
            carburetor.write_bytes(subprocess.run(["git", "--git-dir", str(gitdir), "show",
                                                   R3_OID + ":app/physics/glow/carburetor.gd"],
                                                  check=True, env=env, stdout=subprocess.PIPE, timeout=1100).stdout)
    (out / "app/reference.json").write_text(json.dumps(dict(
        base_commit=BASE_COMMIT, before_sources="docs/research/ground-physics/GP-12/evidence/fixed-brake-input/before",
        pinned_inputs_verified=checked, nitro_06_r3=R3_COMMIT if r3 else None,
        carburetor_sha256=sha(carburetor.read_bytes())), indent=2) + "\n", encoding="utf-8")
    print("reference %s: %d pinned inputs verified%s" % (out, checked, ", NITRO-06-R3 applied" if r3 else ""))
    return 0


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if a not in {"--nitro-06-r3", "--focused-checkout"}]
    if len(args) != 2:
        sys.exit(__doc__)
    sys.exit(main(Path(args[0]).resolve(), Path(args[1]), "--nitro-06-r3" in sys.argv[1:],
                  "--focused-checkout" in sys.argv[1:]))
