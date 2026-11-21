# BL: passive full-angle fin loads and transactional depletion of the experimental blimp.
# Software checks at float64 precision; the estimated propulsion law is not a total-energy validation.
extends SceneTree

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Data := preload("res://physics/airship/airship_data.gd")
const Dynamics := preload("res://physics/airship/airship_dynamics.gd")
const EventStep := preload("res://physics/event_step.gd")
const Session := preload("res://sim/airship/session.gd")
const AirshipLog := preload("res://sim/airship/flight_log.gd")
const Sim := preload("res://sim/simulation.gd")

var _count := 0
var _failed := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failed += 1
	print("%s %s %s" % ["ok  " if ok else "FAIL", label, detail])


func _initialize() -> void:
	var loaded: Dictionary = Data.load_file("res://data/airships/rc-blimp-5m.json")
	if not loaded.ok:
		_check("stock data loads", false, str(loaded.errors))
		_finish()
		return
	var derived: Dictionary = Data.derive(loaded.data, 1.225, 9.80665, 0.0)
	if not derived.ok:
		_check("stock model derives", false, str(derived.errors))
		_finish()
		return
	_fin_properties(derived.model)
	_event_refinement()
	_actual_event_refinement(derived.model)
	_session_depletion()
	_finish()


func _finish() -> void:
	print("%d checks, %d failed" % [_count, _failed])
	quit(1 if _failed else 0)


func _fin_properties(model: Dictionary) -> void:
	var body := PackedFloat64Array([0.0, 0.0, -50.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	var c := PackedFloat64Array()
	c.resize(Data.CONTINUOUS_SIZE)
	c[Data.SOC] = 1.0
	c[Data.BATTERY_CONNECTED] = 1.0
	var zero_input := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
	var wind := PackedFloat64Array([0.0, 0.0, 0.0])
	var max_power := -INF
	var cases := 0
	for deflection in [-20.0, -10.0, 0.0, 10.0, 20.0]:
		for k in 3:
			c[Data.FIN + k] = deg_to_rad(deflection)
		for k in 72:
			var angle := TAU * float(k) / 72.0
			for rotating in [false, true]:
				body[3] = 3.0 * cos(angle)
				body[4] = 3.0 * sin(angle)
				body[5] = 0.25
				body[10] = 0.2 if rotating else 0.0
				body[11] = -0.3 if rotating else 0.0
				body[12] = 0.4 if rotating else 0.0
				var result: Dictionary = Dynamics.evaluate(model, body, c, zero_input, wind, Callable(), true)
				var v := body.slice(RB.VEL, RB.VEL + 3)
				var rates := body.slice(RB.RATE, RB.RATE + 3)
				for i in 3:
					var local: PackedFloat64Array = M.add(v, M.cross(rates, model.fins[i].centroid))
					var power: float = M.dot(local, result.info.fins[i].force)
					max_power = maxf(max_power, power)
					cases += 1
	_check("each fixed fin is passive across signed flow, held deflections and body rates", max_power <= 1e-10,
		"%d fin cases, maximum %.12f W" % [cases, max_power])

	# At small forward angle the old normal coefficient is retained to leading order.
	# At finite angle a chordwise force is intentionally added so lift does no work.
	for k in 3: c[Data.FIN + k] = 0.0
	body[10] = 0.0
	body[11] = 0.0
	body[12] = 0.0
	var fin: Dictionary = model.fins[0]
	var differences := PackedFloat64Array()
	for angle_deg in [3.0, 30.0]:
		var angle := deg_to_rad(angle_deg)
		body[3] = 3.0 * cos(angle)
		body[4] = -3.0 * sin(angle)
		body[5] = 0.0
		var result: Dictionary = Dynamics.evaluate(model, body, c, zero_input, wind, Callable(), true)
		var new_normal: float = M.dot(fin.normal, result.info.fins[0].force)
		var q_area: float = 0.5 * float(model.rho) * float(fin.area) * 9.0
		var sa := sin(angle)
		var ca := cos(angle)
		var old_normal: float = q_area * (float(fin.lift_slope) * sa * ca + float(fin.crossflow_drag) * sa * absf(sa)) \
			+ q_area * float(fin.drag) * sa
		differences.append((new_normal - old_normal) / old_normal)
	_check("forward small-angle fin normal slope and sign are retained", absf(differences[0]) < 0.002,
		"3-degree relative change %.8f; 30-degree change %.8f" % [differences[0], differences[1]])

	# Zero flow has zero force; both sides of pure crossflow and the reverse-axis seam converge.
	var samples: Array[PackedFloat64Array] = []
	for u in [-1e-8, 0.0, 1e-8]:
		body[3] = u
		body[4] = 1.0
		var result: Dictionary = Dynamics.evaluate(model, body, c, zero_input, wind, Callable(), true)
		samples.append(result.info.fins[0].force)
	var seam := maxf(M.norm(M.sub(samples[0], samples[1])), M.norm(M.sub(samples[2], samples[1])))
	body[3] = 0.0
	body[4] = 0.0
	var still: Dictionary = Dynamics.evaluate(model, body, c, zero_input, wind, Callable(), true)
	_check("fin force is continuous at pure crossflow and vanishes at zero speed",
		seam < 1e-7 and M.norm(still.info.fins[0].force) == 0.0, "crossflow difference %.12f N" % seam)
	var reverse_seam := 0.0
	for deflection in [-20.0, 0.0, 20.0]:
		c[Data.FIN] = deg_to_rad(deflection)
		body[3] = -3.0
		var forces: Array[PackedFloat64Array] = []
		for side in [-1e-8, 0.0, 1e-8]:
			body[4] = side
			var result: Dictionary = Dynamics.evaluate(model, body, c, zero_input, wind, Callable(), true)
			forces.append(result.info.fins[0].force)
		reverse_seam = maxf(reverse_seam, M.norm(M.sub(forces[0], forces[1])))
		reverse_seam = maxf(reverse_seam, M.norm(M.sub(forces[2], forces[1])))
	_check("neutral and deflected fins are continuous across the reverse-axis seam", reverse_seam < 1e-7,
		"difference %.12f N" % reverse_seam)


func _event_refinement() -> void:
	# Independent constant-current manufactured case: SOC crosses at 0.5 s exactly.
	# The latch remains connected throughout negative RK trials, then opens once.
	var last_error := INF
	var all_ok := true
	var event_total := 0
	for hz in [240, 480, 960]:
		var h := 1.0 / float(hz)
		var state := PackedFloat64Array()
		state.resize(RB.SIZE + Data.CONTINUOUS_SIZE)
		state[RB.ATT] = 1.0
		state[RB.SIZE + Data.SOC] = 0.25
		state[RB.SIZE + Data.BATTERY_CONNECTED] = 1.0
		var derivative := func(s: PackedFloat64Array, _time: float) -> PackedFloat64Array:
			var out := PackedFloat64Array()
			out.resize(s.size())
			out[RB.SIZE + Data.SOC] = -0.5 if s[RB.SIZE + Data.BATTERY_CONNECTED] == 1.0 else 0.0
			return out
		var transition := func(s: PackedFloat64Array, index: int) -> PackedFloat64Array:
			var out := s.duplicate()
			out[index] = 0.0
			out[RB.SIZE + Data.BATTERY_CONNECTED] = 0.0
			return out
		var located := -1.0
		var events := 0
		for tick in hz:
			var result: Dictionary = EventStep.advance(state, float(tick) * h, h, derivative, PackedFloat64Array(),
				RB.SIZE + Data.SOC, transition, "battery_depleted")
			if not result.ok:
				all_ok = false
				break
			state = result.state
			for event: Dictionary in result.events:
				located = float(event.time_s)
				events += 1
		last_error = absf(located - 0.5)
		event_total += events
		all_ok = all_ok and events == 1 and state[RB.SIZE + Data.SOC] == 0.0 \
			and state[RB.SIZE + Data.BATTERY_CONNECTED] == 0.0 and last_error < 1e-10
	_check("depletion time and exactly-once transition agree with the constant-current oracle at 240/480/960 Hz",
		all_ok and event_total == 3, "events %d, final time error %.12f s" % [event_total, last_error])
	var boundary_ok := true
	var h := 1.0 / 240.0
	for fraction in [0.0001, 0.9999]:
		var state := PackedFloat64Array()
		state.resize(RB.SIZE + Data.CONTINUOUS_SIZE)
		state[RB.ATT] = 1.0
		state[RB.SIZE + Data.SOC] = h * fraction
		state[RB.SIZE + Data.BATTERY_CONNECTED] = 1.0
		var derivative := func(s: PackedFloat64Array, _time: float) -> PackedFloat64Array:
			var out := PackedFloat64Array()
			out.resize(s.size())
			out[RB.SIZE + Data.SOC] = -1.0 if s[RB.SIZE + Data.BATTERY_CONNECTED] == 1.0 else 0.0
			return out
		var result: Dictionary = EventStep.advance(state, 0.0, h, derivative, PackedFloat64Array(),
			RB.SIZE + Data.SOC, Session._battery_depleted, "battery_depleted")
		boundary_ok = boundary_ok and result.ok and result.events.size() == 1 \
			and absf(float(result.events[0].time_s) - h * fraction) < 2e-12
	_check("depletion roots near both tick edges remain bounded and are emitted once", boundary_ok)


func _actual_event_refinement(base: Dictionary) -> void:
	# Actual blimp stage, equal physical initial state/inputs and horizon at three
	# isolated test step sizes; production's fixed 240 Hz clock is not changed.
	var model: Dictionary = base.duplicate(true)
	model.battery.capacity = 0.05
	model.battery.cutoff_cell = 3.2
	var input := PackedFloat64Array([0.0, 0.0, 0.0, 1.0])
	var wind := PackedFloat64Array([0.0, 0.0, 0.0])
	var derivative := func(s: PackedFloat64Array, _time: float) -> PackedFloat64Array:
		var stage: Dictionary = Dynamics.stage(model, s.slice(0, RB.SIZE), s.slice(RB.SIZE), input, wind, Callable())
		var out: PackedFloat64Array = stage.body_derivative.duplicate()
		out.append_array(stage.derivative)
		return out
	var times := PackedFloat64Array()
	var endings: Array[PackedFloat64Array] = []
	var valid := true
	for hz in [240, 480, 960]:
		var h := 1.0 / float(hz)
		var state := PackedFloat64Array()
		state.resize(RB.SIZE + Data.CONTINUOUS_SIZE)
		state[RB.POS + 2] = -50.0
		state[RB.ATT] = 1.0
		state[RB.SIZE + Data.MOTOR] = 0.25
		state[RB.SIZE + Data.MOTOR + 1] = 0.25
		state[RB.SIZE + Data.MOTOR + 2] = 0.1
		state[RB.SIZE + Data.SOC] = 0.00004
		state[RB.SIZE + Data.BATTERY_CONNECTED] = 1.0
		var event_count := 0
		var event_time := -1.0
		for tick in hz / 10:
			var result: Dictionary = EventStep.advance(state, float(tick) * h, h, derivative, PackedFloat64Array(),
				RB.SIZE + Data.SOC, Session._battery_depleted, "battery_depleted")
			if not result.ok:
				valid = false
				break
			state = result.state
			for event: Dictionary in result.events:
				event_count += 1
				event_time = float(event.time_s)
		valid = valid and event_count == 1 and state[RB.SIZE + Data.SOC] == 0.0 \
			and state[RB.SIZE + Data.BATTERY_CONNECTED] == 0.0
		times.append(event_time)
		endings.append(state)
	var coarse_error := absf(times[0] - times[2])
	var middle_error := absf(times[1] - times[2])
	var coarse_state := 0.0
	var middle_state := 0.0
	for i in endings[0].size():
		coarse_state = maxf(coarse_state, absf(endings[0][i] - endings[2][i]))
		middle_state = maxf(middle_state, absf(endings[1][i] - endings[2][i]))
	_check("actual bus/body/actuator crossing and post-event state converge under refinement", valid \
		and middle_error <= coarse_error + 1e-10 and coarse_error < 1e-5 \
		and middle_state <= coarse_state + 1e-10 and coarse_state < 1e-4,
		"time differences %s/%s s; state differences %s/%s" % [String.num_scientific(coarse_error),
			String.num_scientific(middle_error), String.num_scientific(coarse_state), String.num_scientific(middle_state)])


func _session_depletion() -> void:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/airships/rc-blimp-5m.json"))
	raw.battery.capacity.value = 0.05
	raw.battery.initial_soc.value = 0.05
	raw.battery.cutoff_cell_voltage.value = 3.2
	var session: Node = Session.new()
	root.add_child(session)
	if not session.prepare({}, {data = raw, altitude_m = 100.0}) or not session.resume():
		_check("admitted depletion fixture prepares", false, str(session.load_error))
		session.queue_free()
		return
	var input := PackedFloat64Array([0.0, 0.0, 0.0, 1.0])
	var ok := true
	while session.sim.continuous[Data.SOC] > 0.0018 and session.sim.tick < 5000:
		if not session.tick_once(input):
			ok = false
			break
	var before_body: PackedFloat64Array = session.state_snapshot()
	var before_cont: PackedFloat64Array = session.continuous_snapshot()
	var first_tick: int = session.sim.tick
	var recorder := AirshipLog.new(session)
	var path := "user://airship-depletion-%d.orfl" % Time.get_ticks_usec()
	var recording := recorder.start({}, path) == OK
	var reset_count := [0]
	var on_reset := func() -> void: reset_count[0] += 1
	session.resetting.connect(on_reset)
	var saved_tape: PackedByteArray = session.tape.to_byte_array()
	var saved_options: PackedByteArray = var_to_bytes(session.options)
	var refused: bool = not session.prepare({}, {heading_deg = NAN})
	_check("nonfinite start heading is refused before the running flight and recorder change", refused \
		and reset_count[0] == 0 and recorder.recording and session.sim.tick == first_tick \
		and session.state_snapshot().to_byte_array() == before_body.to_byte_array() \
		and session.continuous_snapshot().to_byte_array() == before_cont.to_byte_array() \
		and session.tape.to_byte_array() == saved_tape and var_to_bytes(session.options) == saved_options \
		and session.fault_reason.is_empty() and not session.paused)
	# A36 G2: prepare validates the exact release reset() installs on a detached kernel. A kernel refusal there is
	# reported before commit; the installed flight, tape, recorder and signals stay untouched.
	var kernel_probe: Node = Sim.new()
	var nan_body := PackedFloat64Array()
	nan_body.resize(RB.SIZE)
	nan_body.fill(NAN)
	var late: String = Session._probe_reset(kernel_probe, session.sim.model, session.model, session.environment,
		{body = nan_body, continuous = before_cont.duplicate()})
	kernel_probe.free()
	_check("a detached kernel refusal is reported without touching the installed flight", not late.is_empty()
		and reset_count[0] == 0 and recorder.recording and session.sim.tick == first_tick
		and session.state_snapshot().to_byte_array() == before_body.to_byte_array()
		and session.continuous_snapshot().to_byte_array() == before_cont.to_byte_array()
		and session.tape.to_byte_array() == saved_tape and session.fault_reason.is_empty(), late)
	var release: Dictionary = Session._release_state(session.options, session.model, session.environment, {})
	var accept_probe: Node = Sim.new()
	var accepted: String = Session._probe_reset(accept_probe, session.sim.model, session.model, session.environment, release)
	accept_probe.free()
	_check("prepare's release is exactly the installed start and the detached kernel accepts it", release.ok
		and accepted.is_empty() and release.body.to_byte_array() == session.start_state.to_byte_array()
		and release.continuous.to_byte_array() == session.start_continuous.to_byte_array(), accepted)
	var refused_out: bool = not session.prepare({}, {data_path = "res://data/airships/a36-missing.json", altitude_m = 100.0})
	_check("a missing data file is refused before the running flight changes", refused_out and reset_count[0] == 0
		and session.sim.tick == first_tick and session.tape.to_byte_array() == saved_tape and recorder.recording)
	session.resetting.disconnect(on_reset)
	var event_count := 0
	var event_offset := -1
	var event_time := -1.0
	var min_soc := INF
	var speed_at_cut := 0.0
	for i in 240:
		if not session.tick_once(input):
			ok = false
			break
		min_soc = minf(min_soc, session.sim.continuous[Data.SOC])
		for event: Dictionary in session.sim.last_events:
			if event.type == "battery_depleted":
				event_count += 1
				event_offset = i
				event_time = float(event.time_s) - float(first_tick) / 240.0
				speed_at_cut = session.sim.continuous[Data.MOTOR]
	var end_body: PackedFloat64Array = session.state_snapshot()
	var end_cont: PackedFloat64Array = session.continuous_snapshot()
	var info: Dictionary = session.telemetry_info()
	var stopped := recorder.stop() == OK
	var read: Dictionary = AirshipLog.inspect(path)
	var recorded_events: Array = []
	for event: Dictionary in read.get("events", []):
		if event.kind == "battery_depleted": recorded_events.append(event)
	var verified: Dictionary = AirshipLog.verify(path)
	_check("flight log records the depletion once with sub-tick time and verifies replay", recording and stopped \
		and read.ok and read.complete and recorded_events.size() == 1 and recorded_events[0].has("time_s") \
		and verified.get("ok", false) and verified.get("exact", false), str(verified.get("error", "")))
	var tampered: Dictionary = read.duplicate(true)
	tampered.events = tampered.events.filter(func(event: Dictionary) -> bool: return event.kind != "battery_depleted")
	var probe: Node = Session.new()
	var missing: Dictionary = AirshipLog._replay(probe, {}, tampered.header, tampered,
		{identity_match = false, exact = false, ok = false, first_mismatch_tick = -1, error = ""})
	probe.free()
	_check("replay rejects a missing depletion event", not missing.ok and str(missing.error).contains("depletion"))
	var old: Dictionary = read.duplicate(true)
	old.header.session.law = "airship-kirchhoff-6dof-v1"
	probe = Session.new()
	var old_result: Dictionary = AirshipLog._replay(probe, {}, old.header, old,
		{identity_match = false, exact = false, ok = false, first_mismatch_tick = -1, error = ""})
	probe.free()
	_check("old-law log identity is refused", not old_result.ok and not old_result.identity_match)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_check("actual accepted tick locates depletion once, holds SOC at zero and removes battery draw",
		ok and event_count == 1 and min_soc == 0.0 and end_cont[Data.SOC] == 0.0 \
		and end_cont[Data.BATTERY_CONNECTED] == 0.0 and info.battery.current_a == 0.0 and info.battery.power_w == 0.0,
		"event offset %d, SOC %.12f, current %.12f A" % [event_offset, end_cont[Data.SOC], info.battery.current_a])
	_check("an unpowered rotor coasts down from its accepted speed", speed_at_cut > 0.0 \
		and end_cont[Data.MOTOR] >= 0.0 and end_cont[Data.MOTOR] < speed_at_cut,
		"speed %.12f -> %.12f" % [speed_at_cut, end_cont[Data.MOTOR]])
	var restored: bool = session.restore_checkpoint(before_body, before_cont)
	var replay_events := 0
	var replay_time := -1.0
	for i in 240:
		if not session.tick_once(input):
			ok = false
			break
		for event: Dictionary in session.sim.last_events:
			if event.type == "battery_depleted":
				replay_events += 1
				replay_time = float(event.time_s)
	_check("checkpoint continuation replays the crossing and state exactly", restored and ok and replay_events == 1 \
		and absf(event_time - replay_time) < 1e-9 and session.state_snapshot().to_byte_array() == end_body.to_byte_array() \
		and session.continuous_snapshot().to_byte_array() == end_cont.to_byte_array(),
		"event time difference %.12f s" % absf(event_time - replay_time))
	var invalid := before_cont.duplicate()
	invalid[Data.SOC] = 0.0
	invalid[Data.BATTERY_CONNECTED] = 1.0
	var saved: PackedByteArray = session.state_snapshot().to_byte_array()
	var rejected: bool = not session.restore_checkpoint(before_body, invalid)
	_check("a zero-SOC connected checkpoint is refused without changing the flight", rejected \
		and session.state_snapshot().to_byte_array() == saved and session.fault_reason.is_empty())
	var empty: PackedFloat64Array = session.continuous_snapshot()
	var empty_body: PackedFloat64Array = session.state_snapshot()
	# Nonzero achieved positions distinguish a true hold from snapping to neutral.
	for i in 3:
		empty[Data.VECTOR + i] = deg_to_rad(20.0 + 10.0 * float(i))
		empty[Data.FIN + i] = deg_to_rad(-12.0 + 4.0 * float(i))
	var achieved: PackedByteArray = empty.slice(Data.VECTOR, Data.SOC).to_byte_array()
	var empty_restored: bool = session.restore_checkpoint(empty_body, empty)
	var duplicate_event := false
	for i in 3:
		if not session.tick_once(input): ok = false
		duplicate_event = duplicate_event or not session.sim.last_events.is_empty()
	_check("restoring an already depleted pack does not repeat the event", empty_restored and ok \
		and not duplicate_event and session.sim.continuous[Data.SOC] == 0.0)
	var changed_input := PackedFloat64Array([0.7, 0.8, -0.9, 1.0])
	for i in 30:
		if not session.tick_once(changed_input): ok = false
	var after_input: PackedByteArray = session.sim.continuous.slice(Data.VECTOR, Data.SOC).to_byte_array()
	_check("new commands cannot move unpowered vector and fin actuators", ok and achieved == after_input)

	# A deliberately refused event must restore the complete preceding physical
	# frame and publish no partial depletion event.
	var fault_session: Node = Session.new()
	root.add_child(fault_session)
	var fault_ready: bool = fault_session.prepare({}, {data = raw, altitude_m = 100.0})
	var near_cut := before_cont.duplicate()
	near_cut[Data.SOC] = 1e-8
	fault_ready = fault_ready and fault_session.restore_checkpoint(before_body, near_cut)
	var before_fault_body: PackedByteArray = fault_session.state_snapshot().to_byte_array()
	var before_fault_cont: PackedByteArray = fault_session.continuous_snapshot().to_byte_array()
	var published := [0]
	fault_session.sim.events_located.connect(func(_tick: int, events: Array[Dictionary]) -> void: published[0] += events.size())
	fault_session.sim.model.events[0].transition = func(_state: PackedFloat64Array, _index: int) -> PackedFloat64Array:
		return PackedFloat64Array()
	var fault_tick: bool = fault_session.tick_once(input)
	_check("a refused depletion transition rolls back the full tick and emits no event", fault_ready and not fault_tick \
		and not fault_session.fault_reason.is_empty() and fault_session.sim.tick == 0 and published[0] == 0 \
		and fault_session.state_snapshot().to_byte_array() == before_fault_body \
		and fault_session.continuous_snapshot().to_byte_array() == before_fault_cont)
	fault_session.queue_free()
	session.queue_free()
