# D1-R5: a finite iteration budget must not publish an unsatisfied wing calibration.
extends SceneTree

const Data = preload("res://physics/aircraft_data.gd")
const Session = preload("res://sim/flight_session.gd")
const PATH: String = "res://data/aircraft/jensen_ugly_stik_60.json"
const FILES: Array[String] = ["jensen_ugly_stik_60", "gp_extra_300s_60", "p51d_mustang_120", "sebart_avanti_s_a200"]
var checks: int = 0
var failures: int = 0


func check(label: String, condition: bool, detail: String = "") -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL ", label, " ", detail)


func raw() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(PATH))


func tail_share(model: Dictionary) -> float:
	return float(model.surfaces.horizontal.area) / float(model.reference.S) * float(model.surfaces.horizontal.lift_slope)


func row_mean(values: PackedFloat64Array, count: int) -> float:
	var total: float = 0.0
	for value: float in values:
		total += value
	return total / float(count)


func calibrated(model: Dictionary, env: Dictionary, surfaces: Dictionary, aero: Dictionary) -> Variant:
	# Dynamic dispatch lets this same regression reproduce the old void-returning loader.
	var loader: Script = Data
	return loader.call("_induced_map", env, surfaces, aero, model.reference.S, model.reference.b, model.reference.chords)


func finite_calibration(label: String, model: Dictionary, env: Dictionary, surfaces: Dictionary, aero: Dictionary) -> void:
	var published: bool = env.has("induced_map") and env.has("strip_cl0") and env.has("strip_slope")
	check(label + " publishes map", published)
	if not published:
		return
	var count: int = env.station_ys.size()
	var values: PackedFloat64Array = env.induced_map
	var slope: float = env.strip_slope
	var sized: bool = values.size() == count * count and env.strip_cl0.size() == count
	check(label + " map size", sized)
	if not sized:
		return
	var finite: bool = is_finite(slope)
	for value: float in values:
		finite = finite and is_finite(value)
	for value: float in env.strip_cl0:
		finite = finite and is_finite(value)
	check(label + " finite outputs", finite)
	var tail: Dictionary = surfaces.horizontal
	var share: float = float(tail.area) / float(model.reference.S) * float(tail.lift_slope)
	var target: float = float(aero.CLa) - share
	check(label + " solved slope residual", absf(slope * row_mean(values, count) - target) <= 1e-10 * maxf(1.0, absf(target)))
	var twist: PackedFloat64Array = surfaces.get("station_incidence", PackedFloat64Array())
	var offset: float = share * float(tail.incidence)
	for i: int in count:
		var angle: float = 0.0
		for j: int in count:
			angle += values[i * count + j] * (twist[j] if not twist.is_empty() else 0.0)
		offset += (float(env.strip_cl0[i]) + slope * angle) / float(count)
	check(label + " zero-angle lift residual", absf(offset - float(aero.CL0)) <= 1e-10)
	if tail.has("downwash_gradient"):
		var valid: bool = true
		for key: String in ["free_slope", "elevator_tau", "downwash_per_cl", "free_incidence", "wing_cl0", "downwash_lag_length"]:
			valid = valid and tail.has(key) and is_finite(float(tail.get(key, NAN)))
		check(label + " finite downwash", valid)


func fleet_and_boundaries() -> void:
	for file: String in FILES:
		var loaded: Dictionary = Data.load_file("res://data/aircraft/%s.json" % file)
		check(file + " positive fleet control", loaded.ok, str(loaded.errors))
		if not loaded.ok:
			continue
		var model: Dictionary = loaded.model
		finite_calibration(file, model, model.envelope, model.surfaces, model.aero)
		# Construct roots at the supported section-slope bounds using the fixed geometry.
		var ys: PackedFloat64Array = model.envelope.station_ys
		var span: float = model.reference.b
		var chords: PackedFloat64Array = model.reference.chords
		var local_chords: PackedFloat64Array = PackedFloat64Array()
		for y: float in ys:
			local_chords.append(float(model.reference.S) / span if chords.is_empty() else chords[0] + (chords[1] - chords[0]) * absf(y) / (span / 2.0))
		var influence: PackedFloat64Array = Data.strip_influence(Data.station_edges(span, chords), ys, local_chords)
		for section_slope: float in [0.1, 50.0]:
			var aero: Dictionary = model.aero.duplicate(true)
			aero.CLa = tail_share(model) + section_slope * row_mean(Data.effective_angle_map(influence, section_slope, ys.size()), ys.size())
			var env: Dictionary = {station_ys = ys}
			var surfaces: Dictionary = model.surfaces.duplicate(true)
			check(file + " boundary solve succeeds", calibrated(model, env, surfaces, aero) == true)
			finite_calibration(file + " bound " + str(section_slope), model, env, surfaces, aero)
			check(file + " boundary root retained", env.has("strip_slope") and absf(float(env.get("strip_slope", NAN)) - section_slope) <= 1e-10)
		for target: float in [-1.0, 0.0, 1e-12, 100.0, NAN, INF, -INF]:
			var aero: Dictionary = model.aero.duplicate(true)
			aero.CLa = tail_share(model) + target
			var env: Dictionary = {station_ys = ys}
			var surfaces: Dictionary = model.surfaces.duplicate(true)
			var before: PackedByteArray = var_to_bytes([env, surfaces])
			check(file + " invalid target returns false " + str(target), calibrated(model, env, surfaces, aero) == false)
			check(file + " invalid target publishes nothing " + str(target), var_to_bytes([env, surfaces]) == before)
		# A solved slope still cannot publish overflowing lift offsets or invalid twist.
		for kind: String in ["offset", "twist"]:
			var aero: Dictionary = model.aero.duplicate(true)
			var env: Dictionary = {station_ys = ys}
			var surfaces: Dictionary = model.surfaces.duplicate(true)
			if kind == "offset":
				aero.CL0 = INF
			else:
				var twist: PackedFloat64Array = PackedFloat64Array()
				twist.resize(ys.size())
				twist[0] = NAN
				surfaces.station_incidence = twist
			var before: PackedByteArray = var_to_bytes([env, surfaces])
			check(file + " invalid " + kind + " returns false", calibrated(model, env, surfaces, aero) == false)
			check(file + " invalid " + kind + " publishes nothing", var_to_bytes([env, surfaces]) == before)


func source_refusals() -> void:
	for slope: float in [6.3, 4.58, 4.579999999999, 4.53]:
		var input: Dictionary = raw()
		input.aero.surfaces.horizontal.area.value = 0.4 if slope == 6.3 else input.reference.wing_area.value
		input.aero.surfaces.horizontal.lift_slope.value = slope
		var result: Dictionary = Data.validate_and_derive(input)
		check("unreachable wing target refuses model " + str(slope), not result.ok and result.model.is_empty() and str(result.errors).contains("induced wing calibration"), str(result.errors))


func session_boundary() -> void:
	var input: Dictionary = raw()
	input.aero.surfaces.horizontal.area.value = input.reference.wing_area.value
	input.aero.surfaces.horizontal.lift_slope.value = input.aero.coefficients.CLa.value
	var path: String = "user://d1-r5-invalid-%d.json" % OS.get_process_id()
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	check("invalid fixture writable", file != null)
	if file == null:
		return
	file.store_string(JSON.stringify(input, "", true, true))
	file.close()
	var session: Session = Session.new()
	session.input_enabled = false
	session.setup(PATH)
	for _tick: int in 10:
		session.sim.step()
	var state: Dictionary = session.checkpoint().duplicate(true)
	var aircraft: PackedByteArray = var_to_bytes(session.aircraft)
	var start: PackedByteArray = var_to_bytes([session.start, session.trims])
	var was_paused: bool = session.sim.paused
	session.aircraft_path = path
	var message: String = session.reload()
	check("reload reports calibration failure", message.begins_with("reload failed") and message.contains("induced wing calibration"), message)
	check("reload preserves loaded aircraft", var_to_bytes(session.aircraft) == aircraft)
	check("reload preserves start and trim", var_to_bytes([session.start, session.trims]) == start)
	check("reload preserves complete simulation boundary", var_to_bytes(session.checkpoint().simulation) == var_to_bytes(state.simulation))
	check("reload preserves pause state", session.sim.paused == was_paused and session.can_resume())
	session.sim.step()
	check("old flight continues", session.sim.tick == 11 and session.sim.fault_reason.is_empty())
	session.free()
	var initial: Session = Session.new()
	initial.input_enabled = false
	initial.setup(path)
	check("invalid initial aircraft cannot fly", not initial.is_flyable() and initial.sim.paused and initial.pause_reason.contains("induced wing calibration"))
	initial.resume()
	initial.sim.step()
	check("resume cannot bypass refusal", initial.sim.paused and initial.sim.tick == 0)
	initial.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _initialize() -> void:
	fleet_and_boundaries()
	source_refusals()
	session_boundary()
	print("D1-R5 integration: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
