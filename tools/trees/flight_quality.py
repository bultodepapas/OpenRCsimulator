#!/usr/bin/env python3
"""Run serial native active-flight tree profiles and compare paired builds."""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import statistics
import sys
from typing import Any

from flight_quality_common import (
	DEFAULT_ENGINE,
	REPO_ROOT,
	contains_engine_error,
	godot_command,
	load_json,
	make_fresh_directory,
	parse_environment,
	resolve_repo_path,
	run_godot,
	sha256_file,
	utc_now,
	validate_engine_and_project,
	validate_frame_report,
	write_json,
)


def alternating_orders(pairs: int) -> list[tuple[str, str]]:
	"""Reverse first-run order each pair to reduce monotonic warm-state bias."""
	if pairs < 1:
		raise ValueError("pairs must be positive")
	return [("baseline", "candidate") if index % 2 == 0 else ("candidate", "baseline") for index in range(pairs)]


def parser() -> argparse.ArgumentParser:
	root = argparse.ArgumentParser(description=__doc__)
	root.add_argument("--baseline", required=True, help="frozen baseline app project prepared from the same app revision")
	root.add_argument("--candidate", required=True, help="frozen candidate app project prepared from the same app revision")
	root.add_argument("--engine", default=str(DEFAULT_ENGINE), help="native Godot executable")
	root.add_argument("--out", help="new output directory; defaults to a timestamped tmp/tree-completion path")
	root.add_argument("--pairs", type=int, default=5, help="number of alternating baseline/candidate pairs (default: 5)")
	root.add_argument("--warmup", type=float, default=10.0, help="warm-up seconds per run")
	root.add_argument("--sample", type=float, default=60.0, help="measured seconds per run")
	root.add_argument("--width", type=int, default=1280)
	root.add_argument("--height", type=int, default=720)
	root.add_argument("--fps", type=int, default=60, help="identical native render cap per run")
	root.add_argument("--baseline-env", action="append", help="documented tree/grass environment selector NAME=VALUE; repeatable")
	root.add_argument("--candidate-env", action="append", help="documented tree/grass environment selector NAME=VALUE; repeatable")
	root.add_argument("--timeout", type=float, default=600.0, help="per-run timeout in seconds")
	return root


def default_output() -> Path:
	stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
	return REPO_ROOT / "tmp" / "tree-completion" / f"active-flight-{stamp}"


def frame_summary(report: dict[str, Any]) -> dict[str, float]:
	frame_ms = report.get("frame_ms", {})
	return {key: float(frame_ms[key]) for key in ("p50", "p95", "p99", "max") if key in frame_ms}


def pair_identity_failures(left: dict[str, Any], right: dict[str, Any]) -> list[str]:
	failures: list[str] = []
	if left.get("frame_samples_sha256") != right.get("frame_samples_sha256"):
		failures.append("baseline and candidate used different FrameSamples source hashes")
	if left.get("scenario_sha256") != right.get("scenario_sha256"):
		failures.append("baseline and candidate used different scenario identities")
	if left.get("input_tape_sha256") != right.get("input_tape_sha256"):
		failures.append("baseline and candidate used different live input route tapes")
	return failures


def compare_pair(left: dict[str, Any], right: dict[str, Any]) -> dict[str, Any]:
	by_build = {str(left["build_name"]): left["summary"], str(right["build_name"]): right["summary"]}
	baseline = by_build["baseline"]
	candidate = by_build["candidate"]
	base_ms = frame_summary(baseline)
	cand_ms = frame_summary(candidate)
	return {
		"pair": left["pair"],
		"order": [left["build_name"], right["build_name"]],
		"scenario_sha256": left.get("scenario_sha256"),
		"input_tape_sha256": left.get("input_tape_sha256"),
		"frame_ms": {key: {"baseline": base_ms.get(key), "candidate": cand_ms.get(key),
			"delta_candidate_minus_baseline": cand_ms.get(key, 0.0) - base_ms.get(key, 0.0)}
			for key in ("p50", "p95", "p99", "max")},
		"cpu_render_ms_p95": {
			"baseline": baseline.get("measured_render", {}).get("cpu_render_ms", {}).get("p95"),
			"candidate": candidate.get("measured_render", {}).get("cpu_render_ms", {}).get("p95"),
		},
		"gpu_render_ms_p95": {
			"baseline": baseline.get("measured_render", {}).get("gpu_render_ms", {}).get("p95"),
			"candidate": candidate.get("measured_render", {}).get("gpu_render_ms", {}).get("p95"),
		},
		"memory_bytes_p95": {
			key: {
				"baseline": baseline.get("measured_memory", {}).get(key, {}).get("p95"),
				"candidate": candidate.get("measured_memory", {}).get(key, {}).get("p95"),
			}
			for key in ("cpu_static_bytes", "video_bytes", "texture_bytes", "buffer_bytes")
		},
		"simulation_wall_ratio": {
			"baseline": baseline.get("simulation", {}).get("wall_ratio"),
			"candidate": candidate.get("simulation", {}).get("wall_ratio"),
		},
		"draw_calls_visible_p95": {
			"baseline": baseline.get("measured_render", {}).get("visible_draw_calls", {}).get("p95"),
			"candidate": candidate.get("measured_render", {}).get("visible_draw_calls", {}).get("p95"),
		},
		"draw_calls_shadow_p95": {
			"baseline": baseline.get("measured_render", {}).get("shadow_draw_calls", {}).get("p95"),
			"candidate": candidate.get("measured_render", {}).get("shadow_draw_calls", {}).get("p95"),
		},
		"primitives_visible_p95": {
			"baseline": baseline.get("measured_render", {}).get("visible_primitives", {}).get("p95"),
			"candidate": candidate.get("measured_render", {}).get("visible_primitives", {}).get("p95"),
		},
		"primitives_shadow_p95": {
			"baseline": baseline.get("measured_render", {}).get("shadow_primitives", {}).get("p95"),
			"candidate": candidate.get("measured_render", {}).get("shadow_primitives", {}).get("p95"),
		},
	}


def summarize_pairs(comparisons: list[dict[str, Any]]) -> dict[str, Any]:
	result: dict[str, Any] = {"pairs": len(comparisons), "frame_p95_delta_ms": {}}
	for metric in ("p50", "p95", "p99", "max"):
		values = [float(pair["frame_ms"][metric]["delta_candidate_minus_baseline"]) for pair in comparisons]
		result["frame_p95_delta_ms" if metric == "p95" else f"frame_{metric}_delta_ms"] = {
			"median": statistics.median(values),
			"min": min(values),
			"max": max(values),
			"all_at_or_below_plus_0_5ms": all(value <= 0.5 for value in values) if metric == "p95" else None,
		}
	candidate_ratios = [float(pair["simulation_wall_ratio"]["candidate"] or 0.0) for pair in comparisons]
	result["candidate_simulation_wall_ratio"] = {
		"median": statistics.median(candidate_ratios),
		"all_within_0_99_1_01": all(0.99 <= ratio <= 1.01 for ratio in candidate_ratios),
	}
	candidate_p95 = [float(pair["frame_ms"]["p95"]["candidate"] or 0.0) for pair in comparisons]
	candidate_p99 = [float(pair["frame_ms"]["p99"]["candidate"] or 0.0) for pair in comparisons]
	result["candidate_frame_targets"] = {
		"p95_ms_max": max(candidate_p95),
		"p99_ms_max": max(candidate_p99),
		"all_p95_at_or_below_18ms": all(value <= 18.0 for value in candidate_p95),
		"all_p99_at_or_below_25ms": all(value <= 25.0 for value in candidate_p99),
	}
	result["note"] = "These comparisons expose the plan's targets; they do not certify hardware coverage, readability or owner acceptance."
	return result


def main(argv: list[str] | None = None) -> int:
	args = parser().parse_args(argv)
	if args.pairs < 5:
		print("L6c requires at least five alternating pairs.", file=sys.stderr)
		return 2
	if args.width < 640 or args.height < 480 or args.fps < 1:
		print("Width/height/fps are outside supported native qualification bounds.", file=sys.stderr)
		return 2
	engine = resolve_repo_path(args.engine)
	projects = {
		"baseline": resolve_repo_path(args.baseline),
		"candidate": resolve_repo_path(args.candidate),
	}
	try:
		baseline_environment = parse_environment(args.baseline_env if args.baseline_env is not None else ["OPENRC_TREE_WIND=off"])
		candidate_environment = parse_environment(args.candidate_env if args.candidate_env is not None else ["OPENRC_TREE_WIND=on"])
	except ValueError as error:
		print(str(error), file=sys.stderr)
		return 2
	out = resolve_repo_path(args.out) if args.out else default_output()
	try:
		for project in projects.values():
			validate_engine_and_project(engine, project)
		make_fresh_directory(out)
	except (FileNotFoundError, FileExistsError, RuntimeError) as error:
		print(str(error), file=sys.stderr)
		return 2

	root_report: dict[str, Any] = {
		"format": "openrc-tree-flight-quality-series-v1",
		"status": "running",
		"started_utc": utc_now(),
		"engine": str(engine),
		"engine_sha256": sha256_file(engine),
		"projects": {name: str(path) for name, path in projects.items()},
		"project_purpose": {"baseline": "same-revision tree baseline frozen by the qualification owner", "candidate": "same-revision tree candidate frozen by the qualification owner"},
		"environment_overrides": {"baseline": baseline_environment, "candidate": candidate_environment},
		"settings": {
			"pairs": args.pairs,
			"warmup_s": args.warmup,
			"sample_s": args.sample,
			"width": args.width,
			"height": args.height,
			"fps_cap": args.fps,
			"vsync": "disabled; identical software cap via Godot --max-fps",
			"weather": "calm",
			"lighting": "2026-10-18 12:00 local simulation time",
			"aircraft": "jensen-das-ugly-stik-60",
			"start": "airborne, --quick-flight",
			"camera": "pilot camera fixed at azimuth 0/elevation 5 degrees; auto-zoom off",
			"route": "neutral tick-indexed input through FlightSession.read_raw",
			"logger": "app/render/frame_samples.gd, invoked directly by the external research probe",
			"render_settings": "root viewport MSAA_4X; actual viewport size is asserted against the run's requested dimensions",
		},
		"runs": [],
		"pairs": [],
		"out": str(out),
	}
	write_json(out / "series.json", root_report)
	orders = alternating_orders(args.pairs)
	all_complete = True
	frame_source_hashes: set[str] = set()
	scenario_hashes: set[str] = set()
	input_tape_hashes: set[str] = set()
	comparisons: list[dict[str, Any]] = []
	try:
		for pair_index, pair_order in enumerate(orders, start=1):
			pair_entries: list[dict[str, Any]] = []
			for order_index, build_name in enumerate(pair_order, start=1):
				project = projects[build_name]
				run_id = f"pair-{pair_index:02d}-{order_index}-{build_name}"
				run_dir = out / "runs" / run_id
				run_dir.mkdir(parents=True, exist_ok=False)
				report_path = run_dir / "frametimes.json"
				log_path = run_dir / "console.log"
				user_args = [
					"--mode=performance",
					f"--case={run_id}",
					"--route=performance-neutral-trim",
					f"--report={report_path}",
					f"--probe-warmup={args.warmup:g}",
					f"--probe-sample={args.sample:g}",
					"--quick-flight",
					"--start=airborne",
					"--aircraft=jensen-das-ugly-stik-60",
					"--weather=calm",
					"--time-of-day=12:00",
					"--date=2026-10-18",
					"--rates=normal",
					"--view=pilot",
					"--autozoom=0",
				]
				command = godot_command(engine, project, width=args.width, height=args.height,
					log_path=log_path, user_args=user_args, fps=args.fps)
				environment = baseline_environment if build_name == "baseline" else candidate_environment
				process = run_godot(command, log_path=log_path, timeout_s=args.timeout, environment=environment)
				entry: dict[str, Any] = {
					"run_id": run_id,
					"pair": pair_index,
					"build_name": build_name,
					"order_in_pair": order_index,
					"project": str(project),
					"report_path": str(report_path),
					"process": {key: value for key, value in process.items() if key != "output"},
				}
				failures: list[str] = []
				if process["timed_out"]:
					failures.append("Godot timed out")
				if process["exit_code"] != 0:
					failures.append(f"Godot exited with status {process['exit_code']}")
				if process["contains_error"] or contains_engine_error(process["output"]):
					failures.append("Godot log contains ERROR, regardless of exit status")
				if not report_path.is_file():
					failures.append("FrameSamples report was not written")
				else:
					try:
						report = load_json(report_path)
					except (json.JSONDecodeError, ValueError) as error:
						failures.append(f"FrameSamples report is invalid JSON: {error}")
					else:
						failures.extend(validate_frame_report(report))
						entry["frame_report_sha256"] = sha256_file(report_path)
						entry["scenario_sha256"] = report.get("scenario_sha256")
						entry["input_tape_sha256"] = report.get("input_tape_sha256")
						if entry["scenario_sha256"]:
							scenario_hashes.add(str(entry["scenario_sha256"]))
						if entry["input_tape_sha256"]:
							input_tape_hashes.add(str(entry["input_tape_sha256"]))
						source_hash = str(report.get("build", {}).get("frame_samples_sha256", ""))
						entry["frame_samples_sha256"] = source_hash
						entry["summary"] = {
							"frame_ms": report.get("frame_ms", {}),
			"wall_frame_ms": report.get("wall_frame_ms", {}),
			"engine_frame_ms": report.get("engine_frame_ms", {}),
			"engine_seconds": report.get("engine_seconds"),
			"wall_elapsed_seconds": report.get("wall_elapsed_seconds"),
			"measured_clocks": report.get("measured_clocks", {}),
							"simulation": report.get("simulation", {}),
							"measured_render": report.get("measured_render", {}),
							"measured_memory": report.get("measured_memory", {}),
							"window": report.get("settings", {}).get("window", {}),
							"render_settings": report.get("settings", {}).get("render_settings", {}),
							"viewport_render_timing": report.get("build", {}).get("viewport_render_timing", {}),
						}
						if source_hash:
							frame_source_hashes.add(source_hash)
						if report.get("route_id") != "performance-neutral-trim":
							failures.append("performance report has an unexpected route id")
						if float(report.get("warmup_s", 0)) != float(args.warmup) or float(report.get("sample_s", 0)) != float(args.sample):
							failures.append("FrameSamples warm-up or sample duration differs from the requested values")
						window = report.get("settings", {}).get("window", {})
						if (window.get("width"), window.get("height")) != (args.width, args.height):
							failures.append("actual root viewport size differs from the requested native dimensions")
						if report.get("settings", {}).get("render_settings", {}).get("msaa_4x") is not True:
							failures.append("actual root viewport is not using 4x MSAA")
						if report.get("simulation", {}).get("read_raw_calls", 0) < report.get("simulation", {}).get("ticks", 0):
							failures.append("read_raw call count did not cover the measured flight ticks")
				entry["failures"] = failures
				entry["complete"] = not failures
				root_report["runs"].append(entry)
				pair_entries.append(entry)
				write_json(out / "series.json", root_report)
				if failures:
					all_complete = False
					raise RuntimeError(f"{run_id} failed: " + "; ".join(failures))
			if len(pair_entries) == 2:
				left, right = pair_entries
				if left["build_name"] == right["build_name"]:
					all_complete = False
					raise RuntimeError(f"pair {pair_index} did not contain one baseline and one candidate")
				identity_failures = pair_identity_failures(left, right)
				if identity_failures:
					all_complete = False
					raise RuntimeError(f"pair {pair_index} identity mismatch: " + "; ".join(identity_failures))
				comparison = compare_pair(left, right)
				comparisons.append(comparison)
				root_report["pairs"].append(comparison)
				write_json(out / "series.json", root_report)
		if len(frame_source_hashes) != 1:
			all_complete = False
			raise RuntimeError("FrameSamples source hash changed across baseline/candidate runs")
		if len(scenario_hashes) != 1:
			all_complete = False
			raise RuntimeError("scenario identity changed across the alternating timing series")
		if len(input_tape_hashes) != 1:
			all_complete = False
			raise RuntimeError("live input route tape changed across the alternating timing series")
	except (RuntimeError, OSError, ValueError) as error:
		root_report["status"] = "incomplete"
		root_report["error"] = str(error)
		root_report["finished_utc"] = utc_now()
		root_report["comparison_summary"] = summarize_pairs(comparisons) if comparisons else {}
		write_json(out / "series.json", root_report)
		print(str(error), file=sys.stderr)
		return 1

	root_report["status"] = "collected" if all_complete else "incomplete"
	root_report["finished_utc"] = utc_now()
	root_report["frame_samples_sha256"] = next(iter(frame_source_hashes))
	root_report["scenario_sha256"] = next(iter(scenario_hashes))
	root_report["input_tape_sha256"] = next(iter(input_tape_hashes))
	root_report["comparison_summary"] = summarize_pairs(comparisons)
	root_report["qualification_note"] = "Collected native active-flight measurements. Human readability, flight quality and target-hardware sign-off remain separate evidence gates."
	write_json(out / "series.json", root_report)
	print(json.dumps({"status": root_report["status"], "pairs": len(comparisons),
		"out": str(out), "comparison_summary": root_report["comparison_summary"]}, indent=2))
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
