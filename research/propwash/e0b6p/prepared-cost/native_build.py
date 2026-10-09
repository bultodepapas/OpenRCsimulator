#!/usr/bin/env python3
"""Build an isolated, instrumented E0b6p prepared-model extension."""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import sys


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
PREPARED_DIR = ROOT / "research/propwash/e0b6p/prepared-model"
NATIVE_DIR = ROOT / "research/propwash/e0b6p/native"
LOCKED_BUILDER = ROOT / "research/native-slipstream/build.py"
TOOLCHAIN_LOCK = ROOT / "research/native-slipstream/toolchain-lock.json"
OUTPUT_ROOT = ROOT / ".tools/native-prepared-attribution"
BASELINE_LIBRARY = ROOT / ".tools/native-smooth-wake/libopenrc_slipstream.so"
PREPARED_BUILD = ROOT / ".tools/native-prepared/build.json"


def module(name: str, path: Path):
	module_spec = importlib.util.spec_from_file_location(name, path)
	if module_spec is None or module_spec.loader is None:
		raise RuntimeError(f"Could not import build helper: {path}")
	loaded = importlib.util.module_from_spec(module_spec)
	sys.modules[name] = loaded
	module_spec.loader.exec_module(loaded)
	return loaded


prepared = module("prepared_model_build", PREPARED_DIR / "build.py")
locked = prepared.locked


def sha256_bytes(value: bytes) -> str:
	return hashlib.sha256(value).hexdigest()


def sha256_file(path: Path) -> str:
	return sha256_bytes(path.read_bytes())


def replace_once(source: str, anchor: str, replacement: str, label: str) -> str:
	count = source.count(anchor)
	if count != 1:
		raise RuntimeError(f"Expected one {label} anchor, found {count}; refusing a stale instrumentation patch")
	return source.replace(anchor, replacement, 1)


def extract_function(source: str, signature: str) -> tuple[int, int, str]:
	if source.count(signature) != 1:
		raise RuntimeError(f"Expected one function signature: {signature}")
	start = source.index(signature)
	brace = source.index("{", start)
	depth = 0
	for index in range(brace, len(source)):
		if source[index] == "{":
			depth += 1
		elif source[index] == "}":
			depth -= 1
			if depth == 0:
				return start, index + 1, source[start:index + 1]
	raise RuntimeError(f"Could not find closing brace for: {signature}")


VALIDATE_SIGNATURE = "bool validate(const State13 &state, const Vec3 &velocity, const Pair &deflections, const Model &model,"
VALIDATE_SHA256 = "e29e0535beb7c1766c646944f918eb5f6a49cd4ff586c39337adf1285a9e5cdb"
LOADS_SIGNATURE = "bool loads(const State13 &state, const Vec3 &velocity, const Pair &deflections, const Model &model,"


def attribution_helpers() -> str:
	return """using AttributionClock = std::chrono::steady_clock;

struct AttributionStats {
	std::uint64_t prepared_calls = 0;
	std::uint64_t prepared_method_total_ns = 0;
	std::uint64_t prepared_dispatch_ns = 0;
	std::uint64_t prepared_input_decode_ns = 0;
	std::uint64_t prepared_transport_decode_ns = 0;
	std::uint64_t prepared_kernel_ns = 0;
	std::uint64_t prepared_pack_ns = 0;
	std::uint64_t prepare_calls = 0;
	std::uint64_t prepare_method_total_ns = 0;
	std::uint64_t prepare_model_decode_ns = 0;
	std::uint64_t prepare_validation_ns = 0;
	std::uint64_t kernel_calls = 0;
	std::uint64_t kernel_total_ns = 0;
	std::uint64_t static_validation_ns = 0;
	std::uint64_t dynamic_validation_ns = 0;
	std::uint64_t static_validation_timer_pairs = 0;
	std::uint64_t dynamic_validation_timer_pairs = 0;
	std::uint64_t axial_wake_ns = 0;
	std::uint64_t axial_profile_ns = 0;
	std::uint64_t swirl_ns = 0;
	std::uint64_t kernel_finalize_ns = 0;
};

thread_local AttributionStats g_attribution_stats;

std::uint64_t elapsed_attribution_ns(AttributionClock::time_point start) {
	return static_cast<std::uint64_t>(std::chrono::duration_cast<std::chrono::nanoseconds>(
			AttributionClock::now() - start).count());
}

struct ScopedAttributionTimer {
	std::uint64_t &target;
	std::uint64_t *pair_count;
	AttributionClock::time_point start = AttributionClock::now();
	ScopedAttributionTimer(std::uint64_t &value, std::uint64_t *pairs = nullptr)
			: target(value), pair_count(pairs) {}
	~ScopedAttributionTimer() {
		target += elapsed_attribution_ns(start);
		if (pair_count != nullptr) {
			++(*pair_count);
		}
	}
};

std::uint64_t attribution_clock_pair_overhead_ns() {
	static const std::uint64_t average = []() {
		constexpr std::uint64_t kSamples = 10000;
		std::uint64_t elapsed = 0;
		for (std::uint64_t i = 0; i < kSamples; ++i) {
			const auto start = AttributionClock::now();
			elapsed += static_cast<std::uint64_t>(std::chrono::duration_cast<std::chrono::nanoseconds>(
					AttributionClock::now() - start).count());
		}
		return elapsed / kSamples;
	}();
	return average;
}
"""


def instrument_validate(source: str) -> str:
	start, end, original = extract_function(source, VALIDATE_SIGNATURE)
	if sha256_bytes(original.encode()) != VALIDATE_SHA256:
		raise RuntimeError("The native validation function changed; review its classifications before instrumenting")
	validated = """bool validate(const State13 &state, const Vec3 &velocity, const Pair &deflections, const Model &model,
		const Pair &thrust_torque, double rho, double fade, double downwash_cl,
		const std::vector<double> &transported_dv) {
	{
		ScopedAttributionTimer timer(g_attribution_stats.dynamic_validation_ns,
				&g_attribution_stats.dynamic_validation_timer_pairs);
		for (double value : state) {
			if (!is_finite(value)) {
				return false;
			}
		}
		if (!is_finite(velocity) || !is_finite(deflections) || !is_finite(thrust_torque)) {
			return false;
		}
	}
	{
		ScopedAttributionTimer timer(g_attribution_stats.static_validation_ns,
				&g_attribution_stats.static_validation_timer_pairs);
		if (!is_finite(model.shaft_axis) || !is_finite(model.hub) || !is_finite(model.wash_factor) ||
				!is_finite(model.cg_le)) {
			return false;
		}
	}
	{
		ScopedAttributionTimer timer(g_attribution_stats.dynamic_validation_ns,
				&g_attribution_stats.dynamic_validation_timer_pairs);
		if (!is_finite(rho) || rho <= 0.0 || !is_finite(fade) || fade < 0.0 || fade > 1.0) {
			return false;
		}
	}
	{
		ScopedAttributionTimer timer(g_attribution_stats.static_validation_ns,
				&g_attribution_stats.static_validation_timer_pairs);
		if (!is_finite(model.propeller_diameter) || model.propeller_diameter <= 0.0 ||
				model.shaft_axis[0] != 1.0 || model.shaft_axis[1] != 0.0 || model.shaft_axis[2] != 0.0 ||
				!is_finite(model.swirl_factor) || !is_finite(model.vertical_drift) ||
				model.wash_factor[0] < 0.0 || model.wash_factor[0] > 2.0 ||
				model.wash_factor[1] < 0.0 || model.wash_factor[1] > 2.0 ||
				model.swirl_factor < 0.0 || model.swirl_factor > 1.0 ||
				model.vertical_drift < 0.0 || model.vertical_drift > 1.0 ||
				!is_finite(model.edge_fraction) || model.edge_fraction < 0.01 || model.edge_fraction > 0.5 ||
				!is_finite(model.tail_local_limit) || !is_finite(model.tail_stall_end) ||
				model.tail_stall_end <= model.tail_local_limit || !is_finite(model.tail_cd0) ||
				!is_finite(model.tail_k) || !is_finite(model.tail_cd90) || model.piece_count == 0 ||
				model.piece_count > 8) {
			return false;
		}
	}
	{
		ScopedAttributionTimer timer(g_attribution_stats.dynamic_validation_ns,
				&g_attribution_stats.dynamic_validation_timer_pairs);
		if (!transported_dv.empty() && transported_dv.size() != model.piece_count) {
			return false;
		}
		if (!std::isfinite(downwash_cl)) {
			if (!std::isnan(downwash_cl) || model.tails[0].has_free_slope) {
				return false;
			}
		}
		for (double value : transported_dv) {
			if (!is_finite(value)) {
				return false;
			}
		}
	}
	{
		ScopedAttributionTimer timer(g_attribution_stats.static_validation_ns,
				&g_attribution_stats.static_validation_timer_pairs);
		for (const TailSurface &tail : model.tails) {
			if (!is_finite(tail.position) || !is_finite(tail.lift_slope) || !is_finite(tail.free_slope) ||
					!is_finite(tail.control_effectiveness) || !is_finite(tail.incidence) ||
					!is_finite(tail.downwash_per_cl) || !is_finite(tail.elevator_tau) || !is_finite(tail.free_incidence)) {
				return false;
			}
		}
		for (std::size_t i = 0; i < model.piece_count; ++i) {
			const Piece &piece = model.pieces[i];
			if (piece.surface > 1 || !is_finite(piece.area) || piece.area < 0.001 || piece.area > 1.0 ||
					!is_finite(piece.span) || piece.span < 0.01 || piece.span > 2.0 ||
					!is_finite(piece.root) || !is_finite(piece.span_dir) || piece.profile_count == 0 ||
					piece.profile_count > kMaxProfileIntervals || piece.root[0] <= model.hub[0]) {
				return false;
			}
			const double span_dir_length = std::sqrt(piece.span_dir[0] * piece.span_dir[0] +
					piece.span_dir[1] * piece.span_dir[1] + piece.span_dir[2] * piece.span_dir[2]);
			if (!is_finite(span_dir_length) || std::abs(span_dir_length - 1.0) > 1.0e-6) {
				return false;
			}
			if (piece.span_dir[0] != 0.0 || (piece.surface == 0 ? piece.span_dir[2] != 0.0 : piece.span_dir[1] != 0.0)) {
				return false;
			}
			double previous = 0.0;
			double profile_area = 0.0;
			for (std::size_t j = 0; j < piece.profile_count; ++j) {
				const ProfileInterval &segment = piece.profile[j];
				if (!is_finite(segment.start) || !is_finite(segment.end) || !is_finite(segment.chord_start) ||
						!is_finite(segment.chord_end) || segment.start < previous || segment.start < 0.0 ||
						segment.end <= segment.start || segment.end > 3.0 || segment.end > piece.span + 1.0e-10 ||
						segment.chord_start < 0.0 || segment.chord_start > 3.0 || segment.chord_end < 0.0 ||
						segment.chord_end > 3.0 || segment.chord_start + segment.chord_end <= 0.0) {
					return false;
				}
				profile_area += 0.5 * (segment.chord_start + segment.chord_end) * (segment.end - segment.start);
				previous = segment.end;
			}
			if (!is_finite(profile_area) || std::abs(profile_area - piece.area) > 1.0e-8) {
				return false;
			}
		}
	}
	return true;
}"""
	return source[:start] + validated + source[end:]


def instrument_kernel_loads(source: str) -> str:
	start, end, original = extract_function(source, LOADS_SIGNATURE)
	if "g_attribution_stats.kernel_calls" in original:
		raise RuntimeError("Kernel loads function is already instrumented")
	instrumented = """bool loads(const State13 &state, const Vec3 &velocity, const Pair &deflections, const Model &model,
		const Pair &thrust_torque, double rho, double fade, double downwash_cl,
		const std::vector<double> &transported_dv, Loads6 &output) {
	++g_attribution_stats.kernel_calls;
	ScopedAttributionTimer kernel_timer(g_attribution_stats.kernel_total_ns);
	output = Loads6{0.0, 0.0, 0.0, 0.0, 0.0, 0.0};
	if (!validate(state, velocity, deflections, model, thrust_torque, rho, fade, downwash_cl, transported_dv)) {
		return false;
	}
	if (fade == 0.0) {
		return true;
	}
	Wake wake;
	bool wake_valid = false;
	{
		ScopedAttributionTimer timer(g_attribution_stats.axial_wake_ns);
		wake_valid = compute_wake(velocity, thrust_torque, model, rho, wake);
	}
	if (!wake_valid) {
		return false;
	}
	const double wing_cl = model.tails[0].has_free_slope ? downwash_cl : 0.0;
	bool profile_valid = false;
	{
		ScopedAttributionTimer timer(g_attribution_stats.axial_profile_ns);
		profile_valid = profile_centroid_loads(state, velocity, deflections, model, wake, rho, fade, wing_cl,
				transported_dv, output);
	}
	if (!profile_valid) {
		output = Loads6{0.0, 0.0, 0.0, 0.0, 0.0, 0.0};
		return false;
	}
	Loads6 correction{};
	bool swirl_valid = false;
	{
		ScopedAttributionTimer timer(g_attribution_stats.swirl_ns);
		swirl_valid = swirl_correction(state, velocity, deflections, model, wake, fade, rho, wing_cl, correction);
	}
	if (!swirl_valid) {
		output = Loads6{0.0, 0.0, 0.0, 0.0, 0.0, 0.0};
		return false;
	}
	{
		ScopedAttributionTimer timer(g_attribution_stats.kernel_finalize_ns);
		for (std::size_t component = 0; component < output.size(); ++component) {
			output[component] += correction[component];
		}
		if (!is_finite(output)) {
			output = Loads6{0.0, 0.0, 0.0, 0.0, 0.0, 0.0};
			return false;
		}
	}
	return true;
}"""
	return source[:start] + instrumented + source[end:]


def instrument_prepared_snippet(source: str) -> str:
	method_start = "\tint64_t prepare_model(const godot::Dictionary &model_value) {\n"
	source = replace_once(source, method_start, method_start + "\t\t++g_attribution_stats.prepare_calls;\n\t\tScopedAttributionTimer method_timer(g_attribution_stats.prepare_method_total_ns);\n", "prepare method start")
	source = replace_once(source,
		"\t\tif (!read_model(model_value, candidate)) {\n\t\t\treturn 0;\n\t\t}\n",
		"\t\tbool model_read = false;\n\t\t{\n\t\t\tScopedAttributionTimer timer(g_attribution_stats.prepare_model_decode_ns);\n\t\t\tmodel_read = read_model(model_value, candidate);\n\t\t}\n\t\tif (!model_read) {\n\t\t\treturn 0;\n\t\t}\n", "prepare model decode")
	source = replace_once(source,
		"\t\tif (!validate(state, velocity, deflections, candidate, thrust_torque, 1.225, 1.0, downwash_cl,\n\t\t\t\ttransported_dv)) {\n\t\t\treturn 0;\n\t\t}\n",
		"\t\tbool candidate_valid = false;\n\t\t{\n\t\t\tScopedAttributionTimer timer(g_attribution_stats.prepare_validation_ns);\n\t\t\tcandidate_valid = validate(state, velocity, deflections, candidate, thrust_torque, 1.225, 1.0, downwash_cl,\n\t\t\t\t\ttransported_dv);\n\t\t}\n\t\tif (!candidate_valid) {\n\t\t\treturn 0;\n\t\t}\n", "prepare validation")

	old_loads = """\tgodot::PackedFloat64Array loads_prepared(const godot::PackedFloat64Array &state_value,
	\tconst godot::PackedFloat64Array &velocity_value, const godot::Dictionary &deflections_value,
	\t\tint64_t token, const godot::PackedFloat64Array &thrust_torque_value,
	\t\tdouble rho, double fade, double downwash_cl, const godot::PackedFloat64Array &transported_dv_value) {
	\tif (!model_valid_ || token <= 0 || token != active_generation_ ||
	\t\t\tstate_value.size() != 13 || velocity_value.size() != 3 || thrust_torque_value.size() != 2) {
	\t\treturn godot::PackedFloat64Array();
	\t}
	\tState13 state{};
	\tVec3 velocity{};
	\tPair thrust_torque{};
	\tfor (int64_t i = 0; i < state_value.size(); ++i) {
	\t\tstate[static_cast<std::size_t>(i)] = state_value[i];
	\t}
	\tfor (int64_t i = 0; i < velocity_value.size(); ++i) {
	\t\tvelocity[static_cast<std::size_t>(i)] = velocity_value[i];
	\t}
	\tfor (int64_t i = 0; i < thrust_torque_value.size(); ++i) {
	\t\tthrust_torque[static_cast<std::size_t>(i)] = thrust_torque_value[i];
	\t}
	\tPair deflections{};
	\tif (!read_number(deflections_value, "elevator", deflections[0]) ||
	\t\t\t!read_number(deflections_value, "rudder", deflections[1])) {
	\t\treturn godot::PackedFloat64Array();
	\t}
	\tif (!transported_dv_value.is_empty() &&
	\t\t\tstatic_cast<std::size_t>(transported_dv_value.size()) != model_.piece_count) {
	\t\treturn godot::PackedFloat64Array();
	\t}
	\tstd::vector<double> transported_dv;
	\ttransported_dv.reserve(static_cast<std::size_t>(transported_dv_value.size()));
	\tfor (int64_t i = 0; i < transported_dv_value.size(); ++i) {
	\t\ttransported_dv.push_back(transported_dv_value[i]);
	\t}
	\tLoads6 result{};
	\tif (!openrc::smooth_wake::loads(state, velocity, deflections, model_, thrust_torque, rho, fade,
	\t\t\tdownwash_cl, transported_dv, result)) {
	\t\treturn godot::PackedFloat64Array();
	\t}
	\treturn pack_loads(result);
	}"""
	new_loads = """\tgodot::PackedFloat64Array loads_prepared(const godot::PackedFloat64Array &state_value,
	\tconst godot::PackedFloat64Array &velocity_value, const godot::Dictionary &deflections_value,
	\t\tint64_t token, const godot::PackedFloat64Array &thrust_torque_value,
	\t\tdouble rho, double fade, double downwash_cl, const godot::PackedFloat64Array &transported_dv_value) {
	\t++g_attribution_stats.prepared_calls;
	\tScopedAttributionTimer method_timer(g_attribution_stats.prepared_method_total_ns);
	\t{
	\t\tScopedAttributionTimer timer(g_attribution_stats.prepared_dispatch_ns);
	\t\tif (!model_valid_ || token <= 0 || token != active_generation_ ||
	\t\t\t\tstate_value.size() != 13 || velocity_value.size() != 3 || thrust_torque_value.size() != 2) {
	\t\t\treturn godot::PackedFloat64Array();
	\t\t}
	\t}
	\tState13 state{};
	\tVec3 velocity{};
	\tPair thrust_torque{};
	\tPair deflections{};
	\t{
	\t\tScopedAttributionTimer timer(g_attribution_stats.prepared_input_decode_ns);
	\t\tfor (int64_t i = 0; i < state_value.size(); ++i) {
	\t\t\tstate[static_cast<std::size_t>(i)] = state_value[i];
	\t\t}
	\t\tfor (int64_t i = 0; i < velocity_value.size(); ++i) {
	\t\t\tvelocity[static_cast<std::size_t>(i)] = velocity_value[i];
	\t\t}
	\t\tfor (int64_t i = 0; i < thrust_torque_value.size(); ++i) {
	\t\t\tthrust_torque[static_cast<std::size_t>(i)] = thrust_torque_value[i];
	\t\t}
	\t\tif (!read_number(deflections_value, "elevator", deflections[0]) ||
	\t\t\t\t!read_number(deflections_value, "rudder", deflections[1])) {
	\t\t\treturn godot::PackedFloat64Array();
	\t\t}
	\t}
	\tstd::vector<double> transported_dv;
	\t{
	\t\tScopedAttributionTimer timer(g_attribution_stats.prepared_transport_decode_ns);
	\t\tif (!transported_dv_value.is_empty() &&
	\t\t\t\tstatic_cast<std::size_t>(transported_dv_value.size()) != model_.piece_count) {
	\t\t\treturn godot::PackedFloat64Array();
	\t\t}
	\t\ttransported_dv.reserve(static_cast<std::size_t>(transported_dv_value.size()));
	\t\tfor (int64_t i = 0; i < transported_dv_value.size(); ++i) {
	\t\t\ttransported_dv.push_back(transported_dv_value[i]);
	\t\t}
	\t}
	\tLoads6 result{};
	\tbool loaded = false;
	\t{
	\t\tScopedAttributionTimer timer(g_attribution_stats.prepared_kernel_ns);
	\t\tloaded = openrc::smooth_wake::loads(state, velocity, deflections, model_, thrust_torque, rho, fade,
	\t\t\t\tdownwash_cl, transported_dv, result);
	\t}
	\tif (!loaded) {
	\t\treturn godot::PackedFloat64Array();
	\t}
	\tgodot::PackedFloat64Array packed;
	\t{
	\t\tScopedAttributionTimer timer(g_attribution_stats.prepared_pack_ns);
	\t\tpacked = pack_loads(result);
	\t}
	\treturn packed;
	}"""
	if source.count(old_loads) != 1:
		raise RuntimeError("Prepared loads method changed; review its timer boundaries before instrumenting")
	return source.replace(old_loads, new_loads, 1)


def instrument_candidate(candidate: bytes) -> bytes:
	source = candidate.decode("utf-8")
	source = replace_once(source, "#include <cstdint>\n", "#include <cstdint>\n#include <chrono>\n", "chrono include")
	source = replace_once(source,
		"using Vec3 = openrc::smooth_wake::Vec3;\n\n",
		"using Vec3 = openrc::smooth_wake::Vec3;\n\n" + attribution_helpers() + "\n",
		"attribution helpers")
	source = instrument_validate(source)
	source = instrument_kernel_loads(source)
	source = instrument_prepared_snippet(source)
	# Add the deliberately opt-in counters to the candidate wrapper API only.
	source = replace_once(source,
		'\t\tgodot::ClassDB::bind_method(godot::D_METHOD("invalidate_model"), &OpenRCPreparedWake::invalidate_model);\n',
		'\t\tgodot::ClassDB::bind_method(godot::D_METHOD("invalidate_model"), &OpenRCPreparedWake::invalidate_model);\n'
		'\t\tgodot::ClassDB::bind_method(godot::D_METHOD("reset_attribution"), &OpenRCPreparedWake::reset_attribution);\n'
		'\t\tgodot::ClassDB::bind_method(godot::D_METHOD("get_attribution"), &OpenRCPreparedWake::get_attribution);\n',
		"counter method bindings")
	source = replace_once(source,
		"public:\n\t// Stateless baseline retained with the same API and decoding path.\n",
		"public:\n"
		"\tvoid reset_attribution() { g_attribution_stats = AttributionStats{}; }\n\n"
		"\tgodot::Dictionary get_attribution() const {\n"
		"\t\tgodot::Dictionary result;\n"
		"\t\tresult[\"prepared_calls\"] = static_cast<int64_t>(g_attribution_stats.prepared_calls);\n"
		"\t\tresult[\"calls\"] = static_cast<int64_t>(g_attribution_stats.prepared_calls);\n"
		"\t\tresult[\"prepared_method_total_ns\"] = static_cast<int64_t>(g_attribution_stats.prepared_method_total_ns);\n"
		"\t\tresult[\"prepared_dispatch_ns\"] = static_cast<int64_t>(g_attribution_stats.prepared_dispatch_ns);\n"
		"\t\tresult[\"prepared_input_decode_ns\"] = static_cast<int64_t>(g_attribution_stats.prepared_input_decode_ns);\n"
		"\t\tresult[\"prepared_transport_decode_ns\"] = static_cast<int64_t>(g_attribution_stats.prepared_transport_decode_ns);\n"
		"\t\tresult[\"prepared_kernel_ns\"] = static_cast<int64_t>(g_attribution_stats.prepared_kernel_ns);\n"
		"\t\tresult[\"prepared_pack_ns\"] = static_cast<int64_t>(g_attribution_stats.prepared_pack_ns);\n"
		"\t\tresult[\"prepare_calls\"] = static_cast<int64_t>(g_attribution_stats.prepare_calls);\n"
		"\t\tresult[\"prepare_method_total_ns\"] = static_cast<int64_t>(g_attribution_stats.prepare_method_total_ns);\n"
		"\t\tresult[\"prepare_model_decode_ns\"] = static_cast<int64_t>(g_attribution_stats.prepare_model_decode_ns);\n"
		"\t\tresult[\"prepare_validation_ns\"] = static_cast<int64_t>(g_attribution_stats.prepare_validation_ns);\n"
		"\t\tresult[\"kernel_calls\"] = static_cast<int64_t>(g_attribution_stats.kernel_calls);\n"
		"\t\tresult[\"kernel_total_ns\"] = static_cast<int64_t>(g_attribution_stats.kernel_total_ns);\n"
		"\t\tresult[\"static_validation_ns\"] = static_cast<int64_t>(g_attribution_stats.static_validation_ns);\n"
		"\t\tresult[\"dynamic_validation_ns\"] = static_cast<int64_t>(g_attribution_stats.dynamic_validation_ns);\n"
		"\t\tresult[\"static_validation_timer_pairs\"] = static_cast<int64_t>(g_attribution_stats.static_validation_timer_pairs);\n"
		"\t\tresult[\"dynamic_validation_timer_pairs\"] = static_cast<int64_t>(g_attribution_stats.dynamic_validation_timer_pairs);\n"
		"\t\tresult[\"axial_wake_ns\"] = static_cast<int64_t>(g_attribution_stats.axial_wake_ns);\n"
		"\t\tresult[\"axial_profile_ns\"] = static_cast<int64_t>(g_attribution_stats.axial_profile_ns);\n"
		"\t\tresult[\"swirl_ns\"] = static_cast<int64_t>(g_attribution_stats.swirl_ns);\n"
		"\t\tresult[\"kernel_finalize_ns\"] = static_cast<int64_t>(g_attribution_stats.kernel_finalize_ns);\n"
		"\t\tresult[\"clock_pair_overhead_ns\"] = static_cast<int64_t>(attribution_clock_pair_overhead_ns());\n"
		"\t\treturn result;\n"
		"\t}\n\n"
		"\t// Stateless baseline retained with the same API and decoding path.\n",
		"counter methods")
	return source.encode("utf-8")


def checked_manifest(path: Path, label: str) -> dict:
	try:
		manifest = json.loads(path.read_text(encoding="utf-8"))
	except (OSError, json.JSONDecodeError) as error:
		raise RuntimeError(f"Could not read {label} manifest {path}: {error}") from error
	if not isinstance(manifest, dict):
		raise RuntimeError(f"{label} manifest is not an object: {path}")
	return manifest


def check_prepared_build(path: Path) -> dict:
	manifest = checked_manifest(path, "prepared model build")
	if manifest.get("format") != "openrc-e0b6p-prepared-model-build v1":
		raise RuntimeError("Unexpected prepared-model build manifest format")
	for label, record in manifest.get("sources", {}).items():
		source_path = ROOT / str(record.get("path", ""))
		if not source_path.is_file() or sha256_file(source_path) != record.get("sha256"):
			raise RuntimeError(f"Prepared-model build is stale: {label}")
	library_record = manifest.get("library", {})
	library = Path(str(library_record.get("path", "")))
	if not library.is_file() or sha256_file(library) != library_record.get("sha256"):
		raise RuntimeError("Prepared-model library differs from its build manifest")
	return manifest


def build(args: argparse.Namespace) -> None:
	prepared_manifest = check_prepared_build(args.prepared_build.resolve())
	if not BASELINE_LIBRARY.is_file():
		raise SystemExit(f"Baseline native library is missing: {BASELINE_LIBRARY}")
	contents, source_manifest = prepared.snapshot_inputs()
	expected_candidate = prepared.candidate_source(contents[prepared.ORIGINAL], contents[prepared.SNIPPET])
	if sha256_bytes(expected_candidate) != prepared_manifest["sources"]["generated_candidate"]["sha256"]:
		raise RuntimeError("Prepared-model generated candidate does not match its validated build manifest")
	instrumented_candidate = instrument_candidate(expected_candidate)
	lock = json.loads(contents[TOOLCHAIN_LOCK])
	host = locked.host_platform_name()
	arch = locked.host_arch_name()
	env = os.environ.copy()
	compiler_version = None
	if host == "linux":
		compiler_version = locked.run(["g++", "-dumpfullversion", "-dumpversion"], capture=True).strip()
		if compiler_version != lock["linux"]["compiler_version"]:
			raise SystemExit(f"Expected locked g++ {lock['linux']['compiler_version']}, got {compiler_version}")
		env.update(CC="gcc", CXX="g++")
	scons = locked.ensure_scons(lock)
	dependency = locked.ensure_godot_cpp(lock)

	generated_root = OUTPUT_ROOT / "src"
	generated_root.mkdir(parents=True, exist_ok=True)
	generated_source = generated_root / "smooth_wake_prepared_instrumented.cpp"
	generated_source.write_bytes(instrumented_candidate)
	generated_header = generated_root / prepared.KERNEL.name
	generated_header.write_bytes(contents[prepared.KERNEL])
	profile = lock["godot_cpp"]["build_profile"]
	profile_text = json.dumps(profile["content"], sort_keys=True, separators=(",", ":")) + "\n"
	if sha256_bytes(profile_text.encode()) != profile["sha256"]:
		raise RuntimeError("Locked build profile hash mismatch")
	build_root = OUTPUT_ROOT / f"{host}-{arch}"
	build_root.mkdir(parents=True, exist_ok=True)
	profile_path = build_root / "build_profile.json"
	profile_path.write_text(profile_text, encoding="utf-8")
	sconstruct = locked.sconstruct_text(
		dependency, generated_root, build_root / "lib", profile_path, lock["godot"]["extension_api"])
	if sconstruct.count('"openrc_slipstream"') != 1:
		raise RuntimeError("Locked SConstruct library marker changed; refusing an unexpected output name")
	(build_root / "SConstruct").write_text(
		sconstruct.replace('"openrc_slipstream"', '"openrc_prepared_wake"'), encoding="utf-8")
	locked.run([*scons, "-C", str(build_root), f"-j{args.jobs}", f"platform={host}",
		f"arch={arch}", "target=template_release"], env=env)

	library_name = prepared.library_name(host)
	output = (args.output or OUTPUT_ROOT / library_name).resolve()
	prepared_library = Path(prepared_manifest["library"]["path"]).resolve()
	if output == prepared_library or output == BASELINE_LIBRARY.resolve():
		raise RuntimeError("Refusing to overwrite the baseline or uninstrumented prepared-model library")
	output.parent.mkdir(parents=True, exist_ok=True)
	if any(not path.is_file() or path.read_bytes() != initial for path, initial in contents.items()):
		raise RuntimeError("A captured native/toolchain input changed during compilation")
	if generated_source.read_bytes() != instrumented_candidate or generated_header.read_bytes() != contents[prepared.KERNEL]:
		raise RuntimeError("Generated instrumented source changed during compilation")
	baseline_sha256 = sha256_file(BASELINE_LIBRARY)
	prepared_library_sha256 = sha256_file(prepared_library)
	temporary_library = output.with_name(f".{output.name}.tmp-{os.getpid()}")
	try:
		shutil.copy2(build_root / "lib" / library_name, temporary_library)
		library_sha256 = sha256_file(temporary_library)
		if any(not path.is_file() or path.read_bytes() != initial for path, initial in contents.items()):
			raise RuntimeError("A captured native/toolchain input changed before publishing the library")
		if sha256_file(BASELINE_LIBRARY) != baseline_sha256 or sha256_file(prepared_library) != prepared_library_sha256:
			raise RuntimeError("A reference library changed during compilation")
		os.replace(temporary_library, output)
	finally:
		temporary_library.unlink(missing_ok=True)

	manifest = {
		"format": "openrc-e0b6p-prepared-native-attribution-build v1",
		"instrumentation_api": "openrc-e0b6p-prepared-native-attribution v1",
		"instrumentation_fields": [
			"prepared_method_total_ns", "prepared_dispatch_ns", "prepared_input_decode_ns",
			"prepared_transport_decode_ns", "prepared_kernel_ns", "prepared_pack_ns",
			"prepare_method_total_ns", "prepare_model_decode_ns", "prepare_validation_ns",
			"static_validation_ns", "dynamic_validation_ns", "axial_wake_ns", "axial_profile_ns", "swirl_ns",
		],
		"toolchain": {
			"platform": host, "architecture": arch, "compiler_version": compiler_version,
			"godot_cpp_commit": lock["godot_cpp"]["commit"],
			"godot_extension_api": lock["godot"]["extension_api"],
			"build_profile_sha256": sha256_bytes(profile_text.encode()),
		},
		"sources": source_manifest | {
			"generated_instrumented_candidate": {
				"path": str(generated_source.relative_to(ROOT)), "sha256": sha256_bytes(instrumented_candidate),
			},
			"instrumentation_builder": {
				"path": str(Path(__file__).resolve().relative_to(ROOT)), "sha256": sha256_file(Path(__file__).resolve()),
			},
			"prepared_build_manifest": {
				"path": str(args.prepared_build.resolve().relative_to(ROOT)),
				"sha256": sha256_file(args.prepared_build.resolve()),
			},
		},
		"baseline_library": {"path": str(BASELINE_LIBRARY), "sha256": baseline_sha256},
		"prepared_library": {"path": str(prepared_library), "sha256": prepared_library_sha256},
		"instrumented_library": {"path": str(output), "sha256": library_sha256},
	}
	manifest_path = OUTPUT_ROOT / "build.json"
	temporary_manifest = manifest_path.with_name(f".{manifest_path.name}.tmp-{os.getpid()}")
	try:
		temporary_manifest.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
		os.replace(temporary_manifest, manifest_path)
	finally:
		temporary_manifest.unlink(missing_ok=True)
	print(f"Built isolated prepared attribution library: {output}")
	print(f"Build manifest: {manifest_path}")


def main() -> None:
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument("--jobs", type=int, default=2)
	parser.add_argument("--prepared-build", type=Path, default=PREPARED_BUILD)
	parser.add_argument("--output", type=Path)
	args = parser.parse_args()
	if args.jobs < 1:
		parser.error("--jobs must be positive")
	OUTPUT_ROOT.mkdir(parents=True, exist_ok=True)
	build_lock = OUTPUT_ROOT / ".build.lock"
	try:
		build_lock.mkdir()
	except FileExistsError as error:
		raise SystemExit(f"A prepared attribution build lock exists at {build_lock}; inspect it before retrying") from error
	try:
		(build_lock / "owner.txt").write_text(f"pid={os.getpid()}\n", encoding="utf-8")
		build(args)
	finally:
		shutil.rmtree(build_lock, ignore_errors=True)


if __name__ == "__main__":
	main()
