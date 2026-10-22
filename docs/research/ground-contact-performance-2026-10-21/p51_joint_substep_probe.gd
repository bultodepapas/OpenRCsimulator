extends SceneTree

const Flight := preload("res://sim/flight_session.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const LakeLoader := preload("res://data/lake_loader.gd")
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const P51 := "res://data/aircraft/p51d_mustang_120.json"

var _errors: int = 0


func _initialize() -> void:
	_run()


func _run() -> void:
	var output: Dictionary = {}
	for name: String in ["full_tank", "rpm_boundary", "source_cut", "near_exhaustion", "changing_controls", "runway", "lake_bed"]:
		var result: Dictionary = _scenario(name)
		output[name] = result
		print("SCENARIO ", name, " ticks=", result.get("final_tick", -1), " substeps=", result.get("counts", []),
			" events=", _event_summary(result), " fault=", result.get("fault", result.get("reason", "")))
		if not bool(result.get("ok", false)):
			_errors += 1
	var path: String = _argument("--out=")
	if path.is_empty():
		printerr("Missing -- --out=<path>")
		quit(2)
		return
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		printerr("Cannot open output: " + path)
		quit(2)
		return
	file.store_buffer(var_to_bytes(output))
	file.close()
	var bench: Dictionary = _benchmark()
	print("SUBSTEP_PROBE ", {errors = _errors, bytes = FileAccess.get_file_as_bytes(path).size(), benchmark = bench})
	quit(1 if _errors > 0 else 0)


func _scenario(name: String) -> Dictionary:
	var flight: Node = _new_flight()
	if flight == null or not flight.is_flyable() or not flight.sim.fault_reason.is_empty():
		return {ok = false, reason = "flight setup failed", fault = "" if flight == null else flight.sim.fault_reason}
	if name == "runway":
		flight.start_choice = Flight.START_RUNWAY
		flight.reset()
	if name == "lake_bed":
		var loaded: Dictionary = LakeLoader.load_from("res://data/fields/lake.json")
		if not loaded.get("ok", false) or not flight.set_lake_context(loaded.lake):
			return {ok = false, reason = "lake setup failed"}
		flight.reset()
	var sim: Node = flight.sim
	var counts: Array[int] = []
	var context_counts: Array[int] = []
	_install_substep_recorder(flight, counts, context_counts, true)
	if name == "rpm_boundary":
		flight.engine_running = false
		var continuous: PackedFloat64Array = sim.continuous.duplicate()
		continuous[flight._rotor_index()] = 1.0001
		continuous[flight._liquid_index() + 1] = 0.0
		sim.continuous = continuous
		var aux: PackedFloat64Array = sim.aux.duplicate()
		aux[flight.AUX_RPM] = 1.0001
		sim.aux = aux
		if not sim.reset(sim.state):
			return {ok = false, reason = "RPM boundary reset failed", fault = sim.fault_reason}
	if name == "near_exhaustion":
		flight.engine_running = true
		var continuous: PackedFloat64Array = sim.continuous.duplicate()
		continuous[flight._liquid_index()] = 0.000001
		continuous[flight._liquid_index() + 1] = 1.0
		sim.continuous = continuous
		sim.inputs[3] = 1.0
		if not sim.reset(sim.state):
			return {ok = false, reason = "near-exhaustion reset failed", fault = sim.fault_reason}
	if name == "lake_bed":
		var state: PackedFloat64Array = sim.state.duplicate()
		state[RB.POS] = 110.0
		state[RB.POS + 1] = 125.0
		state[RB.POS + 2] = 5.55
		sim.state = state
		if not sim.reset(state):
			return {ok = false, reason = "lake-bed reset failed", fault = sim.fault_reason}
	var limit: int = 120
	if name in ["rpm_boundary"]:
		limit = 1
	elif name == "near_exhaustion":
		limit = 3
	elif name == "lake_bed":
		limit = 4
	var snapshots: Array[Dictionary] = []
	for tick: int in limit:
		if name == "source_cut" and tick == 40:
			flight.engine_running = false
		_set_controls(sim, tick, name)
		sim.step()
		snapshots.append(_snapshot(flight, counts))
		if name == "rpm_boundary" and tick == 0:
			var direct_count: int = flight._substeps(sim.state, sim.continuous, sim.time())
			var no_context_count: int = direct_count
			if flight.has_method("_substeps_joint"):
				no_context_count = flight._substeps_joint(sim.state, sim.continuous, sim.time(), {})
			if direct_count != no_context_count:
				_errors += 1
			print("DIRECT_SUBSTEPS_FALLBACK", {"direct": direct_count, "empty_joint": no_context_count})
		if not sim.fault_reason.is_empty():
			break
	var result: Dictionary = {
		ok = sim.fault_reason.is_empty(),
		fault = sim.fault_reason,
		engine_running = flight.engine_running,
		final_tick = sim.tick,
		counts = counts,
		snapshots = snapshots,
	}
	flight.free()
	return result


func _new_flight() -> Node:
	var flight: Node = Flight.new()
	if not flight.setup_shaft_integrator("coupled-rk4"):
		flight.free()
		return null
	flight.setup(P51)
	flight.input_enabled = false
	root.add_child(flight)
	flight.reset()
	return flight


func _set_controls(sim: Node, tick: int, name: String) -> void:
	var inputs: PackedFloat64Array = sim.inputs.duplicate()
	if name == "changing_controls":
		inputs[0] = 0.35 if tick % 24 < 12 else -0.25
		inputs[1] = 0.2 if tick % 32 < 16 else -0.15
		inputs[2] = 0.15 if tick % 18 < 9 else -0.1
		inputs[3] = 0.75 if tick % 40 < 20 else 0.3
	elif name == "runway":
		inputs[0] = 0.0
		inputs[1] = 0.7
		inputs[2] = 0.05
		inputs[3] = minf(0.8, float(tick) / 45.0)
	elif name in ["near_exhaustion"]:
		inputs[3] = 1.0
	else:
		inputs[0] = 0.0
		inputs[1] = 0.0
		inputs[2] = 0.0
		inputs[3] = 0.65
	sim.inputs = inputs


func _snapshot(flight: Node, counts: Array[int]) -> Dictionary:
	var sim: Node = flight.sim
	var contact_state: Dictionary = flight.contact_events()
	return {
		"tick": sim.tick,
		"state": sim.state.duplicate(),
		"previous": sim.previous.duplicate(),
		"continuous": sim.continuous.duplicate(),
		"aux": sim.aux.duplicate(),
		"inputs": sim.inputs.duplicate(),
		"modes": sim.modes.duplicate(),
		"loads": sim.last_loads.duplicate(),
		"events": sim.last_events.duplicate(true),
		"contact_events": contact_state.get("events", []).duplicate(true),
		"active_hull_ids": contact_state.get("active_hull_ids", []).duplicate(),
		"substeps": counts.duplicate(),
		"engine_running": flight.engine_running,
		"fault": sim.fault_reason,
	}


func _benchmark() -> Dictionary:
	var flight: Node = _new_bench_flight()
	if flight == null or not flight.is_flyable():
		return {ok = false, reason = "benchmark flight setup failed"}
	var sim: Node = flight.sim
	var calls: Array[int] = []
	var context_calls: Array[int] = []
	_install_substep_recorder(flight, calls, context_calls)
	var samples: Array[float] = []
	const TICKS: int = 120
	for run: int in 3:
		flight.reset()
		var inputs: PackedFloat64Array = sim.inputs.duplicate()
		inputs[3] = 1.0
		sim.inputs = inputs
		sim.paused = true
		var started: int = Time.get_ticks_usec()
		for tick: int in TICKS:
			sim.step()
			if not sim.fault_reason.is_empty():
				return {ok = false, fault = sim.fault_reason, run = run, tick = sim.tick}
		samples.append(float(Time.get_ticks_usec() - started) / float(TICKS))
	var sorted: Array[float] = samples.duplicate()
	sorted.sort()
	var step_usec: float = sim.step_usec
	flight.free()
	return {ok = true, best_usec_per_tick = sorted[0], samples = samples, last_step_usec = step_usec,
		callbacks = calls.size(), context_callbacks = context_calls.size()}


func _new_bench_flight() -> Node:
	var flight: Node = Flight.new()
	flight.soft_hull_contacts = true
	flight.crash_auto_restart = false
	if not flight.setup_shaft_integrator("coupled-rk4"):
		flight.free()
		return null
	flight.setup(P51)
	flight.input_enabled = false
	root.add_child(flight)
	var field: Dictionary = FieldLoader.load_from().field
	var lake: Dictionary = LakeLoader.load_from().lake
	if not flight.set_field(field) or not flight.set_lake_context(lake):
		flight.free()
		return null
	flight.start_choice = Flight.START_RUNWAY
	flight.reset()
	return flight


func _event_summary(result: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for frame: Dictionary in result.get("snapshots", []):
		for event: Dictionary in frame.get("events", []):
			out.append(str(event.get("type", "?")))
		for event: Dictionary in frame.get("contact_events", []):
			out.append(str(event.get("trigger", event.get("event", "contact"))))
	return out


func _install_substep_recorder(flight: Node, calls: Array[int], contexts: Array[int], verify_read_only := false) -> void:
	var model: Object = flight.sim.model
	var joint_callback: Variant = null
	for property_info: Dictionary in model.get_property_list():
		if str(property_info.get("name", "")) == "substeps_joint":
			joint_callback = model.get("substeps_joint")
			break
	if joint_callback is Callable and joint_callback.is_valid():
		var original: Callable = joint_callback
		var recorder: Callable = func(body: PackedFloat64Array, continuous: PackedFloat64Array, at: float,
				current_joint: Dictionary) -> int:
			if current_joint.has("stage_context"):
				contexts.append(1)
			var before: Dictionary = current_joint.duplicate(true) if verify_read_only else {}
			var count: int = original.call(body, continuous, at, current_joint)
			if verify_read_only and current_joint != before:
				_errors += 1
			calls.append(count)
			return count
		model.set("substeps_joint", recorder)
		return
	var original: Callable = model.get("substeps")
	var recorder: Callable = func(body: PackedFloat64Array, continuous: PackedFloat64Array, at: float) -> int:
		var count: int = original.call(body, continuous, at)
		calls.append(count)
		return count
	model.set("substeps", recorder)


func _argument(prefix: String) -> String:
	for value: String in OS.get_cmdline_user_args():
		if value.begins_with(prefix):
			return value.trim_prefix(prefix)
	return ""
