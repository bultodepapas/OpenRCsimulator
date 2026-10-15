extends SceneTree

## Source-free read-only probe for the R09 standard-column domain boundary.
## Run against the retained final-native snapshot, not the shared working app.
const Flight := preload("res://sim/flight_session.gd")
const Config := preload("res://physics/wind_config.gd")
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const FIELD_ELEVATION_M := -500.0
const EDGE_OUTWARD_SPEED_MPS := 0.25

const CASES := [
	{"id": "stik_prescribed", "path": "jensen_ugly_stik_60", "shaft": false},
	{"id": "turbine", "path": "sebart_avanti_s_a200", "shaft": false},
	{"id": "electric", "path": "turbo_lumber_evolution", "shaft": false},
	{"id": "shaft_coupled", "path": "p51d_mustang_120", "shaft": true},
	{"id": "glow", "path": "stik_glow_61fx_2t", "shaft": false},
]

func _initialize() -> void:
	Engine.physics_ticks_per_second = 240
	print(JSON.stringify({kind = "probe", godot = Engine.get_version_info(), hz = Engine.physics_ticks_per_second,
		config = "v4 standard_column; field_elevation_m=-500; no wind/turbulence overrides", field_elevation_m = FIELD_ELEVATION_M,
		boundaries_m = [-500.0, 11000.0],
		dt_s = 1.0 / Engine.physics_ticks_per_second, exact_edge_outward_ned_down_speed_mps = EDGE_OUTWARD_SPEED_MPS,
		inside_control_ned_down_speed_mps = 0.25,
		velocity_assignment = "preserve horizontal NED components; rotate requested NED down velocity into body frame"}))
	for case in CASES:
		for side in ["lower", "upper"]:
			_run_case(case, side)
	quit(0)

func _new_flight(case: Dictionary) -> Dictionary:
	var s := Flight.new()
	s.input_enabled = false
	s.crash_auto_restart = false
	var weather_ok: bool = s.setup_weather(Config.upgrade_column(Config.defaults(), {atmosphere_mode = "standard_column", field_elevation_m = FIELD_ELEVATION_M}))
	s.setup("res://data/aircraft/" + case.path + ".json")
	var shaft_ok := true
	if case.shaft:
		shaft_ok = s.setup_shaft_integrator("coupled-rk4")
		s.reset()
	var contact_context := {}
	if s.sim != null:
		contact_context = {
			post_step_collision_filter = s.sim.post_step.is_valid(),
			ground_surfaces_float_count = s.ground_surfaces.size(),
			wheel_count = s.wheel_count(),
			anchor_count = s.anchor_count(),
			soft_hull_contacts = s.soft_hull_contacts,
		}
	return {session = s, weather_ok = weather_ok, shaft_ok = shaft_ok, flyable = s.is_flyable(), contact_context = contact_context}

func _at_altitude(s: Flight, altitude_m: float, vertical_speed_mps: float) -> PackedFloat64Array:
	var body: PackedFloat64Array = s.sim.state.duplicate()
	body[RB.POS + 2] = FIELD_ELEVATION_M - altitude_m
	var q: PackedFloat64Array = body.slice(RB.ATT, RB.ATT + 4)
	var ned_velocity: PackedFloat64Array = M.q_rotate(q, body.slice(RB.VEL, RB.VEL + 3))
	ned_velocity[2] = vertical_speed_mps
	var q_inverse := PackedFloat64Array([q[0], -q[1], -q[2], -q[3]])
	var corrected_body_velocity: PackedFloat64Array = M.q_rotate(q_inverse, ned_velocity)
	for axis in 3:
		body[RB.VEL + axis] = corrected_body_velocity[axis]
	return body

func _ned_down_speed(body: PackedFloat64Array) -> float:
	var q: PackedFloat64Array = body.slice(RB.ATT, RB.ATT + 4)
	var ned_velocity: PackedFloat64Array = M.q_rotate(q, body.slice(RB.VEL, RB.VEL + 3))
	return ned_velocity[2]

func _geometric_altitude(body: PackedFloat64Array) -> float:
	return FIELD_ELEVATION_M - body[RB.POS + 2]

func _run_case(case: Dictionary, side: String) -> void:
	var created := _new_flight(case)
	var s: Flight = created.session
	var bound := -500.0 if side == "lower" else 11000.0
	var outward := 0.25 if side == "lower" else -0.25
	var clearance := 1.0
	var outside_clearance := 0.1
	var outside_altitude := bound - outside_clearance if side == "lower" else bound + outside_clearance
	var inside_altitude := bound + clearance if side == "lower" else bound - clearance
	var result: Dictionary = {
		kind = "family_boundary", family = case.id, aircraft = case.path, side = side,
		setup = {weather_ok = created.weather_ok, shaft_setup_ok = created.shaft_ok, flyable = created.flyable,
			contact_context = created.contact_context},
		field_elevation_m = FIELD_ELEVATION_M, bound_m = bound, outside_reset_altitude_m = outside_altitude,
		inside_reset_altitude_m = inside_altitude, inside_control_ned_down_speed_mps = outward,
		outside_reset_ned_down_speed_mps = outward,
	}
	if not created.weather_ok or not created.shaft_ok or not created.flyable or s.sim == null:
		result.stopped = "unsupported initialization; no forcing or tuning attempted"
		print(JSON.stringify(result))
		s.free()
		return

	var original_state: PackedByteArray = s.sim.state.to_byte_array()
	var original_loads: PackedByteArray = s.sim.last_loads.to_byte_array()
	var original_tick: int = s.sim.tick
	var outside_body := _at_altitude(s, outside_altitude, outward)
	var outside_env: Dictionary = s.environment_at(outside_body)
	var outside_reset_ok: bool = s.sim.reset(outside_body)
	result.out_of_domain = {
		query_ok = outside_env.get("ok", false), reset_ok = outside_reset_ok,
		state_unchanged = s.sim.state.to_byte_array() == original_state,
		loads_unchanged = s.sim.last_loads.to_byte_array() == original_loads,
		tick_unchanged = s.sim.tick == original_tick,
		state_altitude_after_m = _geometric_altitude(s.sim.state),
		fault_after = s.sim.fault_reason,
	}

	var inside_body := _at_altitude(s, inside_altitude, outward)
	var inside_env: Dictionary = s.environment_at(inside_body)
	var inside_reset_ok: bool = s.sim.reset(inside_body)
	var inside_start_tick: int = s.sim.tick
	var inside_pre_altitude: float = _geometric_altitude(s.sim.state)
	if inside_reset_ok:
		s.sim.step()
	result.in_domain_control = {
		query_ok = inside_env.get("ok", false), reset_ok = inside_reset_ok,
		step_fault = s.sim.fault_reason, tick_before = inside_start_tick, tick_after = s.sim.tick,
		start_altitude_m = inside_pre_altitude, end_altitude_m = _geometric_altitude(s.sim.state),
		actual_start_ned_down_mps = _ned_down_speed(inside_body),
	}

	var edge_body := _at_altitude(s, bound, outward)
	var edge_env: Dictionary = s.environment_at(edge_body)
	var edge_reset_ok: bool = s.sim.reset(edge_body)
	var edge_start_tick: int = s.sim.tick
	var edge_pre_body: PackedFloat64Array = s.sim.state.duplicate()
	var edge_pre_state: PackedByteArray = edge_pre_body.to_byte_array()
	var edge_pre_altitude: float = _geometric_altitude(s.sim.state)
	var rk2_altitude: float = bound - outward * s.sim.dt() * 0.5
	var rk2_body := _at_altitude(s, rk2_altitude, outward)
	var rk2_env: Dictionary = s.environment_at(rk2_body)
	if edge_reset_ok:
		s.sim.step()
	result.boundary_outward_step = {
		query_ok = edge_env.get("ok", false), reset_ok = edge_reset_ok,
		expected_rk2_altitude_m = rk2_altitude, expected_rk2_environment_query_ok = rk2_env.get("ok", false),
		step_fault = s.sim.fault_reason, tick_before = edge_start_tick, tick_after = s.sim.tick,
		start_altitude_m = edge_pre_altitude, end_altitude_m = _geometric_altitude(s.sim.state),
		requested_start_ned_down_mps = outward, actual_start_ned_down_mps = _ned_down_speed(edge_pre_body),
		state_unchanged_by_failed_step = s.sim.tick == edge_start_tick and s.sim.state.to_byte_array() == edge_pre_state,
	}
	print(JSON.stringify(result))
	s.free()
