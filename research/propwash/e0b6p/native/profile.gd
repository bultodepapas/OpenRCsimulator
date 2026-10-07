# Installed beside adapter.gd in a disposable project. Includes all adapter/binding costs.
extends SceneTree
const Native = preload("res://tests/e0b6p_native/adapter.gd")
const Oracle = preload("res://physics/slipstream.gd")
const Fixture = preload("res://tests/test_wash_profile.gd")
const Data = preload("res://physics/aircraft_data.gd")
const Air = preload("res://physics/air_data.gd")

func _initialize() -> void:
	var raw: Dictionary = Fixture.combined_raw()
	raw.propulsion.propeller.slipstream.swirl_factor.value = 0.4
	var validated: Dictionary = Data.validate_and_derive(raw)
	if not validated.ok or not Native.available():
		quit(1)
		return
	var model: Dictionary = validated.model
	var prop: Dictionary = model.propulsion
	var vi0: float = prop.max_rpm / 60.0 * prop.diameter * sqrt(2.0 * prop.ct[1] / PI)
	var controls: Dictionary = {elevator = 0.1, rudder = -0.1, aileron_left = 0.0, aileron_right = 0.0}
	var rows: Array = []
	for regime: String in ["forward", "stall", "static", "spin", "reverse_fade", "reverse_off"]:
		var speed: float = 0.0 if regime == "static" else 15.0
		if regime.begins_with("reverse"):
			speed = (-0.15 if regime == "reverse_fade" else -0.3) * vi0
		var alpha: float = deg_to_rad(15.0 if regime in ["stall", "spin"] else 3.0)
		if regime.begins_with("reverse"):
			alpha = 0.0
		var state: PackedFloat64Array = PackedFloat64Array([
			0.0, 0.0, -100.0, speed * cos(alpha), 0.0, speed * sin(alpha),
			1.0, 0.0, 0.0, 0.0, 0.5 if regime == "spin" else 0.0, -0.3, 1.5 if regime == "spin" else 0.0])
		var air: Dictionary = Air.compute(state, PackedFloat64Array([0.0, 0.0, 0.0]), 1.225)
		var times: Array = [[], []]
		var exact: bool = true
		for pair: int in 35: # Three warm-up pairs, alternate which implementation runs first.
			var results: Array = [null, null]
			for order: int in 2:
				var which: int = (pair + order) % 2
				var started: int = Time.get_ticks_usec()
				if which == 0:
					results[which] = Oracle.loads(state, air, controls, model, prop.max_rpm, 1.225, 0.3)
				else:
					results[which] = Native.loads(state, air, controls, model, prop.max_rpm, 1.225, 0.3)
				var elapsed: int = Time.get_ticks_usec() - started
				if pair >= 3:
					times[which].append(elapsed)
			for component: int in 6:
				var a: float = results[0][component]
				var b: float = results[1][component]
				if not is_finite(a) or not is_finite(b) or absf(a - b) > 1e-10 * (1.0 + absf(a)):
					push_error("Profile reference mismatch")
					quit(1)
					return
				exact = exact and a == b
		var medians: Array = []
		for samples: Array in times:
			var sorted: Array = samples.duplicate()
			sorted.sort()
			medians.append(0.5 * (float(sorted[15]) + float(sorted[16])))
		rows.append({regime = regime, oracle_us = medians[0], native_us = medians[1],
			speedup = medians[0] / maxf(medians[1], 0.5), exact = exact, samples_us = times})
		print("E0b6p native profile %s: %.1f -> %.1f us/load" % [regime, medians[0], medians[1]])
	var output: FileAccess = FileAccess.open(OS.get_cmdline_user_args()[0], FileAccess.WRITE)
	if output == null:
		quit(1)
		return
	output.store_string(JSON.stringify({format = "openrc-smooth-native-profile v1", cpu = OS.get_processor_name(),
		godot = Engine.get_version_info().string, warmup_pairs = 3, measured_pairs = 32, rows = rows}, "\t", true, true) + "\n")
	quit()
