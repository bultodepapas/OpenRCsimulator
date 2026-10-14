# TT-11: qualify Timber runway support, tailwheel taxi steering, ground takeoff, and gear-travel failure detection.
extends SceneTree

const Session := preload("res://sim/flight_session.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const AircraftData := preload("res://physics/aircraft_data.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const GroundStart := preload("res://physics/ground_start.gd")
const Ground := preload("res://physics/ground_contact.gd")
const ImpactSnapshot := preload("res://physics/impact_snapshot.gd")
const Sim := preload("res://sim/simulation.gd")
const RB := preload("res://physics/rigid_body.gd")
const Airplane := preload("res://render/airplane.gd")

const TIMBER_ID := "turbo-lumber-evolution"
const G := 9.80665

var _checks := 0
var _failures := 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	print(("ok   " if ok else "FAIL ") + label + ("" if detail.is_empty() else "  " + detail))
	if not ok:
		_failures += 1


func _initialize() -> void:
	_run()


func _run() -> void:
	var entry: Dictionary = Catalog.entry(TIMBER_ID)
	_check("Timber catalog entry has data", not entry.is_empty() and FileAccess.file_exists(str(entry.get("data", ""))))
	if entry.is_empty() or not FileAccess.file_exists(str(entry.get("data", ""))):
		_finish()
		return
	var loaded: Dictionary = AircraftData.load_file(str(entry.data))
	_check("Timber aircraft data and tyre profile load", loaded.ok, str(loaded.errors))
	if not loaded.ok:
		_finish()
		return
	var model: Dictionary = loaded.model
	var gear: Dictionary = model.get("landing_gear", {})
	_check("Timber wheel profile is applied", model.get("wheel_profile", {}).get("status", "") == "applied",
		str(model.get("wheel_profile", {})))
	_check("Timber has three named profiled contacts", gear.get("contacts", []).size() == 3)
	for contact: Dictionary in gear.get("contacts", []):
		var expected_radius: float = 0.014 if contact.name == "tail" else 0.058002
		_check("%s accepted tyre-profile radius is retained" % str(contact.name),
			absf(float(contact.get("wheel_radius", 0.0)) - expected_radius) < 1e-9,
			str(contact.get("wheel_radius", NAN)))
	_check("wheel profile identity is recorded for trace v6", str(model.get("wheel_profile", {}).get("profile_sha256", "")).length() == 64)

	var field_result: Dictionary = FieldLoader.load_from()
	_check("default runway field loads", field_result.ok, str(field_result.errors))
	if not field_result.ok:
		_finish()
		return
	var field: Dictionary = field_result.field
	var spot: Dictionary = GroundStart.threshold(field)
	_check("default runway has a valid threshold", spot.ok, str(spot))
	if not spot.ok:
		_finish()
		return
	var session: Node = Session.new()
	session.input_enabled = false
	session.setup(str(entry.data))
	root.add_child(session)
	_check("Timber accepts the default field", session.set_field(field))
	session.start_choice = Session.START_RUNWAY
	session.reset()
	var started: bool = session.start_error.is_empty() and session.is_flyable()
	_check("Timber selected runway equilibrium solves", started and session.is_flyable()
		and session.sim.fault_reason.is_empty(), session.start_error)
	var launch_meta: Dictionary = session.trace_meta()
	var launch_meta_ok: bool = launch_meta.get("selected_start_choice") == Session.START_RUNWAY \
		and launch_meta.get("launch_choice") == Session.START_RUNWAY \
		and launch_meta.get("launch_kind") == "runway_threshold"
	_check("selected runway path records Timber threshold launch", launch_meta_ok,
		"choice=%s kind=%s field=%s" % [str(launch_meta.get("launch_choice", "")),
		str(launch_meta.get("launch_kind", "")), str(launch_meta.get("launch_field_id", ""))])
	if not started:
		session.queue_free()
		_finish()
		return
	var launch: PackedFloat64Array = session.sim.state.duplicate()
	var compressions: PackedFloat64Array = session.gear_compressions(launch)
	var load_sum := 0.0
	for index in compressions.size():
		load_sum += float(gear.contacts[index].stiffness) * compressions[index]
	_check("static tyre loads sum to weight within 1%", absf(load_sum - float(model.mass_kg) * G) < 0.01 * float(model.mass_kg) * G,
		"%.4f N vs %.4f N" % [load_sum, float(model.mass_kg) * G])
	var all_compressed := compressions.size() == 3
	for compression in compressions:
		all_compressed = all_compressed and compression > 0.0
	_check("all three wheels support the initial pose", all_compressed,
		str(compressions))
	_check("settled runway pose is within all landing-gear travel limits", not session.gear_collapsed(launch))
	var overtravel: PackedFloat64Array = launch.duplicate()
	var travel_limit := 0.0
	for contact: Dictionary in gear.contacts:
		travel_limit = maxf(travel_limit, float(contact.max_compression))
	overtravel[RB.POS + 2] += travel_limit + 0.01
	var gear_impact: ImpactSnapshot.Snapshot = ImpactSnapshot.gear_limit(overtravel,
		session.sim.tick, gear, session.ground_surfaces)
	_check("excessive wheel compression is detected as a typed gear-travel failure",
		session.gear_collapsed(overtravel) and gear_impact.trigger == "gear_limit" and gear_impact.has_compression
		and gear_impact.compression_m > gear_impact.travel_limit_m and not gear_impact.component_name.is_empty(),
		"%s compressed %.4f m beyond %.4f m" % [gear_impact.component_name,
		gear_impact.compression_m, gear_impact.travel_limit_m])

	# An idle electric start remains settled; this catches the contact, profile, and support-polygon interaction.
	var dt: float = session.sim.dt()
	var max_speed := 0.0
	var max_rate := 0.0
	for _tick in roundi(1.0 / dt):
		session.sim.step()
		session._physics_process(dt)
		var state: PackedFloat64Array = session.sim.state
		max_speed = maxf(max_speed, _speed(state))
		max_rate = maxf(max_rate, sqrt(state[RB.RATE] ** 2 + state[RB.RATE + 1] ** 2 + state[RB.RATE + 2] ** 2))
	var idle_state: PackedFloat64Array = session.sim.state
	var moved := 0.0
	for axis in 3:
		moved += (idle_state[RB.POS + axis] - launch[RB.POS + axis]) ** 2
	moved = sqrt(moved)
	_check("one second at idle stays settled without a crash", max_speed < 1e-4 and max_rate < 1e-4
		and moved < 1e-4 and session.crash.is_empty() and session.sim.fault_reason.is_empty(),
		"max |v| %s m/s, |ω| %s rad/s, moved %s m, crash=%s fault=%s" %
		[str(max_speed), str(max_rate), str(moved), str(session.crash), session.sim.fault_reason])

	# Tailwheel geometry and ground-force sign use the same positive-right yaw convention as the taildragger fixtures.
	var tail: Dictionary = {}
	for contact: Dictionary in gear.contacts:
		if str(contact.name) == "tail":
			tail = contact
	_check("positive right rudder steers the aft tailwheel left", not tail.is_empty()
		and float(tail.get("max_steering", 0.0)) < 0.0, str(tail.get("max_steering", NAN)))
	var right_turn: Dictionary = _taxi_turn(model, launch, 1.0)
	var left_turn: Dictionary = _taxi_turn(model, launch, -1.0)
	_check("taxi steering: right rudder yaws right and left rudder yaws left",
		float(right_turn.yaw_rate) > 0.0 and float(left_turn.yaw_rate) < 0.0
		and str(right_turn.fault).is_empty() and str(left_turn.fault).is_empty(),
		"right %s rad/s; left %s rad/s" % [str(right_turn.yaw_rate), str(left_turn.yaw_rate)])

	# Exercise the same manifest-bound model as flight; raw builders do not supply common adapter bindings.
	var visual: Dictionary = Airplane.build(TIMBER_ID)
	var steering_angle: float = float(tail.get("max_steering", 0.0))
	Airplane.apply_gear(visual, {}, steering_angle)
	var applied_steering: float = visual.gear.steering.rotation.y
	_check("render adapter applies the signed tailwheel steering angle", visual.get("gear", {}).has("steering")
		and absf(wrapf(applied_steering - steering_angle, -PI, PI)) < 1e-6,
		"actual %s rad; expected %s rad" % [str(applied_steering), str(steering_angle)])
	visual.root.free()

	var takeoff: Dictionary = _takeoff(session, launch)
	_check("full-throttle runway roll lifts off without a crash", bool(takeoff.airborne)
		and str(takeoff.fault).is_empty() and takeoff.crash.is_empty(),
		"airborne=%s speed=%s m/s up=%s m fault=%s crash=%s" %
		[takeoff.airborne, str(takeoff.speed), str(takeoff.up), takeoff.fault, str(takeoff.crash)])
	session.queue_free()
	var takeoff_480: Dictionary = _takeoff_at_rate(str(entry.data), field, 480)
	var speed_delta := absf(float(takeoff.speed) - float(takeoff_480.speed))
	_check("runway takeoff agrees qualitatively at 240 and 480 Hz",
		bool(takeoff.airborne) and bool(takeoff_480.airborne) and speed_delta < 2.0
		and str(takeoff_480.fault).is_empty() and takeoff_480.crash.is_empty(),
		"240 Hz %.3f m/s; 480 Hz %.3f m/s; Δ %.3f m/s" %
		[float(takeoff.speed), float(takeoff_480.speed), speed_delta])
	_finish()


func _taxi_turn(model: Dictionary, parked: PackedFloat64Array, steer: float) -> Dictionary:
	var sim: Node = Sim.new()
	sim.mass = float(model.mass_kg)
	sim.inertia = model.inertia.duplicate()
	var gear: Dictionary = model.landing_gear
	sim.loads = func(state: PackedFloat64Array, _time: float) -> PackedFloat64Array:
		var loads: PackedFloat64Array = Ground.loads(state, gear, steer)
		loads[0] += 20.0 * (1.0 - state[RB.VEL])
		return loads
	var state: PackedFloat64Array = parked.duplicate()
	state[RB.VEL] = 1.0
	sim.reset(state)
	for _tick in roundi(2.0 / sim.dt()):
		sim.step()
	var result := {yaw_rate = sim.state[RB.RATE + 2], fault = sim.fault_reason}
	sim.free()
	return result


func _takeoff(session: Node, launch: PackedFloat64Array) -> Dictionary:
	var airborne := false
	var speed := 0.0
	var up := 0.0
	var fault := ""
	session.input_enabled = true
	session.read_raw = func() -> Dictionary:
		var current: PackedFloat64Array = session.sim.state
		var current_speed := _speed(current)
		return {roll = 0.0, pitch = 0.12 if current_speed >= 8.0 else 0.0, yaw = 0.0, throttle = 1.0}
	var dt: float = session.sim.dt()
	for _tick in roundi(12.0 / dt):
		session._physics_process(dt)
		if session.sim.paused or not session.sim.fault_reason.is_empty():
			break
		session.sim.step()
		session._physics_process(dt)
		var state: PackedFloat64Array = session.sim.state
		speed = _speed(state)
		up = -(state[RB.POS + 2] - launch[RB.POS + 2])
		fault = session.sim.fault_reason
		var wheels_clear := true
		for compression in session.gear_compressions(state):
			if compression > 1e-4:
				wheels_clear = false
		if wheels_clear and up > 0.10 and speed >= 8.0:
			airborne = true
			break
		if not session.crash.is_empty():
			break
	session.input_enabled = false
	return {airborne = airborne, speed = speed, up = up, fault = fault, crash = session.crash.duplicate(true)}


func _takeoff_at_rate(path: String, field: Dictionary, tick_rate: int) -> Dictionary:
	var saved_rate := Engine.physics_ticks_per_second
	Engine.physics_ticks_per_second = tick_rate
	var session: Node = Session.new()
	session.input_enabled = false
	session.setup(path, TIMBER_ID)
	root.add_child(session)
	var field_ok: bool = session.set_field(field)
	session.start_choice = Session.START_RUNWAY
	session.reset()
	var result := {airborne = false, speed = 0.0, up = 0.0, fault = session.sim.fault_reason,
		crash = session.crash.duplicate(true)}
	if field_ok and session.start_error.is_empty() and session.is_flyable():
		var launch: PackedFloat64Array = session.sim.state.duplicate()
		result = _takeoff(session, launch)
	session.free()
	Engine.physics_ticks_per_second = saved_rate
	return result


func _speed(state: PackedFloat64Array) -> float:
	return sqrt(state[RB.VEL] ** 2 + state[RB.VEL + 1] ** 2 + state[RB.VEL + 2] ** 2)


func _finish() -> void:
	print("TT-11 Timber ground: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
