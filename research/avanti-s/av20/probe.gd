# AV-20 native paired-flight and supported static-fixture evidence. Output path is explicit and fresh.
extends SceneTree

const Flight := preload("res://sim/flight_session.gd")
const M := preload("res://physics/math3d.gd")
const Turbine := preload("res://physics/turbine.gd")
const DATA := "res://data/aircraft/sebart_avanti_s_a200.json"
const ID := "sebart-avanti-s-a200-p100rx"


func _digest(f: Node) -> String:
	var hash_context := HashingContext.new()
	hash_context.start(HashingContext.HASH_SHA256)
	hash_context.update(var_to_bytes([f.sim.state, f.sim.previous, f.sim.continuous, f.sim.aux,
		f.sim.inputs, f.sim.modes, f.sim.last_loads, f.sim.tick, f.sim.mass, f.sim.inertia]))
	return hash_context.finish().hex_encode()


func _flight_case(path: String) -> Dictionary:
	var f: Node = Flight.new()
	f.setup(path)
	f.input_enabled = false
	if not f.is_flyable():
		f.free()
		return {ok = false, path = path}
	f.set_start_altitude(1000.0)
	f.reset()
	var final_digest: String = ""
	var checkpoints: Array = []
	var timing: Array = []
	for at: int in 720:
		f.commands.roll = 0.08 if at >= 60 and at < 180 else 0.0
		f.commands.pitch = -0.03 if at >= 180 and at < 300 else 0.0
		f.commands.yaw = 0.02 if at >= 300 and at < 420 else 0.0
		f.commands.throttle = 1.0 if at >= 120 and at < 360 else (0.0 if at >= 360 else f.start.throttle)
		f.sim.inputs = f._inputs()
		f._physics_process(f.sim.dt())
		var began: int = Time.get_ticks_usec()
		f.sim.step()
		timing.append(Time.get_ticks_usec() - began)
		if not f.sim.fault_reason.is_empty() or not f.crash.is_empty():
			var reason: String = f.sim.fault_reason
			f.free()
			return {ok = false, path = path, reason = reason, tick = at}
		if at % 120 == 119:
			checkpoints.append(_digest(f))
	final_digest = _digest(f)
	timing.sort()
	var model: Dictionary = f.aircraft.model
	var result := {ok = true, id = model.id, path = path, ticks = f.sim.tick, duration_s = f.sim.time(),
		state_sha256 = final_digest, interval_sha256 = checkpoints,
		final_state = Array(f.sim.state), final_rpm = f.sim.aux[0], continuous = Array(f.sim.continuous),
		mass_kg = f.sim.mass, timing_observational_p50_us = timing[360], timing_observational_p95_us = timing[684]}
	f.free()
	return result


## The stand cancels aircraft force; zero velocity/gravity isolate the same engine law at V=0.
## No physical stand data or engine start/stop/thermal behavior is represented by this fixture.
func _bench(up: bool) -> Dictionary:
	var f: Node = Flight.new()
	f.setup(DATA, ID)
	f.input_enabled = false
	if not f.is_flyable():
		f.free()
		return {ok = false}
	var prop: Dictionary = f.aircraft.model.propulsion
	var n0: float = prop.idle_rpm if up else prop.max_rpm
	var target_n: float = prop.max_rpm if up else prop.idle_rpm
	var f0: float = Turbine.thrust(n0, 0.0, prop, 1.225)
	var f1: float = Turbine.thrust(target_n, 0.0, prop, 1.225)
	f.sim.inputs = PackedFloat64Array([0.0, 0.0, 0.0, 0.0 if up else 1.0])
	f.sim.aux[0] = n0
	if not f.sim.continuous.is_empty():
		f.sim.continuous[0] = n0
		var native: Callable = f.sim.model.stage
		f.sim.model.stage = func(s: PackedFloat64Array, c: PackedFloat64Array, t: float) -> Dictionary:
			var result: Dictionary = native.call(s, c, t)
			if not result.is_empty():
				result.loads = PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
				result.rotor_momentum = PackedFloat64Array([0.0, 0.0, 0.0])
			return result
	else:
		f.sim.model.loads = func(_s: PackedFloat64Array, _t: float) -> PackedFloat64Array:
			return PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	f.sim.gravity = 0.0
	var state := PackedFloat64Array([0.0, 0.0, -1000.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	if not f.sim.reset(state):
		f.free()
		return {ok = false}
	var samples: Array = [{time_s = 0.0, thrust_n = f0}]
	for at: int in 2160:
		if at == 240:
			f.sim.inputs[3] = 1.0 if up else 0.0
		f.sim.step()
		if not f.sim.fault_reason.is_empty():
			var reason: String = f.sim.fault_reason
			f.free()
			return {ok = false, reason = reason}
		samples.append({time_s = f.sim.time(), thrust_n = Turbine.thrust(f.sim.aux[0], 0.0, prop, 1.225)})
	var result := {id = "idle-full" if up else "full-idle", command_edge_time_s = 1.0,
		command_before = 0.0 if up else 1.0, command_after = 1.0 if up else 0.0,
		f0_n = f0, f1_n = f1, rated_thrust_n = maxf(f0, f1), dwell_required_s = 0.05,
		max_sample_gap_s = 0.004167, samples = samples}
	f.free()
	return result


func _initialize() -> void:
	var out: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
	if out.is_empty() or FileAccess.file_exists(out):
		printerr("AV-20 requires a fresh --out= path")
		quit(1)
		return
	Engine.physics_ticks_per_second = 240
	var paths: Array[String] = ["res://data/aircraft/jensen_ugly_stik_60.json", "res://data/aircraft/gp_extra_300s_60.json",
		"res://data/aircraft/p51d_mustang_120.json", "res://data/aircraft/turbo_lumber_evolution.json", DATA]
	var report := {schema = "openrc.av20.native-probe/v1", evidence = "synthetic software verification, no physical calibration", cases = []}
	var ok: bool = true
	for path: String in paths:
		var result: Dictionary = _flight_case(path)
		report.cases.append(result)
		ok = ok and result.ok
	var up: Dictionary = _bench(true)
	var down: Dictionary = _bench(false)
	if up.has("ok") or down.has("ok"):
		ok = false
	report.response = {schema = "openrc.av18.response-trace/v1", source = "AV-20 native fixed-body synthetic stand at 240 Hz", trials = [up, down]}
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	var file := FileAccess.open(out, FileAccess.WRITE)
	if file == null:
		quit(1)
		return
	file.store_string(JSON.stringify(report, "", true, true))
	file.close()
	print("AV-20 native probe: %d cases, ok=%s" % [report.cases.size(), str(ok)])
	quit(0 if ok else 1)
