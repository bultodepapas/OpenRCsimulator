# FT-01: a generic flight-test card for any fixed-wing catalog aircraft, flown through the real session loop (servos,
# aero, propulsion, slipstream, gear, field surfaces and crash checks). Each test starts from the session's own trimmed
# airborne start or its qualified runway start, flies a closed-loop test pilot (pilot.gd), records a trace and derives
# metrics. Every test reports whether its pilot did what the card asks (target reached, controls saturated, crash):
# a failed pilot is reported as such, never as an airplane property. Software evidence, not physical validation.
# FT-04 (card v4) appends aerobatic and inverted (card_aerobatics.gd), power-off (card_power.gd), stall and spin
# (card_stalls.gd) and runway (card_field.gd) tests after the v3 tests, which run exactly as before.
#
# Run (repository root):
#   <godot> --headless --path app --audio-driver Dummy --script "$PWD/research/flight-test/flight_test.gd" -- \
#       --aircraft=p51d-mustang-120 --out=tmp/flight-test [--only=vmax,roll] [--full-traces]
# Writes <out>/<aircraft>/profile.json, profile.md and one 20 Hz CSV per flown test (--full-traces: every tick).
# --list prints the fixed-wing catalog IDs the card can fly and exits. Table rows carry a stable `case` ID so two
# profiles compare case by case (research/flight-test/compare.py).
extends SceneTree

const FlightSession := preload("res://sim/flight_session.gd")
const Recorder := preload("res://sim/recorder.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const Propulsion := preload("res://physics/propulsion.gd")
const Ground := preload("res://physics/ground_contact.gd")
const FlightModes := preload("res://physics/flight_modes.gd")
const Aero := preload("res://physics/aero.gd")
const Air := preload("res://physics/air_data.gd")
const GroundEffect := preload("res://physics/ground_effect.gd")
const RB := preload("res://physics/rigid_body.gd")
const P := preload("pilot.gd")
const Acro := preload("card_aerobatics.gd")
const Power := preload("card_power.gd")
const Stalls := preload("card_stalls.gd")
const Runway := preload("card_field.gd")

const G := 9.80665
const RHO := 1.225
const VERSION := "ft-card-v4"
const HIGH := 250.0 # m, airborne tests that may lose height
const CSV_EVERY := 12 # 240 Hz ticks per committed CSV row (20 Hz)

var session: Node
var model: Dictionary
var aircraft_id := ""
var out_dir := ""
var only: PackedStringArray = []
var full_traces := false
var diagnostics := false
var v_start := 0.0
var vs_estimate := 0.0
var vs := 0.0 # measured power-off stall speed, else the CL_max estimate
var vmax := 0.0 # measured full-throttle level speed, else the trim-sweep limit
var a1 := 0.0 # solved stall start (rad)
var n1 := 0.0 # solved negative stall start, magnitude (rad)
var results := {}
var order: Array[String] = []
var _flight_notes: Array = [] # start substitutions and floor stops of the current test, merged into its notes
const FLOOR := 60.0 # m: airborne tests stop here instead of flying into the ground


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--list":
			_list()
			return
		if arg.begins_with("--aircraft="):
			aircraft_id = arg.substr(11)
		elif arg.begins_with("--out="):
			out_dir = arg.substr(6)
		elif arg.begins_with("--only="):
			only = arg.substr(7).split(",")
		elif arg == "--full-traces":
			full_traces = true
		elif arg == "--diagnostics":
			diagnostics = true
	if aircraft_id.is_empty() or out_dir.is_empty():
		push_error("usage: -- --aircraft=<catalog id> --out=<dir>")
		quit(2)
		return
	var entry: Dictionary = Catalog.entry(aircraft_id)
	if entry.is_empty():
		push_error("unknown catalog aircraft: " + aircraft_id)
		quit(2)
		return
	session = FlightSession.new()
	session.setup(entry.data)
	root.add_child(session)
	session.input_enabled = false
	session.crash_auto_restart = false
	var field: Dictionary = FieldLoader.load_from(FieldLoader.DEFAULT_PATH)
	if not session.aircraft.get("ok", false) or not session.start.get("ok", false) or not session.set_field(field.get("field", field)):
		push_error("session setup failed: %s %s" % [session.start.get("message", ""), session.surface_error])
		quit(2)
		return
	if session._weather.has_turbulence():
		push_error("flight tests need calm, steady weather")
		quit(2)
		return
	model = session.aircraft.model
	v_start = float(model.start_speed)
	a1 = float(model.envelope.get("a1", deg_to_rad(12.0)))
	n1 = float(model.envelope.get("n1", deg_to_rad(10.0)))
	var cl_max: float = float(model.envelope.get("CL_max", 1.0))
	vs_estimate = sqrt(2.0 * model.mass_kg * G / (RHO * float(model.reference.S) * cl_max))
	vs = vs_estimate
	vmax = 2.0 * v_start
	out_dir = out_dir.path_join(aircraft_id)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir) if out_dir.begins_with("res://") or out_dir.begins_with("user://") else out_dir)
	print("FT %s: %.2f kg, S %.3f m2, start %.1f m/s, CL_max %.2f -> Vs estimate %.1f m/s" % [aircraft_id, model.mass_kg, model.reference.S, v_start, cl_max, vs_estimate])
	_run("trim_sweep", _trim_sweep)
	_run("stall_power_off", _stall_power_off)
	_run("vmax", _vmax)
	_run("modes", _modes)
	_run("aero_sweep", _aero_sweep)
	_run("stall_power_on", _stall_power_on)
	_run("throttle_response", _throttle_response)
	_run("hands_off", _hands_off)
	_run("climb", _climb)
	_run("glide", _glide)
	_run("roll_rate", _roll_rate)
	_run("pitch_pull", _pitch_pull)
	_run("loop", _loop)
	_run("turn_60", _turn_60)
	_run("rudder_step", _rudder_step)
	_run("knife_edge", _knife_edge)
	_run("knife_edge_full_rudder", _knife_edge_full_rudder)
	_run("inverted", _inverted)
	_run("spin", _spin)
	_run("takeoff", _takeoff)
	_run("landing", _landing)
	# Card v4 (FT-04): appended after the v3 tests, which run exactly as before; each group lives in its own file.
	_run("inverted_speeds", func() -> Dictionary: return Acro.inverted_speeds(self))
	_run("inverted_turn", func() -> Dictionary: return Acro.inverted_turn(self))
	_run("immelmann", func() -> Dictionary: return Acro.immelmann(self))
	_run("split_s", func() -> Dictionary: return Acro.split_s(self))
	_run("outside_loop", func() -> Dictionary: return Acro.outside_loop(self))
	_run("slow_roll", func() -> Dictionary: return Acro.slow_roll(self))
	_run("point_roll", func() -> Dictionary: return Acro.point_roll(self))
	_run("snap_roll", func() -> Dictionary: return Acro.snap_roll(self))
	_run("stall_turn", func() -> Dictionary: return Acro.stall_turn(self))
	_run("engine_cut_climb", func() -> Dictionary: return Power.engine_cut_climb(self))
	_run("glide_turn", func() -> Dictionary: return Power.glide_turn(self))
	_run("stall_turning", func() -> Dictionary: return Stalls.stall_turning(self))
	_run("stall_cross_controlled", func() -> Dictionary: return Stalls.stall_cross_controlled(self))
	_run("stall_held", func() -> Dictionary: return Stalls.stall_held(self))
	_run("stall_inverted", func() -> Dictionary: return Stalls.stall_inverted(self))
	_run("spin_inverted", func() -> Dictionary: return Stalls.spin_inverted(self))
	_run("dead_stick_landing", func() -> Dictionary: return Runway.dead_stick_landing(self))
	_run("go_around", func() -> Dictionary: return Runway.go_around(self))
	_write_report()
	quit(0)


## Fixed-wing catalog aircraft: the ones whose data a FlightSession accepts with a trimmed start.
func _list() -> void:
	for id in Catalog.ids():
		var probe := FlightSession.new()
		probe.setup(Catalog.entry(id).data)
		root.add_child(probe)
		if probe.aircraft.get("ok", false) and probe.start.get("ok", false):
			print("FT-AIRCRAFT " + id)
		probe.queue_free()
	quit(0)


func _run(name: String, test: Callable) -> void:
	if not only.is_empty() and not only.has(name):
		return
	var started := Time.get_ticks_msec()
	_flight_notes = []
	var r: Dictionary = test.call()
	var notes: Array = r.get("notes", [])
	for note in _flight_notes:
		if not notes.has(note):
			notes.append(note)
	r.notes = notes
	r.wall_s = (Time.get_ticks_msec() - started) / 1000.0
	results[name] = r
	order.append(name)
	print("FT %-24s %s %s" % [name, "valid" if r.get("valid", false) else "INVALID", JSON.stringify(r.get("metrics", {}))])
	for note in r.get("notes", []):
		print("   note: " + str(note))


# --- Flying -------------------------------------------------------------------------------------------------------

## Starts from the session's trimmed airborne start at `speed` and `altitude`, or its runway start, then calls
## pilot(t, s, ctx) -> { roll, pitch, yaw (sticks added to the trims), throttle (absolute) } every tick until `seconds`
## or stop(t, s, ctx). Returns { trace, crashed, ctx, ok, message, dt, t_end }.
func _fly(name: String, start: Dictionary, seconds: float, pilot: Callable, stop := Callable()) -> Dictionary:
	var runway: bool = start.get("runway", false)
	if runway:
		session.start_choice = FlightSession.START_RUNWAY
	else:
		session.start_choice = FlightSession.START_AIRBORNE
		# A trim that fails at the requested speed starts at the nearest faster trimmable one, and says so.
		var speed: float = start.speed
		var trim: Dictionary = session.trim_at(speed, "level")
		while not trim.ok and speed < maxf(1.6 * float(start.speed), v_start):
			speed *= 1.05
			trim = session.trim_at(speed, "level")
		if not trim.ok:
			return { ok = false, message = "trim at %.1f m/s failed: %s" % [start.speed, trim.message] }
		if speed != start.speed:
			_note("%s: no trim at %.1f m/s, started at %.1f m/s" % [name, start.speed, speed])
		session.set_start_altitude(start.get("altitude", HIGH))
		if start.has("north"):
			var placed: PackedFloat64Array = session.start.state
			placed[RB.POS] = start.north
			placed[RB.POS + 1] = start.east
			session.start.state = placed
	session.reset()
	if not session.is_flyable() or not session.sim.fault_reason.is_empty() or not session.start_error.is_empty():
		return { ok = false, message = "start failed: %s %s %s" % [session.start_error, session.pause_reason, session.sim.fault_reason] }
	if runway and session.glow_is_active() and not session.engine_running and not session.glow_start():
		return { ok = false, message = "glow engine did not start on the runway" }
	if start.get("gear_down", false) and session.gear_is_retractable():
		# Down and locked from the start, as on final approach (the P-51 envelope fixture does the same).
		session._gear_requested_down = true
		var aux: PackedFloat64Array = session.sim.aux
		aux[session.gear_aux_index()] = 1.0
		aux[session.gear_aux_index() + 1] = 1.0
		session.sim.aux = aux
	var sim: Node = session.sim
	var rec := Recorder.new(sim, session.electrical_state)
	var metadata: Dictionary = { flight_test = VERSION, test = name, aircraft = aircraft_id }
	if session.electrical_state().get("ok", false) or session.flaps_available() or session.gear_is_retractable():
		metadata = session.trace_meta()
		metadata.flight_test = VERSION
		metadata.test = name
	rec.start(metadata)
	var ctx := { start_throttle = float(session.start.get("throttle", 0.0)) }
	var aero_rows := PackedStringArray()
	if diagnostics:
		aero_rows.append(_aero_diagnostic(0.0))
	var crashed := ""
	var dt: float = sim.dt()
	var t := 0.0
	for k in roundi(seconds / dt):
		t = k * dt
		var s: PackedFloat64Array = sim.state
		ctx.ay = sim.last_loads[1] / (model.mass_kg * G) if sim.last_loads.size() >= 2 else 0.0
		var c: Dictionary = pilot.call(t, s, ctx)
		for axis in ["roll", "pitch", "yaw"]:
			var raw: PackedFloat64Array = ctx.get("raw_" + axis, PackedFloat64Array())
			raw.append(clampf(c.get(axis, 0.0), -1.0, 1.0))
			ctx["raw_" + axis] = raw
		session.commands = { roll = clampf(c.get("roll", 0.0), -1.0, 1.0), pitch = clampf(c.get("pitch", 0.0), -1.0, 1.0),
			yaw = clampf(c.get("yaw", 0.0), -1.0, 1.0), throttle = clampf(c.get("throttle", ctx.start_throttle), 0.0, 1.0) }
		sim.inputs = session._inputs()
		session._physics_process(dt)
		if not session.crash.is_empty():
			crashed = str(session.pause_reason)
			break
		if not sim.fault_reason.is_empty():
			crashed = "simulation fault: " + sim.fault_reason
			break
		sim.step()
		if diagnostics and (k + 1) % CSV_EVERY == 0:
			aero_rows.append(_aero_diagnostic((k + 1) * dt))
		if stop.is_valid() and stop.call(t, sim.state, ctx):
			break
		if not runway and P.altitude(sim.state) < float(start.get("floor", FLOOR)):
			ctx.floor_t = t
			_note("%s%s: stopped at the %.0f m floor after %.1f s" % [name, "" if not ctx.has("suffix") else " " + str(ctx.suffix), float(start.get("floor", FLOOR)), t])
			break
	rec.detach()
	_save_trace(name + ("" if not ctx.has("suffix") else "_" + str(ctx.suffix)), rec.trace)
	if diagnostics:
		_save_aero_diagnostics(name + ("" if not ctx.has("suffix") else "_" + str(ctx.suffix)), aero_rows)
	return { ok = true, trace = rec.trace, crashed = crashed, ctx = ctx, dt = dt, t_end = t }


## --diagnostics: the aerodynamic state at the current tick, recomputed read-only with the session's own inputs (state,
## servo deflections, air density, wind, downwash lag, ground height): α, β, speed, the production local-flow and
## sideslip weights, and body-axis coefficients from the oracle, the local model and the blended production loads.
## `lerp_residual` is |blended − (oracle + w·(local − oracle))| (largest component, N or N·m); production blends exactly
## that way except with flaps, whose clean/flapped split it does not reproduce.
func _aero_diagnostic(t: float) -> String:
	var s: PackedFloat64Array = session.sim.state
	var a: PackedFloat64Array = session.sim.aux
	var rho: float = session.air_density(s)
	var air: Dictionary = Air.compute(s, session.wind_at(t), rho)
	var d: Dictionary = session._deflections(a)
	var lag: int = session.downwash_index()
	var downwash: float = a[lag] if lag >= 0 and lag < a.size() else NAN
	var ground_up: float = session._ground_up(s)
	var ge: PackedFloat64Array = GroundEffect.factors(s, model, ground_up)
	var oracle: PackedFloat64Array = Aero._global_loads(s, air, d, model, rho, downwash, ge)
	var local: PackedFloat64Array = Aero._local_loads(s, air, d, model, rho, downwash, null, ge)
	var blended: PackedFloat64Array = Aero.loads(s, air, d, model, rho, downwash, ground_up)
	var weight: float = Aero.local_flow_weight(s, air, d, model, downwash, ge)
	var speed: float = float(air.V)
	var qs: float = 0.5 * rho * speed * speed * float(model.reference.S)
	var lengths := [1.0, 1.0, 1.0, float(model.reference.b), float(model.reference.c), float(model.reference.b)]
	var residual := 0.0
	for i in 6:
		residual = maxf(residual, absf(blended[i] - (oracle[i] + weight * (local[i] - oracle[i]))))
	var row := PackedStringArray([String.num(t, 4), String.num(rad_to_deg(float(air.alpha)), 4), String.num(rad_to_deg(float(air.beta)), 4),
		String.num(speed, 4), String.num(weight, 4), String.num(Aero.sideslip_weight(float(air.beta), model.envelope), 4)])
	for loads in [oracle, local, blended]:
		for i in 6:
			row.append(String.num(loads[i] / (qs * lengths[i]), 6) if qs > 0.0 else "nan")
	row.append(String.num(residual, 9))
	return ",".join(row)


func _save_aero_diagnostics(name: String, rows: PackedStringArray) -> void:
	var header := PackedStringArray(["t_s", "alpha_deg", "beta_deg", "airspeed_mps", "local_weight", "sideslip_weight"])
	for source in ["oracle", "local", "blended"]:
		for c in ["CX", "CY", "CZ", "Cl", "Cm", "Cn"]:
			header.append("%s_%s" % [c, source])
	header.append("lerp_residual")
	var f := FileAccess.open(out_dir.path_join(name + ".aero.csv"), FileAccess.WRITE)
	if f != null:
		f.store_string("# %s %s aerodynamic diagnostics every %d ticks (research/flight-test --diagnostics)\n" % [aircraft_id, name, CSV_EVERY]
			+ ",".join(header) + "\n" + "\n".join(rows) + "\n")


## Engine failure the way the session's own source cut does it (SF-04): a glow engine through glow_cut(), any other
## source disabled. A running continuous turbine cannot be cut in flight (its hot rundown is AV-05b), so it stays at
## idle. Call it from a pilot callback, between ticks; the pilot then commands zero throttle. Returns what was done:
## "glow cut", "source off", "turbine idle (no hot cutoff, AV-05b)", or "" when the cut was refused.
func _cut_engine() -> String:
	if session.glow_is_active():
		return "glow cut" if session.glow_cut() else ""
	if session.turbine_is_continuous():
		return "turbine idle (no hot cutoff, AV-05b)"
	session.engine_running = false
	return "source off"


func _note(text: String) -> void:
	if not _flight_notes.has(text):
		_flight_notes.append(text)


func _save_trace(name: String, trace: RefCounted) -> void:
	var path := out_dir.path_join(name + ".csv")
	if full_traces:
		trace.save(path)
		return
	var columns: Array = trace.columns()
	var lines := PackedStringArray()
	for key in trace.meta:
		lines.append("# %s: %s" % [key, JSON.stringify(trace.meta[key])])
	lines.append("# rows: every %d ticks" % CSV_EVERY)
	lines.append(",".join(columns))
	for r in range(0, trace.row_count(), CSV_EVERY):
		var row := PackedStringArray()
		for c in columns:
			row.append(String.num(trace.value(r, c), 6))
		lines.append(",".join(row))
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(lines) + "\n")


# --- Trace helpers ------------------------------------------------------------------------------------------------

static func _col(trace: RefCounted, column: String, r0 := 0, r1 := -1) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	var last: int = trace.row_count() if r1 < 0 else mini(r1, trace.row_count())
	for r in range(r0, last):
		out.append(trace.value(r, column))
	return out


static func _max(a: PackedFloat64Array) -> float:
	var m := -INF
	for x in a:
		m = maxf(m, x)
	return m


static func _min(a: PackedFloat64Array) -> float:
	var m := INF
	for x in a:
		m = minf(m, x)
	return m


static func _mean(a: PackedFloat64Array) -> float:
	var s := 0.0
	for x in a:
		s += x
	return s / maxf(a.size(), 1)


static func _row_at(trace: RefCounted, t: float) -> int:
	return clampi(roundi(t / (trace.value(1, "t_s") - trace.value(0, "t_s"))) if trace.row_count() > 1 else 0, 0, trace.row_count() - 1)


## Fraction of the pilot's own commands (sticks before the radio trims) on an axis in [r0, r1) at |cmd| ≥ 0.98.
static func _saturated(ctx: Dictionary, axis: String, r0: int, r1: int) -> float:
	var raw: PackedFloat64Array = ctx.get("raw_" + axis, PackedFloat64Array())
	var n := 0
	var hit := 0
	for r in range(r0, mini(r1, raw.size())):
		n += 1
		hit += int(absf(raw[r]) >= 0.98)
	return float(hit) / maxf(n, 1)


static func _alpha_deg(trace: RefCounted, r: int) -> float:
	return rad_to_deg(atan2(trace.value(r, "w_mps"), trace.value(r, "u_mps")))


static func _beta_deg(trace: RefCounted, r: int) -> float:
	var u: float = trace.value(r, "u_mps")
	var w: float = trace.value(r, "w_mps")
	return rad_to_deg(atan2(trace.value(r, "v_mps"), sqrt(u * u + w * w)))


func _load_factor(trace: RefCounted, r: int) -> float:
	return -trace.value(r, "Fz_N") / (model.mass_kg * G)


## Slope of a column against time over [r0, r1) by least squares (units per second).
static func _slope(trace: RefCounted, column: String, r0: int, r1: int) -> float:
	var n := 0.0
	var st := 0.0
	var sy := 0.0
	var stt := 0.0
	var sty := 0.0
	for r in range(r0, mini(r1, trace.row_count())):
		var t: float = trace.value(r, "t_s")
		var y: float = trace.value(r, column)
		n += 1.0
		st += t
		sy += y
		stt += t * t
		sty += t * y
	var d := n * stt - st * st
	return (n * sty - st * sy) / d if d != 0.0 else 0.0


## Mean rate (deg/s) of the ground track over [r0, r1): the turn rate, from positions only.
static func _track_rate(trace: RefCounted, r0: int, r1: int) -> float:
	var last: int = mini(r1, trace.row_count()) - 1
	var total := 0.0
	var previous := NAN
	for r in range(r0, last):
		var track := rad_to_deg(atan2(trace.value(r + 1, "east_m") - trace.value(r, "east_m"), trace.value(r + 1, "north_m") - trace.value(r, "north_m")))
		if not is_nan(previous):
			total += wrapf(track - previous, -180.0, 180.0)
		previous = track
	return total / (trace.value(last, "t_s") - trace.value(r0 + 1, "t_s"))


## Mean rate (deg/s) of an angle column over [r0, r1), unwrapping its ±180° seam.
static func _unwrapped_rate(trace: RefCounted, column: String, r0: int, r1: int) -> float:
	var total := 0.0
	var last: int = mini(r1, trace.row_count()) - 1
	for r in range(r0, last):
		total += wrapf(trace.value(r + 1, column) - trace.value(r, column), -180.0, 180.0)
	return total / (trace.value(last, "t_s") - trace.value(r0, "t_s"))


func _result(valid: bool, metrics: Dictionary, notes: Array, extra := {}) -> Dictionary:
	var r := { valid = valid, metrics = metrics, notes = notes }
	r.merge(extra)
	return r


func _failed(flight: Dictionary) -> Dictionary:
	return _result(false, {}, [str(flight.get("message", "flight failed"))])


# --- Tests --------------------------------------------------------------------------------------------------------

## Steady level trims on a fixed grid of start-speed multiples, from just above the stall estimate to the speed whose
## trim needs more than full throttle: the throttle/speed map.
func _trim_sweep() -> Dictionary:
	var rows := []
	var limit := NAN
	var first_failures := 0
	var step := 0
	while true:
		# Fixed grid of start-speed multiples (x0.50, x0.55, ...): identical cases across versions of the same aircraft.
		var factor := 0.5 + 0.05 * step
		var v := factor * v_start
		step += 1
		if factor > 4.0:
			break
		if v < 1.05 * vs_estimate:
			continue
		var t: Dictionary = session.trim_at(v, "level")
		if not t.ok or float(t.throttle) > 1.0:
			if rows.is_empty() and v < 1.5 * v_start:
				first_failures += 1 # slow trims that do not converge: keep looking for the first trimmable speed
				continue
			limit = v
			break
		rows.append({ case = "x%.2f" % factor, speed_mps = snappedf(v, 0.01), throttle = snappedf(float(t.throttle), 0.001), stick_pitch = snappedf(float(t.pitch_command), 0.001),
			alpha_deg = snappedf(rad_to_deg(P.alpha(t.state)), 0.01), rpm = roundi(float(t.get("rpm", 0.0))) })
	if is_finite(limit):
		vmax = limit
	session.trim_at(v_start, "level")
	var sweep_notes := [] if rows.size() > 3 else ["few trimmable points"]
	if first_failures > 0 and not rows.is_empty():
		sweep_notes.append("no level trim below %.1f m/s (%d slower speeds failed)" % [rows[0].speed_mps, first_failures])
	return _result(rows.size() > 3, { points = rows.size(), slowest_trim_mps = rows[0].speed_mps if not rows.is_empty() else NAN, first_untrimmable_mps = limit,
		cruise_throttle_at_start_speed = _interp(rows, v_start) }, sweep_notes, { table = rows })


static func _interp(rows: Array, v: float) -> float:
	for i in rows.size() - 1:
		if rows[i].speed_mps <= v and rows[i + 1].speed_mps >= v:
			var f: float = (v - rows[i].speed_mps) / (rows[i + 1].speed_mps - rows[i].speed_mps)
			return snappedf(lerpf(rows[i].throttle, rows[i + 1].throttle, f), 0.001)
	return NAN


## Power-off 1-g stall: idle, the pilot holds height with the elevator (slowing about 0.5-1.5 m/s per s), wings level,
## feet on the ball. The break is a 2 m/s sink or 20° of bank; then unload, wings level, full throttle, pull out.
func _stall_power_off() -> Dictionary:
	return _stall("stall_power_off", 0.0, false)


## Power-on stall: half throttle, nose raised 2°/s from the trimmed attitude, wings level, feet on the ball. For both,
## the break needs α within 1° of the solved stall start, so a pilot transient is not a stall.
func _stall_power_on() -> Dictionary:
	return _stall("stall_power_on", 0.5, true)


func _stall(name: String, throttle: float, ramp: bool) -> Dictionary:
	var entry := 1.4 * vs
	var alt0 := HIGH
	var flight := _fly(name, { speed = entry, altitude = alt0 }, 40.0, func(t: float, s: PackedFloat64Array, ctx: Dictionary) -> Dictionary:
		var k := P.schedule(s, v_start)
		var e := P.euler(s)
		if not ctx.has("pitch0"):
			ctx.pitch0 = e[1]
		if not ctx.has("break_t"):
			var broke: bool = t > 1.0 and P.alpha(s) > a1 - deg_to_rad(1.0) and (P.climb_rate(s) < -2.0 or absf(e[2]) > deg_to_rad(20.0))
			# A benign wing that only mushes: the elevator stays at its stop for 1 s with α near the stall start.
			var raw: PackedFloat64Array = ctx.get("raw_pitch", PackedFloat64Array())
			var at_stop: bool = raw.size() > 240 and P.alpha(s) > 0.8 * a1
			if at_stop:
				for j in range(raw.size() - 240, raw.size()):
					at_stop = at_stop and raw[j] >= 0.98
			if at_stop and not broke:
				broke = true
				ctx.break_kind = "elevator limit (mush)"
			if broke:
				ctx.break_t = t
				ctx.break_v = P.speed(s)
				ctx.break_alpha = P.alpha(s)
				ctx.break_bank = e[2]
			else:
				var pitch_cmd := P.pitch(s, float(ctx.pitch0) + deg_to_rad(2.0) * t, k, ctx, 1.0 / 240.0) if ramp else P.hold_altitude(s, alt0, k, ctx, 1.0 / 240.0)
				return { roll = P.bank(s, 0.0, k), pitch = pitch_cmd, yaw = P.ball(s, k, ctx, 1.0 / 240.0), throttle = throttle }
		# Recovery: unload to half the stall-start α, level the wings, full power; record the deepest bank.
		ctx.max_bank = maxf(float(ctx.get("max_bank", 0.0)), absf(e[2]))
		if t - float(ctx.break_t) < 1.0:
			ctx.max_bank_signed = e[2] if absf(e[2]) >= absf(float(ctx.get("max_bank_signed", 0.0))) else float(ctx.max_bank_signed)
		return { roll = P.bank(s, 0.0, k) if t - float(ctx.break_t) > 0.3 else 0.0, pitch = P.alpha_hold(s, 0.5 * a1, k, ctx, 1.0 / 240.0),
			yaw = P.ball(s, k, ctx, 1.0 / 240.0), throttle = 1.0 }, func(t: float, s: PackedFloat64Array, ctx: Dictionary) -> bool:
		if ctx.has("break_t") and t - float(ctx.break_t) > 1.5 and P.climb_rate(s) > 0.0 and P.speed(s) > 1.2 * float(ctx.break_v):
			ctx.recovered_t = t
			return true
		return false)
	if not flight.ok:
		return _failed(flight)
	var ctx: Dictionary = flight.ctx
	var trace: RefCounted = flight.trace
	var notes := []
	if flight.crashed != "":
		notes.append("crashed: " + flight.crashed)
	if not ctx.has("break_t"):
		notes.append("no stall break within 40 s")
		return _result(false, {}, notes)
	var r0 := _row_at(trace, float(ctx.break_t))
	var alt_min := _min(_col(trace, "alt_m", r0))
	var metrics := { stall_speed_mps = snappedf(ctx.break_v, 0.01), stall_alpha_deg = snappedf(rad_to_deg(ctx.break_alpha), 0.1),
		wing_drop = "left" if float(ctx.get("max_bank_signed", 0.0)) < 0.0 else "right", bank_in_first_second_deg = snappedf(rad_to_deg(float(ctx.get("max_bank_signed", 0.0))), 0.1),
		max_bank_in_recovery_deg = snappedf(rad_to_deg(float(ctx.get("max_bank", 0.0))), 0.1),
		altitude_lost_m = snappedf(trace.value(r0, "alt_m") - alt_min, 0.1),
		recovery_time_s = snappedf(float(ctx.get("recovered_t", NAN)) - float(ctx.break_t), 0.01), break_kind = str(ctx.get("break_kind", "wing drop or sink")),
		deceleration_before_break_mps2 = snappedf(-_slope(trace, "speed_mps", maxi(r0 - 480, 0), r0), 0.01),
		ratio_to_cl_max_estimate = snappedf(float(ctx.break_v) / vs_estimate, 0.001) }
	if not ctx.has("recovered_t"):
		notes.append("not recovered within the test time")
	var valid: bool = flight.crashed == "" and ctx.has("recovered_t")
	if name == "stall_power_off" and valid:
		vs = float(ctx.break_v)
	return _result(valid, metrics, notes)


## Maximum level speed and horizontal acceleration: full throttle from the start speed, height and wings held, feet on
## the ball, until the speed changes by less than 0.05 m/s per second over 3 s (or 60 s).
func _vmax() -> Dictionary:
	var alt0 := 150.0
	var flight := _fly("vmax", { speed = v_start, altitude = alt0 }, 60.0, func(t: float, s: PackedFloat64Array, ctx: Dictionary) -> Dictionary:
		var k := P.schedule(s, v_start)
		return { roll = P.bank(s, 0.0, k), pitch = P.hold_altitude(s, alt0, k, ctx, 1.0 / 240.0), yaw = P.ball(s, k, ctx, 1.0 / 240.0), throttle = 1.0 }, func(t: float, s: PackedFloat64Array, ctx: Dictionary) -> bool:
		var history: Array = ctx.get("history", [])
		if roundi(t * 240.0) % 24 == 0:
			history.append(P.speed(s))
			ctx.history = history
		return history.size() > 30 and absf(history[-1] - history[-31]) < 0.15)
	if not flight.ok:
		return _failed(flight)
	var trace: RefCounted = flight.trace
	var n: int = trace.row_count()
	var v_end: float = trace.value(n - 1, "speed_mps")
	var times := {}
	for gain in [5.0, 10.0]:
		for r in n:
			if trace.value(r, "speed_mps") >= v_start + gain:
				times[gain] = trace.value(r, "t_s")
				break
	var t90 := NAN
	for r in n:
		if trace.value(r, "speed_mps") >= v_start + 0.9 * (v_end - v_start):
			t90 = trace.value(r, "t_s")
			break
	var settled: bool = flight.t_end < 59.9
	var r_end := maxi(n - 720, 0) # the last 3 s, where the speed is read
	var alt_err := maxf(absf(_max(_col(trace, "alt_m", r_end)) - alt0), absf(_min(_col(trace, "alt_m", r_end)) - alt0))
	var alt_err_run := maxf(absf(_max(_col(trace, "alt_m")) - alt0), absf(_min(_col(trace, "alt_m")) - alt0))
	var notes := []
	if not settled:
		notes.append("still accelerating after 60 s")
	if alt_err > 5.0:
		notes.append("height at the end held only within %.1f m" % alt_err)
	if settled:
		vmax = v_end
	return _result(settled and flight.crashed == "" and alt_err <= 5.0, { max_level_speed_mps = snappedf(v_end, 0.01),
		max_level_speed_kmh = snappedf(v_end * 3.6, 0.1), rpm_at_max = roundi(trace.value(n - 1, "engine_rpm")),
		time_plus_5_mps_s = snappedf(times.get(5.0, NAN), 0.01), time_plus_10_mps_s = snappedf(times.get(10.0, NAN), 0.01),
		time_to_90_percent_s = snappedf(t90, 0.01), initial_acceleration_mps2 = snappedf(_slope(trace, "speed_mps", 0, 240), 0.01),
		height_error_end_m = snappedf(alt_err, 0.01), height_error_run_m = snappedf(alt_err_run, 0.01) }, notes)


## Throttle steps at the start speed: trimmed → full at 1 s, full → idle at 7 s, height and wings held.
func _throttle_response() -> Dictionary:
	var alt0 := 150.0
	var flight := _fly("throttle_response", { speed = v_start, altitude = alt0 }, 12.0, func(t: float, s: PackedFloat64Array, ctx: Dictionary) -> Dictionary:
		var k := P.schedule(s, v_start)
		var thr: float = ctx.start_throttle if t < 1.0 else (1.0 if t < 7.0 else 0.0)
		return { roll = P.bank(s, 0.0, k), pitch = P.hold_altitude(s, alt0, k, ctx, 1.0 / 240.0), yaw = P.ball(s, k, ctx, 1.0 / 240.0), throttle = thr })
	if not flight.ok:
		return _failed(flight)
	var trace: RefCounted = flight.trace
	var up := _rise(trace, 1.0, 7.0)
	var down := _rise(trace, 7.0, 12.0)
	return _result(flight.crashed == "", { rpm_trimmed = roundi(trace.value(_row_at(trace, 0.9), "engine_rpm")),
		rpm_full = roundi(trace.value(_row_at(trace, 6.9), "engine_rpm")), rpm_idle_end = roundi(trace.value(trace.row_count() - 1, "engine_rpm")),
		spool_up_10_90_s = up, spool_down_90_10_s = down,
		speed_gain_in_6_s_mps = snappedf(trace.value(_row_at(trace, 6.9), "speed_mps") - trace.value(_row_at(trace, 0.9), "speed_mps"), 0.01) }, [])


## 10 %-90 % time of the rpm change between t0 and t1.
func _rise(trace: RefCounted, t0: float, t1: float) -> float:
	var r0 := _row_at(trace, t0)
	var r1 := _row_at(trace, t1) - 1
	var a: float = trace.value(r0, "engine_rpm")
	var b: float = trace.value(r1, "engine_rpm")
	var t10 := NAN
	var t90 := NAN
	for r in range(r0, r1 + 1):
		var f: float = (trace.value(r, "engine_rpm") - a) / (b - a) if b != a else 1.0
		if is_nan(t10) and f >= 0.1:
			t10 = trace.value(r, "t_s")
		if is_nan(t90) and f >= 0.9:
			t90 = trace.value(r, "t_s")
	return snappedf(t90 - t10, 0.001)


## Full-throttle climb at 1.3, 1.6 and 2.0 Vs, speed held with the elevator (pitch up to 75°); rate from the last 7 of 25 s.
func _climb() -> Dictionary:
	return _steady_path("climb", 1.0)


## Idle glide at the same speeds: sink rate and L/D.
func _glide() -> Dictionary:
	return _steady_path("glide", 0.0)


func _steady_path(name: String, throttle: float) -> Dictionary:
	var rows := []
	var notes := []
	var valid := true
	for factor in [1.3, 1.6, 2.0]:
		var target: float = factor * vs
		if target >= 0.95 * vmax:
			continue
		var flight := _fly(name, { speed = target, altitude = HIGH }, 25.0, func(t: float, s: PackedFloat64Array, ctx: Dictionary) -> Dictionary:
			ctx.suffix = "%.1fVs" % factor
			var k := P.schedule(s, v_start)
			return { roll = P.bank(s, 0.0, k), pitch = P.hold_speed(s, target, k, ctx, 1.0 / 240.0), yaw = P.ball(s, k, ctx, 1.0 / 240.0), throttle = throttle })
		if not flight.ok:
			notes.append(flight.message)
			valid = false
			continue
		var trace: RefCounted = flight.trace
		var r0 := _row_at(trace, 18.0)
		var speeds := _col(trace, "speed_mps", r0)
		var rate := _slope(trace, "alt_m", r0, trace.row_count())
		var pitch_mean := _mean(_col(trace, "pitch_deg", r0))
		# Thrust above weight: the speed cannot fall to the target even near vertical. That is the result, not a pilot fault.
		var vertical: bool = name == "climb" and pitch_mean > 65.0 and _mean(speeds) > target
		var held: bool = (absf(_mean(speeds) - target) < 0.5 or vertical) and flight.crashed == ""
		valid = valid and held
		if vertical:
			notes.append("%.1f Vs: thrust exceeds the climb need; at %.0f° pitch it holds %.2f m/s, not %.2f" % [factor, pitch_mean, _mean(speeds), target])
		elif not held:
			notes.append("%.1f Vs: speed held at %.2f m/s, target %.2f" % [factor, _mean(speeds), target])
		var row := { case = "%.1fVs" % factor, speed_mps = snappedf(_mean(speeds), 0.01), vs_factor = factor, vertical_speed_mps = snappedf(rate, 0.01), pitch_deg = snappedf(pitch_mean, 0.1),
			path_angle_deg = snappedf(rad_to_deg(asin(clampf(rate / target, -1.0, 1.0))), 0.1), rpm = roundi(_mean(_col(trace, "engine_rpm", r0))) }
		if rate < 0.0:
			row.glide_ratio = snappedf(sqrt(maxf(_mean(speeds) ** 2 - rate * rate, 0.0)) / -rate, 0.01)
		rows.append(row)
	var best := {}
	for row in rows:
		if best.is_empty() or (row.vertical_speed_mps > best.vertical_speed_mps):
			best = row
	return _result(valid and not rows.is_empty(), { best = best }, notes, { table = rows })


## Full aileron, both ways, at 1.3 Vs, the start speed and 0.8 Vmax; other controls at trim. Rate, time to 360°,
## height change and adverse sideslip.
func _roll_rate() -> Dictionary:
	var rows := []
	var notes := []
	for named in [["1.3Vs", 1.3 * vs], ["start", v_start], ["0.8Vmax", 0.8 * vmax]]:
		var speed: float = named[1]
		for side in [1.0, -1.0]:
			var flight := _fly("roll_rate", { speed = speed, altitude = HIGH }, 5.0, func(t: float, s: PackedFloat64Array, ctx: Dictionary) -> Dictionary:
				ctx.suffix = "%.0fmps_%s" % [speed, "right" if side > 0.0 else "left"]
				ctx.turned = float(ctx.get("turned", 0.0)) + s[RB.RATE] / 240.0 if t >= 0.25 else 0.0
				return { roll = side if t >= 0.25 else 0.0, throttle = ctx.start_throttle }, func(t: float, s: PackedFloat64Array, ctx: Dictionary) -> bool:
				if absf(float(ctx.get("turned", 0.0))) >= TAU and not ctx.has("full_t"):
					ctx.full_t = t
				return ctx.has("full_t") and t > float(ctx.full_t) + 0.25)
			if not flight.ok:
				notes.append(flight.message)
				continue
			var trace: RefCounted = flight.trace
			var p := _col(trace, "p_radps")
			var peak := _max(p) if side > 0.0 else -_min(p)
			var beta := 0.0
			for r in trace.row_count():
				beta = maxf(beta, absf(_beta_deg(trace, r)))
			rows.append({ case = "%s_%s" % [named[0], "right" if side > 0.0 else "left"], speed_mps = snappedf(speed, 0.01), direction = "right" if side > 0.0 else "left", max_roll_rate_dps = snappedf(rad_to_deg(peak), 0.1),
				time_to_360_s = snappedf(float(flight.ctx.get("full_t", NAN)) - 0.25, 0.01),
				height_change_m = snappedf(trace.value(trace.row_count() - 1, "alt_m") - trace.value(0, "alt_m"), 0.1), max_sideslip_deg = snappedf(beta, 0.1) })
	return _result(rows.size() == 6, {}, notes, { table = rows })


## Full up elevator for 1 s from the start speed and 0.8 Vmax: peak load factor, α and pitch rate; does it stall?
func _pitch_pull() -> Dictionary:
	var rows := []
	for named in [["start", v_start], ["0.8Vmax", 0.8 * vmax]]:
		var speed: float = named[1]
		var flight := _fly("pitch_pull", { speed = speed, altitude = HIGH }, 2.5, func(t: float, s: PackedFloat64Array, ctx: Dictionary) -> Dictionary:
			ctx.suffix = "%.0fmps" % speed
			return { pitch = 1.0 if t >= 0.25 and t < 1.25 else 0.0, throttle = ctx.start_throttle })
		if not flight.ok:
			continue
		var trace: RefCounted = flight.trace
		var n_max := -INF
		var a_max := -INF
		for r in _row_at(trace, 1.5):
			n_max = maxf(n_max, _load_factor(trace, r))
			a_max = maxf(a_max, _alpha_deg(trace, r))
		rows.append({ case = named[0], speed_mps = snappedf(speed, 0.01), peak_load_factor_g = snappedf(n_max, 0.01), peak_alpha_deg = snappedf(a_max, 0.1),
			peak_pitch_rate_dps = snappedf(rad_to_deg(_max(_col(trace, "q_radps"))), 0.1), stalls = a_max > rad_to_deg(a1),
			load_factor_at_cl_max = snappedf((speed / vs) ** 2, 0.01) })
	return _result(rows.size() == 2, {}, [], { table = rows })


## Inside loop as a pilot flies it: full throttle from 0.8 Vmax, α held 2° below the stall start, roll rate stopped
## with the ailerons, feet off. Height, time, minimum speed, sideslip and heading change at the bottom.
func _loop() -> Dictionary:
	var entry := maxf(v_start, 0.8 * vmax)
	var target := a1 - deg_to_rad(2.0)
	var flight := _fly("loop", { speed = entry, altitude = HIGH }, 15.0, func(t: float, s: PackedFloat64Array, ctx: Dictionary) -> Dictionary:
		ctx.turned = float(ctx.get("turned", 0.0)) + s[RB.RATE + 1] / 240.0
		var k := P.schedule(s, v_start)
		return { roll = P.roll_damper(s, k), pitch = P.alpha_hold(s, target, k, ctx, 1.0 / 240.0), throttle = 1.0 }, func(t: float, s: PackedFloat64Array, ctx: Dictionary) -> bool:
		if float(ctx.get("turned", 0.0)) >= TAU:
			ctx.closed_t = t
			return true
		return false)
	if not flight.ok:
		return _failed(flight)
	var trace: RefCounted = flight.trace
	var n: int = trace.row_count()
	var beta := 0.0
	for r in n:
		beta = maxf(beta, absf(_beta_deg(trace, r)))
	var closed: bool = flight.ctx.has("closed_t")
	var heading_change := wrapf(trace.value(n - 1, "yaw_deg") - trace.value(0, "yaw_deg"), -180.0, 180.0)
	var notes := []
	if not closed:
		notes.append("loop not closed in 15 s")
	if beta >= 10.0:
		notes.append("sideslip above 10°: rolling departure, not a clean loop")
	return _result(closed and flight.crashed == "" and beta < 10.0, { entry_speed_mps = snappedf(entry, 0.01), alpha_target_deg = snappedf(rad_to_deg(target), 0.1),
		loop_time_s = snappedf(float(flight.ctx.get("closed_t", NAN)), 0.01), loop_height_m = snappedf(_max(_col(trace, "alt_m")) - trace.value(0, "alt_m"), 0.1),
		min_speed_mps = snappedf(_min(_col(trace, "speed_mps")), 0.01), max_load_factor_g = snappedf(_max_load(trace), 0.01),
		max_sideslip_deg = snappedf(beta, 0.1), heading_change_deg = snappedf(heading_change, 0.1), height_change_m = snappedf(trace.value(n - 1, "alt_m") - trace.value(0, "alt_m"), 0.1) }, notes)


func _max_load(trace: RefCounted) -> float:
	var m := -INF
	for r in trace.row_count():
		m = maxf(m, _load_factor(trace, r))
	return m


## Level 60° turn both ways at the start speed, full throttle, height held, feet on the ball: sustained speed,
## turn rate and radius after 10 s.
func _turn_60() -> Dictionary:
	var rows := []
	var notes := []
	var alt0 := HIGH
	for side in [1.0, -1.0]:
		var flight := _fly("turn_60", { speed = v_start, altitude = alt0 }, 20.0, func(t: float, s: PackedFloat64Array, ctx: Dictionary) -> Dictionary:
			ctx.suffix = "right" if side > 0.0 else "left"
			var k := P.schedule(s, v_start)
			# Height through the attitude PI: its integral supplies the turn's extra pull.
			return { roll = P.bank(s, side * deg_to_rad(60.0), k), pitch = P.hold_altitude(s, alt0, k, ctx, 1.0 / 240.0),
				yaw = P.ball(s, k, ctx, 1.0 / 240.0), throttle = 1.0 })
		if not flight.ok:
			notes.append(flight.message)
			continue
		var trace: RefCounted = flight.trace
		var r0 := _row_at(trace, 12.0)
		var v := _mean(_col(trace, "speed_mps", r0))
		var rate := absf(_track_rate(trace, r0, trace.row_count()))
		var alt_rate := _slope(trace, "alt_m", r0, trace.row_count())
		var bank := _mean(_col(trace, "roll_deg", r0))
		var held: bool = absf(absf(bank) - 60.0) < 5.0 and absf(alt_rate) < 1.0 and flight.crashed == ""
		if not held:
			notes.append("%s: bank %.1f°, vertical speed %.2f m/s" % ["right" if side > 0.0 else "left", bank, alt_rate])
		rows.append({ case = "right" if side > 0.0 else "left", direction = "right" if side > 0.0 else "left", sustained_speed_mps = snappedf(v, 0.01), turn_rate_dps = snappedf(rate, 0.1),
			radius_m = snappedf(v / deg_to_rad(rate), 0.1) if rate > 0.0 else NAN, bank_deg = snappedf(bank, 0.1), vertical_speed_mps = snappedf(alt_rate, 0.01),
			load_factor_g = snappedf(_mean(PackedFloat64Array(range(r0, trace.row_count()).map(func(r): return _load_factor(trace, r)))), 0.01), held = held })
	return _result(rows.size() == 2 and rows.all(func(r): return r.held), {}, notes, { table = rows })


## Full rudder step at the start speed, ailerons and elevator at trim: yaw rate, sideslip and the roll it induces.
func _rudder_step() -> Dictionary:
	var rows := []
	for side in [1.0, -1.0]:
		var flight := _fly("rudder_step", { speed = v_start, altitude = HIGH }, 3.0, func(t: float, s: PackedFloat64Array, ctx: Dictionary) -> Dictionary:
			ctx.suffix = "right" if side > 0.0 else "left"
			return { yaw = side if t >= 0.25 else 0.0, throttle = ctx.start_throttle })
		if not flight.ok:
			continue
		var trace: RefCounted = flight.trace
		var n: int = trace.row_count()
		var beta := 0.0
		for r in n:
			beta = maxf(beta, absf(_beta_deg(trace, r)))
		var r_col := _col(trace, "r_radps")
		rows.append({ case = "right" if side > 0.0 else "left", direction = "right" if side > 0.0 else "left", peak_yaw_rate_dps = snappedf(rad_to_deg(_max(r_col) if side > 0.0 else -_min(r_col)), 0.1),
			max_sideslip_deg = snappedf(beta, 0.1), bank_after_2_75_s_deg = snappedf(trace.value(n - 1, "roll_deg"), 0.1),
			peak_roll_rate_dps = snappedf(rad_to_deg(_max(_col(trace, "p_radps")) if side > 0.0 else _min(_col(trace, "p_radps"))), 0.1),
			pitch_change_deg = snappedf(trace.value(n - 1, "pitch_deg") - trace.value(0, "pitch_deg"), 0.1) })
	return _result(rows.size() == 2, {}, [], { table = rows })


## Sustained knife-edge both ways at 0.8 Vmax and full throttle: roll to 90° and hold it with the ailerons, the height
## with top rudder (PI) and the heading with the elevator. Reports the rudder it needs, whether it saturates, and the
## sink rate with what it has, plus the aileron and elevator couplings.
func _knife_edge() -> Dictionary:
	return _knife("knife_edge", false)


## Knife-edge with full top rudder held: does it climb or sink, and how much?
func _knife_edge_full_rudder() -> Dictionary:
	return _knife("knife_edge_full_rudder", true)


func _knife(name: String, full_rudder: bool) -> Dictionary:
	var rows := []
	var notes := []
	var valid := true
	for throttle in [1.0, 0.5]:
		for side in [1.0, -1.0]:
			var entry := 0.8 * vmax
			var alt0 := HIGH
			var heading := 0.0
			var flight := _fly(name, { speed = entry, altitude = alt0 }, 10.0, func(t: float, s: PackedFloat64Array, ctx: Dictionary) -> Dictionary:
				ctx.suffix = "%s_%.0fpct" % ["right" if side > 0.0 else "left", 100.0 * throttle]
				var k := P.schedule(s, v_start)
				var e := P.euler(s)
				if not ctx.has("heading"):
					ctx.heading = e[0]
				var phi: float = e[2]
				var sphi := sin(phi)
				# Nose elevation through top rudder: raising the nose in a right knife-edge (φ = +90°) is left rudder.
				# The nose must rise as far as the sideslip the fuselage needs: allow up to 35°.
				var wanted := clampf(0.02 * (alt0 - P.altitude(s)) - 0.03 * P.climb_rate(s), -0.6, 0.6)
				var error: float = wanted - e[1]
				ctx.ke_i = clampf(float(ctx.get("ke_i", 0.0)) + 6.0 * k * error / 240.0 * absf(sphi), -1.0, 1.0)
				var nose_up: float = k * (3.0 * error + 0.6 * s[RB.RATE + 2] * sphi) + float(ctx.ke_i)
				var yaw := -sphi * nose_up
				if full_rudder and absf(sphi) > 0.7:
					yaw = -signf(sphi)
				# Heading with the elevator: in a right knife-edge nose-up elevator turns right.
				var pitch: float = k * (3.0 * sphi * wrapf(float(ctx.heading) - e[0], -PI, PI) - 0.6 * s[RB.RATE + 1])
				return { roll = P.bank_pi(s, side * PI / 2.0, k, ctx, 1.0 / 240.0), pitch = pitch, yaw = yaw, throttle = throttle })
			if not flight.ok:
				notes.append(flight.message)
				valid = false
				continue
			var trace: RefCounted = flight.trace
			var n: int = trace.row_count()
			var r0 := mini(_row_at(trace, 5.0), maxi(n - 240, 0)) # a floor stop leaves at least the last second
			var bank := _mean(_col(trace, "roll_deg", r0))
			var rudder := _mean(_col(trace, "cmd_yaw", r0))
			var sat := _saturated(flight.ctx, "yaw", r0, n)
			var climb := _slope(trace, "alt_m", r0, n)
			# The card is met when the bank is held and either the height is held or the rudder is at its stop; a pilot
			# that sinks with rudder to spare measured itself, not the airplane.
			var held: bool = absf(absf(bank) - 90.0) < 10.0 and flight.crashed == "" and (full_rudder or absf(climb) < 0.5 or sat > 0.5)
			if not held:
				notes.append("%s %.0f %%: bank %.1f°, vertical speed %.2f m/s, rudder saturated %.0f %% %s" % ["right" if side > 0.0 else "left", 100.0 * throttle, bank, climb, 100.0 * sat, flight.crashed])
			valid = valid and held
			rows.append({ case = "%s_%.0fpct" % ["right" if side > 0.0 else "left", 100.0 * throttle], direction = "right" if side > 0.0 else "left", throttle = throttle, entry_speed_mps = snappedf(entry, 0.01),
				speed_after_5_s_mps = snappedf(trace.value(r0, "speed_mps"), 0.01), speed_end_mps = snappedf(trace.value(n - 1, "speed_mps"), 0.01),
				vertical_speed_mps = snappedf(_slope(trace, "alt_m", r0, n), 0.01), height_change_10_s_m = snappedf(trace.value(n - 1, "alt_m") - alt0, 0.1),
				rudder_stick = snappedf(rudder, 0.001), rudder_saturated_fraction = snappedf(sat, 0.01),
				aileron_stick = snappedf(_mean(_col(trace, "cmd_roll", r0)), 0.001), elevator_stick = snappedf(_mean(_col(trace, "cmd_pitch", r0)), 0.001),
				sideslip_deg = snappedf(_mean(PackedFloat64Array(range(r0, n).map(func(r): return _beta_deg(trace, r)))), 0.1),
				pitch_attitude_deg = snappedf(_mean(_col(trace, "pitch_deg", r0)), 0.1), bank_deg = snappedf(bank, 0.1),
				sustained = not full_rudder and sat < 0.05 and absf(_slope(trace, "alt_m", r0, n)) < 0.5 })
	return _result(valid, {}, notes, { table = rows })


## Inverted level pass at 0.6 Vmax (at least the start speed): roll over, hold 180°, the height through a bounded α
## and the speed with the throttle. Reports the elevator, α and throttle it needs.
func _inverted() -> Dictionary:
	var r := _inverted_pass("inverted", maxf(v_start, 0.6 * vmax), PI, deg_to_rad(160.0), "")
	if not r.ok:
		return _failed(r)
	return _result(r.held, r.metrics, [] if r.held else [r.why])


## Inverted pass at `pass_speed` (the `inverted` law, also flown by card_aerobatics.gd): roll to `bank` (π is wings
## level inverted) with the elevator only damping until |roll| ≥ `over`, then hold the height and the speed as below.
## `suffix` names the trace. Returns the flight plus { held, why, metrics } over the last 5 s.
func _inverted_pass(name: String, pass_speed: float, bank: float, over: float, suffix: String, seconds := 16.0) -> Dictionary:
	var alt0 := HIGH
	var flight := _fly(name, { speed = pass_speed, altitude = alt0 }, seconds, func(t: float, s: PackedFloat64Array, ctx: Dictionary) -> Dictionary:
		if suffix != "":
			ctx.suffix = suffix
		var k := P.schedule(s, v_start)
		var e := P.euler(s)
		# Roll over with the elevator only damping, then hold the height through an angle of attack bounded by the
		# negative stall start (+2°) and +5°: inverted, a climb needs a more negative α. Euler-free inner α loop.
		var pitch: float = -k * 0.6 * s[RB.RATE + 1]
		if not ctx.has("over_t") and absf(e[2]) >= over:
			ctx.over_t = t
			ctx.bank_i = 0.0 # the roll-over wound the bank integrator up; start the hold from zero
			ctx.alpha_i = 0.0
		if ctx.has("over_t"):
			var e_alt: float = alt0 - P.altitude(s)
			ctx.inv_i = clampf(float(ctx.get("inv_i", 0.0)) + e_alt / 240.0, -40.0, 40.0)
			var wanted := clampf(-(0.02 * e_alt - 0.03 * P.climb_rate(s) + 0.004 * float(ctx.inv_i)),
				-(n1 - deg_to_rad(2.0)), deg_to_rad(5.0))
			pitch = P.alpha_hold(s, wanted, k, ctx, 1.0 / 240.0)
		var throttle: float = clampf(float(ctx.start_throttle) + 0.1 * (pass_speed - P.speed(s)) + 0.05 * float(ctx.get("thr_i", 0.0)), 0.0, 1.0)
		ctx.thr_i = clampf(float(ctx.get("thr_i", 0.0)) + (pass_speed - P.speed(s)) / 240.0, -20.0, 20.0)
		return { roll = P.bank_pi(s, bank, k, ctx, 1.0 / 240.0), pitch = pitch, yaw = P.ball(s, k, ctx, 1.0 / 240.0), throttle = throttle })
	if not flight.ok:
		return flight
	var trace: RefCounted = flight.trace
	var n: int = trace.row_count()
	var r0 := _row_at(trace, seconds - 5.0)
	var bank_mean := absf(_mean(PackedFloat64Array(range(r0, n).map(func(r): return absf(trace.value(r, "roll_deg"))))))
	var rate := _slope(trace, "alt_m", r0, n)
	flight.held = bank_mean > 170.0 and absf(rate) < 0.5 and flight.crashed == ""
	flight.why = "inverted hold not achieved: |bank| %.1f°, vertical speed %.2f m/s %s" % [bank_mean, rate, flight.crashed]
	flight.metrics = { elevator_stick = snappedf(_mean(_col(trace, "cmd_pitch", r0)), 0.001), elevator_servo = snappedf(_mean(_col(trace, "srv_pitch", r0)), 0.001),
		alpha_deg = snappedf(_mean(PackedFloat64Array(range(r0, n).map(func(r): return _alpha_deg(trace, r)))), 0.1),
		throttle = snappedf(_mean(_col(trace, "cmd_throttle", r0)), 0.001), upright_throttle = snappedf(float(flight.ctx.start_throttle), 0.001),
		speed_mps = snappedf(_mean(_col(trace, "speed_mps", r0)), 0.01), vertical_speed_mps = snappedf(rate, 0.01) }
	return flight


## Spins both ways: idle, full up and full rudder for 6 s from 1.2 Vs, then opposite rudder and stick half forward until
## the yaw rate falls below 0.5 rad/s, then neutral and pull out at half the stall-start α.
func _spin() -> Dictionary:
	var rows := []
	var notes := []
	for side in [1.0, -1.0]:
		var flight := _fly("spin", { speed = 1.2 * vs, altitude = 400.0 }, 25.0, func(t: float, s: PackedFloat64Array, ctx: Dictionary) -> Dictionary:
			ctx.suffix = "right" if side > 0.0 else "left"
			var k := P.schedule(s, v_start)
			if t < 6.25:
				if t >= 0.25:
					ctx.turns_pro = float(ctx.get("turns_pro", 0.0)) + absf(_earth_yaw_rate(s)) / TAU / 240.0
				return { pitch = 1.0 if t >= 0.25 else 0.0, yaw = side if t >= 0.25 else 0.0, throttle = 0.0 }
			if not ctx.has("stopped_t"):
				ctx.turns_recovery = float(ctx.get("turns_recovery", 0.0)) + absf(_earth_yaw_rate(s)) / TAU / 240.0
				if absf(s[RB.RATE + 2]) < 0.5 and t > 6.5:
					ctx.stopped_t = t
				return { pitch = -0.5, yaw = -side, throttle = 0.0 }
			return { roll = P.roll_damper(s, k), pitch = P.alpha_hold(s, 0.5 * a1, k, ctx, 1.0 / 240.0), throttle = 0.0 }, func(t: float, s: PackedFloat64Array, ctx: Dictionary) -> bool:
			if t > 4.0 and t < 6.25:
				ctx.rate_samples = ctx.get("rate_samples", []) + [absf(_earth_yaw_rate(s))]
			if ctx.has("stopped_t") and P.climb_rate(s) > 0.0 and t > float(ctx.stopped_t) + 0.5:
				ctx.level_t = t
				return true
			return false)
		if not flight.ok:
			notes.append(flight.message)
			continue
		var trace: RefCounted = flight.trace
		var ctx: Dictionary = flight.ctx
		var rate := _mean(PackedFloat64Array(ctx.get("rate_samples", [])))
		var r6 := _row_at(trace, 6.25)
		var alt_entry: float = trace.value(_row_at(trace, 0.25), "alt_m")
		var turns_pro: float = float(ctx.get("turns_pro", 0.0))
		var row := { case = "right" if side > 0.0 else "left", direction = "right" if side > 0.0 else "left", steady_turn_time_s = snappedf(TAU / rate, 0.01) if rate > 0.0 else NAN,
			turns_in_6_s = snappedf(turns_pro, 0.01), height_lost_per_turn_m = snappedf((alt_entry - trace.value(r6, "alt_m")) / maxf(turns_pro, 0.01), 0.1),
			max_alpha_deg = snappedf(_max(PackedFloat64Array(range(0, r6).map(func(r): return _alpha_deg(trace, r)))), 0.1),
			recovery_turns = snappedf(float(ctx.get("turns_recovery", NAN)), 0.01), recovery_time_s = snappedf(float(ctx.get("stopped_t", NAN)) - 6.25, 0.01),
			total_height_lost_m = snappedf(alt_entry - _min(_col(trace, "alt_m")), 0.1), recovered = ctx.has("level_t") and flight.crashed == "" }
		# A spin turns faster than once per 3 s with the wing past its stall start; anything slower is a spiral.
		row.entered = "spin" if rate > TAU / 3.0 and row.max_alpha_deg > rad_to_deg(a1) else "spiral (no spin)"
		if not row.recovered:
			notes.append("%s spin not recovered %s" % [row.direction, flight.crashed])
		rows.append(row)
	return _result(rows.size() == 2, {}, notes, { table = rows })


func _wheels_down(s: PackedFloat64Array) -> int:
	var n := 0
	for c in Ground.compressions(s, session.current_landing_gear()):
		n += int(c > 0.0)
	return n


## Yaw rate about the earth vertical (rad/s): the spin's rotation, whatever the attitude.
static func _earth_yaw_rate(s: PackedFloat64Array) -> float:
	var up := P.up_body(s)
	return -(s[RB.RATE] * up[0] + s[RB.RATE + 1] * up[1] + s[RB.RATE + 2] * up[2])


## Takeoff from the qualified runway start: throttle up over 2 s, stick back below 0.4 Vs, then a 1° attitude, rotate at
## 1.25 Vs to min(8°, stall start − 3°) with a PI pitch loop, heading held with the rudder, wings level. Also a
## rudder-free sample: the swing in 3 s.
func _takeoff() -> Dictionary:
	if not FlightSession.runway_aircraft_supported(aircraft_id):
		return _result(false, {}, ["no qualified runway start for this aircraft"], { skipped = true })
	var rotate := minf(deg_to_rad(8.0), a1 - deg_to_rad(3.0))
	var heading := NAN
	var pilot := func(rudder: bool) -> Callable:
		return func(t: float, s: PackedFloat64Array, ctx: Dictionary) -> Dictionary:
			if not ctx.has("heading"):
				ctx.heading = P.euler(s)[0]
			var v := P.speed(s)
			var k := 1.0
			var c := { roll = P.bank(s, 0.0, k), yaw = P.ground_heading(s, ctx.heading) if rudder else 0.0, throttle = clampf(t / 2.0, 0.0, 1.0) }
			if v < 0.4 * vs:
				c.pitch = 0.6
			elif v < 1.25 * vs:
				c.pitch = P.pitch(s, deg_to_rad(1.0), k, ctx, 1.0 / 240.0)
			else:
				if not ctx.has("rotation_t"):
					ctx.rotation_t = t
					ctx.erase("pitch_i")
				c.pitch = P.pitch(s, rotate, k, ctx, 1.0 / 240.0)
				ctx.rotation_pitch = maxf(float(ctx.get("rotation_pitch", -1.0)), P.euler(s)[1]) if t - float(ctx.rotation_t) <= 1.5 else float(ctx.get("rotation_pitch", -1.0))
			if not ctx.has("x0"):
				ctx.x0 = s[RB.POS]
				ctx.y0 = s[RB.POS + 1]
			if not ctx.has("liftoff_t") and t > 1.0 and _wheels_down(s) == 0:
				ctx.liftoff_t = t
				ctx.liftoff_v = v
				ctx.liftoff_x = sqrt((s[RB.POS] - float(ctx.x0)) ** 2 + (s[RB.POS + 1] - float(ctx.y0)) ** 2)
			if not ctx.has("liftoff_t"):
				ctx.max_heading_error = maxf(float(ctx.get("max_heading_error", 0.0)), absf(wrapf(P.euler(s)[0] - float(ctx.heading), -PI, PI)))
				ctx.max_rudder = maxf(float(ctx.get("max_rudder", 0.0)), absf(c.yaw))
			return c
	var free := _fly("takeoff_rudder_free", { runway = true }, 3.0, pilot.call(false))
	var flight := _fly("takeoff", { runway = true }, 15.0, pilot.call(true), func(t: float, s: PackedFloat64Array, ctx: Dictionary) -> bool:
		return ctx.has("liftoff_t") and t > float(ctx.liftoff_t) + 3.0)
	if not flight.ok:
		return _failed(flight)
	var ctx: Dictionary = flight.ctx
	var notes := []
	var swing := NAN
	if free.ok:
		var tr: RefCounted = free.trace
		swing = wrapf(tr.value(tr.row_count() - 1, "yaw_deg") - tr.value(0, "yaw_deg"), -180.0, 180.0)
	if not ctx.has("liftoff_t"):
		notes.append("no lift-off in 15 s " + flight.crashed)
		return _result(false, {}, notes)
	var rotated: bool = rad_to_deg(float(ctx.get("rotation_pitch", -1.0))) >= rad_to_deg(rotate) - 1.0
	if not rotated:
		notes.append("rotation attitude not reached: %.1f° of %.1f°" % [rad_to_deg(float(ctx.get("rotation_pitch", -1.0))), rad_to_deg(rotate)])
	return _result(rotated and flight.crashed == "", { liftoff_speed_mps = snappedf(ctx.liftoff_v, 0.01), liftoff_speed_vs = snappedf(float(ctx.liftoff_v) / vs, 0.01),
		ground_roll_m = snappedf(float(ctx.liftoff_x), 0.1), time_to_liftoff_s = snappedf(ctx.liftoff_t, 0.01),
		rotation_attitude_deg = snappedf(rad_to_deg(rotate), 0.1), max_rudder_stick = snappedf(float(ctx.get("max_rudder", 0.0)), 0.01),
		max_heading_error_deg = snappedf(rad_to_deg(float(ctx.get("max_heading_error", 0.0))), 0.1), rudder_free_heading_change_3_s_deg = snappedf(swing, 0.1) }, notes)


## Linearized modes of the real equations (physics/flight_modes.gd) at 1.3 Vs, the start speed and 0.8 Vmax. No flight.
func _modes() -> Dictionary:
	var rows := []
	var notes := []
	for named in [["1.3Vs", 1.3 * vs], ["start", v_start], ["0.8Vmax", 0.8 * vmax]]:
		var m := FlightModes.analyze(model, named[1])
		if not m.ok:
			notes.append("%s: %s" % [named[0], m.message])
			continue
		var spiral: float = m.spiral_tau
		# A "phugoid" faster than the short period is a mislabelled root of the block projection, not a phugoid.
		var phugoid: Dictionary = m.phugoid
		if float(phugoid.get("f_hz", 0.0)) >= float(m.short_period.get("f_hz", INF)):
			notes.append("%s: longitudinal roots do not separate into short period and phugoid; phugoid not reported" % named[0])
			phugoid = {}
		rows.append({ case = named[0], speed_mps = snappedf(named[1], 0.01),
			short_period_hz = snappedf(float(m.short_period.get("f_hz", NAN)), 0.001), short_period_zeta = snappedf(float(m.short_period.get("zeta", NAN)), 0.001),
			phugoid_period_s = snappedf(1.0 / float(phugoid.get("f_hz", NAN)), 0.01), phugoid_zeta = snappedf(float(phugoid.get("zeta", NAN)), 0.001),
			dutch_roll_hz = snappedf(float(m.dutch_roll.f_hz), 0.001), dutch_roll_zeta = snappedf(float(m.dutch_roll.zeta), 0.001),
			roll_time_constant_s = snappedf(float(m.roll_tau), 0.001),
			spiral_time_to_double_s = snappedf(-spiral * log(2.0), 0.1) if spiral < 0.0 else NAN,
			spiral_time_to_half_s = snappedf(spiral * log(2.0), 0.1) if spiral > 0.0 else NAN })
	# The start-speed case defines the test; a speed without a level trim is the airplane's answer, kept as a note.
	return _result(rows.any(func(r): return r.case == "start"), {}, notes, { table = rows })


## Static aerodynamics at the start speed with every control neutral, no flight: which model carries the loads and what
## each one gives. A sideslip sweep at the level-trim α (CY, Cn, Cl) and an α sweep at zero sideslip (CL, CD, Cm), each
## from the coefficient oracle, the local surface model, the blended production loads, and the production local-flow
## weight (0 = oracle, 1 = local). Body-axis loads about the CG on wing area, span and chord; CL/CD in wind axes.
## Summaries locate the regime seams and the side force a knife-edge needs at the knife-edge test speed (0.8 Vmax).
func _aero_sweep() -> Dictionary:
	var notes := []
	var trim: Dictionary = session.trim_at(v_start, "level")
	var alpha_trim: float = P.alpha(trim.state) if trim.get("ok", false) else 0.0
	if not trim.get("ok", false):
		notes.append("no level trim at the start speed; sideslip sweep at α 0°")
	var neutral := { elevator = 0.0, aileron_right = 0.0, aileron_left = 0.0, rudder = 0.0 }
	var qs: float = 0.5 * RHO * v_start * v_start * float(model.reference.S)
	var span: float = float(model.reference.b)
	var chord: float = float(model.reference.c)
	var all_finite := true
	var beta_rows := []
	var weight_full_beta := NAN
	var cy_blended_max := 0.0
	for beta_deg in [0.0, 5.0, 10.0, 15.0, 20.0, 25.0, 30.0, 45.0, 60.0, 90.0]:
		var e := _aero_point(alpha_trim, deg_to_rad(beta_deg), neutral)
		all_finite = all_finite and e.finite
		if is_nan(weight_full_beta) and e.weight >= 1.0:
			weight_full_beta = beta_deg
		if beta_deg <= 30.0:
			cy_blended_max = maxf(cy_blended_max, absf(e.blended[1] / qs))
		beta_rows.append({ case = "beta_%02d" % int(beta_deg), beta_deg = beta_deg, local_weight = snappedf(e.weight, 0.001),
			cy_oracle = snappedf(e.oracle[1] / qs, 0.0001), cy_local = snappedf(e.local[1] / qs, 0.0001), cy = snappedf(e.blended[1] / qs, 0.0001),
			cn_oracle = snappedf(e.oracle[5] / (qs * span), 0.0001), cn_local = snappedf(e.local[5] / (qs * span), 0.0001), cn = snappedf(e.blended[5] / (qs * span), 0.0001),
			cl_oracle = snappedf(e.oracle[3] / (qs * span), 0.0001), cl_local = snappedf(e.local[3] / (qs * span), 0.0001), cl = snappedf(e.blended[3] / (qs * span), 0.0001) })
	var alpha_rows := []
	var weight_full_alpha := NAN
	for alpha_deg in [-10.0, -5.0, 0.0, 5.0, 10.0, 15.0, 20.0, 30.0]:
		var a := deg_to_rad(alpha_deg)
		var e := _aero_point(a, 0.0, neutral)
		all_finite = all_finite and e.finite
		if is_nan(weight_full_alpha) and alpha_deg > 0.0 and e.weight >= 1.0:
			weight_full_alpha = alpha_deg
		var row := { case = ("alpha_m%02d" % int(-alpha_deg)) if alpha_deg < 0.0 else ("alpha_%02d" % int(alpha_deg)), alpha_deg = alpha_deg, local_weight = snappedf(e.weight, 0.001) }
		for named in [["oracle", e.oracle], ["local", e.local], ["", e.blended]]:
			var f: PackedFloat64Array = named[1]
			var suffix: String = "" if named[0] == "" else "_" + named[0]
			row["cl_lift" + suffix] = snappedf((-f[2] * cos(a) + f[0] * sin(a)) / qs, 0.0001)
			row["cd" + suffix] = snappedf((-f[0] * cos(a) - f[2] * sin(a)) / qs, 0.0001)
			row["cm" + suffix] = snappedf(f[4] / (qs * chord), 0.0001)
		alpha_rows.append(row)
	var at20: Dictionary = beta_rows.filter(func(r): return r.case == "beta_20")[0]
	var v_knife := 0.8 * vmax
	var required: float = model.mass_kg * G / (0.5 * RHO * v_knife * v_knife * float(model.reference.S))
	var metrics := { trim_alpha_deg = snappedf(rad_to_deg(alpha_trim), 0.01),
		local_weight_full_at_beta_deg = weight_full_beta, local_weight_full_at_alpha_deg = weight_full_alpha,
		cy_at_beta20 = at20.cy, cy_oracle_at_beta20 = at20.cy_oracle,
		cy_max_beta_le_30 = snappedf(cy_blended_max, 0.0001),
		knife_edge_cy_needed_at_0_8vmax = snappedf(required, 0.0001),
		knife_edge_side_force_margin = snappedf(cy_blended_max / required, 0.001) }
	if is_finite(weight_full_beta) and weight_full_beta < rad_to_deg(float(model.envelope.get("b2", deg_to_rad(25.0)))):
		notes.append("with controls neutral the local model carries all loads from β %.0f° at the trim α, before the sideslip blend ends (%.0f°); a deflected rudder keeps the fin's own angle lower in flight (see --diagnostics)" % [weight_full_beta, rad_to_deg(float(model.envelope.get("b2", NAN)))])
	if not results.has("vmax") and not results.has("trim_sweep"):
		notes.append("Vmax was not measured in this run; 2 × start speed stands in for the knife-edge speed")
	if cy_blended_max < required:
		notes.append("no sideslip up to 30° gives the side force a knife-edge needs at 0.8 Vmax (|CY| %.3f of %.3f)" % [cy_blended_max, required])
	return _result(all_finite, metrics, notes, { table = beta_rows + alpha_rows })


## Body-axis loads [Fx, Fy, Fz, Mx, My, Mz] at the start speed for α, β: oracle, local, blended production, local weight.
func _aero_point(alpha: float, beta: float, d: Dictionary) -> Dictionary:
	var s := PackedFloat64Array([0.0, 0.0, -HIGH, v_start * cos(alpha) * cos(beta), v_start * sin(beta), v_start * sin(alpha) * cos(beta),
		1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	var air: Dictionary = Air.compute(s, PackedFloat64Array([0.0, 0.0, 0.0]), RHO)
	var oracle: PackedFloat64Array = Aero._global_loads(s, air, d, model, RHO)
	var local: PackedFloat64Array = Aero._local_loads(s, air, d, model, RHO)
	var blended: PackedFloat64Array = Aero.loads(s, air, d, model, RHO)
	var weight: float = Aero.local_flow_weight(s, air, d, model)
	var finite := is_finite(weight)
	for f in [oracle, local, blended]:
		for x in f:
			finite = finite and is_finite(x)
	return { oracle = oracle, local = local, blended = blended, weight = weight, finite = finite }


## Hands off for 30 s from the trimmed start at 400 m after two small disturbances: 0.2 up elevator for 0.5 s at 1 s (phugoid,
## from the speed extrema) and 0.2 right aileron for 0.5 s at 2 s (spiral, from the bank and heading afterwards). An exact
## trim in calm air would otherwise show no motion at all.
func _hands_off() -> Dictionary:
	var flight := _fly("hands_off", { speed = v_start, altitude = 400.0 }, 30.0, func(t: float, s: PackedFloat64Array, ctx: Dictionary) -> Dictionary:
		return { pitch = 0.2 if t >= 1.0 and t < 1.5 else 0.0, roll = 0.2 if t >= 2.0 and t < 2.5 else 0.0, throttle = ctx.start_throttle })
	if not flight.ok:
		return _failed(flight)
	var trace: RefCounted = flight.trace
	var n: int = trace.row_count()
	var peaks := PackedFloat64Array()
	var mean_v := _mean(_col(trace, "speed_mps"))
	for r in range(24, n - 24):
		var v: float = trace.value(r, "speed_mps")
		var local_peak: bool = v > trace.value(r - 24, "speed_mps") and v >= trace.value(r + 24, "speed_mps") and v > trace.value(r - 1, "speed_mps") and v >= trace.value(r + 1, "speed_mps")
		if local_peak and absf(v - mean_v) > 0.02 and trace.value(r, "t_s") > 2.0:
			if peaks.is_empty() or trace.value(r, "t_s") - peaks[-1] > 1.0:
				peaks.append(trace.value(r, "t_s"))
	var period := NAN
	if peaks.size() >= 2:
		period = (peaks[-1] - peaks[0]) / (peaks.size() - 1)
	var metrics := {}
	for at in [10.0, 30.0]:
		var r := mini(_row_at(trace, at), n - 1)
		var label := "%.0f_s" % at
		metrics["height_change_" + label + "_m"] = snappedf(trace.value(r, "alt_m") - trace.value(0, "alt_m"), 0.01)
		metrics["speed_change_" + label + "_mps"] = snappedf(trace.value(r, "speed_mps") - trace.value(0, "speed_mps"), 0.01)
		metrics["bank_" + label + "_deg"] = snappedf(trace.value(r, "roll_deg"), 0.1)
		metrics["heading_change_" + label + "_deg"] = snappedf(_unwrapped_rate(trace, "yaw_deg", 0, r + 1) * (trace.value(r, "t_s") - trace.value(0, "t_s")), 0.1)
	metrics.bank_after_aileron_pulse_deg = snappedf(trace.value(_row_at(trace, 3.0), "roll_deg"), 0.1)
	metrics.phugoid_period_s = snappedf(period, 0.01) # flown: the spiral and the trimmed throttle mix in; damping is in `modes`
	# Reaching the floor in a spiral dive is the result: record when.
	metrics.reached_floor_s = snappedf(float(flight.ctx.get("floor_t", NAN)), 0.01)
	return _result(flight.crashed == "", metrics, [] if flight.crashed == "" else [flight.crashed])


## Landing on the field's runway (qualified runway aircraft only): gear down, 4° approach from 30 m at 1.3 Vs aimed 10 m past the
## threshold; the elevator flies the path and the throttle the speed (a coupled approach); rudder holds the runway
## heading; flare one second of approach
## sink above the wheels with the throttle closed, raising the nose from the approach attitude until the sink follows the
## height down (0.3 m/s + 0.6/s × height); after touchdown the attitude is held
## until 0.7 Vs, then the stick comes back. No brakes.
func _landing() -> Dictionary:
	if not FlightSession.runway_aircraft_supported(aircraft_id):
		return _result(false, {}, ["no qualified runway start for this aircraft"], { skipped = true })
	var v_app := 1.3 * vs
	var gamma := deg_to_rad(4.0)
	var threshold := 15.0 # m north of the field origin; the runway runs east from -45 m (app/data/fields)
	var threshold_east := -45.0
	var aim := threshold_east + 10.0
	var h0 := 30.0 # a stabilized final: about 430 m of 4° path before the flare
	# Flare one second of approach sink above the wheels (constant time to touchdown, as a pilot judges it).
	var flare := clampf(v_app * tan(gamma) * 1.0, 0.5, 3.0)
	var flight := _fly("landing", { speed = v_app, altitude = h0, north = threshold, east = aim - h0 / tan(gamma), gear_down = true, floor = -INF }, 60.0,
			func(t: float, s: PackedFloat64Array, ctx: Dictionary) -> Dictionary:
		var k := P.schedule(s, v_start)
		var h := _wheel_height(s)
		var c := { roll = P.bank(s, 0.0, k), yaw = P.ground_heading(s, PI / 2.0), throttle = 0.0, pitch = 0.0 }
		if not ctx.has("td_t") and _wheels_down(s) > 0:
			ctx.td_t = t
			ctx.td_sink = -P.climb_rate(s)
			ctx.td_v = P.speed(s)
			ctx.td_east = s[RB.POS + 1]
			ctx.td_pitch = P.euler(s)[1]
		if not ctx.has("td_t"):
			if h > flare:
				# Coupled approach: the elevator flies the path (a sink-rate target that closes on the glide path) and the
				# throttle holds the speed, which also suits engines with spool lag.
				c.pitch = P.approach_pitch(s, h, (aim - s[RB.POS + 1]) * tan(gamma), v_app, gamma, a1, k, ctx)
				c.throttle = P.approach_throttle(s, v_app, float(ctx.start_throttle), ctx)
			else:
				# Flare: from the approach attitude, raise the nose until the sink follows the height down (PI on sink).
				c.pitch = P.flare(s, h, a1, k, ctx)
		else:
			c.pitch = P.pitch(s, float(ctx.td_pitch), 1.0, ctx, 1.0 / 240.0) if P.speed(s) > 0.7 * vs else clampf((0.7 * vs - P.speed(s)) / 3.0, 0.0, 1.0)
			if t > float(ctx.td_t) + 0.3 and _wheels_down(s) == 0 and h > 0.3:
				ctx.bounced = true
			ctx.max_heading_error = maxf(float(ctx.get("max_heading_error", 0.0)), absf(wrapf(P.euler(s)[0] - PI / 2.0, -PI, PI)))
		return c, func(t: float, s: PackedFloat64Array, ctx: Dictionary) -> bool:
			if ctx.has("td_t") and P.speed(s) < 1.0:
				ctx.stop_t = t
				ctx.stop_east = s[RB.POS + 1]
				return true
			return false)
	if not flight.ok:
		return _failed(flight)
	var ctx: Dictionary = flight.ctx
	if not ctx.has("td_t"):
		return _result(false, {}, ["no touchdown " + flight.crashed])
	var td_x: float = float(ctx.td_east) - threshold_east
	var on_runway: bool = td_x > -5.0 and td_x < 100.0
	var notes := []
	if not on_runway:
		notes.append("touchdown %.0f m from the threshold, off the 100 m runway" % td_x)
	if flight.crashed != "":
		notes.append(flight.crashed)
	return _result(on_runway and flight.crashed == "", { approach_speed_mps = snappedf(v_app, 0.01), touchdown_speed_mps = snappedf(ctx.td_v, 0.01),
		touchdown_speed_vs = snappedf(float(ctx.td_v) / vs, 0.01), touchdown_sink_mps = snappedf(ctx.td_sink, 0.01),
		touchdown_pitch_deg = snappedf(rad_to_deg(ctx.td_pitch), 0.1), touchdown_past_threshold_m = snappedf(td_x, 0.1),
		bounced = ctx.get("bounced", false), rollout_m = snappedf(float(ctx.get("stop_east", NAN)) - float(ctx.td_east), 0.1),
		rollout_time_s = snappedf(float(ctx.get("stop_t", NAN)) - float(ctx.td_t), 0.01),
		max_heading_error_deg = snappedf(rad_to_deg(float(ctx.get("max_heading_error", 0.0))), 0.1), flare_height_m = flare }, notes)


## Height of the lowest landing-gear contact above the ground (m); the crash hull is not a wheel.
func _wheel_height(s: PackedFloat64Array) -> float:
	var deepest := -INF
	for c in Ground.compressions(s, session.current_landing_gear()):
		deepest = maxf(deepest, c)
	return -deepest if is_finite(deepest) else P.altitude(s)


# --- Report -------------------------------------------------------------------------------------------------------

func _write_report() -> void:
	var data := { format = VERSION, aircraft = aircraft_id, name = Catalog.entry(aircraft_id).get("name", aircraft_id),
		data_sha256 = model.get("data_sha256", ""), mass_kg = model.mass_kg, wing_area_m2 = model.reference.S, span_m = model.reference.b,
		start_speed_mps = v_start, stall_speed_estimate_mps = vs_estimate, stall_start_alpha_deg = rad_to_deg(a1),
		engine = Engine.get_version_info().string, results = {} }
	for name in order:
		data.results[name] = results[name]
	var f := FileAccess.open(out_dir.path_join("profile.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(_finite_json(data), "  ", false) + "\n")
	var md := PackedStringArray()
	md.append("# Flight-test profile: %s" % data.name)
	md.append("")
	md.append("`%s` · %s · mass %.2f kg · S %.3f m² · span %.2f m · start %.1f m/s · Vs estimate %.1f m/s (CL_max) · Godot %s. Generated by `research/flight-test/flight_test.gd`; software evidence, not physical validation." %
		[aircraft_id, VERSION, model.mass_kg, model.reference.S, model.reference.b, v_start, vs_estimate, data.engine])
	md.append("")
	md.append("| Test | Valid | Result |")
	md.append("| --- | --- | --- |")
	for name in order:
		var r: Dictionary = results[name]
		var text := _fmt(r.get("metrics", {}))
		if r.has("table"):
			var parts := PackedStringArray()
			for row in r.table:
				parts.append(_fmt(row))
			text += ("<br>" if not text.is_empty() else "") + "<br>".join(parts)
		for note in r.get("notes", []):
			text += "<br>*%s*" % str(note)
		md.append("| %s | %s | %s |" % [name, "yes" if r.get("valid", false) else ("skipped" if r.get("skipped", false) else "**no**"), text])
	var m := FileAccess.open(out_dir.path_join("profile.md"), FileAccess.WRITE)
	m.store_string("\n".join(md) + "\n")
	print("FT report: " + out_dir.path_join("profile.md"))


## JSON has no NaN or infinity: undefined results become null.
static func _finite_json(v: Variant) -> Variant:
	if v is float:
		return v if is_finite(v) else null
	if v is Dictionary:
		var out := {}
		for key in v:
			out[key] = _finite_json(v[key])
		return out
	if v is Array:
		return v.map(func(x): return _finite_json(x))
	return v


static func _fmt(d: Dictionary) -> String:
	var parts := PackedStringArray()
	for key in d:
		var v = d[key]
		parts.append("%s %s" % [key, JSON.stringify(v) if v is Dictionary else str(v)])
	return ", ".join(parts)
