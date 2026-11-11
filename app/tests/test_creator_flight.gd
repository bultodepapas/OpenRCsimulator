extends SceneTree
## AC-06: the compiled template candidate in the existing FlightSession. Headless, the project's 240 Hz
## tick, GDScript reference stage. The candidate enters only through
## FlightSession.setup("", aircraft_id, flight_data): no file, no catalog entry, no vehicle branch.
## These are software checks of an estimated package: bounds are stability and sanity limits, not
## handling validation. Measured values: docs/research/aircraft-creator/estimated-trainer-package.md.
## Run: godot --headless --path . --script res://tests/test_creator_flight.gd

const Definition := preload("res://workshop/creator/definition.gd")
const Compiler := preload("res://workshop/creator/compiler.gd")
const R := preload("res://workshop/creator/result.gd")
const Session := preload("res://sim/flight_session.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const Weather := preload("res://physics/wind_config.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")

const HANDS_OFF_S := 20.0
const RESPONSE_S := 0.25
const STICK_STEP := 0.3
const LAUNCH_S := 4.0
const MANOEUVRE_S := 4.0
const SPIRAL_STICK := 0.2
const SPIRAL_UPSET_S := 0.4
const SPIRAL_WAIT_S := 8.0

var checks := 0
var failures := 0


func check(label: String, ok: bool, detail: String = "") -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label, "  ", detail)


func _initialize() -> void:
	check("the project tick is 240 Hz", Engine.physics_ticks_per_second == 240)
	var compiled: Dictionary = Compiler.compile_candidate(Definition.template())
	check("template compiles", compiled.ok, str(R.texts(compiled)))
	if compiled.ok:
		var candidate: RefCounted = compiled.value
		_airborne(candidate)
		_control_signs(candidate)
		_hand_launch(candidate)
		_refinement(candidate)
		_spiral()
	print("AC-06 creator flight: %d checks, %d failed" % [checks, failures])
	quit(1 if failures > 0 else 0)


## A detached session flying the candidate's own loader result, as the Workshop's fixed-tape runs do.
func _session(candidate: RefCounted) -> Node:
	var session: Node = Session.new()
	session.physics_enabled = true
	session.input_enabled = false
	session.rate_profile = "full"
	session.crash_auto_restart = false
	session.start_choice = Session.START_AIRBORNE
	session.setup("", candidate.aircraft_id(), candidate.flight_data())
	return session


## [yaw, pitch, roll] in radians.
func _euler(s: PackedFloat64Array) -> PackedFloat64Array:
	return M.q_to_euler(M.quat(s[RB.ATT], s[RB.ATT + 1], s[RB.ATT + 2], s[RB.ATT + 3]))


func _airborne(candidate: RefCounted) -> void:
	var session: Node = _session(candidate)
	check("airborne start sets up and resets", session.aircraft.get("ok", false) and session.is_flyable()
		and str(session.start_error).is_empty() and session.sim.fault_reason.is_empty() and session.sim.tick == 0
		and not session.sim.paused, "%s / %s" % [session.start_error, session.sim.fault_reason])
	if not session.is_flyable():
		session.free()
		return
	var meta: Dictionary = session.trace_meta()
	check("the committed start is the trimmed airborne one", meta.launch_choice == "airborne" and meta.launch_kind == "trimmed_airborne"
		and meta.launch_error == "", str(meta))
	check("the candidate flies as itself on the reference stage", session.aircraft.model.id == candidate.aircraft_id()
		and session.aircraft.input_identity.sha256 == candidate.raw_sha256()
		and session.stage_backend_status().identity.get("backend") == "gdscript_reference")
	check("finite battery and coupled electric shaft", session.battery_is_dynamic() and session.shaft_is_coupled()
		and session.aircraft.model.landing_gear.is_empty())

	# Trim at the derived level speed: sane means a small elevator share, part throttle, attached flow.
	var trim: Dictionary = session.start
	var summary: Dictionary = candidate.summary()
	print("trim: V %.3f m/s, alpha %.3f deg, throttle %.4f, rpm %.0f, pitch %.4f, roll %.4f, yaw %.4f of travel" % [trim.V,
		rad_to_deg(trim.alpha), trim.throttle, trim.rpm, trim.pitch_command, trim.roll_command, trim.get("yaw_command", 0.0)])
	check("trim solves at the derived level speed", trim.ok and absf(float(trim.V) - float(summary.level_speed_mps)) < 1e-9)
	check("elevator trim within 35 % of travel", absf(trim.pitch_command) < 0.35, str(trim.pitch_command))
	check("trim throttle strictly between 0 and 1, part throttle", trim.throttle > 0.15 and trim.throttle < 0.7, str(trim.throttle))
	check("trim angle of attack attached and positive", trim.alpha > 0.0 and trim.alpha < deg_to_rad(8.0), str(rad_to_deg(trim.alpha)))
	check("roll and yaw trim only balance the propeller", absf(trim.roll_command) < 0.1 and absf(trim.get("yaw_command", 0.0)) < 0.1)

	# Hands off: the trimmed inputs held, no pilot.
	var start: PackedFloat64Array = session.sim.state.duplicate()
	var altitude: float = -start[RB.POS + 2]
	var speed_low := INF
	var speed_high := 0.0
	var lowest := altitude
	var highest := altitude
	var bank := 0.0
	var pitch_low := INF
	var pitch_high := -INF
	var finite := true
	var clear := true
	for tick: int in int(HANDS_OFF_S * 240.0):
		session.sim.step()
		var s: PackedFloat64Array = session.sim.state
		if not session.sim.fault_reason.is_empty() or not Session.Sim.state_is_valid(s):
			finite = false
			break
		clear = clear and not session.touches_ground(s)
		var speed: float = session.air_data(s).V
		var euler := _euler(s)
		speed_low = minf(speed_low, speed)
		speed_high = maxf(speed_high, speed)
		lowest = minf(lowest, -s[RB.POS + 2])
		highest = maxf(highest, -s[RB.POS + 2])
		bank = maxf(bank, absf(euler[2]))
		pitch_low = minf(pitch_low, euler[1])
		pitch_high = maxf(pitch_high, euler[1])
	print("hands-off %.0f s: airspeed %.3f..%.3f m/s, altitude %.3f..%.3f m from %.1f m, bank max %.3f deg, pitch %.3f..%.3f deg" % [
		HANDS_OFF_S, speed_low, speed_high, lowest, highest, altitude, rad_to_deg(bank), rad_to_deg(pitch_low), rad_to_deg(pitch_high)])
	check("hands-off flight stays finite for 20 s", finite and session.sim.tick == int(HANDS_OFF_S * 240.0), session.sim.fault_reason)
	check("hands-off airspeed stays within 1 m/s of trim", speed_low > trim.V - 1.0 and speed_high < trim.V + 1.0)
	check("hands-off altitude stays within 2 m", lowest > altitude - 2.0 and highest < altitude + 2.0 and clear)
	check("hands-off bank stays below 5 degrees", bank < deg_to_rad(5.0), str(rad_to_deg(bank)))
	check("hands-off pitch stays within 2 degrees of trim", pitch_low > trim.alpha - deg_to_rad(2.0) and pitch_high < trim.alpha + deg_to_rad(2.0))
	var electric: Dictionary = session.electrical_state()
	print("battery after %.0f s: %.1f C consumed, %.1f C left" % [HANDS_OFF_S, electric.get("consumed_charge_c", NAN), electric.get("remaining_charge_c", NAN)])
	check("the finite battery discharges", electric.get("ok", false) and electric.consumed_charge_c > 0.0
		and electric.remaining_charge_c < 3600.0 * 3.2 * 0.95 and not electric.exhausted)
	session.free()


## Pilot conventions (physics/control_surfaces.gd): positive roll raises the right aileron and rolls right,
## positive pitch raises the elevator and pitches up, positive yaw moves the rudder right and yaws right.
func _control_signs(candidate: RefCounted) -> void:
	var names := ["roll", "pitch", "yaw"]
	for axis: int in 3:
		for direction: float in [1.0, -1.0]:
			var session: Node = _session(candidate)
			if not session.is_flyable():
				check("%s response session starts" % names[axis], false, session.start_error)
				session.free()
				continue
			var inputs: PackedFloat64Array = session.sim.inputs.duplicate()
			inputs[axis] += direction * STICK_STEP
			for tick: int in int(RESPONSE_S * 240.0):
				session.sim.inputs = inputs
				session.sim.step()
			var rates: PackedFloat64Array = session.sim.state.slice(RB.RATE, RB.RATE + 3)
			var own: float = rates[axis]
			var others: float = 0.0
			for other: int in 3:
				if other != axis:
					others = maxf(others, absf(rates[other]))
			print("%s %+.1f for %.2f s: p %.4f, q %.4f, r %.4f rad/s" % [names[axis], direction * STICK_STEP, RESPONSE_S, rates[0], rates[1], rates[2]])
			check("%s stick %+.1f turns its own axis the same way" % [names[axis], direction * STICK_STEP],
				session.sim.fault_reason.is_empty() and own * direction > 0.1 and absf(own) < 3.0, str(rates))
			check("%s stick %+.1f mostly drives its own axis" % [names[axis], direction * STICK_STEP], others < absf(own))
			session.free()


## Hand launch from the runway edge at full throttle, hands off, as the gearless X8 is checked (X8-07).
func _hand_launch(candidate: RefCounted) -> void:
	var field: Dictionary = FieldLoader.load_from().field
	check("default field loads", not field.is_empty())
	var session: Node = Session.new()
	session.start_choice = Session.START_HAND_LAUNCH
	session.input_enabled = false
	session.crash_auto_restart = false
	session.setup("", candidate.aircraft_id(), candidate.flight_data())
	root.add_child(session)
	check("field and calm weather install", session.set_field(field) and session.setup_weather(Weather.defaults()), session.weather_error)
	session.reset()
	var meta: Dictionary = session.trace_meta()
	check("hand launch commits", session.is_flyable() and str(session.start_error).is_empty() and not session.sim.paused
		and session.sim.tick == 0 and meta.launch_choice == Session.START_HAND_LAUNCH and meta.launch_kind == "hand_launch_release",
		"%s %s" % [session.start_error, str(meta)])
	if not session.is_flyable() or not str(session.start_error).is_empty():
		print("hand launch refused: ", session.start_error)
		session.free()
		return
	check("released at full throttle, motor running", session.commands.throttle == Session.HAND_LAUNCH_THROTTLE and session.engine_running)
	var release: PackedFloat64Array = session.sim.state.duplicate()
	var ground: float = session.environment.terrain(release[RB.POS], release[RB.POS + 1])[0]
	var lowest := INF
	var slowest := INF
	var height := 0.0
	var bank := 0.0
	for tick: int in int(LAUNCH_S * 240.0):
		# The product tick order: the session's contact and crash gate, then the step.
		if not session._session_after_input():
			break
		session.sim.step()
		height = -session.sim.state[RB.POS + 2] - ground
		lowest = minf(lowest, height)
		slowest = minf(slowest, float(session.air_data(session.sim.state).V))
		bank = maxf(bank, absf(_euler(session.sim.state)[2]))
	print("hand launch, hands off %.0f s: lowest %.3f m, slowest %.3f m/s, height %.2f m, bank max %.1f deg, crash %s" % [LAUNCH_S,
		lowest, slowest, height, rad_to_deg(bank), str(session.crash)])
	check("hand launch flies on without a crash or fault", session.crash.is_empty() and session.sim.fault_reason.is_empty()
		and session.sim.tick == int(LAUNCH_S * 240.0), str(session.crash))
	check("hand launch does not sink more than 0.3 m below the release", lowest > Session.HAND_LAUNCH_RELEASE_HEIGHT_M - 0.3, str(lowest))
	check("hand launch climbs more than 5 m in 4 s", height > Session.HAND_LAUNCH_RELEASE_HEIGHT_M + 5.0, str(height))
	session.reset()
	check("a restart repeats the release exactly", session.sim.state == release and session.sim.tick == 0)
	session.free()


## The same open-loop manoeuvre (pitch, roll and yaw pulses defined in seconds) at 240, 480 and 960 Hz.
## Stick values are sampled once per tick and servos move at a finite rate, so the result converges at
## first order in the step; the checks bound the 240 Hz error and require the differences to shrink.
func _refinement(candidate: RefCounted) -> void:
	var saved: int = Engine.physics_ticks_per_second
	var finals := {}
	var speeds := {}
	for rate: int in [240, 480, 960]:
		Engine.physics_ticks_per_second = rate
		var session: Node = _session(candidate)
		if not session.is_flyable():
			check("refinement session starts at %d Hz" % rate, false, session.start_error)
			session.free()
			continue
		var trimmed: PackedFloat64Array = session.sim.inputs.duplicate()
		for tick: int in int(MANOEUVRE_S * rate):
			var time: float = float(tick) / float(rate)
			var inputs: PackedFloat64Array = trimmed.duplicate()
			if time >= 0.5 and time < 1.0:
				inputs[1] += STICK_STEP
			if time >= 1.5 and time < 2.0:
				inputs[0] += STICK_STEP
			if time >= 2.5 and time < 3.0:
				inputs[2] += STICK_STEP
			session.sim.inputs = inputs
			session.sim.step()
		check("manoeuvre completes at %d Hz" % rate, session.sim.fault_reason.is_empty() and session.sim.tick == int(MANOEUVRE_S * rate)
			and Session.Sim.state_is_valid(session.sim.state), session.sim.fault_reason)
		finals[rate] = session.sim.state.duplicate()
		speeds[rate] = float(session.air_data(session.sim.state).V)
		session.free()
	Engine.physics_ticks_per_second = saved
	if finals.size() != 3:
		return
	var coarse := _difference(finals[240], finals[480])
	var fine := _difference(finals[480], finals[960])
	print("refinement after %.0f s: 240 vs 480 Hz position %.5f m, attitude %.5f deg, airspeed %.5f m/s; 480 vs 960 Hz position %.5f m, attitude %.5f deg, airspeed %.5f m/s" % [
		MANOEUVRE_S, coarse[0], coarse[1], absf(speeds[240] - speeds[480]), fine[0], fine[1], absf(speeds[480] - speeds[960])])
	check("the manoeuvre moved the airplane", absf(_euler(finals[240])[2]) > deg_to_rad(5.0))
	check("240 Hz against 480 Hz: position within 0.02 m", coarse[0] < 0.02, str(coarse[0]))
	check("240 Hz against 480 Hz: attitude within 0.05 degrees", coarse[1] < 0.05, str(coarse[1]))
	check("240 Hz against 480 Hz: airspeed within 0.01 m/s", absf(speeds[240] - speeds[480]) < 0.01)
	check("differences shrink with the step", fine[0] < coarse[0] and fine[1] < coarse[1])


## Wing dihedral and the spiral mode (AC-12). The same small roll upset (right stick 0.2 for 0.4 s from
## the level trim), then hands off for 8 s, with a flat wing, the template's 5 degrees and the domain's
## 8 degrees. The linear analysis (research/aircraft-creator/ac12) gives spiral roots of +0.19, +0.06
## and -0.03 1/s: the flat wing's bank must grow several times, the template's less, and at 8 degrees
## it must not grow. Software check of the estimated package, not a handling validation.
func _spiral() -> void:
	var after_upset := {}
	var after_wait := {}
	for angle: float in [0.0, 5.0, 8.0]:
		var definition: Dictionary = Definition.template()
		definition["wing"]["dihedral_deg"] = angle
		var compiled: Dictionary = Compiler.compile_candidate(definition)
		check("dihedral %s deg compiles" % angle, compiled.ok, str(R.texts(compiled)))
		if not compiled.ok:
			return
		var session: Node = _session(compiled.value)
		if not session.is_flyable():
			check("spiral session starts at %s deg" % angle, false, session.start_error)
			session.free()
			return
		var trimmed: PackedFloat64Array = session.sim.inputs.duplicate()
		for tick: int in int((SPIRAL_UPSET_S + SPIRAL_WAIT_S) * 240.0):
			var inputs: PackedFloat64Array = trimmed.duplicate()
			if float(tick) / 240.0 < SPIRAL_UPSET_S:
				inputs[0] += SPIRAL_STICK
			session.sim.inputs = inputs
			session.sim.step()
			if tick + 1 == int(SPIRAL_UPSET_S * 240.0):
				after_upset[angle] = rad_to_deg(_euler(session.sim.state)[2])
		check("spiral flight stays valid at %s deg" % angle, session.sim.fault_reason.is_empty()
			and Session.Sim.state_is_valid(session.sim.state), session.sim.fault_reason)
		after_wait[angle] = rad_to_deg(_euler(session.sim.state)[2])
		session.free()
	print("roll upset, then hands off %.0f s: bank %.2f -> %.2f deg flat, %.2f -> %.2f deg at 5 deg dihedral, %.2f -> %.2f deg at 8 deg" % [
		SPIRAL_WAIT_S, after_upset[0.0], after_wait[0.0], after_upset[5.0], after_wait[5.0], after_upset[8.0], after_wait[8.0]])
	check("the upset banks every variant alike, 5 to 15 degrees to the right", after_upset[0.0] > 5.0 and after_upset[0.0] < 15.0
		and absf(after_upset[5.0] - after_upset[0.0]) < 1.0 and absf(after_upset[8.0] - after_upset[0.0]) < 1.0, str(after_upset))
	check("a flat wing lets the bank grow more than twice in 8 s", after_wait[0.0] > 2.0 * after_upset[0.0], str(after_wait[0.0]))
	check("more dihedral, less bank after the same upset", after_wait[0.0] > after_wait[5.0] + 5.0 and after_wait[5.0] > after_wait[8.0] + 2.0,
		str(after_wait))
	check("the template's bank grows less than half as much as the flat wing's",
		after_wait[5.0] - after_upset[5.0] < 0.5 * (after_wait[0.0] - after_upset[0.0]), str(after_wait))
	check("at 8 degrees the bank does not grow", after_wait[8.0] < after_upset[8.0] + 1.0 and after_wait[8.0] > 0.0, str(after_wait[8.0]))


## [position difference in m, largest Euler angle difference in degrees] between two states.
func _difference(a: PackedFloat64Array, b: PackedFloat64Array) -> PackedFloat64Array:
	var position: float = M.norm(M.v3(a[RB.POS] - b[RB.POS], a[RB.POS + 1] - b[RB.POS + 1], a[RB.POS + 2] - b[RB.POS + 2]))
	var first := _euler(a)
	var second := _euler(b)
	var angle := 0.0
	for axis: int in 3:
		angle = maxf(angle, absf(wrapf(first[axis] - second[axis], -PI, PI)))
	return PackedFloat64Array([position, rad_to_deg(angle)])
