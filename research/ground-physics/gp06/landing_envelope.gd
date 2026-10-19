# GP-06 landing envelope: controlled touchdowns of catalog airplanes on the real FlightSession (aero, propulsion at
# idle, wheel profiles, field surfaces, gear-collapse, hull and prop-strike checks) over a sink-rate sweep.
# Modes: flare (level-flight trim attitude at 1.15 Vs, mains first), flat (trim attitude at 1.4 Vs: a wheel landing on
# a taildragger, a flat arrival on a tricycle) and, for taildraggers, three_point (geometric three-point pitch at the
# speed whose level trim needs that pitch). The CG starts 1 cm above first wheel contact with the requested sink added
# to the level-flight velocity. A minimal test pilot holds wings level, heading and the touchdown pitch attitude with
# throttle at idle (no flare law, no bounce recovery); --no-pilot leaves the trimmed controls fixed. --terminal uses
# the scripted D9d policy (any hull touch ends the flight) instead of the interactive soft contacts. Vs uses the
# envelope CL_max at sea-level density. Gains, speeds and start height are authored probe choices, not pilot data.
# Retractable gear is set downlocked through session internals (probe only; flight code is not changed).
# Run (from the repository root):
#   godot --headless --path app --script "$PWD/research/ground-physics/gp06/landing_envelope.gd" -- \
#     --out=<file.json> jensen_ugly_stik_60 gp_extra_300s_60 p51d_mustang_120 sebart_avanti_s_a200 turbo_lumber_evolution
extends SceneTree

const Session = preload("res://sim/flight_session.gd")
const Field = preload("res://data/field_loader.gd")
const M = preload("res://physics/math3d.gd")
const RB = preload("res://physics/rigid_body.gd")

const G := 9.80665
const RUN_S := 4.0
const SINKS := [0.25, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5]
const MODES := ["flare", "flat", "three_point"]
const SPEED_FACTOR := {"flare": 1.15, "flat": 1.4}

var soft := true
var pilot := true


func _initialize() -> void:
	var out_path := ""
	var files: Array = []
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_path = arg.trim_prefix("--out=")
		elif arg == "--terminal":
			soft = false
		elif arg == "--no-pilot":
			pilot = false
		else:
			files.append(arg)
	var loaded: Dictionary = Field.load_from()
	var runway: Dictionary = {}
	for surface: Dictionary in loaded.field.surfaces:
		if surface.id == loaded.field.runway:
			runway = surface
	var report := {format = "openrc-gp06-landing-envelope v1", soft_hull_contacts = soft, pilot = pilot,
		run_s = RUN_S, aircraft = {}}
	for f: String in files:
		var path := "res://data/aircraft/%s.json" % f
		var rows := []
		for mode: String in MODES:
			for sink: float in SINKS:
				var r := _run(path, loaded.field, runway, mode, sink)
				if r.has("skip"):
					break
				rows.append(r)
				if r.has("error"):
					print(f, " ", mode, " ", r.error)
					break
				print(_line(f, r))
		report.aircraft[f] = rows
	if not out_path.is_empty():
		var file := FileAccess.open(out_path, FileAccess.WRITE)
		file.store_string(JSON.stringify(report, "  ", false) + "\n")
		file.close()
	quit(0)


func _line(f: String, r: Dictionary) -> String:
	var fractions := ""
	for i in r.max_compression_fraction.size():
		fractions += "%s %.0f%% " % [r.contact_names[i], 100.0 * r.max_compression_fraction[i]]
	return "%-24s %-11s sink %.2f V %.1f pitch %+.1f | %s| %s | scrape %s | hop %.0f mm, %d bounces, air %.2f s | n %.1f | e %s | strike %s" % [
		f, r.mode, r.sink, r.V, r.pitch_deg, fractions, r.crash if not r.crash.is_empty() else "landed",
		str(r.scraped), 1000.0 * r.max_bounce_m, r.bounces, r.airborne_after_touch_s, r.peak_load_factor,
		"%.2f" % (r.w_out / r.w_in) if is_finite(r.w_out) and r.w_in > 0.0 else "-", r.prop_strike]


static func _three_point_pitch(gear: Dictionary) -> float:
	var mains := PackedFloat64Array()
	var other := PackedFloat64Array()
	for c: Dictionary in gear.contacts:
		if str(c.name).begins_with("main"):
			mains = c.position
		else:
			other = c.position
	return atan((mains[2] - other[2]) / (mains[0] - other[0]))


static func _is_taildragger(gear: Dictionary) -> bool:
	for c: Dictionary in gear.contacts:
		if str(c.name) == "tail":
			return true
	return false


func _run(path: String, field: Dictionary, runway: Dictionary, mode: String, sink: float) -> Dictionary:
	var session: Node = Session.new()
	session.setup(path)
	root.add_child(session)
	var out := {mode = mode, sink = sink}
	if not session.aircraft.get("ok", false) or not session.set_field(field):
		out.error = "setup"
		session.free()
		return out
	var model: Dictionary = session.aircraft.model
	var gear: Dictionary = model.landing_gear
	if mode == "three_point" and not _is_taildragger(gear):
		session.free()
		return {skip = true}
	var vs: float = sqrt(2.0 * model.mass_kg * G / (1.225 * float(model.reference.S) * float(model.envelope.CL_max)))
	var V: float = float(SPEED_FACTOR.get(mode, 1.15)) * vs
	var pitch := 0.0
	if mode == "three_point":
		# The speed whose level trim needs the geometric three-point pitch (bisection on the trimmed alpha).
		pitch = _three_point_pitch(gear)
		var lo := 0.8 * vs
		var hi := 1.6 * vs
		for _i in 30:
			var mid := 0.5 * (lo + hi)
			var tm: Dictionary = session.trim_at(mid)
			if not tm.ok or float(tm.alpha) > pitch:
				lo = mid
			else:
				hi = mid
		V = hi
	var t: Dictionary = session.trim_at(V)
	if not t.ok:
		out.error = "trim %s" % t.get("message", "")
		session.free()
		return out
	if mode != "three_point":
		pitch = t.alpha
	out.vs = vs
	out.V = V
	out.pitch_deg = rad_to_deg(pitch)
	var q := M.q_from_euler(PI / 2.0, pitch, 0.0)
	var v_body := M.q_rotate(M.q_conj(q), M.v3(0.0, V, sink))
	var lowest := -INF
	for c: Dictionary in gear.contacts:
		lowest = maxf(lowest, M.q_rotate(q, c.position)[2])
	session.start.state = RB.make_state(M.v3(runway.center_north, runway.center_east - 20.0, -(lowest + 0.01)), v_body, q,
		M.v3(0, 0, 0))
	session.input_enabled = false
	session.soft_hull_contacts = soft
	session.reset()
	if session.gear_is_retractable():
		var gi: int = session.gear_aux_index()
		var aux_values: PackedFloat64Array = session.sim.aux
		aux_values[gi] = 1.0
		aux_values[gi + 1] = 1.0
		session.sim.aux = aux_values
		session._gear_requested_down = true
		session._gear_cache_fraction = -1.0
	var dt: float = session.sim.dt()
	session.commands = {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0}
	session._physics_process(dt)
	var max_frac := PackedFloat64Array()
	max_frac.resize(gear.contacts.size())
	var touched := false
	var was_down := false
	var airborne_after := 0.0
	var bounces := 0
	var max_n := 0.0
	var max_bounce := 0.0
	var first_contact := ""
	var scraped := {}
	var w_in := NAN
	var w_out := NAN
	var names: PackedStringArray = model.get("crash_hull_components", PackedStringArray())
	for tick in roundi(RUN_S / dt):
		if not session.crash.is_empty() or not session.sim.fault_reason.is_empty():
			break
		var before: PackedFloat64Array = session.sim.state
		var qb := M.quat(before[6], before[7], before[8], before[9])
		if pilot:
			var eb := M.q_to_euler(qb)
			var heading_error: float = wrapf(PI / 2.0 - eb[0], -PI, PI)
			session.commands = {roll = clampf(-1.5 * eb[2] - 0.35 * before[10], -1.0, 1.0),
				pitch = clampf(1.5 * (pitch - eb[1]) - 0.4 * before[11], -1.0, 1.0),
				yaw = clampf(0.8 * heading_error - 0.3 * before[12], -1.0, 1.0), throttle = 0.0}
		session.sim.inputs = session._inputs()
		session.sim.step()
		session._physics_process(dt)
		var after: PackedFloat64Array = session.sim.state
		var qa := M.quat(after[6], after[7], after[8], after[9])
		var comp: PackedFloat64Array = session.gear_compressions(after)
		var any_down := false
		for i in comp.size():
			if comp[i] > 0.0:
				any_down = true
				if not touched and first_contact.is_empty():
					first_contact = str(gear.contacts[i].name)
				max_frac[i] = maxf(max_frac[i], comp[i] / float(gear.contacts[i].max_compression))
		for contact: Dictionary in session.soft_contacts:
			var index: int = int(contact.get("index", -1))
			scraped[names[index] if index >= 0 and index < names.size() else str(index)] = true
		var down_before: float = M.q_rotate(qb, M.v3(before[3], before[4], before[5]))[2]
		var down_after: float = M.q_rotate(qa, M.v3(after[3], after[4], after[5]))[2]
		if any_down and not touched:
			touched = true
			w_in = down_before
		if touched:
			var lowest_wheel := INF
			for c: float in comp:
				lowest_wheel = minf(lowest_wheel, -c)
			max_bounce = maxf(max_bounce, lowest_wheel)
			if not any_down:
				airborne_after += dt
			if was_down and not any_down:
				bounces += 1
				if is_nan(w_out):
					w_out = -down_after
			max_n = maxf(max_n, 1.0 - (down_after - down_before) / dt / G)
		was_down = any_down
	out.crash = "" if session.crash.is_empty() else str(session.crash.get("why", "crash"))
	out.fault = session.sim.fault_reason
	out.max_compression_fraction = Array(max_frac)
	out.contact_names = Array(gear.contacts.map(func(c: Dictionary) -> String: return str(c.name)))
	out.bounces = bounces
	out.airborne_after_touch_s = airborne_after
	out.max_bounce_m = max_bounce
	out.peak_load_factor = max_n
	out.first_contact = first_contact
	out.w_in = w_in
	out.w_out = w_out
	out.scraped = scraped.keys()
	out.prop_strike = not session.prop_strike.is_empty()
	out.final_speed = M.norm(M.v3(session.sim.state[3], session.sim.state[4], session.sim.state[5]))
	session.free()
	return out
