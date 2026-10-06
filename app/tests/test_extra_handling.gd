# EX-07/EX-08 (first part): the Extra 300S flown through the real session loop. Predictions come from the Extra's own
# data file (single-axis formulas over its coefficients), so this VERIFIES the implementation and the data's
# consistency; it does not validate the airplane (EX-09). The Ugly Stik's handling checks stay in test_handling.gd.
# Run: godot --headless --path . --script res://tests/test_extra_handling.gd
extends SceneTree

const FlightSession := preload("res://sim/flight_session.gd")
const Maneuvers := preload("res://sim/maneuvers.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const RB := preload("res://physics/rigid_body.gd")

const EXTRA := "gp-extra-300s-60"

var _failures := 0
var _count := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	print(("ok   " if ok else "FAIL ") + label + "  " + detail)
	if not ok:
		_failures += 1


func _max(trace: RefCounted, column: String) -> float:
	var m := -1e30
	for r in trace.row_count():
		m = maxf(m, trace.value(r, column))
	return m


func _finite(trace: RefCounted) -> bool:
	for r in trace.row_count():
		for column in ["alt_m", "speed_mps", "p_radps", "q_radps", "r_radps"]:
			if not is_finite(trace.value(r, column)):
				return false
	return true


func _initialize() -> void:
	var session := FlightSession.new()
	session.setup(Catalog.entry(EXTRA).data)
	root.add_child(session)
	_check("Extra data loads and trims at its own start speed", session.aircraft.ok and session.start.get("ok", false), str(session.start.get("V", "?")))
	if not session.aircraft.ok:
		print("%d checks, %d failed" % [_count, _failures + 1])
		quit(1)
		return
	var model: Dictionary = session.aircraft.model
	var a: Dictionary = model.aero
	var v0: float = model.start_speed
	var hands_off := func(_t: float, _s: PackedFloat64Array) -> Dictionary: return Maneuvers._hands_off()

	# Hands-off 30 s at the start (EX-07 acceptance): the six-axis trim holds; the 0-dihedral spiral mode is slow.
	var hold: RefCounted = Maneuvers.fly(session, { mode = "level", speed = v0, duration = 30.0, sticks = hands_off })
	var last: int = hold.row_count() - 1
	_check("hands-off 30 s: finite", _finite(hold))
	_check("hands-off 30 s: altitude within 1 m, speed within 0.2 m/s", absf(hold.value(last, "alt_m") - hold.value(0, "alt_m")) < 1.0 and absf(hold.value(last, "speed_mps") - v0) < 0.2,
		"Δalt %.4f m, Δspeed %.5f m/s" % [hold.value(last, "alt_m") - hold.value(0, "alt_m"), hold.value(last, "speed_mps") - v0])

	# Coordinated full-aileron roll vs the single-axis prediction −2·Clδa·δa/Clp · 2V/b (± 7 %, as for the Stik).
	for v in [v0, 22.0]:
		var roll := { mode = "level", speed = v, duration = 2.5, sticks = func(t: float, s: PackedFloat64Array) -> Dictionary:
			return Maneuvers._coordinated(Maneuvers._pulse(t, 0.25, 1.25, { roll = 1.0 }), s) }
		var tr: RefCounted = Maneuvers.fly(session, roll)
		var predicted := rad_to_deg(-2.0 * float(a.Clda_left) * float(model.controls.throw_rad.aileron) / float(a.Clp) * 2.0 * v / float(model.reference.b))
		var p := rad_to_deg(_max(tr, "p_radps"))
		_check("coordinated roll at %.0f m/s: %.0f°/s ± 7 %% (single-axis prediction)" % [v, predicted], absf(p - predicted) <= 0.07 * predicted, "%.1f°/s" % p)

	# Inside loop the way a pilot flies it on high rates: 0.3 stick (≈ 7° of elevator) and full throttle from 20 m/s,
	# from 100 m. The pitch attitude goes all the way round (∫q dt ≥ 2π) within 6 s, flying over the top.
	var loop := { mode = "level", speed = 20.0, altitude = 100.0, duration = 6.0, sticks = func(t: float, _s: PackedFloat64Array) -> Dictionary:
		return Maneuvers._pulse(t, 0.2, 6.0, { pitch = 0.3, throttle_delta = 1.0 }) }
	var lt: RefCounted = Maneuvers.fly(session, loop)
	var turned := 0.0
	var loop_time := NAN
	for r in lt.row_count():
		turned += float(lt.value(r, "q_radps")) * session.sim.dt()
		if is_nan(loop_time) and turned >= TAU:
			loop_time = r * session.sim.dt()
	_check("inside loop at 0.3 stick: 360° of pitch within 6 s, finite", turned >= TAU and _finite(lt), "%.0f° (%.1f s)" % [rad_to_deg(turned), loop_time])
	_check("inside loop: faster than the 1-g stall speed over the top", _min(lt, "speed_mps", 0.0, loop_time) > _stall_speed(model),
		"min %.1f m/s (1-g stall %.1f)" % [_min(lt, "speed_mps", 0.0, loop_time), _stall_speed(model)])
	# Full high-rate elevator at 20 m/s asks for more lift than the wing has: it stalls (manual p43: "too much throw
	# can force the plane into a stall or snap roll"). The airplane stays finite.
	var yank := { mode = "level", speed = 20.0, altitude = 100.0, duration = 2.0, sticks = func(t: float, _s: PackedFloat64Array) -> Dictionary:
		return Maneuvers._pulse(t, 0.2, 2.0, { pitch = 1.0 }) }
	var yt: RefCounted = Maneuvers.fly(session, yank)
	var yank_alpha := -1e30
	for r in yt.row_count():
		yank_alpha = maxf(yank_alpha, atan2(float(yt.value(r, "w_mps")), float(yt.value(r, "u_mps"))))
	_check("full high-rate up elevator at 20 m/s stalls the wing, finite", yank_alpha > model.envelope.a1 and _finite(yt), "α max %.1f° (stall start %.1f°)" % [rad_to_deg(yank_alpha), rad_to_deg(model.envelope.a1)])

	# Power-off full-up stall from 12 m/s: α goes past the solved stall start and the loads stay finite.
	var stall := { mode = "glide", speed = 12.0, duration = 4.0, sticks = func(t: float, _s: PackedFloat64Array) -> Dictionary:
		return Maneuvers._pulse(t, 0.25, 4.0, { pitch = 1.0 }) }
	var st: RefCounted = Maneuvers.fly(session, stall)
	var alpha_max := -1e30
	for r in st.row_count():
		alpha_max = maxf(alpha_max, atan2(float(st.value(r, "w_mps")), float(st.value(r, "u_mps"))))
	_check("full-up power-off: α passes the stall start, finite", alpha_max > model.envelope.a1 and _finite(st), "α max %.1f° (stall start %.1f°)" % [rad_to_deg(alpha_max), rad_to_deg(model.envelope.a1)])

	# Spin entry (idle, full up + full right rudder for 3.75 s), standard recovery (opposite rudder, stick forward)
	# for 1 s, then neutral: the rotation stops within 3 s of starting the recovery.
	var spin := { mode = "level", speed = 12.0, altitude = 150.0, duration = 8.0, sticks = func(t: float, _s: PackedFloat64Array) -> Dictionary:
		var c := Maneuvers._pulse(t, 0.25, 4.0, { pitch = 1.0, yaw = 1.0 })
		if t >= 4.0 and t < 5.0:
			c = { roll = 0.0, pitch = -0.5, yaw = -1.0, throttle_delta = 0.0 }
		c.throttle_delta = -1.0
		return c }
	var sp: RefCounted = Maneuvers.fly(session, spin)
	var r_entry := _max_abs(sp, "r_radps", 2.0, 4.0)
	var r_after := _max_abs(sp, "r_radps", 7.0, 8.0)
	_check("spin: right rudder + full up yaws right", _max(sp, "r_radps") > 1.0, "r max %.2f rad/s" % r_entry)
	_check("spin recovery: yaw rate below 0.5 rad/s 3 s after recovery input, finite", r_after < 0.5 and _finite(sp), "%.2f rad/s" % r_after)
	_check("spin: still above the ground at the end (the check is not measured underground)", sp.value(sp.row_count() - 1, "alt_m") > 0.0, "%.0f m" % sp.value(sp.row_count() - 1, "alt_m"))

	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)


func _stall_speed(model: Dictionary) -> float:
	return sqrt(2.0 * model.mass_kg * 9.80665 / (1.225 * model.reference.S * model.envelope.CL_max))


func _min(trace: RefCounted, column: String, t0: float, t1: float) -> float:
	var m := 1e30
	var dt := 1.0 / 240.0
	for r in trace.row_count():
		if r * dt >= t0 and (is_nan(t1) or r * dt <= t1):
			m = minf(m, trace.value(r, column))
	return m


func _max_abs(trace: RefCounted, column: String, t0: float, t1: float) -> float:
	var m := 0.0
	var dt := 1.0 / 240.0
	for r in trace.row_count():
		if r * dt >= t0 and r * dt <= t1:
			m = maxf(m, absf(trace.value(r, column)))
	return m
