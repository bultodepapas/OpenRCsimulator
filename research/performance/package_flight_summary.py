#!/usr/bin/env python3
"""Strict reader for the opt-in, packaged AppRoot direct-flight capture.

The source-only sustained-flight reader is deliberately unchanged.  This
reader validates a single CPU/health/resource collection, not a campaign,
displayed pixels, signature, engine-pair provenance, or a promotion decision.
"""
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import sys
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))
from research.performance import native_summary as native
from research.performance import sustained_resources as resources

FORMAT = "openrc-package-live-flight v1"
ROUTE = "app-root-direct-flight-fixed-circuit"
PINS_FORMAT = "openrc-package-live-pins v1"
MAX_HEALTH_BYTES = 16 * 1024 * 1024
HEX = re.compile(r"[0-9a-f]{64}\Z")
VIOLATIONS = {"tick_discontinuity", "nonfinite", "input_ownership", "backend", "crash", "fault", "pause",
              "hold", "contact", "prop_strike", "pilot_failure", "focus_loss", "undrawable", "render_scope",
              "observation_overflow"}
FORBIDDEN_ENGINE = {"--script", "-s", "--path", "--main-pack", "--remote-fs", "--editor", "-e",
                    "--project-manager", "--fixed-fps", "--write-movie", "--time-scale", "--frame-delay",
                    "--disable-render-loop", "--headless", "--gpu-profile"}
FORBIDDEN_USER = {"scripted", "trace", "capture", "visual_pose", "visual_distance", "visual_elevation",
                  "visual_azimuth", "hide_airplane", "hide_treeline", "experimental-aircraft-data",
                  "electric-demo", "flight-log-cli", "native-qualification", "sustained-hide-shader",
                  "sustained-shader-param"}


def _sha(value: Any) -> bool:
    return isinstance(value, str) and HEX.fullmatch(value) is not None


def _read(path: Path, maximum: int) -> tuple[bytes, dict[str, Any]]:
    data = resources._read(path, maximum)
    return data, resources._json(data)


def _file_sha256(path: Path, maximum: int) -> str:
    if path.is_symlink() or not path.is_file():
        raise ValueError("missing or linked evidence: " + str(path))
    size = 0
    digest = hashlib.sha256()
    with path.open("rb") as source:
        while True:
            block = source.read(1024 * 1024)
            if not block: break
            size += len(block)
            if size > maximum: raise ValueError("evidence exceeds its byte bound: " + str(path))
            digest.update(block)
    if size == 0: raise ValueError("evidence is empty: " + str(path))
    return digest.hexdigest()


def _positive_int(value: Any) -> bool:
    return type(value) is int and value > 0


def _drawable_observation(health: dict[str, Any], report: dict[str, Any]) -> dict[str, Any]:
    receipt, scenario, obs = health.get("drawable"), health.get("scenario"), health.get("observation")
    if not isinstance(receipt, dict) or not isinstance(receipt.get("scope"), str) or not receipt["scope"]:
        raise ValueError("drawable availability or scope is missing")
    if receipt.get("status") == "not_observed":
        if not isinstance(receipt.get("reason"), str) or not receipt["reason"]:
            raise ValueError("unobserved drawable lacks a reason")
        return {"status": "not_observed", "actual_1080p": False, "reason": receipt["reason"]}
    if (receipt.get("status") != "observed" or not isinstance(scenario, dict)
            or scenario.get("drawable_observation_requested") is not True
            or scenario.get("display_link_requested") is not False or not isinstance(obs, dict)):
        raise ValueError("drawable evidence has an unsupported owner or request scope")
    a, b = receipt.get("before"), receipt.get("after")
    for item in (a, b):
        if (not isinstance(item, dict) or item.get("status") != "observed" or item.get("owner") != "ordinary"
                or item.get("evidence") != "acquired_framebuffer_texture_not_scanout"):
            raise ValueError("drawable boundary is missing or was not acquired as an ordinary framebuffer")
        for key in ("scope", "attempts", "observed", "missed", "changes", "width", "height", "pixel_format",
                    "query_before_usec", "query_after_usec"):
            if type(item.get(key)) is not int or item[key] < 0:
                raise ValueError("drawable counter, extent or clock is malformed")
        if (not item["scope"] or not item["observed"] or not item["width"] or not item["height"]
                or not item["pixel_format"] or item["observed"] > item["attempts"]
                or item["missed"] != item["attempts"] - item["observed"]
                or item["changes"] >= item["observed"] or not item["query_before_usec"]
                or item["query_before_usec"] > item["query_after_usec"]):
            raise ValueError("drawable boundary counters or timestamps are inconsistent")
    start, end = report.get("actual_sample_start_monotonic_usec"), report.get("actual_sample_end_monotonic_usec")
    observed_start, observed_end, dwell = obs.get("start_usec"), obs.get("end_usec"), obs.get("dwell_usec")
    if (not all(type(value) is int and value > 0 for value in (start, end, observed_start, observed_end, dwell))
            or not observed_start <= a["query_before_usec"] <= a["query_after_usec"] <= start < end
            or not end <= b["query_before_usec"] <= b["query_after_usec"] <= observed_end + dwell
            or start - a["query_after_usec"] > 1_000_000 or b["query_before_usec"] - end > 1_000_000
            or a["scope"] != b["scope"] or b["observed"] <= a["observed"]
            or b["missed"] != a["missed"] or b["changes"] != a["changes"]
            or any(a[key] != b[key] for key in ("width", "height", "pixel_format"))
            or b["attempts"] - a["attempts"] != b["observed"] - a["observed"]):
        raise ValueError("drawable boundaries do not bracket stable observed acquisitions")
    return {"status": "observed", "actual_1080p": (a["width"], a["height"]) == (1920, 1080),
            "width": a["width"], "height": a["height"], "pixel_format": a["pixel_format"],
            "scope_id": a["scope"], "observed_in_bracket": b["observed"] - a["observed"],
            "scope": "ordinary-owner acquired framebuffer textures; no encoder, draw or OS scanout proof"}


def _health_errors(health: dict[str, Any], report: dict[str, Any], report_hash: str,
                   stream_hash: str, pins: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    if health.get("format") != FORMAT or health.get("route") != ROUTE or report.get("route") != ROUTE:
        errors.append("package flight format or route differs")
    if (health.get("complete") is not True or health.get("failure") != ""
            or type(health.get("frame_exit_code")) is not int or health["frame_exit_code"] != 0):
        errors.append("package flight did not complete without a failure")
    if health.get("promotion_eligible") is not False:
        errors.append("single-run receipt must not claim package promotion")
    try:
        _drawable_observation(health, report)
    except ValueError as error:
        errors.append(str(error))
    gpu_observation = health.get("real_gpu_completion")
    if not isinstance(gpu_observation, dict) or gpu_observation.get("status") != "not_observed" \
            or not isinstance(gpu_observation.get("scope"), str) or not gpu_observation["scope"]:
        errors.append("real GPU completion availability is missing or unsupported by this reader")
    capture = report.get("capture_id")
    if not isinstance(capture, str) or not capture or len(capture) > 128 or health.get("capture_id") != capture:
        errors.append("capture identity differs")
    if not _positive_int(report.get("pid")) or health.get("pid") != report.get("pid"):
        errors.append("flight and frame process IDs differ")
    if health.get("frame_report_sha256") != report_hash or health.get("frame_stream_sha256") != stream_hash:
        errors.append("flight receipt is not bound to the frame report and stream")
    before, after = health.get("package_before"), health.get("package_after")
    replay, replay_after = health.get("replay_before"), health.get("replay_after")
    backend = health.get("backend_identity")
    if not isinstance(before, dict) or not before or before != after or before.get("ok") is not True \
            or not isinstance(replay, dict) or replay != replay_after or not isinstance(backend, dict):
        errors.append("package, replay or backend identity is missing or changed")
        before, replay, backend = {}, {}, {}
    role = backend.get("backend")
    reference = before.get("reference_identity") if role == "native" else before
    if (role not in ("native", "gdscript_reference") or not isinstance(reference, dict)
            or replay.get("kind") != before.get("kind") or replay.get("sha256") != before.get("sha256")
            or not _sha(replay.get("sha256")) or (role == "native" and replay.get("stage_backend") != backend)):
        errors.append("installed backend is not bound to the package replay identity")
        reference = {}
    if (pins.get("format") != PINS_FORMAT or any(not _sha(pins.get(key)) for key in
            ("reference_receipt_sha256", "executable_sha256", "pack_sha256"))
            or reference.get("receipt_sha256") != pins.get("reference_receipt_sha256")
            or reference.get("executable_sha256") != pins.get("executable_sha256")
            or reference.get("pack_sha256") != pins.get("pack_sha256")):
        errors.append("package does not match the independently selected reference pins")
    if role == "native" and (not _sha(pins.get("native_receipt_sha256"))
            or before.get("receipt_sha256") != pins.get("native_receipt_sha256")):
        errors.append("native package does not match the selected native receipt")
    if not _sha(health.get("initial_checkpoint_sha256")):
        errors.append("tick-zero checkpoint identity is missing")
    scenario = health.get("scenario")
    if ("initial_screened_checkpoint_sha256" in health or
            (isinstance(scenario, dict) and ("screened_configuration_sha256" in scenario or "screened_domain" in scenario))):
        if (not _sha(health.get("initial_screened_checkpoint_sha256")) or not isinstance(scenario, dict)
                or not _sha(scenario.get("screened_configuration_sha256"))
                or not isinstance(scenario.get("screened_domain"), dict)):
            errors.append("screened checkpoint or configuration evidence is incomplete")
    render = health.get("render_scope")
    settings = report.get("render_settings")
    camera = report.get("camera")
    policy = settings.get("reconstruction") if isinstance(settings, dict) else None
    if (not isinstance(render, dict) or not isinstance(settings, dict) or not isinstance(camera, dict)
            or not isinstance(policy, dict) or render.get("fallback") is not False or policy.get("fallback") is not False
            or any(not isinstance(render.get(k), str) or not render[k] for k in
                   ("backend", "driver", "requested", "selected", "provider", "camera_view"))
            or any(type(render.get(k)) is not int or render[k] < 0 for k in
                   ("scaling_3d_mode", "msaa_3d", "screen_space_aa", "max_fps", "vsync_mode"))
            or type(render.get("use_hdr_2d")) is not bool or type(render.get("auto_zoom")) is not bool
            or render.get("shadow_mode") not in ("sun", "vertical", "off")
            or not native._is_number(render.get("scaling_3d_scale")) or render["scaling_3d_scale"] <= 0
            or any(not isinstance(render.get(key), list) or len(render[key]) != 2
                   or any(not native._is_number(v) or v <= 0 for v in render[key])
                   for key in ("window_size", "logical_size"))
            or render.get("backend") != report.get("backend") or render.get("driver") != report.get("rendering_driver")
            or any(render.get(k) != policy.get(k) for k in ("requested", "selected", "provider"))
            or any(render.get(k) != settings.get(k) for k in
                   ("scaling_3d_mode", "scaling_3d_scale", "msaa_3d", "screen_space_aa", "use_hdr_2d"))
            or render.get("window_size") != report.get("window_size_at_report")
            or render.get("logical_size") != camera.get("viewport") or render.get("camera_view") != camera.get("mode")
            or type(camera.get("autozoom")) is not bool or render.get("auto_zoom") != camera.get("autozoom")
            or render.get("max_fps") != report.get("max_fps") or render.get("vsync_mode") != report.get("vsync_mode")):
        errors.append("render configuration was unavailable, fell back, or differs from the frame endpoint")
    obs = health.get("observation")
    violations = health.get("violations")
    if not isinstance(obs, dict) or not isinstance(violations, dict):
        return errors + ["health observation or violations are missing"]
    tick = obs.get("end_tick")
    if (not _positive_int(tick) or type(obs.get("start_tick")) is not int or obs["start_tick"] != 0
            or type(obs.get("observer_calls")) is not int or obs["observer_calls"] != tick
            or type(obs.get("input_reads")) is not int or obs["input_reads"] != tick
            or type(obs.get("last_read_tick")) is not int or obs["last_read_tick"] != tick - 1
            or type(obs.get("pilot_updates")) is not int or obs["pilot_updates"] != (tick + 3) // 4
            or obs.get("pilot_failure") != ""):
        errors.append("accepted tick or fixed-input coverage is incomplete")
        tick = 0
    for name in ("observer_usec", "input_usec", "pilot_usec"):
        if type(obs.get(name)) is not int or obs[name] < 0:
            errors.append(f"{name} is invalid")
    start, end, dwell = obs.get("start_usec"), obs.get("end_usec"), obs.get("dwell_usec")
    sample_start, sample_end = report.get("actual_sample_start_monotonic_usec"), report.get("actual_sample_end_monotonic_usec")
    if (not _positive_int(start) or not _positive_int(end) or not _positive_int(sample_start)
            or not _positive_int(sample_end) or not start <= sample_start < sample_end <= end
            or type(dwell) is not int or dwell < 2_500_000):
        errors.append("health observation does not bracket the full frame window and dwell")
    if (type(obs.get("pilot_usec")) is int and type(obs.get("input_usec")) is int
            and obs["pilot_usec"] > obs["input_usec"]):
        errors.append("nested pilot timing exceeds its input callback")
    measured = report.get("measured_simulation")
    if (not isinstance(measured, dict) or type(measured.get("start_tick")) is not int
            or type(measured.get("end_tick")) is not int or not 0 <= measured["start_tick"] < measured["end_tick"] <= tick):
        errors.append("measured simulation endpoints fall outside observed accepted ticks")
    if set(violations) != VIOLATIONS or any(type(violations.get(k)) is not int or violations[k] != 0 for k in VIOLATIONS):
        errors.append("health violations are missing, malformed or nonzero")
    if type(health.get("native_checked_ticks")) is not int:
        errors.append("native coverage counter is malformed")
    elif role == "native" and health.get("native_checked_ticks") != tick:
        errors.append("native execution was not covered at each accepted tick")
    elif role == "gdscript_reference" and health.get("native_checked_ticks") != 0:
        errors.append("reference receipt has unexpected native coverage")
    points = health.get("checkpoints")
    next_tick = 1
    if not isinstance(points, list) or not points or len(points) > 4096:
        errors.append("bounded tick checkpoints are missing")
        points = []
    for index, point in enumerate(points):
        if not isinstance(point, dict):
            errors.append("tick checkpoint is malformed")
            break
        last = point.get("end_tick")
        partial = point.get("partial")
        if (point.get("start_tick") != next_tick or type(last) is not int or last < next_tick or last > tick
                or type(partial) is not bool or not _sha(point.get("sha256"))
                or (partial and (index != len(points) - 1 or last - next_tick + 1 >= 6000))
                or (not partial and last - next_tick + 1 != 6000)):
            errors.append("tick checkpoints are not contiguous fixed windows")
            break
        next_tick = last + 1
    if tick and next_tick != tick + 1:
        errors.append("tick checkpoints do not cover the sealed flight")
    scenario = health.get("scenario")
    samples = health.get("activation_samples")
    transitions = health.get("activation_transitions")
    if not isinstance(health.get("activation_scope"), str) or not health["activation_scope"]:
        errors.append("activation observation scope is missing")
    if not isinstance(scenario, dict) or not isinstance(samples, list) or not isinstance(transitions, list) \
            or len(samples) != 1 + tick // 240 or len(samples) > 4096 or len(transitions) > 256:
        errors.append("bounded activation history is incomplete")
        return errors
    trim = scenario.get("trim")
    if (not isinstance(scenario.get("aircraft_id"), str) or not scenario["aircraft_id"]
            or scenario["aircraft_id"] != report.get("aircraft_id") or scenario.get("field_id") != "default"
            or scenario.get("seed") != 20261021 or scenario.get("rate_profile") != "full"
            or scenario.get("start_choice") not in ("airborne", "airborne_half_power")
            or any(type(scenario.get(k)) is not bool for k in
                   ("frame_generation_requested", "display_link_requested", "metalfx_trial_requested",
                    "drawable_observation_requested"))
            or any(not _sha(scenario.get(key)) for key in ("configuration", "collision_world_identity", "lake_identity"))
            or not isinstance(trim, dict) or trim.get("ok") is not True
            or not native._is_number(trim.get("V")) or trim["V"] <= 0
            or not native._is_number(trim.get("throttle")) or not 0 <= trim["throttle"] <= 1
            or not isinstance(scenario.get("weather"), dict)):
        errors.append("fixed aircraft, start, input or world scenario is incomplete")
    expected_transitions: list[tuple[int, dict[str, Any]]] = []
    previous: dict[str, Any] | None = None
    prior_time = 0
    prior_companion_tick = None
    for index, row in enumerate(samples):
        if not isinstance(row, dict) or type(row.get("tick")) is not int or row["tick"] != index * 240 \
                or not _positive_int(row.get("monotonic_usec")) or row["monotonic_usec"] < prior_time \
                or not isinstance(start, int) or not isinstance(end, int) or not start <= row["monotonic_usec"] <= end \
                or not isinstance(row.get("value"), dict):
            errors.append("activation samples are malformed or out of order")
            break
        prior_time = row["monotonic_usec"]
        value = row["value"]
        fg_status = row.get("frame_generation_status")
        if "frame_generation_status" not in row:
            errors.append("frame-generation policy availability is missing")
        if fg_status is not None and (not isinstance(fg_status, dict)
                or any(fg_status.get(k) is not None and type(fg_status[k]) is not bool for k in
                       ("requested", "observer_requested", "frame_producer_requested", "attempt_renderer_gated_composition"))
                or any(fg_status.get(k) is not None and (not isinstance(fg_status[k], str) or len(fg_status[k]) > 256)
                       for k in ("state", "reason"))):
            errors.append("frame-generation policy status is malformed")
        bools = ("radio_connected", "controller_service_selected", "soundscape_installed", "engine_audio_installed",
                 "lake_audio_installed", "lens_installed", "companion_manager_installed")
        config = value.get("companion_config")
        if (any(type(value.get(k)) is not bool for k in bools) or value.get("radio_connected") is not False
                or not isinstance(value.get("lens_options"), dict) or not isinstance(value.get("companion_config"), dict)
                or not isinstance(value.get("weather"), dict) or value["weather"] != scenario.get("weather")):
            errors.append("activation facts are incomplete or radio/weather changed")
            break
        if (type(config.get("enabled")) is not bool or type(config.get("count")) is not int or config["count"] < 0
                or (config["enabled"] and config["count"] > 0 and not value["companion_manager_installed"])):
            errors.append("requested companion configuration was not instantiated")
        for field, installed in (("engine_audio_playing", "engine_audio_installed"),
                                 ("engine_audio_paused", "engine_audio_installed"),
                                 ("lake_audio_playing", "lake_audio_installed")):
            if (value[installed] and type(value.get(field)) is not bool) or (not value[installed] and value.get(field) is not None):
                errors.append("audio activation fact is malformed")
        manager = value.get("companion_status")
        if value["companion_manager_installed"]:
            if (not isinstance(manager, dict) or any(type(manager.get(k)) is not int or manager[k] < 0
                    for k in ("active", "airborne", "requested", "faulted", "crashed"))
                    or type(manager.get("removed")) is not bool or manager["removed"]
                    or manager["faulted"] or manager["crashed"] or manager["active"] != manager["requested"]
                    or manager["airborne"] != manager["active"]
                    or manager["requested"] != (config["count"] if config["enabled"] else 0)
                    or type(row.get("companion_accepted_ticks")) is not int):
                errors.append("companion activation is incomplete or unhealthy")
                break
            companion_tick = row["companion_accepted_ticks"]
            if companion_tick < 0 or (prior_companion_tick is not None and manager["active"] > 0
                                      and companion_tick <= prior_companion_tick):
                errors.append("active companion ticks did not advance")
            prior_companion_tick = companion_tick
        elif manager is not None or row.get("companion_accepted_ticks") is not None:
            errors.append("absent companion manager has inconsistent telemetry")
        if value != previous:
            expected_transitions.append((row["tick"], value))
            previous = value
    if [(row.get("tick"), row.get("value")) for row in transitions if isinstance(row, dict)] != expected_transitions \
            or any(not isinstance(row, dict) or not _positive_int(row.get("monotonic_usec"))
                   or not isinstance(start, int) or not isinstance(end, int)
                   or not start <= row["monotonic_usec"] <= end for row in transitions):
        errors.append("activation transitions do not match the sampled history")
    return errors


def _command_errors(command: Any, report: dict[str, Any], health: dict[str, Any]) -> list[str]:
    if not isinstance(command, list) or not 3 <= len(command) <= 256 or command.count("--") != 1 \
            or any(not isinstance(x, str) or not x or len(x) > 4096 for x in command):
        return ["checked command is malformed"]
    engine, user = command[:command.index("--")], command[command.index("--") + 1:]
    errors: list[str] = []
    if not engine or any(x.split("=", 1)[0] in FORBIDDEN_ENGINE for x in engine[1:]):
        errors.append("engine invocation uses a scripted, artificial or headless route")
    if any(x in ("--display-driver=headless", "--rendering-driver=dummy")
           or (x in ("--display-driver", "--rendering-driver") and i + 1 < len(engine)
               and engine[i + 1] == ("headless" if x == "--display-driver" else "dummy"))
           for i, x in enumerate(engine)):
        errors.append("engine invocation uses a headless driver")
    for option, field in (("--rendering-method", "backend"), ("--rendering-driver", "rendering_driver")):
        values = []
        for i, token in enumerate(engine):
            if token.startswith(option + "="): values.append(token.split("=", 1)[1])
            elif token == option: values.append(engine[i + 1] if i + 1 < len(engine) else "")
        if values != [report.get(field)]: errors.append(f"{option} is missing or differs from the effective value")
    scenario = health.get("scenario")
    if not isinstance(scenario, dict) or scenario.get("arguments") != user:
        errors.append("checked user arguments differ from the live flight")
    parsed: dict[str, str | bool] = {}
    for argument in user:
        if not argument.startswith("--"):
            errors.append("unexpected user argument")
            continue
        key, equal, value = argument[2:].partition("=")
        if not key or key in parsed or key in FORBIDDEN_USER:
            errors.append("duplicate or incompatible user argument")
        parsed[key] = value if equal else True
    frame_path = health.get("frame_report")
    output = parsed.get("package-flight-receipt")
    safe_paths = False
    if isinstance(frame_path, str) and isinstance(output, str) and "\\" not in frame_path + output:
        frame_posix, output_posix = PurePosixPath(frame_path), PurePosixPath(output)
        safe_paths = (frame_posix.is_absolute() and output_posix.is_absolute()
                      and ".." not in frame_posix.parts and ".." not in output_posix.parts
                      and output_posix.parent == frame_posix.parent
                      and output_posix.name == "health-" + frame_posix.name)
    identity = health.get("backend_identity")
    if (not safe_paths or parsed.get("frametimes") != frame_path
            or parsed.get("frametimes-stream") is not True
            or not isinstance(identity, dict) or parsed.get("physics-backend") != identity.get("backend")
            or not isinstance(output, str)):
        errors.append("frame, receipt or backend command does not match the live flight")
    return errors


def reduce_run(frame_path: Path, pins: dict[str, Any], *, minimum_seconds: int) -> dict[str, Any]:
    """Validate a single complete run; raise ValueError for incomplete evidence."""
    if minimum_seconds not in (120, 1800): raise ValueError("minimum sample must be 120 or 1800 seconds")
    frame_path = Path(frame_path)
    frame_bytes, frame = _read(frame_path, native.MAX_REPORT_BYTES)
    if frame.get("format") != native.STREAM_FORMAT:
        raise ValueError("package flight requires the v3 frame stream")
    health_path = frame_path.with_name("health-" + frame_path.name)
    health_bytes, health = _read(health_path, MAX_HEALTH_BYTES)
    checked_path = frame_path.with_name("checked-" + frame_path.name)
    checked_bytes, checked = _read(checked_path, native.MAX_BENCHMARK_CHECK_BYTES)
    log_path = frame_path.with_suffix(".log")
    log_bytes = resources._read(log_path, native.MAX_LOG_BYTES)
    if (checked.get("format") != "openrc-godot-check v1" or checked.get("complete") is not True
            or checked.get("ok") is not True or checked.get("process_exit") != 0 or checked.get("reason") != "passed"
            or checked.get("capture_id") != frame.get("capture_id")
            or checked.get("log_sha256") != hashlib.sha256(log_bytes).hexdigest()
            or native._log_error_lines(native._decode_log(log_bytes))):
        raise ValueError("checked launch or its log is invalid")
    marker = ("PACKAGE_FLIGHT verdict=collected capture_id=" + str(frame.get("capture_id"))).encode()
    if marker not in log_bytes: raise ValueError("matching package-flight completion marker is absent")
    command_errors = _command_errors(checked.get("command"), frame, health)
    if command_errors: raise ValueError("; ".join(command_errors))
    frame_report_sha = hashlib.sha256(frame_bytes).hexdigest()
    hydrated, stream = native._hydrate_stream_report(frame, frame_path, include_metrics=True)
    schema_errors, derived = native.validate_native_report(hydrated)
    if schema_errors or derived is None: raise ValueError("invalid frame stream: " + "; ".join(schema_errors))
    health_errors = _health_errors(health, frame, frame_report_sha, stream["sha256"], pins)
    if health_errors: raise ValueError("; ".join(health_errors))
    policy = dict(native.DEFAULT_POLICY, minimum_warmup_s=30.0, minimum_sample_s=float(minimum_seconds))
    duration, pacing, rendering = native.duration_gate(frame, policy), native.pacing_gate(derived, policy), native.rendering_gate(hydrated)
    simulation, endpoint = frame.get("simulation"), frame.get("session_at_report")
    if (frame.get("os") != "macOS" or frame.get("architecture") != "arm64" or frame.get("input_enabled") is not True
            or not isinstance(simulation, dict) or simulation.get("physics_enabled") is not True
            or simulation.get("physics_ticks_per_second") != 240 or simulation.get("paused") is not False
            or simulation.get("fault") != "" or not isinstance(endpoint, dict) or endpoint.get("pause_reason") != ""
            or endpoint.get("holds") != [] or endpoint.get("crashed") is not False or endpoint.get("window_focused") is not True
            or not duration["eligible"] or not rendering["eligible"] or derived["sample_simulation_ticks"] <= 0
            or derived["max_nonadvancing_interval_usec"] > policy["active_nonadvancing_interval_max_usec"]):
        raise ValueError("duration, render progress or active simulation evidence is insufficient")
    directory = resources._checked_hierarchy(frame_path, dict(checked, _frame_path=health.get("frame_report")))
    original = resources._read(directory / "report.json", native.MAX_BENCHMARK_CHECK_BYTES)
    original_log = resources._read(directory / "engine.log", native.MAX_LOG_BYTES)
    if original != checked_bytes or original_log != log_bytes:
        raise ValueError("copied checked receipt or log differs from its original")
    attachment = checked.get("resources")
    if not isinstance(attachment, dict) or attachment.get("file") != "resources.json" or attachment.get("published") is not True:
        raise ValueError("checked resource attachment is unavailable")
    resource_bytes, sampled = _read(directory / "resources.json", resources.MAX_RESOURCE_BYTES)
    if attachment.get("bytes") != len(resource_bytes) or attachment.get("sha256") != hashlib.sha256(resource_bytes).hexdigest():
        raise ValueError("checked resource attachment hash differs")
    for key in ("coverage", "required_coverage", "sample_count", "measurement_status", "summary"):
        if attachment.get(key) != sampled.get(key): raise ValueError("resource receipt differs: " + key)
    invocation = sampled.get("invocation")
    if (sampled.get("capture_id") != frame.get("capture_id") or not isinstance(invocation, dict)
            or invocation.get("capture_id") != frame.get("capture_id")
            or any(invocation.get(k) != checked.get(k) for k in
                   ("command", "cwd", "started_utc", "process_exit", "reason", "log_sha256", "elapsed_seconds"))):
        raise ValueError("resource capture belongs to a different invocation")
    resources._verify_process(frame, sampled, checked)
    resource_rows = resources._validate_resource_series(sampled)
    retained: dict[Path, str] = {}
    resource_window = resources._window_section(hydrated, sampled, resource_rows, directory, checked, frame, retained)
    edge_windows = None
    if minimum_seconds == 1800:
        edge_windows = resources._edge_windows(hydrated, sampled, resource_rows, directory, checked, frame,
                                               retained, resource_window, 300)
        if edge_windows.get("status") != "available":
            raise ValueError("early and final five-minute resource windows are unavailable")
    for path, content, maximum in ((frame_path, frame_bytes, native.MAX_REPORT_BYTES),
                                   (health_path, health_bytes, MAX_HEALTH_BYTES),
                                   (checked_path, checked_bytes, native.MAX_BENCHMARK_CHECK_BYTES),
                                   (log_path, log_bytes, native.MAX_LOG_BYTES),
                                   (directory / "report.json", original, native.MAX_BENCHMARK_CHECK_BYTES),
                                   (directory / "engine.log", original_log, native.MAX_LOG_BYTES),
                                   (directory / "resources.json", resource_bytes, resources.MAX_RESOURCE_BYTES)):
        if resources._read(path, maximum) != content: raise ValueError("evidence changed during validation: " + str(path))
    if _file_sha256(frame_path.with_name(stream["file"]), native.STREAM_MAX_BYTES) != stream["sha256"]:
        raise ValueError("frame stream changed during validation")
    for path, digest in retained.items():
        if _file_sha256(path, max(resources.MAX_RESOURCE_BYTES, resources.host.MAX_BYTES)) != digest:
            raise ValueError("host evidence changed during validation")
    drawable = _drawable_observation(health, frame)
    unresolved = ["completed real GPU pacing", "external signed package and paired-engine verification",
                  "observer overhead", "paired/long campaign", "Home route and physical pilot"]
    if not drawable.get("actual_1080p"): unresolved.append("actual 1080p acquired drawable")
    if resource_window.get("host_state", {}).get("status") != "complete":
        unresolved.append("complete host thermal/power/sleep context")
    measured_activations = [row for row in health["activation_samples"]
                            if frame["actual_sample_start_monotonic_usec"] <= row["monotonic_usec"]
                            <= frame["actual_sample_end_monotonic_usec"]]
    fg_counts: Counter[str] = Counter()
    for row in measured_activations:
        state = row["frame_generation_status"]
        name = state.get("state") if isinstance(state, dict) else None
        fg_counts[name if isinstance(name, str) and name else "unavailable"] += 1
    return {"format": "openrc-package-live-summary v1", "capture_id": frame["capture_id"],
            "route": ROUTE, "collection_valid": True, "promotion_eligible": False,
            "scope": "synthetic no-radio direct AppRoot flight; no Home, physical pilot or scanout claim",
            "frame_report_sha256": frame_report_sha, "frame_stream_sha256": stream["sha256"],
            "health_sha256": hashlib.sha256(health_bytes).hexdigest(),
            "checked_sha256": hashlib.sha256(checked_bytes).hexdigest(), "resource_sha256": hashlib.sha256(resource_bytes).hexdigest(),
            "duration": duration, "pacing": pacing, "rendering": rendering, "metrics": derived,
            "scenario": health["scenario"], "render_scope": health["render_scope"],
            "activation": {"scope": health.get("activation_scope"), "sample_count": len(health["activation_samples"]),
                           "measured_sample_count": len(measured_activations),
                           "first": health["activation_samples"][0], "last": health["activation_samples"][-1],
                           "transitions": health["activation_transitions"], "fg_policy_state_counts": dict(fg_counts),
                           "fg_scope": "sampled policy states only; not proof of a generated or displayed frame"},
            "resources": resource_window, "edge_windows": edge_windows, "drawable": drawable,
            "real_gpu_completion": health.get("real_gpu_completion"), "unresolved": unresolved}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("frame_report", type=Path)
    parser.add_argument("--pins", required=True, type=Path, help="independently frozen package identity pins")
    parser.add_argument("--minimum-seconds", required=True, type=int, choices=(120, 1800))
    args = parser.parse_args()
    try:
        _, pins = _read(args.pins, 64 * 1024)
        result = reduce_run(args.frame_report, pins, minimum_seconds=args.minimum_seconds)
    except (OSError, ValueError, TypeError, KeyError, OverflowError, RecursionError) as error:
        print(json.dumps({"format": "openrc-package-live-summary v1", "collection_valid": False,
                          "promotion_eligible": False, "reason": str(error)}))
        return 1
    print(json.dumps(result, sort_keys=True, allow_nan=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
