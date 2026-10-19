# D10-R4 (2026-10-18): long pro-spin hold, read-only. Same entry as the flight-test card's spin (trimmed at 1.2 Vs, then
# idle, full up and full rudder from 0.25 s), held for --hold seconds to see whether the developed spin settles beyond
# the card's 4.0-6.25 s window. --aileron adds a pro-spin (positive) or anti-spin (negative) aileron fraction.
# Prints window means as Markdown and writes a 4 Hz CSV. The vertical-force coefficient m(g - a_sink)/(q_sink S) uses
# the sink rate and its slope in the window; it equals 2(W/S)g/(rho V_sink^2) in a steady spin.
# Run from the repository root:
#   godot --headless --path app --audio-driver Dummy --script "$PWD/research/flight-dynamics/spin-post-stall/long_spin.gd" \
#     -- --aircraft=gp-extra-300s-60 [--hold=20] [--side=1] [--aileron=0] [--vs=<m/s>] [--out=tmp/spin.csv]
# --data=<absolute JSON path> flies that aircraft file instead of the catalog entry, e.g. a D8b-R2 wing-polar candidate
# (research/flight-robustness/d8b-r2/candidates/*.json); --aircraft then only labels the output.
extends SceneTree

const FlightSession := preload("res://sim/flight_session.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const RB := preload("res://physics/rigid_body.gd")
const P := preload("../../flight-test/pilot.gd")

const G := 9.80665
const RHO := 1.225
const START_ALTITUDE := 900.0 # m: a 20 s spin loses 300-450 m
const FLOOR := 60.0
const SAMPLE_TICKS := 60 # 4 Hz at 240 Hz
const WINDOWS := [[4.0, 6.25], [6.25, 10.0], [10.0, 15.0], [15.0, 20.0], [20.0, 30.0]]


func _initialize() -> void:
	var aircraft_id := ""
	var hold := 20.0
	var side := 1.0
	var aileron := 0.0
	var vs := NAN
	var out := ""
	var data_path := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--aircraft="): aircraft_id = arg.trim_prefix("--aircraft=")
		elif arg.begins_with("--hold="): hold = float(arg.trim_prefix("--hold="))
		elif arg.begins_with("--side="): side = signf(float(arg.trim_prefix("--side=")))
		elif arg.begins_with("--aileron="): aileron = clampf(float(arg.trim_prefix("--aileron=")), -1.0, 1.0)
		elif arg.begins_with("--vs="): vs = float(arg.trim_prefix("--vs="))
		elif arg.begins_with("--out="): out = arg.trim_prefix("--out=")
		elif arg.begins_with("--data="): data_path = arg.trim_prefix("--data=")
	var entry: Dictionary = Catalog.entry(aircraft_id)
	if not data_path.is_empty():
		if not data_path.is_absolute_path() or not FileAccess.file_exists(data_path):
			printerr("--data needs an absolute path to an existing aircraft JSON")
			quit(2)
			return
		entry = { data = data_path }
	if entry.is_empty() or side == 0.0 or not hold > 0.0:
		printerr("usage: -- --aircraft=<catalog id> [--hold=s] [--side=+1|-1] [--aileron=f] [--vs=m/s] [--out=csv]")
		quit(2)
		return
	var session: Node = FlightSession.new()
	session.setup(entry.data)
	root.add_child(session)
	session.input_enabled = false
	session.crash_auto_restart = false
	var field: Dictionary = FieldLoader.load_from(FieldLoader.DEFAULT_PATH)
	if not session.aircraft.get("ok", false) or not session.start.get("ok", false) or not session.set_field(field.get("field", field)):
		printerr("session setup failed")
		quit(1)
		return
	var model: Dictionary = session.aircraft.model
	var area: float = float(model.reference.S)
	var span: float = float(model.reference.b)
	var mass: float = float(model.mass_kg)
	if is_nan(vs):
		vs = sqrt(2.0 * mass * G / (RHO * area * float(model.envelope.get("CL_max", 1.0))))
	session.start_choice = FlightSession.START_AIRBORNE
	var speed := 1.2 * vs
	var trim: Dictionary = session.trim_at(speed, "level")
	while not trim.ok and speed < 2.0 * vs:
		speed *= 1.05
		trim = session.trim_at(speed, "level")
	if not trim.ok:
		printerr("no level trim up to 2 Vs: ", trim.get("message", ""))
		quit(1)
		return
	session.set_start_altitude(START_ALTITUDE)
	session.reset()
	if not session.is_flyable() or not session.sim.fault_reason.is_empty():
		printerr("start failed: ", session.start_error, " ", session.sim.fault_reason)
		quit(1)
		return
	var sim: Node = session.sim
	var dt: float = sim.dt()
	var rows: Array[PackedFloat64Array] = []
	var stop := ""
	for k in roundi((hold + 0.25) / dt) + 1:
		var t: float = k * dt
		var s: PackedFloat64Array = sim.state
		if k % SAMPLE_TICKS == 0:
			rows.append(_sample(t, s))
		if P.altitude(s) < FLOOR:
			stop = "floor at %.2f s" % t
			break
		var spin := t >= 0.25
		session.commands = { roll = aileron * side if spin else 0.0, pitch = 1.0 if spin else 0.0,
			yaw = side if spin else 0.0, throttle = 0.0 }
		sim.inputs = session._inputs()
		sim.step()
		if not sim.fault_reason.is_empty():
			stop = "fault: " + sim.fault_reason
			break
	if not data_path.is_empty():
		print("data: %s (wing polar: %s)" % [data_path, "tabulated" if model.get("envelope", {}).has("wing_polar") else "legacy blend"])
	print("%s: %.2f kg, S %.3f m2, b %.3f m, W/S %.2f kg/m2, entry %.2f m/s (Vs %.2f), side %+.0f, aileron %+.2f, hold %.1f s%s" % [
		aircraft_id, mass, area, span, mass / area, speed, vs, side, aileron, hold, ("; " + stop) if stop != "" else ""])
	print("| Window (s) | α (°) | \\|β\\| (°) | V (m/s) | \\|p\\| (°/s) | \\|r\\| (°/s) | θ (°) | Ωb/2V | Sink (m/s) | Sink slope (m/s²) | Vertical-force coeff. |")
	print("| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |")
	for w in WINDOWS:
		var sel := rows.filter(func(r: PackedFloat64Array) -> bool: return r[0] >= w[0] and r[0] <= w[1])
		if sel.size() < 3:
			continue
		var sink_rate := -_slope(sel, 0, 1)
		var sink_accel := _slope_of_sink(sel)
		var coeff := mass * (G - sink_accel) / (0.5 * RHO * sink_rate * sink_rate * area)
		var reduced := _mean(sel.map(func(r: PackedFloat64Array) -> float: return deg_to_rad(r[9]) * span / (2.0 * r[2])))
		print("| %.2f–%.2f | %.1f | %.1f | %.1f | %.0f | %.0f | %.0f | %.3f | %.1f | %.2f | %.2f |" % [w[0], w[1],
			_mean(sel.map(func(r: PackedFloat64Array) -> float: return r[3])),
			absf(_mean(sel.map(func(r: PackedFloat64Array) -> float: return r[4]))),
			_mean(sel.map(func(r: PackedFloat64Array) -> float: return r[2])),
			absf(_mean(sel.map(func(r: PackedFloat64Array) -> float: return r[5]))),
			absf(_mean(sel.map(func(r: PackedFloat64Array) -> float: return r[7]))),
			_mean(sel.map(func(r: PackedFloat64Array) -> float: return r[8])),
			reduced, sink_rate, sink_accel, coeff])
	if out != "":
		if not out.is_absolute_path():
			out = ProjectSettings.globalize_path("res://..").path_join(out)
		DirAccess.make_dir_recursive_absolute(out.get_base_dir())
		var file := FileAccess.open(out, FileAccess.WRITE)
		file.store_line("t_s,alt_m,speed_mps,alpha_deg,beta_deg,p_dps,q_dps,r_dps,pitch_deg,omega_dps,roll_deg,earth_yaw_rate_dps")
		for r in rows:
			file.store_line(",".join(Array(r).map(func(x: float) -> String: return "%.4f" % x)))
		file.close()
	session.free()
	quit(0)


## [t, altitude, airspeed, α°, β°, p, q, r (°/s), pitch°, |ω| (°/s), roll°, earth-vertical yaw rate (°/s)]
static func _sample(t: float, s: PackedFloat64Array) -> PackedFloat64Array:
	var e := P.euler(s)
	var p := s[RB.RATE]
	var q := s[RB.RATE + 1]
	var r := s[RB.RATE + 2]
	var up := P.up_body(s)
	return PackedFloat64Array([t, P.altitude(s), P.speed(s), rad_to_deg(P.alpha(s)), rad_to_deg(P.beta(s)),
		rad_to_deg(p), rad_to_deg(q), rad_to_deg(r), rad_to_deg(e[1]), rad_to_deg(sqrt(p * p + q * q + r * r)),
		rad_to_deg(e[2]), rad_to_deg(-(p * up[0] + q * up[1] + r * up[2]))])


static func _mean(values: Array) -> float:
	var total := 0.0
	for v in values:
		total += float(v)
	return total / maxf(values.size(), 1.0)


## Least-squares slope of column y against column x over the rows.
static func _slope(rows: Array, x: int, y: int) -> float:
	var mx := _mean(rows.map(func(r: PackedFloat64Array) -> float: return r[x]))
	var my := _mean(rows.map(func(r: PackedFloat64Array) -> float: return r[y]))
	var num := 0.0
	var den := 0.0
	for r: PackedFloat64Array in rows:
		num += (r[x] - mx) * (r[y] - my)
		den += (r[x] - mx) * (r[x] - mx)
	return num / den if den > 0.0 else 0.0


## Slope of the sink rate (from successive altitude samples) against time: positive while the descent accelerates.
static func _slope_of_sink(rows: Array) -> float:
	var sinks: Array = []
	for i in range(1, rows.size()):
		var a: PackedFloat64Array = rows[i - 1]
		var b: PackedFloat64Array = rows[i]
		sinks.append(PackedFloat64Array([0.5 * (a[0] + b[0]), -(b[1] - a[1]) / (b[0] - a[0])]))
	return _slope(sinks, 0, 1)
