# D1-R4: validate solved stall envelopes, not just finite input quantities.
extends SceneTree
const Data = preload("res://physics/aircraft_data.gd")
const Aero = preload("res://physics/aero.gd")
const Session = preload("res://sim/flight_session.gd")
const PATH: String = "res://data/aircraft/jensen_ugly_stik_60.json"
var checks: int = 0
var failures: int = 0

func check(label: String, condition: bool, detail: String = "") -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL ", label, " ", detail)

func raw() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(PATH))

func peak(aero: Dictionary, env: Dictionary, side: float) -> float:
	var start: float = env.a1 if side > 0.0 else env.n1
	var end: float = env.a2 if side > 0.0 else env.n2
	var best: float = 0.0
	for k in 801:
		var angle: float = side * (start + (end - start) * (float(k) / 800.0) * 1.25)
		best = maxf(best, side * Aero.lift_alpha(angle, aero, env))
	return best

func reject(label: String, input: Dictionary, needle: String = "aero.envelope") -> void:
	var result: Dictionary = Data.validate_and_derive(input)
	check(label, not result.ok and result.model.is_empty() and str(result.errors).contains(needle), str(result.errors))

func _initialize() -> void:
	for file: String in ["jensen_ugly_stik_60", "gp_extra_300s_60", "p51d_mustang_120", "sebart_avanti_s_a200"]:
		var loaded: Dictionary = Data.load_file("res://data/aircraft/%s.json" % file)
		check("fleet load " + file, loaded.ok, str(loaded.errors))
		if not loaded.ok:
			continue
		var model: Dictionary = loaded.model
		var env: Dictionary = model.envelope
		for side: float in [1.0, -1.0]:
			var start: float = env.a1 if side > 0 else env.n1
			var end: float = env.a2 if side > 0 else env.n2
			var target: float = env.CL_max if side > 0 else -env.CL_min
			check("fleet finite ordered domain", is_finite(start) and is_finite(end) and start >= deg_to_rad(8) and end > start and end <= PI / 2.0)
			check("fleet independently scanned peak", absf(peak(model.aero, env, side) - target) <= 1e-9)
			check("fleet separated at 90 degrees", Aero.stall_weight(side * PI / 2.0, env) == 1.0)
	# All are finite input values; the old loader accepts the first four and tiny collapsed blends.
	for slope: float in [0.1, 1e-10, 1e-100, 1e-300]:
		var input: Dictionary = raw()
		input.aero.coefficients.CLa.value = slope
		reject("unreachable finite lift slope", input)
	# Offset lift must be signed separately on each side.
	for offset: float in [-0.8, 0.8]:
		var input: Dictionary = raw()
		input.aero.coefficients.CL0.value = offset
		input.aero.coefficients.CLa.value = 0.5
		reject("asymmetric unreachable side", input)
	var input: Dictionary = raw()
	input.aero.coefficients.CL0.value = 0.0
	input.aero.coefficients.CLa.value = 1.0
	input.aero.envelope.stall_blend_width.value = 30.0
	input.aero.envelope.CL_max.value = 1.3
	input.aero.envelope.CL_min.value = -1.3
	input.aero.envelope.CD90.value = 0.5
	reject("reachable linear bound but blend ends beyond 90", input, "finish by 90")
	input = raw()
	input.aero.coefficients.CL0.value = 1.5
	reject("nonpositive search bracket", input, "bracket")
	for key: String in ["CL_max", "CL_min", "CD90", "stall_blend_width"]:
		for bad: float in [NAN, INF, -INF]:
			input = raw()
			input.aero.envelope[key].value = bad
			reject("nonfinite source " + key, input)
	# Generate positive controls from the original sampled law, including a grid extending past 90.
	for start_deg: float in [8.1, 15.0, 45.0, 79.9]:
		var errors: PackedStringArray = PackedStringArray()
		var node: Dictionary = raw().aero.envelope.duplicate(true)
		var start: float = deg_to_rad(start_deg)
		var width: float = deg_to_rad(10.0)
		var aero: Dictionary = {CL0 = 0.0, CLa = 3.0 if start_deg < 20.0 else 1.0}
		var env: Dictionary = {a1 = start, a2 = start + width, n1 = start, n2 = start + width, CD90 = 0.5}
		var target: float = peak(aero, env, 1.0)
		node.CL_max.value = target
		node.CL_min.value = -target
		node.CD90.value = 0.5
		node.stall_blend_width.value = 10.0
		var solved: Dictionary = Data._envelope(errors, node, aero)
		check("valid constructed envelope " + str(start_deg), errors.is_empty() and not solved.is_empty(), str(errors))
		if not solved.is_empty():
			check("constructed root preserved", absf(solved.a1 - start) < 1e-12 and absf(solved.n1 - start) < 1e-12)
	if OS.get_environment("OPENRC_ENVELOPE_SKIP_SESSION") != "1":
		_session_boundary()
	print("D1-R4: %d checks, %d failed" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _session_boundary() -> void:
	var invalid: Dictionary = raw()
	invalid.aero.coefficients.CLa.value = 0.1
	var path: String = "user://d1-r4-invalid-%d.json" % OS.get_process_id()
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	check("invalid fixture writable", file != null)
	if file == null:
		return
	file.store_string(JSON.stringify(invalid, "", true, true))
	file.close()
	check("invalid file refused", not Data.load_file(path).ok)
	var session: Node = Session.new()
	session.input_enabled = false
	session.setup(PATH)
	for _tick in 10:
		session.sim.step()
	var state: Dictionary = session.checkpoint().duplicate(true)
	var aircraft: Dictionary = session.aircraft.duplicate(true)
	var start: Dictionary = session.start.duplicate(true)
	var trims: Dictionary = session.trims.duplicate(true)
	session.aircraft_path = path
	var message: String = session.reload()
	check("reload identifies envelope", message.begins_with("reload failed") and message.contains("aero.envelope"), message)
	check("reload preserves aircraft and trim", session.aircraft == aircraft and session.start == start and session.trims == trims)
	# aircraft_path is intentionally the rejected path; compare the complete simulation boundary.
	check("reload preserves flight state", session.checkpoint().simulation == state.simulation)
	session.sim.step()
	check("existing aircraft continues", session.sim.tick == 11 and session.sim.fault_reason.is_empty())
	session.free()
	var initial: Node = Session.new()
	initial.input_enabled = false
	initial.setup(path)
	check("invalid initial aircraft cannot fly", not initial.is_flyable() and initial.sim.paused and initial.pause_reason.contains("aero.envelope"))
	initial.resume()
	initial.sim.step()
	check("resume cannot bypass invalid envelope", initial.sim.paused and initial.sim.tick == 0)
	initial.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
