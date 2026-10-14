# D6e-R1 root-cause counterfactuals for the standard Ugly Stik. Research only; never writes aircraft data.
# Variants change (a) the propeller Ct/Cp tables to APC's 12x6 data at the legacy 11149 rpm slice and/or
# (b) reference.aero_reference_point x, the moment reference of the borrowed coefficients. Moving the ARP transfers every
# global moment through r x F and moves the local wing strips with it, so both regimes keep one static margin. Directional
# derivatives are recomputed with the loader's fin-arm contract, which leaves the yaw physics about the CG unchanged.
# Each variant re-solves the normal 15 m/s start, then flies calm 40 s throttle steps and the owner's recorded inputs.
extends SceneTree

const Session := preload("res://sim/flight_session.gd")
const Weather := preload("res://physics/wind_config.gd")
const AircraftData := preload("res://physics/aircraft_data.gd")
const WheelProfiles := preload("res://physics/wheel_profiles.gd")
const Dynamics := preload("res://physics/dynamics.gd")
const Lin := preload("res://physics/linearize.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")
const PATH := "res://data/aircraft/jensen_ugly_stik_60.json"
const ID := "jensen-das-ugly-stik-60"
const PLAN_CG_X := 0.1209
const CHORD := 0.3048
## Target static margin for the geometric counterfactual: inside the 3-9 % range of vlm_neutral_point.py at the plan CG.
const GEOMETRIC_MARGIN := 0.06

var raw := {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0}
var samples := {}


func _initialize() -> void:
	_run.call_deferred()


func _variant(arp_x: float, prop_tables: Dictionary = {}) -> Dictionary:
	var parsed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	parsed.reference.aero_reference_point.value[0] = arp_x
	if not prop_tables.is_empty():
		parsed.propulsion.propeller.ct_table.value = prop_tables.ct
		parsed.propulsion.propeller.cp_table.value = prop_tables.cp
	var fin: Dictionary = parsed.aero.surfaces.vertical
	var area: float = parsed.reference.wing_area.value
	var span: float = parsed.reference.wing_span.value
	var fin_lift: float = float(fin.lift_slope.value) * float(fin.area.value) / area
	var arm: float = float(fin.position.value[0]) - arp_x
	parsed.aero.coefficients.Cndr.value = -fin_lift * float(fin.control_effectiveness.value) * arm / span
	parsed.aero.coefficients.Cnb.value = fin_lift * arm / span
	var result: Dictionary = AircraftData.validate_and_derive(parsed)
	assert(result.ok, str(result.get("errors", [])))
	var profiled: Dictionary = WheelProfiles.apply_to_model(result.model)
	assert(profiled.ok)
	result.model = profiled.model
	result.wheel_profile_identity = profiled.identity
	result.input_identity = {format = AircraftData.FORMAT, sha256 = "research-variant-arp-%.6f" % arp_x}
	return result


func _session(frozen: Dictionary, gentle: bool) -> Node:
	var session := Session.new()
	if gentle:
		assert(session.setup_weather(Weather.GENTLE_PRACTICE))
	session.setup(PATH, ID, frozen.duplicate(true))
	root.add_child(session)
	session.set_physics_process(false)
	session.sim.set_physics_process(false)
	session.radio.connected = false
	raw = {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0}
	session.read_raw = func() -> Dictionary: return raw.duplicate()
	session.rate_profile = "normal"
	return session


## Static pitch stiffness about the CG at the trimmed state, by central difference of the complete runtime loads.
func _stiffness(model: Dictionary, s0: PackedFloat64Array, d: Dictionary, rpm: float) -> Dictionary:
	var loads := {}
	var V: float = sqrt(s0[3] * s0[3] + s0[5] * s0[5])
	for sign: float in [-1.0, 1.0]:
		var a: float = atan2(s0[5], s0[3]) + sign * 1e-4
		var s := s0.duplicate()
		s[3] = V * cos(a)
		s[5] = V * sin(a)
		loads[sign] = Dynamics.evaluate(s, model, d, rpm, 1.225, M.v3(0, 0, 0), 9.80665).loads
	var qbar := 0.5 * 1.225 * V * V
	var cma: float = (loads[1.0][4] - loads[-1.0][4]) / 2e-4 / (qbar * model.reference.S * model.reference.c)
	var cla: float = -(loads[1.0][2] - loads[-1.0][2]) / 2e-4 / (qbar * model.reference.S)
	return {Cma_cg = cma, CLa = cla, static_margin = -cma / cla}


## Longitudinal 4-state linearization x = [u, w, q, theta] about the trimmed state, throttle and surfaces fixed.
func _modes(model: Dictionary, s0: PackedFloat64Array, d: Dictionary, rpm: float) -> Dictionary:
	var euler: PackedFloat64Array = M.q_to_euler(RB._att(s0))
	var f := func(x: PackedFloat64Array) -> PackedFloat64Array:
		var s := RB.make_state(M.v3(0, 0, -500), M.v3(x[0], 0.0, x[1]), M.q_from_euler(euler[0], x[3], 0.0), M.v3(0.0, x[2], 0.0))
		var dot: PackedFloat64Array = Dynamics.evaluate(s, model, d, rpm, 1.225, M.v3(0, 0, 0), 9.80665).derivative
		return PackedFloat64Array([dot[RB.VEL], dot[RB.VEL + 2], dot[RB.RATE + 1], x[2]])
	var classified: Dictionary = Lin.classify(Lin.eigenvalues(Lin.jacobian(f, PackedFloat64Array([s0[3], s0[5], 0.0, euler[1]]), 1e-5)))
	return {oscillatory = classified.oscillatory, real = classified.real}


func _flight(frozen: Dictionary, protocol: Dictionary) -> Dictionary:
	var replay: bool = protocol.get("replay", false)
	var session := _session(frozen, replay)
	assert(session.start.get("ok", false), "trim failed")
	if not replay:
		session.sim.state[2] = -300.0
		session.sim.previous = session.sim.state.duplicate()
	var trim_throttle: float = session.commands.throttle
	var h0: float = -session.sim.state[2]
	var end_tick: int = protocol.ticks
	var target: float = protocol.get("throttle", trim_throttle)
	var first_inverted := -1.0
	var max_q := 0.0
	var max_pitch := -INF
	var rows: Array = []
	for tick in range(1, end_tick + 1):
		if replay and samples.has(tick):
			raw = samples[tick].raw
		session._physics_process(session.sim.dt())
		if session.sim.paused:
			break
		if not replay:
			session.commands.throttle = trim_throttle if tick < 480 else target
			session.sim.inputs = session._inputs()
		session.sim.step()
		if not session.crash.is_empty():
			break
		var s: PackedFloat64Array = session.sim.state
		var att: PackedFloat64Array = RB._att(s)
		var euler: PackedFloat64Array = M.q_to_euler(att)
		max_q = maxf(max_q, absf(s[RB.RATE + 1]))
		max_pitch = maxf(max_pitch, rad_to_deg(euler[1]))
		if first_inverted < 0.0 and M.q_rotate(att, M.v3(0.0, 0.0, 1.0))[2] < 0.0:
			first_inverted = session.sim.time()
		if tick % 240 == 0:
			var air: Dictionary = session.air_data(s, session.sim.time())
			var v_ned: PackedFloat64Array = M.q_rotate(att, M.v3(s[3], s[4], s[5]))
			rows.append({t = snappedf(session.sim.time(), 0.001), height_gain_m = snappedf(-s[2] - h0, 0.01),
				airspeed = snappedf(air.V, 0.01), alpha_deg = snappedf(rad_to_deg(air.alpha), 0.01),
				pitch_deg = snappedf(rad_to_deg(euler[1]), 0.1), roll_deg = snappedf(rad_to_deg(euler[2]), 0.1),
				path_deg = snappedf(rad_to_deg(atan2(-v_ned[2], sqrt(v_ned[0] * v_ned[0] + v_ned[1] * v_ned[1]))), 0.1),
				q = snappedf(s[RB.RATE + 1], 0.001), throttle = snappedf(session.commands.throttle, 0.001)})
	var result := {seconds = session.sim.time(), complete = session.sim.tick == end_tick, crashed = not session.crash.is_empty(),
		trim_throttle = trim_throttle, first_inverted_s = first_inverted, max_abs_q = max_q, max_pitch_deg = max_pitch,
		final_height_gain_m = -session.sim.state[2] - h0, rows = rows}
	session.free()
	return result


func _run() -> void:
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(get_script().resource_path.get_base_dir().path_join("ugly-loop-inputs.json")))
	for row: Dictionary in fixture.samples:
		samples[int(row.tick)] = row
	# --production measures the shipped data unchanged (the post-correction record); the default reproduces the counterfactuals.
	var production := "--production" in OS.get_cmdline_user_args()
	var variants := []
	if production:
		variants.append({label = "production", frozen = AircraftData.load_file(PATH)})
	else:
		var apc_case: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../docs/research/flight-dynamics/climb-trim/apc12x6-comparison.json")).cases[0]
		var apc := {ct = apc_case.ct_table.value, cp = apc_case.cp_table.value}
		var probe := _session(_variant(PLAN_CG_X), false)
		if not probe.start.get("ok", false):
			print("BASE_TRIM_FAILED ", probe.start)
			quit(2)
			return
		var base: Dictionary = _stiffness(probe.aircraft.model, probe.start.state, probe._deflections(probe.sim.aux), probe.sim.aux[0])
		probe.free()
		var arp_geometric: float = PLAN_CG_X - (float(base.static_margin) - GEOMETRIC_MARGIN) * CHORD
		variants.append({label = "baseline", frozen = _variant(PLAN_CG_X)})
		variants.append({label = "apc12x6_prop", frozen = _variant(PLAN_CG_X, apc)})
		variants.append({label = "geometric_margin", frozen = _variant(arp_geometric)})
		variants.append({label = "apc12x6_plus_geometric_margin", frozen = _variant(arp_geometric, apc)})
	var reports := {}
	for v: Dictionary in variants:
		var frozen: Dictionary = v.frozen
		var s := _session(frozen, false)
		assert(s.start.get("ok", false), "trim failed " + v.label)
		var d: Dictionary = s._deflections(s.sim.aux)
		var report := {arp_x_m = float(frozen.model.reference.arp_le[0]), stability = _stiffness(s.aircraft.model, s.start.state, d, s.sim.aux[0]),
			modes = _modes(s.aircraft.model, s.start.state, d, s.sim.aux[0]), trim_throttle = s.commands.throttle,
			trim_elevator_up_deg = -rad_to_deg(d.elevator), trim_alpha_deg = rad_to_deg(s.start.alpha), flights = {}}
		s.free()
		for throttle: float in [0.5, 0.75, 1.0]:
			report.flights["calm_step_%d" % int(throttle * 100)] = _flight(frozen, {throttle = throttle, ticks = 9600})
		report.flights.owner_replay = _flight(frozen, {replay = true, ticks = int(fixture.last_tick)})
		reports[v.label] = report
		var summary := {label = v.label, static_margin = report.stability.static_margin, elevator_up_deg = report.trim_elevator_up_deg,
			trim_throttle = report.trim_throttle}
		for key: String in report.flights:
			var f: Dictionary = report.flights[key]
			summary[key] = {inverted_s = f.first_inverted_s, max_q = f.max_abs_q, max_pitch_deg = f.max_pitch_deg, seconds = f.seconds}
		print("ROOT_CAUSE_VARIANT ", JSON.stringify(summary))
	var output: String = ProjectSettings.globalize_path("res://../docs/research/flight-dynamics/climb-trim/"
		+ ("root-cause-correction.json" if production else "root-cause-variants.json"))
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output = argument.trim_prefix("--output=")
	var result := {method = "Normal 15 m/s start re-solved per variant. Calm steps hold the solved throttle for 2 s, then the target for 38 s at 300 m. owner_replay repeats the captured raw inputs in gentle weather from 30 m.",
		limits = "Shipped data after the D6e-R1 reference correction; estimated, not a measured margin. Torque roll, slipstream, inertia and mass inventory are unchanged." if production else "Counterfactuals, not calibrated replacements. The APC table is one 11149 rpm slice with the legacy rpm-lag law; the geometric margin moves only the moment reference. Lateral data, slipstream, inertia and mass inventory are unchanged.",
		source_sha256 = {aircraft = FileAccess.get_sha256(PATH), probe = FileAccess.get_sha256(get_script().resource_path)},
		geometric_margin_target = GEOMETRIC_MARGIN, variants = reports}
	var file := FileAccess.open(output, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(result, "\t") + "\n")
	print("ROOT_CAUSE_RESULT ", output)
	quit(0)
