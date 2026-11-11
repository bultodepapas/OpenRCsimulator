# DR-25/DR-26 RACE-09, RACE-10, RACE-11, RACE-13, RACE-14 (pause part) and RACE-15 on the shared kernel: the composed
# race model wraps the electrical controlled multirotor (tests/mr_fixtures.gd, synthetic numbers) and a small synthetic
# square course on flat ground. Free flight in IDLE is byte-identical to the bare plant; start refusals; the 720-tick
# drive-inhibited countdown; GO from the fresh pre-inhibit sample (granted, throttle/source refusals, kernel-refused GO
# tick); a scripted chord crossing of gate 0; a crash abort; checkpoint replay; course swap at restore; pause.
# Software evidence on estimated data; local practice rules; no federation compliance or timing claims beyond the
# declared chord-path envelope.
extends SceneTree

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Sim := preload("res://sim/simulation.gd")
const Fixtures := preload("res://tests/mr_fixtures.gd")
const Plant := preload("res://physics/multirotor/controlled_plant.gd")
const FC := preload("res://physics/multirotor/flight_controller.gd")
const Rates := preload("res://physics/multirotor/rates.gd")
const Track := preload("res://sim/race/track.gd")
const Director := preload("res://sim/race/race_director.gd")
const RaceModel := preload("res://sim/race/race_model.gd")

const PAD_NORTH := 0.0
const PAD_EAST := -6.0

var _count := 0
var _failures := 0
var _course: Dictionary


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
	print("%s %s %s" % ["ok  " if ok else "FAIL", label, detail])


func _initialize() -> void:
	_run.call_deferred()


static func _document(shift_g1_m: float = 0.0) -> Dictionary:
	return {format = Track.FORMAT, id = "synthetic-model-square", name = "Synthetic model square", field_id = "synthetic",
		ruleset = Track.RULESET, laps = 3, origin = "pilot", pad = {north_m = PAD_NORTH, east_m = PAD_EAST, heading_deg = 90.0},
		gates = [
			{id = "g0", north_m = 0.0, east_m = 0.0, center_height_m = 2.0, heading_deg = 90.0, width_m = 3.0, height_m = 2.0},
			{id = "g1", north_m = 10.0, east_m = 10.0 + shift_g1_m, center_height_m = 2.0, heading_deg = 0.0, width_m = 3.0, height_m = 2.0},
			{id = "g2", north_m = 20.0, east_m = 0.0, center_height_m = 2.0, heading_deg = 270.0, width_m = 3.0, height_m = 2.0},
			{id = "g3", north_m = 10.0, east_m = -10.0, center_height_m = 2.0, heading_deg = 180.0, width_m = 3.0, height_m = 2.0}]}


static func _field() -> Dictionary:
	return {id = "synthetic", pilot = {north = 0.0, east = 0.0, down = 0.0, eye_height = 1.7},
		surfaces = [{id = "flat", type = "rough", center_north = 0.0, center_east = 0.0, length_east_west = 1000.0,
			width_north_south = 1000.0}], objects = []}


func _prepare(shift_g1_m: float = 0.0) -> Dictionary:
	var flat := func(_n: float, _e: float) -> PackedFloat64Array: return PackedFloat64Array([0.0, 0.0, 0.0])
	var loaded: Dictionary = Track.load_document(_document(shift_g1_m), "model square")
	return Track.prepare(loaded.track, _field(), flat) if loaded.ok else {ok = false, errors = loaded.errors}


func _run() -> void:
	var started: int = Time.get_ticks_msec()
	var prepared: Dictionary = _prepare()
	_check("the synthetic model course prepares", prepared.ok, str(prepared.get("errors", "")))
	if not prepared.ok:
		quit(1)
		return
	_course = prepared.course
	_layout()
	_idle_parity()
	_start_refusals()
	_countdown_and_go()
	_scripted_crossing()
	_crash_in_race()
	_checkpoint_replay()
	_course_swap()
	_pause()
	print("    wall time %.1f s" % (float(Time.get_ticks_msec() - started) / 1000.0))
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)


## {ok, errors, sim, wrapper, plant, model} on a fresh kernel (not reset). The caller frees `sim`.
func _install(course: Dictionary) -> Dictionary:
	var data: Dictionary = Fixtures.electric()
	var created: Dictionary = Plant.create(data, Rates.default_profile(), FC.THROTTLE_ABSOLUTE)
	if not created.ok:
		return {ok = false, errors = created.errors}
	var wrapped: Dictionary = RaceModel.wrap(created.plant, course)
	if not wrapped.ok:
		return {ok = false, errors = wrapped.errors}
	var sim: Node = Sim.new()
	root.add_child(sim)
	var installed: bool = sim.set_model(wrapped.model)
	sim.mass = float(data.mass_kg)
	sim.inertia = data.inertia_kg_m2.duplicate()
	return {ok = installed, errors = PackedStringArray(), sim = sim, wrapper = wrapped.wrapper, plant = created.plant,
		model = wrapped.model}


func _body(north: float, east: float, altitude: float, velocity: PackedFloat64Array = M.v3(0.0, 0.0, 0.0)) -> PackedFloat64Array:
	return RB.make_state(M.v3(north, east, -altitude), velocity, M.q_identity(), M.v3(0.0, 0.0, 0.0))


func _pad_body() -> PackedFloat64Array:
	return _body(PAD_NORTH, PAD_EAST, 0.018)


## A RACING frame (GO at the reset clock zero) for scripted flights.
func _racing_frame(h: Dictionary, body: PackedFloat64Array) -> Dictionary:
	var frame: Dictionary = h.wrapper.initial_frame(body)
	frame.modes[RaceModel.MODE_PHASE] = Director.PHASE_RACING
	frame.modes[RaceModel.MODE_ATTEMPT] = 1
	return frame


func _reset(h: Dictionary, frame: Dictionary) -> String:
	return Fixtures.reset(h.sim, frame, h.wrapper.input(FC.neutral_input()))


func _step(h: Dictionary, pilot: PackedFloat64Array, action: int = Director.ACTION_NONE) -> Array:
	h.sim.inputs = h.wrapper.input(pilot, action)
	h.sim.step()
	return h.sim.last_events.duplicate(true)


func _types(events: Array) -> String:
	var names := PackedStringArray()
	for event: Dictionary in events:
		names.append(str(event.type))
	return ",".join(names)


func _frame_bytes(sim: Node) -> PackedByteArray:
	return var_to_bytes([sim.state, sim.continuous, sim.aux, sim.modes, sim.tick, sim.inputs])


func _max_shaft(sim: Node) -> float:
	return maxf(maxf(sim.continuous[0], sim.continuous[1]), maxf(sim.continuous[2], sim.continuous[3]))


func _layout() -> void:
	var h: Dictionary = _install(_course)
	var message: String = _reset(h, h.wrapper.initial_frame(_pad_body())) if h.ok else "install failed"
	var sim: Node = h.sim
	_check("the wrapped model validates, installs and resets through prepare/commit_prepared_reset_frame", h.ok and message.is_empty(),
		message + str(h.errors))
	_check("layout: ten inputs, aux 31 + 9, modes 8 + 10, the plant's eight continuous values", sim.model.input_size == 10
		and sim.model.aux_size == 40 and sim.model.modes_size == 18 and sim.model.continuous_size == 8
		and RaceModel.AUX_RACE + Director.AUX_SIZE == RaceModel.AUX_SIZE and RaceModel.MODES_RACE + Director.MODES_SIZE == RaceModel.MODES_SIZE)
	_check("layout identity is the plant layout plus the ruleset suffix; identity pins ruleset, course and path policy",
		sim.model.state_layout_identity == Plant.LAYOUT_ELECTRIC + "+openrc-local-race-v1"
		and sim.model.identity.race_ruleset == Track.RULESET and sim.model.identity.race_course == _course.identity
		and sim.model.identity.race_path_policy == Track.PATH_POLICY and sim.model.identity.law == Plant.LAW_ELECTRIC)
	var bad: Dictionary = h.wrapper.initial_frame(_pad_body())
	bad.modes[RaceModel.MODE_NEXT_GATE] = 4
	var refused: String = _reset(h, bad)
	var staged: Dictionary = h.wrapper.initial_frame(_pad_body())
	staged.modes[RaceModel.MODE_STAGED] = 1
	_check("RACE-01/03 a reset frame outside the race domains is refused (next gate beyond the course, staging residue)",
		not refused.is_empty() and not _reset(h, staged).is_empty())
	sim.free()


func _idle_parity() -> void:
	var bare: Dictionary = Fixtures.install(root, Fixtures.electric())
	var h: Dictionary = _install(_course)
	var a: String = Fixtures.reset(bare.sim, bare.plant.initial_frame(Fixtures.body(0.018)), FC.neutral_input())
	var b: String = _reset(h, h.wrapper.initial_frame(Fixtures.body(0.018)))
	var same: bool = a.is_empty() and b.is_empty()
	var first_difference := -1
	for tick in 480:
		var arm: int = 0 if tick < 2 else 1
		var throttle: float = 0.0 if tick < 60 else 0.6
		var pilot: PackedFloat64Array = Fixtures.pilot(0.05 * sin(0.02 * tick), 0.0, 0.0, throttle, arm)
		bare.sim.inputs = pilot
		bare.sim.step()
		var events: Array = _step(h, pilot)
		var equal: bool = bare.sim.state.to_byte_array() == h.sim.state.to_byte_array() \
			and bare.sim.continuous.to_byte_array() == h.sim.continuous.to_byte_array() \
			and bare.sim.aux.to_byte_array() == h.sim.aux.slice(0, RaceModel.PLANT_AUX_SIZE).to_byte_array() \
			and bare.sim.modes.to_byte_array() == h.sim.modes.slice(0, RaceModel.PLANT_MODES_SIZE).to_byte_array() \
			and var_to_bytes(bare.sim.last_events) == var_to_bytes(events)
		if not equal and first_difference < 0:
			first_difference = tick
		same = same and equal
	var suffix_untouched: bool = h.sim.aux.slice(RaceModel.AUX_RACE) == Director.empty_aux(float(_course.tag)) \
		and h.sim.modes.slice(RaceModel.MODES_RACE) == Director.empty_modes()
	_check("RACE-09 free flight in IDLE: the plant slices stay byte-identical to the bare plant over 480 ticks with arming and a climb",
		same and bare.sim.fault_reason.is_empty() and h.sim.fault_reason.is_empty() and -h.sim.state[RB.POS + 2] > 2.0 and suffix_untouched,
		"first difference %d height %.2f m %s" % [first_difference, -h.sim.state[RB.POS + 2], h.sim.fault_reason])
	bare.sim.free()
	h.sim.free()


func _start_refusals() -> void:
	var h: Dictionary = _install(_course)
	var sim: Node = h.sim
	var cases: Array = [
		["off the pad", h.wrapper.initial_frame(Fixtures.body(0.018)), Director.REASON_START_NOT_ON_PAD],
		["above the pad", h.wrapper.initial_frame(_body(PAD_NORTH, PAD_EAST, 1.0)), Director.REASON_START_NOT_ON_PAD],
		["while moving", h.wrapper.initial_frame(_body(PAD_NORTH, PAD_EAST, 0.018, M.v3(0.5, 0.0, 0.0))), Director.REASON_START_MOVING],
	]
	var terminal: Dictionary = h.wrapper.initial_frame(_pad_body())
	terminal.modes[FC.MODE_MOTOR] = FC.MOTOR_CRASHED
	terminal.modes[FC.MODE_ARM_BLOCK] = FC.BLOCK_TERMINAL
	terminal.continuous[Plant.C_CUT_LATCH] = 1.0
	cases.append(["after a crash", terminal, Director.REASON_START_TERMINAL])
	for item: Array in cases:
		var message: String = _reset(h, item[1])
		var events: Array = _step(h, Fixtures.pilot(0.0, 0.0, 0.0, 0.0, 0), Director.ACTION_START)
		_check("start request refused %s with reason code %d" % [item[0], item[2]], message.is_empty()
			and sim.modes[RaceModel.MODE_PHASE] == Director.PHASE_IDLE and sim.modes[RaceModel.MODE_REASON] == item[2]
			and sim.modes[RaceModel.MODE_ATTEMPT] == 0 and _types(events).ends_with("race_refused")
			and events[-1].reason_code == item[2], message + _types(events) + sim.fault_reason)
	sim.free()


## Reset on the pad, request the start, arm during the countdown and stop just before the GO sample.
func _to_go(h: Dictionary) -> Dictionary:
	var sim: Node = h.sim
	var message: String = _reset(h, h.wrapper.initial_frame(_pad_body()))
	var events: Array = _step(h, Fixtures.pilot(0.0, 0.0, 0.0, 0.0, 0), Director.ACTION_START)
	var countdown_started: bool = message.is_empty() and sim.modes[RaceModel.MODE_PHASE] == Director.PHASE_COUNTDOWN \
		and sim.modes[RaceModel.MODE_COUNTDOWN] == 1 and sim.modes[RaceModel.MODE_ATTEMPT] == 1 and _types(events) == "race_countdown"
	var shafts := 0.0
	var commands := 0.0
	var phases_ok := true
	for i in range(1, 720):
		_step(h, Fixtures.pilot(0.0, 0.0, 0.0, 0.0, 0 if i < 3 else 1))
		shafts = maxf(shafts, _max_shaft(sim))
		if sim.modes[FC.MODE_MOTOR] == FC.MOTOR_ARMED:
			commands = maxf(commands, sim.aux[FC.AUX_COMMAND])
		phases_ok = phases_ok and sim.modes[RaceModel.MODE_PHASE] == Director.PHASE_COUNTDOWN \
			and sim.modes[RaceModel.MODE_COUNTDOWN] == i + 1
	return {started = countdown_started, shafts = shafts, commands = commands, phases_ok = phases_ok}


func _countdown_and_go() -> void:
	var h: Dictionary = _install(_course)
	var sim: Node = h.sim
	var run: Dictionary = _to_go(h)
	_check("RACE-11 a start on the pad at rest begins the countdown in that sample", run.started)
	_check("RACE-11 the countdown runs exactly 720 accepted ticks with the arm switch cycled to ARMED",
		run.phases_ok and sim.tick == 720 and sim.modes[RaceModel.MODE_COUNTDOWN] == 720
		and sim.modes[FC.MODE_MOTOR] == FC.MOTOR_ARMED and sim.fault_reason.is_empty(), sim.fault_reason)
	_check("RACE-11 zero effective drive through the countdown while the sampled commands stay nonzero in aux",
		run.shafts == 0.0 and run.commands > 0.0, "shafts %s commands %.4f" % [String.num_scientific(run.shafts), run.commands])
	var checkpoint: Dictionary = sim.checkpoint()
	var before: PackedByteArray = _frame_bytes(sim)
	var t_go: float = sim.time()
	var events: Array = _step(h, Fixtures.pilot(0.0, 0.0, 0.0, 0.0, 1))
	_check("RACE-11 GO with low throttle and armed motors: RACING, race_go at the start of that tick, drive in the same interval",
		sim.modes[RaceModel.MODE_PHASE] == Director.PHASE_RACING and sim.aux[RaceModel.AUX_GO_TIME] == t_go
		and sim.aux[RaceModel.AUX_LAP_START] == t_go and _types(events) == "race_go" and events[0].time_s == t_go
		and _max_shaft(sim) > 0.0, "%s shaft %.3f" % [_types(events), _max_shaft(sim)])
	var state: Dictionary = h.wrapper.race_state({body = sim.state, continuous = sim.continuous, aux = sim.aux, modes = sim.modes},
		sim.time())
	_check("race_state decodes phase, next gate and elapsed lap time", state.phase == "RACING" and state.next_gate == 0
		and state.next_gate_id == "g0" and absf(state.elapsed_lap_s - (sim.time() - t_go)) < 1e-12 and state.attempt == 1)
	events = _step(h, Fixtures.pilot(0.0, 0.0, 0.0, 0.0, 1), Director.ACTION_CANCEL)
	_check("cancel during RACING aborts with the cancelled reason and one race_abort", sim.modes[RaceModel.MODE_PHASE] == Director.PHASE_ABORTED
		and sim.modes[RaceModel.MODE_REASON] == Director.REASON_CANCELLED and _types(events) == "race_abort")
	# High throttle at the GO sample.
	var restored: bool = sim.restore_checkpoint(checkpoint)
	sim.set_paused(false)
	events = _step(h, Fixtures.pilot(0.0, 0.0, 0.0, 0.6, 1))
	_check("RACE-11 GO with high throttle is refused: IDLE, reason, motor DISARMED without OFF evidence, no drive",
		restored and sim.modes[RaceModel.MODE_PHASE] == Director.PHASE_IDLE and sim.modes[RaceModel.MODE_REASON] == Director.REASON_GO_THROTTLE
		and sim.modes[FC.MODE_MOTOR] == FC.MOTOR_DISARMED and sim.modes[FC.MODE_OFF_OBSERVED] == 0 and _max_shaft(sim) == 0.0
		and _types(events) == "race_refused", "%s motor %d" % [_types(events), sim.modes[FC.MODE_MOTOR]])
	for _i in 30:
		_step(h, Fixtures.pilot(0.0, 0.0, 0.0, 0.0, 1))
	var held: bool = sim.modes[FC.MODE_MOTOR] == FC.MOTOR_DISARMED and _max_shaft(sim) == 0.0
	_step(h, Fixtures.pilot(0.0, 0.0, 0.0, 0.0, 0))
	_step(h, Fixtures.pilot(0.0, 0.0, 0.0, 0.0, 1))
	_check("RACE-11 a switch held high after the refusal does not rearm; a fresh OFF then ON at low throttle does",
		held and sim.modes[FC.MODE_MOTOR] == FC.MOTOR_ARMED)
	# Source not ready at the GO sample.
	sim.restore_checkpoint(checkpoint)
	sim.set_paused(false)
	var lost: PackedFloat64Array = Fixtures.pilot(0.0, 0.0, 0.0, 0.0, 1)
	lost[FC.IN_SOURCE_READY] = 0.0
	events = _step(h, lost)
	_check("RACE-11 GO with the source not ready is refused with its reason and no drive",
		sim.modes[RaceModel.MODE_PHASE] == Director.PHASE_IDLE and sim.modes[RaceModel.MODE_REASON] == Director.REASON_GO_SOURCE
		and sim.modes[FC.MODE_MOTOR] == FC.MOTOR_DISARMED and _max_shaft(sim) == 0.0)
	# A kernel-refused GO tick: a non-finite pilot frame.
	sim.restore_checkpoint(checkpoint)
	sim.set_paused(false)
	var nan_frame: PackedFloat64Array = Fixtures.pilot(0.0, 0.0, 0.0, 0.0, 1)
	nan_frame[FC.IN_ROLL] = NAN
	sim.inputs = h.wrapper.input(nan_frame)
	sim.step()
	sim.inputs = h.wrapper.input(Fixtures.pilot(0.0, 0.0, 0.0, 0.0, 1)) # the frame is compared without the rejected inputs
	var after_nan: PackedByteArray = _frame_bytes(sim)
	_check("RACE-11 a GO tick refused by the kernel (NaN pilot frame) commits neither GO nor countdown progress",
		not sim.fault_reason.is_empty() and after_nan == before and sim.modes[RaceModel.MODE_PHASE] == Director.PHASE_COUNTDOWN
		and sim.modes[RaceModel.MODE_COUNTDOWN] == 720, sim.fault_reason)
	sim.free()
	# A kernel-refused GO tick: the stage fails once drive is enabled (the first RACING sample).
	var failing: Dictionary = _install(_course)
	var original: Callable = failing.model.stage_sampled
	failing.model.stage_sampled = func(body: PackedFloat64Array, continuous: PackedFloat64Array, t: float, context: Dictionary) -> Variant:
		var result: Variant = original.call(body, continuous, t, context)
		if context.modes[RaceModel.MODE_PHASE] == Director.PHASE_RACING:
			return {loads = PackedFloat64Array([NAN, 0.0, 0.0, 0.0, 0.0, 0.0]), derivative = result.derivative,
				rotor_momentum = result.rotor_momentum}
		return result
	var fsim: Node = failing.sim
	var reset_message: String = _reset(failing, failing.wrapper.initial_frame(_pad_body()))
	var restored_failing: bool = fsim.restore_checkpoint(checkpoint)
	fsim.set_paused(false)
	var failing_before: PackedByteArray = _frame_bytes(fsim)
	fsim.inputs = failing.wrapper.input(Fixtures.pilot(0.0, 0.0, 0.0, 0.0, 1))
	fsim.step()
	_check("RACE-11 a GO tick whose stage fails commits neither GO, drive nor countdown progress (state bytes unchanged)",
		reset_message.is_empty() and restored_failing and not fsim.fault_reason.is_empty() and _frame_bytes(fsim) == failing_before
		and fsim.modes[RaceModel.MODE_PHASE] == Director.PHASE_COUNTDOWN and fsim.tick == 720 and fsim.last_events.is_empty(),
		fsim.fault_reason)
	fsim.free()


func _scripted_crossing() -> void:
	var h: Dictionary = _install(_course)
	var sim: Node = h.sim
	var message: String = _reset(h, _racing_frame(h, _body(0.0, -0.5, 2.0, M.v3(0.0, 20.0, 0.0))))
	var scored: Dictionary = {}
	var expected := NAN
	var t0 := 0.0
	var dt: float = sim.dt()
	for _i in 30:
		var p0: PackedFloat64Array = sim.state.slice(0, 3)
		var start: float = sim.time()
		var events: Array = _step(h, FC.neutral_input())
		var p1: PackedFloat64Array = sim.state.slice(0, 3)
		for event: Dictionary in events:
			if event.type == "race_gate":
				scored = event
				t0 = start
				expected = start + (-p0[1] / (p1[1] - p0[1])) * dt
		if not scored.is_empty():
			break
	_check("RACE-09/15 a scripted flight through gate 0 at 20 m/s scores it once, strictly inside the tick",
		message.is_empty() and not scored.is_empty() and scored.gate == 0 and scored.lap == 1 and scored.time_s > t0
		and scored.time_s < t0 + dt and sim.modes[RaceModel.MODE_NEXT_GATE] == 1 and sim.modes[RaceModel.MODE_GATES_TOTAL] == 1,
		message + str(scored))
	_check("the event time equals the independently computed chord crossing within 1e-9 s",
		not scored.is_empty() and absf(scored.time_s - expected) < 1e-9 and sim.aux[RaceModel.AUX_LAST_GATE_TIME] == scored.time_s,
		"%s s" % String.num_scientific(absf(float(scored.get("time_s", 0.0)) - expected)))
	message = _reset(h, _racing_frame(h, _body(0.0, 0.5, 2.0, M.v3(0.0, -20.0, 0.0))))
	var backwards: Array = []
	for _i in 30:
		backwards.append_array(_step(h, FC.neutral_input()))
	_check("RACE-12 flying gate 0 backwards does not score", message.is_empty() and backwards.is_empty() and sim.state[RB.POS + 1] < -1.0
		and sim.modes[RaceModel.MODE_NEXT_GATE] == 0 and sim.modes[RaceModel.MODE_UNRESOLVED] == 0, _types(backwards))
	sim.free()


func _crash_in_race() -> void:
	var h: Dictionary = _install(_course)
	var sim: Node = h.sim
	var frame: Dictionary = _racing_frame(h, _body(5.0, 5.0, 0.3, M.v3(0.0, 0.0, 14.0)))
	frame.aux[RaceModel.AUX_LAP_DURATION] = 12.5
	frame.modes[RaceModel.MODE_VALID_LAPS] = 1
	frame.modes[RaceModel.MODE_GATES_TOTAL] = 4
	var message: String = _reset(h, frame)
	var events: Array = []
	for _i in 60:
		events = _step(h, FC.neutral_input())
		if not events.is_empty() or not sim.fault_reason.is_empty():
			break
	_check("RACE-13 a crash during RACING aborts: crash then one race_abort in the tick's ordered list, slots retained",
		message.is_empty() and _types(events) == "crash,race_abort" and events[1].time_s == events[0].time_s
		and sim.modes[RaceModel.MODE_PHASE] == Director.PHASE_ABORTED and sim.modes[RaceModel.MODE_REASON] == Director.REASON_CRASH
		and sim.modes[RaceModel.MODE_VALID_LAPS] == 1 and sim.aux[RaceModel.AUX_LAP_DURATION] == 12.5,
		message + _types(events) + sim.fault_reason)
	var record: Dictionary = h.wrapper.result({body = sim.state, continuous = sim.continuous, aux = sim.aux, modes = sim.modes})
	_check("the terminal record projection keeps the completed lap, reason, course identity, ruleset and path envelope",
		record.terminal and not record.valid and record.phase == "ABORTED" and record.reason == "crash" and record.laps.size() == 1
		and record.laps[0].duration_s == 12.5 and record.course_identity == _course.identity and record.ruleset == Track.RULESET
		and record.path_policy == Track.PATH_POLICY and record.acceleration_envelope_mps2 == 250.0
		and var_to_bytes(record) == var_to_bytes(h.wrapper.result({body = sim.state, continuous = sim.continuous, aux = sim.aux,
			modes = sim.modes})))
	sim.free()


func _checkpoint_replay() -> void:
	var h: Dictionary = _install(_course)
	var sim: Node = h.sim
	_reset(h, _racing_frame(h, _body(0.0, -0.5, 2.0, M.v3(0.0, 20.0, 0.0))))
	for _i in 3:
		_step(h, FC.neutral_input())
	var snapshot: Dictionary = sim.checkpoint()
	var tapes: Array = []
	for run in 2:
		if run == 1:
			var restored: bool = sim.restore_checkpoint(snapshot)
			sim.set_paused(false)
			if not restored:
				tapes.append([])
				continue
		var tape: Array = []
		for i in 8:
			var events: Array = _step(h, Fixtures.pilot(0.1 * float(i % 3), -0.05, 0.0, 0.0, 0))
			tape.append([_frame_bytes(sim), events])
		tapes.append(tape)
	var scored := false
	for row: Array in tapes[0]:
		scored = scored or _types(row[1]).contains("race_gate")
	_check("RACE-15 checkpoint just before a gate crossing, continue, restore, replay: identical frames and event lists",
		not snapshot.is_empty() and scored and var_to_bytes(tapes[0]) == var_to_bytes(tapes[1]))
	sim.free()


func _course_swap() -> void:
	var moved: Dictionary = _prepare(1.0)
	var h: Dictionary = _install(_course)
	_reset(h, h.wrapper.initial_frame(_pad_body()))
	_step(h, Fixtures.pilot(0.0, 0.0, 0.0, 0.0, 0), Director.ACTION_START)
	var snapshot: Dictionary = h.sim.checkpoint()
	var other: Dictionary = _install(moved.course)
	_reset(other, other.wrapper.initial_frame(_pad_body()))
	var same: Dictionary = _install(_course)
	_reset(same, same.wrapper.initial_frame(_pad_body()))
	var layouts_equal: bool = other.model.state_layout_identity == h.model.state_layout_identity
	_check("RACE-03 a kernel whose model wraps another course (same layout identity) refuses the checkpoint; the same course accepts it",
		moved.ok and layouts_equal and other.model.identity.race_course != h.model.identity.race_course
		and not other.sim.can_restore_checkpoint(snapshot) and same.sim.can_restore_checkpoint(snapshot))
	var forged: Dictionary = snapshot.duplicate(true)
	forged.aux[RaceModel.AUX_COURSE_TAG] = float(moved.course.tag)
	_check("what protects it: the course tag in the race suffix, checked by the state validator (a forged tag passes, so the session envelope must still pin the course identity)",
		other.sim.can_restore_checkpoint(forged) and not same.sim.can_restore_checkpoint(forged))
	h.sim.free()
	other.sim.free()
	same.sim.free()


func _pause() -> void:
	var h: Dictionary = _install(_course)
	var sim: Node = h.sim
	_reset(h, h.wrapper.initial_frame(_pad_body()))
	_step(h, Fixtures.pilot(0.0, 0.0, 0.0, 0.0, 0), Director.ACTION_START)
	sim.inputs = h.wrapper.input(Fixtures.pilot(0.0, 0.0, 0.0, 0.0, 0))
	var before: PackedByteArray = _frame_bytes(sim)
	sim.set_paused(true)
	for _i in 10:
		sim._physics_process(1.0 / 240.0)
	var frozen: bool = _frame_bytes(sim) == before
	sim.set_paused(false)
	sim._physics_process(1.0 / 240.0)
	_check("RACE-14 pause is not stepping: no tick and no countdown progress while paused; resume continues by one tick",
		frozen and sim.tick == 2 and sim.modes[RaceModel.MODE_COUNTDOWN] == 2)
	sim.free()
