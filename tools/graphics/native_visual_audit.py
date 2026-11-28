"""Capture a matched baseline/candidate pair on an isolated Linux graphics runner.

Inspect --plan without a display or engine. Execution temporarily installs reviewed
shader bytes in a clean disposable checkout. The baseline runtime is the pinned
app/assets tree, rendered with the same candidate-side evidence harness as the candidate.
"""
import argparse
from contextlib import contextmanager
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import re
import signal
import statistics
import subprocess
import sys
import tempfile
import threading
import time

BASE = "71306784a250d634854f0c8bab3a927cc46a61b8"
ROOT = Path(__file__).resolve().parents[2]
SHADERS = {
    "app/render/lake/water.gdshader",
    "app/render/lens/lens_film.gdshader",
    "app/render/ground.gdshader",
    "app/render/landscape_upgrade/countryside_surface.gdshader",
    "app/render/windsock_deformation.gdshaderinc",
    "app/render/weather/rain_curtain.gdshader",
    "app/scenery/building_roofs.gdshader",
    "app/scenery/pit_shelter_roof.gdshader",
    "app/render/world/moon_disc.gdshaderinc",
    "app/assets/vehicle-paints/turbo-lumber-evolution/aserradero.gdshader",
}
FIELD = "app/tests/capture_landscape_upgrade.gd"
CASES = ("lake_shore", "lake_overview", "pilot_north", "plain_highway", "plain_field_entry", "postcard_pavilion")
CONTROL_IDS = ("dirt_light_off", "dirt_specular_000", "dirt_specular_035", "dirt_specular_050",
               "lens_disabled", "lens_curtain_partial", "lens_curtain_held")
ROOF_FOOTPRINTS = {
    "pavilion_normal_footprint": ("res://scenery/building_roofs.gdshader", "Roof_prop_pavilion_00_slate", 2.24587e-7),
    "pit_normal_footprint": ("res://scenery/pit_shelter_roof.gdshader", "PitShelter_prop_pit-shelters_00", 2.75892e-7),
}
DETAIL = {
    "controls": ("tools/graphics/capture_native_shader_controls.gd", CONTROL_IDS),
    "moon": ("tools/world/moon_capture.gd", ("full_high-close", "full_high-wide")),
    "roofs": ("tools/landscape/capture_building_roofs.gd",
              ("club_air", "pavilion_pilot", "pavilion_roof", "shed_roof", "farm_roofs", *ROOF_FOOTPRINTS)),
    "windsock": ("tools/ground/capture_windsock_detail.gd", ("whole", "fabric", "throat", "base")),
    "storm": ("tools/atmosphere/storm_bank_capture.gd", ("distant_storm-day-pilot-fov50", "distant_storm-day-pilot-fov25")),
    "paint": ("tools/skins/paint_preview.gd", ("turbo-lumber-evolution_aserradero_front34", "turbo-lumber-evolution_aserradero_top")),
}
DETAIL_ARGS = {
    "roofs": ("--normal-footprint=on",),
    "moon": ("--cases=full_high", "--views=close,wide"),
    "storm": ("--only=day", "--view=pilot", "--seed=1253"),
    "paint": ("--vehicle=turbo-lumber-evolution", "--skin=aserradero", "--views=front34,top", "--env=flight", "--zoom=1.0"),
}
PAINT_SHADER = "res://assets/vehicle-paints/turbo-lumber-evolution/aserradero.gdshader"
# The common external studio fixture emits its selected material and observed camera for pair verification.
# The studio's simulation, drawing and existing save call are unchanged.
PAINT_READBACK = """		var canopy := node.find_child("canopy_glass", true, false) as MeshInstance3D
		var active: ShaderMaterial = canopy.get_active_material(0) as ShaderMaterial if canopy != null else null
		var shader_path: String = active.shader.resource_path if active != null and active.shader != null else ""
		var camera_target := centre + Vector3(0, lift, 0)
		var audit_record := {"view": view, "shader": shader_path, "vehicle": vehicle, "skin": skin,
			"position": [_camera.position.x, _camera.position.y, _camera.position.z],
			"target": [camera_target.x, camera_target.y, camera_target.z], "fov": _camera.fov,
			"environment": _option("env", "flight"), "zoom": zoom}
"""
WORKLOADS = [*("field:" + case for case in CASES), *("detail:" + name for name in DETAIL)]
ORDER = ("baseline", "candidate", "candidate", "baseline")
SHUTDOWN_GRACE_S = 30
DRIVERS = {"gl_compatibility": ("opengl3", "Compatibility"), "forward_plus": ("vulkan", "Forward+")}
FIXED_ENV = {"OPENRC_SCENERY": "on", "OPENRC_SCENERY_AUDIO": "off", "OPENRC_SCENERY_BIRDS": "off",
             "OPENRC_SCENE_DETAIL": "medium", "LP_NUM_THREADS": "2", "LIBGL_ALWAYS_SOFTWARE": "1"}
SIZE = (1920, 1080)
SAMPLES = 31
COVERAGE_LIMITS = [
    "Static world fixture. Flight simulation, thermal behavior and physical GPU throughput are unmeasured.",
    "Dirt and lens controls are isolated views. The storm and paint images use stationary cameras.",
    "Detail fixtures have one matched image per variant per view. The lunar phase sweep and motion shimmer are unmeasured.",
]


def sha(data):
    return hashlib.sha256(data).hexdigest()


def dump(path, data):
    path.write_text(json.dumps(data, indent=2, allow_nan=False) + "\n", encoding="utf-8")


def git(*args, root=ROOT):
    return subprocess.check_output(["git", "-C", str(root), *args])


def names(raw):
    return [os.fsdecode(name) for name in raw.split(b"\0") if name]


def source_changes(base, plan=False, root=ROOT):
    revisions = [base] if plan else [base, "HEAD"]
    paths = names(git("diff", "--no-renames", "--name-only", "-z", *revisions, "--", "app", "assets", root=root))
    unexpected = set(paths) - SHADERS
    if unexpected:
        raise ValueError(f"Unreviewed app/assets changes: {sorted(unexpected)}")
    if not plan:
        flags = names(git("ls-files", "-v", "-z", "--", "app", "assets", root=root))
        if any(not entry.startswith("H ") for entry in flags):
            raise ValueError("Cannot establish runtime identity from sparse, unmerged or assume-unchanged app/assets inputs")
        if git("status", "--porcelain=v1", "-z", "--untracked-files=all", "--", "app", "assets", root=root):
            raise ValueError("Run only in a clean disposable app/assets checkout")
        if not paths:
            raise ValueError("Candidate has no changed shader")
        for path in paths:
            if not (root / path).is_file() or (root / path).is_symlink():
                raise ValueError(f"Expected existing regular shader {path}")
            for rev in (base, "HEAD"):
                if not git("ls-tree", rev, "--", path, root=root).startswith(b"100644 blob "):
                    raise ValueError(f"Expected existing regular shader in {rev}: {path}")
    return paths


def runtime_hashes(root):
    """Hash actual checkout bytes, including Git's per-file line-ending policy."""
    files = {}
    for name in names(git("ls-files", "-z", "--", "app", "assets", root=root)):
        path = root / name
        if not path.is_file() or path.is_symlink():
            raise ValueError(f"Missing or nonregular runtime input {name}")
        with path.open("rb") as stream:
            files[name] = hashlib.file_digest(stream, "sha256").hexdigest()
    return files


@contextmanager
def shader_variant(root, originals, desired):
    """Validate all originals before first write; roll back partial switches."""
    changed = []
    for name, original in originals.items():
        if (root / name).read_bytes() != original:
            raise ValueError(f"Concurrent source change at {name}")
    try:
        for name, data in desired.items():
            if data != originals[name]:
                changed.append(name)
                (root / name).write_bytes(data)
        for name, data in desired.items():
            if (root / name).read_bytes() != data:
                raise ValueError(f"Variant verification failed at {name}")
        yield
    finally:
        for name in reversed(changed):
            (root / name).write_bytes(originals[name])
        for name, original in originals.items():
            if (root / name).read_bytes() != original:
                raise RuntimeError(f"Could not restore candidate {name}")


def fixture_bytes(path):
    data = (ROOT / path).read_bytes()
    if path == DETAIL["controls"][0]:
        return data
    original_size = b"Vector2i(1600, 1000)" if path == DETAIL["paint"][0] else b"Vector2i(1280, 720)"
    if data.count(original_size) != 1:
        raise ValueError(f"Unexpected viewport declaration in {path}")
    data = data.replace(original_size, b"Vector2i(1920, 1080)")
    if path == DETAIL["paint"][0]:
        marker = b"\t\tvar path := out.path_join("
        if data.count(marker) != 1:
            raise ValueError("Cannot locate studio readback point")
        data = data.replace(marker, PAINT_READBACK.encode() + marker)
        data = data.replace(b"var _camera: Camera3D", b"var _audit_records: Array[Dictionary] = []\nvar _camera: Camera3D")
        data = data.replace(b'\t\tprint("saved ", path)', b'\t\taudit_record["sha256"] = FileAccess.get_sha256(path)\n'
                            b'\t\t_audit_records.append(audit_record)\n\t\tprint("saved ", path)')
        close = b"\tvar manifest := FileAccess.open(out.path_join(\"capture.json\"), FileAccess.WRITE)\n"
        close += b"\tif manifest == null:\n\t\tquit(1)\n\t\treturn\n"
        close += b'\tmanifest.store_string(JSON.stringify({"complete": true, "method": RenderingServer.get_current_rendering_method(),'
        close += b' "adapter": RenderingServer.get_video_adapter_name(), "records": _audit_records}))\n\tmanifest.close()\n'
        data = data.replace(b"\tnode.queue_free()", close + b"\tnode.queue_free()")
    return data


def commands(engine, renderer, output, workload="all"):
    runner = [sys.executable, str(ROOT / "tools/godot/run_checked.py")]
    base_cmd = [engine, "--path", str(ROOT / "app"), "--audio-driver", "Dummy"]
    rendered = [*base_cmd, "--rendering-method", renderer, "--rendering-driver", DRIVERS[renderer][0],
                "--resolution", "1920x1080", "--windowed", "--max-fps", "0"]
    if workload != "all" and workload not in WORKLOADS:
        raise ValueError(f"Unknown workload: {workload}")
    field_cases = (workload.removeprefix("field:"),) if workload.startswith("field:") else CASES
    detail_kinds = (workload.removeprefix("detail:"),) if workload.startswith("detail:") else DETAIL
    order = ORDER[:2] if workload.startswith("detail:") else ORDER
    result = []
    for idx, side in enumerate(order, 1):
        block = f"{idx}-{side}"
        directory = output / block
        def checked(label, flags, command):
            return [*runner, "--out-dir", str(directory / "checks" / label), "--label", label, *flags, "--", *command]
        steps = {"import": checked("import", ["--timeout", "1200"], [*base_cmd, "--headless", "--import"])}
        if not workload.startswith("detail:"):
            field = [*rendered, "--script", "res://tests/capture_landscape_upgrade.gd", "--",
                     f"--out={directory / 'field'}", "--width=1920", "--height=1080", "--motion=off",
                     "--measure_render_time=on", f"--frames={SAMPLES}", "--cases=" + ",".join(field_cases)]
            flags = ["--timeout", "1200", "--resources", "--resource-interval", "1",
                     "--require-text", "LU native capture complete:"]
            steps["field"] = checked("field", flags, field)
        if idx <= 2 and not workload.startswith("field:"):
            for kind in detail_kinds:
                cmd = [*rendered, "--script", str(output / "harnesses" / (kind + ".gd")), "--",
                       f"--out={directory / kind}", *DETAIL_ARGS.get(kind, ())]
                helper = [sys.executable, str(Path(__file__).resolve()), "detail-process", kind, renderer,
                          str(directory / kind), *cmd]
                steps[kind] = checked(kind, ["--timeout", "900", "--require-text", "Verified detail-process receipt:"], helper)
        result.append({"block": block, "variant": side, "field_cases": list(field_cases) if "field" in steps else [],
                       "commands": steps})
    return result


def renderer_line(log, renderer):
    label = DRIVERS[renderer][1]
    api = "OpenGL" if renderer == "gl_compatibility" else "Vulkan"
    lines = [line for line in log.splitlines()
             if line.startswith(api + " ") and f" - {label} - Using Device" in line
             and re.search(r"\b(llvmpipe|lavapipe)\b", line, re.I)]
    if len(lines) != 1:
        raise ValueError(f"Expected one actual Mesa software {label} device identification in engine log")
    return lines[0]


def metrics(row, count=SAMPLES):
    if row["timing_valid"] is not True or row["render_timing_enabled"] is not True:
        raise ValueError("Invalid timing route")
    frame, cpu, gpu = [row[key] for key in ("frame_ms_raw", "viewport_cpu_ms_raw", "viewport_gpu_ms_raw")]
    for samples in (frame, cpu, gpu):
        if len(samples) != count or any(type(x) not in (int, float) or not math.isfinite(x) or x < 0 for x in samples):
            raise ValueError("Missing or invalid raw samples")
    if min(frame) <= 0:
        raise ValueError("Missing wall interval")
    valid = frame[1:]
    positive_gpu = [value for value in gpu[1:] if value > 0]
    positive_cpu = [value for value in cpu[1:] if value > 0]
    sorted_ms = sorted(valid)
    return {"samples_after_bootstrap": len(valid), "median_render_loop_fps": statistics.median(1000/v for v in valid),
            "throughput_fps": 1000 * len(valid) / sum(valid), "wall_ms_p50": statistics.median(valid),
            "wall_ms_p95": sorted_ms[math.ceil(0.95 * len(valid))-1], "wall_ms_worst": max(valid),
            "viewport_cpu_positive_polls": len(positive_cpu),
            "viewport_cpu_positive_poll_ms_median": statistics.median(positive_cpu) if positive_cpu else None,
            "viewport_gpu_positive_polls": len(positive_gpu),
            "viewport_gpu_poll_ms_median_freshness_unverified": statistics.median(positive_gpu) if positive_gpu else None,
            "engine_video_memory_bytes": row["video_memory"], "draw_calls": row["draws"],
            "visible_draws": row["visible_draws"], "shadow_draws": row["shadow_draws"], "primitives": row["primitives"]}


def common_conditions(label, report, renderer):
    """Shared fixture inputs, excluding run-specific counters and pixel hashes."""
    if label == "field":
        args = {key: value for key, value in report["arguments"].items() if key != "out"}
        static = {key: report[key] for key in ("adapter", "driver", "engine", "width", "height", "scene_detail",
                  "mesh_lod_threshold_px", "reflection_slots", "night_options")}
        lake = {key: report["lake"][key] for key in ("identity", "bounds", "triangles", "vertices", "bank_shader")}
        cases = {name: {key: report["cases"][name][key] for key in ("exposure", "night_options", "ground_materials",
                        "worn_photo_enabled", "worn_shoulder_enabled")} for name in report["cases"]}
        return {**static, "arguments": args, "lake": lake, "by_case": cases}
    if label == "controls":
        expected_times = dict.fromkeys(CONTROL_IDS, 3.0)
        expected_times.update(lens_curtain_partial=3.5, lens_curtain_held=4.5)
        rows = {row["view"]: row for row in report["records"]}
        if (set(rows) != set(CONTROL_IDS) or len(report["records"]) != len(rows) or report["complete"] is not True
                or report["method"] != renderer or report["viewport"] != list(SIZE) or report["seed"] != 1253):
            raise ValueError("Missing or inconsistent native control identities")
        for name, row in rows.items():
            if not math.isclose(row["clock_s"], expected_times[name], rel_tol=0, abs_tol=1e-6):
                raise ValueError(f"Unexpected fixture clock at {name}")
            settings = row["controls"]
            if name.startswith("dirt_"):
                specular = {"dirt_light_off": 0.0, "dirt_specular_000": 0.0, "dirt_specular_035": 0.35,
                            "dirt_specular_050": 0.5}[name]
                if (settings["shader"] != "res://render/ground.gdshader" or settings["surface"] != "DirtLoopSurface"
                        or settings["mesh_vertices"] <= 0 or not 0.99 <= settings["track_coverage"] <= 1.0
                        or settings["light_visible"] is not (name != "dirt_light_off")
                        or not math.isclose(settings["light_specular"], specular, abs_tol=1e-6)):
                    raise ValueError(f"Wrong production dirt material or light state at {name}")
            elif name == "lens_disabled":
                if settings != {"enabled": False, "shader": "", "age_s": 0.0}:
                    raise ValueError("Disabled lens unexpectedly drew a film")
            elif (settings["shader"] != "res://render/lens/lens_film.gdshader" or settings["enabled"] is not True
                  or settings["seed"] != 1253 or settings["event_key"] != "native-shader-controls-pilot"
                  or settings["view"] != "pilot" or not math.isfinite(settings["film_seed"])
                  or not math.isclose(settings["age_s"], expected_times[name]-3.0, abs_tol=1e-6)):
                raise ValueError(f"Wrong production lens material or strike state at {name}")
        inputs = {key: report[key] for key in ("adapter", "method", "driver", "engine", "viewport", "seed")}
        inputs["by_view"] = {name: {key: row[key] for key in ("eye", "at", "fov", "clock_s", "controls")}
                             for name, row in rows.items()}
        return inputs
    if label == "paint":
        by_view = {row["view"]: row for row in report}
        if set(by_view) != {"front34", "top"} or len(by_view) != len(report):
            raise ValueError("Missing or duplicate studio camera observations")
        for row in report:
            if (row["vehicle"], row["skin"], row["shader"], row["environment"], row["zoom"]) != (
                    "turbo-lumber-evolution", "aserradero", PAINT_SHADER, "flight", 1.0):
                raise ValueError("Studio fixture did not activate Aserradero")
            for point in ("position", "target"):
                values = row[point]
                if len(values) != 3 or not all(type(x) in (int, float) and math.isfinite(x) for x in values):
                    raise ValueError(f"Invalid studio camera {point}")
            if row["fov"] != 35 or row["target"] == row["position"]:
                raise ValueError("Invalid studio camera or field of view")
        return by_view
    if label == "storm":
        rows = report["images"]
        if (report["viewport"] != list(SIZE) or report["renderer"] != renderer or len(rows) != 2
                or {row["id"] for row in rows} != set(DETAIL[label][1])):
            raise ValueError("Missing or mismatched storm fixture views")
        for row in rows:
            bank = row["bank"]
            if bank["enabled"] is not True or bank["rain_count"] <= 0 or bank["seed"] != 1253:
                raise ValueError("Storm fixture did not activate seeded rain sheets")
        return report
    if label == "moon":
        rows = {row["file"]: row for row in report["cases"]}
        expected = {name + ".png" for name in DETAIL[label][1]}
        if set(rows) != expected or len(report["cases"]) != len(expected):
            raise ValueError("Incomplete lunar camera/lighting records")
        return {"adapter": report["adapter"], "engine": report["engine"], "by_file": rows}
    if report.get("complete") is not True or report.get("method") != renderer:
        raise ValueError(f"Invalid {label} completion or renderer")
    rows = {row["view"]: row for row in report["records"]}
    if set(rows) != set(DETAIL[label][1]) or len(rows) != len(report["records"]):
        raise ValueError(f"Incomplete {label} camera records")
    keys = ("eye_ned", "at_ned", "fov") if label == "roofs" else ("eye", "fov")
    by_view = {view: {key: row[key] for key in keys} for view, row in rows.items()}
    if label == "roofs":
        for view, (shader, mesh_node, expected_det) in ROOF_FOOTPRINTS.items():
            sample = rows[view]["normal_footprint"]
            if (sample["shader"] != shader or sample["mesh_node"] != mesh_node or sample["viewport"] != list(SIZE)
                    or rows[view]["fov"] != 42 or not math.isclose(sample["center_distance_m"], 2.0, abs_tol=0.01)
                    or not math.isclose(sample["uv_det_abs"], expected_det, rel_tol=0.05)
                    or not 0 < sample["uv_det_abs"] < 1e-6):
                raise ValueError(f"Roof centre did not resolve the intended sub-threshold material at {view}")
            by_view[view]["normal_footprint"] = sample
    return {"adapter": report["adapter"], "by_view": by_view}


def verify_matched_inputs(observations):
    for observation in observations[1:]:
        for kind, group in observation.items():
            baseline = observations[0][kind]
            if baseline["conditions"] != group["conditions"] or baseline["device"] != group["device"]:
                raise ValueError(f"Unmatched {kind} fixture conditions or renderer device")


def run_block(block, output, renderer, env):
    directory = output / block["block"]
    directory.mkdir()
    evidence = {}
    for label, command in block["commands"].items():
        subprocess.run(command, cwd=ROOT, env=env, check=True)
        checks, = (directory / "checks" / label).glob("*/report.json")
        verdict = json.loads(checks.read_text())
        if verdict.get("ok") is not True:
            raise ValueError(f"Missing checked verdict: {checks}")
        if label == "import":
            continue
        log = checks.with_name("engine.log").read_text(errors="replace")
        evidence[label] = {"device": renderer_line(log, renderer),
                           "re_spirv_unsupported_opcode_count": log.count("OpVectorExtractDynamic is not supported yet.")}
        if label == "field":
            report = json.loads((directory / label / "report.json").read_text())
            if (report["width"], report["height"]) != SIZE or set(report["cases"]) != set(block["field_cases"]) or not report["lake"]:
                raise ValueError("Wrong render target, incomplete case set or absent production lake")
            if not re.search(r"llvmpipe|lavapipe", report["adapter"], re.I):
                raise ValueError(f"Unexpected adapter {report['adapter']}")
            evidence[label]["cases"] = {case: metrics(report["cases"][case]) for case in block["field_cases"]}
            resources = checks.with_name("resources.json")
            telemetry = json.loads(resources.read_text())
            if sha(resources.read_bytes()) != verdict["resources"]["sha256"] or telemetry["capture_id"] != verdict["capture_id"]:
                raise ValueError("Process sampler identity mismatch")
            summary = telemetry["summary"]
            rss = summary["peaks"]["rss_bytes"]
            user_cpu = summary["counter_deltas"]["cpu_user_seconds"]
            system_cpu = summary["counter_deltas"]["cpu_system_seconds"]
            if telemetry["sample_count"] < 2 or not rss or user_cpu is None or system_cpu is None:
                raise ValueError("Missing direct-process CPU/RSS samples")
            evidence[label]["process_including_startup_and_selected_cases"] = {
                "sampled_peak_rss_bytes": rss, "sampled_cpu_seconds": user_cpu + system_cpu,
                "coverage": telemetry["required_coverage"], "sample_count": telemetry["sample_count"]}
            evidence[label]["conditions"] = common_conditions(label, report, renderer)
            evidence[label]["images"] = validate_images(directory / label, block["field_cases"])
        else:
            snapshot = detail_snapshot(label, renderer, directory / label)
            lifecycle = json.loads((directory / (label + "-lifecycle.json")).read_text())
            if not lifecycle["accepted"] or lifecycle["verified_digest"] != snapshot["digest"]:
                raise ValueError(f"Invalid capture lifecycle receipt for {label}")
            evidence[label].update(conditions=snapshot["conditions"], images=snapshot["images"], lifecycle=lifecycle)
    dump(directory / "observation.json", evidence)
    return evidence


def validate_images(directory, pictures):
    from PIL import Image
    if {path.stem for path in directory.glob("*.png")} != set(pictures):
        raise ValueError(f"Unexpected image roster in {directory}")
    images = {}
    for name in pictures:
        path = directory / (name + ".png")
        if not path.read_bytes().endswith(b"\x00\x00\x00\x00IEND\xaeB\x60\x82"):
            raise ValueError(f"Incomplete PNG at {path}")
        with Image.open(path) as png:
            png.verify()
        with Image.open(path) as image:
            if image.format != "PNG" or image.size != SIZE:
                raise ValueError(f"Expected lossless 1920x1080 PNG at {path}")
            rgb = image.convert("RGB")
            if all(lo == hi for lo, hi in rgb.getextrema()):
                raise ValueError(f"Uniform image at {path}")
            images[name] = {"png_sha256": sha(path.read_bytes()), "rgb_sha256": sha(rgb.tobytes())}
    return images


def detail_snapshot(kind, renderer, directory):
    """Validate all required native records and fully decode every output before trusting completion."""
    name = "manifest.json" if kind in ("moon", "storm") else "capture.json"
    manifest_bytes = (directory / name).read_bytes()
    report = json.loads(manifest_bytes)
    if not re.search(r"llvmpipe|lavapipe", report["adapter"], re.I):
        raise ValueError(f"Unexpected capture device {report['adapter']}")
    if kind == "paint":
        if report["complete"] is not True or report["method"] != renderer:
            raise ValueError("Incomplete studio capture or actual renderer mismatch")
        conditions = common_conditions(kind, [{k: v for k, v in record.items() if k != "sha256"}
                                               for record in report["records"]], renderer)
    else:
        conditions = common_conditions(kind, report, renderer)
    images = validate_images(directory, DETAIL[kind][1])
    if "records" in report:
        for row in report["records"]:
            stem = "turbo-lumber-evolution_aserradero_" + row["view"] if kind == "paint" else row["view"]
            if images[stem]["png_sha256"] != row["sha256"]:
                raise ValueError(f"Wrong native output hash for {kind}/{stem}")
    digest = sha(json.dumps({"manifest": sha(manifest_bytes), "images": images}, sort_keys=True).encode())
    return {"conditions": conditions, "images": images, "digest": digest}


def observe_detail_shutdown(process, snapshot, grace=SHUTDOWN_GRACE_S, poll_interval=0.5):
    """Only our explicit signal following stable, already verified output may close a stuck image fixture."""
    started = time.monotonic()
    verified = None
    saved_at = None
    before_signal = None
    requested_at = None
    sent = []
    while process.poll() is None:
        if saved_at is None:
            try:
                verified = snapshot()
            except (OSError, ValueError, KeyError, TypeError, IndexError):
                pass  # Partial/missing/invalid files never authorize termination.
            else:
                saved_at = time.monotonic()
        elif time.monotonic() - saved_at >= grace:
            before_signal = snapshot()
            if before_signal != verified:
                raise ValueError("Image evidence changed during exit grace")
            if process.poll() is None:
                try:
                    os.kill(process.pid, signal.SIGTERM)
                    sent.append(signal.SIGTERM)
                    requested_at = time.monotonic()
                except ProcessLookupError:
                    pass
                try:
                    process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    try:
                        os.kill(process.pid, signal.SIGKILL)
                        sent.append(signal.SIGKILL)
                    except ProcessLookupError:
                        pass
            break
        time.sleep(poll_interval)
    code = process.wait()
    forced = code < 0 and -code in sent
    exited_at = time.monotonic()
    receipt = {"engine_pid": process.pid, "engine_returncode": code, "signals_sent": [int(s) for s in sent],
               "forced_post_save_cleanup": forced, "grace_seconds": grace, "accepted": False,
               "initial_verified_digest": verified, "pre_signal_verified_digest": before_signal,
               "first_verified_after_s": None if saved_at is None else saved_at-started,
               "first_signal_after_s": None if requested_at is None else requested_at-started,
               "exit_observed_after_s": exited_at-started}
    if code == 0 or forced:
        final = snapshot()
        if verified is not None and final != verified:
            raise ValueError("Final image evidence differs from verified output")
        receipt.update(accepted=True, verified_digest=final)
    return receipt


def detail_process(kind, renderer, directory, command):
    # Forward every byte through EOF to the checked runner. Its disk log is buffered, so
    # validate the startup device from our bounded in-memory copy of the same bytes.
    header = bytearray()
    relay_errors = []
    child = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    def relay():
        try:
            with child.stdout as pipe:
                while chunk := pipe.read1(65536):
                    header.extend(chunk[:max(0, 65536-len(header))])
                    sys.stdout.buffer.write(chunk)
                    sys.stdout.buffer.flush()
        except (OSError, ValueError) as exc:
            relay_errors.append(str(exc))
    def snapshot():
        if child.poll() is not None:
            forwarding.join(timeout=5)
            if relay_errors or forwarding.is_alive():
                raise ValueError("Engine output did not drain through EOF")
        renderer_line(bytes(header).decode(errors="replace"), renderer)
        return detail_snapshot(kind, renderer, directory)["digest"]
    forwarding = threading.Thread(target=relay, daemon=True)
    forwarding.start()
    receipt_path = directory.parent / (kind + "-lifecycle.json")
    try:
        receipt = observe_detail_shutdown(child, snapshot)
    except Exception as exc:
        if child.poll() is None:
            child.kill()
        dump(receipt_path, {"accepted": False, "engine_pid": child.pid, "engine_returncode": child.wait(),
                            "evidence_validation_error": str(exc)})
        raise
    finally:
        if child.poll() is None:
            child.kill()
            child.wait()
        forwarding.join(timeout=5)
    if relay_errors or forwarding.is_alive():
        receipt.update(accepted=False, log_relay_error=relay_errors or ["did not reach EOF"])
    dump(receipt_path, receipt)
    if not receipt["accepted"]:
        code = receipt["engine_returncode"]
        return 128-code if code < 0 else code or 1
    print("Verified detail-process receipt:", json.dumps(receipt), flush=True)
    return 0


def image_pairs(output, blocks, observations):
    from PIL import Image, ImageChops, ImageOps, ImageStat
    before, after = (output / desc["block"] for desc in blocks[:2])
    review = output / "review"
    review.mkdir()
    pairs = {}
    for kind, group in observations[0].items():
        for name in group["images"]:
            key = f"{kind}-{name}"
            with Image.open(before / kind / (name + ".png")) as a, Image.open(after / kind / (name + ".png")) as b:
                a, b = a.convert("RGB"), b.convert("RGB")
                diff = ImageChops.difference(a, b)
                channels = diff.split()
                nonzero = ImageChops.lighter(ImageChops.lighter(channels[0], channels[1]), channels[2]).histogram()
                record = {"changed_pixels": sum(nonzero[1:]), "mean_abs_rgb_8bit": ImageStat.Stat(diff).mean,
                          "changed_bbox_xyxy_exclusive": diff.getbbox(), "left": "baseline", "right": "candidate"}
                joined = Image.new("RGB", (1280, 360))
                for index, frame in enumerate((a, b)):
                    joined.paste(ImageOps.contain(frame, (640, 360)), (640 * index, 0))
                joined.save(review / (key + ".jpg"), quality=86)
            if kind == "field":
                record["baseline_repeat_rgb_identical"] = (group["images"][name]["rgb_sha256"] ==
                    observations[3][kind]["images"][name]["rgb_sha256"])
                record["candidate_repeat_rgb_identical"] = (observations[1][kind]["images"][name]["rgb_sha256"] ==
                    observations[2][kind]["images"][name]["rgb_sha256"])
            pairs[key] = record
    return pairs


def execute(args, plan):
    root, out = ROOT, args.out
    if out.exists() or out.is_relative_to(root / "app") or out.is_relative_to(root / "assets"):
        raise ValueError("Choose a new output directory outside app and assets")
    paths = source_changes(BASE)
    ignored = names(git("ls-files", "--others", "--ignored", "--exclude-standard", "--directory", "-z", "--", "app", "assets"))
    if ignored:
        raise ValueError(f"Use a pristine disposable checkout, found pre-existing generated runtime files: {ignored[:5]}")
    originals = {name: (root / name).read_bytes() for name in paths}
    for name, original in originals.items():
        if original != git("show", "HEAD:" + name):
            raise ValueError(f"Expected exact candidate bytes for {name}")
    previous = {name: git("show", BASE + ":" + name) for name in paths}
    engine = Path(args.godot)
    if not engine.is_file():
        raise ValueError("Supply the pinned Godot executable")
    out.mkdir(parents=True)
    dump(out / "plan.json", plan)
    runtime = runtime_hashes(root)
    dump(out / "runtime-input-sha256.json", runtime)
    harnesses = out / "harnesses"
    harnesses.mkdir()
    sources = {name: {"sha256": sha((root / name).read_bytes())} for name in (
        FIELD, "app/scenery/postcards.gd", "tools/graphics/native_visual_audit.py",
        "tools/godot/run_checked.py", "tools/godot/resource_samples.py")}
    for kind, (path, _) in DETAIL.items():
        data = fixture_bytes(path)
        (harnesses / (kind + ".gd")).write_bytes(data)
        sources[path] = {"source_sha256": sha((root / path).read_bytes()), "used_sha256": sha(data),
                         "adaptation": {"controls": "original native 1080p fixture",
                                        "paint": "1600x1000 -> 1920x1080 and read-only camera/material telemetry"}
                         .get(kind, "Vector2i(1280, 720) -> Vector2i(1920, 1080)")}
    receipt = {"base": BASE, "candidate": git("rev-parse", "HEAD").decode().strip(),
               "host": platform.uname()._asdict(), "engine_sha256": sha(engine.read_bytes()),
               "candidate_runtime_inputs": len(runtime),
               "candidate_runtime_manifest_sha256": sha((out / "runtime-input-sha256.json").read_bytes()),
               "root_tree_ids": {rev: git("ls-tree", rev, "--", "app", "assets").decode().splitlines()
                                 for rev in (BASE, "HEAD")},
               "shader_sha256": {name: {"baseline": sha(previous[name]), "candidate": sha(originals[name])} for name in paths},
               "harnesses": sources, "software_renderer": True, "hardware_performance_qualified": False,
               "baseline_assembly": "baseline shader bytes on candidate checkout; app and assets differ only at listed paths"}
    dump(out / "inputs.json", receipt)
    checked = []
    lock = Path(git("rev-parse", "--path-format=absolute", "--git-path", "openrc-native-visual-audit.lock").decode().strip())
    with lock.open("x"):
        try:
            for block in plan["blocks"]:
                desired = previous if block["variant"] == "baseline" else originals
                with shader_variant(root, originals, desired), tempfile.TemporaryDirectory(prefix="openrc-visual-profile-") as profile:
                    env = {**os.environ, **FIXED_ENV, **{key: str(Path(profile) / key) for key in
                           ("XDG_CACHE_HOME", "XDG_DATA_HOME", "XDG_CONFIG_HOME")}}
                    checked.append(run_block(block, out, args.renderer, env))
        finally:
            lock.unlink()
    if git("status", "--porcelain=v1", "-z", "--untracked-files=all", "--", "app", "assets"):
        raise ValueError("Unexpected tracked runtime changes after restoration")
    verify_matched_inputs(checked)
    pairs = image_pairs(out, plan["blocks"], checked)
    dump(out / "results.json", {"completed": True, "workload": args.workload,
         "order": [block["variant"] for block in plan["blocks"]], "observations": checked, "pairs": pairs,
         "coverage_limits": COVERAGE_LIMITS, "scope": "Software renderer, static production field views. Wall values are post-draw loop intervals. "
                  "GPU polls have unverified age. RSS and CPU seconds include startup. No target-GPU result."})
    # Repeat sources can be audited via their raw report + pixel hashes. Keep original evidence if pixels differ.
    for i, key in ((2, "candidate_repeat_rgb_identical"), (3, "baseline_repeat_rgb_identical")):
        for name in plan["blocks"][0]["field_cases"]:
            if pairs["field-" + name][key]:
                (out / plan["blocks"][i]["block"] / "field" / (name + ".png")).unlink()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--workload", choices=["all", *WORKLOADS], default="all")
    parser.add_argument("--renderer", choices=DRIVERS, default="gl_compatibility")
    parser.add_argument("--godot", default="PINNED_GODOT")
    parser.add_argument("--out", type=Path, default=ROOT / "tmp/native-visual-audit")
    parser.add_argument("--plan", action="store_true", help="print source scope and commands without writing or starting Godot")
    parser.add_argument("--disposable-checkout", action="store_true", help="allow temporary shader swaps in this isolated checkout")
    args = parser.parse_args()
    args.out = args.out.resolve()
    if args.godot != "PINNED_GODOT":
        args.godot = str(Path(args.godot).resolve())
    plan = {"workload": args.workload, "base": BASE, "candidate_head": git("rev-parse", "HEAD").decode().strip(),
            "app_asset_changes_including_worktree": source_changes(BASE, plan=True),
            "env": FIXED_ENV, "warmup_frames_per_case": 60, "first_interval_excluded": True, "coverage_limits": COVERAGE_LIMITS,
            "display": "1920x1080x24 Xvfb", "blocks": commands(args.godot, args.renderer, args.out, args.workload)}
    if args.plan:
        print(json.dumps(plan, indent=2))
    elif args.disposable_checkout:
        # Run restoration when a hosted job sends a termination signal.
        def terminate(signum, _frame):
            raise SystemExit(128 + signum)
        signal.signal(signal.SIGTERM, terminate)
        execute(args, plan)
    else:
        parser.error("Run --plan, or execute in a clean disposable checkout with --disposable-checkout")


if __name__ == "__main__":
    if sys.argv[1:2] == ["detail-process"]:
        kind, renderer, directory, *engine_command = sys.argv[2:]
        if kind not in DETAIL or renderer not in DRIVERS or not engine_command:
            raise SystemExit("Invalid image fixture process")
        raise SystemExit(detail_process(kind, renderer, Path(directory), engine_command))
    main()
