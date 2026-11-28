extends SceneTree
## NK-6u: the native tick integrator's own substep count equals FlightSession._substeps_joint and _substeps. For the
## Corsair and P-51 (liquid, joint callback, retractable gear), the glow Stik 61FX and the electric Ugly Stik 60:
## 1. 4,000 random bodies near and above the ground (speeds, attitudes, rotor speeds down to the stop and below,
##    valid and invalid gear aux) give the callback's count whenever the kernel answers, with the stage dictionary the
##    kernel built;
## 2. two native sessions, one leaving every count to the callbacks, keep identical checkpoints from the default start,
##    power off and nose down into ground contact, with the engine stopped halfway.
## Skips (passes) without the verified library.

const Session := preload("res://sim/flight_session.gd")
const Ground := preload("res://physics/ground_contact.gd")
const AIRCRAFT := [["res://data/aircraft/f4u_corsair_250.json", "f4u-corsair-250"],
	["res://data/aircraft/p51d_mustang_120.json", "p51d-mustang-120"],
	["res://data/aircraft/stik_glow_61fx_2t.json", "stik-glow-61fx-2t"],
	["res://data/aircraft/jensen_ugly_stik_60.json", "jensen-das-ugly-stik-60"]]
const TICKS := 2400

var _checks := 0
var _failures := 0
var _rng := RandomNumberGenerator.new()


func _initialize() -> void:
	_run.call_deferred()


func _session(path: String, id: String, native_substeps: bool) -> Node:
	var session: Node = Session.new()
	session.input_enabled = false
	session.crash_auto_restart = false
	session.native_substeps_enabled = native_substeps
	session.setup_stage_backend("native")
	session.setup(path, id)
	root.add_child(session)
	session.set_process(false)
	session.set_physics_process(false)
	return session


func _run() -> void:
	var status: Dictionary = load("res://sim/native_stage.gd").library_status()
	if not status.get("ok", false) or not ClassDB.class_has_method(&"OpenRCNativeKernel", &"prepare_substeps"):
		print("NK6U_SKIP no native library with the substep plan")
		quit(0)
		return
	_rng.seed = 6211
	for aircraft: Array in AIRCRAFT:
		var probe: Node = _session(aircraft[0], aircraft[1], true)
		var native: Node = _session(aircraft[0], aircraft[1], true)
		var reference: Node = _session(aircraft[0], aircraft[1], false)
		var id: String = aircraft[1]
		var bound: bool = native._native_stage != null and native._native_stage._substeps_bound \
			and reference._native_stage != null and not reference._native_stage._substeps_bound
		_check("%s: the native session binds its substep plan, the reference does not" % id, bound)
		if bound:
			_oracle(probe, id)
			_lockstep(native, reference, id)
		for session: Node in [probe, native, reference]:
			session.free()
	print("native substeps: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 or _checks == 0 else 0)


func _oracle(session: Node, id: String) -> void:
	for i: int in 30:
		session.sim.step()
	var plan: Dictionary = session.native_substep_plan()
	var model: RefCounted = session.sim.model
	var kernel: Object = session._native_stage._native
	var joint: bool = model.substeps_joint.is_valid()
	var base_state: PackedFloat64Array = session.sim.state.duplicate()
	var base_values: PackedFloat64Array = session.sim.continuous.duplicate()
	var base_aux: PackedFloat64Array = session.sim.aux.duplicate()
	# The tick context of a tick about to start at sim.time(), so a stage at that time can capture the preview.
	var t: float = session.sim.time()
	var dt: float = session.sim.dt()
	var installed: bool = session._native_stage.tick_context(session, base_aux, session.sim.inputs)
	var rotor: int = int(plan.rotor_index)
	var gear_index: int = int(plan.gear_aux_index)
	var answered := 0
	var mismatched := 0
	var first := ""
	var histogram := {}
	for i: int in 4000:
		var body: PackedFloat64Array = base_state.duplicate()
		body[2] = -_rng.randf_range(-0.3, 3.0) if i % 5 != 0 else -_rng.randf_range(3.0, 40.0)
		for k: int in 3:
			body[3 + k] = 0.0 if i % 11 == 0 else _rng.randf_range(-25.0, 25.0)
			body[10 + k] = _rng.randf_range(-3.0, 3.0)
		var q := Quaternion(Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)).normalized(),
			_rng.randf_range(-0.6, 0.6))
		body[6] = q.w
		body[7] = q.x
		body[8] = q.y
		body[9] = q.z
		var values: PackedFloat64Array = base_values.duplicate()
		if rotor < values.size():
			values[rotor] = [0.0, 1.0, 1.0000001, 2.0, 20.0, 150.0, _rng.randf_range(1.0, 400.0), _rng.randf_range(400.0, 12000.0)][i % 8]
		var aux: PackedFloat64Array = base_aux.duplicate()
		if gear_index >= 0 and gear_index + 1 < aux.size():
			aux[gear_index] = [1.0, 0.0, 0.5, _rng.randf(), 1.5, NAN][i % 6] if i % 3 == 0 else 1.0
			aux[gear_index + 1] = [1.0, 0.0, 0.5][i % 3] if i % 7 == 0 else 1.0
		# Half the samples carry the joint stage's preview, as the tick's own state does when the session captures it.
		var previewed: bool = i % 2 == 0
		kernel.set_preview_context(body, values, previewed)
		var probe: Array = kernel.stage_substep_probe(model, body, values, aux, t, dt)
		if probe.size() != 2:
			mismatched += 1
			continue
		var native_count: int = probe[0]
		if native_count < 0:
			continue
		answered += 1
		var saved_aux: PackedFloat64Array = session.sim.aux
		session.sim.aux = aux # current_landing_gear() reads sim.aux, as inside the tick
		var expected: int = session._substeps_joint(body, values, t, probe[1]) if joint else session._substeps(body, values, t)
		session.sim.aux = saved_aux
		histogram[expected] = int(histogram.get(expected, 0)) + 1
		if native_count != expected:
			mismatched += 1
			if first.is_empty():
				first = "sample %d: native %d, callback %d" % [i, native_count, expected]
	var refined: bool = histogram.keys().any(func(count: int) -> bool: return count > 1)
	_check("%s: the kernel's counts equal the callback's (%d answered of 4000, counts %s, plan %s)" % [id, answered,
		histogram, plan], installed and mismatched == 0 and answered >= 1800 and (refined or not plan.shaft_base), first)
	# No stock gear declares more than one contact substep: a synthetic gear plan checks the kernel's Ground.substeps,
	# with this aircraft's retractable aux rule, against the GDScript law on the same gear values.
	var synthetic: Dictionary = plan.duplicate()
	synthetic.gear_mode = maxi(1, int(plan.gear_mode))
	synthetic.gear_count = 4
	synthetic.reach = 0.42
	synthetic.shaft_base = false
	var gear := {substeps = 4, reach = 0.42}
	var prepared: bool = kernel.prepare_substeps(session, synthetic)
	var ground_mismatch := 0
	var ground_histogram := {}
	for i: int in 3000:
		var body: PackedFloat64Array = base_state.duplicate()
		body[2] = -_rng.randf_range(-0.2, 2.5)
		for k: int in 3:
			body[3 + k] = [0.0, -0.0, _rng.randf_range(-30.0, 30.0)][i % 3]
		var aux: PackedFloat64Array = base_aux.duplicate()
		if gear_index >= 0 and gear_index + 1 < aux.size():
			aux[gear_index] = [1.0, 0.0, 0.5, _rng.randf(), 1.5, NAN, -0.0][i % 7]
			aux[gear_index + 1] = [1.0, 0.0, 0.5, -0.0][i % 4]
		kernel.set_preview_context(body, base_values, false)
		var probe: Array = kernel.stage_substep_probe(model, body, base_values, aux, t, dt)
		var posed: Dictionary = gear if synthetic.gear_mode == 1 or session._gear_aux_valid(aux) else {}
		var expected: int = Ground.substeps(body, posed, dt, session.ground_surfaces)
		ground_histogram[expected] = int(ground_histogram.get(expected, 0)) + 1
		if probe.size() != 2 or int(probe[0]) != expected:
			ground_mismatch += 1
	_check("%s: a synthetic 4-substep gear plan counts as Ground.substeps (counts %s)" % [id, ground_histogram],
		prepared and ground_mismatch == 0 and ground_histogram.size() == 2, str(ground_mismatch))
	_check("%s: the session's own plan rebinds" % id, kernel.prepare_substeps(session, session.native_substep_plan()))


func _lockstep(native: Node, reference: Node, id: String) -> void:
	var sessions: Array = [native, reference]
	for session: Node in sessions:
		session.sim.inputs[3] = 0.0
		session.sim.inputs[1] = -0.35
	var diverged := -1
	var lowest := INF
	for tick: int in TICKS:
		if tick == TICKS / 2:
			for session: Node in sessions:
				session.engine_running = false
		for session: Node in sessions:
			session.sim.step()
		lowest = minf(lowest, -native.sim.state[2])
		if var_to_bytes(native.checkpoint()) != var_to_bytes(reference.checkpoint()):
			diverged = tick
			break
	var stats: Dictionary = native._native_stage._native.tick_stats()
	var answers: int = int(stats.get("substep_answers", 0))
	var reference_answers: int = int(reference._native_stage._native.tick_stats().get("substep_answers", 0))
	_check("%s: identical checkpoints with and without the kernel's count (lowest %.2f m, %d kernel answers, %d refined)" % [id,
		lowest, answers, int(stats.get("substep_refined", 0))], diverged < 0 and answers > TICKS / 2 and reference_answers == 0, "diverged at tick %d" % diverged)


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL ", label, " ", detail)
	else:
		print("ok ", label)
