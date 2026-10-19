# AV-07: the SebArt Avanti S (A200) with its JetCat P100-RX flown through the real session loop.
# Consistency and broad plausibility checks of an experimental model. Model-derived predictions and borrowed
# research ranges do not identify this aircraft. AV-16 requires complete finite traces through the session callback;
# its research matrix separately measures flight-path geometry and both-sign responses.
# Run: godot --headless --path . --script res://tests/test_avanti_handling.gd
extends SceneTree

const FlightSession := preload("res://sim/flight_session.gd")
const Maneuvers := preload("res://sim/maneuvers.gd")
const Commands := preload("res://input/commands.gd")
const Trim := preload("res://physics/trim.gd")
const Turbine := preload("res://physics/turbine.gd")
const Dynamics := preload("res://physics/dynamics.gd")
const RB := preload("res://physics/rigid_body.gd")
const Recorder := preload("res://sim/recorder.gd")
const Trace := preload("res://sim/trace.gd")

const DATA := "res://data/aircraft/sebart_avanti_s_a200.json"
const ID := "sebart-avanti-s-a200-p100rx"
const G := 9.80665

var _failures := 0
var _count := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	print(("ok   " if ok else "FAIL ") + label + "  " + detail)
	if not ok:
		_failures += 1


func _initialize() -> void:
	var session := FlightSession.new()
	session.setup(DATA, ID)
	root.add_child(session)
	_check("Avanti data loads and trims at its own start speed", session.aircraft.ok and session.start.get("ok", false), "%s %s" % [session.start.get("V", "?"), session.start.get("message", "")])
	if not session.aircraft.ok or not session.start.get("ok", false):
		print("%d checks, %d failed" % [_count, _failures + 1])
		quit(1)
		return
	var model: Dictionary = session.aircraft.model
	var prop: Dictionary = model.propulsion
	var a: Dictionary = model.aero
	var v0: float = model.start_speed
	var dt: float = session.sim.dt()
	_check("data id and turbine propulsion", model.id == ID and Turbine.is_turbine(prop), str(model.id))
	# The data must carry the ram recovery the derivation assumes (AV-06: a generator once dropped it and the loader,
	# for which it is optional, accepted the file): at 70 m/s and full rpm the thrust lapse is ~9 % of the bare law.
	_check("ram recovery present: thrust at 70 m/s, full rpm, 85–92 % of static", prop.has("ram_flow") and prop.has("ram_jet")
		and Turbine.thrust(float(prop.max_rpm), 70.0, prop, 1.225) / Turbine.thrust(float(prop.max_rpm), 0.0, prop, 1.225) > 0.85
		and Turbine.thrust(float(prop.max_rpm), 70.0, prop, 1.225) / Turbine.thrust(float(prop.max_rpm), 0.0, prop, 1.225) < 0.92,
		"%.3f" % (Turbine.thrust(float(prop.max_rpm), 70.0, prop, 1.225) / Turbine.thrust(float(prop.max_rpm), 0.0, prop, 1.225)))
	_check("mass: 10.5 kg dry (manual) + half of the 3.2 l tank, 11–12.5 kg", model.mass_kg > 11.0 and model.mass_kg < 12.5, "%.2f kg" % model.mass_kg)
	_check("span 2.00 m (manual)", absf(float(model.reference.b) - 2.0) < 1e-9)
	var j: PackedFloat64Array = model.inertia
	# The AV-06 window brackets GTM (underwing engines) and fighter radii; it does not replace the inventory. FUEL-05e put the
	# fuel at its Krill arm and removed 0.28 kg of virtual tail ballast that had compensated a mislocated tank, so Izz sits
	# at R_z ≈ 0.47, just below GTM's 0.49: the low end the AV-06 note expects for a single-turbine fuselage jet.
	_check("inertia within the research window (Ixx 0.55–0.90, Iyy 1.9–2.6, Izz 2.7–3.6 kg·m²)", j[0] > 0.55 and j[0] < 0.90 and j[1] > 1.9 and j[1] < 2.6 and j[2] > 2.7 and j[2] < 3.6,
		"%.3f %.3f %.3f" % [j[0], j[1], j[2]])

	# Trim at the start: low throttle (thrust follows the stick), small up elevator, wings level with no aileron
	# (a turbine has no reaction torque) and the governor settled on the demand.
	var st: Dictionary = session.start
	_check("trim: throttle 5–30 % at the start speed (cruise on little thrust)", st.throttle > 0.05 and st.throttle < 0.30, "%.1f %%" % (st.throttle * 100.0))
	_check("trim: elevator within a quarter of the throw", absf(st.pitch_command) < 0.25, "%.3f" % st.pitch_command)
	_check("trim: no aileron or rudder (no propeller torque, no slipstream)", absf(st.roll_command) < 1e-6 and absf(st.yaw_command) < 1e-6, "%s %s" % [st.roll_command, st.yaw_command])
	_check("trim: rpm = the ECU demand for the trim throttle", absf(st.rpm - Turbine.demand_rpm(st.throttle, prop)) < 1e-6, "%.0f rpm" % st.rpm)

	# Differential ailerons (manual p.4): full right roll = right aileron 30° up, left aileron 25° down.
	var d := Commands.surface_deflections_deg({ roll = 1.0, pitch = 0.0, yaw = 0.0 }, model.controls.throw_deg)
	_check("differential ailerons 30° up / 25° down", absf(d.aileron_right - 30.0) < 1e-9 and absf(d.aileron_left + 25.0) < 1e-9, "%.1f / %.1f" % [d.aileron_right, d.aileron_left])

	var hands_off := func(_t: float, _s: PackedFloat64Array) -> Dictionary: return Maneuvers._hands_off()
	# Hands-off 30 s at the start: the six-axis trim holds.
	var hold: RefCounted = _fly(session, { mode = "level", speed = v0, duration = 30.0, sticks = hands_off })
	var last: int = hold.row_count() - 1
	_check("hands-off 30 s: altitude within 2 m, speed within 0.3 m/s, finite", _finite(hold) and absf(hold.value(last, "alt_m") - hold.value(0, "alt_m")) < 2.0 and absf(hold.value(last, "speed_mps") - v0) < 0.3,
		"Δalt %.4f m, Δspeed %.5f m/s" % [hold.value(last, "alt_m") - hold.value(0, "alt_m"), hold.value(last, "speed_mps") - v0])

	# Spool-up through the session loop: full throttle from the trim. Predicted time to 95 % of maximum thrust from the
	# data's own schedule (integrated here at the tick); envelope 2–4.5 s (P100 traces and models, AV-05 report).
	var up := { mode = "level", speed = v0, altitude = 150.0, duration = 6.0, sticks = func(t: float, _s: PackedFloat64Array) -> Dictionary:
		return Maneuvers._pulse(t, 0.0, 6.0, { throttle_delta = 1.0 }) }
	var ut: RefCounted = _fly(session, up)
	var target := _rpm_for_thrust_fraction(prop, 0.95)
	var t_flown := _first_time(ut, "engine_rpm", target, dt)
	var t_predicted := _spool_time(st.rpm, 1.0, target, prop, dt)
	_check("spool-up in flight follows the data's schedule (95 %% thrust at %.2f s)" % t_predicted, absf(t_flown - t_predicted) <= 1.5 * dt, "%.3f s" % t_flown)
	var t_idle_up := _spool_time(float(prop.idle_rpm), 1.0, target, prop, dt)
	_check("spool-up idle → 95 % thrust within 2–4.5 s (P100 evidence)", t_idle_up > 2.0 and t_idle_up < 4.5, "%.2f s" % t_idle_up)
	_check("thrust lags the throttle: speed gain in the first 0.5 s below 1 m/s", ut.value(roundi(0.5 / dt), "speed_mps") - v0 < 1.0, "%.2f m/s" % (ut.value(roundi(0.5 / dt), "speed_mps") - v0))
	var t_down := _spool_time(float(prop.max_rpm), 0.0, _rpm_for_thrust_fraction(prop, 0.05), prop, dt)
	_check("spool-down max → 5 % thrust faster than spool-up, within 0.8–2.5 s", t_down < t_idle_up and t_down > 0.8 and t_down < 2.5, "%.2f s" % t_down)

	# Coordinated roll at the manual's normal-flight rate (aileron D/R 50 %) vs the single-axis prediction
	# p = −Clδa·(δup + δdown)/Clp · 2V/b (± 7 %, as for the other aircraft). At full high-rate throw the helix angle
	# pb/2V reaches 0.25 and the wing tips leave the linear range, so the linear prediction is checked at half stick.
	for v in [v0, 45.0]:
		var roll := { mode = "level", speed = v, altitude = 150.0, duration = 3.0, sticks = func(t: float, s: PackedFloat64Array) -> Dictionary:
			return Maneuvers._coordinated(Maneuvers._pulse(t, 0.25, 1.75, { roll = 0.5 }), s) }
		var tr: RefCounted = _fly(session, roll)
		var swing: float = 0.5 * (float(model.controls.throw_rad.aileron) + float(model.controls.throw_rad.aileron_down))
		var predicted := rad_to_deg(-float(a.Clda_left) * swing / float(a.Clp) * 2.0 * v / float(model.reference.b))
		var p := rad_to_deg(_max(tr, "p_radps"))
		_check("coordinated roll, D/R 50 %% at %.0f m/s: %.0f°/s ± 7 %% (single-axis prediction)" % [v, predicted], absf(p - predicted) <= 0.07 * predicted, "%.1f°/s" % p)

	# Maximum level speed: the trim holds full throttle just below it and needs more than full throttle just above.
	var vmax := _vmax(model)
	_check("predicted maximum level speed 60–80 m/s (model regression, not a safe-speed limit)", vmax > 60.0 and vmax < 80.0, "%.1f m/s (%.0f km/h)" % [vmax, vmax * 3.6])

	# Glide: power-off trim at 21 m/s; L/D in the sport-jet range 8–12 and finite.
	var gl := Trim.solve("glide", 21.0, model, G, model.controls.throw_rad)
	_check("power-off glide trims; L/D 8–12", gl.ok and -1.0 / tan(gl.gamma) > 8.0 and -1.0 / tan(gl.gamma) < 12.0, "L/D %.2f" % (-1.0 / tan(gl.gamma)))

	# Idle chop, hands off: once the spool is at idle the specific energy (V²/2 + g·h) falls at the drag-polar rate
	# (D − T_idle)·V/m. Measured over 1.5–2.5 s, while the airplane is still near its trimmed state, ± 15 %.
	var chop := { mode = "level", speed = v0, altitude = 150.0, duration = 2.5, sticks = func(_t: float, _s: PackedFloat64Array) -> Dictionary:
		return { roll = 0.0, pitch = 0.0, yaw = 0.0, throttle_delta = -1.0 } }
	var ct: RefCounted = _fly(session, chop)
	var r0 := roundi(1.5 / dt)
	var r1: int = ct.row_count() - 1
	var e_rate: float = (_energy(ct, r1) - _energy(ct, r0)) / ((r1 - r0) * dt)
	var vm: float = 0.5 * (ct.value(r0, "speed_mps") + ct.value(r1, "speed_mps"))
	var cl: float = model.mass_kg * G / (0.5 * 1.225 * vm * vm * float(model.reference.S))
	var drag: float = 0.5 * 1.225 * vm * vm * float(model.reference.S) * (float(a.CD0) + float(a.k_induced) * cl * cl)
	var e_pred: float = -(drag - Turbine.thrust(float(prop.idle_rpm), vm, prop, 1.225)) * vm / model.mass_kg
	_check("idle glide energy loss = (D − T_idle)·V/m ± 15 %% (%.1f m²/s³)" % e_pred, absf(e_rate - e_pred) < 0.15 * absf(e_pred) and _finite(ct), "%.1f m²/s³" % e_rate)
	_check("idle: the clean jet keeps its energy, deceleration-equivalent below 1.5 m/s²", -e_rate / vm < 1.5, "%.2f m/s²" % (-e_rate / vm))

	# Open-loop pitch input from 50 m/s. Integrated body q is a rotation diagnostic, not proof of a planar loop.
	# Speed above the 1-g estimate does not rule out accelerated stall; AV-16 records independent path geometry.
	var loop := { mode = "level", speed = 50.0, altitude = 150.0, duration = 8.0, sticks = func(t: float, _s: PackedFloat64Array) -> Dictionary:
		return Maneuvers._pulse(t, 0.2, 8.0, { pitch = 0.25, throttle_delta = 1.0 }) }
	var lt: RefCounted = _fly(session, loop)
	var turned := 0.0
	var loop_time := NAN
	for r in lt.row_count():
		turned += float(lt.value(r, "q_radps")) * dt
		if is_nan(loop_time) and turned >= TAU:
			loop_time = r * dt
	_check("pitch-input body-q integral exceeds 360° within 8 s, finite", turned >= TAU and _finite(lt), "%.0f° (%.1f s); not loop proof" % [rad_to_deg(turned), loop_time])
	_check("pitch-input minimum speed exceeds clean 1-g estimate (not an accelerated-stall test)", _min(lt, "speed_mps", 0.0, loop_time) > _stall_speed(model), "min %.1f m/s (1-g estimate %.1f)" % [_min(lt, "speed_mps", 0.0, loop_time), _stall_speed(model)])

	# Clean stall: 1-g stall speed 16–19.5 m/s (aero research: 17.2–17.9 m/s); power-off full up passes the stall start.
	var vs := _stall_speed(model)
	_check("clean 1-g stall speed 16–19.5 m/s", vs > 16.0 and vs < 19.5, "%.1f m/s" % vs)
	var stall := { mode = "glide", speed = 24.0, altitude = 150.0, duration = 4.0, sticks = func(t: float, _s: PackedFloat64Array) -> Dictionary:
		return Maneuvers._pulse(t, 0.25, 4.0, { pitch = 1.0 }) }
	var sl: RefCounted = _fly(session, stall)
	var alpha_max := -1e30
	for r in sl.row_count():
		alpha_max = maxf(alpha_max, atan2(float(sl.value(r, "w_mps")), float(sl.value(r, "u_mps"))))
	_check("full-up power-off: α passes the stall start, finite", alpha_max > model.envelope.a1 and _finite(sl), "α max %.1f° (stall start %.1f°)" % [rad_to_deg(alpha_max), rad_to_deg(model.envelope.a1)])

	# Spin entry at idle (full up + full right rudder for 3.75 s), opposite rudder 1 s, then neutral. This fuselage-
	# loaded jet (Iyy ≈ 4 Ixx) snaps and then wallows deep in the stall instead of settling into a steady spin; the
	# checks are the entry (deeply stalled, rotating) and the recovery (attached flow and slow rates 2 s later).
	var spin := { mode = "level", speed = 24.0, altitude = 300.0, duration = 8.0, sticks = func(t: float, _s: PackedFloat64Array) -> Dictionary:
		var c := Maneuvers._pulse(t, 0.25, 4.0, { pitch = 1.0, yaw = 1.0 })
		if t >= 4.0 and t < 5.0:
			c = { roll = 0.0, pitch = 0.0, yaw = -1.0, throttle_delta = 0.0 }
		c.throttle_delta = -1.0
		return c }
	var sp: RefCounted = _fly(session, spin)
	var alpha_entry := -1e30
	for r in range(roundi(1.0 / dt), roundi(4.0 / dt)):
		alpha_entry = maxf(alpha_entry, atan2(float(sp.value(r, "w_mps")), float(sp.value(r, "u_mps"))))
	_check("spin entry: deeply stalled and rotating (α > 25°, |ω| > 0.7 rad/s)", alpha_entry > deg_to_rad(25.0) and _max_rate(sp, 1.0, 4.0) > 0.7,
		"α %.0f°, |ω| %.2f rad/s" % [rad_to_deg(alpha_entry), _max_rate(sp, 1.0, 4.0)])
	var r_end: int = sp.row_count() - 1
	var alpha_end := atan2(float(sp.value(r_end, "w_mps")), float(sp.value(r_end, "u_mps")))
	_check("commanded stall-rotation recovery: terminal α < 10° and |ω| < 0.6 rad/s, finite", absf(alpha_end) < deg_to_rad(10.0) and _max_rate(sp, 7.0, 8.0) < 0.6 and _finite(sp),
		"α %.1f°, |ω| %.2f rad/s" % [rad_to_deg(alpha_end), _max_rate(sp, 7.0, 8.0)])
	_check("spin: height lost below 200 m", 300.0 - sp.value(r_end, "alt_m") < 200.0, "%.0f m" % (300.0 - sp.value(r_end, "alt_m")))

	# Gyroscopic coupling of the spool: a pitch rate q yaws the airplane by −(h × ω)_z = h·q / Izz.
	var h := Dynamics.rotor_momentum(model, float(prop.max_rpm))
	_check("spool angular momentum 0.3–1.0 N·m·s at full rpm (AV-05 estimate 0.56)", absf(h[0]) > 0.3 and absf(h[0]) < 1.0, "%.3f N·m·s" % h[0])

	_check("trace guard rejects an empty trace", not _finite(Trace.new()))
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)


## Shaft rpm at which the installed static thrust is a fraction of its maximum (inverts the data table).
func _rpm_for_thrust_fraction(prop: Dictionary, fraction: float) -> float:
	var lo: float = prop.idle_rpm
	var hi: float = prop.max_rpm
	var top := Turbine.thrust(hi, 0.0, prop, 1.225)
	for i in 60:
		var mid := 0.5 * (lo + hi)
		if Turbine.thrust(mid, 0.0, prop, 1.225) < fraction * top:
			lo = mid
		else:
			hi = mid
	return 0.5 * (lo + hi)


## Time (s) for the spool to cross `target` from `rpm` at a fixed throttle, stepping the data's law at the tick.
func _spool_time(rpm: float, throttle: float, target: float, prop: Dictionary, dt: float) -> float:
	var rising := target > rpm
	for i in 4000:
		rpm = Turbine.spool_step(rpm, throttle, dt, prop)
		if (rising and rpm >= target) or (not rising and rpm <= target):
			return (i + 1) * dt
	return INF


func _first_time(trace: RefCounted, column: String, target: float, dt: float) -> float:
	for r in trace.row_count():
		if float(trace.value(r, column)) >= target:
			return r * dt
	return INF


func _vmax(model: Dictionary) -> float:
	var lo := 40.0
	var hi := 100.0
	for i in 30:
		var mid := 0.5 * (lo + hi)
		var t := Trim.solve("level", mid, model, G, model.controls.throw_rad)
		if t.ok:
			lo = mid
		else:
			hi = mid
	return lo


func _energy(trace: RefCounted, r: int) -> float:
	return 0.5 * pow(float(trace.value(r, "speed_mps")), 2) + G * float(trace.value(r, "alt_m"))


func _max_rate(trace: RefCounted, t0: float, t1: float) -> float:
	var m := 0.0
	for r in trace.row_count():
		if trace.value(r, "t_s") >= t0 and trace.value(r, "t_s") <= t1:
			m = maxf(m, sqrt(pow(float(trace.value(r, "p_radps")), 2) + pow(float(trace.value(r, "q_radps")), 2) + pow(float(trace.value(r, "r_radps")), 2)))
	return m


func _stall_speed(model: Dictionary) -> float:
	return sqrt(2.0 * model.mass_kg * G / (1.225 * model.reference.S * model.envelope.CL_max))


func _finite(trace: RefCounted) -> bool:
	if trace.row_count() < 2 or not trace.is_continuous():
		return false
	for r in trace.row_count():
		for column in trace.columns():
			if not is_finite(trace.value(r, column)):
				return false
	return true


func _max(trace: RefCounted, column: String) -> float:
	var m := -1e30
	for r in trace.row_count():
		m = maxf(m, trace.value(r, column))
	return m


func _min(trace: RefCounted, column: String, t0: float, t1: float) -> float:
	var m := 1e30
	for r in trace.row_count():
		if trace.value(r, "t_s") >= t0 and (is_nan(t1) or trace.value(r, "t_s") <= t1):
			m = minf(m, trace.value(r, column))
	return m


func _max_abs(trace: RefCounted, column: String, t0: float, t1: float) -> float:
	var m := 0.0
	for r in trace.row_count():
		if trace.value(r, "t_s") >= t0 and trace.value(r, "t_s") <= t1:
			m = maxf(m, absf(trace.value(r, column)))
	return m


## AV-16: the full session callback supplies the flat-ground hull check that Maneuvers.fly omits.
func _fly(session: Node, maneuver: Dictionary) -> RefCounted:
	session.input_enabled = false
	var trim: Dictionary = session.trim_at(maneuver.speed, maneuver.mode)
	_check("maneuver trim succeeds", trim.get("ok", false), str(trim.get("message", "")))
	if not trim.get("ok", false):
		return Trace.new()
	session.set_start_altitude(float(maneuver.get("altitude", 150.0)))
	session.reset()
	var rec := Recorder.new(session.sim, session.electrical_state, Callable(session, "mass_properties"))
	rec.start(session.trace_meta())
	var steps := roundi(float(maneuver.duration) / session.sim.dt())
	for _i in steps:
		var sticks: Dictionary = maneuver.sticks.call(session.sim.time(), session.sim.state)
		session.commands = {roll = sticks.roll, pitch = sticks.pitch, yaw = sticks.yaw,
			throttle = clampf(float(session.start.throttle) + sticks.throttle_delta, 0.0, 1.0)}
		session.sim.inputs = session._inputs()
		session._physics_process(session.sim.dt())
		if not session.crash.is_empty() or not session.sim.fault_reason.is_empty() or session.sim.paused:
			break
		session.sim.step()
	session._physics_process(0.0)
	rec.detach()
	_check("maneuver trace complete, continuous and finite; no crash/fault/pause",
		rec.trace.row_count() == steps + 1 and _finite(rec.trace)
		and session.crash.is_empty() and session.sim.fault_reason.is_empty() and not session.sim.paused,
		"%d/%d rows; %s" % [rec.trace.row_count(), steps + 1, session.sim.fault_reason])
	return rec.trace
