# Runs only against the disposable instrumented app prepared by measure.py.
extends "../e4a/run.gd"
const Perturb = preload("math_probe.gd")
const M = preload("res://physics/math3d.gd")
const Aero = preload("res://physics/aero.gd")
const Ground = preload("res://physics/ground_contact.gd")
const Propulsion = preload("res://physics/propulsion.gd")
var metrics: Dictionary = {}
var exact_samples: int = 0
var discrete_mismatches: Array = []


func measure(session: Node, expected: Dictionary) -> void:
	var actual: Dictionary = sample(session)
	if var_to_bytes(actual) == var_to_bytes(expected):
		exact_samples += 1
	for key: String in ["tick", "dt", "modes", "continuous", "inputs"]:
		if actual[key] != expected[key]:
			discrete_mismatches.append({tick = actual.tick, block = key})
	for key: String in ["state", "previous", "aux"]:
		for i: int in actual[key].size():
			if key == "aux" and i >= Session.AUX_ANCHORS and i < Session.AUX_ANCHORS + session.anchor_count() * 3 and (i - Session.AUX_ANCHORS) % 3 == 2:
				if actual[key][i] != expected[key][i]:
					discrete_mismatches.append({tick = actual.tick, block = "anchor_mode", index = i})
				continue
			var component: String = session.aux_component(i) if key == "aux" else ("position" if i < 3 else ("velocity" if i < 6 else ("attitude" if i < 10 else "rate")))
			var delta: float = absf(actual[key][i] - expected[key][i])
			var tolerance: float = Policy.COMPONENTS[component].absolute
			if not metrics.has(component):
				metrics[component] = {max_absolute = 0.0, max_ratio = 0.0, tolerance = tolerance, first_exceed_tick = -1, peak_tick = 0, block = key, index = i}
			var metric: Dictionary = metrics[component]
			if delta > metric.max_absolute:
				metric.merge({max_absolute = delta, max_ratio = delta / tolerance, peak_tick = actual.tick, block = key, index = i}, true)
			if delta > tolerance and metric.first_exceed_tick == -1:
				metric.first_exceed_tick = actual.tick


func bits(value: float) -> String:
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(8)
	bytes.encode_double(0, value)
	return bytes.hex_encode()


func run_probe(session: Node, path: String, direction: int) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {ok = false, error = "cannot read tape"}
	var value: Variant = file.get_var(false)
	file.close()
	if not valid_tape(value, session):
		return {ok = false, error = "invalid tape"}
	tape = value
	var field: Dictionary = Field.load_from(field_path)
	if not field.ok or tape.field_sha256 != FileAccess.get_sha256(field_path) or tape.aircraft_sha256 != FileAccess.get_sha256(session.aircraft_path):
		return {ok = false, error = "field/aircraft source mismatch"}
	if not session.set_field(field.field) or not session.restore_checkpoint(tape.initial):
		return {ok = false, error = "authentic restore refused"}
	var initial: Dictionary = compare(session, tape.samples[0])
	if not initial.ok or not initial.exact:
		return {ok = false, error = "initial sample not exact"}
	measure(session, tape.samples[0])
	# The two wrappers change only from this point. Derived model/fingerprint stays authentic.
	Perturb.direction = direction
	var math_check: Array = []
	for argument: float in [0.375, -0.375, 0.0]:
		math_check.append({builtin = bits(sin(argument)), wrapper = bits(M.sin_(argument))})
	for argument: float in [0.5, -0.5, 0.0]:
		math_check.append({builtin = bits(atan2(argument, 1.0)), wrapper = bits(M.atan2_(argument, 1.0))})
	var trajectory: HashingContext = HashingContext.new()
	trajectory.start(HashingContext.HASH_SHA256)
	var branches: Array = []
	var modes: Array = []
	var checkpoint_index: int = 1
	session.sim.set_paused(false)
	for tick: int in range(1, tape.ticks + 1):
		Aero.h7_branch_tape.clear()
		Ground.h7_branch_tape.clear()
		Propulsion.h7_branch_tape.clear()
		session.sim.inputs = tape.inputs[tick - 1].duplicate()
		session.sim.step()
		session._physics_process(session.sim.dt())
		if session.sim.tick != tick or not session.sim.fault_reason.is_empty() or not session.crash.is_empty() or session.sim.paused:
			return {ok = false, error = "replay tick/crash/fault/pause", tick = tick, fault = session.sim.fault_reason}
		trajectory.update(var_to_bytes(sample(session)))
		# Retain all selected decisions per tick (interned by the Python runner), not just a total count.
		branches.append([Aero.h7_branch_tape.duplicate(), Ground.h7_branch_tape.duplicate(), Propulsion.h7_branch_tape.duplicate()])
		var flags: Array = [session.sim.modes[0]]
		for wheel: int in session.anchor_count():
			flags.append(session.sim.aux[Session.AUX_ANCHORS + wheel * 3 + 2])
		modes.append(flags)
		if tick == tape.samples[checkpoint_index].tick:
			measure(session, tape.samples[checkpoint_index])
			checkpoint_index += 1
	Perturb.direction = 0
	return {ok = true, ticks = session.sim.tick, checkpoints = checkpoint_index, exact_samples = exact_samples,
		metrics = metrics, discrete_mismatches = discrete_mismatches, branches = branches, modes = modes,
		trajectory_sha256 = trajectory.finish().hex_encode(), math_check = math_check, direction = direction,
		tape_sha256 = FileAccess.get_sha256(path), policy = Policy.descriptor(), stamp = Policy.stamp()}


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 4 or args[3] not in ["-1", "0", "1"]:
		printerr("require TAPE FIELD REPORT DIRECTION(-1/0/1)")
		quit(2)
		return
	Engine.physics_ticks_per_second = 240
	field_path = args[1]
	var session: Node = Session.new()
	session.setup()
	root.add_child(session)
	var result: Dictionary = run_probe(session, args[0], int(args[3]))
	session.free()
	var output: FileAccess = FileAccess.open(args[2], FileAccess.WRITE)
	if output == null:
		printerr("cannot write result")
		quit(2)
		return
	output.store_string(JSON.stringify(result, "", true, true) + "\n")
	output.close()
	print("E4b completed: ", result.ok)
	quit(0 if result.ok else 1)
