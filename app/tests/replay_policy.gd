# H9 numerical regression tolerances, not aerodynamic validation bands.
extends RefCounted

const BuildInfo := preload("res://app_state/build_info.gd")
const FORMAT := "openrc-replay-policy v1"
# [engineering scale, accepted absolute error]. Scaling makes diagnostic ratios comparable;
# the body limits preserve openrc-golden v1. RPM/servo limits are explicit numerical budgets.
const COMPONENTS := {
	position = { unit = "m", scale = 1.0, absolute = 1e-6 },
	velocity = { unit = "m/s", scale = 1.0, absolute = 1e-6 },
	attitude = { unit = "quaternion component", scale = 1.0, absolute = 1e-9 },
	rate = { unit = "rad/s", scale = 1.0, absolute = 1e-6 },
	rpm = { unit = "rpm", scale = 10000.0, absolute = 1e-5 },
	servo = { unit = "normalized command", scale = 1.0, absolute = 1e-9 },
}


static func descriptor() -> Dictionary:
	return { format = FORMAT, components = COMPONENTS.duplicate(true), discrete = "exact", clock = "exact ticks and dt",
		reference_ci = "ubuntu-24.04 x86_64, pinned Godot; app/test.sh gates CI",
		other_platforms = "same tolerances; manual/non-gating reports until explicit CI jobs exist" }


static func accepted(component: String, actual: float, expected: float) -> bool:
	return is_finite(actual) and is_finite(expected) and absf(actual - expected) <= float(COMPONENTS[component].absolute)


static func normalized_error(component: String, actual: float, expected: float) -> float:
	return absf(actual - expected) / float(COMPONENTS[component].scale) if is_finite(actual) and is_finite(expected) else INF


static func stamp() -> Dictionary:
	var build := BuildInfo.current()
	if build.source == "development":
		var output: Array = []
		if OS.execute("git", PackedStringArray(["-C", ProjectSettings.globalize_path("res://"), "describe", "--always", "--tags", "--dirty"]), output) == 0:
			build.describe = str(output[0]).strip_edges()
		output.clear()
		if OS.execute("git", PackedStringArray(["-C", ProjectSettings.globalize_path("res://"), "rev-parse", "HEAD"]), output) == 0:
			build.commit = str(output[0]).strip_edges()
		build.dirty = str(build.describe).ends_with("-dirty")
	return { os = OS.get_name(), architecture = Engine.get_architecture_name(), cpu = OS.get_processor_name(),
		godot = Engine.get_version_info(), build = build, ticks_per_second = Engine.physics_ticks_per_second }
