#!/usr/bin/env python3
"""Capture native temporal tree-review clips from the live flight scene."""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
import re
import struct
import subprocess
import sys
from typing import Any

from flight_quality_common import (
	DEFAULT_ENGINE,
	REPO_ROOT,
	discover_ffmpeg,
	godot_command,
	load_json,
	make_fresh_directory,
	parse_environment,
	project_source_fingerprint,
	resolve_repo_path,
	run_godot,
	sha256_file,
	utc_now,
	validate_engine_and_project,
	write_json,
)


ROUTES = ("slow-pan", "pilot-input-pulse", "pilot-bank-reversal", "chase-control-pulse", "camera-cut")
RESOLUTIONS = {720: (1280, 720), 1080: (1920, 1080)}


def parser() -> argparse.ArgumentParser:
	root = argparse.ArgumentParser(description=__doc__)
	root.add_argument("--app", default="tmp/tree-oak/candidate/app", help="frozen oak+bark candidate app project")
	root.add_argument("--engine", default=str(DEFAULT_ENGINE), help="native Godot executable")
	root.add_argument("--ffmpeg", help="optional ffmpeg executable; defaults to PATH or the verified repository tool")
	root.add_argument("--env", action="append", help="documented tree/grass environment selector NAME=VALUE; repeatable")
	root.add_argument("--out", help="new output directory; defaults to a timestamped tmp/tree-completion path")
	root.add_argument("--raw-avi-out", help="temporary directory for uncompressed AVI sources; defaults to <out>/raw-avi")
	root.add_argument("--resolutions", default="720,1080", help="comma-separated 720,1080 capture sizes")
	root.add_argument("--fps", type=int, default=24)
	root.add_argument("--frames", type=int, default=120, help="one to five seconds of frames per clip; default is five seconds")
	root.add_argument("--timeout", type=float, default=600.0, help="per-clip timeout in seconds")
	return root


def default_output() -> Path:
	return REPO_ROOT / "tmp" / "tree-completion" / f"temporal-{utc_now().replace(':', '').replace('-', '')}"


def parse_resolutions(value: str) -> list[int]:
	try:
		resolutions = [int(part.strip()) for part in value.split(",") if part.strip()]
	except ValueError as error:
		raise ValueError("--resolutions must be a comma-separated list of 720 and/or 1080") from error
	if not resolutions or any(height not in RESOLUTIONS for height in resolutions):
		raise ValueError("--resolutions must be a comma-separated list of 720 and/or 1080")
	if len(set(resolutions)) != len(resolutions):
		raise ValueError("--resolutions cannot contain duplicates")
	return resolutions


def vector_distance(first: Any, second: Any) -> float | None:
	if not isinstance(first, list) or not isinstance(second, list) or len(first) != 3 or len(second) != 3:
		return None
	return math.sqrt(sum((float(a) - float(b)) ** 2 for a, b in zip(first, second)))


def encode_mp4(ffmpeg: Path, raw_avi: Path, mp4_path: Path, timeout_s: float) -> dict[str, Any]:
	command = [
		str(ffmpeg), "-hide_banner", "-loglevel", "error", "-y", "-i", str(raw_avi),
		"-an", "-c:v", "libx264", "-preset", "medium", "-crf", "18",
		"-pix_fmt", "yuv420p", "-movflags", "+faststart", str(mp4_path),
	]
	result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
		text=True, encoding="utf-8", errors="replace", timeout=timeout_s, check=False)
	if result.returncode != 0 or not mp4_path.is_file() or mp4_path.stat().st_size == 0:
		raise RuntimeError(f"ffmpeg encoding failed ({result.returncode}): {result.stdout.strip()}")
	return {"command": command, "exit_code": result.returncode, "output": result.stdout,
		"size_bytes": mp4_path.stat().st_size, "sha256": sha256_file(mp4_path)}


def native_avi_capture(path: Path) -> dict[str, Any]:
	with path.open("rb") as stream:
		header = stream.read(4096)
	if len(header) < 64 or header[:4] != b"RIFF" or header[8:12] != b"AVI ":
		raise ValueError(f"not a RIFF AVI file: {path}")
	avih = header.find(b"avih")
	if avih < 0 or struct.unpack_from("<I", header, avih + 4)[0] < 56:
		raise ValueError(f"AVI main header is missing or truncated: {path}")
	frame_duration_usec = struct.unpack_from("<I", header, avih + 8)[0]
	frames = struct.unpack_from("<I", header, avih + 8 + 16)[0]
	if frame_duration_usec <= 0 or frames <= 0:
		raise ValueError(f"AVI main header has invalid frame timing: {path}")
	return {
		"frames": frames,
		"frame_duration_usec": frame_duration_usec,
		"duration_s": frames * frame_duration_usec / 1_000_000.0,
		"size_bytes": path.stat().st_size,
		"sha256": sha256_file(path),
	}


def main(argv: list[str] | None = None) -> int:
	args = parser().parse_args(argv)
	try:
		resolutions = parse_resolutions(args.resolutions)
	except ValueError as error:
		print(str(error), file=sys.stderr)
		return 2
	if args.fps != 24:
		print("Temporal route schedules are defined at a native 24 fps; --fps must be 24.", file=sys.stderr)
		return 2
	if args.frames < args.fps or args.frames > args.fps * 5:
		print("--frames must produce clips from one through five seconds.", file=sys.stderr)
		return 2
	engine = resolve_repo_path(args.engine)
	project = resolve_repo_path(args.app)
	out = resolve_repo_path(args.out) if args.out else default_output()
	raw_avi_out = resolve_repo_path(args.raw_avi_out) if args.raw_avi_out else out / "raw-avi"
	ffmpeg = discover_ffmpeg(args.ffmpeg)
	try:
		environment = parse_environment(args.env if args.env is not None else ["OPENRC_TREE_WIND=on"])
	except ValueError as error:
		print(str(error), file=sys.stderr)
		return 2
	try:
		validate_engine_and_project(engine, project)
		make_fresh_directory(out)
		if raw_avi_out.resolve() == out.resolve():
			raise ValueError("raw AVI output must be a separate temporary directory")
		make_fresh_directory(raw_avi_out)
	except (FileNotFoundError, FileExistsError) as error:
		print(str(error), file=sys.stderr)
		return 2
	except ValueError as error:
		print(str(error), file=sys.stderr)
		return 2

	source_fingerprint_before = project_source_fingerprint(project)

	series: dict[str, Any] = {
		"format": "openrc-tree-temporal-series-v1",
		"status": "running",
		"started_utc": utc_now(),
		"app": str(project),
		"engine": str(engine),
		"engine_sha256": sha256_file(engine),
		"resolution_heights": resolutions,
		"fps": args.fps,
		"frames_per_clip": args.frames,
		"duration_s": args.frames / args.fps,
		"routes": list(ROUTES),
		"environment_overrides": environment,
		"capture": "Godot native --write-movie AVI; ffmpeg H.264 MP4 encoding when available",
		"owner_review": "Software produces repeatable flight footage and camera/input traces; human readability approval is not inferred.",
		"project_source_sha256_before": source_fingerprint_before["sha256"],
		"project_source_files_before": source_fingerprint_before["files"],
		"raw_avi_out": str(raw_avi_out),
		"clips": [],
		"out": str(out),
	}
	write_json(out / "series.json", series)
	all_complete = True
	try:
		for height in resolutions:
			width, actual_height = RESOLUTIONS[height]
			for route in ROUTES:
				clip_id = f"{route}-{width}x{actual_height}"
				clip_dir = out / clip_id
				clip_dir.mkdir(parents=True, exist_ok=False)
				raw_avi = raw_avi_out / f"{clip_id}.avi"
				probe_report_path = clip_dir / "probe.json"
				console_log = clip_dir / "console.log"
				user_args = [
					"--mode=temporal",
					f"--route={route}",
					f"--report={probe_report_path}",
					f"--clip={raw_avi}",
					f"--frames={args.frames}",
					"--weather=calm",
					"--time-of-day=12:00",
					"--date=2026-10-18",
					"--rates=normal",
					"--quick-flight",
					"--start=airborne",
					"--aircraft=jensen-das-ugly-stik-60",
				]
				command = godot_command(engine, project, width=width, height=actual_height,
					log_path=console_log, user_args=user_args, movie_path=raw_avi, fps=args.fps, fixed_fps=True)
				process = run_godot(command, log_path=console_log, timeout_s=args.timeout, environment=environment)
				entry: dict[str, Any] = {
					"clip_id": clip_id,
					"route": route,
					"resolution": [width, actual_height],
					"fps": args.fps,
					"frames_requested": args.frames,
					"duration_requested_s": args.frames / args.fps,
					"process": {key: value for key, value in process.items() if key != "output"},
					"probe_report_path": str(probe_report_path),
					"raw_avi_path": str(raw_avi),
				}
				failures: list[str] = []
				if process["timed_out"]:
					failures.append("Godot timed out")
				if process["exit_code"] != 0:
					failures.append(f"Godot exited with status {process['exit_code']}")
				if process["contains_error"]:
					failures.append("Godot log contains ERROR, regardless of exit status")
				if not raw_avi.is_file() or raw_avi.stat().st_size == 0:
					failures.append("Godot native AVI movie was not written")
				probe_report: dict[str, Any] | None = None
				frame_trace: list[dict[str, Any]] = []
				if not probe_report_path.is_file():
					failures.append("temporal route report was not written")
				else:
					try:
						probe_report = load_json(probe_report_path)
					except (json.JSONDecodeError, ValueError) as error:
						failures.append(f"temporal route report is invalid JSON: {error}")
					else:
						failures.extend(validate_temporal_report(probe_report, route, args.frames, width, actual_height))
						frame_trace = probe_report.get("frame_trace", [])
					if probe_report is not None:
						entry["input_tape_sha256"] = probe_report.get("input_tape_sha256")
						entry["camera_events"] = probe_report.get("camera_events", [])
						entry["frame_trace_count"] = len(frame_trace)
						entry["frame_trace_monotonic_start_usec"] = frame_trace[0].get("monotonic_usec") if frame_trace else None
						entry["frame_trace_monotonic_end_usec"] = frame_trace[-1].get("monotonic_usec") if frame_trace else None
						entry["aircraft_position_start"] = frame_trace[0].get("aircraft_position") if frame_trace else None
						entry["aircraft_position_end"] = frame_trace[-1].get("aircraft_position") if frame_trace else None
						entry["aircraft_motion_m"] = vector_distance(entry["aircraft_position_start"], entry["aircraft_position_end"])
						camera_start = frame_trace[0].get("camera_transform", {}).get("position") if frame_trace else None
						camera_end = frame_trace[-1].get("camera_transform", {}).get("position") if frame_trace else None
						entry["camera_motion_m"] = vector_distance(camera_start, camera_end)
						entry["simulation"] = probe_report.get("simulation", {})
						entry["physics_ticks_per_second"] = probe_report.get("route_spec", {}).get("tick_rate")
						entry["probe_report_sha256"] = sha256_file(probe_report_path)
				if failures:
					entry["failures"] = failures
					entry["complete"] = False
					series["clips"].append(entry)
					write_json(out / "series.json", series)
					all_complete = False
					raise RuntimeError(f"{clip_id} failed: " + "; ".join(failures))
				entry["raw_avi_sha256"] = sha256_file(raw_avi)
				entry["raw_avi_size_bytes"] = raw_avi.stat().st_size
				entry["native_avi_capture"] = native_avi_capture(raw_avi)
				if ffmpeg:
					mp4 = clip_dir / f"{clip_id}.mp4"
					encoding = encode_mp4(ffmpeg, raw_avi, mp4, args.timeout)
					entry["video_path"] = str(mp4)
					entry["video_format"] = "mp4/h264"
					entry["video_sha256"] = encoding["sha256"]
					entry["video_size_bytes"] = encoding["size_bytes"]
					entry["encoder"] = {"ffmpeg": str(ffmpeg), "command": encoding["command"], "exit_code": encoding["exit_code"]}
				else:
					entry["video_path"] = str(raw_avi)
					entry["video_format"] = "native-godot-avi"
					entry["video_sha256"] = entry["raw_avi_sha256"]
					entry["video_size_bytes"] = entry["raw_avi_size_bytes"]
					entry["encoder"] = {"ffmpeg": None, "note": "ffmpeg was not found; retaining the native AVI clip."}
				entry["started_utc"] = process["started_utc"]
				entry["finished_utc"] = process["finished_utc"]
				entry["complete"] = True
				entry["manifest_path"] = str(clip_dir / "manifest.json")
				write_json(clip_dir / "manifest.json", {
					"format": "openrc-tree-temporal-clip-manifest-v1",
					"clip_id": clip_id,
					"route": route,
					"resolution": [width, actual_height],
					"fps": args.fps,
					"frames": args.frames,
					"duration_s": args.frames / args.fps,
					"started_utc": process["started_utc"],
					"finished_utc": process["finished_utc"],
					"elapsed_monotonic_s": process["elapsed_monotonic_s"],
					"video_path": entry["video_path"],
					"video_format": entry["video_format"],
					"video_sha256": entry["video_sha256"],
					"video_size_bytes": entry["video_size_bytes"],
					"raw_avi_path": str(raw_avi),
					"raw_avi_sha256": entry["raw_avi_sha256"],
					"native_avi_capture": entry["native_avi_capture"],
					"probe_report_path": str(probe_report_path),
					"probe_report_sha256": entry["probe_report_sha256"],
					"camera_events": entry["camera_events"],
					"input_tape_sha256": entry["input_tape_sha256"],
					"frame_trace": frame_trace,
					"simulation": entry["simulation"],
					"physics_ticks_per_second": entry["physics_ticks_per_second"],
					"aircraft_motion_m": entry["aircraft_motion_m"],
					"camera_motion_m": entry["camera_motion_m"],
					"process_command": process["command"],
				})
				series["clips"].append(entry)
				write_json(out / "series.json", series)
	except (RuntimeError, OSError, ValueError, subprocess.SubprocessError) as error:
		series["status"] = "incomplete"
		series["error"] = str(error)
		source_fingerprint_after = project_source_fingerprint(project)
		series["project_source_sha256_after"] = source_fingerprint_after["sha256"]
		series["project_source_unchanged"] = source_fingerprint_before["sha256"] == source_fingerprint_after["sha256"]
		series["finished_utc"] = utc_now()
		write_json(out / "series.json", series)
		print(str(error), file=sys.stderr)
		return 1

	source_fingerprint_after = project_source_fingerprint(project)
	series["project_source_sha256_after"] = source_fingerprint_after["sha256"]
	series["project_source_files_after"] = source_fingerprint_after["files"]
	series["project_source_unchanged"] = source_fingerprint_before["sha256"] == source_fingerprint_after["sha256"]
	if not series["project_source_unchanged"]:
		series["status"] = "incomplete"
		series["error"] = "frozen app source tree changed while temporal clips were captured"
	else:
		series["status"] = "collected" if all_complete and len(series["clips"]) == len(resolutions) * len(ROUTES) else "incomplete"
	series["finished_utc"] = utc_now()
	series["source_note"] = "All clips use actual interactive flight and deterministic tick-scheduled input; camera routes call the production CameraRig. This report does not decide software readability or owner approval."
	write_json(out / "series.json", series)
	print(json.dumps({"status": series["status"], "clips": len(series["clips"]), "out": str(out)}, indent=2))
	return 0


def validate_temporal_report(report: dict[str, Any], route: str, frames: int, width: int, height: int) -> list[str]:
	failures: list[str] = []
	if report.get("format") != "openrc-tree-temporal-v1" or report.get("complete") is not True:
		failures.append("temporal report format is unsupported or route is incomplete")
	if report.get("route") != route or report.get("frames") != frames:
		failures.append("temporal report does not match the requested route/frame count")
	if report.get("resolution") != [width, height]:
		failures.append("temporal report resolution differs from the requested native size")
	if not re.fullmatch(r"[0-9a-f]{64}", str(report.get("input_tape_sha256", ""))):
		failures.append("temporal input tape hash is missing or invalid")
	frame_trace = report.get("frame_trace", [])
	if not isinstance(frame_trace, list) or len(frame_trace) != frames:
		failures.append("per-frame camera/aircraft trace does not match the requested frame count")
		frame_trace = frame_trace if isinstance(frame_trace, list) else []
	else:
		for index, frame in enumerate(frame_trace):
			if int(frame.get("frame", -1)) != index:
				failures.append("per-frame trace indices are not consecutive")
				break
			if not isinstance(frame.get("camera_transform"), dict) or not isinstance(frame.get("aircraft_transform"), dict):
				failures.append("per-frame trace is missing a camera or aircraft transform")
				break
			if not isinstance(frame.get("aircraft_position"), list) or len(frame["aircraft_position"]) != 3:
				failures.append("per-frame trace is missing the aircraft world position")
				break
			if _positive_number(frame.get("camera_fov_deg")) is None:
				failures.append("per-frame trace is missing a positive camera FOV")
				break
			if not str(frame.get("camera_view", "")):
				failures.append("per-frame trace is missing its camera mode")
				break
		timestamps = [_positive_number(frame.get("monotonic_usec")) for frame in frame_trace]
		if any(value is None for value in timestamps) or any(a >= b for a, b in zip(timestamps, timestamps[1:])):
			failures.append("per-frame monotonic timestamps are missing or not increasing")
		ticks = [_positive_number(frame.get("simulation_tick")) for frame in frame_trace]
		if any(value is None for value in ticks) or any(a >= b for a, b in zip(ticks, ticks[1:])):
			failures.append("per-frame simulation tick clock is missing or does not advance")
	simulation = report.get("simulation", {})
	if simulation.get("input_enabled") is not True or simulation.get("physics_enabled") is not True:
		failures.append("temporal flight did not keep the live input and physics paths enabled")
	if simulation.get("paused") is not False:
		failures.append("temporal flight paused before clip completion")
	if simulation.get("crash") is not False or simulation.get("fault"):
		failures.append("temporal flight crashed or faulted before clip completion")
	tick_rate = int(simulation.get("physics_ticks_per_second", 0))
	if tick_rate < 1 or int(report.get("route_spec", {}).get("tick_rate", 0)) != tick_rate:
		failures.append("temporal route tick rate does not match the live physics rate")
	if int(simulation.get("elapsed_ticks", 0)) <= 0 or int(report.get("input_read_calls", 0)) < int(simulation.get("elapsed_ticks", 0)):
		failures.append("FlightSession.read_raw calls do not cover advancing simulation ticks")
	events = report.get("camera_events", [])
	if not isinstance(events, list) or not events:
		failures.append("temporal clip recorded no production CameraRig state changes")
	elif route == "camera-cut" and not {str(event.get("view")) for event in events}.issuperset({"pilot", "chase", "orbit", "closeup"}):
		failures.append("camera-cut clip did not record all four scheduled CameraRig views")
	return failures


def _positive_number(value: Any) -> float | None:
	try:
		numeric = float(value)
	except (TypeError, ValueError):
		return None
	return numeric if math.isfinite(numeric) and numeric > 0.0 else None


if __name__ == "__main__":
	raise SystemExit(main())
