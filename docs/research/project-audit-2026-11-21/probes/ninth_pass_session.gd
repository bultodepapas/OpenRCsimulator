extends SceneTree
## Source-pinned integration observations. Synthetic wall and elevated practice
## spawn are declared fixtures, not a recorded player drive or jump.
const Session := preload("res://sim/ground_vehicle/session.gd")
const Data := preload("res://physics/ground_vehicle/vehicle_data.gd")
const Course := preload("res://physics/ground_vehicle/course.gd")
const Field := preload("res://data/field_loader.gd")
const Vehicle := preload("res://physics/ground_vehicle/vehicle_dynamics.gd")
const Nitro := preload("res://physics/ground_vehicle/nitro_dynamics.gd")
const M := preload("res://physics/math3d.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(label: String, condition: bool) -> void:
	checks += 1
	if not condition: failures += 1
	print(("PASS " if condition else "FAIL ") + label)

func controls(throttle: float = 0.0, brake: float = 0.0) -> Dictionary:
	return {"throttle": throttle, "steering": 0.0, "brake": brake,
		"reverse": false, "source": "r9-probe", "armed": true}

func run() -> void:
	check("reference backend selection", Vehicle.set_backend_override_for_tests(Vehicle.BACKEND_GDSCRIPT_REFERENCE))
	wall_session()
	heading_session()
	nitro_session()
	print("R9 SESSION: %d checks, %d failed" % [checks, failures])
	quit(0 if failures == 0 else 1)

func wall_session() -> void:
	var field: Dictionary = Field.load_from()
	check("stock field loads", bool(field.get("ok", false)))
	var plain = Session.new()
	root.add_child(plain)
	var prepared: bool = plain.prepare_airfield(field)
	check("stock Bisonte airfield preparation", prepared)
	if not prepared:
		print(plain.load_error)
		plain.free()
		return
	var model: Dictionary = plain.model_snapshot()
	var initial: PackedFloat64Array = plain.state_snapshot()
	var q: PackedFloat64Array = initial.slice(6, 10)
	var front_center: PackedFloat64Array = model.hull_probe_centers_frd_m.slice(0, 3)
	var center_world: PackedFloat64Array = M.add(initial.slice(0, 3), M.q_rotate(q, front_center))
	var radius: float = model.hull_probe_radii_m[0]
	var overlap: float = 1.0 / float(model.hull_contact_stiffness_n_per_m)
	var boundary: float = center_world[1] + radius - overlap
	# Default runway spawn faces east; admit one ordinary normalized box through
	# prepare_airfield's real scenery bridge. No _road/state replacement is used.
	check("fixture default runway heading is east", absf(M.q_rotate(q, PackedFloat64Array([1.0, 0.0, 0.0]))[1] - 1.0) < 1.0e-12)
	var proxy := {"id": "r9-synthetic-wall", "shape": "box", "north": initial[0],
		"east": boundary + 0.15, "down": -1.0, "half_x": 0.15, "half_z": 1.0,
		"half_down": 1.0, "sin_heading": 0.0, "cos_heading": 1.0,
		"response_class": "hard_terminal"}
	var world := {"identity": JSON.stringify(proxy).sha256_text(), "proxies": [proxy]}
	var s = Session.new()
	root.add_child(s)
	var wall_prepared: bool = s.prepare_airfield(field, {}, {}, "mt8-bisonte", world)
	check("synthetic box admitted through production airfield preparation", wall_prepared)
	if not wall_prepared:
		print(s.load_error)
		s.free()
		plain.free()
		return
	var before: PackedFloat64Array = s.state_snapshot()
	check("wall does not alter initial supported pose", before.to_byte_array() == initial.to_byte_array())
	var road: Callable = s.environment.road
	var stage: Dictionary = Vehicle._evaluate_active(before, model, controls(0.0, 1.0), road, false, true)
	var no_wall_stage: Dictionary = Vehicle._evaluate_active(before, model, controls(0.0, 1.0), plain.environment.road, false, true)
	check("prepared session stage accepts exactly one near-1-N wall contact", bool(stage.get("ok", false))
		and int(stage.get("wall_contact_count", 0)) == 1 and absf(float(stage.get("wall_normal_load_n", 0.0)) - 1.0) < 1.0e-7)
	var acceleration: PackedFloat64Array = stage.get("generalized_acceleration", PackedFloat64Array())
	var base_acceleration: PackedFloat64Array = no_wall_stage.get("generalized_acceleration", PackedFloat64Array())
	check("wall adds a substantial wheel acceleration to the same prepared no-wall state",
		acceleration.size() == 14 and base_acceleration.size() == 14 and absf(acceleration[10] - base_acceleration[10]) > 0.1)
	check("wall leaves the ground and brake solution unchanged", bool(no_wall_stage.get("ok", false))
		and stage.wheel_longitudinal_force_n.to_byte_array() == no_wall_stage.wheel_longitudinal_force_n.to_byte_array()
		and stage.wheel_lateral_force_n.to_byte_array() == no_wall_stage.wheel_lateral_force_n.to_byte_array()
		and stage.wheel_brake_torque_n_m.to_byte_array() == no_wall_stage.wheel_brake_torque_n_m.to_byte_array())
	check("neutral sample and explicit resume accepted", s.tick_once(controls()) and s.resume())
	var accepted: bool = s.tick_once(controls(0.0, 1.0))
	check("one braked wall tick committed by shared kernel", accepted and s.tick == 1 and s.fault_reason.is_empty())
	var after: PackedFloat64Array = s.state_snapshot()
	check("accepted tick moves relative wheel spin", after.size() == 31 and absf(after[21]) > 1.0e-7)
	check("matched no-wall braked tick accepted", plain.tick_once(controls()) and plain.resume()
		and plain.tick_once(controls(0.0, 1.0)) and plain.tick == 1 and plain.fault_reason.is_empty())
	var plain_after: PackedFloat64Array = plain.state_snapshot()
	check("wall changes the committed tick relative to matched no-wall control", after.to_byte_array() != plain_after.to_byte_array())
	var checkpoint: Dictionary = s.checkpoint()
	check("wall tick checkpoint admitted and restores exact state", s.can_restore_checkpoint(checkpoint)
		and s.restore_checkpoint(checkpoint) and after.to_byte_array() == s.state_snapshot().to_byte_array())
	print("R9_WALL_SESSION=", JSON.stringify({"fixture": "stock Bisonte/field, synthetic normalized box at spawn",
		"backend": Vehicle.backend_identity(), "world": world,
		"initial_wheel_acceleration_rad_s2": acceleration.slice(10, 14),
		"no_wall_initial_wheel_acceleration_rad_s2": base_acceleration.slice(10, 14),
		"initial_wall_load_n": stage.get("wall_normal_load_n", 0.0),
		"initial_sweeps": stage.get("friction_sweeps_used", -1),
		"accepted_tick": s.tick, "wheel_spin_after_rad_s": after.slice(21, 25),
		"no_wall_wheel_spin_after_rad_s": plain_after.slice(21, 25),
		"body_velocity_after_m_s": after.slice(3, 6), "identities": s.identities_snapshot()}))
	s.free()
	plain.free()

func heading_session() -> void:
	var loaded: Dictionary = Data.load_default()
	loaded["vehicle_id"] = "mt8-bisonte"
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Course.DEFAULT_PATH))
	var stock_course: Dictionary = Course.validate(raw)
	var road := func(north: float, east: float) -> Dictionary:
		return Course.sample(stock_course.course, north, east)
	var supported: Dictionary = Vehicle.initialize(loaded.model, road)
	check("heading fixture has validated stock vehicle/course and supported height", bool(loaded.get("ok", false))
		and bool(stock_course.get("ok", false)) and bool(supported.get("ok", false)))
	var up: float = -supported.state[2] - 0.00001
	var stages: Array[Dictionary] = []
	var states: Array[PackedFloat64Array] = []
	var rows: Array[Dictionary] = []
	for heading: float in [0.0, PI / 2.0]:
		var custom: Dictionary = raw.duplicate(true)
		custom.spawns[0].heading_rad.value = heading
		custom.spawns[0].vehicle_up_m.value = up
		for key: String in ["heading_rad", "vehicle_up_m"]:
			custom.spawns[0][key].kind = "estimated"
			custom.spawns[0][key].source = "estimated: R9 diagnostic yaw/10-micrometre support compression; not measured vehicle data"
		var changed: Dictionary = Course.parse_text(JSON.stringify(custom, "", true, true))
		check("synthetic heading/height course passes full loader %.1f" % heading, bool(changed.get("ok", false)))
		var s = Session.new()
		root.add_child(s)
		var prepared: bool = s.prepare(loaded, changed)
		check("synthetic course passes public Session.prepare %.1f" % heading, prepared)
		if not prepared:
			print(s.load_error)
			s.free()
			return
		var initial: PackedFloat64Array = s.state_snapshot()
		var stage: Dictionary = Vehicle._evaluate_active(initial, s.model_snapshot(), controls(), s.environment.road, false, true)
		check("prepared yaw stage accepts four tyre contacts %.1f" % heading, bool(stage.get("ok", false))
			and (stage.wheel_in_contact as PackedByteArray).count(1) == 4)
		check("neutral yaw tick commits %.1f" % heading, s.tick_once(controls()) and s.resume()
			and s.tick_once(controls()) and s.tick == 1 and s.fault_reason.is_empty())
		stages.append(stage)
		states.append(s.state_snapshot())
		rows.append({"heading_rad": heading, "up_m": up, "accepted_tick": s.tick,
			"sweeps": stage.friction_sweeps_used, "lateral_force_n": stage.wheel_lateral_force_n,
			"travel_acceleration_m_s2": stage.generalized_acceleration.slice(6, 10),
			"travel_rates_after_m_s": states[-1].slice(17, 21), "identities": s.identities_snapshot()})
		s.free()
	check("only zero heading skips the prepared tyre solve", int(stages[0].friction_sweeps_used) == 0
		and int(stages[1].friction_sweeps_used) > 0)
	var maximum := 0.0
	for i in range(17, 21): maximum = maxf(maximum, absf(states[0][i] - states[1][i]))
	check("yaw-dependent derivative changes accepted suspension rates", maximum > 1.0e-8)
	print("R9_HEADING_SESSION=", JSON.stringify({"fixture": "stock vehicle; fully validated practice variants change start heading and CG height only, with honest provenance",
		"max_travel_rate_difference_m_s": maximum, "records": rows}))

func nitro_session() -> void:
	var loaded: Dictionary = Data.load_vehicle("monster-car-2")
	loaded["vehicle_id"] = "monster-car-2"
	var course: Dictionary = Course.load_default()
	check("stock nitro and practice course load", bool(loaded.get("ok", false)) and bool(course.get("ok", false)))
	var states: Array[PackedFloat64Array] = []
	var records: Array[Dictionary] = []
	for throttle: float in [0.0, 1.0]:
		var s = Session.new()
		root.add_child(s)
		var prepared: bool = s.prepare(loaded, course, loaded, 5.0)
		check("elevated practice spawn accepted %.1f" % throttle, prepared)
		if not prepared:
			print(s.load_error)
			s.free()
			return
		var initial: PackedFloat64Array = s.state_snapshot()
		var before: Dictionary = s.telemetry_snapshot()
		check("prepared nitro session is airborne %.1f" % throttle, bool(before.get("airborne", false)))
		check("neutral and resume accepted %.1f" % throttle, s.tick_once(controls()) and s.resume())
		var accepted: bool = s.tick_once(controls(throttle))
		check("nitro composite policy commits tick %.1f" % throttle, accepted and s.tick == 1 and s.fault_reason.is_empty())
		var state: PackedFloat64Array = s.state_snapshot()
		var telemetry: Dictionary = s.telemetry_snapshot()
		check("session remains airborne and clutch open %.1f" % throttle, bool(telemetry.get("airborne", false))
			and float(telemetry.nitro.clutch_engagement) == 0.0 and float(telemetry.nitro.wheel_drive_torque_nm) == 0.0)
		states.append(state)
		records.append({"throttle": throttle, "accepted_tick": s.tick,
			"initial_rpm": initial[31] * Nitro.RPM_PER_RAD_S, "final_rpm": state[31] * Nitro.RPM_PER_RAD_S,
			"flywheel_delta_h_nms": float(loaded.model.powertrain.engine_rotor_inertia_kg_m2) * (state[31] - initial[31]),
			"body_rates_rad_s": state.slice(10, 13), "identities": s.identities_snapshot()})
		s.free()
	var same_body: bool = states[0].slice(0, 31).to_byte_array() == states[1].slice(0, 31).to_byte_array()
	check("accepted neutral/full session body states are byte-identical", same_body)
	check("accepted full-throttle session changes flywheel speed", states[1][31] > states[0][31])
	print("R9_NITRO_SESSION=", JSON.stringify({"fixture": "stock nitro and practice, +5m public preparation height offset",
		"body_bytes_equal": same_body, "records": records}))
