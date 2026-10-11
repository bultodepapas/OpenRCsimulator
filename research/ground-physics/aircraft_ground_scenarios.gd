# GP-02/GP-04: bounded ground-only scenarios using actual aircraft mass, gear, field and wheel profiles.
# Aero and propulsion are disabled. These measurements verify the ground law and are not physical calibration.
# Run from the repository root; --path must point at the Godot app project.
extends SceneTree

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Integrator := preload("res://physics/integrator.gd")
const AircraftData := preload("res://physics/aircraft_data.gd")
const WheelProfiles := preload("res://physics/wheel_profiles.gd")
const Ground := preload("res://physics/ground_wheels.gd")
const GroundStart := preload("res://physics/ground_start.gd")
const GroundSurfaces := preload("res://physics/ground_surfaces.gd")
const Terrain := preload("res://physics/ground_terrain.gd")
const FieldLoader := preload("res://data/field_loader.gd")

const GRAVITY := 9.80665
const AIRCRAFT := [
	{"id": "jensen-das-ugly-stik-60", "path": "res://data/aircraft/jensen_ugly_stik_60.json"},
	{"id": "gp-extra-300s-60", "path": "res://data/aircraft/gp_extra_300s_60.json"},
	{"id": "p51d-mustang-120", "path": "res://data/aircraft/p51d_mustang_120.json"},
]
const COAST_SPEEDS := [2.0, 5.0, 10.0]
const DROP_CASES := [[0.1, 240], [0.1, 480], [0.1, 960], [0.3, 240], [0.3, 480], [0.3, 960]]
const COAST_HORIZON_S := 20.0
const DROP_HORIZON_S := 8.0
const RUNWAY_NORTH := 15.0
const RUNWAY_EAST := -25.0
const EASTBOUND_START_EAST := -45.0
const WESTBOUND_START_EAST := 45.0
const ROUGH_NORTH := 0.0
const ROUGH_EAST := -25.0
const EDGE_NORTH := 9.0
const EDGE_APPROACH_M := 0.1
const EDGE_CROSSING_ANGLE := PI / 4.0
const EAST_HEADING := PI / 2.0
const WEST_HEADING := 3.0 * PI / 2.0

var _surfaces := PackedFloat64Array()
var _field_id := ""
var _failures := 0
var _report: Dictionary = {
	"evidence_kind": "force-only verification; aircraft gear/profile values loaded from project data",
	"aerodynamics": "disabled",
	"propulsion": "disabled",
	"gravity_mps2": GRAVITY,
	"not_covered": [
		"aerodynamic crosswind response and powered takeoff/landing (aero and propulsion are disabled)",
		"brake-driven noseover and full ground-loop/crash acceptance (no calibrated aircraft brake torque or crash model in this force-only driver)",
		"taxi on a deliberately inclined surface (taxi probes use supported runway poses)"
	],
	"aircraft": [],
	"failures": [],
}


func _fail(message: String) -> void:
	_failures += 1
	_report.failures.append(message)
	printerr("FAIL " + message)


func _finite(values: PackedFloat64Array) -> bool:
	for value: float in values:
		if not is_finite(value):
			return false
	return true


func _load_surfaces() -> bool:
	var field_result: Dictionary = FieldLoader.load_from()
	if not field_result.get("ok", false):
		_fail("field load failed: " + str(field_result.get("errors", [])))
		return false
	_field_id = str(field_result.field.get("id", ""))
	var table_result: Dictionary = GroundSurfaces.load_table()
	if not table_result.get("ok", false):
		_fail("surface table load failed: " + str(table_result.get("errors", [])))
		return false
	var built: Dictionary = GroundSurfaces.build(table_result.table, field_result.field)
	if not built.get("ok", false):
		_fail("surface build failed: " + str(built.get("errors", [])))
		return false
	_surfaces = built.rects
	var edge_inside := Terrain.sample_validated(EDGE_NORTH + 0.000001, 0.0, _surfaces)
	var edge_outside := Terrain.sample_validated(EDGE_NORTH - 0.000001, 0.0, _surfaces)
	var edge_height_delta: float = edge_inside[0] - edge_outside[0]
	_report.lower_runway_edge_height_probe = {
		"north_edge_m": EDGE_NORTH, "inside_sample_north_m": EDGE_NORTH + 0.000001,
		"outside_sample_north_m": EDGE_NORTH - 0.000001,
		"inside_height_up_m": edge_inside[0], "outside_height_up_m": edge_outside[0],
		"height_delta_m": edge_height_delta, "continuity_tolerance_m": 0.000001,
		"continuous_within_tolerance": absf(edge_height_delta) <= 0.000001}
	if absf(edge_height_delta) > 0.000001:
		_fail("lower runway edge terrain height step exceeds 1 µm: %g m" % edge_height_delta)
	return true


func _load_model(spec: Dictionary) -> Dictionary:
	var loaded: Dictionary = AircraftData.load_file(str(spec.path))
	if not loaded.get("ok", false):
		_fail("aircraft load failed for %s: %s" % [spec.id, str(loaded.get("errors", []))])
		return {}
	var profiled: Dictionary = WheelProfiles.apply_to_model(loaded.model)
	if not profiled.get("ok", false):
		_fail("wheel profile load failed for %s: %s" % [spec.id, str(profiled.get("errors", []))])
		return {}
	var model: Dictionary = profiled.model
	if str(model.get("id", "")) != str(spec.id):
		_fail("aircraft ID mismatch for %s (loaded %s)" % [spec.id, model.get("id", "? ")])
		return {}
	if model.get("landing_gear", {}).get("contacts", []).size() < 2:
		_fail("aircraft %s does not have at least two modeled wheel contacts" % spec.id)
		return {}
	return model


func _deflections() -> Dictionary:
	return {"elevator": 0.0, "aileron_left": 0.0, "aileron_right": 0.0, "rudder": 0.0}


func _support(model: Dictionary, north: float, east: float, heading := EAST_HEADING) -> Dictionary:
	# Solve the same force/moment balance as the engine-off stage of GroundStart, but without its
	# runway-start stiction precondition. These force-only scenarios do not need stiction anchors.
	var gear: Dictionary = model.landing_gear
	var front_x := -INF
	var front_z := 0.0
	var rear_x := INF
	var rear_z := 0.0
	for contact: Dictionary in gear.contacts:
		var x: float = contact.position[0]
		var z: float = contact.position[2]
		if x > front_x:
			front_x = x
			front_z = z
		if x < rear_x:
			rear_x = x
			rear_z = z
	var pitch_seed := atan2(front_z - rear_z, front_x - rear_x) if front_x - rear_x > 1e-6 else 0.0
	var lowest_projected := -INF
	for contact: Dictionary in gear.contacts:
		var projected := -sin(pitch_seed) * float(contact.position[0]) + cos(pitch_seed) * float(contact.position[2])
		lowest_projected = maxf(lowest_projected, projected)
	var seed_down := -(lowest_projected - float(gear.get("static_sag", 0.0)))
	var residual := func(x: PackedFloat64Array) -> PackedFloat64Array:
		# GroundStart pose convention is [down, roll, pitch].
		var q := M.q_from_euler(heading, x[2], x[1])
		var state := RB.make_state(M.v3(north, east, x[0]), M.v3(0.0, 0.0, 0.0), q,
			M.v3(0.0, 0.0, 0.0))
		var evaluation: Dictionary = Ground.evaluate(state, gear, 0.0, _surfaces,
			PackedFloat64Array(), _wheel_speeds(gear, 0.0), 0.0)
		var loads: PackedFloat64Array = evaluation.get("loads", PackedFloat64Array())
		if not loads.is_empty() and loads.size() != 6:
			return PackedFloat64Array([INF, INF, INF])
		var force := M.v3(0.0, 0.0, 0.0)
		var moment := M.v3(0.0, 0.0, 0.0)
		if loads.size() == 6:
			force = M.v3(loads[0], loads[1], loads[2])
			moment = M.v3(loads[3], loads[4], loads[5])
		var derivative := RB.derivative(state, float(model.mass_kg), model.inertia,
			RB.inertia_inverse(model.inertia), force, moment, GRAVITY)
		var linear_world := M.q_rotate(q, M.v3(derivative[RB.VEL], derivative[RB.VEL + 1], derivative[RB.VEL + 2]))
		var angular_world := M.q_rotate(q, M.v3(derivative[RB.RATE], derivative[RB.RATE + 1], derivative[RB.RATE + 2]))
		return PackedFloat64Array([linear_world[2], angular_world[0], angular_world[1]])
	var solved: Dictionary = GroundStart._newton(residual,
		PackedFloat64Array([seed_down, 0.0, pitch_seed]))
	if not solved.get("ok", false):
		return {"ok": false, "message": "static wheel support did not converge (residual %s)" % str(solved.get("residual", INF))}
	var x: PackedFloat64Array = solved.x
	var q := M.q_from_euler(heading, x[2], x[1])
	var state := RB.make_state(M.v3(north, east, x[0]), M.v3(0.0, 0.0, 0.0), q,
		M.v3(0.0, 0.0, 0.0))
	return {"ok": true, "state": state, "residual": solved.residual, "iterations": solved.iterations}


func _combined(state: PackedFloat64Array, wheel_speeds: PackedFloat64Array) -> PackedFloat64Array:
	var result := state.duplicate()
	result.append_array(wheel_speeds)
	return result


func _wheel_speeds(gear: Dictionary, value: float) -> PackedFloat64Array:
	var result := PackedFloat64Array()
	for _contact in gear.contacts:
		result.append(value)
	return result


func _rolling_wheel_speeds(state: PackedFloat64Array, gear: Dictionary) -> PackedFloat64Array:
	# Match each wheel's spin to its actual ground-projected contact velocity at the current pose.
	# This avoids injecting a pitch/terrain-induced slip impulse into an otherwise steady coast.
	var probe: Dictionary = Ground.evaluate(state, gear, 0.0, _surfaces,
		PackedFloat64Array(), _wheel_speeds(gear, 0.0), 0.0)
	var wheels: Array = probe.get("wheels", [])
	var result := PackedFloat64Array()
	for i in gear.contacts.size():
		result.append(float(wheels[i].get("long_speed", 0.0)) if i < wheels.size() else 0.0)
	return result


func _set_horizontal_velocity(state: PackedFloat64Array, speed: float, east_sign: float) -> void:
	_set_world_horizontal_velocity(state, 0.0, east_sign * speed)


func _set_world_horizontal_velocity(state: PackedFloat64Array, north_speed: float, east_speed: float) -> void:
	var q := M.quat(state[RB.ATT], state[RB.ATT + 1], state[RB.ATT + 2], state[RB.ATT + 3])
	var body_velocity := M.q_rotate(M.q_conj(q), M.v3(north_speed, east_speed, 0.0))
	state[RB.VEL] = body_velocity[0]
	state[RB.VEL + 1] = body_velocity[1]
	state[RB.VEL + 2] = body_velocity[2]


func _horizontal_speed(values: PackedFloat64Array) -> float:
	var q := M.quat(values[RB.ATT], values[RB.ATT + 1], values[RB.ATT + 2], values[RB.ATT + 3])
	var world_velocity := M.q_rotate(q, M.v3(values[RB.VEL], values[RB.VEL + 1], values[RB.VEL + 2]))
	return M.sqrt_(world_velocity[0] * world_velocity[0] + world_velocity[1] * world_velocity[1])


func _rhs(values: PackedFloat64Array, model: Dictionary, gear: Dictionary, steer: float,
		context: Dictionary) -> PackedFloat64Array:
	var state := values.slice(0, RB.SIZE)
	var wheel_speeds := values.slice(RB.SIZE)
	var evaluation: Dictionary = Ground.evaluate(state, gear, steer, _surfaces, PackedFloat64Array(), wheel_speeds, 0.0)
	context.evaluation = evaluation
	var loads: PackedFloat64Array = evaluation.get("loads", PackedFloat64Array())
	var force := M.v3(0.0, 0.0, 0.0)
	var moment := M.v3(0.0, 0.0, 0.0)
	if loads.size() == 6:
		force = M.v3(loads[0], loads[1], loads[2])
		moment = M.v3(loads[3], loads[4], loads[5])
	var derivative := RB.derivative(state, float(model.mass_kg), model.inertia,
		RB.inertia_inverse(model.inertia), force, moment, GRAVITY)
	var wheel_derivative: PackedFloat64Array = evaluation.get("derivative", PackedFloat64Array())
	if wheel_derivative.size() != gear.contacts.size():
		context.error = "wheel derivative count does not match contact count"
		return PackedFloat64Array()
	derivative.append_array(wheel_derivative)
	return derivative


func _step(values: PackedFloat64Array, dt: float, model: Dictionary, gear: Dictionary,
		steer: float, context: Dictionary) -> PackedFloat64Array:
	var f := func(x: PackedFloat64Array) -> PackedFloat64Array:
		return _rhs(x, model, gear, steer, context)
	var k1: PackedFloat64Array = f.call(values)
	if k1.size() != values.size():
		context.error = "malformed ground-only derivative"
		return PackedFloat64Array()
	var result := Integrator.rk4_step(values, dt, f, k1)
	if result.size() == values.size():
		var state := result.slice(0, RB.SIZE)
		var speeds := result.slice(RB.SIZE)
		context.sampled = Ground.evaluate(state, gear, steer, _surfaces, PackedFloat64Array(), speeds, 0.0)
	return result


func _update_contact_metrics(metrics: Dictionary, evaluation: Dictionary) -> void:
	var wheels: Array = evaluation.get("wheels", [])
	var count := 0
	for wheel: Dictionary in wheels:
		if float(wheel.get("normal_load", 0.0)) > 0.0:
			count += 1
		metrics.max_contacts = maxi(int(metrics.max_contacts), count)
		metrics.peak_compression_m = maxf(float(metrics.peak_compression_m), float(wheel.get("compression", 0.0)))
		metrics.max_rim_speed_mps = maxf(float(metrics.max_rim_speed_mps), absf(float(wheel.get("rim_speed", 0.0))))
	metrics.any_contact_ticks = int(metrics.any_contact_ticks) + (1 if count > 0 else 0)
	metrics.all_contact_ticks = int(metrics.all_contact_ticks) + (1 if count == wheels.size() and not wheels.is_empty() else 0)


func _run_coast(model: Dictionary, gear: Dictionary, start_state: PackedFloat64Array,
		initial_speed: float, hz: int, surface_label: String, direction: String) -> Dictionary:
	var coast_start := start_state.duplicate()
	_set_horizontal_velocity(coast_start, initial_speed, 1.0 if direction == "eastbound" else -1.0)
	var matched_speeds := _rolling_wheel_speeds(coast_start, gear)
	var values := _combined(coast_start, matched_speeds)
	var initial_north := values[RB.POS]
	var initial_east := values[RB.POS + 1]
	var dt := 1.0 / float(hz)
	var ticks := ceili(COAST_HORIZON_S * hz)
	var time_s := 0.0
	var stopped := false
	var context := {"evaluation": {}, "sampled": {}, "error": ""}
	var metrics := {"peak_compression_m": 0.0, "max_rim_speed_mps": initial_speed,
		"max_contacts": 0, "any_contact_ticks": 0, "all_contact_ticks": 0}
	var initial_evaluation: Dictionary = Ground.evaluate(coast_start, gear, 0.0, _surfaces,
		PackedFloat64Array(), matched_speeds, 0.0)
	var initial_normal := 0.0
	var initial_rolling := 0.0
	var expected_rolling := 0.0
	var expected_normal := 0.0
	var initial_surfaces := []
	var initial_wheel_diagnostics := []
	var evaluated_wheels: Array = initial_evaluation.get("wheels", [])
	var reference_radius: float = gear.get("rolling_reference_radius", Ground.REFERENCE_RADIUS)
	var base_rolling: float = gear.get("rolling_resistance", 0.0)
	for i in evaluated_wheels.size():
		var wheel: Dictionary = evaluated_wheels[i]
		var contact: Dictionary = gear.contacts[i]
		var normal: float = wheel.get("normal_load", 0.0)
		var rolling_force: float = wheel.get("rolling_force", 0.0)
		var surface_index: int = int(wheel.get("surface_index", -1))
		var rolling_factor := 1.0
		if surface_index >= 0 and surface_index + 5 < _surfaces.size():
			rolling_factor = _surfaces[surface_index + 5]
		var radius: float = contact.get("wheel_radius", Ground.REFERENCE_RADIUS)
		var expected_coefficient := base_rolling * (1.0 + (rolling_factor - 1.0) * sqrt(reference_radius / radius))
		initial_normal += normal
		initial_rolling += rolling_force
		expected_normal += normal
		expected_rolling += expected_coefficient * normal
		initial_surfaces.append(surface_index)
		initial_wheel_diagnostics.append({"contact": contact.get("name", str(i)),
			"normal_load_n": normal, "rolling_force_n": rolling_force,
			"slip_force_n": wheel.get("slip_force", 0.0),
			"lateral_force_n": wheel.get("lateral_force", 0.0),
			"surface_index": surface_index,
			"expected_rolling_coefficient": expected_coefficient})
	var effective_crr := -initial_rolling / initial_normal if initial_normal > 0.0 else 0.0
	var expected_effective_crr := expected_rolling / expected_normal if expected_normal > 0.0 else 0.0
	var predicted_distance: Variant = null
	if effective_crr > 0.0:
		predicted_distance = maxf(0.0, initial_speed * initial_speed - 0.01) / (2.0 * GRAVITY * effective_crr)
	for tick in ticks:
		var speed := _horizontal_speed(values)
		if tick > 0 and speed <= 0.1:
			stopped = true
			break
		values = _step(values, dt, model, gear, 0.0, context)
		if values.is_empty() or not _finite(values):
			_fail("%s %s coastdown became nonfinite at %.3f s: %s" % [model.id, surface_label, time_s, context.error])
			break
		_update_contact_metrics(metrics, context.sampled)
		time_s += dt
	var distance := sqrt(pow(values[RB.POS] - initial_north, 2.0) + pow(values[RB.POS + 1] - initial_east, 2.0))
	var runway_endpoint_in_bounds := values[RB.POS + 1] >= -50.0 and values[RB.POS + 1] <= 50.0 and values[RB.POS] >= 9.0 and values[RB.POS] <= 21.0
	if surface_label == "runway" and not runway_endpoint_in_bounds:
		_fail("%s %s %g m/s coastdown left the 100 m by 12 m runway bounds" % [model.id, direction, initial_speed])
	return {"aircraft": model.id, "surface": surface_label, "initial_speed_mps": initial_speed,
		"direction": direction, "hz": hz, "distance_to_0_1_mps_m": distance, "time_to_0_1_mps_s": time_s,
		"initial_weighted_rolling_coefficient": effective_crr,
		"initial_expected_weighted_rolling_coefficient": expected_effective_crr,
		"initial_weighted_rolling_coefficient_error": effective_crr - expected_effective_crr,
		"aircraft_base_rolling_resistance": base_rolling,
		"rolling_reference_radius_m": reference_radius,
		"constant_drag_distance_estimate_m": predicted_distance,
		"initial_wheel_surface_indices": initial_surfaces,
		"initial_wheel_forces": initial_wheel_diagnostics,
		"runway_endpoint_in_bounds": runway_endpoint_in_bounds if surface_label == "runway" else null,
		"final_north_m": values[RB.POS], "final_east_m": values[RB.POS + 1],
		"final_horizontal_speed_mps": _horizontal_speed(values), "stopped": stopped, "metrics": metrics}


func _landing_release_state(support_state: PackedFloat64Array, gear: Dictionary,
		clearance_m: float, pitch_delta: float) -> PackedFloat64Array:
	var state := support_state.duplicate()
	var old_q := M.quat(state[RB.ATT], state[RB.ATT + 1], state[RB.ATT + 2], state[RB.ATT + 3])
	var euler: PackedFloat64Array = M.q_to_euler(old_q)
	var new_q := M.q_from_euler(euler[0], euler[1] + pitch_delta, euler[2])
	var main_indices: Array = []
	for i in gear.contacts.size():
		if str(gear.contacts[i].get("name", "")).begins_with("main"):
			main_indices.append(i)
	if main_indices.is_empty():
		main_indices = [0, mini(1, gear.contacts.size() - 1)]
	var old_projection := 0.0
	var new_projection := 0.0
	for i in main_indices:
		var point: PackedFloat64Array = gear.contacts[i].position
		old_projection += M.q_rotate(old_q, point)[2]
		new_projection += M.q_rotate(new_q, point)[2]
	old_projection /= float(main_indices.size())
	new_projection /= float(main_indices.size())
	var main_plane_down := state[RB.POS + 2] + old_projection
	state[RB.POS + 2] = main_plane_down - new_projection - clearance_m
	for i in 4:
		state[RB.ATT + i] = new_q[i]
	return state


func _mechanical_energy(values: PackedFloat64Array, model: Dictionary, gear: Dictionary,
		wheel_diagnostics: Array) -> float:
	var state := values.slice(0, RB.SIZE)
	var speeds := values.slice(RB.SIZE)
	var vx := state[RB.VEL]
	var vy := state[RB.VEL + 1]
	var vz := state[RB.VEL + 2]
	var translation := 0.5 * float(model.mass_kg) * (vx * vx + vy * vy + vz * vz)
	var w := M.v3(state[RB.RATE], state[RB.RATE + 1], state[RB.RATE + 2])
	var inertia: PackedFloat64Array = model.inertia
	var iw := M.v3(inertia[0] * w[0] + inertia[3] * w[1] + inertia[4] * w[2],
		inertia[3] * w[0] + inertia[1] * w[1] + inertia[5] * w[2],
		inertia[4] * w[0] + inertia[5] * w[1] + inertia[2] * w[2])
	var rotation := 0.5 * M.dot(w, iw)
	var wheel_energy := 0.0
	for i in mini(gear.contacts.size(), speeds.size()):
		var contact: Dictionary = gear.contacts[i]
		var radius: float = contact.get("wheel_radius", 0.0381)
		var omega := speeds[i] / radius
		wheel_energy += 0.5 * float(contact.get("wheel_inertia", 0.00003)) * omega * omega
	var suspension := 0.0
	for i in mini(gear.contacts.size(), wheel_diagnostics.size()):
		var compression := maxf(0.0, float(wheel_diagnostics[i].get("compression", 0.0)))
		suspension += 0.5 * float(gear.contacts[i].get("stiffness", 0.0)) * compression * compression
	var terrain: PackedFloat64Array = Terrain.sample(state[RB.POS], state[RB.POS + 1], _surfaces)
	var altitude := float(terrain[0]) - state[RB.POS + 2]
	var gravity_potential := float(model.mass_kg) * GRAVITY * altitude
	return translation + rotation + wheel_energy + suspension + gravity_potential


func _run_drop(model: Dictionary, gear: Dictionary, support_state: PackedFloat64Array,
		drop_m: float, hz: int, landing_kind := "free_drop", pitch_delta := 0.0) -> Dictionary:
	var state := _landing_release_state(support_state, gear, drop_m, pitch_delta)
	var release_down := state[RB.POS + 2]
	var values := _combined(state, _wheel_speeds(gear, 0.0))
	var dt := 1.0 / float(hz)
	var ticks := ceili(DROP_HORIZON_S * hz)
	var context := {"evaluation": {}, "sampled": {}, "error": ""}
	var metrics := {"peak_compression_m": 0.0, "max_rim_speed_mps": 0.0, "max_contacts": 0,
		"any_contact_ticks": 0, "all_contact_ticks": 0, "max_abs_body_vertical_speed_mps": 0.0,
		"max_bounce_height_after_upward_reversal_m": 0.0, "contact_loss_events": 0,
		"contact_reacquisition_events": 0}
	var compression_by_wheel := []
	for i in gear.contacts.size():
		var contact: Dictionary = gear.contacts[i]
		compression_by_wheel.append({"wheel": contact.get("name", str(i)),
			"provisional_max_compression_m": float(contact.get("max_compression", INF)),
			"peak_compression_m": 0.0, "peak_over_limit_m": 0.0,
			"exceeded_provisional_limit": false})
	var first_contact_s := -1.0
	var previous_contact_count := 0
	var lost_contact := false
	var first_contact_times := {}
	var upward_reversal_s := -1.0
	var rebound_start_down := 0.0
	var rebound_started := false
	var rebound_finished := false
	var initial_evaluation: Dictionary = Ground.evaluate(values.slice(0, RB.SIZE), gear, 0.0,
		_surfaces, PackedFloat64Array(), values.slice(RB.SIZE), 0.0)
	var initial_energy := _mechanical_energy(values, model, gear, initial_evaluation.get("wheels", []))
	var maximum_energy_gain := 0.0
	var minimum_energy := initial_energy
	var final_world_vertical_speed := 0.0
	var time_s := 0.0
	for tick in ticks:
		values = _step(values, dt, model, gear, 0.0, context)
		if values.is_empty() or not _finite(values):
			_fail("%s %.3fm drop became nonfinite at %.3f s: %s" % [model.id, drop_m, time_s, context.error])
			break
		var sample: Dictionary = context.sampled
		var wheels: Array = sample.get("wheels", [])
		_update_contact_metrics(metrics, sample)
		for i in mini(wheels.size(), compression_by_wheel.size()):
			var compression := maxf(0.0, float(wheels[i].get("compression", 0.0)))
			var wheel_metrics: Dictionary = compression_by_wheel[i]
			wheel_metrics.peak_compression_m = maxf(float(wheel_metrics.peak_compression_m), compression)
			var limit := float(wheel_metrics.provisional_max_compression_m)
			wheel_metrics.peak_over_limit_m = maxf(float(wheel_metrics.peak_over_limit_m), maxf(0.0, compression - limit))
			wheel_metrics.exceeded_provisional_limit = bool(wheel_metrics.exceeded_provisional_limit) or compression > limit
		var contact_count := 0
		for i in wheels.size():
			var wheel: Dictionary = wheels[i]
			if float(wheel.get("normal_load", 0.0)) > 0.0:
				contact_count += 1
				if not first_contact_times.has(str(gear.contacts[i].get("name", i))):
					first_contact_times[str(gear.contacts[i].get("name", i))] = time_s
				if first_contact_s < 0.0:
					first_contact_s = time_s
		if previous_contact_count > 0 and contact_count == 0:
			metrics.contact_loss_events = int(metrics.contact_loss_events) + 1
			lost_contact = true
		elif previous_contact_count == 0 and contact_count > 0 and lost_contact:
			metrics.contact_reacquisition_events = int(metrics.contact_reacquisition_events) + 1
			lost_contact = false
		previous_contact_count = contact_count
		var attitude := M.quat(values[RB.ATT], values[RB.ATT + 1], values[RB.ATT + 2], values[RB.ATT + 3])
		var world_velocity := M.q_rotate(attitude, M.v3(values[RB.VEL], values[RB.VEL + 1], values[RB.VEL + 2]))
		final_world_vertical_speed = world_velocity[2]
		if first_contact_s >= 0.0 and not rebound_started and not rebound_finished and world_velocity[2] < -0.02:
			rebound_started = true
			upward_reversal_s = time_s
			rebound_start_down = values[RB.POS + 2]
		if rebound_started and not rebound_finished:
			if world_velocity[2] < 0.0:
				metrics.max_bounce_height_after_upward_reversal_m = maxf(float(metrics.max_bounce_height_after_upward_reversal_m),
					rebound_start_down - values[RB.POS + 2])
			else:
				rebound_finished = true
		metrics.max_abs_body_vertical_speed_mps = maxf(float(metrics.max_abs_body_vertical_speed_mps), absf(float(world_velocity[2])))
		var energy := _mechanical_energy(values, model, gear, wheels)
		minimum_energy = minf(minimum_energy, energy)
		maximum_energy_gain = maxf(maximum_energy_gain, energy - initial_energy)
		time_s += dt
	var energy_tolerance := 0.02
	if maximum_energy_gain > energy_tolerance:
		_fail("%s %s %gm drop gained %.6f J mechanical energy" % [model.id, landing_kind, drop_m, maximum_energy_gain])
	metrics["first_contact_time_s"] = first_contact_s
	metrics["first_contact_by_wheel_s"] = first_contact_times
	metrics["upward_reversal_time_s"] = upward_reversal_s
	metrics["initial_mechanical_energy_j"] = initial_energy
	metrics["final_mechanical_energy_j"] = _mechanical_energy(values, model, gear, context.sampled.get("wheels", []))
	metrics["minimum_mechanical_energy_j"] = minimum_energy
	metrics["maximum_mechanical_energy_gain_j"] = maximum_energy_gain
	metrics["energy_nonincreasing_within_tolerance"] = maximum_energy_gain <= energy_tolerance
	metrics["energy_gain_tolerance_j"] = energy_tolerance
	metrics["final_vertical_speed_mps"] = final_world_vertical_speed
	metrics["final_body_rates_radps"] = [values[RB.RATE], values[RB.RATE + 1], values[RB.RATE + 2]]
	metrics["final_down_m"] = values[RB.POS + 2]
	metrics["release_down_m"] = release_down
	metrics["compression_by_wheel"] = compression_by_wheel
	metrics["any_wheel_exceeded_provisional_compression_limit"] = false
	for wheel_metrics in compression_by_wheel:
		metrics.any_wheel_exceeded_provisional_compression_limit = bool(metrics.any_wheel_exceeded_provisional_compression_limit) or bool(wheel_metrics.exceeded_provisional_limit)
	return {"aircraft": model.id, "landing_kind": landing_kind, "pitch_delta_deg": rad_to_deg(pitch_delta),
		"drop_height_m": drop_m, "hz": hz, "duration_s": time_s,
		"finite": not values.is_empty() and _finite(values), "metrics": metrics}


func _run_taxi_turn(model: Dictionary, gear: Dictionary, support_state: PackedFloat64Array,
		steer: float, hz := 240, duration_s := 0.5) -> Dictionary:
	var initial := support_state.duplicate()
	_set_horizontal_velocity(initial, 1.5, 1.0)
	var values := _combined(initial, _rolling_wheel_speeds(initial, gear))
	var start_north := values[RB.POS]
	var start_east := values[RB.POS + 1]
	var start_yaw: float = M.q_to_euler(M.quat(values[RB.ATT], values[RB.ATT + 1], values[RB.ATT + 2], values[RB.ATT + 3]))[0]
	var dt := 1.0 / float(hz)
	var context := {"evaluation": {}, "sampled": {}, "error": ""}
	for _tick in ceili(duration_s * hz):
		values = _step(values, dt, model, gear, steer, context)
		if values.is_empty() or not _finite(values):
			_fail("%s steer %.3f taxi became nonfinite: %s" % [model.id, steer, context.error])
			break
	var final_yaw: float = M.q_to_euler(M.quat(values[RB.ATT], values[RB.ATT + 1], values[RB.ATT + 2], values[RB.ATT + 3]))[0]
	var yaw_change := wrapf(final_yaw - start_yaw + PI, 0.0, TAU) - PI
	return {"aircraft": model.id, "steer": steer, "initial_speed_mps": 1.5,
		"duration_s": duration_s, "distance_m": sqrt(pow(values[RB.POS] - start_north, 2.0) + pow(values[RB.POS + 1] - start_east, 2.0)),
		"yaw_change_rad": yaw_change, "yaw_change_deg": rad_to_deg(yaw_change),
		"final_horizontal_speed_mps": _horizontal_speed(values), "finite": not values.is_empty() and _finite(values)}


func _edge_probe(model: Dictionary, gear: Dictionary, support_state: PackedFloat64Array,
		speed: float, direction: String) -> Dictionary:
	var state := support_state.duplicate()
	var heading: float = M.q_to_euler(M.quat(state[RB.ATT], state[RB.ATT + 1], state[RB.ATT + 2], state[RB.ATT + 3]))[0]
	_set_horizontal_velocity(state, speed, 1.0 if direction == "eastbound" else -1.0)
	var speeds := _rolling_wheel_speeds(state, gear)
	var result: Dictionary = Ground.evaluate(state, gear, 0.0, _surfaces, PackedFloat64Array(), speeds, 0.0)
	var wheels: Array = result.get("wheels", [])
	var contacts := []
	for i in wheels.size():
		var c: Dictionary = gear.contacts[i]
		var wheel: Dictionary = wheels[i]
		contacts.append({"contact": c.get("name", str(i)), "surface_index": wheel.surface_index,
			"normal_load_n": wheel.normal_load, "rolling_force_n": wheel.rolling_force,
			"long_speed_mps": wheel.long_speed})
	return {"aircraft": model.id, "field": _field_id, "cg_north_m": state[RB.POS],
		"cg_east_m": state[RB.POS + 1], "direction": direction, "speed_mps": speed,
		"heading_rad": heading, "contacts": contacts,
		"body_yaw_moment_nm": result.loads[5] if result.loads.size() == 6 else 0.0}


func _contact_world_ned(state: PackedFloat64Array, contact: Dictionary) -> PackedFloat64Array:
	var q := M.quat(state[RB.ATT], state[RB.ATT + 1], state[RB.ATT + 2], state[RB.ATT + 3])
	var position: PackedFloat64Array = contact.get("position", PackedFloat64Array([0.0, 0.0, 0.0]))
	var offset := M.q_rotate(q, M.v3(position[0], position[1], position[2]))
	return M.v3(state[RB.POS] + offset[0], state[RB.POS + 1] + offset[1], state[RB.POS + 2] + offset[2])


func _edge_start(model: Dictionary, gear: Dictionary, direction: String) -> Dictionary:
	# Place every wheel 0.1 m on one material side of the lower N edge. The two directions
	# reverse the runway/rough transition while preserving an oblique eastbound path.
	var from_runway := direction == "runway_to_rough"
	var heading := PI / 2.0 + (EDGE_CROSSING_ANGLE if from_runway else -EDGE_CROSSING_ANGLE)
	var seed_north := EDGE_NORTH + 0.75 if from_runway else EDGE_NORTH - 0.75
	var support := _support(model, seed_north, ROUGH_EAST, heading)
	if not support.get("ok", false):
		return {"ok": false, "message": "seed support failed: " + str(support.get("message", "unknown"))}
	var target_extreme_north := EDGE_NORTH + EDGE_APPROACH_M if from_runway else EDGE_NORTH - EDGE_APPROACH_M
	var center_north: float = support.state[RB.POS]
	for _iteration in 3:
		var extreme_north := INF if from_runway else -INF
		for contact: Dictionary in gear.contacts:
			var point := _contact_world_ned(support.state, contact)
			extreme_north = minf(extreme_north, point[0]) if from_runway else maxf(extreme_north, point[0])
		var correction := target_extreme_north - extreme_north
		if absf(correction) < 0.000001:
			break
		center_north += correction
		support = _support(model, center_north, ROUGH_EAST, heading)
		if not support.get("ok", false):
			return {"ok": false, "message": "edge support iteration failed: " + str(support.get("message", "unknown"))}
	var state: PackedFloat64Array = support.state.duplicate()
	var expected_surface := 0 if from_runway else 6
	var initial_eval: Dictionary = Ground.evaluate(state, gear, 0.0, _surfaces,
		PackedFloat64Array(), _wheel_speeds(gear, 0.0), 0.0)
	var initial_wheels: Array = initial_eval.get("wheels", [])
	var initial_surfaces := []
	for wheel: Dictionary in initial_wheels:
		initial_surfaces.append(int(wheel.get("surface_index", -1)))
	if initial_surfaces.size() != gear.contacts.size():
		return {"ok": false, "message": "initial surface diagnostic count mismatch"}
	for i in gear.contacts.size():
		if initial_surfaces[i] != expected_surface:
			return {"ok": false, "message": "wheel %s starts on surface %d, expected %d" % [gear.contacts[i].get("name", str(i)), initial_surfaces[i], expected_surface]}
	return {"ok": true, "state": state, "heading_rad": heading,
		"target_extreme_north_m": target_extreme_north, "initial_surfaces": initial_surfaces,
		"support_residual": support.residual, "support_iterations": support.iterations}


func _run_edge_crossing(model: Dictionary, gear: Dictionary, speed: float, direction: String) -> Dictionary:
	var start := _edge_start(model, gear, direction)
	if not start.get("ok", false):
		_fail(str(model.id) + " " + direction + " edge-crossing start failed: " + str(start.get("message", "unknown")))
		return {"aircraft": model.id, "direction": direction, "initial_speed_mps": speed,
			"ok": false, "error": start.get("message", "unknown")}
	var state: PackedFloat64Array = start.state.duplicate()
	var north_sign := -1.0 if direction == "runway_to_rough" else 1.0
	_set_world_horizontal_velocity(state, north_sign * speed * sin(EDGE_CROSSING_ANGLE), speed * cos(EDGE_CROSSING_ANGLE))
	var wheel_speeds := _rolling_wheel_speeds(state, gear)
	var values := _combined(state, wheel_speeds)
	var dt := 1.0 / 240.0
	var context := {"evaluation": {}, "sampled": {}, "error": ""}
	var initial_evaluation: Dictionary = Ground.evaluate(state, gear, 0.0, _surfaces,
		PackedFloat64Array(), wheel_speeds, 0.0)
	var previous_wheels: Array = initial_evaluation.get("wheels", [])
	if previous_wheels.size() != gear.contacts.size():
		_fail("%s %s initial edge-crossing diagnostic count mismatch" % [model.id, direction])
		return {"aircraft": model.id, "direction": direction, "initial_speed_mps": speed, "ok": false}
	var previous_points: Array = []
	var previous_terrain: Array = []
	for i in gear.contacts.size():
		var point := _contact_world_ned(state, gear.contacts[i])
		previous_points.append(point)
		previous_terrain.append(Terrain.sample_validated(point[0], point[1], _surfaces))
	var transitions := []
	var transition_by_wheel := {}
	var main_names := ["main_left", "main_right"]
	var expected_from := 0 if direction == "runway_to_rough" else 6
	var expected_to := 6 if direction == "runway_to_rough" else 0
	var metrics := {"peak_compression_m": 0.0, "max_abs_height_step_m": 0.0,
		"max_height_continuity_residual_m": 0.0, "max_abs_normal_load_step_n": 0.0,
		"contact_loss_events": 0, "max_abs_vertical_speed_mps": absf(M.q_rotate(
		M.quat(state[RB.ATT], state[RB.ATT + 1], state[RB.ATT + 2], state[RB.ATT + 3]),
		M.v3(values[RB.VEL], values[RB.VEL + 1], values[RB.VEL + 2]))[2])}
	var time_s := 0.0
	var stopped := false
	var finite := true
	var previous_loads: PackedFloat64Array = initial_evaluation.get("loads", PackedFloat64Array())
	var ticks := 4 * 240
	for _tick in ticks:
		if transition_by_wheel.has("main_left") and transition_by_wheel.has("main_right"):
			break
		if _horizontal_speed(values) <= 0.1:
			stopped = true
			break
		var values_before := values.duplicate()
		values = _step(values, dt, model, gear, 0.0, context)
		if values.is_empty() or not _finite(values):
			_fail(str(model.id) + " " + direction + " " + str(speed) + " m/s dynamic edge crossing became nonfinite at " + str(time_s) + " s: " + str(context.error))
			finite = false
			break
		time_s += dt
		var state_now: PackedFloat64Array = values.slice(0, RB.SIZE)
		var wheels_now: Array = context.sampled.get("wheels", [])
		var loads_now: PackedFloat64Array = context.sampled.get("loads", PackedFloat64Array())
		if wheels_now.size() != gear.contacts.size():
			_fail(str(model.id) + " " + direction + " dynamic edge crossing diagnostic count mismatch")
			finite = false
			break
		for i in wheels_now.size():
			var contact: Dictionary = gear.contacts[i]
			var name := str(contact.get("name", str(i)))
			var previous: Dictionary = previous_wheels[i]
			var current: Dictionary = wheels_now[i]
			var point_now := _contact_world_ned(state_now, contact)
			var terrain_now := Terrain.sample_validated(point_now[0], point_now[1], _surfaces)
			var point_previous: PackedFloat64Array = previous_points[i]
			var terrain_previous: PackedFloat64Array = previous_terrain[i]
			var delta_height: float = terrain_now[0] - terrain_previous[0]
			var predicted_delta: float = 0.5 * (terrain_now[1] + terrain_previous[1]) * (point_now[0] - point_previous[0]) \
				+ 0.5 * (terrain_now[2] + terrain_previous[2]) * (point_now[1] - point_previous[1])
			var continuity_residual := absf(delta_height - predicted_delta)
			metrics.max_abs_height_step_m = maxf(float(metrics.max_abs_height_step_m), absf(delta_height))
			metrics.max_height_continuity_residual_m = maxf(float(metrics.max_height_continuity_residual_m), continuity_residual)
			var previous_load: float = previous.get("normal_load", 0.0)
			var current_load: float = current.get("normal_load", 0.0)
			if current_load < 0.0:
				_fail(str(model.id) + " " + direction + " " + str(speed) + " m/s " + name + " has a tensile normal load")
			metrics.max_abs_normal_load_step_n = maxf(float(metrics.max_abs_normal_load_step_n), absf(current_load - previous_load))
			metrics.peak_compression_m = maxf(float(metrics.peak_compression_m), float(current.get("compression", 0.0)))
			if previous_load > 0.0 and current_load <= 0.0:
				metrics.contact_loss_events += 1
			var from_index := int(previous.get("surface_index", -1))
			var to_index := int(current.get("surface_index", -1))
			if from_index != to_index and to_index >= 0 and not transition_by_wheel.has(name):
				var normal_before := maxf(0.0, previous_load)
				var normal_after := maxf(0.0, current_load)
				var crr_before := absf(float(previous.get("rolling_force", 0.0))) / normal_before if normal_before > 0.0 else 0.0
				var crr_after := absf(float(current.get("rolling_force", 0.0))) / normal_after if normal_after > 0.0 else 0.0
				var q := M.quat(state_now[RB.ATT], state_now[RB.ATT + 1], state_now[RB.ATT + 2], state_now[RB.ATT + 3])
				var world_velocity := M.q_rotate(q, M.v3(values[RB.VEL], values[RB.VEL + 1], values[RB.VEL + 2]))
				var q_before := M.quat(values_before[RB.ATT], values_before[RB.ATT + 1], values_before[RB.ATT + 2], values_before[RB.ATT + 3])
				var world_velocity_before := M.q_rotate(q_before, M.v3(values_before[RB.VEL], values_before[RB.VEL + 1], values_before[RB.VEL + 2]))
				var event := {"wheel": name, "from_surface_index": from_index, "to_surface_index": to_index,
					"time_s": time_s, "time_bracket_s": [time_s - dt, time_s],
					"north_m": point_now[0], "east_m": point_now[1],
					"speed_mps": _horizontal_speed(values),
					"north_speed_mps": world_velocity[0], "east_speed_mps": world_velocity[1],
					"normal_load_before_n": normal_before, "normal_load_after_n": normal_after,
					"compression_before_m": float(previous.get("compression", 0.0)),
					"compression_after_m": float(current.get("compression", 0.0)),
					"rolling_force_before_n": float(previous.get("rolling_force", 0.0)),
					"rolling_force_after_n": float(current.get("rolling_force", 0.0)),
					"rolling_coefficient_before": crr_before, "rolling_coefficient_after": crr_after,
					"body_ground_force_before_n": Array(previous_loads.slice(0, 3)) if previous_loads.size() == 6 else [],
					"body_ground_force_after_n": Array(loads_now.slice(0, 3)) if loads_now.size() == 6 else [],
					"body_down_speed_before_mps": world_velocity_before[2],
					"body_down_speed_after_mps": world_velocity[2],
					"body_down_speed_step_mps": world_velocity[2] - world_velocity_before[2],
					"terrain_height_before_up_m": terrain_previous[0], "terrain_height_after_up_m": terrain_now[0],
					"height_step_m": delta_height, "height_continuity_residual_m": continuity_residual,
					"body_yaw_moment_before_nm": previous_loads[5] if previous_loads.size() == 6 else 0.0,
					"body_yaw_moment_after_nm": loads_now[5] if loads_now.size() == 6 else 0.0}
				transitions.append(event)
				transition_by_wheel[name] = event
				if name in main_names:
					if normal_before <= 0.0 or normal_after <= 0.0:
						_fail(str(model.id) + " " + direction + " " + str(speed) + " m/s " + name + " crossed the edge without loaded contact")
					if float(event.speed_mps) <= 0.1:
						_fail(str(model.id) + " " + direction + " " + str(speed) + " m/s " + name + " crossed after reaching the 0.1 m/s stop threshold")
					var correct_order := from_index == expected_from and to_index == expected_to
					if not correct_order:
						_fail(str(model.id) + " " + direction + " " + str(speed) + " m/s " + name + " crossed from material " + str(from_index) + " to " + str(to_index))
					var rough_higher := crr_after > crr_before if direction == "runway_to_rough" else crr_before > crr_after
					if not rough_higher:
						_fail(str(model.id) + " " + direction + " " + str(speed) + " m/s " + name + " did not measure higher rough rolling coefficient (" + str(crr_before) + " / " + str(crr_after) + ")")
				if continuity_residual > 0.001:
					_fail(str(model.id) + " " + direction + " " + str(speed) + " m/s " + name + " terrain continuity residual exceeds 1 mm: " + str(continuity_residual) + " m")
			previous_points[i] = point_now
			previous_terrain[i] = terrain_now
			previous_wheels[i] = current
		previous_loads = loads_now
		var q_now := M.quat(state_now[RB.ATT], state_now[RB.ATT + 1], state_now[RB.ATT + 2], state_now[RB.ATT + 3])
		var velocity_world := M.q_rotate(q_now, M.v3(values[RB.VEL], values[RB.VEL + 1], values[RB.VEL + 2]))
		metrics.max_abs_vertical_speed_mps = maxf(float(metrics.max_abs_vertical_speed_mps), absf(velocity_world[2]))
	var left_event: Dictionary = transition_by_wheel.get("main_left", {})
	var right_event: Dictionary = transition_by_wheel.get("main_right", {})
	var both_main_events := not left_event.is_empty() and not right_event.is_empty()
	var distinct_order := both_main_events and absf(float(left_event.time_s) - float(right_event.time_s)) >= dt
	if not both_main_events:
		_fail(str(model.id) + " " + direction + " " + str(speed) + " m/s stopped or timed out before both main wheels crossed (events " + str(left_event.size()) + "/" + str(right_event.size()) + ", stopped " + str(stopped) + ")")
	elif not distinct_order:
		_fail(str(model.id) + " " + direction + " " + str(speed) + " m/s main wheel transitions were not separated by one 240 Hz tick")
	var final_surface_indices := []
	for wheel: Dictionary in previous_wheels:
		final_surface_indices.append(int(wheel.get("surface_index", -1)))
	return {"aircraft": model.id, "direction": direction, "initial_speed_mps": speed,
		"heading_rad": start.heading_rad, "heading_deg": rad_to_deg(start.heading_rad),
		"start_cg_north_m": values[RB.POS], "start_cg_east_m": values[RB.POS + 1],
		"target_extreme_north_m": start.target_extreme_north_m,
		"initial_surface_indices": start.initial_surfaces, "support_residual": start.support_residual,
		"support_iterations": start.support_iterations, "expected_from_surface_index": expected_from,
		"expected_to_surface_index": expected_to, "transitions": transitions,
		"main_wheel_crossings_ordered": distinct_order, "both_main_wheels_crossed": both_main_events,
		"stopped_before_both_crossed": stopped and not both_main_events,
		"duration_s": time_s, "final_horizontal_speed_mps": _horizontal_speed(values),
		"final_surface_indices": final_surface_indices,
		"finite": finite and not values.is_empty() and _finite(values), "metrics": metrics}


func _skid_probe(model: Dictionary, gear: Dictionary, support_state: PackedFloat64Array,
		side_speed: float) -> Dictionary:
	var state := support_state.duplicate()
	state[RB.VEL + 1] = side_speed
	var result: Dictionary = Ground.evaluate(state, gear, 0.0, _surfaces,
		PackedFloat64Array(), _wheel_speeds(gear, 0.0), 0.0)
	var wheels: Array = result.get("wheels", [])
	var diagnostics := []
	for i in wheels.size():
		diagnostics.append({"contact": gear.contacts[i].get("name", str(i)),
			"lateral_force_n": wheels[i].lateral_force, "normal_load_n": wheels[i].normal_load})
	return {"aircraft": model.id, "ground_only_lateral_skid_mps": side_speed,
		"body_side_force_n": result.loads[1] if result.loads.size() == 6 else 0.0,
		"body_yaw_moment_nm": result.loads[5] if result.loads.size() == 6 else 0.0,
		"wheel_forces": diagnostics}


func _run_aircraft(spec: Dictionary) -> Dictionary:
	var model := _load_model(spec)
	if model.is_empty():
		return {}
	var gear: Dictionary = model.landing_gear
	var wheels: Array = gear.contacts
	var output := {"id": model.id, "mass_kg": model.mass_kg,
		"wheel_profile": model.get("wheel_profile", {}), "contact_count": wheels.size(),
		"base_rolling_resistance": gear.get("rolling_resistance", 0.0),
		"rolling_reference_radius_m": gear.get("rolling_reference_radius", Ground.REFERENCE_RADIUS),
		"contacts": [], "coastdowns": [], "drops": [], "landings": [], "taxi_turns": [],
		"lateral_skids": [], "asymmetric_edges": [], "edge_crossings": []}
	for contact: Dictionary in wheels:
		output.contacts.append({"name": contact.name, "wheel_radius_m": contact.get("wheel_radius", 0.0),
			"wheel_inertia_kgm2": contact.get("wheel_inertia", 0.0),
			"spin_relaxation_s": contact.get("spin_relaxation", 0.0),
			"brake_torque_nm": contact.get("brake_torque", 0.0)})
	var runway_east_support := _support(model, RUNWAY_NORTH, EASTBOUND_START_EAST, EAST_HEADING)
	var runway_west_support := _support(model, RUNWAY_NORTH, WESTBOUND_START_EAST, WEST_HEADING)
	var rough_east_support := _support(model, ROUGH_NORTH, EASTBOUND_START_EAST, EAST_HEADING)
	var rough_west_support := _support(model, ROUGH_NORTH, WESTBOUND_START_EAST, WEST_HEADING)
	var supports := [runway_east_support, runway_west_support, rough_east_support, rough_west_support]
	for support: Dictionary in supports:
		if not support.get("ok", false):
			_fail("%s static support failed: %s" % [model.id, str(support.get("message", "unknown"))])
			return output
	output["support"] = {
		"runway_east_residual": runway_east_support.residual,
		"runway_west_residual": runway_west_support.residual,
		"rough_east_residual": rough_east_support.residual,
		"rough_west_residual": rough_west_support.residual,
		"runway_east_state": Array(runway_east_support.state),
		"runway_west_state": Array(runway_west_support.state),
		"rough_east_state": Array(rough_east_support.state),
		"rough_west_state": Array(rough_west_support.state)}
	for speed: float in COAST_SPEEDS:
		output.coastdowns.append(_run_coast(model, gear, runway_east_support.state, speed, 240, "runway", "eastbound"))
		output.coastdowns.append(_run_coast(model, gear, rough_east_support.state, speed, 240, "rough", "eastbound"))
		output.coastdowns.append(_run_coast(model, gear, runway_west_support.state, speed, 240, "runway", "westbound"))
		output.coastdowns.append(_run_coast(model, gear, rough_west_support.state, speed, 240, "rough", "westbound"))
	for drop_case: Array in DROP_CASES:
		output.drops.append(_run_drop(model, gear, runway_east_support.state, float(drop_case[0]), int(drop_case[1])))
	output.landings.append(_run_drop(model, gear, runway_east_support.state, 0.1, 240, "three_point", 0.0))
	output.landings.append(_run_drop(model, gear, runway_east_support.state, 0.1, 240, "mainwheel", -deg_to_rad(5.0)))
	for steer in [-0.2, 0.2]:
		output.taxi_turns.append(_run_taxi_turn(model, gear, runway_east_support.state, float(steer)))
	for side_speed in [-0.5, 0.5]:
		output.lateral_skids.append(_skid_probe(model, gear, runway_east_support.state, float(side_speed)))
	for direction_case: Dictionary in [
		{"name": "eastbound", "heading": EAST_HEADING, "east": -25.0},
		{"name": "westbound", "heading": WEST_HEADING, "east": -25.0}]:
		var edge_support := _support(model, EDGE_NORTH, float(direction_case.east), float(direction_case.heading))
		if edge_support.get("ok", false):
			for speed: float in COAST_SPEEDS:
				output.asymmetric_edges.append(_edge_probe(model, gear, edge_support.state, speed, str(direction_case.name)))
		else:
			_fail("%s edge support failed (%s): %s" % [model.id, direction_case.name, edge_support.get("message", "unknown")])
	for speed: float in COAST_SPEEDS:
		output.edge_crossings.append(_run_edge_crossing(model, gear, speed, "runway_to_rough"))
		output.edge_crossings.append(_run_edge_crossing(model, gear, speed, "rough_to_runway"))
	return output


func _write_output() -> void:
	_report.engine = Engine.get_version_info().string
	_report.field_id = _field_id
	_report.failure_count = _failures
	_report.ok = _failures == 0
	var serialized := JSON.stringify(_report, "\t") + "\n"
	print("GP_SCENARIO_JSON " + JSON.stringify(_report))
	for arg in OS.get_cmdline_user_args():
		if not str(arg).begins_with("--out="):
			continue
		var output_path := str(arg).trim_prefix("--out=")
		var file := FileAccess.open(output_path, FileAccess.WRITE)
		if file == null:
			_fail("cannot write scenario report %s (error %d)" % [output_path, FileAccess.get_open_error()])
			quit(1)
			return
		file.store_string(serialized)
		file.close()
		break
	quit(0 if _failures == 0 else 1)


func _initialize() -> void:
	if not _load_surfaces():
		_write_output()
		return
	for spec: Dictionary in AIRCRAFT:
		var result := _run_aircraft(spec)
		if not result.is_empty():
			_report.aircraft.append(result)
	_write_output()
