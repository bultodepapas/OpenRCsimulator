# D6-TRIM-01 calibration probe: how far each catalog airplane departs hands-off with one out-of-trim axis at full scale,
# and whether the matching trim cancels it. Read-only use of FlightSession; writes one JSON report.
# "$(app/get-godot.sh)" --headless --path app --audio-driver Dummy --script "$PWD/research/flight-dynamics/out-of-trim/probe_out_of_trim.gd" -- --out=tmp/oot-probe [--aircraft=id,id] [--seconds=8]
extends SceneTree

const FlightSession := preload("res://sim/flight_session.gd")
const OutOfTrim := preload("res://sim/out_of_trim.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")

const ALTITUDE := 150.0
## Hands-off cases: an airframe draw (signed fractions of the full scale) and, optionally, the pilot trimming it out.
const CASES := [
	{name = "true", unit = [0.0, 0.0, 0.0], trimmed = false},
	{name = "roll+", unit = [1.0, 0.0, 0.0], trimmed = false},
	{name = "pitch+", unit = [0.0, 1.0, 0.0], trimmed = false},
	{name = "pitch-", unit = [0.0, -1.0, 0.0], trimmed = false},
	{name = "yaw+", unit = [0.0, 0.0, 1.0], trimmed = false},
	{name = "typical", unit = [0.625, -0.625, 0.625], trimmed = false},
	{name = "typical trimmed", unit = [0.625, -0.625, 0.625], trimmed = true},
]


func _initialize() -> void:
	var out_dir := "tmp/oot-probe"
	var seconds := 8.0
	var only := PackedStringArray()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.substr(6)
		elif arg.begins_with("--seconds="):
			seconds = float(arg.substr(10))
		elif arg.begins_with("--aircraft="):
			only = arg.substr(11).split(",")
	var report := {probe = "D6-TRIM-01 v1", full_scale_deg = OutOfTrim.FULL_SCALE_DEG, seconds = seconds, aircraft = {}}
	for id: String in Catalog.ids():
		if Catalog.is_rotorcraft(id) or not Catalog.can_fly(id) or (not only.is_empty() and not only.has(id)):
			continue
		var rows := {}
		for case: Dictionary in CASES:
			rows[case.name] = _fly(id, case, seconds)
		report.aircraft[id] = rows
		_print_rows(id, rows)
	var path := ProjectSettings.globalize_path("res://").path_join("..").path_join(out_dir)
	DirAccess.make_dir_recursive_absolute(path)
	var file := FileAccess.open(path.path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  ", false))
	file.close()
	print("report: ", path.path_join("report.json"))
	quit(0)


func _fly(id: String, case: Dictionary, seconds: float) -> Dictionary:
	var session: Node = FlightSession.new()
	session.trim_throttle = FlightSession.CRUISE_TRIM_THROTTLE # like Home: trimmed level at half throttle
	session.start_choice = FlightSession.START_AIRBORNE
	session.setup(Catalog.data_for(id, Catalog.default_battery_mode(id)), id)
	root.add_child(session)
	session.input_enabled = false
	session.crash_auto_restart = false
	var field: Dictionary = FieldLoader.load_from(FieldLoader.DEFAULT_PATH)
	session.set_field(field.get("field", field))
	session.set_start_altitude(ALTITUDE)
	var unit := PackedFloat64Array(case.unit)
	var airframes := {probe = {unit = unit, intensity_percent = 100, pilot_trim = PackedFloat64Array([0.0, 0.0, 0.0])}}
	if case.trimmed:
		var offsets: PackedFloat64Array = OutOfTrim.offsets(unit, 100, session.throws_deg())
		airframes.probe.pilot_trim = PackedFloat64Array([-offsets[0], -offsets[1], -offsets[2]])
	var config := {enabled = true, intensity_percent = 100, mode = OutOfTrim.MODE_FIRST_FLIGHT}
	if not session.setup_out_of_trim(config, 1, airframes, "probe"):
		return {ok = false, message = session.out_of_trim_error}
	session.reset()
	if not session.is_flyable():
		var refused := {ok = false, message = "%s %s" % [session.start_error, session.pause_reason]}
		session.free()
		return refused
	var sim: Node = session.sim
	var dt: float = sim.dt()
	var start_state: PackedFloat64Array = sim.state.duplicate()
	var e0: PackedFloat64Array = _euler(start_state)
	var v0: float = float(session.air_data(start_state).V)
	var throttle: float = float(session.start.get("throttle", 0.5))
	var marks := {}
	var peak_nz := 0.0
	var mass: float = session.aircraft.model.mass_kg
	for k in roundi(seconds / dt):
		session.commands = {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = throttle}
		sim.inputs = session._inputs()
		session._physics_process(dt)
		if not session.crash.is_empty() or not sim.fault_reason.is_empty():
			break
		sim.step()
		if sim.last_loads.size() >= 3:
			peak_nz = maxf(peak_nz, absf(-sim.last_loads[2] / (mass * 9.80665) - 1.0))
		var t: float = (k + 1) * dt
		for mark: float in [2.0, 5.0, seconds]:
			if is_equal_approx(t, mark):
				var s: PackedFloat64Array = sim.state
				var e: PackedFloat64Array = _euler(s)
				marks[str(mark)] = {
					bank_deg = rad_to_deg(e[2]), pitch_change_deg = rad_to_deg(e[1] - e0[1]),
					heading_change_deg = rad_to_deg(wrapf(e[0] - e0[0], -PI, PI)),
					height_change_m = start_state[RB.POS + 2] - s[RB.POS + 2],
					airspeed_change_mps = float(session.air_data(s).V) - v0,
				}
	var status: Dictionary = session.out_of_trim_status()
	var result := {ok = true, offset = Array(status.offset), offset_deg = status.offset_deg, v0_mps = v0,
		peak_delta_nz = peak_nz, marks = marks, crashed = not session.crash.is_empty()}
	session.free()
	return result


static func _euler(s: PackedFloat64Array) -> PackedFloat64Array:
	return M.q_to_euler(M.quat(s[RB.ATT], s[RB.ATT + 1], s[RB.ATT + 2], s[RB.ATT + 3]))


func _print_rows(id: String, rows: Dictionary) -> void:
	print("== %s" % id)
	for name: String in rows:
		var row: Dictionary = rows[name]
		if not row.ok:
			print("  %-16s refused: %s" % [name, row.message])
			continue
		var line := "  %-16s off° a%+.2f e%+.2f r%+.2f |dnz| %.2f" % [name, row.offset_deg.aileron, row.offset_deg.elevator, row.offset_deg.rudder, row.peak_delta_nz]
		for mark: String in row.marks:
			var m: Dictionary = row.marks[mark]
			line += "  | t%s φ%+6.1f Δθ%+6.1f Δψ%+6.1f Δh%+6.1f ΔV%+5.1f" % [mark, m.bank_deg, m.pitch_change_deg, m.heading_change_deg, m.height_change_m, m.airspeed_change_mps]
		print(line)
