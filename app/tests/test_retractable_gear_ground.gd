## AV-09 real-session regression for retractable tricycle gear and source-derived Vantage Jet contacts.
## The seven-input layout includes an explicit zero flap request in these gear-only scenarios.
## Run with the pinned Godot binary from the repository root:
##   godot --headless --path app --script res://tests/test_retractable_gear_ground.gd
extends SceneTree

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Ground := preload("res://physics/ground_contact.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const GroundStart := preload("res://physics/ground_start.gd")
const ImpactSnapshot := preload("res://physics/impact_snapshot.gd")
const WindConfig := preload("res://physics/wind_config.gd")
const FlightSession := preload("res://sim/flight_session.gd")

const AIRCRAFT_PATH := "res://data/aircraft/sebart_avanti_s_a200.json"
const AVANTI_ID := "sebart-avanti-s-a200-p100rx"
const G := 9.80665
const NOMINAL_SINK := 1.5
const CLEARANCE := 0.08

var _count := 0
var _failures := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	print(("ok   " if ok else "FAIL ") + label + ("" if detail.is_empty() else "  " + detail))
	if not ok:
		_failures += 1


func _session(tick_rate := 240, weather: Dictionary = {}) -> Dictionary:
	Engine.physics_ticks_per_second = tick_rate
	var session := FlightSession.new()
	if not weather.is_empty() and not session.setup_weather(weather):
		return {ok = false, session = session, message = session.weather_error}
	session.setup(AIRCRAFT_PATH)
	root.add_child(session)
	session.input_enabled = true
	if not session.aircraft.get("ok", false):
		return {ok = false, session = session, message = str(session.aircraft.get("errors", []))}
	var loaded := FieldLoader.load_from()
	if not loaded.ok:
		return {ok = false, session = session, message = str(loaded.errors)}
	var field: Dictionary = loaded.field
	if not session.set_field(field):
		return {ok = false, session = session, message = session.surface_error}
	var spot := GroundStart.threshold(field)
	if not spot.ok or not session.reset_on_runway(spot.north, spot.east, spot.heading):
		return {ok = false, session = session, message = str(spot)}
	return {ok = true, session = session, field = field, spot = spot}


func _engine_off(session: Node) -> void:
	session.engine_running = false
	var aux: PackedFloat64Array = session.sim.aux.duplicate()
	aux[0] = 0.0 # accepted turbine RPM mirror
	session.sim.aux = aux
	var continuous: PackedFloat64Array = session.sim.continuous.duplicate()
	if not continuous.is_empty():
		continuous[0] = 0.0
	session.sim.continuous = continuous
	session.sim.inputs = PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0])


func _set_rim_speed(session: Node, speed: float) -> void:
	var continuous: PackedFloat64Array = session.sim.continuous.duplicate()
	for index in session.wheel_count():
		continuous[session.wheel_index() + index] = speed
	session.sim.continuous = continuous


func _release_anchors(session: Node) -> void:
	var aux: PackedFloat64Array = session.sim.aux.duplicate()
	for index in session.anchor_count():
		aux[FlightSession.AUX_ANCHORS + index * Ground.ANCHOR_STRIDE + 2] = 0.0
	session.sim.aux = aux


func _speed(state: PackedFloat64Array) -> float:
	return sqrt(state[RB.VEL] ** 2 + state[RB.VEL + 1] ** 2 + state[RB.VEL + 2] ** 2)


func _yaw(state: PackedFloat64Array) -> float:
	return M.q_to_euler(M.quat(state[RB.ATT], state[RB.ATT + 1], state[RB.ATT + 2], state[RB.ATT + 3]))[0]


func _step(session: Node, seconds: float, inputs: PackedFloat64Array, on_tick: Callable = Callable()) -> Dictionary:
	var dt: float = session.sim.dt()
	var peak_compression := 0.0
	var start_position: PackedFloat64Array = session.sim.state.slice(RB.POS, RB.POS + 3)
	for _index in roundi(seconds / dt):
		session.sim.inputs = inputs.duplicate()
		session._physics_process(dt)
		if not session.crash.is_empty():
			break
		session.sim.step()
		if not session.sim.fault_reason.is_empty():
			break
		for compression: float in session.gear_compressions(session.sim.state):
			peak_compression = maxf(peak_compression, compression)
		if on_tick.is_valid():
			on_tick.call(session.sim.state)
	var state: PackedFloat64Array = session.sim.state.duplicate()
	var displacement := sqrt((state[RB.POS] - start_position[0]) ** 2 + (state[RB.POS + 1] - start_position[1]) ** 2)
	return {state = state, speed = _speed(state), displacement = displacement,
		peak_compression = peak_compression, crash = session.crash.duplicate(true), fault = session.sim.fault_reason}


func _roll_to_stop(session: Node, brake: float, max_seconds: float) -> Dictionary:
	var dt: float = session.sim.dt()
	var start: PackedFloat64Array = session.sim.state.slice(RB.POS, RB.POS + 2)
	var stopped := false
	var elapsed := 0.0
	for index in roundi(max_seconds / dt):
		session.sim.inputs = PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 1.0, brake, 0.0])
		session._physics_process(dt)
		if not session.crash.is_empty():
			break
		session.sim.step()
		if not session.sim.fault_reason.is_empty():
			break
		elapsed = float(index + 1) * dt
		if _speed(session.sim.state) < 0.05:
			stopped = true
			break
	var state: PackedFloat64Array = session.sim.state
	var distance := sqrt((state[RB.POS] - start[0]) ** 2 + (state[RB.POS + 1] - start[1]) ** 2)
	return {stopped = stopped, elapsed = elapsed, distance = distance, speed = _speed(state),
		crash = session.crash.duplicate(true), fault = session.sim.fault_reason}


func _landing_case(tick_rate: int, impact_sink: float) -> Dictionary:
	var created := _session(tick_rate)
	if not created.ok:
		created.session.queue_free()
		return {ok = false, message = created.message}
	var session: Node = created.session
	session.input_enabled = false
	_engine_off(session)
	var initial: PackedFloat64Array = session.sim.state.duplicate()
	var clearance := CLEARANCE
	var initial_sink := sqrt(maxf(0.0, impact_sink * impact_sink - 2.0 * G * clearance))
	var full_gear: Dictionary = session.current_landing_gear()
	var contacts: PackedFloat64Array = session.gear_compressions(initial)
	var greatest_penetration := 0.0
	for compression: float in contacts:
		greatest_penetration = maxf(greatest_penetration, compression)
	# Lift the solved static wheel plane by its measured compression plus a known gap; set the world-down
	# velocity so gravity over CLEARANCE gives the requested nominal/hard impact sink.
	initial[RB.POS + 2] -= greatest_penetration + clearance
	var world_velocity := M.q_rotate(M.q_conj(RB._att(initial)), M.v3(0.0, 0.0, initial_sink))
	for axis in 3:
		initial[RB.VEL + axis] = world_velocity[axis]
	session.sim.state = initial.duplicate()
	session.sim.previous = initial.duplicate()
	session.sim.set_paused(false)
	var dt: float = session.sim.dt()
	var peak := 0.0
	var first_touch_sink := 0.0
	var touched := false
	var trigger := ""
	var impact_time := -1.0
	for index in roundi(2.0 / dt):
		session._physics_process(dt)
		if not session.crash.is_empty():
			var impact: ImpactSnapshot.Snapshot = session.crash.get("impact")
			trigger = impact.trigger
			impact_time = float(index) * dt
			break
		session.sim.step()
		if not session.sim.fault_reason.is_empty():
			break
		var current_state: PackedFloat64Array = session.sim.state
		var compressions: PackedFloat64Array = session.gear_compressions(current_state)
		for compression: float in compressions:
			peak = maxf(peak, compression)
			if compression > 1.0e-5 and not touched:
				touched = true
				first_touch_sink = M.q_rotate(RB._att(current_state), RB._slice3(current_state, RB.VEL))[2]
	var result := {ok = session.sim.fault_reason.is_empty(), trigger = trigger, impact_time = impact_time,
		touched = touched, first_touch_sink = first_touch_sink, peak_compression = peak,
		state = session.sim.state.duplicate(), crash = session.crash.duplicate(true), fault = session.sim.fault_reason,
		gear = full_gear, tick_rate = tick_rate}
	session.queue_free()
	return result


func _initialize() -> void:
	var saved_tick := Engine.physics_ticks_per_second
	var airborne := FlightSession.new()
	airborne.setup(AIRCRAFT_PATH)
	root.add_child(airborne)
	airborne.input_enabled = true
	# The actuator timing check is independent of trim endurance; keep the aircraft well clear of the ground for the
	# two configured 2.5 s transitions.
	var high_state: PackedFloat64Array = airborne.sim.state.duplicate()
	high_state[RB.POS + 2] = -500.0
	airborne.sim.state = high_state.duplicate()
	airborne.sim.previous = high_state.duplicate()
	_check("file-backed Vantage Jet loads with an applied wheel profile and retractable gear",
		airborne.aircraft.get("ok", false) and airborne.aircraft.model.id == AVANTI_ID
		and airborne.aircraft.model.capabilities.gear == "retractable_tricycle"
		and airborne.aircraft.model.wheel_profile.status == "applied" and airborne.wheel_count() == 3,
		str(airborne.aircraft.get("errors", [])))
	var initial_gear: Dictionary = airborne.gear_state()
	_check("airborne start initializes gear fully stowed and produces no ground support",
		initial_gear.get("available", false) and initial_gear.extension == 0.0 and initial_gear.status == "up"
		and Ground.loads(airborne.sim.state, airborne.current_landing_gear()).is_empty())
	_check("gear can extend in flight", airborne.set_gear_down(true))
	airborne.sim.inputs = airborne._inputs()
	airborne.input_enabled = false
	var extension_time: float = airborne.aircraft.model.landing_gear.retraction.extension_time
	var actuator_throttle: float = float(airborne.start.get("throttle", 0.0))
	var extended := _step(airborne, extension_time, PackedFloat64Array([0.0, 0.0, 0.0, actuator_throttle, 1.0, 0.0, 0.0]))
	_check("extension reaches the exact downlock endpoint in its configured time",
		extended.fault.is_empty() and airborne.gear_state().extension == 1.0 and airborne.gear_state().status == "down",
		str(airborne.gear_state()))
	airborne.input_enabled = true
	var retract_requested: bool = airborne.set_gear_down(false)
	_check("gear can retract in flight", retract_requested)
	airborne.input_enabled = false
	airborne.sim.inputs = airborne._inputs()
	var retraction_time: float = airborne.aircraft.model.landing_gear.retraction.retraction_time
	var retracted := _step(airborne, retraction_time, PackedFloat64Array([0.0, 0.0, 0.0, actuator_throttle, 0.0, 0.0, 0.0]))
	_check("retraction returns to exact stowed endpoint without fault",
		retracted.fault.is_empty() and airborne.gear_state().extension == 0.0 and airborne.gear_state().status == "up",
		str(airborne.gear_state()))
	airborne.queue_free()

	var parked_setup := _session()
	_check("Vantage Jet qualifies for a real default-field runway start", parked_setup.ok, str(parked_setup.get("message", "")))
	if not parked_setup.ok:
		Engine.physics_ticks_per_second = saved_tick
		print("%d checks, %d failed" % [_count, _failures])
		quit(1)
		return
	var parked: Node = parked_setup.session
	var model: Dictionary = parked.aircraft.model
	var gear_state: Dictionary = parked.gear_state()
	_check("runway start deploys all three gear contacts", gear_state.extension == 1.0 and gear_state.status == "down"
		and parked.wheel_count() == 3)
	var start_state: PackedFloat64Array = parked.sim.state.duplicate()
	var start_compressions: PackedFloat64Array = parked.gear_compressions(start_state)
	var all_touching := start_compressions.size() == 3
	for compression: float in start_compressions:
		all_touching = all_touching and compression > 0.001
	_check("runway rest solves positive load-bearing compression on mains and nose", all_touching, str(start_compressions))
	_engine_off(parked)
	parked.input_enabled = false
	var rest := _step(parked, 2.0, PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0]))
	_check("engine-off runway rest stays level on all three wheels without drift or fault",
		rest.crash.is_empty() and rest.fault.is_empty() and rest.speed < 0.01 and rest.displacement < 0.002,
		"speed %.4f m/s, drift %.4f m, fault %s" % [rest.speed, rest.displacement, rest.fault])

	var crosswind: Dictionary = WindConfig.defaults()
	crosswind.speed_mps = 1.5
	crosswind.from_deg = 0.0
	var windy_setup := _session(240, crosswind)
	_check("Vantage Jet runway solver accepts a steady crosswind", windy_setup.ok, str(windy_setup.get("message", "")))
	if windy_setup.ok:
		var windy: Node = windy_setup.session
		windy.input_enabled = false
		var wind: PackedFloat64Array = windy.wind_at(0.0)
		var windy_rest := _step(windy, 2.0, PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0]))
		_check("crosswind runway rest remains stationary with matching gear-drag loads",
			M.norm(wind) >= 1.49 and windy_rest.crash.is_empty() and windy_rest.fault.is_empty()
			and windy_rest.speed < 0.01 and windy_rest.displacement < 0.002,
			"wind %s m/s, speed %.5f m/s, drift %.5f m, fault %s" %
			[str(wind), windy_rest.speed, windy_rest.displacement, windy_rest.fault])
		windy.queue_free()

	# Ground-side interlock: pilot gear-up requests are rejected while loaded; partial/up poses have no spring support,
	# even when the witness contacts are deliberately driven below the runway plane.
	parked.input_enabled = true
	var retract_on_wheels: bool = parked.set_gear_down(false)
	_check("retraction request is inhibited under wheel load", not retract_on_wheels and parked.gear_state().inhibited)
	var penetrating := start_state.duplicate()
	penetrating[RB.POS + 2] += 0.30
	for fraction in [0.0, 0.5]:
		var aux: PackedFloat64Array = parked.sim.aux.duplicate()
		var gear_index: int = parked.gear_aux_index()
		aux[gear_index] = fraction
		aux[gear_index + 1] = 0.0
		var unlocked: Dictionary = parked.current_landing_gear(aux)
		var geometric_compression := Ground.compressions(penetrating, unlocked)
		var force: PackedFloat64Array = Ground.loads(penetrating, unlocked, 0.0, parked.ground_surfaces)
		var penetrates := not geometric_compression.is_empty()
		for compression: float in geometric_compression:
			penetrates = penetrates and compression > 0.001
		var force_zero := true
		for value: float in force:
			force_zero = force_zero and absf(value) < 1.0e-12
		_check("extension %.1f has no ghost spring support when penetrated" % fraction,
			penetrates and force_zero and unlocked.contacts.size() == 3
			and unlocked.contacts[0].stiffness == 0.0 and unlocked.contacts[0].damping == 0.0
			and unlocked.contacts[0].max_compression == 0.0,
			"compression %s, load %s" % [str(geometric_compression), str(force)])

	# A real engine-on taxi run; the steering command is the existing rudder-to-nosewheel path.
	var taxi_setup := _session()
	_check("powered taxi session starts on the same default runway", taxi_setup.ok, str(taxi_setup.get("message", "")))
	if taxi_setup.ok:
		var taxi: Node = taxi_setup.session
		_release_anchors(taxi)
		var taxi_state: PackedFloat64Array = taxi.sim.state.duplicate()
		taxi_state[RB.VEL] = 0.5
		taxi.sim.state = taxi_state.duplicate()
		taxi.sim.previous = taxi_state.duplicate()
		_set_rim_speed(taxi, 0.5)
		taxi.input_enabled = false
		var before_yaw := _yaw(taxi_state)
		var taxi_result := _step(taxi, 2.5, PackedFloat64Array([0.0, 0.0, 0.45, 0.2, 1.0, 0.0, 0.0]))
		var yaw_change := wrapf(_yaw(taxi_result.state) - before_yaw, -PI, PI)
		var taxi_contacts: PackedFloat64Array = taxi.gear_compressions(taxi_result.state)
		var contact_count_ok := taxi_contacts.size() == 3
		for compression: float in taxi_contacts:
			contact_count_ok = contact_count_ok and compression > -0.005
		_check("powered taxi accelerates and right steering yaws right without contact loss or crash",
			taxi_result.crash.is_empty() and taxi_result.fault.is_empty() and taxi_result.speed > 0.7
			and taxi_result.displacement > 0.5 and yaw_change > 0.01 and contact_count_ok,
			"speed %.3f m/s, distance %.3f m, Δyaw %.3f rad, fault %s" %
			[taxi_result.speed, taxi_result.displacement, yaw_change, taxi_result.fault])
		taxi.queue_free()

	# Main-wheel brakes: compare identical engine-off 3 m/s starts with and without the optional brake command.
	var brake_speeds := PackedFloat64Array()
	for demand in [0.0, 1.0]:
		var brake_setup := _session()
		if not brake_setup.ok:
			_check("braking setup loads", false, str(brake_setup.message))
			continue
		var braking: Node = brake_setup.session
		_engine_off(braking)
		_release_anchors(braking)
		var moving: PackedFloat64Array = braking.sim.state.duplicate()
		moving[RB.VEL] = 3.0
		braking.sim.state = moving.duplicate()
		braking.sim.previous = moving.duplicate()
		_set_rim_speed(braking, 3.0)
		braking.input_enabled = true
		var accepted: bool = braking.set_wheel_brake(demand)
		braking.sim.inputs = braking._inputs()
		braking.input_enabled = false
		_check("wheel brake command %.1f is accepted" % demand, accepted)
		var braking_result := _step(braking, 0.5, PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 1.0, demand, 0.0]))
		brake_speeds.append(braking_result.speed)
		_check("brake run has no crash or numerical fault", braking_result.crash.is_empty() and braking_result.fault.is_empty(), braking_result.fault)
		braking.queue_free()
	if brake_speeds.size() == 2:
		_check("both main brakes measurably slow an otherwise identical 3 m/s roll",
			brake_speeds[1] < brake_speeds[0] - 0.08,
			"unbraked %.3f m/s, braked %.3f m/s" % [brake_speeds[0], brake_speeds[1]])
	var stop_results: Array[Dictionary] = []
	for demand in [0.0, 1.0]:
		var stop_setup := _session()
		if not stop_setup.ok:
			_check("stopping-distance setup loads", false, str(stop_setup.message))
			continue
		var rolling: Node = stop_setup.session
		_engine_off(rolling)
		_release_anchors(rolling)
		var rolling_state: PackedFloat64Array = rolling.sim.state.duplicate()
		rolling_state[RB.VEL] = 3.0
		rolling.sim.state = rolling_state.duplicate()
		rolling.sim.previous = rolling_state.duplicate()
		_set_rim_speed(rolling, 3.0)
		rolling.input_enabled = false
		stop_results.append(_roll_to_stop(rolling, demand, 12.0))
		rolling.queue_free()
	if stop_results.size() == 2:
		var free_roll: Dictionary = stop_results[0]
		var braked_roll: Dictionary = stop_results[1]
		var both_stopped: bool = free_roll.stopped and braked_roll.stopped
		_check("1 Nm main-wheel brakes shorten 3 m/s stopping distance and time",
			both_stopped and braked_roll.distance < free_roll.distance and braked_roll.elapsed < free_roll.elapsed
			and free_roll.crash.is_empty() and braked_roll.crash.is_empty()
			and free_roll.fault.is_empty() and braked_roll.fault.is_empty(),
			"free roll %.3f m/%.2f s; braked %.3f m/%.2f s" %
			[free_roll.distance, free_roll.elapsed, braked_roll.distance, braked_roll.elapsed])

	var nominal := _landing_case(240, NOMINAL_SINK)
	_check("nominal 1.5 m/s runway landing is accepted and settles without a gear-limit crash",
		nominal.get("ok", false) and nominal.get("touched", false) and nominal.get("crash", {}).is_empty()
		and nominal.get("fault", "").is_empty(),
		"touch %s at %.3f m/s, peak %.3f m, fault %s" %
		[str(nominal.get("touched", false)), nominal.get("first_touch_sink", 0.0), nominal.get("peak_compression", 0.0), nominal.get("fault", "")])
	var hard := _landing_case(240, 4.0)
	_check("hard landing collapses at the gear terminal-contact limit",
		hard.get("ok", false) and not hard.get("crash", {}).is_empty() and hard.get("trigger", "") == "gear_limit",
		"trigger %s at %.3f s; peak %.3f m, fault %s" %
		[hard.get("trigger", ""), hard.get("impact_time", -1.0), hard.get("peak_compression", 0.0), hard.get("fault", "")])
	var refined := _landing_case(480, NOMINAL_SINK)
	if nominal.get("ok", false) and refined.get("ok", false) and nominal.get("crash", {}).is_empty() and refined.get("crash", {}).is_empty():
		var ds: PackedFloat64Array = nominal.state
		var hs: PackedFloat64Array = refined.state
		var position_error := sqrt((ds[RB.POS] - hs[RB.POS]) ** 2 + (ds[RB.POS + 1] - hs[RB.POS + 1]) ** 2 + (ds[RB.POS + 2] - hs[RB.POS + 2]) ** 2)
		var velocity_error := sqrt((ds[RB.VEL] - hs[RB.VEL]) ** 2 + (ds[RB.VEL + 1] - hs[RB.VEL + 1]) ** 2 + (ds[RB.VEL + 2] - hs[RB.VEL + 2]) ** 2)
		_check("nominal landing converges at 240/480 Hz within 2 cm and 0.1 m/s",
			position_error < 0.02 and velocity_error < 0.1,
			"Δposition %.5f m, Δvelocity %.5f m/s" % [position_error, velocity_error])
	else:
		_check("nominal landing is valid at both 240/480 Hz", false, "240 Hz %s; 480 Hz %s" % [str(nominal), str(refined)])

	parked.queue_free()
	Engine.physics_ticks_per_second = saved_tick
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)
