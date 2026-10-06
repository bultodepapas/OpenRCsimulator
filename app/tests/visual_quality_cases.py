#!/usr/bin/env python3
"""VQ-01b fixed visual case matrix and optional frametime process runner.

The established L1-L4 atmosphere references remain owned by capture.sh and
check_landscape_captures.py. This runner adds real-field, pilot-readability,
and synthetic aircraft views without sweeping old PNGs into the new inventory.

Run the matrix with:
    python3 app/tests/visual_quality_cases.py --app app --godot "$(app/get-godot.sh)" --out app/captures/vq01b
The optional, separate 3 × 10 s warmup + 60 s scripted render sample uses
`--performance-only`; existing physical-flight traces and suites remain its
regression evidence. Use the pinned environment from app/tests/visual-env.sh.
"""
from __future__ import annotations

import argparse
from contextlib import contextmanager
from dataclasses import dataclass
from datetime import datetime, timezone
import fcntl
import hashlib
import json
import math
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
from typing import Any

from capture_runner import run_capture


FORMAT = "openrc-vq-01b-run v1"
FRAME_FORMAT = "openrc-vq-01b-frametime-run v1"
CAPTURE_TIME_S = 1.5
FIELD_REPEATS = 2
PERFORMANCE_REPEATS = 3
PERFORMANCE_WARMUP_S = 10.0
PERFORMANCE_SAMPLE_S = 60.0
POSES = ("level", "inverted", "knife_left", "knife_right", "climb", "dive")
AIRCRAFT = (
    ("stik", "jensen-das-ugly-stik-60"),
    ("extra", "gp-extra-300s-60"),
)
COUNTER_KEYS = ("draw_calls", "primitives", "objects")


@dataclass(frozen=True)
class CaptureCase:
    case_id: str
    family: str
    aircraft: str
    route: str
    arguments: tuple[str, ...]
    expected_scene: str = "field"
    repeat_group: str = ""
    repeat_index: int = 0
    visual_pose: str = ""
    visual_distance_m: float = 0.0
    pilot_visible: bool | None = None
    autozoom: bool | None = None
    kind: str = "flight"
    language: str = ""

    @property
    def filename(self) -> str:
        return f"{self.case_id}.png"


def capture_cases() -> list[CaptureCase]:
    """Return the fixed, ordered capture inventory. IDs are part of the evidence contract."""
    cases: list[CaptureCase] = []

    # Existing L0c captures supply the 30 m trimmed-start view; --alt=3 makes
    # the matching low pass. Each view has the 2×2 autozoom/airplane comparison.
    for range_id, altitude in (("30m", None), ("3m", 3.0)):
        for autozoom in (True, False):
            for visible in (True, False):
                zoom_id = "autozoom-on" if autozoom else "autozoom-off"
                plane_id = "" if visible else "-noplane"
                case_id = f"pilot-{range_id}-{zoom_id}{plane_id}"
                arguments = ["--t=1.5", f"--autozoom={1 if autozoom else 0}", "--shadow=off"]
                if altitude is not None:
                    arguments.append(f"--alt={altitude:g}")
                if not visible:
                    arguments.append("--hide_airplane")
                arguments.append(f"--case={case_id}")
                cases.append(CaptureCase(
                    case_id=case_id, family="pilot-readability", aircraft=AIRCRAFT[0][1],
                    route="physics-fixed", arguments=tuple(arguments),
                    pilot_visible=visible, autozoom=autozoom,
                ))

    # Eight cardinal/horizon views plus the 30 m cenital view, each captured
    # in two fresh Godot processes so PNG and all render counters can be paired.
    field_views = [(azimuth, elevation, None) for azimuth in (0, 90, 180, 270) for elevation in (0, 10)]
    field_views.append((0, -90, 30))
    for azimuth, elevation, look_alt in field_views:
        view_id = "field-top30m" if elevation == -90 else f"field-az{azimuth}-el{elevation}"
        group = view_id
        for repeat in range(1, FIELD_REPEATS + 1):
            case_id = f"{view_id}-repeat{repeat}"
            arguments = [
                "--t=1.5", "--autozoom=0", "--shadow=off", "--hide_airplane",
                f"--look_az={azimuth}", f"--look_el={elevation}", f"--case={case_id}",
            ]
            if look_alt is not None:
                arguments.append(f"--look_alt={look_alt}")
            cases.append(CaptureCase(
                case_id=case_id, family="field-repeat", aircraft=AIRCRAFT[0][1],
                route="physics-fixed", arguments=tuple(arguments), repeat_group=group,
                repeat_index=repeat, pilot_visible=False, autozoom=False,
            ))

    # Both model builders use the same pilot camera, fixed FOV, light and
    # scripted clock. These are render-only inspection fixtures, not flights.
    for short_name, aircraft_id in AIRCRAFT:
        for distance in (20, 50, 100):
            for pose in POSES:
                case_id = f"synthetic-{short_name}-{distance}m-{pose}"
                arguments = (
                    "--scripted", f"--visual_pose={pose}",
                    f"--visual_distance={distance}", "--autozoom=0", "--shadow=off",
                    f"--aircraft={aircraft_id}", "--t=1.5", f"--case={case_id}",
                )
                cases.append(CaptureCase(
                    case_id=case_id, family="synthetic-attitude", aircraft=aircraft_id,
                    route="synthetic-inspection", arguments=arguments,
                    visual_pose=pose, visual_distance_m=float(distance),
                    pilot_visible=True, autozoom=False,
                ))

    # Four UI captures include Home's initial frame and the real Home Fly route
    # in both source and translated language.
    for screen, route in (("home", "standalone-home"), ("flight", "interactive-home-fly")):
        for language in ("en", "es"):
            case_id = f"ui-{screen}-{language}"
            cases.append(CaptureCase(
                case_id=case_id, family="ui-route", aircraft=AIRCRAFT[0][1],
                route=route, arguments=(), expected_scene=screen,
                kind="ui", language=language,
            ))

    return cases


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def input_hashes(repo_root: Path) -> dict[str, str]:
    """Hash the source tree and model assets used by the capture, never captures/caches."""
    repo_root = Path(repo_root).resolve()
    paths: set[Path] = set()
    excluded = {".godot", "__pycache__", "captures"}
    for relative in ("app", "assets/aircraft"):
        base = repo_root / relative
        if not base.exists():
            continue
        for path in base.rglob("*"):
            if not path.is_file() or any(part in excluded for part in path.relative_to(repo_root).parts):
                continue
            if path.suffix in (".uid", ".import", ".pyc"):
                continue
            paths.add(path)
    for relative in ("docs/VISUAL-QUALITY-PLAN.md",):
        path = repo_root / relative
        if path.is_file():
            paths.add(path)
    return {path.relative_to(repo_root).as_posix(): sha256_file(path) for path in sorted(paths)}


def code_revision(repo_root: Path) -> tuple[str, str]:
    """Return the caller's revision override or a git revision marked dirty when needed."""
    override = os.environ.get("OPENRC_CODE_REVISION", "").strip()
    if override:
        return override, "environment:OPENRC_CODE_REVISION"
    try:
        commit = subprocess.run(
            ["git", "-C", str(repo_root), "rev-parse", "HEAD"],
            check=True, capture_output=True, text=True, timeout=5,
        ).stdout.strip()
        status = subprocess.run(
            ["git", "-C", str(repo_root), "status", "--porcelain", "--untracked-files=all"],
            check=True, capture_output=True, text=True, timeout=5,
        ).stdout
        if status:
            commit += "+dirty"
        return commit, "git:rev-parse+status"
    except (OSError, subprocess.SubprocessError):
        return "unavailable", "no git metadata or override"


def _number(value: Any, label: str) -> float:
    if type(value) not in (int, float) or not math.isfinite(float(value)):
        raise RuntimeError(f"{label} must be a finite number")
    return float(value)


def validate_capture_evidence(case: CaptureCase, manifest: dict[str, Any]) -> dict[str, Any]:
    """Reject captures whose native, rendered-state evidence disagrees with the fixed case."""
    evidence = manifest.get("visual_evidence")
    if not isinstance(evidence, dict) or evidence.get("format") != "openrc-visual-evidence v1":
        raise RuntimeError(f"{case.case_id}: missing openrc-visual-evidence v1")
    if evidence.get("case_id") != case.case_id:
        raise RuntimeError(f"{case.case_id}: native case_id mismatch")
    if evidence.get("aircraft") != case.aircraft:
        raise RuntimeError(f"{case.case_id}: native aircraft mismatch")
    if evidence.get("route") != case.route:
        raise RuntimeError(f"{case.case_id}: route {evidence.get('route')!r}, expected {case.route!r}")
    if manifest.get("capture_scene") != case.expected_scene:
        raise RuntimeError(f"{case.case_id}: capture scene {manifest.get('capture_scene')!r}, expected {case.expected_scene!r}")

    if evidence.get("visual_pose", "") != case.visual_pose:
        raise RuntimeError(f"{case.case_id}: visual pose metadata mismatch")
    requested_distance = _number(evidence.get("visual_distance_m", 0), f"{case.case_id} visual_distance_m")
    if case.visual_pose:
        actual_distance = _number(evidence.get("distance_to_pilot_m"), f"{case.case_id} distance_to_pilot_m")
        if abs(requested_distance - case.visual_distance_m) > 1e-4:
            raise RuntimeError(f"{case.case_id}: requested distance metadata mismatch")
        if abs(actual_distance - case.visual_distance_m) > 1e-4:
            raise RuntimeError(f"{case.case_id}: actual distance {actual_distance:.6f} m, expected {case.visual_distance_m:.6f} m")
        if not case.visual_distance_m:
            raise RuntimeError(f"{case.case_id}: synthetic case has no requested distance")

    camera = evidence.get("camera")
    if not isinstance(camera, dict):
        raise RuntimeError(f"{case.case_id}: missing camera evidence")
    fov = _number(camera.get("fov_deg"), f"{case.case_id} camera.fov_deg")
    if not 1.0 <= fov <= 179.0:
        raise RuntimeError(f"{case.case_id}: invalid camera FOV {fov}")
    if type(camera.get("autozoom")) is not bool:
        raise RuntimeError(f"{case.case_id}: camera.autozoom must be boolean")
    if case.autozoom is not None and camera["autozoom"] != case.autozoom:
        raise RuntimeError(f"{case.case_id}: autozoom metadata mismatch")
    _number(evidence.get("clock_s"), f"{case.case_id} clock_s")
    if abs(float(evidence["clock_s"]) - CAPTURE_TIME_S) > 1e-6:
        raise RuntimeError(f"{case.case_id}: clock is not fixed at {CAPTURE_TIME_S:g} s")
    _number(evidence.get("exposure"), f"{case.case_id} exposure")
    if not isinstance(evidence.get("pose"), dict):
        raise RuntimeError(f"{case.case_id}: missing rendered pose")
    if not isinstance(evidence.get("light"), dict):
        raise RuntimeError(f"{case.case_id}: missing light evidence")
    if not isinstance(evidence.get("state"), dict) or evidence["state"].get("shadow") != "off":
        raise RuntimeError(f"{case.case_id}: expected airplane shadow mode off")
    if case.pilot_visible is not None and evidence["state"].get("aircraft_visible") is not case.pilot_visible:
        raise RuntimeError(f"{case.case_id}: airplane visibility metadata mismatch")
    if not isinstance(evidence.get("seed"), dict):
        raise RuntimeError(f"{case.case_id}: missing seed/determinism metadata")
    provenance = evidence.get("provenance")
    if not isinstance(provenance, dict) or not isinstance(provenance.get("source_sha256"), dict):
        raise RuntimeError(f"{case.case_id}: missing source hash provenance")
    revision = str(provenance.get("code_revision", "")).strip()
    if not revision:
        raise RuntimeError(f"{case.case_id}: missing code revision provenance")
    return evidence


def validate_ui_evidence(case: CaptureCase, manifest: dict[str, Any], output: Path) -> dict[str, Any]:
    if manifest.get("format") != "openrc-ui-capture v2" or manifest.get("producer") != "capture_ui":
        raise RuntimeError(f"{case.case_id}: expected native capture_ui v2 evidence")
    if manifest.get("image") != output.name or manifest.get("sha256") != sha256_file(output):
        raise RuntimeError(f"{case.case_id}: UI manifest image/hash mismatch")
    if manifest.get("size") != [1280, 720] or manifest.get("capture_scene") != case.expected_scene:
        raise RuntimeError(f"{case.case_id}: UI manifest size/screen mismatch")
    evidence = manifest.get("ui_evidence")
    if not isinstance(evidence, dict):
        raise RuntimeError(f"{case.case_id}: missing native UI runtime evidence")
    if evidence.get("state") != case.expected_scene or evidence.get("route") != case.route:
        raise RuntimeError(f"{case.case_id}: UI state/route mismatch")
    if evidence.get("language") != case.language:
        raise RuntimeError(f"{case.case_id}: UI language mismatch")
    viewport = evidence.get("viewport")
    if not isinstance(viewport, dict):
        raise RuntimeError(f"{case.case_id}: missing UI viewport evidence")
    for key in ("camera_3d_count", "world_environment_count"):
        count = viewport.get(key)
        if type(count) is not int or count < 0:
            raise RuntimeError(f"{case.case_id}: invalid UI viewport {key}")
    if case.expected_scene == "flight":
        if viewport["camera_3d_count"] != 1 or viewport["world_environment_count"] != 1:
            raise RuntimeError(f"{case.case_id}: expected one flight camera and WorldEnvironment")
        if not viewport.get("active_camera"):
            raise RuntimeError(f"{case.case_id}: missing active flight camera path")
        flight_evidence = evidence.get("visual")
        if not isinstance(flight_evidence, dict) or not isinstance(flight_evidence.get("camera"), dict):
            raise RuntimeError(f"{case.case_id}: missing actual flight capture evidence")
        flight_clock = _number(flight_evidence.get("clock_s"), f"{case.case_id} flight clock")
        if abs(flight_clock - CAPTURE_TIME_S) > 1e-6:
            raise RuntimeError(f"{case.case_id}: flight image is not pinned to 1.5 s")
    return evidence


def _counter_signature(manifest: dict[str, Any]) -> dict[str, Any]:
    signature: dict[str, Any] = {}
    for key in COUNTER_KEYS:
        values = manifest.get(key)
        if not isinstance(values, dict):
            raise RuntimeError(f"missing render counter group {key}")
        signature[key] = {}
        for pass_name in ("visible", "shadow"):
            count = values.get(pass_name)
            if type(count) is not int or count < 0:
                raise RuntimeError(f"invalid render counter {key}.{pass_name}")
            signature[key][pass_name] = count
    return signature


def validate_field_parity(entries: list[dict[str, Any]]) -> list[dict[str, Any]]:
    groups: dict[str, list[dict[str, Any]]] = {}
    for entry in entries:
        if entry.get("family") == "field-repeat":
            groups.setdefault(str(entry["repeat_group"]), []).append(entry)
    if len(groups) != 9:
        raise RuntimeError(f"field repeat groups: expected 9, got {len(groups)}")
    checks: list[dict[str, Any]] = []
    for group, values in sorted(groups.items()):
        values.sort(key=lambda item: item["repeat_index"])
        if [item["repeat_index"] for item in values] != [1, 2]:
            raise RuntimeError(f"{group}: expected exactly repeats 1 and 2")
        first, second = values
        if first["sha256"] != second["sha256"]:
            raise RuntimeError(f"{group}: repeated PNG hashes differ")
        if first["render_counters"] != second["render_counters"]:
            raise RuntimeError(f"{group}: repeated render counters differ")
        checks.append({
            "view": group, "repeat_images_identical": True,
            "render_counters_identical": True,
            "sha256": first["sha256"], "render_counters": first["render_counters"],
        })
    return checks


def validate_png_inventory(output_dir: Path, cases: list[CaptureCase]) -> None:
    expected = {case.filename for case in cases}
    present = {path.name for path in Path(output_dir).glob("*.png")}
    if present != expected:
        raise RuntimeError(
            f"PNG inventory mismatch: missing={sorted(expected - present)}, extra={sorted(present - expected)}"
        )


def _same_json_value(left: Any, right: Any, tolerance: float = 1e-9) -> bool:
    if type(left) in (int, float) and type(right) in (int, float):
        return math.isfinite(float(left)) and math.isfinite(float(right)) and abs(float(left) - float(right)) <= tolerance
    if isinstance(left, dict) and isinstance(right, dict):
        return left.keys() == right.keys() and all(_same_json_value(left[key], right[key], tolerance) for key in left)
    if isinstance(left, list) and isinstance(right, list):
        return len(left) == len(right) and all(_same_json_value(a, b, tolerance) for a, b in zip(left, right))
    return left == right


def validate_synthetic_parity(entries: list[dict[str, Any]]) -> dict[str, Any]:
    synthetic = [entry for entry in entries if entry.get("family") == "synthetic-attitude"]
    expected = len(AIRCRAFT) * 3 * len(POSES)
    if len(synthetic) != expected:
        raise RuntimeError(f"synthetic inventory: expected {expected}, got {len(synthetic)}")
    if len({entry["case_id"] for entry in synthetic}) != expected:
        raise RuntimeError("synthetic case IDs are not unique")
    reference: dict[str, Any] | None = None
    for entry in sorted(synthetic, key=lambda item: item["case_id"]):
        evidence = entry["visual_evidence"]
        camera = evidence["camera"]
        current = {"fov_deg": camera["fov_deg"], "autozoom": camera["autozoom"],
                   "exposure": evidence["exposure"], "light": evidence["light"]}
        if current["autozoom"] is not False:
            raise RuntimeError(f"{entry['case_id']}: synthetic camera autozoom must be off")
        if reference is None:
            reference = current
        elif not _same_json_value(current, reference):
            raise RuntimeError(f"{entry['case_id']}: synthetic light/FOV/exposure differs from the shared fixture")
    return {
        "case_count": expected,
        "aircraft": [aircraft_id for _, aircraft_id in AIRCRAFT],
        "distances_m": [20, 50, 100], "poses": list(POSES),
        "shared_light_fov_exposure": True,
        "camera": reference,
    }


def build_capture_command(app_dir: Path, godot: str, xvfb: str, output: Path,
                          case: CaptureCase) -> list[str]:
    if case.kind == "ui":
        return [
            xvfb, "-a", "-s", "-screen 0 1280x720x24",
            godot, "--path", str(Path(app_dir).resolve()),
            "--rendering-driver", "opengl3", "--audio-driver", "Dummy",
            "--script", "res://tests/capture_ui.gd", "--",
            f"--out={Path(output).resolve()}", f"--lang={case.language}",
            f"--screen={case.expected_scene}",
        ]
    return [
        xvfb, "-a", "-s", "-screen 0 1280x720x24",
        godot, "--path", str(Path(app_dir).resolve()),
        "--rendering-driver", "opengl3", "--audio-driver", "Dummy", "--", "--capture",
        *case.arguments, f"--out={Path(output).resolve()}",
    ]


def _capture_record(case: CaptureCase, output: Path, manifest: dict[str, Any]) -> dict[str, Any]:
    if case.kind == "ui":
        evidence = validate_ui_evidence(case, manifest, output)
        return {
            "case_id": case.case_id, "family": case.family, "kind": "ui",
            "image": output.name, "sha256": sha256_file(output),
            "capture_manifest": output.with_suffix(".json").name,
            "capture_manifest_sha256": sha256_file(output.with_suffix(".json")),
            "capture_scene": manifest["capture_scene"], "route": evidence["route"],
            "language": evidence["language"], "ui_evidence": evidence,
        }
    if manifest.get("image") != output.name:
        raise RuntimeError(f"{case.case_id}: native manifest image mismatch")
    digest = sha256_file(output)
    if manifest.get("sha256") != digest:
        raise RuntimeError(f"{case.case_id}: native manifest PNG hash mismatch")
    evidence = validate_capture_evidence(case, manifest)
    return {
        "case_id": case.case_id, "family": case.family,
        "image": output.name, "sha256": digest,
        "capture_manifest": output.with_suffix(".json").name,
        "capture_manifest_sha256": sha256_file(output.with_suffix(".json")),
        "capture_scene": manifest["capture_scene"], "route": evidence["route"],
        "aircraft": evidence["aircraft"],
        "repeat_group": case.repeat_group, "repeat_index": case.repeat_index,
        "render_counters": _counter_signature(manifest),
        "visual_evidence": evidence,
    }


def _write_json_atomic(path: Path, data: dict[str, Any]) -> None:
    temp = path.with_name(path.name + ".tmp")
    temp.write_text(json.dumps(data, indent=2, sort_keys=True, allow_nan=False) + "\n", encoding="utf-8")
    temp.replace(path)


@contextmanager
def _output_lock(output_dir: Path):
    lock_path = output_dir / ".visual-quality-cases.lock"
    with lock_path.open("a", encoding="utf-8") as stream:
        try:
            fcntl.flock(stream.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise RuntimeError(f"another VQ-01b run owns {output_dir}") from error
        try:
            yield
        finally:
            fcntl.flock(stream.fileno(), fcntl.LOCK_UN)


def run_visual_quality_cases(app_dir: Path, godot: str, output_dir: Path,
                             xvfb: str = "xvfb-run", timeout: float = 120.0) -> dict[str, Any]:
    """Produce the complete 66-case matrix and publish its exact set manifest last."""
    app_dir = Path(app_dir).resolve()
    repo_root = app_dir.parent
    output_dir = Path(output_dir).resolve()
    if timeout <= 0 or not math.isfinite(timeout):
        raise ValueError("capture timeout must be finite and positive")
    if not Path(godot).is_file() and shutil.which(godot) is None:
        raise ValueError(f"Godot executable not found: {godot}")
    if shutil.which(xvfb) is None and not Path(xvfb).is_file():
        raise ValueError(f"display runner not found: {xvfb}")
    output_dir.mkdir(parents=True, exist_ok=True)
    with _output_lock(output_dir):
        return _run_visual_quality_cases_locked(app_dir, repo_root, godot, output_dir, xvfb, timeout)


def _run_visual_quality_cases_locked(app_dir: Path, repo_root: Path, godot: str,
                                     output_dir: Path, xvfb: str, timeout: float) -> dict[str, Any]:
    complete_path = output_dir / "visual-quality-run-manifest.json"
    complete_path.unlink(missing_ok=True)
    os.environ.setdefault("LP_NUM_THREADS", "1")
    revision, revision_source = code_revision(repo_root)
    if revision != "unavailable":
        os.environ["OPENRC_CODE_REVISION"] = revision
    initial_input_hashes = input_hashes(repo_root)

    cases = capture_cases()
    case_ids = [case.case_id for case in cases]
    if len(case_ids) != len(set(case_ids)):
        raise RuntimeError("fixed capture inventory has duplicate case IDs")
    if (sum(case.family == "pilot-readability" for case in cases) != 8
            or sum(case.family == "field-repeat" for case in cases) != 18
            or sum(case.family == "synthetic-attitude" for case in cases) != 36
            or sum(case.family == "ui-route" for case in cases) != 4
            or len(cases) != 66):
        raise RuntimeError("fixed capture inventory no longer matches VQ-01b's 8+18+36+4 contract")

    entries: list[dict[str, Any]] = []
    for index, case in enumerate(cases, start=1):
        output = output_dir / case.filename
        command = build_capture_command(app_dir, godot, xvfb, output, case)
        print(f"VQ-01b capture {index}/{len(cases)} {case.case_id}", flush=True)
        try:
            manifest = run_capture(command, output, case.kind, case.expected_scene, timeout=timeout)
            entries.append(_capture_record(case, output, manifest))
        except Exception as error:
            raise RuntimeError(f"case {index}/{len(cases)} {case.case_id} failed: {error}") from error

    if [entry["case_id"] for entry in entries] != case_ids:
        raise RuntimeError("completed capture inventory differs from fixed case order")
    validate_png_inventory(output_dir, cases)
    field_parity = validate_field_parity(entries)
    synthetic_parity = validate_synthetic_parity(entries)

    # Reuse the existing L0c airplane-vs-background measurements. The 30 m and
    # 3 m results are recorded without adding new pass/fail thresholds.
    from compare_captures import readability

    readability_path = output_dir / "pilot-readability.json"
    readability_data = readability(str(output_dir), str(readability_path))
    expected_readability = {
        "pilot-30m-autozoom-on.png", "pilot-30m-autozoom-off.png",
        "pilot-3m-autozoom-on.png", "pilot-3m-autozoom-off.png",
    }
    if set(readability_data) != expected_readability:
        raise RuntimeError(f"pilot readability output inventory mismatch: {sorted(readability_data)}")
    if any(int(value.get("pixels", 0)) <= 0 for value in readability_data.values()):
        raise RuntimeError("a pilot airplane/background pair has no visible difference")

    final_input_hashes = input_hashes(repo_root)
    if final_input_hashes != initial_input_hashes:
        raise RuntimeError("source/assets changed during the VQ-01b run; no complete manifest was published")
    manifest = {
        "format": FORMAT,
        "complete": True,
        "created_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "code_revision": revision,
        "code_revision_source": revision_source,
        "input_sha256": initial_input_hashes,
        "harness_sha256": sha256_file(Path(__file__).resolve()),
        "app": str(app_dir),
        "godot": str(Path(godot).resolve()) if Path(godot).exists() else godot,
        "rendering_driver": "opengl3",
        "display": {"size": [1280, 720], "runner": xvfb},
        "capture_timeout_s": timeout,
        "reference_suite": {
            "runner": "app/capture.sh",
            "checker": "app/tests/check_landscape_captures.py",
            "implementation_report": "docs/research/visual-quality-implementation/VQ-01a/README.md",
            "note": "The L1-L4 atmosphere captures stay in their existing suite; this matrix does not rerun or replace them.",
        },
        "inventory": {
            "expected_case_ids": case_ids,
            "capture_count": len(entries),
            "counts_by_family": {
                family: sum(case.family == family for case in cases)
                for family in ("pilot-readability", "field-repeat", "synthetic-attitude", "ui-route")
            },
        },
        "field_repeat_parity": field_parity,
        "synthetic_parity": synthetic_parity,
        "pilot_readability": readability_data,
        "pilot_readability_sha256": sha256_file(readability_path),
        "captures": entries,
    }
    _write_json_atomic(complete_path, manifest)
    return manifest


def _run_guarded_process(command: list[str], log_path: Path, timeout: float) -> None:
    """Run one frametime process with the same process-group timeout and error guards as capture_runner."""
    if timeout <= 0 or not math.isfinite(timeout):
        raise ValueError("process timeout must be finite and positive")
    log_path.parent.mkdir(parents=True, exist_ok=True)
    try:
        with log_path.open("w", encoding="utf-8") as stream:
            process = subprocess.Popen(command, stdout=stream, stderr=subprocess.STDOUT, start_new_session=True)
            try:
                status = process.wait(timeout=timeout)
            except subprocess.TimeoutExpired as error:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
                raise RuntimeError(f"process timed out after {timeout:g}s") from error
        log_text = log_path.read_text(encoding="utf-8", errors="replace")
        if status != 0:
            raise RuntimeError(f"process exited {status}")
        import re
        if re.search(r"^\s*(?:(?:SCRIPT|SHADER)\s+)?ERROR:", log_text, re.M):
            raise RuntimeError("engine error during frametime run")
    except Exception as error:
        raise RuntimeError(f"{log_path.name}: {error}; log: {log_path}") from error


def _report_number(report: dict[str, Any], keys: tuple[str, ...], label: str) -> float:
    for key in keys:
        if key in report:
            return _number(report[key], f"frametime {label}")
    raise RuntimeError(f"frametime report missing {label} ({' or '.join(keys)})")


def validate_frametime_report(report: dict[str, Any], route: str,
                              warmup_s: float = PERFORMANCE_WARMUP_S,
                              sample_s: float = PERFORMANCE_SAMPLE_S,
                              case_id: str | None = None) -> dict[str, Any]:
    """Require complete raw samples and allow a final frame to cross the sample boundary."""
    if report.get("format") != "openrc-frametimes v2":
        raise RuntimeError("frametime report must use openrc-frametimes v2")
    if report.get("complete") is not True:
        raise RuntimeError("frametime report is not marked complete")
    if report.get("route") != route:
        raise RuntimeError(f"frametime route {report.get('route')!r}, expected {route!r}")
    actual_case_id = report.get("case_id")
    if not isinstance(actual_case_id, str) or not actual_case_id.strip():
        raise RuntimeError("frametime report is missing case_id")
    if case_id is not None and actual_case_id != case_id:
        raise RuntimeError(f"frametime case_id {actual_case_id!r}, expected {case_id!r}")
    for key in ("preset", "backend"):
        value = report.get(key)
        if not isinstance(value, str) or not value.strip():
            raise RuntimeError(f"frametime report is missing nonempty {key}")
    recorded_warmup = _report_number(report, ("requested_warmup_s", "warmup_s", "warmup_seconds"), "warmup")
    recorded_sample = _report_number(report, ("requested_sample_s", "sample_s", "duration_s", "requested_duration_s"), "sample duration")
    if abs(recorded_warmup - warmup_s) > 1e-9 or abs(recorded_sample - sample_s) > 1e-9:
        raise RuntimeError("frametime report does not record the requested warmup/sample duration")
    deltas = report.get("frame_deltas_s", report.get("frame_deltas"))
    if not isinstance(deltas, list) or not deltas:
        raise RuntimeError("frametime report is missing raw frame deltas")
    values = [_number(delta, "frame delta") for delta in deltas]
    if any(delta <= 0 for delta in values):
        raise RuntimeError("frametime report contains a non-positive frame delta")
    frames = report.get("frames")
    if type(frames) is not int or frames != len(values):
        raise RuntimeError("frametime frame count does not match raw frame deltas")
    raw_arrays = (
        "engine_frame_deltas_s", "frame_wall_usec", "frame_end_monotonic_usec",
        "sim_time_s", "sim_tick", "physics_step_usec", "fps_monitor",
        "process_time_s", "physics_process_time_s", "object_count", "node_count",
        "draw_calls", "primitives", "physics_3d_active_objects", "physics_3d_collision_pairs",
    )
    raw_metric_lengths: dict[str, int] = {"frame_deltas_s": frames}
    for key in raw_arrays:
        if key not in report:
            continue
        samples = report[key]
        if not isinstance(samples, list) or len(samples) != frames:
            raise RuntimeError(f"frametime raw metric {key} length does not match frames")
        raw_metric_lengths[key] = len(samples)
        for value in samples:
            _number(value, f"raw metric {key}")
    timestamps = report.get("frame_end_monotonic_usec")
    if timestamps is not None and any(right <= left for left, right in zip(timestamps, timestamps[1:])):
        raise RuntimeError("frametime monotonic timestamps are not strictly increasing")
    measured = sum(values)
    reported = _report_number(report, ("wall_seconds", "sampled_seconds", "raw_duration_s", "seconds"), "raw sample duration")
    if abs(measured - reported) > max(1e-6, len(values) * 1e-12):
        raise RuntimeError("frametime raw duration does not equal the sum of frame deltas")
    if reported < sample_s:
        raise RuntimeError(f"frametime raw duration {reported:.3f}s is shorter than the requested {sample_s:g}s sample")
    if reported - values[-1] >= sample_s + 1e-6:
        raise RuntimeError("frametime sample contains more than one frame interval beyond the requested duration")
    return {
        "route": route, "case_id": actual_case_id,
        "preset": report["preset"], "backend": report["backend"],
        "requested_warmup_s": warmup_s,
        "requested_sample_s": sample_s, "frames": frames,
        "raw_sample_seconds": reported,
        "frame_deltas_s": values,
        "raw_metric_lengths": raw_metric_lengths,
    }


def build_frametime_command(app_dir: Path, godot: str, xvfb: str,
                            report_path: Path, route: str, warmup_s: float,
                            sample_s: float, case_id: str = "scripted-fixed") -> list[str]:
    args = [f"--frametimes={Path(report_path).resolve()}", f"--t={sample_s:g}", f"--warmup={warmup_s:g}",
            f"--case={case_id}"]
    if route == "scripted-fixed":
        args.append("--scripted")
    elif route != "live-input":
        raise ValueError(f"unsupported frametime route: {route}")
    return [
        xvfb, "-a", "-s", "-screen 0 1280x720x24",
        godot, "--path", str(Path(app_dir).resolve()),
        "--rendering-driver", "opengl3", "--audio-driver", "Dummy", "--", *args,
    ]


def run_performance_cases(app_dir: Path, godot: str, output_dir: Path,
                          xvfb: str = "xvfb-run", timeout: float = 90.0,
                          repeats: int = PERFORMANCE_REPEATS,
                          warmup_s: float = PERFORMANCE_WARMUP_S,
                          sample_s: float = PERFORMANCE_SAMPLE_S) -> dict[str, Any]:
    """Run three fresh 10 s warmup + 60 s samples of the deterministic scripted route."""
    app_dir = Path(app_dir).resolve()
    repo_root = app_dir.parent
    output_dir = Path(output_dir).resolve() / "performance"
    if repeats != 3 or warmup_s != 10.0 or sample_s != 60.0:
        raise ValueError("VQ-01b performance contract is fixed at 3 × (10 s warmup + 60 s sample)")
    if timeout <= warmup_s + sample_s:
        raise ValueError("frametime timeout must exceed the 10 s warmup + 60 s sample")
    if not Path(godot).is_file() and shutil.which(godot) is None:
        raise ValueError(f"Godot executable not found: {godot}")
    if shutil.which(xvfb) is None and not Path(xvfb).is_file():
        raise ValueError(f"display runner not found: {xvfb}")
    output_dir.mkdir(parents=True, exist_ok=True)
    with _output_lock(output_dir):
        return _run_performance_cases_locked(app_dir, repo_root, godot, output_dir,
                                             xvfb, timeout, repeats, warmup_s, sample_s)


def _run_performance_cases_locked(app_dir: Path, repo_root: Path, godot: str,
                                  output_dir: Path, xvfb: str, timeout: float,
                                  repeats: int, warmup_s: float, sample_s: float) -> dict[str, Any]:
    complete_path = output_dir / "performance-run-manifest.json"
    complete_path.unlink(missing_ok=True)
    os.environ.setdefault("LP_NUM_THREADS", "1")
    revision, revision_source = code_revision(repo_root)
    if revision != "unavailable":
        os.environ["OPENRC_CODE_REVISION"] = revision
    initial_input_hashes = input_hashes(repo_root)

    reports: list[dict[str, Any]] = []
    for route in ("scripted-fixed",):
        for repeat in range(1, repeats + 1):
            name = f"frametimes-{route}-{repeat}.json"
            case_id = f"{route}-repeat{repeat}"
            report_path = output_dir / name
            report_path.unlink(missing_ok=True)
            log_path = report_path.with_suffix(".log")
            command = build_frametime_command(app_dir, godot, xvfb, report_path, route,
                                              warmup_s, sample_s, case_id)
            try:
                print(f"VQ-01b frametime {repeat}/{repeats} {route}", flush=True)
                _run_guarded_process(command, log_path, timeout)
                report = json.loads(report_path.read_text(encoding="utf-8"))
                evidence = validate_frametime_report(report, route, warmup_s, sample_s, case_id)
                reports.append({
                    "case_id": case_id, "route": route,
                    "repeat": repeat, "report": name,
                    "report_sha256": sha256_file(report_path), "log": log_path.name,
                    "log_sha256": sha256_file(log_path), "evidence": evidence,
                })
            except Exception as error:
                report_path.unlink(missing_ok=True)
                raise RuntimeError(f"frametime case {route} repeat {repeat} failed: {error}") from error
    final_input_hashes = input_hashes(repo_root)
    if final_input_hashes != initial_input_hashes:
        raise RuntimeError("source/assets changed during the performance run; no complete manifest was published")
    manifest = {
        "format": FRAME_FORMAT, "complete": True,
        "created_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "code_revision": revision, "code_revision_source": revision_source,
        "input_sha256": initial_input_hashes,
        "harness_sha256": sha256_file(Path(__file__).resolve()),
        "warmup_s": warmup_s, "sample_s": sample_s, "repeats_per_route": repeats,
        "routes": ["scripted-fixed"], "process_count": len(reports),
        "physical_route_note": "Physical flight behavior remains checked by the existing trace and flight suites; it is not labelled as a fixed render replay.",
        "warning": "Xvfb/llvmpipe frametimes are harness evidence, not hardware performance approval.",
        "reports": reports,
    }
    _write_json_atomic(complete_path, manifest)
    return manifest


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, required=True, help="Godot app directory")
    parser.add_argument("--godot", required=True, help="Godot 4.7 executable")
    parser.add_argument("--out", type=Path, required=True, help="dedicated output directory under app/captures")
    parser.add_argument("--xvfb", default="xvfb-run", help="display runner (default: xvfb-run)")
    parser.add_argument("--timeout", type=float, default=120.0, help="per-process timeout in seconds")
    parser.add_argument("--performance-only", action="store_true",
                        help="run three optional scripted frametime processes instead of image captures")
    args = parser.parse_args(argv)
    try:
        if args.performance_only:
            manifest = run_performance_cases(args.app, args.godot, args.out, args.xvfb,
                                             timeout=max(args.timeout, PERFORMANCE_WARMUP_S + PERFORMANCE_SAMPLE_S + 10.0))
            print(f"complete: {manifest['process_count']} frametime reports at {args.out / 'performance'}")
        else:
            manifest = run_visual_quality_cases(args.app, args.godot, args.out, args.xvfb, args.timeout)
            print(f"complete: {manifest['inventory']['capture_count']} captures; manifest {args.out / 'visual-quality-run-manifest.json'}")
    except (OSError, ValueError, RuntimeError, json.JSONDecodeError) as error:
        print(f"VQ-01b failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
