extends SceneTree

const Swash = preload("res://physics/rotorcraft/swash.gd")

var _check_count: int = 0
var _failure_count: int = 0


func _initialize() -> void:
	_test_curves()
	_test_mixer()
	_test_servo_dynamics_and_saturation()
	_test_linkage()
	_test_invalid_inputs()
	print("%d checks, %d failed" % [_check_count, _failure_count])
	quit(1 if _failure_count > 0 else 0)


func _test_curves() -> void:
	var curves := {
		"normal": {
			"pitch": PackedFloat64Array([-1.0, -0.6, 0.0, 0.7, 1.0]),
			"throttle": PackedFloat64Array([0.08, 0.2, 0.4, 0.72, 1.0]),
		},
		"idle_up": {
			"pitch": PackedFloat64Array([-0.5, -0.25, 0.0, 0.25, 0.5]),
			"throttle": PackedFloat64Array([1.0, 0.68, 0.55, 0.7, 1.0]),
		},
	}
	_check("two named flight modes validate", Swash.validate_curves(curves)["ok"])
	var interpolated: Dictionary = Swash.sample_mode_curve(curves, "normal", "pitch", -0.75)
	_check("normal pitch curve samples", interpolated["ok"])
	_close("linear interpolation between adjacent pitch knots", interpolated["value"], -0.8)
	var idle_throttle: Dictionary = Swash.sample_mode_curve(curves, "idle_up", "throttle", 0.0)
	_close("mode selects its own center throttle point", idle_throttle["value"], 0.55)
	var endpoint: Dictionary = Swash.sample_mode_curve(curves, "normal", "throttle", 1.0)
	_close("curve returns the exact right endpoint", endpoint["value"], 1.0)


func _test_mixer() -> void:
	var mixed: Dictionary = Swash.mix_120(0.2, 0.3, -0.1)
	_check("120 degree mixer accepts normalized axes", mixed["ok"])
	var decoded: Dictionary = Swash.unmix_120(mixed["servo_targets"])
	_check("analytic 120 degree inverse accepts mixer output", decoded["ok"])
	_close("mixer round trip collective", decoded["collective"], 0.2)
	_close("mixer round trip positive-forward longitudinal", decoded["longitudinal"], 0.3)
	_close("mixer round trip lateral-right", decoded["lateral"], -0.1)

	var collective_only: Dictionary = Swash.mix_120(0.37, 0.0, 0.0)
	var collective_servos: PackedFloat64Array = collective_only["servo_targets"]
	_close("collective is common mode at front", collective_servos[0], 0.37)
	_close("collective is common mode at rear right", collective_servos[1], 0.37)
	_close("collective is common mode at rear left", collective_servos[2], 0.37)

	var cyclic_only: Dictionary = Swash.mix_120(0.0, 0.4, -0.3)
	var cyclic_servos: PackedFloat64Array = cyclic_only["servo_targets"]
	_close("pure cyclic has zero servo-command sum", cyclic_servos[0] + cyclic_servos[1] + cyclic_servos[2], 0.0)
	var decoded_cyclic: Dictionary = Swash.unmix_120(cyclic_servos)
	_close("pure cyclic has zero collective", decoded_cyclic["collective"], 0.0)


func _test_servo_dynamics_and_saturation() -> void:
	var full_mix: Dictionary = Swash.mix_120(1.0, 1.0, 1.0)
	var asymmetric_spec := {
		"travel_min": PackedFloat64Array([-0.9, -0.7, -0.4]),
		"travel_max": PackedFloat64Array([0.9, 0.7, 0.4]),
		"rate_per_second": PackedFloat64Array([10.0, 10.0, 10.0]),
		"lag_seconds": PackedFloat64Array([0.0, 0.0, 0.0]),
	}
	var saturated: Dictionary = Swash.step_servos(PackedFloat64Array([0.0, 0.0, 0.0]), full_mix["servo_targets"], asymmetric_spec, 1.0)
	_check("full collective plus cyclic is accepted before servo limits", saturated["ok"])
	var saturated_positions: PackedFloat64Array = saturated["positions"]
	_close("front servo clips at its declared maximum", saturated_positions[0], 0.9)
	_close("rear-right servo clips at its own declared maximum", saturated_positions[1], 0.7)
	_close("rear-left servo retains its independently unsaturated target", saturated_positions[2], -0.3660254037844386)
	var clipped: Array = saturated["travel_clamped"]
	_check("clamp flags identify only the two saturated servos", clipped[0] and clipped[1] and not clipped[2])

	var dynamic_spec := {
		"travel_min": PackedFloat64Array([-1.0, -1.0, -1.0]),
		"travel_max": PackedFloat64Array([1.0, 1.0, 1.0]),
		"rate_per_second": PackedFloat64Array([0.5, 100.0, 100.0]),
		"lag_seconds": PackedFloat64Array([0.0, 0.5, 0.25]),
	}
	var dynamic: Dictionary = Swash.step_servos(PackedFloat64Array([0.0, 0.0, 0.0]), PackedFloat64Array([1.0, -1.0, 0.5]), dynamic_spec, 0.25)
	_check("per-servo slew and lag step succeeds", dynamic["ok"])
	var dynamic_positions: PackedFloat64Array = dynamic["positions"]
	_close("first servo obeys its per-servo rate cap", dynamic_positions[0], 0.125)
	_close("second servo follows exact first-order lag", dynamic_positions[1], -0.3934693402873666)
	_close("third servo follows its own exact first-order lag", dynamic_positions[2], 0.31606027941427883)
	var rate_flags: Array = dynamic["rate_limited"]
	_check("rate-limited state is reported per servo", rate_flags[0] and not rate_flags[1] and not rate_flags[2])

	var no_lag_spec := {
		"travel_min": PackedFloat64Array([-1.0, -1.0, -1.0]),
		"travel_max": PackedFloat64Array([1.0, 1.0, 1.0]),
		"rate_per_second": PackedFloat64Array([100.0, 100.0, 100.0]),
	}
	var no_lag: Dictionary = Swash.step_servos(PackedFloat64Array([0.0, 0.0, 0.0]), PackedFloat64Array([0.4, 0.0, -0.2]), no_lag_spec, 0.1)
	_close("omitting lag requests the rate-limited no-lag response", no_lag["positions"][0], 0.4)
	_close("no-lag response preserves the negative servo command", no_lag["positions"][2], -0.2)


func _test_linkage() -> void:
	var mixed: Dictionary = Swash.mix_120(0.2, 0.3, -0.1)
	var linkage := {
		"collective_rad_per_unit": 0.2,
		"longitudinal_rad_per_unit": 0.1,
		"lateral_rad_per_unit": 0.15,
		"collective_min_rad": -0.1,
		"collective_max_rad": 0.15,
		"cyclic_max_rad": 0.05,
	}
	var output: Dictionary = Swash.linkage_output(mixed["servo_targets"], linkage)
	_check("declared linkage converts achieved servo positions", output["ok"])
	_close("collective linkage is linear in radians", output["theta0_rad"], 0.04)
	_close("longitudinal linkage preserves positive-forward sign", output["longitudinal_rad"], 0.03)
	_close("lateral linkage preserves signed lateral command", output["lateral_rad"], -0.015)

	var limit_linkage: Dictionary = linkage.duplicate()
	limit_linkage["collective_rad_per_unit"] = 0.4
	limit_linkage["longitudinal_rad_per_unit"] = 0.2
	limit_linkage["lateral_rad_per_unit"] = 0.3
	var near_limits: Dictionary = Swash.mix_120(0.5, 0.4, 0.2)
	var limited: Dictionary = Swash.linkage_output(near_limits["servo_targets"], limit_linkage)
	_close("collective linkage obeys its caller-declared limit", limited["theta0_rad"], 0.15)
	_close("longitudinal cyclic obeys its declared limit", limited["longitudinal_rad"], 0.05)
	_close("lateral cyclic obeys its declared limit", limited["lateral_rad"], 0.05)


func _test_invalid_inputs() -> void:
	var bad_curves := {
		"normal": {
			"pitch": PackedFloat64Array([-1.0, -0.5, 0.0, 0.5]),
			"throttle": PackedFloat64Array([0.0, 0.25, 0.5, 0.75, 1.0]),
		},
	}
	_check("four-point curve is rejected", not Swash.validate_curves(bad_curves)["ok"])
	var valid_curves := {
		"normal": {
			"pitch": PackedFloat64Array([-1.0, -0.5, 0.0, 0.5, 1.0]),
			"throttle": PackedFloat64Array([0.0, 0.25, 0.5, 0.75, 1.0]),
		},
	}
	_check("missing mode is rejected", not Swash.sample_mode_curve(valid_curves, "hold", "pitch", 0.0)["ok"])
	_check("unknown curve channel is rejected", not Swash.sample_mode_curve(valid_curves, "normal", "rudder", 0.0)["ok"])
	_check("out-of-range stick value is rejected", not Swash.sample_mode_curve(valid_curves, "normal", "pitch", 1.1)["ok"])
	_check("non-numeric mixer axis is rejected", not Swash.mix_120("forward", 0.0, 0.0)["ok"])
	_check("wrong servo count is rejected by inverse mixer", not Swash.unmix_120(PackedFloat64Array([0.0, 0.0]))["ok"])

	var spec := {
		"travel_min": PackedFloat64Array([-1.0, -1.0, -1.0]),
		"travel_max": PackedFloat64Array([1.0, 1.0, 1.0]),
		"rate_per_second": PackedFloat64Array([1.0, 1.0, 1.0]),
	}
	_check("wrong prior servo count is rejected", not Swash.step_servos(PackedFloat64Array([0.0]), PackedFloat64Array([0.0, 0.0, 0.0]), spec, 0.1)["ok"])
	_check("wrong rate count is rejected", not Swash.step_servos(PackedFloat64Array([0.0, 0.0, 0.0]), PackedFloat64Array([0.0, 0.0, 0.0]), {"travel_min": spec["travel_min"], "travel_max": spec["travel_max"], "rate_per_second": PackedFloat64Array([1.0, 1.0])}, 0.1)["ok"])
	_check("non-positive time step is rejected", not Swash.step_servos(PackedFloat64Array([0.0, 0.0, 0.0]), PackedFloat64Array([0.0, 0.0, 0.0]), spec, 0.0)["ok"])
	_check("command outside the mixer-reachable range is rejected", not Swash.step_servos(PackedFloat64Array([0.0, 0.0, 0.0]), PackedFloat64Array([3.0, 0.0, 0.0]), spec, 0.1)["ok"])
	_check("unknown servo configuration key is rejected", not Swash.step_servos(PackedFloat64Array([0.0, 0.0, 0.0]), PackedFloat64Array([0.0, 0.0, 0.0]), {"travel_min": spec["travel_min"], "travel_max": spec["travel_max"], "rate_per_second": spec["rate_per_second"], "assumed_limit": 0.9}, 0.1)["ok"])

	var good_positions: PackedFloat64Array = Swash.mix_120(0.0, 0.0, 0.0)["servo_targets"]
	_check("missing linkage limits are rejected", not Swash.linkage_output(good_positions, {"collective_rad_per_unit": 0.1})["ok"])


func _close(label: String, actual: float, expected: float, tolerance: float = 1.0e-14) -> void:
	_check(label, absf(actual - expected) <= tolerance, "got " + str(actual) + ", expected " + str(expected))


func _check(label: String, condition: bool, detail: String = "") -> void:
	_check_count += 1
	if not condition:
		_failure_count += 1
		push_error("FAIL: %s %s" % [label, detail])
