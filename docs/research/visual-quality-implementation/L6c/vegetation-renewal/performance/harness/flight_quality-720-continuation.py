#!/usr/bin/env python3
"""Run serial native active-flight tree profiles and compare paired builds."""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import statistics
import sys
from typing import Any

from flight_quality_common import (
	DEFAULT_ENGINE,
	PROBE,
	REPO_ROOT,
	contains_engine_error,
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
	validate_frame_report,
	write_json,
)

HARNESS_FILES = ("flight_quality.py", "flight_quality_common.py", "flight_quality_probe.gd")
LEGACY_RUNTIME_HARNESS_FILES = ("flight_quality_common.py", "flight_quality_probe.gd")
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")


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
	root.add_argument("--resume", action="store_true", help="continue an incomplete series in the existing --out directory")
	root.add_argument("--resume-source-receipt", help="pre-run source identity receipt for a legacy series without embedded identities")
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


def series_settings(args: argparse.Namespace) -> dict[str, Any]:
	return {
		"pairs": args.pairs,
		"warmup_s": args.warmup,
		"sample_s": args.sample,
		"width": args.width,
		"height": args.height,
		"fps_cap": args.fps,
		"timeout_s": args.timeout,
		"vsync": "disabled; identical software cap via Godot --max-fps",
		"weather": "calm",
		"lighting": "2026-10-18 12:00 local simulation time",
		"aircraft": "jensen-das-ugly-stik-60",
		"start": "airborne, --quick-flight",
		"camera": "pilot camera fixed at azimuth 0/elevation 5 degrees; auto-zoom off",
		"route": "neutral tick-indexed input through FlightSession.read_raw",
		"logger": "app/render/frame_samples.gd, invoked directly by the external research probe",
		"render_settings": "root viewport MSAA_4X; actual viewport size is asserted against the run's requested dimensions",
	}


def source_identities(engine: Path, projects: dict[str, Path]) -> dict[str, Any]:
	project_identities: dict[str, dict[str, Any]] = {}
	for name, project in projects.items():
		fingerprint = project_source_fingerprint(project)
		project_identities[name] = {"sha256": fingerprint["sha256"], "files": fingerprint["files"]}
	harness_paths = {
		"flight_quality.py": Path(__file__).resolve(),
		"flight_quality_common.py": Path(__file__).with_name("flight_quality_common.py").resolve(),
		"flight_quality_probe.gd": PROBE.resolve(),
	}
	return {
		"engine_sha256": sha256_file(engine),
		"projects": project_identities,
		"harness_sha256": {name: sha256_file(path) for name, path in harness_paths.items()},
	}


def source_identity_failures(expected: dict[str, Any], current: dict[str, Any]) -> list[str]:
	failures: list[str] = []
	if expected.get("engine_sha256") != current.get("engine_sha256"):
		failures.append("Godot executable hash differs from the recorded source identity")
	for build_name in ("baseline", "candidate"):
		expected_project = expected.get("projects", {}).get(build_name, {})
		current_project = current.get("projects", {}).get(build_name, {})
		if expected_project.get("sha256") != current_project.get("sha256") or expected_project.get("files") != current_project.get("files"):
			failures.append(f"{build_name} source fingerprint differs from the recorded source identity")
	for filename in HARNESS_FILES:
		if expected.get("harness_sha256", {}).get(filename) != current.get("harness_sha256", {}).get(filename):
			failures.append(f"{filename} hash differs from the recorded harness identity")
	return failures


def legacy_receipt_failures(receipt: dict[str, Any], current: dict[str, Any]) -> list[str]:
	"""Validate a pre-run receipt for old series files that lack embedded identities.

	The resume implementation necessarily changes flight_quality.py itself. For a legacy
	receipt, the measurement implementation identities are flight_quality_common.py and
	flight_quality_probe.gd; the old runner hash is retained in the receipt for provenance.
	"""
	failures: list[str] = []
	for build_name in ("baseline", "candidate"):
		block = receipt.get(build_name, {})
		current_project = current.get("projects", {}).get(build_name, {})
		manifest = block.get("file_manifest")
		if not isinstance(manifest, dict) or not manifest:
			failures.append(f"source receipt has no full {build_name} file manifest")
			continue
		if block.get("files") != len(manifest):
			failures.append(f"source receipt {build_name} manifest count is invalid")
		if block.get("sha256") != current_project.get("sha256") or block.get("files") != current_project.get("files"):
			failures.append(f"source receipt {build_name} fingerprint does not match the current project")
	harness = receipt.get("harness", {})
	for filename in HARNESS_FILES:
		value = harness.get(filename)
		if not isinstance(value, str) or not SHA256_RE.fullmatch(value):
			failures.append(f"source receipt is missing a valid {filename} hash")
	for filename in LEGACY_RUNTIME_HARNESS_FILES:
		current_hash = current.get("harness_sha256", {}).get(filename)
		if harness.get(filename) != current_hash:
			failures.append(f"source receipt {filename} hash does not match the current measurement harness")
	return failures


def accepted_pair_attempts(root_report: dict[str, Any], out: Path, pair_count: int) -> dict[int, int]:
	"""Return intact accepted pairs, validating their unchanged report artifacts and structure."""
	comparisons = root_report.get("pairs", [])
	runs = root_report.get("runs", [])
	if not isinstance(comparisons, list) or not isinstance(runs, list):
		raise ValueError("series pairs/runs history is malformed")
	orders = alternating_orders(pair_count)
	accepted: dict[int, int] = {}
	for comparison in comparisons:
		try:
			pair_number = int(comparison["pair"])
			attempt = int(comparison.get("attempt", 1))
		except (KeyError, TypeError, ValueError) as error:
			raise ValueError("accepted pair comparison is missing its pair or attempt identity") from error
		if pair_number < 1 or pair_number > pair_count or attempt < 1 or pair_number in accepted:
			raise ValueError("accepted pair identities are duplicated or outside the requested series")
		try:
			pair_runs = [run for run in runs if int(run.get("pair", 0)) == pair_number and int(run.get("attempt", 1) or 1) == attempt]
		except (AttributeError, TypeError, ValueError) as error:
			raise ValueError("series run history contains an invalid pair or attempt identity") from error
		if len(pair_runs) != 2:
			raise ValueError(f"accepted pair {pair_number} does not have exactly two retained runs")
		expected_order = orders[pair_number - 1]
		for index, (run, build_name) in enumerate(zip(pair_runs, expected_order, strict=True), start=1):
			try:
				order_in_pair = int(run.get("order_in_pair", 0))
			except (AttributeError, TypeError, ValueError) as error:
				raise ValueError(f"accepted pair {pair_number} has an invalid run order") from error
			if run.get("build_name") != build_name or order_in_pair != index:
				raise ValueError(f"accepted pair {pair_number} run order does not match the alternating schedule")
			if run.get("complete") is not True or run.get("failures"):
				raise ValueError(f"accepted pair {pair_number} contains an incomplete run")
			report_path = Path(str(run.get("report_path", "")))
			if not report_path.is_absolute():
				report_path = out / report_path
			if not report_path.is_file():
				raise ValueError(f"accepted pair {pair_number} report artifact is missing: {report_path}")
			recorded_hash = run.get("frame_report_sha256")
			if not isinstance(recorded_hash, str) or not SHA256_RE.fullmatch(recorded_hash) or sha256_file(report_path) != recorded_hash:
				raise ValueError(f"accepted pair {pair_number} report artifact hash does not match its history")
		if pair_identity_failures(pair_runs[0], pair_runs[1]):
			raise ValueError(f"accepted pair {pair_number} run identities do not match")
		if comparison.get("scenario_sha256") != pair_runs[0].get("scenario_sha256") or comparison.get("input_tape_sha256") != pair_runs[0].get("input_tape_sha256"):
			raise ValueError(f"accepted pair {pair_number} comparison identity does not match its runs")
		accepted[pair_number] = attempt
	if sorted(accepted) != list(range(1, len(accepted) + 1)):
		raise ValueError("accepted pairs are not a contiguous prefix of the alternating series")
	return accepted


def resume_contract_failures(
	root_report: dict[str, Any],
	*,
	args: argparse.Namespace,
	out: Path,
	engine: Path,
	projects: dict[str, Path],
	baseline_environment: dict[str, str],
	candidate_environment: dict[str, str],
	current_identities: dict[str, Any],
	receipt: dict[str, Any] | None,
) -> list[str]:
	failures: list[str] = []
	if root_report.get("format") != "openrc-tree-flight-quality-series-v1":
		failures.append("--resume output is not a recognized flight-quality series")
	if root_report.get("status") == "collected":
		failures.append("series is already collected; it cannot be resumed")
	if os.path.normcase(str(Path(str(root_report.get("out", ""))).resolve())) != os.path.normcase(str(out.resolve())):
		failures.append("--out does not match the recorded series directory")
	if os.path.normcase(str(Path(str(root_report.get("engine", ""))).resolve())) != os.path.normcase(str(engine.resolve())):
		failures.append("Godot executable path differs from the recorded series")
	if root_report.get("engine_sha256") != current_identities.get("engine_sha256"):
		failures.append("Godot executable hash differs from the recorded series")
	recorded_projects = root_report.get("projects", {})
	for build_name in ("baseline", "candidate"):
		if os.path.normcase(str(Path(str(recorded_projects.get(build_name, ""))).resolve())) != os.path.normcase(str(projects[build_name].resolve())):
			failures.append(f"{build_name} project path differs from the recorded series")
	if root_report.get("environment_overrides") != {"baseline": baseline_environment, "candidate": candidate_environment}:
		failures.append("environment overrides differ from the recorded series")
	recorded_settings = root_report.get("settings", {})
	for key, value in series_settings(args).items():
		# Legacy v1 output did not record timeout_s; it does not change sample contents.
		if key == "timeout_s" and key not in recorded_settings:
			continue
		if recorded_settings.get(key) != value:
			failures.append(f"setting {key} differs from the recorded series")
	stored_identities = root_report.get("source_identities")
	if isinstance(stored_identities, dict):
		failures.extend(source_identity_failures(stored_identities, current_identities))
	elif receipt is None:
		failures.append("legacy series requires --resume-source-receipt because it lacks embedded source identities")
	else:
		failures.extend(legacy_receipt_failures(receipt, current_identities))
	if receipt is not None and isinstance(stored_identities, dict):
		failures.extend(legacy_receipt_failures(receipt, current_identities))
	return failures


def next_pair_attempt(root_report: dict[str, Any], out: Path, pair_number: int, pair_order: tuple[str, str]) -> int:
	runs = root_report.get("runs", [])
	prior_attempts = [int(run.get("attempt", 1)) for run in runs if int(run.get("pair", 0)) == pair_number]
	attempt = max(prior_attempts, default=0) + 1 if prior_attempts else 1
	while True:
		if attempt == 1:
			run_ids = [f"pair-{pair_number:02d}-{index}-{build}" for index, build in enumerate(pair_order, start=1)]
		else:
			run_ids = [f"pair-{pair_number:02d}-attempt-{attempt:02d}-{index}-{build}" for index, build in enumerate(pair_order, start=1)]
		if not any((out / "runs" / run_id).exists() for run_id in run_ids):
			return attempt
		attempt += 1


def run_identifier(pair_number: int, attempt: int, order_index: int, build_name: str) -> str:
	if attempt == 1:
		return f"pair-{pair_number:02d}-{order_index}-{build_name}"
	return f"pair-{pair_number:02d}-attempt-{attempt:02d}-{order_index}-{build_name}"


def accepted_identity_hashes(root_report: dict[str, Any], accepted: dict[int, int]) -> tuple[set[str], set[str], set[str]]:
	frame_hashes: set[str] = set()
	scenario_hashes: set[str] = set()
	input_hashes: set[str] = set()
	for run in root_report.get("runs", []):
		pair_number = int(run.get("pair", 0))
		if accepted.get(pair_number) != int(run.get("attempt", 1)):
			continue
		for key, target in (
			("frame_samples_sha256", frame_hashes),
			("scenario_sha256", scenario_hashes),
			("input_tape_sha256", input_hashes),
		):
			value = run.get(key)
			if not isinstance(value, str) or not value:
				raise ValueError(f"accepted run {run.get('run_id')} is missing {key}")
			target.add(value)
	for label, values in (("FrameSamples source", frame_hashes), ("scenario", scenario_hashes), ("input route tape", input_hashes)):
		if len(values) > 1:
			raise ValueError(f"accepted pairs contain multiple {label} identities")
	return frame_hashes, scenario_hashes, input_hashes


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
	if args.resume and not args.out:
		print("--resume requires --out to name the existing series directory.", file=sys.stderr)
		return 2
	if args.resume_source_receipt and not args.resume:
		print("--resume-source-receipt requires --resume.", file=sys.stderr)
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
		current_identities = source_identities(engine, projects)
	except (FileNotFoundError, OSError, RuntimeError, KeyError) as error:
		print(str(error), file=sys.stderr)
		return 2
	if args.resume_source_receipt:
		try:
			receipt = load_json(resolve_repo_path(args.resume_source_receipt))
		except (OSError, json.JSONDecodeError, ValueError) as error:
			print(f"could not load --resume-source-receipt: {error}", file=sys.stderr)
			return 2
	else:
		receipt = None
	accepted: dict[int, int] = {}
	if args.resume:
		series_path = out / "series.json"
		try:
			root_report = load_json(series_path)
			contract_failures = resume_contract_failures(
				root_report,
				args=args,
				out=out,
				engine=engine,
				projects=projects,
				baseline_environment=baseline_environment,
				candidate_environment=candidate_environment,
				current_identities=current_identities,
				receipt=receipt,
			)
			if contract_failures:
				raise ValueError("; ".join(contract_failures))
			accepted = accepted_pair_attempts(root_report, out, args.pairs)
			frame_source_hashes, scenario_hashes, input_tape_hashes = accepted_identity_hashes(root_report, accepted)
		except (OSError, json.JSONDecodeError, ValueError, TypeError) as error:
			print(f"could not safely resume series: {error}", file=sys.stderr)
			return 2
		previous_state = {
			"status": root_report.get("status"),
			"error": root_report.get("error"),
			"finished_utc": root_report.get("finished_utc"),
		}
		root_report.setdefault("resume_history", []).append({"resumed_utc": utc_now(), **previous_state})
		root_report["source_identities"] = current_identities
		root_report["settings"]["timeout_s"] = args.timeout
		if receipt is not None:
			receipt_path = resolve_repo_path(args.resume_source_receipt)
			root_report["resume_source_receipt"] = {
				"path": str(receipt_path),
				"sha256": sha256_file(receipt_path),
				"pre_resume_flight_quality_py_sha256": receipt["harness"]["flight_quality.py"],
				"current_flight_quality_py_sha256": current_identities["harness_sha256"]["flight_quality.py"],
				"note": "The resume-capable collector differs from the pre-run receipt; common and probe hashes were verified exactly.",
			}
		root_report["status"] = "running"
		root_report.pop("error", None)
		root_report.pop("finished_utc", None)
		write_json(series_path, root_report)
		comparisons: list[dict[str, Any]] = root_report["pairs"]
	else:
		try:
			make_fresh_directory(out)
		except (FileExistsError, RuntimeError) as error:
			print(str(error), file=sys.stderr)
			return 2
		root_report = {
			"format": "openrc-tree-flight-quality-series-v1",
			"status": "running",
			"started_utc": utc_now(),
			"engine": str(engine),
			"engine_sha256": current_identities["engine_sha256"],
			"projects": {name: str(path) for name, path in projects.items()},
			"project_purpose": {"baseline": "same-revision tree baseline frozen by the qualification owner", "candidate": "same-revision tree candidate frozen by the qualification owner"},
			"environment_overrides": {"baseline": baseline_environment, "candidate": candidate_environment},
			"source_identities": current_identities,
			"settings": series_settings(args),
			"runs": [],
			"pairs": [],
			"out": str(out),
		}
		write_json(out / "series.json", root_report)
		comparisons = root_report["pairs"]
		frame_source_hashes: set[str] = set()
		scenario_hashes: set[str] = set()
		input_tape_hashes: set[str] = set()
	orders = alternating_orders(args.pairs)
	all_complete = True
	try:
		for pair_index, pair_order in enumerate(orders, start=1):
			if pair_index in accepted:
				continue
			pair_attempt = next_pair_attempt(root_report, out, pair_index, pair_order)
			pair_entries: list[dict[str, Any]] = []
			for order_index, build_name in enumerate(pair_order, start=1):
				project = projects[build_name]
				run_id = run_identifier(pair_index, pair_attempt, order_index, build_name)
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
					"attempt": pair_attempt,
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
				comparison["attempt"] = pair_attempt
				root_report["pairs"].append(comparison)
				for entry in pair_entries:
					frame_source_hashes.add(str(entry["frame_samples_sha256"]))
					scenario_hashes.add(str(entry["scenario_sha256"]))
					input_tape_hashes.add(str(entry["input_tape_sha256"]))
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
