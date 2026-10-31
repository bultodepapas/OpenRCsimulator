#!/usr/bin/env python3
"""Experimental capture-group receipts and reduction, not a CI qualification gate.

The caller supplies a fresh run ID to each group, then independently supplies
that same ID, the expected commit and the engine/interpreter to ``reduce``.
This checks completed shell milestones and intact artifacts. It does not
establish rendered equivalence, individual assertion counts, or GPU quality.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import subprocess
import sys
import tempfile

RECEIPT = "capture-group-receipt.json"
START = ".capture-start.json"
CHECKS = ".capture-checks"
GROUP_CHECKS = {
    "core": ["sun-alignment", "shots", "landscape", "readability", "trace", "trace-check"],
    "ui": ["captures"],
    "quality": ["tests", "cases", "aircraft-lights", "field-failures"],
    "terrain-atmosphere": ["tree-review", "horizon", "phase6", "cloud-probe"],
    "ground": ["surfaces", "stripe-tests", "stripes", "windsock", "pilot-station",
               "flightline-barrier", "contact-shadows"],
    "vegetation": ["grass", "grass-seam", "tree-wind", "treeline-tests", "treeline"],
    "scenario": ["run"],
}
GROUP_PHASES = {group: ["setup", group] for group in GROUP_CHECKS}
GROUP_PHASES["core"] = ["setup", "core-render", "core-checks"]

# Direct entry points are byte-hashed even in a clean working tree. Git's
# commit plus dirty/untracked file contents bind the rest of the checkout.
DIRECT_SOURCES = (
    "app/capture.sh", "app/get-godot.sh", "app/tests/visual-env.sh",
    "app/tests/requirements-visual.txt", "app/tests/capture_runner.py",
    "app/tests/test_capture_runner.py", "app/tests/capture_ui.gd",
    "app/tests/fixtures/atmosphere_field.tscn", "app/tests/capture_landscape_upgrade.gd",
    "app/tests/check_landscape_captures.py", "app/tests/compare_captures.py",
    "app/tests/check_trimmed_flight.py", "app/tests/test_visual_quality_cases.py",
    "app/tests/visual_quality_cases.py", "app/tests/capture_aircraft_lights.gd",
    "app/tests/test_field_failures.py", "app/tests/test_treeline_readability.py",
    "app/tests/treeline_readability.py", "tools/ci/capture_groups.py",
    "tools/trees/check_review.py", "tools/trees/check_wind.py",
    "tools/terrain/check_horizon.py", "tools/atmosphere/check_phase6.py",
    "tools/atmosphere/check_cloud_probe.py", "tools/ground/check_surfaces.py",
    "tools/ground/test_stripes.py", "tools/ground/check_stripes.py",
    "tools/ground/check_windsock.py", "tools/grass/check_grass.py",
    "tools/grass/check_grass_seam.py", "tools/scenery/scenario.sh",
    "tools/scenery/scenario_report.py", "app/scenery/runway_scenario.gd",
)
SOURCE_SUFFIXES = {".gd", ".gdshader", ".gdextension", ".tscn", ".tres", ".py", ".sh",
                   ".json", ".cfg", ".toml", ".ini", ".uid", ".import", ".csv"}

CORE_IMAGES = [f"capture{suffix}.png" for suffix in (
    "", "-inspect", "-inspect-deflected", "-physics", "-physics-inspect", "-physics-nozoom",
    "-physics-low-inspect", "-physics-low-inspect-noplane", "-physics-inspect-noplane")]
CORE_IMAGES += [f"capture-land-az{az}-el{el}.png" for az in (0, 90, 180, 270) for el in (0, 10)]
CORE_IMAGES += ["capture-land-az90-el10-t11.png"]
CORE_IMAGES += [f"capture-land-az{az}-el0-100m.png" for az in (0, 90, 180, 225, 270)]
CORE_IMAGES += [f"capture-land-{name}.png" for name in ("30m", "low3m", "sun", "30m-noplane", "low3m-noplane", "top")]
CORE_IMAGES += [f"field/capture-land-az{az}-el{el}.png" for az in (0, 90, 180, 270) for el in (0, 10)]
CORE_IMAGES += ["field/capture-land-top.png"]
UI_IMAGES = [f"ui-{screen}-{lang}.png" for lang in ("en", "es") for screen in ("home", "pause", "help", "hint")]
POSES = ("level", "inverted", "knife_left", "knife_right", "climb", "dive")
VQ_CASES = [f"pilot-{distance}-autozoom-{zoom}{hidden}"
            for distance in ("30m", "3m") for zoom in ("on", "off") for hidden in ("", "-noplane")]
VQ_CASES += [f"field-az{az}-el{el}-repeat{repeat}" for az in (0, 90, 180, 270)
             for el in (0, 10) for repeat in (1, 2)]
VQ_CASES += [f"field-top30m-repeat{repeat}" for repeat in (1, 2)]
VQ_CASES += [f"synthetic-{plane}-{distance}m-{pose}" for plane in ("stik", "extra")
             for distance in (20, 50, 100) for pose in POSES]
VQ_CASES += [f"ui-{screen}-{lang}" for screen in ("home", "flight") for lang in ("en", "es")]
TREELINE_CASES = [f"l6c-{view}-{background}-{case}" for view in ("game", "fixed")
                  for background in ("sky", "horizon", "trees", "ground")
                  for case in ("noplane", "notrees", *POSES)]
REQUIRED_OUTPUTS = {
    "core": ["trace-physics.csv", "landscape-counters.txt", "field/landscape-counters.txt",
             "sun-alignment/report.json", "sun-alignment/sun_alignment.png"],
    "ui": [],
    "quality": ["vq01b/visual-quality-run-manifest.json", "aircraft-lights/summary.json"],
    "terrain-atmosphere": ["l6b/repeat-1/review.json", "l7/capture-summary.json",
                           "l4b/capture-summary.json", "l15d/summary.json"],
    "ground": ["l9c/summary.json", "l9c/stripes/summary.json", "l10a/summary.json",
               "l10b/summary.json", "l10c/summary.json", "l10d/summary.json"],
    "vegetation": ["l11a/capture-summary.json", "l11a/seam-summary.json",
                   "l15b/capture-summary.json", "l6c/l6c-run-manifest.json"],
    "scenario": ["scenario/latest/scenario.json", "scenario/latest/sync.json", "scenario/latest/report.html"],
}


def fail(message: str) -> None:
    raise ValueError(message)


def digest(path: Path) -> str:
    if not path.is_file():
        fail(f"missing regular file: {path}")
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def source_identity(repo: Path) -> dict:
    root = Path(subprocess.check_output(["git", "-C", str(repo), "rev-parse", "--show-toplevel"], text=True).strip()).resolve()
    if root != repo.resolve() or Path(__file__).resolve() != root / "tools/ci/capture_groups.py":
        fail("the verifier and supplied repository must belong to the same checkout")
    commit = subprocess.check_output(["git", "-C", str(root), "rev-parse", "HEAD"], text=True).strip()
    if not re.fullmatch(r"[0-9a-f]{40}", commit):
        fail("cannot identify full source commit")
    index = subprocess.check_output(["git", "-C", str(root), "ls-files", "-v", "-z"])
    if any(record[:2] != b"H " for record in index.split(b"\0") if record):
        fail("assume-unchanged, sparse or unmerged index entries cannot establish source identity")
    status = subprocess.check_output(["git", "-C", str(root), "status", "--porcelain=v1", "-z",
                                      "--untracked-files=all", "--no-renames"])
    changes = []
    for record in status.split(b"\0"):
        if not record:
            continue
        if len(record) < 4 or record[2:3] != b" ":
            fail("unrecognized Git status record")
        name = os.fsdecode(record[3:])
        path = root / name
        if path.is_symlink():
            value = {"symlink": os.readlink(path)}
        elif path.is_file():
            value = {"sha256": digest(path)}
        elif not path.exists():
            value = {"deleted": True}
        else:
            fail(f"unsupported changed source path: {name}")
        changes.append({"status": os.fsdecode(record[:2]), "path": name, **value})
    sources = {name: digest(root / name) for name in DIRECT_SOURCES}
    tracked = subprocess.check_output(["git", "-C", str(root), "ls-files", "-z", "--", "app", "tools"])
    tracked_source = {}
    for record in tracked.split(b"\0"):
        if not record:
            continue
        name = os.fsdecode(record)
        if Path(name).suffix.lower() in SOURCE_SUFFIXES:
            tracked_source[name] = digest(root / name)
    # Ignored import/runtime caches and capture outputs are not authoring input.
    # Other ignored files in runtime/checker roots may be loaded dynamically,
    # including local native libraries, and therefore bind their actual bytes.
    ignored = subprocess.check_output(["git", "-C", str(root), "ls-files", "--others", "--ignored",
                                       "--exclude-standard", "-z", "--", "app", "tools", "assets"])
    ignored_inputs = {}
    for record in ignored.split(b"\0"):
        if not record:
            continue
        name = os.fsdecode(record)
        parts = Path(name).parts
        if any(part in {".godot", "captures", ".capture-profile", "__pycache__"} for part in parts):
            continue
        if Path(name).suffix.lower() in {".tmp", ".log", ".pyc"}:
            continue
        path = root / name
        if path.is_symlink():
            fail(f"ignored source input is a symlink: {name}")
        ignored_inputs[name] = digest(path)
    return {"commit": commit, "changes": changes, "direct_sources": sources,
            "tracked_runtime_sources": tracked_source,
            "ignored_runtime_inputs": dict(sorted(ignored_inputs.items()))}


def configuration(check_environment: bool = False, revision: str | None = None) -> dict:
    expected = {"OPENRC_SCENERY": "off", "OPENRC_SCENERY_BIRDS": "off",
                "OPENRC_ENGINE_SHADOWS": "off", "LP_NUM_THREADS": "1"}
    if check_environment:
        actual = {key: os.environ.get(key, "1" if key == "LP_NUM_THREADS" else "") for key in expected}
        if actual != expected:
            fail(f"experimental receipts require the fixed capture environment: {actual}")
        prefixes = ("OPENRC_", "GODOT_", "MESA_", "LIBGL_", "GALLIUM_", "LP_", "VK_")
        allowed = set(expected)
        if revision is not None:
            allowed.add("OPENRC_CODE_REVISION")
            if os.environ.get("OPENRC_CODE_REVISION") != revision:
                fail("capture revision metadata does not match the independently inspected checkout")
        unexpected = sorted(key for key in os.environ if key.startswith(prefixes) and key not in allowed)
        if unexpected:
            fail(f"unsupported capture environment overrides: {unexpected}")
    return {"environment": expected, "driver": "opengl3", "audio": "Dummy",
            "historical_viewport": [1280, 720], "large_xvfb_screen": [1920, 1080],
            "system": platform.system(), "machine": platform.machine(),
            "orchestrator_python": platform.python_version()}


def valid_run_id(run_id: str) -> None:
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]{0,127}", run_id):
        fail("run ID must be 1-128 ASCII letters, digits, dots, underscores or hyphens")


def read_json(path: Path):
    def unique_object(pairs):
        value = {}
        for key, item in pairs:
            if key in value:
                fail(f"duplicate JSON key in {path}: {key}")
            value[key] = item
        return value

    def invalid_constant(value):
        fail(f"invalid JSON constant in {path}: {value}")

    with path.open(encoding="utf-8") as stream:
        return json.load(stream, object_pairs_hook=unique_object, parse_constant=invalid_constant)


def same_json(left, right) -> bool:
    # Python considers True == 1 and 720.0 == 720, but evidence schemas do not.
    return json.dumps(left, sort_keys=True, allow_nan=False) == json.dumps(right, sort_keys=True, allow_nan=False)


def atomic_new_json(path: Path, value: dict) -> None:
    if path.name == "run-manifest.json":
        fail("the legacy capture-set marker is reserved")
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temp = tempfile.mkstemp(prefix=".capture-write-", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            json.dump(value, stream, indent=2, sort_keys=True)
            stream.write("\n")
        os.link(temp, path)  # atomic, and fails if the result already exists
    finally:
        os.unlink(temp)


def phase_and_checks(root: Path, group: str) -> None:
    expected_checks = ["setup:import", "setup:capture-runner-tests"]
    expected_checks += [f"{group}:{name}" for name in GROUP_CHECKS[group]]
    if (root / CHECKS).read_text(encoding="utf-8").splitlines() != expected_checks:
        fail(f"{group}: missing, duplicated, unexpected or out-of-order checker milestone")
    lines = (root / "timings.tsv").read_text(encoding="utf-8").splitlines()
    if not lines or lines[0] != "phase\tseconds\tresult":
        fail(f"{group}: invalid timings header")
    rows = [line.split("\t") for line in lines[1:]]
    if ([row[0] for row in rows] != GROUP_PHASES[group]
            or any(len(row) != 3 or not row[1].isdigit() or row[2] != "pass" for row in rows)):
        fail(f"{group}: incomplete, failed or unexpected phases")


def local_file(root: Path, name: str) -> Path:
    path = Path(name)
    if path.is_absolute() or not name or any(part in ("..", ".") for part in path.parts):
        fail(f"unsafe output path: {name}")
    result = root / path
    if result.is_symlink() or not result.is_file() or not result.resolve().is_relative_to(root.resolve()):
        fail(f"missing or unsafe output: {name}")
    return result


def verify_matrix(root: Path, relative: str, expected_ids: list[str]) -> None:
    folder = root / relative
    count = len(expected_ids)
    name = "visual-quality-run-manifest.json" if count == 66 else "l6c-run-manifest.json"
    data = read_json(local_file(folder, name))
    if not isinstance(data, dict) or not isinstance(data.get("inventory"), dict):
        fail(f"{relative}: invalid matrix manifest")
    inventory, captures = data.get("inventory", {}), data.get("captures", [])
    ids = inventory.get("expected_case_ids")
    if (data.get("complete") is not True or type(inventory.get("capture_count")) is not int
            or inventory.get("capture_count") != count
            or ids != expected_ids
            or not isinstance(captures, list) or len(captures) != count
            or any(not isinstance(capture, dict) for capture in captures)
            or [c.get("case_id") for c in captures] != ids):
        fail(f"{relative}: incomplete or inconsistent fixed capture inventory")
    for capture in captures:
        image = local_file(folder, capture.get("image", ""))
        sidecar = local_file(folder, capture.get("capture_manifest", ""))
        case_id = capture["case_id"]
        metadata = read_json(sidecar)
        if not isinstance(metadata, dict):
            fail(f"{relative}: invalid matrix sidecar")
        scene = case_id.split("-")[1] if case_id.startswith("ui-") else "field"
        if (image.name != f"{case_id}.png" or sidecar.name != f"{case_id}.json"
                or digest(image) != capture.get("sha256") or digest(sidecar) != capture.get("capture_manifest_sha256")
                or metadata.get("image") != image.name or metadata.get("sha256") != capture.get("sha256")
                or metadata.get("capture_scene") != scene):
            fail(f"{relative}: matrix image or sidecar hash mismatch")


def verify_outputs(root: Path, group: str) -> dict[str, str]:
    if (root / "run-manifest.json").exists():
        fail("a partial group must never contain the legacy complete marker")
    phase_and_checks(root, group)
    images = CORE_IMAGES if group == "core" else UI_IMAGES if group == "ui" else []
    for name in [*REQUIRED_OUTPUTS[group], *images]:
        path = local_file(root, name)
        if path.stat().st_size == 0:
            fail(f"empty required output: {name}")
        if path.suffix == ".json":
            read_json(path)
    for name in images:
        image = local_file(root, name)
        sidecar = local_file(root, str(Path(name).with_suffix(".json")))
        data = read_json(sidecar)
        if not isinstance(data, dict):
            fail(f"{group}: invalid image sidecar: {name}")
        scene = ("field" if name.startswith("field/") else "atmosphere") if group == "core" else name.split("-")[1]
        if data.get("image") != image.name or data.get("sha256") != digest(image) or data.get("capture_scene") != scene:
            fail(f"{group}: image/sidecar mismatch: {name}")
    if group == "quality":
        verify_matrix(root, "vq01b", VQ_CASES)
        light_summary = read_json(root / "aircraft-lights/summary.json")
        if not isinstance(light_summary, dict) or light_summary.get("ok") is not True:
            fail("aircraft lights summary did not pass")
    if group == "vegetation":
        verify_matrix(root, "l6c", TREELINE_CASES)
    if group == "scenario":
        checks = read_json(root / "scenario/latest/sync.json")
        if (not isinstance(checks, list) or not checks
                or any(not isinstance(c, dict) or c.get("ok") is not True for c in checks)):
            fail("scenario sync checks are missing or failed")
    files = {}
    for directory, dirs, names in os.walk(root, followlinks=False):
        parent = Path(directory)
        for name in list(dirs):
            if (parent / name).is_symlink():
                fail("symlink in group output")
        if parent == root and ".capture-profile" in dirs:
            dirs.remove(".capture-profile")
        for name in names:
            path = parent / name
            relative = path.relative_to(root).as_posix()
            if relative == RECEIPT:
                continue
            files[relative] = digest(local_file(root, relative))
    return dict(sorted(files.items()))


def begin(args) -> None:
    valid_run_id(args.run_id)
    config = configuration(check_environment=True)
    resolved_out = args.out.resolve()
    if resolved_out.is_relative_to(args.repo.resolve()):
        ignored = subprocess.run(["git", "-C", str(args.repo), "check-ignore", "-q", str(resolved_out)], check=False)
        if ignored.returncode != 0:
            fail("group output inside the checkout must be Git-ignored")
    start = {"format": "openrc-experimental-capture-start v1", "group": args.group,
             "run_id": args.run_id, "source": source_identity(args.repo),
             "engine_sha256": digest(args.godot), "config": config}
    atomic_new_json(args.out / START, start)


def finish(args) -> None:
    valid_run_id(args.run_id)
    start = read_json(args.out / START)
    source = source_identity(args.repo)
    revision = source["commit"] + ("-dirty" if source["changes"] else "")
    expected = {"format": "openrc-experimental-capture-start v1", "group": args.group,
                "run_id": args.run_id, "source": source,
                "engine_sha256": digest(args.godot), "config": configuration(check_environment=True, revision=revision)}
    if not same_json(start, expected):
        fail("group source, engine, configuration or run identity changed")
    visual_python = digest(args.visual_python)
    files = verify_outputs(args.out, args.group)
    if source_identity(args.repo) != start["source"] or digest(args.godot) != start["engine_sha256"] or digest(args.visual_python) != visual_python:
        fail("source, engine or visual interpreter changed while recording outputs")
    receipt = {"format": "openrc-experimental-capture-group v1", "status": "passed",
               "start": start, "visual_python_sha256": visual_python, "outputs": files}
    atomic_new_json(args.out / RECEIPT, receipt)


def reduce_groups(args) -> None:
    valid_run_id(args.run_id)
    if not re.fullmatch(r"[0-9a-f]{40}", args.expect_commit):
        fail("expected commit must be a full lowercase Git SHA")
    source = source_identity(args.repo)
    if source["commit"] != args.expect_commit:
        fail("checkout does not match independently expected commit")
    engine = digest(args.godot)
    visual_python = digest(args.visual_python)
    config = configuration()
    groups = {}
    directories = set()
    for raw in args.parts:
        if raw.is_symlink() or not raw.is_dir():
            fail(f"invalid group directory: {raw}")
        root = raw.resolve()
        if any(root.is_relative_to(other) or other.is_relative_to(root) for other in directories):
            fail("duplicate or nested group directory")
        if args.out.resolve().is_relative_to(root):
            fail("the reducer output must be outside every group directory")
        directories.add(root)
        receipt = read_json(local_file(root, RECEIPT))
        if (not isinstance(receipt, dict)
                or set(receipt) != {"format", "status", "start", "visual_python_sha256", "outputs"}
                or not isinstance(receipt.get("start"), dict) or not isinstance(receipt.get("outputs"), dict)):
            fail("invalid capture group receipt schema")
        start = receipt.get("start", {})
        group = start.get("group")
        if group not in GROUP_CHECKS or group in groups:
            fail("unexpected or duplicated group")
        expected_start = {"format": "openrc-experimental-capture-start v1", "group": group,
                          "run_id": args.run_id, "source": source, "engine_sha256": engine, "config": config}
        if (receipt.get("format") != "openrc-experimental-capture-group v1"
                or receipt.get("status") != "passed" or not same_json(start, expected_start)
                or not same_json(read_json(local_file(root, START)), expected_start)
                or receipt.get("visual_python_sha256") != visual_python):
            fail(f"{group}: wrong run, source, engine, configuration or completion")
        if receipt.get("outputs") != verify_outputs(root, group):
            fail(f"{group}: output inventory or content changed")
        groups[group] = {"receipt_sha256": digest(root / RECEIPT), "output_count": len(receipt["outputs"])}
    if set(groups) != set(GROUP_CHECKS):
        fail(f"missing groups: {sorted(set(GROUP_CHECKS) - set(groups))}")
    if source_identity(args.repo) != source or digest(args.godot) != engine or digest(args.visual_python) != visual_python:
        fail("source, engine or visual interpreter changed during reduction")
    atomic_new_json(args.out, {"format": "openrc-experimental-capture-reduction v1",
                              "status": "groups-recorded", "production_qualified": False,
                              "run_id": args.run_id, "commit": args.expect_commit,
                              "engine_sha256": engine, "config": config, "groups": groups})


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    for command in ("begin", "finish"):
        p = sub.add_parser(command)
        p.add_argument("--repo", type=Path, required=True)
        p.add_argument("--group", choices=GROUP_CHECKS, required=True)
        p.add_argument("--run-id", required=True)
        p.add_argument("--godot", type=Path, required=True)
        p.add_argument("--out", type=Path, required=True)
        if command == "finish":
            p.add_argument("--visual-python", type=Path, required=True)
    p = sub.add_parser("reduce")
    p.add_argument("--repo", type=Path, required=True)
    p.add_argument("--run-id", required=True)
    p.add_argument("--expect-commit", required=True)
    p.add_argument("--godot", type=Path, required=True)
    p.add_argument("--visual-python", type=Path, required=True)
    p.add_argument("--out", type=Path, required=True)
    p.add_argument("--parts", type=Path, nargs="+", required=True)
    args = parser.parse_args()
    try:
        {"begin": begin, "finish": finish, "reduce": reduce_groups}[args.command](args)
    except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError) as error:
        print(f"experimental capture groups: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
