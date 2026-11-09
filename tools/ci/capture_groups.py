#!/usr/bin/env python3
"""Experimental capture-group receipts and reduction, not a CI qualification gate.

The caller supplies a fresh run ID to each group, then independently supplies
that same ID, the expected commit and the engine/interpreter to ``reduce``.
This checks completed shell milestones and intact artifacts. It does not
establish rendered equivalence, individual assertion counts, or GPU quality.
``inventory`` and ``compare`` record hosted shadow evidence: whether separately
run groups reproduce the unchanged full run's outputs. They never qualify production.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import re
import struct
import subprocess
import sys
import tempfile

RECEIPT = "capture-group-receipt.json"
START = ".capture-start.json"
CHECKS = ".capture-checks"
GROUP_CHECKS = {
    "core": ["sun-alignment", "shots", "landscape", "readability", "trace", "trace-check"],
    "ui": ["captures"],
    "quality": ["tests", "cases", "aircraft-lights", "field-failures", "lighting-pixels"],
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
    "app/tests/test_lighting_skin_patterns.gd", "app/tests/test_lighting_segment_filter.gd",
    "tools/godot/run_checked.py", "tools/godot/summarize.py",
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
    "quality": ["vq01b/visual-quality-run-manifest.json", "aircraft-lights/summary.json",
                "lighting-pixels/segment_filter-metrics.json", "lighting-pixels/skin_patterns-metrics.json"],
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
        verify_lighting_metrics(root)
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


# Shadow equivalence: hosted group jobs and the unchanged full job each publish a
# small inventory; ``compare`` checks every output against the full run.
INVENTORY = "inventory.json"
SEGMENT_METRICS = "lighting-pixels/segment_filter-metrics.json"
SKIN_METRICS = "lighting-pixels/skin_patterns-metrics.json"
# Until matched rendered evidence justifies a wider boundary, metric equivalence
# requires exact values (absolute and relative tolerances are both zero).
SEGMENT_METRIC_NAMES = {"far_point_error", "far_filtered_error", "cell_overlap_error", "perspective_error", "reversed_error"}
SEGMENT_METRIC_NAMES.update(f"whole_path_{sample}_{axis}" for sample in range(3) for axis in range(3))
SKIN_METRIC_NAMES = {f"{pattern}_error" for pattern in ("steady", "breath", "pulse", "chase", "wave", "rainbow", "segments")}
SKIN_METRIC_NAMES.update({"wave_spatial_distance", "phase_early_error", "phase_later_error", "phase_distance",
                          "mirror_error", "mirror_distance", "exposure_error", "exposure_delta"})
BOOKKEEPING = {START, CHECKS, RECEIPT, "timings.tsv", ".gdignore", ".capture.lock", "run-manifest.json"}
TEXT_SUFFIXES = {".json", ".txt", ".csv", ".log", ".tsv", ".html", ".md", ".xml", ".svg"}
IMAGE_SUFFIXES = {".png", ".exr", ".jpg", ".jpeg", ".webp"}
LOG_SUFFIXES = {".log", ".html"}
MAX_NORMALIZED_BYTES = 16 * 1024 * 1024
MAX_LISTED = 200
# Volatility model. Every rule is declared here and reported; a hosted run that still differs
# identifies new volatile outputs to examine, never to silently ignore.
SKIPPED_PARTS = {".godot", ".capture-profile", "__pycache__"}
VOLATILE_TREES = ("l9c/disabled-surface-app", "l9c/unfiltered-stripe-app", "l9c/stripes/raw-app",
                  "scenario/history")
VOLATILE_KEYS = {"created_utc", "started_utc", "finished_utc", "checked_utc", "resumed_utc",
                 "capture_id", "elapsed_seconds", "wall_elapsed_seconds", "log_sha256", "log_bytes"}
CHECKED_RUN = re.compile(r"-[a-z0-9_]{8}$")  # tempfile.mkdtemp suffix used by run_checked.py


def canonical_sha256(value) -> str:
    return hashlib.sha256(json.dumps(value, sort_keys=True, allow_nan=False).encode()).hexdigest()


def cpu_model() -> str:
    try:
        for line in Path("/proc/cpuinfo").read_text(encoding="utf-8", errors="replace").splitlines():
            if line.startswith("model name"):
                return line.split(":", 1)[1].strip()
    except OSError:
        pass
    return platform.processor() or "unknown"


def read_timings(root: Path) -> list[list]:
    path = root / "timings.tsv"
    if not path.is_file():
        return []
    rows = []
    for line in path.read_text(encoding="utf-8").splitlines()[1:]:
        parts = line.split("\t")
        if len(parts) == 3 and parts[1].isdigit():
            rows.append([parts[0], int(parts[1]), parts[2]])
    return rows


def excluded_output(relative: str) -> bool:
    """Declared non-evidence trees: import caches/profiles, regenerable mutation copies, dated history."""
    parts = relative.split("/")
    return (relative in BOOKKEEPING or bool(set(parts) & SKIPPED_PARTS)
            or any(relative == tree or relative.startswith(tree + "/") for tree in VOLATILE_TREES))


def strip_volatile(value, markers: list[str]):
    if isinstance(value, dict):
        return {k: strip_volatile(v, markers) for k, v in value.items() if k not in VOLATILE_KEYS}
    if isinstance(value, list):
        return [strip_volatile(v, markers) for v in value]
    if isinstance(value, str):
        for marker in markers:
            value = value.replace(marker, "<CAPTURES>")
        return value
    return value


def normalized_sha256(path: Path, markers: list[str]) -> str | None:
    data = path.read_bytes()
    if path.suffix.lower() == ".json":
        try:
            # Recorded run clocks/IDs and log digests are not rendered evidence.
            value = json.loads(data)
            if path.name in {Path(SEGMENT_METRICS).name, Path(SKIN_METRICS).name}:
                # No run-clock/path rules apply inside semantic measurements.
                return canonical_sha256(value)
            own_output_paths = None
            if (isinstance(value, dict) and value.get("format") == "openrc-godot-check v1"
                    and path.name == "report.json" and CHECKED_RUN.search(path.parent.name)):
                # Only normalize paths that name this checked invocation's own
                # files. An unexpected report-supplied path remains a difference.
                own_output_paths = {}
                for key, filename in (("log", "engine.log"), ("report", "report.json")):
                    own_output_paths[key] = value.get(key) == str(path.with_name(filename))
                    if own_output_paths[key]:
                        value[key] = filename
            value = strip_volatile(value, markers)
            if own_output_paths is not None:
                # Keep independently derived validity outside report-supplied
                # data, so a literal normalization token cannot impersonate it.
                value = {"report": value, "own_output_paths": own_output_paths}
            return canonical_sha256(value)
        except (ValueError, UnicodeDecodeError, RecursionError):
            pass
    normalized = data
    for marker in markers:
        normalized = normalized.replace(os.fsencode(marker), b"<CAPTURES>")
    return hashlib.sha256(normalized).hexdigest() if normalized != data else None


def tree_inventory(root: Path) -> dict:
    """Hash every evidence output under a stable logical path.

    Checked-runner directories (``<label>-<mkdtemp suffix>`` holding report.json and
    engine.log) drop their random suffix; text outputs also get a normalized hash.
    """
    resolved = root.resolve()
    markers = sorted({str(root.absolute()), str(resolved)}, key=len, reverse=True)
    files, logical = {}, {"": ""}
    for directory, dirs, names in os.walk(resolved, followlinks=False):
        parent = Path(directory)
        raw_parent = parent.relative_to(resolved).as_posix() if parent != resolved else ""
        for name in list(dirs):
            child = parent / name
            raw = f"{raw_parent}/{name}" if raw_parent else name
            if child.is_symlink():
                fail("symlink in capture output")
            if excluded_output(raw):
                dirs.remove(name)
                continue
            if CHECKED_RUN.search(name) and (child / "report.json").is_file() and (child / "engine.log").is_file():
                name = CHECKED_RUN.sub("", name)
            logical[raw] = f"{logical[raw_parent]}/{name}" if logical[raw_parent] else name
        for name in names:
            path = parent / name
            raw = f"{raw_parent}/{name}" if raw_parent else name
            if excluded_output(raw) or path.is_symlink():
                continue
            relative = f"{logical[raw_parent]}/{name}" if logical[raw_parent] else name
            if relative in files:  # two checked runs share a label: keep both under raw paths
                relative = raw
            entry = {"sha256": digest(path), "bytes": path.stat().st_size}
            if raw != relative:
                entry["path"] = raw
            if path.suffix.lower() in TEXT_SUFFIXES and entry["bytes"] <= MAX_NORMALIZED_BYTES:
                normalized = normalized_sha256(path, markers)
                if normalized:
                    entry["normalized_sha256"] = normalized
            files[relative] = entry
    return dict(sorted(files.items()))


def metric_bytes_match(value: float, encoded: str) -> bool:
    if type(encoded) is not str or not re.fullmatch(r"[0-9a-f]{16}", encoded):
        return False
    decoded = struct.unpack("<d", bytes.fromhex(encoded))[0]
    # Godot prints -0.0 as 0.0. Hex remains authoritative and distinguishes the
    # signs during comparison; decimal display need only agree numerically.
    return math.isfinite(decoded) and decoded == float(value)


def verify_pixel_metrics(path: Path, suite: str, minimum_checks: int, names: set[str]) -> None:
    data = read_json(path)
    if (not isinstance(data, dict) or data.get("format") != f"openrc-lighting-{suite}-metrics v1"
            or not same_json(data.get("viewport"), [1920, 1080]) or data.get("complete") is not True
            or type(data.get("checks")) is not int or data["checks"] < minimum_checks
            or type(data.get("failures")) is not int or data["failures"] != 0):
        fail("missing, incomplete or failed structured lighting metrics")
    values = data.get("metrics")
    if (not isinstance(values, dict) or set(values) != names
            or any(type(v) not in (int, float) or not math.isfinite(v) for v in values.values())):
        fail("structured lighting metric roster must contain finite numeric values")
    bits = data.get("float64_hex")
    if (not isinstance(bits, dict) or set(bits) != names
            or any(not metric_bytes_match(value, bits[key])
                   for key, value in values.items())):
        fail("structured lighting values do not match their exact float64 bytes")


def verify_segment_metrics(path: Path) -> None:
    verify_pixel_metrics(path, "segment", 12, SEGMENT_METRIC_NAMES)


def verify_lighting_metrics(root: Path) -> None:
    verify_segment_metrics(local_file(root, SEGMENT_METRICS))
    verify_pixel_metrics(local_file(root, SKIN_METRICS), "skin", 13, SKIN_METRIC_NAMES)


def inventory(args) -> None:
    if args.group != "all":
        valid_run_id(args.run_id)
    if args.group in ("all", "quality"):
        verify_lighting_metrics(args.root)
    source = source_identity(args.repo)
    atomic_new_json(args.out, {
        "format": "openrc-capture-inventory v1", "group": args.group,
        "run_id": args.run_id if args.group != "all" else None,
        "commit": source["commit"], "clean": not source["changes"],
        "source_sha256": canonical_sha256(source), "engine_sha256": digest(args.godot),
        "visual_python_sha256": digest(args.visual_python), "config": configuration(),
        "cpu": cpu_model(), "timings": read_timings(args.root), "files": tree_inventory(args.root)})


def kind_of(path: str) -> str:
    suffix = Path(path).suffix.lower()
    return "image" if suffix in IMAGE_SUFFIXES else "log" if suffix in LOG_SUFFIXES else "data"


def compare_groups(args) -> int:
    errors = []
    full = read_json(args.full)
    if not isinstance(full, dict) or full.get("format") != "openrc-capture-inventory v1" or full.get("group") != "all":
        fail("full inventory has an unsupported format")
    if full.get("commit") != args.expect_commit or full.get("clean") is not True:
        errors.append("full capture did not run on the clean expected commit")
    groups, receipts = {}, {}
    for directory in args.groups:
        receipt, inv = read_json(local_file(directory, RECEIPT)), read_json(local_file(directory, INVENTORY))
        start = receipt.get("start") if isinstance(receipt, dict) else None
        group = start.get("group") if isinstance(start, dict) else None
        if group not in GROUP_CHECKS or group in groups:
            fail(f"unexpected or duplicated group in {directory}")
        groups[group], receipts[group] = inv, receipt
        source = start.get("source", {})
        checks = {
            "receipt did not pass": receipt.get("format") == "openrc-experimental-capture-group v1"
                                     and receipt.get("status") == "passed",
            "wrong run ID": start.get("run_id") == args.run_id and inv.get("run_id") == args.run_id,
            "source is not the clean expected commit": source.get("commit") == args.expect_commit
                                                      and source.get("changes") == [],
            "source inputs differ from the full run": canonical_sha256(source) == full.get("source_sha256")
                                                     == inv.get("source_sha256"),
            "engine differs from the full run": start.get("engine_sha256") == full.get("engine_sha256")
                                                == inv.get("engine_sha256"),
            "visual interpreter differs from the full run": receipt.get("visual_python_sha256")
                                                            == full.get("visual_python_sha256")
                                                            == inv.get("visual_python_sha256"),
            "capture configuration differs from the full run": same_json(start.get("config"), full.get("config"))
                                                               and same_json(inv.get("config"), full.get("config")),
            "inventory does not match its receipt": inv.get("group") == group and isinstance(inv.get("files"), dict)
                and {k: v for k, v in receipt.get("outputs", {}).items() if not excluded_output(k)}
                == {v.get("path", k): v.get("sha256") for k, v in inv["files"].items()},
        }
        errors += [f"{group}: {message}" for message, ok in checks.items() if not ok]
    missing = sorted(set(GROUP_CHECKS) - set(groups))
    if missing:
        errors.append(f"missing groups: {missing}")
    owner, overlaps = {}, []
    for group in sorted(groups):
        for path in groups[group].get("files", {}):
            if path in owner:
                overlaps.append(f"{path} ({owner[path]}, {group})")
            else:
                owner[path] = group
    full_files = full.get("files", {})
    counts = {kind: {"identical": 0, "normalized": 0, "different": 0} for kind in ("image", "data", "log")}
    different = {kind: [] for kind in counts}
    for path in sorted(set(owner) & set(full_files)):
        left, right = full_files[path], groups[owner[path]]["files"][path]
        kind = kind_of(path)
        if left["sha256"] == right["sha256"]:
            counts[kind]["identical"] += 1
        elif left.get("normalized_sha256", left["sha256"]) == right.get("normalized_sha256", right["sha256"]):
            counts[kind]["normalized"] += 1
        else:
            counts[kind]["different"] += 1
            # llvmpipe JIT output can depend on host CPU features: mark such differences.
            host = "" if groups[owner[path]].get("cpu") == full.get("cpu") else " [different CPU]"
            different[kind].append(f"{owner[path]}: {path}{host}")
    missing_from_groups = sorted(set(full_files) - set(owner))
    extra_in_groups = sorted(f"{owner[path]}: {path}" for path in set(owner) - set(full_files))
    group_seconds = {g: sum(row[1] for row in inv.get("timings", [])) for g, inv in sorted(groups.items())}
    equivalent = (not errors and not overlaps and not missing_from_groups and not extra_in_groups
                  and not different["image"] and not different["data"])
    report = {
        "format": "openrc-capture-shadow-comparison v1", "production_qualified": False,
        "equivalent": equivalent, "run_id": args.run_id, "commit": args.expect_commit,
        "errors": errors, "overlaps": overlaps[:MAX_LISTED],
        "missing_from_groups": missing_from_groups[:MAX_LISTED], "extra_in_groups": extra_in_groups[:MAX_LISTED],
        "counts": counts, "different": {k: v[:MAX_LISTED] for k, v in different.items()},
        "cpu": {"full": full.get("cpu"), **{g: inv.get("cpu") for g, inv in sorted(groups.items())}},
        "cpu_mismatch_groups": sorted(g for g, inv in groups.items() if inv.get("cpu") != full.get("cpu")),
        "volatility_model": {"skipped_parts": sorted(SKIPPED_PARTS), "volatile_trees": list(VOLATILE_TREES),
                             "volatile_json_keys": sorted(VOLATILE_KEYS),
                             "checked_report_paths": {"log": "engine.log", "report": "report.json"},
                             "checked_report_path_validation": "exact own file paths; validity retained"},
        "metric_policy": {"absolute_tolerance": 0.0, "relative_tolerance": 0.0,
                          "encoding": "full-precision decimal plus validated little-endian float64 hex",
                          "required_metrics": {SEGMENT_METRICS: sorted(SEGMENT_METRIC_NAMES),
                                               SKIN_METRICS: sorted(SKIN_METRIC_NAMES)}},
        "timings_seconds": {"full": sum(row[1] for row in full.get("timings", [])), "groups": group_seconds,
                            "slowest_group": max(group_seconds.values(), default=0)},
    }
    atomic_new_json(args.out, report)
    lines = [f"### Visual group shadow comparison: {'equivalent' if equivalent else 'NOT equivalent'}", "",
             "Shadow evidence only (`production_qualified: false`); the full visual job remains the gate.", "",
             "| Kind | Identical | Path-normalized | Different |", "| --- | ---: | ---: | ---: |"]
    lines += [f"| {k} | {c['identical']} | {c['normalized']} | {c['different']} |" for k, c in counts.items()]
    lines += ["", f"Full run {report['timings_seconds']['full']} s; slowest group "
              f"{report['timings_seconds']['slowest_group']} s (capture phases only, excluding job setup).",
              f"Groups on a different CPU model than the full run: {report['cpu_mismatch_groups'] or 'none'}."]
    for label, values in (("Errors", errors), ("Overlapping outputs", overlaps),
                          ("Missing from groups", missing_from_groups), ("Only in groups", extra_in_groups),
                          ("Different images", different["image"]), ("Different data", different["data"]),
                          ("Different logs (informational)", different["log"])):
        if values:
            lines += ["", f"**{label}** ({len(values)}):", *[f"- `{v}`" for v in values[:20]]]
            if len(values) > 20:
                lines.append(f"- … {len(values) - 20} more in the comparison report")
    print("\n".join(lines))
    return 0 if equivalent else 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("verify-metrics", help="require complete, finite lighting measurements")
    p.add_argument("--root", type=Path, required=True)
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
    p = sub.add_parser("inventory", help="hash one completed full or group capture tree")
    p.add_argument("--repo", type=Path, required=True)
    p.add_argument("--root", type=Path, required=True)
    p.add_argument("--group", choices=["all", *GROUP_CHECKS], required=True)
    p.add_argument("--run-id", default="")
    p.add_argument("--godot", type=Path, required=True)
    p.add_argument("--visual-python", type=Path, required=True)
    p.add_argument("--out", type=Path, required=True)
    p = sub.add_parser("compare", help="compare seven group receipts/inventories with the full inventory")
    p.add_argument("--run-id", required=True)
    p.add_argument("--expect-commit", required=True)
    p.add_argument("--full", type=Path, required=True)
    p.add_argument("--out", type=Path, required=True)
    p.add_argument("--groups", type=Path, nargs="+", required=True)
    args = parser.parse_args()
    try:
        if args.command == "verify-metrics":
            verify_lighting_metrics(args.root)
            return 0
        if args.command == "compare":
            valid_run_id(args.run_id)
            return compare_groups(args)
        {"begin": begin, "finish": finish, "reduce": reduce_groups, "inventory": inventory}[args.command](args)
    except (OSError, ValueError, KeyError, TypeError, AttributeError, subprocess.SubprocessError) as error:
        print(f"experimental capture groups: {error}", file=sys.stderr)
        return 2 if args.command == "compare" else 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
