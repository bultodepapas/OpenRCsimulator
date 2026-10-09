#!/usr/bin/env python3
"""Verify and profile the instrumented E0b6p prepared-model extension."""
from __future__ import annotations

import argparse
import copy
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys
import tempfile
from typing import Any


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
NATIVE_DIR = ROOT / "research/propwash/e0b6p/native"
PREPARED_DIR = ROOT / "research/propwash/e0b6p/prepared-model"
NATIVE_COST_DIR = ROOT / "research/propwash/e0b6p/native-cost"
BUILD_MANIFEST = ROOT / ".tools/native-prepared-attribution/build.json"
PREPARED_BUILD_MANIFEST = ROOT / ".tools/native-prepared/build.json"
BASELINE_LIBRARY = ROOT / ".tools/native-smooth-wake/libopenrc_slipstream.so"
ERROR_RE = re.compile(r"(?m)^(?:SCRIPT ERROR:|ERROR:|Parse Error:)")
REGIMES: tuple[str, ...]
WARMUP_CALLS: int
CALLS_PER_BATCH: int
MEASURED_BATCHES: int
ROUTE_KEYS = ("native", "kernel_calls", "legacy", "refused")
STAT_KEYS = (
	"calls", "prepared_calls", "prepared_method_total_ns", "prepared_dispatch_ns",
	"prepared_input_decode_ns", "prepared_transport_decode_ns", "prepared_kernel_ns", "prepared_pack_ns",
	"prepare_calls", "prepare_method_total_ns", "prepare_model_decode_ns", "prepare_validation_ns",
	"kernel_calls", "kernel_total_ns", "static_validation_ns", "dynamic_validation_ns",
	"static_validation_timer_pairs", "dynamic_validation_timer_pairs", "axial_wake_ns", "axial_profile_ns",
	"swirl_ns", "kernel_finalize_ns", "clock_pair_overhead_ns",
)
TOP_LEVEL_PHASES = (
	"prepared_dispatch_ns", "prepared_input_decode_ns", "prepared_transport_decode_ns",
	"prepared_kernel_ns", "prepared_pack_ns",
)
KERNEL_PHASES = (
	"static_validation_ns", "dynamic_validation_ns", "axial_wake_ns", "axial_profile_ns",
	"swirl_ns", "kernel_finalize_ns",
)


def module(name: str, path: Path):
	spec = importlib.util.spec_from_file_location(name, path)
	if spec is None or spec.loader is None:
		raise RuntimeError(f"Could not import runner helper: {path}")
	loaded = importlib.util.module_from_spec(spec)
	sys.modules[name] = loaded
	spec.loader.exec_module(loaded)
	return loaded


prepared = module("prepared_model_run", PREPARED_DIR / "run.py")
native = prepared.native
native_cost = module("e0b6p_native_cost_run", NATIVE_COST_DIR / "run_attribution.py")
REGIMES = tuple(native_cost.REGIMES)
WARMUP_CALLS = native_cost.WARMUP_CALLS
CALLS_PER_BATCH = native_cost.CALLS_PER_BATCH
MEASURED_BATCHES = native_cost.MEASURED_BATCHES


def sha256(path: Path) -> str:
	digest = hashlib.sha256()
	with path.open("rb") as file_handle:
		for block in iter(lambda: file_handle.read(1024 * 1024), b""):
			digest.update(block)
	return digest.hexdigest()


def source_tree_hashes(root: Path) -> dict[str, str]:
	ignored = {".git", ".godot", "captures", "__pycache__", ".pytest_cache"}
	result: dict[str, str] = {}
	for path in sorted(root.rglob("*")):
		if not path.is_file() or any(part in ignored for part in path.relative_to(root).parts):
			continue
		result[path.relative_to(root).as_posix()] = sha256(path)
	return result


def harness_hashes() -> dict[str, str]:
	roots = (
		HERE, NATIVE_DIR, PREPARED_DIR, NATIVE_COST_DIR,
		ROOT / "research/propwash/e0b6p/stage-sharing",
		ROOT / "research/propwash/e0b6p/decoder",
		ROOT / "research/native-slipstream",
	)
	result: dict[str, str] = {}
	for directory in roots:
		for path, digest in source_tree_hashes(directory).items():
			result[str((directory / path).relative_to(ROOT))] = digest
	return result


def build_input_hashes(build_path: Path, prepared_build_path: Path, manifest: dict[str, Any],
		baseline: Path, prepared_library: Path, instrumented: Path) -> dict[str, str]:
	paths = {build_path.resolve(), prepared_build_path.resolve(), baseline.resolve(),
		prepared_library.resolve(), instrumented.resolve()}
	for build in (manifest, read_json(prepared_build_path)):
		for record in build.get("sources", {}).values():
			paths.add((ROOT / str(record.get("path", ""))).resolve())
	missing = [str(path) for path in sorted(paths) if not path.is_file()]
	if missing:
		raise RuntimeError("Build provenance inputs are missing: " + ", ".join(missing))
	return {str(path): sha256(path) for path in sorted(paths)}


def provenance_snapshot(project: Path, build_path: Path, prepared_build_path: Path,
		manifest: dict[str, Any], baseline: Path, prepared_library: Path,
		instrumented: Path) -> dict[str, dict[str, str]]:
	return {
		"app_source_sha256": source_tree_hashes(project),
		"harness_source_sha256": harness_hashes(),
		"build_input_sha256": build_input_hashes(
			build_path, prepared_build_path, manifest, baseline, prepared_library, instrumented),
	}


def summarize_hash_map(values: dict[str, str]) -> dict[str, Any]:
	canonical = json.dumps(values, sort_keys=True, separators=(",", ":")).encode("utf-8")
	return {"file_count": len(values), "sha256": hashlib.sha256(canonical).hexdigest()}


def summarize_provenance(values: dict[str, dict[str, str]]) -> dict[str, Any]:
	return {name: summarize_hash_map(items) for name, items in values.items()}


def changed_provenance_paths(before: dict[str, dict[str, str]], after: dict[str, dict[str, str]]) -> dict[str, list[str]]:
	changed: dict[str, list[str]] = {}
	for group in sorted(set(before) | set(after)):
		old = before.get(group, {})
		new = after.get(group, {})
		paths = sorted(path for path in set(old) | set(new) if old.get(path) != new.get(path))
		if paths:
			changed[group] = paths
	return changed


def read_json(path: Path) -> dict[str, Any]:
	try:
		value = json.loads(path.read_text(encoding="utf-8"))
	except (OSError, json.JSONDecodeError) as error:
		raise RuntimeError(f"Could not read JSON report {path}: {error}") from error
	if not isinstance(value, dict):
		raise RuntimeError(f"Expected an object in {path}")
	return value


def finite(value: Any) -> bool:
	return not isinstance(value, bool) and isinstance(value, (int, float)) and math.isfinite(float(value))


def nonnegative_integer(value: Any) -> bool:
	return isinstance(value, int) and not isinstance(value, bool) and value >= 0


def require_number(value: Any, label: str, *, positive: bool = False) -> None:
	if not finite(value) or (positive and float(value) <= 0.0):
		raise RuntimeError(f"{label} must be a finite number" + (" above zero" if positive else ""))


def require_vector(row: dict[str, Any], key: str, label: str) -> None:
	values = row.get(key)
	if not isinstance(values, list) or len(values) != 6 or any(not finite(value) for value in values):
		raise RuntimeError(f"{label} has a missing, malformed, or non-finite six-load vector")


def require_batches(row: dict[str, Any], key: str, label: str, *, positive: bool) -> None:
	values = row.get(key)
	if (not isinstance(values, list) or len(values) != MEASURED_BATCHES
			or any(not finite(value) or (positive and float(value) <= 0.0) for value in values)):
		raise RuntimeError(f"{label} must contain {MEASURED_BATCHES} valid samples")


def require_stats(stats: Any, expected_calls: int, label: str) -> None:
	if not isinstance(stats, dict) or any(not nonnegative_integer(stats.get(key)) for key in STAT_KEYS):
		raise RuntimeError(f"{label} has missing, fractional, negative, or non-integer native counters")
	if (stats["calls"] != expected_calls or stats["prepared_calls"] != expected_calls or
			stats["kernel_calls"] != expected_calls):
		raise RuntimeError(f"{label} native call counts differ from the workload")
	if stats["clock_pair_overhead_ns"] <= 0:
		raise RuntimeError(f"{label} omitted the clock-pair calibration")
	if (stats["static_validation_timer_pairs"] != expected_calls * 3 or
			stats["dynamic_validation_timer_pairs"] != expected_calls * 3):
		raise RuntimeError(f"{label} validation phase timer counts differ from the workload")
	method_phase_sum = sum(stats[key] for key in TOP_LEVEL_PHASES)
	kernel_phase_sum = sum(stats[key] for key in KERNEL_PHASES)
	if method_phase_sum > stats["prepared_method_total_ns"]:
		raise RuntimeError(f"{label} exclusive method phases exceed the inclusive method total")
	if kernel_phase_sum > stats["kernel_total_ns"]:
		raise RuntimeError(f"{label} exclusive kernel phases exceed the inclusive kernel total")
	if stats["kernel_total_ns"] > stats["prepared_kernel_ns"]:
		raise RuntimeError(f"{label} kernel total exceeds its prepared-method phase")
	if expected_calls == 0:
		for key in STAT_KEYS:
			if key != "clock_pair_overhead_ns" and stats[key] != 0:
				raise RuntimeError(f"{label} has counters despite zero native calls")


def require_preparation_stats(stats: Any, label: str) -> None:
	if not isinstance(stats, dict):
		raise RuntimeError(f"{label} omitted explicit preparation counters")
	for key in STAT_KEYS:
		if not nonnegative_integer(stats.get(key)):
			raise RuntimeError(f"{label}/{key} must be a nonnegative integer counter")
	if (stats["prepare_calls"] != 1 or stats["prepared_calls"] != 0 or
			stats["kernel_calls"] != 0):
		raise RuntimeError(f"{label} preparation call roster is wrong")
	if (stats["prepare_method_total_ns"] <= 0 or stats["prepare_model_decode_ns"] <= 0 or
			stats["prepare_validation_ns"] <= 0 or stats["clock_pair_overhead_ns"] <= 0):
		raise RuntimeError(f"{label} did not measure decode, validation, and method setup")
	if (stats["static_validation_timer_pairs"] != 3 or
			stats["dynamic_validation_timer_pairs"] != 3):
		raise RuntimeError(f"{label} preparation validation phase counts are wrong")
	if stats["prepare_model_decode_ns"] + stats["prepare_validation_ns"] > stats["prepare_method_total_ns"]:
		raise RuntimeError(f"{label} exclusive preparation phases exceed the inclusive preparation total")
	if stats["static_validation_ns"] + stats["dynamic_validation_ns"] > stats["prepare_validation_ns"]:
		raise RuntimeError(f"{label} validation phases exceed validation time")


def require_profile(report: dict[str, Any], label: str, instrumented: bool) -> None:
	if report.get("format") != "openrc-e0b6p-prepared-native-attribution-profile v1":
		raise RuntimeError(f"Unexpected {label} profile format")
	if report.get("instrumented") is not instrumented:
		raise RuntimeError(f"Unexpected instrumented flag in {label} profile")
	if (report.get("warmup_calls_per_regime") != WARMUP_CALLS or
			report.get("calls_per_batch") != CALLS_PER_BATCH or
			report.get("measured_batches") != MEASURED_BATCHES):
		raise RuntimeError(f"{label} profile used an unexpected timing roster")
	rows = report.get("rows")
	if not isinstance(rows, list) or [row.get("regime") for row in rows] != list(REGIMES):
		raise RuntimeError(f"{label} profile omitted or reordered a fixed regime")
	for row in rows:
		regime = str(row["regime"])
		require_number(row.get("fade"), f"{label}/{regime}/fade")
		require_vector(row, "direct_loads", f"{label}/{regime}/direct")
		require_vector(row, "adapter_loads", f"{label}/{regime}/adapter")
		if row["direct_loads"] != row["adapter_loads"]:
			raise RuntimeError(f"{label}/{regime} direct and adapter loads differ")
		for key in ("direct_loads_bytes_hex", "adapter_loads_bytes_hex"):
			value = row.get(key)
			if not isinstance(value, str) or len(value) != 96:
				raise RuntimeError(f"{label}/{regime}/{key} is not a six-load byte string")
		if row["direct_loads_bytes_hex"] != row["adapter_loads_bytes_hex"]:
			raise RuntimeError(f"{label}/{regime} direct and adapter bytes differ")
		require_batches(row, "direct_external_us_per_call_batches", f"{label}/{regime}/direct time", positive=True)
		require_batches(row, "direct_empty_loop_us_per_iteration_batches", f"{label}/{regime}/empty loop", positive=False)
		require_batches(row, "adapter_external_us_per_call_batches", f"{label}/{regime}/adapter time", positive=True)
		routes = row.get("adapter_routes_batches")
		if not isinstance(routes, list) or len(routes) != MEASURED_BATCHES:
			raise RuntimeError(f"{label}/{regime} has incomplete adapter route samples")
		expected_kernel_calls = 0 if regime == "reverse_off" else CALLS_PER_BATCH
		for batch_routes in routes:
			expected_routes = {
				"native": CALLS_PER_BATCH, "kernel_calls": expected_kernel_calls,
				"legacy": 0, "refused": 0,
			}
			if (not isinstance(batch_routes, dict) or
					any(not nonnegative_integer(batch_routes.get(key)) for key in ROUTE_KEYS) or
					any(batch_routes.get(key) != value for key, value in expected_routes.items())):
				raise RuntimeError(f"{label}/{regime} adapter route counts are wrong: {batch_routes}")
		if row.get("adapter_routes_last_batch") != routes[-1]:
			raise RuntimeError(f"{label}/{regime} last adapter routes do not match the batch list")
		direct_stats = row.get("direct_internal_stats_batches")
		adapter_stats = row.get("adapter_internal_stats_batches")
		expected_stats = MEASURED_BATCHES if instrumented else 0
		if not isinstance(direct_stats, list) or len(direct_stats) != expected_stats:
			raise RuntimeError(f"{label}/{regime} has incomplete direct native phase samples")
		if not isinstance(adapter_stats, list) or len(adapter_stats) != expected_stats:
			raise RuntimeError(f"{label}/{regime} has incomplete adapter native phase samples")
		if instrumented:
			require_preparation_stats(row.get("preparation_stats"), f"{label}/{regime}")
			for index, stats in enumerate(direct_stats):
				require_stats(stats, CALLS_PER_BATCH, f"{label}/{regime}/direct batch {index}")
			for index, stats in enumerate(adapter_stats):
				require_stats(stats, expected_kernel_calls, f"{label}/{regime}/adapter batch {index}")
		elif row.get("preparation_stats") != {}:
			raise RuntimeError(f"{label}/{regime} baseline unexpectedly prepared a model")


def compare_profiles(baseline: dict[str, Any], instrumented: dict[str, Any]) -> dict[str, Any]:
	require_profile(baseline, "baseline", False)
	require_profile(instrumented, "instrumented", True)
	rows: list[dict[str, Any]] = []
	for old, new in zip(baseline["rows"], instrumented["rows"], strict=True):
		if old.get("regime") != new.get("regime") or old.get("fade") != new.get("fade"):
			raise RuntimeError("Baseline and prepared profiles do not describe the same fixture inputs")
		for key in ("direct_loads_bytes_hex", "adapter_loads_bytes_hex"):
			if old.get(key) != new.get(key):
				raise RuntimeError(f"Instrumented {key} differs byte for byte for {old['regime']}")
		if old.get("adapter_routes_batches") != new.get("adapter_routes_batches"):
			raise RuntimeError(f"Instrumented adapter route roster differs for {old['regime']}")
		rows.append({
			"regime": old["regime"],
			"fade": old["fade"],
			"direct_loads_match_bytes": True,
			"adapter_loads_match_bytes": True,
			"adapter_routes_match": True,
		})
	return {"format": "openrc-e0b6p-prepared-native-profile-comparison v1", "rows": rows}


def synthetic_stats(calls: int) -> dict[str, int]:
	values = {key: 0 for key in STAT_KEYS}
	values["calls"] = calls
	values["prepared_calls"] = calls
	values["kernel_calls"] = calls
	values["clock_pair_overhead_ns"] = 20
	values["static_validation_timer_pairs"] = calls * 3
	values["dynamic_validation_timer_pairs"] = calls * 3
	values["prepare_calls"] = 0
	if calls:
		values.update({
			"prepared_method_total_ns": calls * 1000,
			"prepared_dispatch_ns": calls * 100,
			"prepared_input_decode_ns": calls * 100,
			"prepared_transport_decode_ns": calls * 100,
			"prepared_kernel_ns": calls * 500,
			"prepared_pack_ns": calls * 100,
			"kernel_total_ns": calls * 400,
			"static_validation_ns": calls * 20,
			"dynamic_validation_ns": calls * 20,
			"axial_wake_ns": calls * 30,
			"axial_profile_ns": calls * 30,
			"swirl_ns": calls * 30,
			"kernel_finalize_ns": calls * 30,
		})
	return values


def synthetic_profile(instrumented: bool) -> dict[str, Any]:
	rows = []
	for regime in REGIMES:
		kernel_calls = 0 if regime == "reverse_off" else CALLS_PER_BATCH
		routes = {"native": CALLS_PER_BATCH, "kernel_calls": kernel_calls, "legacy": 0, "refused": 0}
		row: dict[str, Any] = {
			"regime": regime,
			"fade": 0.0 if regime == "reverse_off" else 1.0,
			"preparation_stats": synthetic_stats(0) if instrumented else {},
			"direct_loads": [0.0] * 6,
			"direct_loads_bytes_hex": "0" * 96,
			"direct_external_us_per_call_batches": [1.0] * MEASURED_BATCHES,
			"direct_empty_loop_us_per_iteration_batches": [0.01] * MEASURED_BATCHES,
			"direct_internal_stats_batches": [],
			"adapter_loads": [0.0] * 6,
			"adapter_loads_bytes_hex": "0" * 96,
			"adapter_external_us_per_call_batches": [2.0] * MEASURED_BATCHES,
			"adapter_internal_stats_batches": [],
			"adapter_routes_batches": [routes.copy() for _ in range(MEASURED_BATCHES)],
			"adapter_routes_last_batch": routes.copy(),
		}
		if instrumented:
			row["preparation_stats"] = synthetic_stats(0)
			row["preparation_stats"].update({
				"prepare_calls": 1, "prepare_method_total_ns": 300, "prepare_model_decode_ns": 100,
				"prepare_validation_ns": 100, "static_validation_ns": 20, "dynamic_validation_ns": 20,
				"static_validation_timer_pairs": 3,
				"dynamic_validation_timer_pairs": 3, "clock_pair_overhead_ns": 20,
			})
			row["direct_internal_stats_batches"] = [synthetic_stats(CALLS_PER_BATCH) for _ in range(MEASURED_BATCHES)]
			row["adapter_internal_stats_batches"] = [synthetic_stats(kernel_calls) for _ in range(MEASURED_BATCHES)]
		rows.append(row)
	return {
		"format": "openrc-e0b6p-prepared-native-attribution-profile v1",
		"instrumented": instrumented,
		"warmup_calls_per_regime": WARMUP_CALLS,
		"calls_per_batch": CALLS_PER_BATCH,
		"measured_batches": MEASURED_BATCHES,
		"rows": rows,
	}


def self_check_comparator() -> list[dict[str, Any]]:
	baseline = synthetic_profile(False)
	instrumented = synthetic_profile(True)
	compare_profiles(baseline, instrumented)
	mutations: list[tuple[str, dict[str, Any], dict[str, Any]]] = []
	missing = copy.deepcopy(baseline)
	del missing["rows"][0]["direct_loads"]
	missing_candidate = copy.deepcopy(instrumented)
	del missing_candidate["rows"][0]["direct_loads"]
	mutations.append(("missing vector", missing, missing_candidate))
	nonfinite = copy.deepcopy(instrumented)
	nonfinite["rows"][0]["adapter_loads"][2] = float("nan")
	mutations.append(("non-finite output", copy.deepcopy(baseline), nonfinite))
	bytes_changed = copy.deepcopy(instrumented)
	bytes_changed["rows"][0]["direct_loads_bytes_hex"] = "f" + bytes_changed["rows"][0]["direct_loads_bytes_hex"][1:]
	mutations.append(("changed output bytes", copy.deepcopy(baseline), bytes_changed))
	wrong_count = copy.deepcopy(instrumented)
	wrong_count["rows"][0]["direct_internal_stats_batches"][0]["calls"] = CALLS_PER_BATCH - 1
	mutations.append(("wrong native count", copy.deepcopy(baseline), wrong_count))
	wrong_routes = copy.deepcopy(instrumented)
	wrong_routes["rows"][0]["adapter_routes_batches"][0]["kernel_calls"] -= 1
	mutations.append(("wrong route count", copy.deepcopy(baseline), wrong_routes))
	missing_phase = copy.deepcopy(instrumented)
	del missing_phase["rows"][0]["direct_internal_stats_batches"][0]["static_validation_ns"]
	mutations.append(("missing validation counter", copy.deepcopy(baseline), missing_phase))
	fractional_timer = copy.deepcopy(instrumented)
	fractional_timer["rows"][0]["direct_internal_stats_batches"][0]["clock_pair_overhead_ns"] += 0.5
	mutations.append(("fractional timer counter", copy.deepcopy(baseline), fractional_timer))
	overlapping_phases = copy.deepcopy(instrumented)
	first_stats = overlapping_phases["rows"][0]["direct_internal_stats_batches"][0]
	first_stats["static_validation_ns"] = first_stats["kernel_total_ns"]
	mutations.append(("exclusive phases exceed inclusive total", copy.deepcopy(baseline), overlapping_phases))
	reverse_cutoff = copy.deepcopy(instrumented)
	reverse_cutoff["rows"][-1]["adapter_routes_last_batch"]["kernel_calls"] = CALLS_PER_BATCH
	mutations.append(("reverse cutoff bypass", copy.deepcopy(baseline), reverse_cutoff))
	caught: list[dict[str, Any]] = []
	for label, old, new in mutations:
		try:
			compare_profiles(old, new)
		except RuntimeError as error:
			caught.append({"control": label, "rejected": True, "error": str(error)})
		else:
			raise RuntimeError(f"Comparator self-check did not reject {label}")
	if len(caught) != len(mutations):
		raise RuntimeError("Comparator self-check did not reject every malformed report")
	return caught


def median(values: list[float]) -> float:
	ordered = sorted(values)
	middle = len(ordered) // 2
	if len(ordered) % 2:
		return ordered[middle]
	return 0.5 * (ordered[middle - 1] + ordered[middle])


def phase_summary(report: dict[str, Any]) -> list[dict[str, Any]]:
	rows: list[dict[str, Any]] = []
	for row in report["rows"]:
		batch_stats: list[dict[str, Any]] = row["direct_internal_stats_batches"]
		calls = CALLS_PER_BATCH
		phase_samples: dict[str, list[float]] = {
			key: [] for key in (*TOP_LEVEL_PHASES, *KERNEL_PHASES,
				"prepared_method_total_ns", "kernel_total_ns")
		}
		corrected_samples: dict[str, list[float]] = {key: [] for key in KERNEL_PHASES}
		method_phase_sum_samples: list[float] = []
		kernel_phase_sum_samples: list[float] = []
		method_residual_samples: list[float] = []
		kernel_residual_samples: list[float] = []
		for stats in batch_stats:
			clock_pair = float(stats["clock_pair_overhead_ns"])
			for key in phase_samples:
				phase_samples[key].append(float(stats[key]) / calls)
			method_sum = sum(stats[key] for key in TOP_LEVEL_PHASES)
			kernel_sum = sum(stats[key] for key in KERNEL_PHASES)
			method_phase_sum_samples.append(float(method_sum) / calls)
			kernel_phase_sum_samples.append(float(kernel_sum) / calls)
			method_residual_samples.append(float(stats["prepared_method_total_ns"] - method_sum) / calls)
			kernel_residual_samples.append(float(stats["kernel_total_ns"] - kernel_sum) / calls)
			for key in KERNEL_PHASES:
				pair_key = "static_validation_timer_pairs" if key == "static_validation_ns" else (
					"dynamic_validation_timer_pairs" if key == "dynamic_validation_ns" else None)
				pairs = float(stats[pair_key]) if pair_key else calls
				corrected_samples[key].append(max(0.0, float(stats[key]) / calls - clock_pair * pairs / calls))
		medians = {key: median(values) for key, values in phase_samples.items()}
		corrected = {key: median(values) for key, values in corrected_samples.items()}
		binding_remainder = [
			float(external) - float(empty) - float(stats["prepared_method_total_ns"]) / calls / 1000.0
			for external, empty, stats in zip(
				row["direct_external_us_per_call_batches"],
				row["direct_empty_loop_us_per_iteration_batches"], batch_stats, strict=True)
		]
		adapter_count = int(row["adapter_routes_last_batch"]["kernel_calls"])
		rows.append({
			"regime": row["regime"],
			"fade": row["fade"],
			"calls_per_batch": calls,
			"adapter_kernel_calls_per_batch": adapter_count,
			"clock_pair_overhead_ns_median": median([float(stats["clock_pair_overhead_ns"]) for stats in batch_stats]),
			"direct_external_us_per_call_batches": row["direct_external_us_per_call_batches"],
			"direct_external_us_per_call_median": median(row["direct_external_us_per_call_batches"]),
			"direct_empty_loop_us_per_iteration_batches": row["direct_empty_loop_us_per_iteration_batches"],
			"prepared_method_and_phase_ns_per_call_median_raw": medians,
			"kernel_phase_ns_per_call_median_clock_corrected": corrected,
			"prepared_method_top_level_phase_sum_median_ns_per_call_raw": median(method_phase_sum_samples),
			"prepared_method_unattributed_ns_per_call_median_from_batch_residuals": median(method_residual_samples),
			"prepared_method_unattributed_ns_per_call_batch_residuals": method_residual_samples,
			"kernel_phase_sum_median_ns_per_call_raw": median(kernel_phase_sum_samples),
			"kernel_unattributed_ns_per_call_median_from_batch_residuals": median(kernel_residual_samples),
			"kernel_unattributed_ns_per_call_batch_residuals": kernel_residual_samples,
			"external_to_method_remainder_us_per_call_batches": binding_remainder,
			"external_to_method_remainder_us_per_call_median": median(binding_remainder),
			"adapter_external_us_per_call_batches": row["adapter_external_us_per_call_batches"],
			"adapter_external_us_per_call_median": median(row["adapter_external_us_per_call_batches"]),
			"preparation_method_total_us": float(row["preparation_stats"]["prepare_method_total_ns"]) / 1000.0,
			"preparation_model_decode_us": float(row["preparation_stats"]["prepare_model_decode_ns"]) / 1000.0,
			"preparation_validation_us": float(row["preparation_stats"]["prepare_validation_ns"]) / 1000.0,
			"preparation_static_validation_us": float(row["preparation_stats"]["static_validation_ns"]) / 1000.0,
			"preparation_dynamic_validation_us": float(row["preparation_stats"]["dynamic_validation_ns"]) / 1000.0,
		})
	return rows


def profile_source(instrumented: bool) -> str:
	source = (HERE / "native_probe.gd").read_text(encoding="utf-8")
	if instrumented:
		replacements = {
			'const Adapter = preload("res://tests/e0b6p_native/adapter.gd")':
				'const Adapter = preload("res://tests/e0b6p_prepared/adapter.gd")',
			"__PREPARE_CALL__": "Adapter.prepare(model)",
			"__TOKEN_CALL__": "int(Adapter.prepared_token)",
		}
	else:
		replacements = {
			"__PREPARE_CALL__": "true",
			"__TOKEN_CALL__": "0",
		}
	for anchor, replacement in replacements.items():
		if source.count(anchor) != 1:
			raise RuntimeError(f"Native probe source drifted at {anchor}")
		source = source.replace(anchor, replacement, 1)
	if "__PREPARE_CALL__" in source or "__TOKEN_CALL__" in source:
		raise RuntimeError("Native probe retains an unresolved source placeholder")
	return source


def run_profile(godot: str, project: Path, script: Path, report: Path, instrumented: bool) -> str:
	log_path = report.parent / f"{report.stem}.log"
	if report.exists() or log_path.exists():
		raise RuntimeError(f"Refusing to reuse native profile output: {report}")
	command = [godot, "--headless", "--path", str(project), "--script", str(script), "--",
		str(report), "true" if instrumented else "false"]
	result = subprocess.run(command, text=True, capture_output=True, timeout=240, check=False)
	combined = result.stdout + result.stderr
	log_path.write_text(combined, encoding="utf-8")
	if result.returncode != 0 or ERROR_RE.search(combined):
		raise RuntimeError(f"Native prepared profile failed ({result.returncode}): {script}\n{combined}")
	if not report.is_file():
		raise RuntimeError(f"Godot did not write profile report: {report}\n{combined}")
	return combined


def check_build(path: Path, baseline: Path, instrumented: Path) -> dict[str, Any]:
	manifest = read_json(path)
	if (manifest.get("format") != "openrc-e0b6p-prepared-native-attribution-build v1" or
			manifest.get("instrumentation_api") != "openrc-e0b6p-prepared-native-attribution v1"):
		raise RuntimeError("Unexpected prepared attribution build manifest format")
	for label, record in manifest.get("sources", {}).items():
		item = ROOT / str(record.get("path", ""))
		if not item.is_file() or sha256(item) != record.get("sha256"):
			raise RuntimeError(f"Instrumented build is stale: {label}")
	for label, path_value in (("baseline library", baseline), ("prepared library", Path(manifest["prepared_library"]["path"])),
			("instrumented library", instrumented)):
		if not path_value.is_file():
			raise RuntimeError(f"Missing {label}: {path_value}")
		key = {"baseline library": "baseline_library", "prepared library": "prepared_library",
			"instrumented library": "instrumented_library"}[label]
		if sha256(path_value) != manifest[key]["sha256"]:
			raise RuntimeError(f"{label} differs from the attribution build manifest")
	if baseline.resolve() != Path(manifest["baseline_library"]["path"]).resolve():
		raise RuntimeError("Selected baseline is not the one captured by the attribution build")
	if instrumented.resolve() != Path(manifest["instrumented_library"]["path"]).resolve():
		raise RuntimeError("Selected instrumented library is not the one captured by the attribution build")
	return manifest


def run_prepared_verifiers(godot: str, app: Path, probe: Path, output: Path) -> dict[str, Any]:
	results: dict[str, Any] = {}
	for name in ("verify_lifecycle", "verify_adapter", "verify_fields", "verify_native"):
		report_path = output / f"instrumented-{name}.json"
		prepared.execute(godot, app, probe / f"{name}.gd", report_path)
		report = native._read_json(report_path)
		key = "failed" if name == "verify_fields" else "failures"
		if not nonnegative_integer(report.get(key)) or report[key] != 0:
			raise RuntimeError(f"Instrumented candidate failed {name}: {report}")
		expected = {"verify_lifecycle": ("case_count", 68), "verify_adapter": ("case_count", 35),
			"verify_fields": ("cases", 165), "verify_native": ("compared_loads", 297)}[name]
		if not nonnegative_integer(report.get(expected[0])) or report[expected[0]] != expected[1]:
			raise RuntimeError(f"Instrumented candidate {name} did not cover {expected[1]} cases")
		results[name] = {"path": str(report_path), "count_key": expected[0], "count": expected[1], "failures": 0}
	return results


def check_adapter_mutations(godot: str, app: Path, probe: Path, output: Path) -> list[dict[str, Any]]:
	rows = prepared.check_adapter_mutations(godot, app, probe, output)
	if len(rows) != 2 or any(not row.get("rejected", False) for row in rows):
		raise RuntimeError("Prepared adapter lifecycle mutation checks did not reject every defect")
	return rows


def main() -> None:
	comparator_controls = self_check_comparator()
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument("--project", type=Path, default=ROOT / "app", help="stable Godot app to copy")
	parser.add_argument("--godot", required=True, help="Godot 4.7 executable")
	parser.add_argument("--baseline-library", type=Path, default=BASELINE_LIBRARY)
	parser.add_argument("--prepared-build", type=Path, default=PREPARED_BUILD_MANIFEST)
	parser.add_argument("--build", type=Path, default=BUILD_MANIFEST)
	parser.add_argument("--instrumented-library", type=Path)
	parser.add_argument("--output", type=Path, required=True)
	parser.add_argument("--keep-work", action="store_true")
	args = parser.parse_args()
	project = args.project.expanduser().resolve()
	baseline = args.baseline_library.expanduser().resolve()
	output = args.output.expanduser().resolve()
	if not (project / "project.godot").is_file():
		raise RuntimeError(f"Project is not a Godot app: {project}")
	build_path = args.build.expanduser().resolve()
	prepared_build_path = args.prepared_build.expanduser().resolve()
	build_manifest = read_json(build_path)
	instrumented = args.instrumented_library.expanduser().resolve() if args.instrumented_library else Path(
		build_manifest.get("instrumented_library", {}).get("path", "")).resolve()
	manifest = check_build(build_path, baseline, instrumented)
	prepared_manifest = read_json(prepared_build_path)
	if prepared_manifest.get("format") != "openrc-e0b6p-prepared-model-build v1":
		raise RuntimeError("Unexpected prepared-model build manifest format")
	prepared_library = Path(prepared_manifest.get("library", {}).get("path", "")).resolve()
	if sha256(prepared_library) != prepared_manifest["library"]["sha256"]:
		raise RuntimeError("Prepared-model library changed after validation")
	if manifest["prepared_library"]["sha256"] != prepared_manifest["library"]["sha256"]:
		raise RuntimeError("Instrumented and ordinary prepared builds use different candidate libraries")
	if not baseline.is_file() or not instrumented.is_file():
		raise RuntimeError("Baseline or instrumented native library does not exist")
	godot = native._resolve_godot(args.godot)
	provenance_before = provenance_snapshot(
		project, build_path, prepared_build_path, manifest, baseline, prepared_library, instrumented)
	output.mkdir(parents=True, exist_ok=False)
	temporary: tempfile.TemporaryDirectory[str] | None = None
	if args.keep_work:
		work_root = Path(tempfile.mkdtemp(prefix="work-", dir=output))
	else:
		temporary = tempfile.TemporaryDirectory(prefix="openrc-prepared-native-cost-")
		work_root = Path(temporary.name)
	baseline_app = work_root / "baseline-app"
	instrumented_app = work_root / "instrumented-app"
	evidence_path = output / "native-evidence.json"
	evidence: dict[str, Any] = {
		"format": "openrc-e0b6p-prepared-native-attribution v1",
		"status": "running",
		"project": str(project),
		"godot": godot,
		"baseline_library_sha256": sha256(baseline),
		"prepared_library_sha256": sha256(prepared_library),
		"instrumented_library_sha256": sha256(instrumented),
		"build_manifest_sha256": sha256(build_path),
		"prepared_build_manifest_sha256": sha256(prepared_build_path),
		"builder_sha256": sha256(HERE / "native_build.py"),
		"runner_sha256": sha256(Path(__file__).resolve()),
		"probe_sha256": sha256(HERE / "native_probe.gd"),
		"host_platform": platform.platform(),
		"host_arch": platform.machine(),
		"python": platform.python_version(),
		"output": str(output),
		"keep_work": args.keep_work,
		"work_root": str(work_root) if args.keep_work else None,
		"provenance_before": provenance_before,
		"provenance_before_summary": summarize_provenance(provenance_before),
		"measurement_note": (
			"Baseline and prepared measurements run in separate Godot processes. Their timing difference is descriptive; "
			"shared-host noise and instrumentation prevent causal speedup claims. The native probe is a direct-call "
			"microbenchmark, not an additive decomposition of the separate whole-tick workload."
		),
		"timer_note": (
			"Static and dynamic kernel validation timers cover disjoint contiguous groups of the existing validator's "
			"checks in their original short-circuit order. Axial wake, axial profile, swirl, and finalization timers "
			"are sequential and non-overlapping. Prepared method and kernel totals are inclusive; reported phase buckets "
			"are exclusive within each level. Raw counters remain present. Clock correction subtracts the measured "
			"steady_clock pair cost multiplied by the recorded phase pair count; this does not remove counter updates "
			"or other instrumentation effects."
		),
		"marshalling_note": (
			"Native input decode covers C++ copies from PackedFloat64Array values and elevator/rudder Variant reads. "
			"The external-to-method remainder also includes Godot binding/marshalling, return conversion, Variant work, "
			"GDScript loop overhead beyond the empty-loop sample, and timer quantization; it is not a pure binding cost."
		),
	}
	error_message: str | None = None
	try:
		native._copy_project(project, instrumented_app)
		instrumented_probe = prepared.stage(instrumented_app, instrumented)
		(instrumented_probe / "native_probe.gd").write_text(profile_source(True), encoding="utf-8")
		evidence["instrumented_app_source_sha256"] = native._source_hashes(instrumented_app)
		evidence["instrumented_verification"] = run_prepared_verifiers(
			godot, instrumented_app, instrumented_probe, output)
		evidence["adapter_mutations_rejected"] = check_adapter_mutations(
			godot, instrumented_app, instrumented_probe, output)

		native._copy_project(project, baseline_app)
		baseline_probe = native._install_probe(baseline_app, baseline)
		(baseline_probe / "native_probe.gd").write_text(profile_source(False), encoding="utf-8")
		evidence["baseline_app_source_sha256"] = native._source_hashes(baseline_app)
		baseline_profile_path = output / "native-baseline-profile.json"
		run_profile(godot, baseline_app, baseline_probe / "native_probe.gd", baseline_profile_path, False)
		baseline_profile = read_json(baseline_profile_path)
		require_profile(baseline_profile, "baseline", False)
		evidence["baseline_profile"] = str(baseline_profile_path)

		instrumented_profile_path = output / "native-instrumented-profile.json"
		run_profile(godot, instrumented_app, instrumented_probe / "native_probe.gd",
			instrumented_profile_path, True)
		instrumented_profile = read_json(instrumented_profile_path)
		require_profile(instrumented_profile, "instrumented", True)
		evidence["instrumented_profile"] = str(instrumented_profile_path)
		evidence["profile_comparison"] = compare_profiles(baseline_profile, instrumented_profile)
		evidence["phase_summary"] = phase_summary(instrumented_profile)
		evidence["comparator_negative_controls"] = comparator_controls
		evidence["status"] = "pass"
	except Exception as error:
		error_message = str(error)
		evidence.update(status="fail", error=error_message)
	finally:
		try:
			provenance_after = provenance_snapshot(
				project, build_path, prepared_build_path, manifest, baseline, prepared_library, instrumented)
			evidence["provenance_after"] = provenance_after
			evidence["provenance_after_summary"] = summarize_provenance(provenance_after)
			changed = changed_provenance_paths(provenance_before, provenance_after)
			evidence["provenance_changed_paths"] = changed
			evidence["provenance_stable"] = not changed
			if changed:
				evidence.update(status="fail", error="Source/build provenance changed during staging or measurement")
		except Exception as provenance_error:
			evidence["provenance_recheck_error"] = str(provenance_error)
			evidence.update(status="fail", error="Could not recheck source/build provenance at end")
		try:
			evidence_path.write_text(json.dumps(evidence, indent=2, allow_nan=False) + "\n", encoding="utf-8")
		except Exception as evidence_error:
			if error_message is None:
				error_message = f"Could not write final evidence: {evidence_error}"
		if temporary is not None:
			temporary.cleanup()
	if evidence.get("status") != "pass":
		raise SystemExit(
			f"Prepared native attribution failed; evidence: {evidence_path}\n"
			f"{evidence.get('error', error_message or 'unknown error')}"
		)
	print(f"Prepared native attribution passed; evidence: {evidence_path}")
	for row in evidence["phase_summary"]:
		phase = row["kernel_phase_ns_per_call_median_clock_corrected"]
		print(
			f"{row['regime']}: static validate {phase['static_validation_ns']:.0f} ns, "
			f"dynamic validate {phase['dynamic_validation_ns']:.0f} ns, "
			f"axial profile {phase['axial_profile_ns']:.0f} ns, swirl {phase['swirl_ns']:.0f} ns, "
			f"method {row['prepared_method_and_phase_ns_per_call_median_raw']['prepared_method_total_ns']:.0f} ns"
		)
	if args.keep_work:
		print(f"Staged projects retained under: {work_root}")


if __name__ == "__main__":
	main()
