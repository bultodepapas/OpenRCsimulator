# E4a offline circuit tape. Uses downstream applied inputs, never reruns the feedback pilot on replay.
extends SceneTree
const Session = preload("res://sim/flight_session.gd")
const Field = preload("res://data/field_loader.gd")
const Policy = preload("res://tests/replay_policy.gd")
const FORMAT: String = "openrc-circuit-tape v1"
const EVERY: int = 60
var tape: Dictionary = {}
var field_path: String = "res://data/fields/default.json"


func sample(session: Node) -> Dictionary:
	return {tick = session.sim.tick, dt = session.sim.dt(), state = session.sim.state.duplicate(),
		previous = session.sim.previous.duplicate(), aux = session.sim.aux.duplicate(),
		modes = session.sim.modes.duplicate(), continuous = session.sim.continuous.duplicate(),
		inputs = session.sim.inputs.duplicate(), loads = session.sim.last_loads.duplicate()}


func capture(tick: int, _time: float, _state: PackedFloat64Array, _loads: PackedFloat64Array,
		inputs: PackedFloat64Array, _aux: PackedFloat64Array, session: Node) -> void:
	if tick == 0:
		# reset_on_runway performs two resets; only the last is the start of the circuit.
		tape.initial = session.checkpoint()
		tape.inputs = []
		tape.samples = [sample(session)]
	else:
		tape.inputs.append(inputs.duplicate())
		if tick % EVERY == 0:
			tape.samples.append(sample(session))


func record(session: Node, field: Dictionary, path: String) -> Dictionary:
	var parent: String = get_script().resource_path.get_base_dir().get_base_dir()
	var driver: Script = load(parent.path_join("e3c2a/circuit_driver.gd"))
	var pilot: Script = load(parent.path_join("e3c2a/circuit_pilot.gd"))
	tape = {format = FORMAT, hz = 240, policy = Policy.descriptor(), stamp = Policy.stamp(),
		field_sha256 = FileAccess.get_sha256(field_path),
		aircraft_sha256 = FileAccess.get_sha256(session.aircraft_path)}
	var callback: Callable = capture.bind(session)
	session.sim.stepped.connect(callback)
	var flight: Dictionary = driver.fly(session, field, pilot, true)
	session.sim.stepped.disconnect(callback)
	if not flight.get("completed", false) or flight.crash or not flight.fault.is_empty() \
			or not flight.continuity_ok or not flight.commands_finite_bounded or flight.wash_enabled \
			or flight.max_contact_sink_mps > 1.0 or flight.landing_margin_m < 0.5 \
			or flight.stop_dwell_s < 5.0 or absf(flight.turn_rad) < 5.8:
		return {ok = false, error = "source circuit did not meet bounded E3c2a conditions", flight = flight}
	if int(tape.samples[-1].tick) != session.sim.tick:
		tape.samples.append(sample(session))
	tape.ticks = session.sim.tick
	tape.flight = flight
	if not valid_tape(tape, session):
		return {ok = false, error = "recorded tape failed its shape/completion contract"}
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null or not file.store_var(tape, false):
		return {ok = false, error = "cannot write tape"}
	file.close()
	return {ok = true, ticks = tape.ticks, checkpoints = tape.samples.size(), duration_s = flight.duration_s,
		turn_rad = flight.turn_rad, touchdown_sink_mps = flight.max_contact_sink_mps,
		landing_margin_m = flight.landing_margin_m, stop_dwell_s = flight.stop_dwell_s,
		tape_sha256 = FileAccess.get_sha256(path), stamp = tape.stamp}


func finite_array(value: Variant, size: int) -> bool:
	if not value is PackedFloat64Array or value.size() != size:
		return false
	for number: float in value:
		if not is_finite(number):
			return false
	return true


func valid_tape(value: Variant, session: Node) -> bool:
	if not value is Dictionary or not value.has_all(["format", "hz", "ticks", "initial", "inputs", "samples", "field_sha256", "aircraft_sha256", "flight", "policy", "stamp"]):
		return false
	if value.format != FORMAT or value.hz != 240 or typeof(value.ticks) != TYPE_INT or value.ticks < 1 or value.ticks > 57600:
		return false
	if not value.policy is Dictionary or value.policy != Policy.descriptor() or not value.stamp is Dictionary \
			or not value.stamp.has_all(["os", "architecture", "cpu", "godot", "build", "ticks_per_second"]):
		return false
	for key: String in ["os", "architecture", "cpu"]:
		if not value.stamp[key] is String or value.stamp[key].is_empty():
			return false
	if not value.stamp.godot is Dictionary or not value.stamp.build is Dictionary \
			or value.stamp.ticks_per_second != 240 or value.stamp.godot.get("string", "") != Engine.get_version_info().string:
		return false
	if not value.initial is Dictionary or not value.initial.get("simulation", null) is Dictionary \
			or value.initial.simulation.get("tick", -1) != 0 or not value.flight is Dictionary \
			or value.flight.get("completed", false) != true or value.flight.get("tick_count", -1) != value.ticks:
		return false
	if not value.inputs is Array or value.inputs.size() != value.ticks or not value.samples is Array:
		return false
	for command: Variant in value.inputs:
		if not finite_array(command, 4):
			return false
		for i: int in 4:
			if command[i] > 1.0 or command[i] < (0.0 if i == 3 else -1.0):
				return false
	var expected_ticks: Array = range(0, value.ticks + 1, EVERY)
	if expected_ticks[-1] != value.ticks:
		expected_ticks.append(value.ticks)
	if value.samples.size() != expected_ticks.size():
		return false
	for index: int in value.samples.size():
		var cp: Variant = value.samples[index]
		if not cp is Dictionary or not cp.has_all(["tick", "dt", "state", "previous", "aux", "modes", "continuous", "inputs", "loads"]):
			return false
		if typeof(cp.tick) != TYPE_INT or cp.tick != expected_ticks[index] or cp.dt != 1.0 / 240.0:
			return false
		if not finite_array(cp.state, 13) or not finite_array(cp.previous, 13) \
				or not finite_array(cp.aux, session.sim.aux.size()) or not finite_array(cp.inputs, 4) \
				or not finite_array(cp.loads, 6) or not finite_array(cp.continuous, 0) \
				or not cp.modes is PackedInt64Array or cp.modes.size() != 1 or cp.modes[0] != 1:
			return false
		if cp.tick > 0 and cp.inputs != value.inputs[cp.tick - 1]:
			return false
		for wheel: int in session.anchor_count():
			var flag: float = cp.aux[Session.AUX_ANCHORS + wheel * 3 + 2]
			if flag != 0.0 and flag != 1.0:
				return false
	return true


func compare(session: Node, cp: Dictionary) -> Dictionary:
	var actual: Dictionary = sample(session)
	var exact: bool = var_to_bytes(actual) == var_to_bytes(cp)
	if actual.tick != cp.tick or actual.dt != cp.dt or actual.modes != cp.modes \
			or actual.continuous != cp.continuous or actual.inputs != cp.inputs:
		return {ok = false, error = "clock/mode/layout/input mismatch", tick = actual.tick}
	for key: String in ["state", "previous", "aux"]:
		for i: int in actual[key].size():
			if key == "aux" and i >= Session.AUX_ANCHORS and i < Session.AUX_ANCHORS + session.anchor_count() * 3 \
					and (i - Session.AUX_ANCHORS) % 3 == 2 and actual[key][i] != cp[key][i]:
				return {ok = false, error = "anchor mode mismatch", tick = actual.tick, index = i}
			var component: String = session.aux_component(i) if key == "aux" else \
				("position" if i < 3 else ("velocity" if i < 6 else ("attitude" if i < 10 else "rate")))
			if not Policy.accepted(component, actual[key][i], cp[key][i]):
				return {ok = false, error = "H9 tolerance exceeded", tick = actual.tick, block = key,
					index = i, component = component, actual = actual[key][i], expected = cp[key][i],
					absolute_error = absf(actual[key][i] - cp[key][i]), tolerance = Policy.COMPONENTS[component].absolute}
	return {ok = true, exact = exact}


func replay(session: Node, field: Dictionary, path: String, mutation: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {ok = false, error = "cannot open tape"}
	var value: Variant = file.get_var(false)
	file.close()
	if not valid_tape(value, session):
		return {ok = false, error = "invalid tape"}
	tape = value
	if tape.field_sha256 != FileAccess.get_sha256(field_path) \
			or tape.aircraft_sha256 != FileAccess.get_sha256(session.aircraft_path):
		return {ok = false, error = "aircraft/field source identity mismatch"}
	if not session.set_field(field) or not session.restore_checkpoint(tape.initial):
		return {ok = false, error = "initial checkpoint refused"}
	session.sim.set_paused(false)
	var first: Dictionary = compare(session, tape.samples[0])
	if not first.ok:
		return first
	# Deliberate sensitivity probes begin only AFTER authentic baseline restoration.
	# No saved fingerprint, source file, or recorded command is modified.
	var gear: Dictionary = session.aircraft.model.landing_gear
	if mutation == "rolling":
		gear.rolling_resistance *= 1.1
	elif mutation == "anchor":
		for contact: Dictionary in gear.contacts:
			contact.anchor_stiffness *= 2.0
	var checkpoint_index: int = 1
	var exact: bool = first.exact
	for tick: int in range(1, tape.ticks + 1):
		session.sim.inputs = tape.inputs[tick - 1].duplicate()
		session.sim.step()
		session._physics_process(session.sim.dt())
		if session.sim.tick != tick or not session.sim.fault_reason.is_empty() or not session.crash.is_empty() or session.sim.paused:
			return {ok = false, error = "replay tick/crash/fault/pause", tick = tick, fault = session.sim.fault_reason}
		if tick == tape.samples[checkpoint_index].tick:
			var comparison: Dictionary = compare(session, tape.samples[checkpoint_index])
			if not comparison.ok:
				return comparison
			exact = exact and comparison.exact
			checkpoint_index += 1
	return {ok = true, ticks = session.sim.tick, checkpoints = checkpoint_index, bit_exact = exact,
		tape_sha256 = FileAccess.get_sha256(path), mutation = mutation, stamp = Policy.stamp()}


func _initialize() -> void:
	var path: String = ""
	var report_path: String = ""
	var mode: String = ""
	var mutation: String = "none"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--record=") and mode.is_empty():
			mode = "record"
			path = arg.trim_prefix("--record=")
		elif arg.begins_with("--replay=") and mode.is_empty():
			mode = "replay"
			path = arg.trim_prefix("--replay=")
		elif arg.begins_with("--report="):
			report_path = arg.trim_prefix("--report=")
		elif arg.begins_with("--field="):
			field_path = arg.trim_prefix("--field=")
		elif arg.begins_with("--mutation="):
			mutation = arg.trim_prefix("--mutation=")
		else:
			printerr("unknown or repeated mode argument: ", arg)
			quit(2)
			return
	if path.is_empty() or report_path.is_empty() or mutation not in ["none", "rolling", "anchor"] or (mode == "record" and mutation != "none"):
		printerr("require --record=PATH or --replay=PATH, --report=PATH; replay-only --mutation=rolling|anchor")
		quit(2)
		return
	Engine.physics_ticks_per_second = 240
	var session: Node = Session.new()
	session.setup()
	root.add_child(session)
	var field: Dictionary = Field.load_from(field_path)
	var result: Dictionary = {ok = false, error = "field unavailable"}
	if field.ok:
		result = record(session, field.field, path) if mode == "record" else replay(session, field.field, path, mutation)
	session.free()
	var output: FileAccess = FileAccess.open(report_path, FileAccess.WRITE)
	if output == null:
		printerr("cannot open report")
		quit(2)
		return
	output.store_string(JSON.stringify(result, "\t", true, true) + "\n")
	output.close()
	print(JSON.stringify(result))
	quit(0 if result.ok else 1)
