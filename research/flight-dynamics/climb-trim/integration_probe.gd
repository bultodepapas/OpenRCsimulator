extends SceneTree

# Real-session smooth-transient comparison. Errors are measurements, not acceptance thresholds.
# Run from the repository root with: Godot --headless --path app --script <absolute path to this file>
const Flight := preload("res://sim/flight_session.gd")

const CASES := [
	{"name": "glow_2t", "path": "res://data/aircraft/stik_glow_55ax_2t.json"},
	{"name": "electric_4s", "path": "res://data/aircraft/synthetic_stik_electric_4s.json"},
	{"name": "electric_battery_4s", "path": "res://data/aircraft/synthetic_stik_electric_4s_battery.json"},
	{"name": "electric_battery_6s", "path": "res://data/aircraft/synthetic_stik_electric_6s_battery.json"},
	{"name": "turbine", "path": "res://data/aircraft/sebart_avanti_s_a200.json", "id": "sebart-avanti-s-a200-p100rx"},
]
const DURATION := 0.5
const RATES := [120, 240, 480, 960]


func _run_case(config: Dictionary, hz: int) -> Dictionary:
	Engine.physics_ticks_per_second = hz
	var flight: Node = Flight.new()
	flight.setup(str(config.path), str(config.get("id", "")))
	flight.input_enabled = false
	if not flight.is_flyable():
		var message := str(flight.pause_reason)
		flight.free()
		return {ok = false, error = "setup: " + message}
	var rpm_index: int = int(flight._rotor_index()) if flight.has_method("_rotor_index") else 0
	if rpm_index < 0 or rpm_index >= flight.sim.continuous.size() or flight.sim.aux.is_empty():
		flight.free()
		return {ok = false, error = "no RPM state or auxiliary RPM mirror"}
	var initial_rpm: float = flight.sim.continuous[rpm_index]
	var initial_throttle: float = flight.sim.inputs[3]
	flight.sim.inputs[3] = clampf(float(flight.sim.inputs[3]) + 0.03, 0.0, 1.0)
	var commanded_throttle: float = flight.sim.inputs[3]
	var start_tick: int = flight.sim.tick
	for _tick in range(roundi(DURATION * hz)):
		flight.sim.step()
		if not flight.sim.fault_reason.is_empty():
			var reason := str(flight.sim.fault_reason)
			flight.free()
			return {ok = false, error = "step: " + reason}
	var body: PackedFloat64Array = flight.sim.state.duplicate()
	var continuous: PackedFloat64Array = flight.sim.continuous.duplicate()
	var aux: PackedFloat64Array = flight.sim.aux.duplicate()
	var end_tick: int = flight.sim.tick
	flight.free()
	return {ok = end_tick == start_tick + roundi(DURATION * hz), body = body,
		continuous = continuous, aux = aux, rpm_index = rpm_index, initial_rpm = initial_rpm,
		initial_throttle = initial_throttle, commanded_throttle = commanded_throttle, tick = end_tick}


func _distance(value: Dictionary, reference: Dictionary) -> Dictionary:
	var body: PackedFloat64Array = value.body
	var ref_body: PackedFloat64Array = reference.body
	var continuous: PackedFloat64Array = value.continuous
	var ref_continuous: PackedFloat64Array = reference.continuous
	if body.size() != ref_body.size() or continuous.size() != ref_continuous.size():
		return {ok = false, error = "endpoint layout changed"}
	var body_scaled := 0.0
	var body_abs := 0.0
	var body_index := -1
	for i in body.size():
		var scale := 10.0 if i < 3 else (20.0 if i < 6 else (4.0 if i >= 10 else 1.0))
		var delta := absf(body[i] - ref_body[i])
		body_scaled = maxf(body_scaled, delta / scale)
		if delta > body_abs:
			body_abs = delta
			body_index = i
	var continuous_scaled := 0.0
	var continuous_abs := 0.0
	var continuous_index := -1
	for i in continuous.size():
		var delta := absf(continuous[i] - ref_continuous[i])
		continuous_scaled = maxf(continuous_scaled, delta / maxf(1.0, absf(ref_continuous[i])))
		if delta > continuous_abs:
			continuous_abs = delta
			continuous_index = i
	return {ok = true, body_scaled = body_scaled, body_abs = body_abs, body_index = body_index,
		continuous_scaled = continuous_scaled, continuous_abs = continuous_abs, continuous_index = continuous_index}


func _initialize() -> void:
	var original_hz: int = Engine.physics_ticks_per_second
	var results: Array[Dictionary] = []
	var failed := false
	for config in CASES:
		var runs: Dictionary = {}
		var ok := true
		for hz in RATES:
			var run := _run_case(config, hz)
			runs[str(hz)] = run
			ok = ok and bool(run.ok)
		if not ok:
			failed = true
			results.append({name = config.name, ok = false, runs = runs})
			continue
		var reference: Dictionary = runs["960"]
		var errors: Dictionary = {}
		for hz in RATES:
			errors[str(hz)] = _distance(runs[str(hz)], reference)
		var rpm_index: int = int(reference.rpm_index)
		var mirrored_rpm: float = reference.aux[0]
		results.append({name = config.name, ok = true, errors_vs_960hz = errors,
			final_rpm = reference.continuous[rpm_index], final_aux_rpm = mirrored_rpm,
			rpm_mirror_error = absf(reference.continuous[rpm_index] - mirrored_rpm),
			initial_rpm = reference.initial_rpm, initial_throttle = reference.initial_throttle,
			commanded_throttle = reference.commanded_throttle,
			final_body = runs["960"].body, final_continuous = runs["960"].continuous})
	Engine.physics_ticks_per_second = original_hz
	print(JSON.stringify(results))
	quit(1 if failed else 0)
