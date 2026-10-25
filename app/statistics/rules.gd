## Versioned pure classification thresholds for accepted-tick flight statistics.
extends RefCounted

const VERSION := "flight-statistics-rules-v1"

const DEFAULTS := {
	"liftoff_clearance_s": 1.0,
	"stable_support_s": 0.5,
	"full_stop_s": 2.0,
	"rearm_clearance_s": 2.0,
	"max_sample_dt_s": 0.25,
	"wheel_compression_m": 0.00001,
	"full_stop_speed_mps": 0.5,
	"full_stop_angular_speed_rad_s": 0.10,
	"speed_window_s": 0.25,
	"speed_stability_absolute_mps": 2.0,
	"speed_stability_fraction": 0.05,
	"speed_acceleration_limit_mps2": 294.1995,
	"default_speed_cap_mps": 100.0,
	"speed_exclusion_after_activation_s": 1.0,
	"max_speed_samples": 128,
}


static func resolve(profile: Dictionary) -> Dictionary:
	var result: Dictionary = DEFAULTS.duplicate(true)
	var overrides: Variant = profile.get("rules", {})
	if typeof(overrides) != TYPE_DICTIONARY:
		return result
	for key: String in DEFAULTS:
		if not overrides.has(key):
			continue
		var value: Variant = overrides[key]
		if typeof(value) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(value)):
			continue
		var numeric := float(value)
		if numeric <= 0.0:
			continue
		if key == "max_speed_samples":
			result[key] = clampi(int(numeric), 16, 128)
		else:
			result[key] = numeric
	return result
