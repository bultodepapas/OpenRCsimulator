# DRAFT ONLY: the lead owns inspection, execution and interpretation.
# Real stock vehicle data and Session tick/observer paths; synthetic flat road and
# one narrow, frictionless AABB at altitude. Only initial pose/velocity are seeded.
# This is not a flown/driven approach, a real-RC severity measurement, or proof that
# the damage-energy residual is causally equal to contact work. Admission checks
# make the region assertion conditional on a front-probe-only damaging interval.
extends SceneTree

const Session := preload("res://sim/ground_vehicle/session.gd")
const Vehicle := preload("res://physics/ground_vehicle/vehicle_dynamics.gd")
const Nitro := preload("res://physics/ground_vehicle/nitro_dynamics.gd")
const Damage := preload("res://physics/ground_vehicle/vehicle_damage.gd")
const M := preload("res://physics/math3d.gd")

const NEUTRAL := {"throttle": 0.0, "steering": 0.0, "brake": 0.0,
	"reverse": false, "armed": true}
const ALTITUDE_M := 10.0
const FRONT_SPEED_MPS := 4.0
const DRIFT_SPEED_MPS := 8.0
const START_GAP_M := 0.001
const WALL_HALF_WIDTH_M := 0.05
const MAX_TICKS := 4
const EPS := 1.0e-9

var checks: Array[Dictionary] = []
var failures := 0


class RegionSession extends Session:
	var drift_mps := 0.0
	var include_wall := true
	var fixture_wall: Dictionary = {}

	func _fixture_road(wall: Dictionary) -> Callable:
		var included := include_wall
		var own_wall := wall.duplicate(true)
		return func(_north: float, _east: float) -> Dictionary:
			return {"height_m": 0.0, "normal_ned": PackedFloat64Array([0.0, 0.0, -1.0]),
				"mu": 0.0, "rolling": 0.0, "surface_id": "round4-flat-zero-grip",
				"walls": [own_wall] if included else []}

	func _stage_session(vehicle_result: Dictionary, course_result: Dictionary, requested_spawn: String,
			baseline_vehicle_result: Dictionary, pose_up_delta_m: float) -> Dictionary:
		var staged: Dictionary = super._stage_session(vehicle_result, course_result, requested_spawn,
			baseline_vehicle_result, pose_up_delta_m)
		if not bool(staged.get("ok", false)):
			return staged
		var model: Dictionary = staged.model
		var centers: PackedFloat64Array = model.hull_probe_centers_frd_m
		var radii: PackedFloat64Array = model.hull_probe_radii_m
		if centers.size() < 3 or radii.is_empty():
			return {"ok": false, "errors": PackedStringArray(["fixture needs the stock front probe"])}
		# The loaded stock inventory declares front bumper as probe 0. Check its
		# forward extent independently before using it as the fixture witness.
		var front_extent: float = centers[0] + radii[0]
		for i in range(1, radii.size()):
			if centers[3 * i] + radii[i] >= front_extent:
				return {"ok": false, "errors": PackedStringArray(["probe 0 is not uniquely frontmost"])}
		fixture_wall = {"id": "round4-narrow-front-wall",
			"north_min_m": front_extent + START_GAP_M,
			"north_max_m": front_extent + START_GAP_M + 0.5,
			"east_min_m": centers[1] - WALL_HALF_WIDTH_M,
			"east_max_m": centers[1] + WALL_HALF_WIDTH_M,
			"bottom_up_m": ALTITUDE_M - 2.0, "top_up_m": ALTITUDE_M + 2.0,
			"mu": 0.0}
		var road: Callable = _fixture_road(fixture_wall)
		var initial: PackedFloat64Array = staged.initial_state.duplicate()
		initial[Vehicle.POS] = 0.0
		initial[Vehicle.POS + 1] = 0.0
		initial[Vehicle.POS + 2] = -ALTITUDE_M
		initial[Vehicle.VEL] = FRONT_SPEED_MPS
		initial[Vehicle.VEL + 1] = drift_mps
		initial[Vehicle.VEL + 2] = 0.0
		initial[Vehicle.ATT] = 1.0
		for i in range(1, 4): initial[Vehicle.ATT + i] = 0.0
		for i in 3: initial[Vehicle.RATE + i] = 0.0
		if not _state_is_valid_for_model(initial, model):
			return {"ok": false, "errors": PackedStringArray(["seeded state was rejected"])}
		var telemetry: Dictionary = _telemetry_for_model(initial, model, road, _neutral_controls())
		if not _telemetry_is_valid_for_model(telemetry, model):
			return {"ok": false, "errors": PackedStringArray([str(telemetry.get("error", "seeded telemetry was rejected"))])}
		staged.road = road
		staged.initial_state = initial
		staged.telemetry = telemetry
		return staged


func _initialize() -> void:
	_run.call_deferred()


func _check(label: String, passed: bool) -> void:
	checks.append({"label": label, "passed": passed})
	if not passed: failures += 1
	print("%s %s" % ["ok" if passed else "FAIL", label])


func _plain(value: Variant) -> Variant:
	match typeof(value):
		TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_STRING_ARRAY:
			var array: Array = []
			for item in value: array.append(item)
			return array
		TYPE_ARRAY:
			var array: Array = []
			for item in value: array.append(_plain(item))
			return array
		TYPE_DICTIONARY:
			var dictionary: Dictionary = {}
			for key in value: dictionary[key] = _plain(value[key])
			return dictionary
	return value


func _max_abs(values: Variant) -> float:
	var maximum := 0.0
	for item in values: maximum = maxf(maximum, absf(float(item)))
	return maximum


func _point_geometry(state: PackedFloat64Array, model: Dictionary, wall: Dictionary) -> Dictionary:
	var position: PackedFloat64Array = state.slice(Vehicle.POS, Vehicle.POS + 3)
	var q: PackedFloat64Array = M.q_normalized(state.slice(Vehicle.ATT, Vehicle.ATT + 4))
	var centers: PackedFloat64Array = model.hull_probe_centers_frd_m
	var radii: PackedFloat64Array = model.hull_probe_radii_m
	var hull: Array = []
	for i in radii.size():
		var body_point: PackedFloat64Array = centers.slice(3 * i, 3 * i + 3)
		var point: PackedFloat64Array = M.add(position, M.q_rotate(q, body_point))
		var contact: Dictionary = Vehicle._sphere_aabb_contact(point, radii[i], wall)
		hull.append({"index": i, "center_ned_m": _plain(point), "radius_m": radii[i],
			"ground_clearance_m": -point[2] - radii[i], "wall_contact": _plain(contact)})
	var wheel: Array = []
	var geometry: Dictionary = Vehicle._corner_geometry(state, model, state[Vehicle.STEER],
		state[Vehicle.STEER_RATE], 0.0)
	if bool(geometry.get("ok", false)):
		for i in 4:
			var point: PackedFloat64Array = M.add(position, M.q_rotate(q, geometry.hub_position_body[i]))
			var radius := float(model.tire_radius_m)
			wheel.append({"index": i, "center_ned_m": _plain(point), "radius_m": radius,
				"ground_clearance_m": -point[2] - radius,
				"wall_contact": _plain(Vehicle._sphere_aabb_contact(point, radius, wall))})
	return {"hull": hull, "wheel": wheel, "wheel_geometry_ok": bool(geometry.get("ok", false))}


func _telemetry_report(t: Dictionary) -> Dictionary:
	return {"ok": bool(t.get("ok", false)), "error": str(t.get("error", "")),
		"total_energy_j": t.get("total_energy_j", null),
		"wall_contact_count": t.get("wall_contact_count", null),
		"wall_normal_load_n": t.get("wall_normal_load_n", null),
		"wall_friction_power_w": t.get("wall_friction_power_w", null),
		"wheel_in_contact": _plain(t.get("wheel_in_contact", [])),
		"wheel_load_n": _plain(t.get("wheel_load_n", [])),
		"wheel_wall_in_contact": _plain(t.get("wheel_wall_in_contact", [])),
		"wheel_wall_load_n": _plain(t.get("wheel_wall_load_n", [])),
		"hull_in_contact": _plain(t.get("hull_in_contact", [])),
		"hull_wall_load_n": _plain(t.get("hull_wall_load_n", [])),
		"damage": _plain(t.get("damage", {}))}


func _no_ground_or_wheel_wall(t: Dictionary) -> bool:
	if not bool(t.get("ok", false)): return false
	var wheel: Variant = t.get("wheel_in_contact", [])
	var wheel_wall: Variant = t.get("wheel_wall_load_n", [])
	var wheel_wall_flags: Variant = t.get("wheel_wall_in_contact", [])
	var hull: Variant = t.get("hull_in_contact", [])
	var hull_wall: Variant = t.get("hull_wall_load_n", [])
	if wheel.size() != 4 or wheel_wall.size() != 4 or wheel_wall_flags.size() != 4 \
			or hull.size() != hull_wall.size() or hull.is_empty(): return false
	if _max_abs(wheel) > 0.0 or _max_abs(wheel_wall) > 0.0 \
			or _max_abs(wheel_wall_flags) > 0.0: return false
	for i in hull.size():
		if (int(hull[i]) != 0) != (float(hull_wall[i]) > 0.0): return false
	return true


func _only_front_or_clear(t: Dictionary) -> bool:
	if not _no_ground_or_wheel_wall(t): return false
	var loads: Variant = t.get("hull_wall_load_n", [])
	for i in range(1, loads.size()):
		if float(loads[i]) != 0.0: return false
	return int(t.get("wall_contact_count", -1)) == (1 if float(loads[0]) > 0.0 else 0)


func _face_normal_is_forward(geometry: Dictionary, t: Dictionary) -> bool:
	var loads: Variant = t.get("hull_wall_load_n", [])
	if loads.is_empty() or float(loads[0]) <= 0.0: return true
	var contact: Dictionary = geometry.hull[0].wall_contact
	var normal: Array = contact.get("normal_ned", [])
	return bool(contact.get("overlap", false)) and normal.size() == 3 \
		and absf(float(normal[0]) + 1.0) < EPS and absf(float(normal[1])) < EPS \
		and absf(float(normal[2])) < EPS


func _geometry_has_no_other_contact(geometry: Dictionary, wall_present: bool) -> bool:
	if not bool(geometry.get("wheel_geometry_ok", false)): return false
	for item: Dictionary in geometry.get("hull", []):
		if float(item.ground_clearance_m) <= 0.0: return false
		if wall_present and int(item.index) != 0 and bool(item.wall_contact.get("overlap", false)): return false
	for item: Dictionary in geometry.get("wheel", []):
		if float(item.ground_clearance_m) <= 0.0: return false
		if wall_present and bool(item.wall_contact.get("overlap", false)): return false
	return true


# Re-evaluate the same tick in a detached instrumented shadow. For Nitro this
# reproduces the production midpoint powertrain setup before calling the shared
# body policy; for Bisonte it calls the same reference policy directly. An exact
# byte comparison with the accepted body endpoint is required before using these
# RK-stage observations as evidence about that interval. RK stages are not an
# independently flown trajectory or exact samples on the accepted path.
func _shadow_stages(s: RegionSession, before: PackedFloat64Array, after: PackedFloat64Array) -> Dictionary:
	var model: Dictionary = s.model_snapshot()
	var controls: Dictionary = s._neutral_controls()
	var body: PackedFloat64Array = before.slice(0, Vehicle.STATE_SIZE)
	var body_model: Dictionary = model
	var body_controls: Dictionary = controls
	if s._uses_nitro(model):
		var dt := Session.DT
		var wheel_speed: float = Nitro._mean_wheel_speed(before)
		var throttle := float(controls.throttle) if not bool(controls.reverse) else 0.0
		var initial: Dictionary = Nitro._engine_rates(before[Nitro.ENGINE_SPEED], before[Nitro.FUEL_MASS],
			throttle, wheel_speed, model.powertrain, not bool(controls.reverse),
			before[Nitro.FUEL_MASS] / dt, dt, float(model.wheel_spin_inertia_kg_m2))
		var mid_speed := clampf(before[Nitro.ENGINE_SPEED] + 0.5 * dt * float(initial.speed_rate_rad_s2),
			0.0, float(model.powertrain.engine_max_speed_rad_s))
		var mid_fuel := maxf(0.0, before[Nitro.FUEL_MASS] - 0.5 * dt * float(initial.fuel_flow_kg_per_s))
		var middle: Dictionary = Nitro._engine_rates(mid_speed, mid_fuel, throttle, wheel_speed,
			model.powertrain, not bool(controls.reverse), before[Nitro.FUEL_MASS] / dt, dt,
			float(model.wheel_spin_inertia_kg_m2))
		var wheel_torque := float(middle.wheel_drive_torque_nm)
		body_model = Nitro._body_model_with_drive_torque(model, wheel_torque)
		body_controls = Nitro._body_controls(controls, wheel_torque > 0.0,
			float(model.get("suspension_preload_n", 0.0)), minf(0.0, wheel_torque))
	var plan: Dictionary = Vehicle.begin_tick(body, body_model, body_controls, Session.DT, s._road)
	if not bool(plan.get("ok", false)):
		return {"ok": false, "error": "shadow begin_tick refused the fixture"}
	var shadow_road: Callable = plan.road
	var samples: Array[Dictionary] = []
	var evaluator := func(stage_state: PackedFloat64Array, stage_time: float) -> PackedFloat64Array:
		var telemetry: Dictionary = Vehicle.telemetry(stage_state, body_model, shadow_road, body_controls)
		samples.append({"stage_time_s": stage_time, "state": stage_state.duplicate(), "telemetry": telemetry})
		return Vehicle.stage_derivative(stage_state, body_model, body_controls, shadow_road)
	var first: PackedFloat64Array = evaluator.call(body, 0.0)
	if first.size() != Vehicle.STATE_SIZE:
		return {"ok": false, "error": "shadow initial stage failed"}
	var shadow: PackedFloat64Array = Vehicle.tick_policy(body, 0.0, Session.DT, evaluator, first, int(plan.substeps))
	var exact := shadow.size() == Vehicle.STATE_SIZE \
		and shadow.to_byte_array() == after.slice(0, Vehicle.STATE_SIZE).to_byte_array()
	var qualified := exact and not samples.is_empty()
	var front_seen := false
	var stages: Array = []
	for sample: Dictionary in samples:
		var state: PackedFloat64Array = sample.state
		var telemetry: Dictionary = sample.telemetry
		var geometry := _point_geometry(state, model, s.fixture_wall)
		var loads: Variant = telemetry.get("hull_wall_load_n", [])
		front_seen = front_seen or (not loads.is_empty() and float(loads[0]) > 0.0)
		qualified = qualified and _only_front_or_clear(telemetry) \
			and _geometry_has_no_other_contact(geometry, s.include_wall) \
			and _face_normal_is_forward(geometry, telemetry)
		stages.append({"stage_time_s": sample.stage_time_s, "state": _plain(state),
			"telemetry": _telemetry_report(telemetry), "geometry": geometry})
	return {"ok": true, "body_endpoint_exact": exact, "front_seen": front_seen,
		"front_only_and_ground_clear": qualified, "substeps": int(plan.substeps), "stages": stages}


func _capture(s: RegionSession) -> Dictionary:
	var state: PackedFloat64Array = s.state_snapshot()
	return {"tick": s.tick, "state": _plain(state),
		"telemetry": _telemetry_report(s.telemetry_snapshot()),
		"geometry": _point_geometry(state, s.model_snapshot(), s.fixture_wall),
		"damage_state": _plain(s.damage_snapshot()), "damage_visual": _plain(s.damage_visual_state()),
		"events": _plain(s.event_tape_snapshot())}


func _run_case(vehicle_id: String, drift: float, include_wall: bool) -> Dictionary:
	var s := RegionSession.new()
	s.drift_mps = drift
	s.include_wall = include_wall
	root.add_child(s)
	var result: Dictionary = {"vehicle_id": vehicle_id, "drift_mps": drift,
		"include_wall": include_wall, "prepared": false, "completed_ticks": 0, "trace": []}
	if not s.prepare_default({}, vehicle_id):
		result["error"] = s.load_error
		s.free()
		return result
	result.prepared = true
	result["model_identity"] = _plain(s.identities_snapshot())
	result["fixture_wall"] = _plain(s.fixture_wall)
	result["stock_hull_centers_frd_m"] = _plain(s.model_snapshot().hull_probe_centers_frd_m)
	result["stock_hull_radii_m"] = _plain(s.model_snapshot().hull_probe_radii_m)
	var initial_t: Dictionary = s.telemetry_snapshot()
	result["initial_no_ground_or_wall"] = _only_front_or_clear(initial_t) \
		and int(initial_t.get("wall_contact_count", -1)) == 0
	result.trace.append(_capture(s))
	result["recording_started"] = s.start_recording()
	if not s.tick_once(NEUTRAL) or not s.resume():
		result["error"] = "neutral arm/resume failed: " + s.load_error
		s.free()
		return result
	var first_damage := false
	var shadow_history: Array = []
	var all_shadow_qualified := true
	var any_shadow_front := false
	for i in MAX_TICKS:
		var before_state: PackedFloat64Array = s.state_snapshot()
		var before_t: Dictionary = s.telemetry_snapshot()
		var before_damage: PackedFloat64Array = s.damage_snapshot()
		if not s.tick_once(NEUTRAL):
			result["error"] = "tick failed: " + s.fault_reason + " " + s.load_error
			break
		result.completed_ticks += 1
		var after_state: PackedFloat64Array = s.state_snapshot()
		var after_t: Dictionary = s.telemetry_snapshot()
		var after_damage: PackedFloat64Array = s.damage_snapshot()
		var after_geometry := _point_geometry(after_state, s.model_snapshot(), s.fixture_wall)
		var shadow := _shadow_stages(s, before_state, after_state)
		shadow_history.append(shadow)
		all_shadow_qualified = all_shadow_qualified and bool(shadow.get("front_only_and_ground_clear", false))
		any_shadow_front = any_shadow_front or bool(shadow.get("front_seen", false))
		result.trace.append(_capture(s))
		var delta := PackedFloat64Array()
		for j in Damage.STATE_SIZE: delta.append(after_damage[j] - before_damage[j])
		var changed := false
		for j in 5: changed = changed or delta[j] > 0.0
		if changed and not first_damage:
			first_damage = true
			var after_loads: Variant = after_t.get("hull_wall_load_n", [])
			var front_after := not after_loads.is_empty() and float(after_loads[0]) > 0.0
			var before_speed := M.norm(before_state.slice(Vehicle.VEL, Vehicle.VEL + 3))
			var after_speed := M.norm(after_state.slice(Vehicle.VEL, Vehicle.VEL + 3))
			result["first_damage_tick"] = s.tick
			result["damage_delta"] = _plain(delta)
			result["speed_drop_mps"] = before_speed - after_speed
			result["mean_body_velocity_frd_mps"] = [0.5 * (before_state[3] + after_state[3]),
				0.5 * (before_state[4] + after_state[4]), 0.5 * (before_state[5] + after_state[5])]
			result["admitted_front_only"] = include_wall and _only_front_or_clear(before_t) \
				and _only_front_or_clear(after_t) and front_after \
				and _geometry_has_no_other_contact(after_geometry, true) \
				and _face_normal_is_forward(after_geometry, after_t) \
				and all_shadow_qualified and any_shadow_front
			break
	result["shadow_history"] = shadow_history
	result["all_shadow_front_only_and_ground_clear"] = all_shadow_qualified
	result["any_shadow_front"] = any_shadow_front
	if s.recording:
		result["recording_stopped"] = s.stop_recording()
		result["recording_metadata"] = _plain(s._recording_metadata())
	result["event_tape"] = _plain(s.event_tape_snapshot())
	result["control_tape"] = _plain(s.control_tape_snapshot())
	result["final_damage"] = _plain(s.damage_snapshot())
	result["final_visual"] = _plain(s.damage_visual_state())
	s.free()
	return result


func _front_only_damage(r: Dictionary) -> bool:
	var delta: Array = r.get("damage_delta", [])
	if delta.size() != Damage.STATE_SIZE: return false
	return float(delta[Damage.BODY_FRONT]) > 0.0 and float(delta[Damage.BODY_REAR]) == 0.0 \
		and float(delta[Damage.BODY_LEFT]) == 0.0 and float(delta[Damage.BODY_RIGHT]) == 0.0 \
		and float(delta[Damage.BODY_BOTTOM]) == 0.0


func _run() -> void:
	var old_hz := Engine.physics_ticks_per_second
	Engine.physics_ticks_per_second = 240
	var cases: Array = []
	for vehicle_id in ["mt8-bisonte", "monster-car-2"]:
		var positive := _run_case(vehicle_id, DRIFT_SPEED_MPS, true)
		var negative := _run_case(vehicle_id, -DRIFT_SPEED_MPS, true)
		var straight := _run_case(vehicle_id, 0.0, true)
		var clear := _run_case(vehicle_id, DRIFT_SPEED_MPS, false)
		cases.append_array([positive, negative, straight, clear])
		for named in [["positive drift", positive], ["negative drift", negative], ["straight", straight]]:
			var label: String = named[0]
			var r: Dictionary = named[1]
			_check(vehicle_id + " " + label + " fixture and recording prepared", bool(r.get("prepared", false)) \
				and bool(r.get("recording_started", false)) and bool(r.get("initial_no_ground_or_wall", false)) \
				and int(r.get("completed_ticks", 0)) > 0 and not r.has("error"))
			_check(vehicle_id + " " + label + " front-only damaging interval admitted", bool(r.get("admitted_front_only", false)))
			_check(vehicle_id + " " + label + " damage belongs to front probe", _front_only_damage(r))
		_check(vehicle_id + " clear-wall control has no body damage", bool(clear.get("prepared", false)) \
			and not clear.has("error") and int(clear.get("completed_ticks", 0)) == MAX_TICKS \
			and bool(clear.get("all_shadow_front_only_and_ground_clear", false)) \
			and not bool(clear.get("any_shadow_front", true)) \
			and float(clear.get("final_visual", {}).get("body_damage", -1.0)) == 0.0)
		var pos_velocity: Array = positive.get("mean_body_velocity_frd_mps", [])
		var neg_velocity: Array = negative.get("mean_body_velocity_frd_mps", [])
		_check(vehicle_id + " drift signs dominate forward speed at observed damage boundary", \
			pos_velocity.size() == 3 and neg_velocity.size() == 3 \
			and float(pos_velocity[1]) > absf(float(pos_velocity[0])) \
			and float(neg_velocity[1]) < -absf(float(neg_velocity[0])))
	var report := {"scope": "stock model, prescribed airborne start, synthetic front AABB, accepted Session ticks",
		"physics_hz": 240, "dt_s": Session.DT, "start_gap_m": START_GAP_M,
		"forward_speed_mps": FRONT_SPEED_MPS, "drift_speed_mps": DRIFT_SPEED_MPS,
		"wall_half_width_m": WALL_HALF_WIDTH_M, "wall_mu": 0.0,
		"warning": "fixture/course and initial pose are synthetic; energy is not isolated collision work",
		"checks": checks, "failures": failures, "cases": cases}
	print("ROUND4_CAR_REGION_JSON " + JSON.stringify(report, "", true, true))
	print("ROUND4_CAR_REGION_COMPLETE %d checks, %d failures" % [checks.size(), failures])
	Engine.physics_ticks_per_second = old_hz
	quit(1 if failures > 0 else 0)
