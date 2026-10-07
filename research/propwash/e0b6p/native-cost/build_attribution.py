#!/usr/bin/env python3
"""Build a separately instrumented copy of the E0b6p native extension."""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
SOURCE_DIR = ROOT / "research/propwash/e0b6p/native/src"
BASELINE_LIBRARY = ROOT / ".tools/native-smooth-wake/libopenrc_slipstream.so"
LOCKED_BUILDER = ROOT / "research/native-slipstream/build.py"
SPEC = importlib.util.spec_from_file_location("gate_p_build", LOCKED_BUILDER)
locked = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(locked)


def replace_once(source: str, anchor: str, replacement: str, label: str) -> str:
    count = source.count(anchor)
    if count != 1:
        raise RuntimeError(f"Expected one {label} anchor, found {count}; source has drifted")
    return source.replace(anchor, replacement, 1)


def instrument(source: str) -> str:
    source = replace_once(
        source,
        "#include <cstdint>\n",
        "#include <cstdint>\n#include <chrono>\n",
        "chrono include",
    )
    source = replace_once(
        source,
        "using Vec3 = openrc::smooth_wake::Vec3;\n\n",
        """using Vec3 = openrc::smooth_wake::Vec3;

using AttributionClock = std::chrono::steady_clock;

struct AttributionStats {
\tstd::uint64_t calls = 0;
\tstd::uint64_t method_total_ns = 0;
\tstd::uint64_t input_decode_ns = 0;
\tstd::uint64_t model_decode_ns = 0;
\tstd::uint64_t transported_decode_ns = 0;
\tstd::uint64_t kernel_total_ns = 0;
\tstd::uint64_t validate_ns = 0;
\tstd::uint64_t wake_ns = 0;
\tstd::uint64_t profile_ns = 0;
\tstd::uint64_t swirl_ns = 0;
\tstd::uint64_t kernel_finalize_ns = 0;
\tstd::uint64_t pack_ns = 0;
};

thread_local AttributionStats g_attribution_stats;

std::uint64_t elapsed_ns(AttributionClock::time_point start) {
\treturn static_cast<std::uint64_t>(std::chrono::duration_cast<std::chrono::nanoseconds>(
\t\t\tAttributionClock::now() - start).count());
}

struct ScopedAttributionTimer {
\tstd::uint64_t &target;
\tAttributionClock::time_point start = AttributionClock::now();
\texplicit ScopedAttributionTimer(std::uint64_t &value) : target(value) {}
\t~ScopedAttributionTimer() { target += elapsed_ns(start); }
};

std::uint64_t clock_pair_overhead_ns() {
\tstatic const std::uint64_t average = []() {
\t\tconstexpr std::uint64_t kSamples = 10000;
\t\tstd::uint64_t elapsed = 0;
\t\tfor (std::uint64_t i = 0; i < kSamples; ++i) {
\t\t\tconst auto start = AttributionClock::now();
\t\t\telapsed += static_cast<std::uint64_t>(std::chrono::duration_cast<std::chrono::nanoseconds>(
\t\t\t\t\tAttributionClock::now() - start).count());
\t\t}
\t\treturn elapsed / kSamples;
\t}();
\treturn average;
}

""",
        "attribution counters",
    )
    original_core = """bool loads(const State13 &state, const Vec3 &velocity, const Pair &deflections, const Model &model,
		const Pair &thrust_torque, double rho, double fade, double downwash_cl,
		const std::vector<double> &transported_dv, Loads6 &output) {
	output = Loads6{0.0, 0.0, 0.0, 0.0, 0.0, 0.0};
	if (!validate(state, velocity, deflections, model, thrust_torque, rho, fade, downwash_cl, transported_dv)) {
		return false;
	}
	if (fade == 0.0) {
		return true;
	}
	Wake wake;
	if (!compute_wake(velocity, thrust_torque, model, rho, wake)) {
		return false;
	}
	const double wing_cl = model.tails[0].has_free_slope ? downwash_cl : 0.0;
	if (!profile_centroid_loads(state, velocity, deflections, model, wake, rho, fade, wing_cl,
			transported_dv, output)) {
		output = Loads6{0.0, 0.0, 0.0, 0.0, 0.0, 0.0};
		return false;
	}
	Loads6 correction{};
	if (!swirl_correction(state, velocity, deflections, model, wake, fade, rho, wing_cl, correction)) {
		output = Loads6{0.0, 0.0, 0.0, 0.0, 0.0, 0.0};
		return false;
	}
	for (std::size_t component = 0; component < output.size(); ++component) {
		output[component] += correction[component];
	}
	if (!is_finite(output)) {
		output = Loads6{0.0, 0.0, 0.0, 0.0, 0.0, 0.0};
		return false;
	}
	return true;
}"""
    timed_core = """bool loads(const State13 &state, const Vec3 &velocity, const Pair &deflections, const Model &model,
		const Pair &thrust_torque, double rho, double fade, double downwash_cl,
		const std::vector<double> &transported_dv, Loads6 &output) {
	ScopedAttributionTimer kernel_timer(g_attribution_stats.kernel_total_ns);
	output = Loads6{0.0, 0.0, 0.0, 0.0, 0.0, 0.0};
	const auto validate_started = AttributionClock::now();
	const bool valid = validate(state, velocity, deflections, model, thrust_torque, rho, fade, downwash_cl, transported_dv);
	g_attribution_stats.validate_ns += elapsed_ns(validate_started);
	if (!valid) {
		return false;
	}
	if (fade == 0.0) {
		return true;
	}
	Wake wake;
	const auto wake_started = AttributionClock::now();
	const bool wake_valid = compute_wake(velocity, thrust_torque, model, rho, wake);
	g_attribution_stats.wake_ns += elapsed_ns(wake_started);
	if (!wake_valid) {
		return false;
	}
	const double wing_cl = model.tails[0].has_free_slope ? downwash_cl : 0.0;
	const auto profile_started = AttributionClock::now();
	const bool profile_valid = profile_centroid_loads(state, velocity, deflections, model, wake, rho, fade, wing_cl,
			transported_dv, output);
	g_attribution_stats.profile_ns += elapsed_ns(profile_started);
	if (!profile_valid) {
		output = Loads6{0.0, 0.0, 0.0, 0.0, 0.0, 0.0};
		return false;
	}
	Loads6 correction{};
	const auto swirl_started = AttributionClock::now();
	const bool swirl_valid = swirl_correction(state, velocity, deflections, model, wake, fade, rho, wing_cl, correction);
	g_attribution_stats.swirl_ns += elapsed_ns(swirl_started);
	if (!swirl_valid) {
		output = Loads6{0.0, 0.0, 0.0, 0.0, 0.0, 0.0};
		return false;
	}
	const auto finalize_started = AttributionClock::now();
	for (std::size_t component = 0; component < output.size(); ++component) {
		output[component] += correction[component];
	}
	const bool finite_output = is_finite(output);
	if (!finite_output) {
		output = Loads6{0.0, 0.0, 0.0, 0.0, 0.0, 0.0};
	}
	g_attribution_stats.kernel_finalize_ns += elapsed_ns(finalize_started);
	return finite_output;
}"""
    source = replace_once(source, original_core, timed_core, "core-load function")
    class_anchor = "class OpenRCSmoothWake final : public godot::RefCounted {"
    initializer_anchor = "\nvoid initialize_openrc_smooth_wake(godot::ModuleInitializationLevel level) {"
    start = source.find(class_anchor)
    end = source.find(initializer_anchor, start)
    if start < 0 or end < 0 or source.find(class_anchor, start + 1) >= 0:
        raise RuntimeError("Expected one native wrapper class region; source has drifted")
    original_class = source[start:end]
    expected_class_hash = "460b8d1e3d37968d6315fe2dddf59d4091c4fccb6dca7bc6c16bb500f38dfebd"
    actual_class_hash = hashlib.sha256(original_class.encode()).hexdigest()
    if actual_class_hash != expected_class_hash:
        raise RuntimeError(
            "Native wrapper class changed; refusing to replace an unexpected source region "
            f"(expected {expected_class_hash}, got {actual_class_hash})"
        )
    instrumented_class = """class OpenRCSmoothWake final : public godot::RefCounted {
	GDCLASS(OpenRCSmoothWake, godot::RefCounted)

protected:
	static void _bind_methods() {
		godot::ClassDB::bind_method(godot::D_METHOD("loads", "state", "velocity", "deflections", "model",
				"thrust_torque", "rho", "fade", "downwash_cl", "transported_dv"), &OpenRCSmoothWake::loads);
		godot::ClassDB::bind_method(godot::D_METHOD("reset_attribution"), &OpenRCSmoothWake::reset_attribution);
		godot::ClassDB::bind_method(godot::D_METHOD("get_attribution"), &OpenRCSmoothWake::get_attribution);
	}

public:
	void reset_attribution() {
		g_attribution_stats = AttributionStats{};
	}

	godot::Dictionary get_attribution() const {
		godot::Dictionary result;
		result["calls"] = static_cast<int64_t>(g_attribution_stats.calls);
		result["method_total_ns"] = static_cast<int64_t>(g_attribution_stats.method_total_ns);
		result["input_decode_ns"] = static_cast<int64_t>(g_attribution_stats.input_decode_ns);
		result["model_decode_ns"] = static_cast<int64_t>(g_attribution_stats.model_decode_ns);
		result["transported_decode_ns"] = static_cast<int64_t>(g_attribution_stats.transported_decode_ns);
		result["kernel_total_ns"] = static_cast<int64_t>(g_attribution_stats.kernel_total_ns);
		result["validate_ns"] = static_cast<int64_t>(g_attribution_stats.validate_ns);
		result["wake_ns"] = static_cast<int64_t>(g_attribution_stats.wake_ns);
		result["profile_ns"] = static_cast<int64_t>(g_attribution_stats.profile_ns);
		result["swirl_ns"] = static_cast<int64_t>(g_attribution_stats.swirl_ns);
		result["kernel_finalize_ns"] = static_cast<int64_t>(g_attribution_stats.kernel_finalize_ns);
		result["pack_ns"] = static_cast<int64_t>(g_attribution_stats.pack_ns);
		result["clock_pair_overhead_ns"] = static_cast<int64_t>(clock_pair_overhead_ns());
		return result;
	}

	godot::PackedFloat64Array loads(const godot::PackedFloat64Array &state_value,
		const godot::PackedFloat64Array &velocity_value, const godot::Dictionary &deflections_value,
			const godot::Dictionary &model_value, const godot::PackedFloat64Array &thrust_torque_value,
			double rho, double fade, double downwash_cl, const godot::PackedFloat64Array &transported_dv_value) {
		++g_attribution_stats.calls;
		ScopedAttributionTimer method_timer(g_attribution_stats.method_total_ns);
		if (state_value.size() != 13 || velocity_value.size() != 3 || thrust_torque_value.size() != 2) {
			return godot::PackedFloat64Array();
		}
		State13 state{};
		Vec3 velocity{};
		Pair thrust_torque{};
		Pair deflections{};
		const auto input_started = AttributionClock::now();
		for (int64_t i = 0; i < state_value.size(); ++i) {
			state[static_cast<std::size_t>(i)] = state_value[i];
		}
		for (int64_t i = 0; i < velocity_value.size(); ++i) {
			velocity[static_cast<std::size_t>(i)] = velocity_value[i];
		}
		for (int64_t i = 0; i < thrust_torque_value.size(); ++i) {
			thrust_torque[static_cast<std::size_t>(i)] = thrust_torque_value[i];
		}
		const bool deflections_valid = read_number(deflections_value, "elevator", deflections[0]) &&
				read_number(deflections_value, "rudder", deflections[1]);
		g_attribution_stats.input_decode_ns += elapsed_ns(input_started);
		if (!deflections_valid) {
			return godot::PackedFloat64Array();
		}
		Model model;
		const auto model_started = AttributionClock::now();
		const bool model_valid = read_model(model_value, model);
		g_attribution_stats.model_decode_ns += elapsed_ns(model_started);
		if (!model_valid) {
			return godot::PackedFloat64Array();
		}
		if (!transported_dv_value.is_empty() &&
				static_cast<std::size_t>(transported_dv_value.size()) != model.piece_count) {
			return godot::PackedFloat64Array();
		}
		std::vector<double> transported_dv;
		transported_dv.reserve(static_cast<std::size_t>(transported_dv_value.size()));
		const auto transported_started = AttributionClock::now();
		for (int64_t i = 0; i < transported_dv_value.size(); ++i) {
			transported_dv.push_back(transported_dv_value[i]);
		}
		g_attribution_stats.transported_decode_ns += elapsed_ns(transported_started);
		Loads6 result{};
		if (!openrc::smooth_wake::loads(state, velocity, deflections, model, thrust_torque, rho, fade,
				downwash_cl, transported_dv, result)) {
			return godot::PackedFloat64Array();
		}
		const auto pack_started = AttributionClock::now();
		godot::PackedFloat64Array packed_result;
		packed_result.resize(6);
		for (std::size_t i = 0; i < result.size(); ++i) {
			packed_result[static_cast<int64_t>(i)] = result[i];
		}
		g_attribution_stats.pack_ns += elapsed_ns(pack_started);
		return packed_result;
	}
};
"""
    return source[:start] + instrumented_class + source[end:]


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--jobs", type=int, default=2)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if args.jobs < 1:
        parser.error("--jobs must be positive")
    lock = locked.load_lock()
    platform = locked.host_platform_name()
    arch = locked.host_arch_name()
    env = os.environ.copy()
    if platform == "linux":
        version = locked.run(["g++", "-dumpfullversion", "-dumpversion"], capture=True).strip()
        if version != lock["linux"]["compiler_version"]:
            raise SystemExit(f"Expected locked g++ {lock['linux']['compiler_version']}, got {version}")
        env.update(CC="gcc", CXX="g++")
    scons = locked.ensure_scons(lock)
    dependency = locked.ensure_godot_cpp(lock)

    tool_root = ROOT / ".tools/native-wake-attribution"
    build = tool_root / f"{platform}-{arch}"
    source_copy = tool_root / "src"
    source_copy.mkdir(parents=True, exist_ok=True)
    original_source = SOURCE_DIR / "smooth_wake_extension.cpp"
    generated_source = source_copy / original_source.name
    generated_source.write_text(instrument(original_source.read_text(encoding="utf-8")), encoding="utf-8")
    shutil.copy2(SOURCE_DIR / "smooth_wake_kernel.hpp", source_copy / "smooth_wake_kernel.hpp")
    build.mkdir(parents=True, exist_ok=True)

    profile = lock["godot_cpp"]["build_profile"]
    content = json.dumps(profile["content"], sort_keys=True, separators=(",", ":")) + "\n"
    if hashlib.sha256(content.encode()).hexdigest() != profile["sha256"]:
        raise SystemExit("Locked build profile hash mismatch")
    profile_path = build / "build_profile.json"
    profile_path.write_text(content, encoding="utf-8")
    (build / "SConstruct").write_text(locked.sconstruct_text(
        dependency, source_copy, build / "lib", profile_path, lock["godot"]["extension_api"]),
        encoding="utf-8")
    locked.run([*scons, "-C", str(build), f"-j{args.jobs}", f"platform={platform}",
                f"arch={arch}", "target=template_release"], env=env)

    name = locked.expected_library_name(platform)
    output = (args.output or tool_root / name).resolve()
    if output == BASELINE_LIBRARY.resolve():
        raise RuntimeError("Refusing to overwrite the uninstrumented baseline library")
    output.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(build / "lib" / name, output)
    metadata = {
        "format": "openrc-e0b6p-native-attribution-build v1",
        "baseline_source_sha256": sha256(original_source),
        "kernel_header_sha256": sha256(SOURCE_DIR / "smooth_wake_kernel.hpp"),
        "instrumented_source_sha256": sha256(generated_source),
        "instrumented_header_sha256": sha256(source_copy / "smooth_wake_kernel.hpp"),
        "instrumented_library_sha256": sha256(output),
        "instrumented_library": str(output),
        "builder": str(Path(__file__).resolve()),
    }
    metadata_path = tool_root / "build-metadata.json"
    metadata_path.write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
    print(f"Built isolated attribution library {output}")
    print(f"Build metadata: {metadata_path}")


if __name__ == "__main__":
    main()
