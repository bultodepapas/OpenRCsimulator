# P51-07: the P-51D Mustang 120 cc flown through the real session loop. Predictions come from the P-51's own data
# file (single-axis formulas over its coefficients), so this VERIFIES the implementation and the data's consistency;
# it does not validate the airplane (no flight identification yet). Speeds scale with its 25 m/s start.
# Run: godot --headless --path . --script res://tests/test_p51_handling.gd
extends SceneTree

const FlightSession := preload("res://sim/flight_session.gd")
const Maneuvers := preload("res://sim/maneuvers.gd")
const RB := preload("res://physics/rigid_body.gd")

const DATA := "res://data/aircraft/p51d_mustang_120.json"
const ID := "p51d-mustang-120"

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
	session.setup(DATA)
	root.add_child(session)
	_check("P-51 data loads and trims at its own start speed", session.aircraft.ok and session.start.get("ok", false), str(session.start.get("V", "?")) + " " + str(session.start.get("message", "")))
	if not session.aircraft.ok or not session.start.get("ok", false):
		print("%d checks, %d failed" % [_count, _failures + 1])
		quit(1)
		return
	var model: Dictionary = session.aircraft.model
	var a: Dictionary = model.aero
	var v0: float = model.start_speed
	_check("data id", model.id == ID, str(model.id))
	_check("giant-scale mass and span", model.mass_kg > 15.0 and model.mass_kg < 23.0 and absf(float(model.reference.b) - 2.82) < 0.01, "%.2f kg, %.3f m" % [model.mass_kg, model.reference.b])
	_check("trim throttle leaves a climb reserve (below 85 %)", session.start.throttle < 0.85, "%.0f %%" % (session.start.throttle * 100.0))
	_check("trim elevator within half the throw", absf(session.start.get("pitch_command", 0.0)) < 0.5, str(session.start.get("pitch_command", "?")))
	var hands_off := func(_t: float, _s: PackedFloat64Array) -> Dictionary: return Maneuvers._hands_off()

	# Hands-off 30 s at the start: the six-axis trim holds (the 5° dihedral gives a slow, stable spiral mode).
	var hold: RefCounted = Maneuvers.fly(session, { mode = "level", speed = v0, duration = 30.0, sticks = hands_off })
	var last: int = hold.row_count() - 1
	_check("hands-off 30 s: finite", _finite(hold))
	_check("hands-off 30 s: altitude within 2 m, speed within 0.3 m/s", absf(hold.value(last, "alt_m") - hold.value(0, "alt_m")) < 2.0 and absf(hold.value(last, "speed_mps") - v0) < 0.3,
		"Δalt %.4f m, Δspeed %.5f m/s" % [hold.value(last, "alt_m") - hold.value(0, "alt_m"), hold.value(last, "speed_mps") - v0])

	# Coordinated full-aileron roll vs the single-axis prediction −2·Clδa·δa/Clp · 2V/b (± 7 %, as for the Stik and Extra).
	for v in [v0, 27.0]: # 27 m/s: below the full-throttle level maximum of this propeller (derivation.md)
		var roll := { mode = "level", speed = v, duration = 3.0, sticks = func(t: float, s: PackedFloat64Array) -> Dictionary:
			return Maneuvers._coordinated(Maneuvers._pulse(t, 0.25, 1.75, { roll = 1.0 }), s) }
		var tr: RefCounted = Maneuvers.fly(session, roll)
		var predicted := rad_to_deg(-2.0 * float(a.Clda_left) * float(model.controls.throw_rad.aileron) / float(a.Clp) * 2.0 * v / float(model.reference.b))
		var p := rad_to_deg(_max(tr, "p_radps"))
		_check("coordinated roll at %.0f m/s: %.0f°/s ± 7 %% (single-axis prediction)" % [v, predicted], absf(p - predicted) <= 0.07 * predicted, "%.1f°/s" % p)

	# Inside loop as a pilot flies a warbird: 0.7 stick (≈10° of elevator) and full throttle from 27 m/s, from 150 m: round within 8 s.
	var loop := { mode = "level", speed = 27.0, altitude = 150.0, duration = 8.0, sticks = func(t: float, _s: PackedFloat64Array) -> Dictionary:
		return Maneuvers._pulse(t, 0.2, 8.0, { pitch = 0.7, throttle_delta = 1.0 }) }
	var lt: RefCounted = Maneuvers.fly(session, loop)
	var turned := 0.0
	var loop_time := NAN
	for r in lt.row_count():
		turned += float(lt.value(r, "q_radps")) * session.sim.dt()
		if is_nan(loop_time) and turned >= TAU:
			loop_time = r * session.sim.dt()
	_check("inside loop at 0.7 stick from 27 m/s: 360° of pitch within 8 s, finite", turned >= TAU and _finite(lt), "%.0f° (%.1f s)" % [rad_to_deg(turned), loop_time])
	_check("inside loop: faster than the 1-g stall speed over the top", _min(lt, "speed_mps", 0.0, loop_time) > _stall_speed(model),
		"min %.1f m/s (1-g stall %.1f)" % [_min(lt, "speed_mps", 0.0, loop_time), _stall_speed(model)])

	# Power-off full-up stall from 18 m/s: α goes past the solved stall start and the loads stay finite.
	var stall := { mode = "glide", speed = 18.0, duration = 4.0, sticks = func(t: float, _s: PackedFloat64Array) -> Dictionary:
		return Maneuvers._pulse(t, 0.25, 4.0, { pitch = 1.0 }) }
	var st: RefCounted = Maneuvers.fly(session, stall)
	var alpha_max := -1e30
	for r in st.row_count():
		alpha_max = maxf(alpha_max, atan2(float(st.value(r, "w_mps")), float(st.value(r, "u_mps"))))
	_check("full-up power-off: α passes the stall start, finite", alpha_max > model.envelope.a1 and _finite(st), "α max %.1f° (stall start %.1f°)" % [rad_to_deg(alpha_max), rad_to_deg(model.envelope.a1)])

	# Spin entry (idle, full up + full right rudder for 3.75 s), standard recovery for 1 s, then neutral: the
	# rotation stops within 3 s of starting the recovery. A heavy warbird starts from 200 m.
	var spin := { mode = "level", speed = 18.0, altitude = 200.0, duration = 8.0, sticks = func(t: float, _s: PackedFloat64Array) -> Dictionary:
		var c := Maneuvers._pulse(t, 0.25, 4.0, { pitch = 1.0, yaw = 1.0 })
		if t >= 4.0 and t < 5.0:
			c = { roll = 0.0, pitch = -0.5, yaw = -1.0, throttle_delta = 0.0 }
		c.throttle_delta = -1.0
		return c }
	var sp: RefCounted = Maneuvers.fly(session, spin)
	var r_entry := _max_abs(sp, "r_radps", 2.0, 4.0)
	var r_after := _max_abs(sp, "r_radps", 7.0, 8.0)
	_check("spin: right rudder + full up yaws right", _max(sp, "r_radps") > 0.7, "r max %.2f rad/s" % r_entry)
	_check("spin recovery: yaw rate below 0.5 rad/s 3 s after recovery input, finite", r_after < 0.5 and _finite(sp), "%.2f rad/s" % r_after)
	_check("spin: still above the ground at the end", sp.value(sp.row_count() - 1, "alt_m") > 0.0, "%.0f m" % sp.value(sp.row_count() - 1, "alt_m"))

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
