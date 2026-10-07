# E3b3: full-throttle takeoff roll from the E3b2 runway start, against an independent 1-D model integral that uses the
# same mass, propeller data, aero and runway rolling resistance (point mass along the runway, attitude fixed, RK4).
# Bands: while the airplane still sits at its rest attitude (x ≤ 5 m) V(x) agrees within 0.5 %; up to 20 m within 3 %
# (the 6-DOF airplane rotates as the nose unloads: more lift, less rolling resistance); the lift-off distance within
# 10 % of the 1-D distance to the same speed. Attitude-matched check: the same 1-D integral driven by the 6-DOF's
# recorded pitch reproduces V(x) within 0.2 % (baseline 0.07 %), so the remaining difference is rotation, not ground
# coupling; a 10 % rolling-resistance error moves V by about 0.35 % and fails it.
# Records that propeller wash is off for the Stik (no slipstream data).
# Run: godot --headless --path . --script res://tests/test_takeoff_roll.gd
extends SceneTree

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Ground := preload("res://physics/ground_contact.gd")
const GroundStart := preload("res://physics/ground_start.gd")
const Dynamics := preload("res://physics/dynamics.gd")
const Propulsion := preload("res://physics/propulsion.gd")
const Air := preload("res://physics/air_data.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const FlightSession := preload("res://sim/flight_session.gd")

const G := 9.80665
const RUNWAY_ROLLING := 2.5 # surface_friction.json runway rolling factor (test_ground_surfaces pins it)
const DT_1D := 1.0 / 4800.0
const MARKS := [1.0, 2.0, 5.0, 10.0, 15.0, 20.0]

var _failures := 0
var _count := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	print(("ok   " if ok else "FAIL ") + label + ("" if detail.is_empty() else "  " + detail))
	if not ok:
		_failures += 1


func _initialize() -> void:
	var f := FieldLoader.load_from()
	var session := FlightSession.new()
	session.setup()
	root.add_child(session)
	session.input_enabled = false
	session.set_field(f.field)
	var spot := GroundStart.threshold(f.field)
	_check("runway start", session.reset_on_runway(spot.north, spot.east, spot.heading))
	var model: Dictionary = session.aircraft.model
	_check("record: propeller wash is OFF for the Stik (no slipstream data); E0b may change this roll",
		model.propulsion.get("slipstream", {}).is_empty())
	var rest: PackedFloat64Array = session.sim.state.duplicate()
	var aux0: PackedFloat64Array = session.sim.aux.duplicate()
	var d: Dictionary = session._deflections(aux0)
	var run := _roll_6dof(session, rest)
	_check("6-DOF: every anchor releases and the airplane lifts off within 4 s, no fault or crash", not run.lof.is_empty(),
		"lift-off t %.3f s, x %.2f m, V %.2f m/s, pitch %.2f°, lateral drift %.2f m" % [run.lof.get("t", -1.0), run.lof.get("x", -1.0),
			run.lof.get("v", -1.0), run.lof.get("pitch", 0.0), run.lof.get("y", 0.0)])
	if run.lof.is_empty():
		print("%d checks, %d failed" % [_count, _failures])
		quit(1)
		return
	var fixed := _roll_1d(model, rest, d, aux0[0], PackedFloat64Array(), PackedFloat64Array(), run.lof.v)
	var guided := _roll_1d(model, rest, d, aux0[0], run.x, run.pitch, run.lof.v)
	var worst_early := 0.0
	var worst_all := 0.0
	var worst_guided := 0.0
	for i in MARKS.size():
		var mark: float = MARKS[i]
		var v6: float = _interp(run.x, run.v, mark)
		var e_fixed: float = absf(fixed.v_at[i] - v6) / v6
		var e_guided: float = absf(guided.v_at[i] - v6) / v6
		print("info x %4.1f m: 6-DOF %.3f m/s (pitch %+.2f°), 1-D fixed %.3f (%.2f %%), 1-D with 6-DOF pitch %.3f (%.2f %%)"
			% [mark, v6, _interp(run.x, run.pitch_deg, mark), fixed.v_at[i], 100.0 * e_fixed, guided.v_at[i], 100.0 * e_guided])
		if mark <= 5.0:
			worst_early = maxf(worst_early, e_fixed)
		worst_all = maxf(worst_all, e_fixed)
		worst_guided = maxf(worst_guided, e_guided)
	_check("V(x) at the rest attitude (x ≤ 5 m) within 0.5 % of the 1-D integral", worst_early < 0.005, "worst %.3f %%" % (100.0 * worst_early))
	_check("V(x) up to 20 m within 3 % of the 1-D integral (rotation adds lift)", worst_all < 0.03, "worst %.2f %%" % (100.0 * worst_all))
	_check("lift-off distance %.2f m within 10 %% of the 1-D distance to %.2f m/s (%.2f m)" % [run.lof.x, run.lof.v, fixed.x_at_lof],
		absf(run.lof.x - fixed.x_at_lof) < 0.1 * fixed.x_at_lof)
	_check("the 1-D integral with the 6-DOF's pitch history matches within 0.2 % (difference = rotation; detects a 10 % rolling error)",
		worst_guided < 0.002, "worst %.3f %%" % (100.0 * worst_guided))
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)


## Full throttle from the runway start, hands off at the trims. Records distance along the runway, speed and pitch
## until every wheel has left the ground.
func _roll_6dof(session: Node, rest: PackedFloat64Array) -> Dictionary:
	var inputs: PackedFloat64Array = session.sim.inputs.duplicate()
	inputs[3] = 1.0
	session.sim.inputs = inputs
	var gear: Dictionary = session.aircraft.model.landing_gear
	var out := { x = PackedFloat64Array([0.0]), v = PackedFloat64Array([0.0]), pitch = PackedFloat64Array([_pitch(rest)]),
		pitch_deg = PackedFloat64Array([rad_to_deg(_pitch(rest))]), lof = {} }
	for i in roundi(4.0 / session.sim.dt()):
		session.sim.step()
		if not session.sim.fault_reason.is_empty() or not session.crash.is_empty():
			return out
		var s: PackedFloat64Array = session.sim.state
		var x: float = s[RB.POS + 1] - rest[RB.POS + 1]
		out.x.append(x)
		out.v.append(sqrt(s[RB.VEL] ** 2 + s[RB.VEL + 1] ** 2 + s[RB.VEL + 2] ** 2))
		out.pitch.append(_pitch(s))
		out.pitch_deg.append(rad_to_deg(_pitch(s)))
		var c := Ground.compressions(s, gear)
		if c[0] <= 0.0 and c[1] <= 0.0 and c[2] <= 0.0:
			out.lof = { t = (i + 1) * session.sim.dt(), x = x, v = out.v[-1], pitch = out.pitch_deg[-1], y = s[RB.POS] - rest[RB.POS] }
			return out
	return out


## Point mass along the runway (east), RK4 at 4.8 kHz. Forces from Dynamics.loads (thrust, aero) at the rest attitude,
## or at the pitch interpolated from a recorded (x, pitch) history; normal load N = W + down-force; rolling C_rr·N.
## rpm follows the throttle lag (Propulsion.rpm_step) exactly. Returns { v_at (per MARK), x_at_lof }.
func _roll_1d(model: Dictionary, rest: PackedFloat64Array, d: Dictionary, rpm0: float, hist_x: PackedFloat64Array,
		hist_pitch: PackedFloat64Array, v_lof: float) -> Dictionary:
	var c_rr: float = model.landing_gear.rolling_resistance * RUNWAY_ROLLING
	var rest_euler := M.q_to_euler(PackedFloat64Array([rest[RB.ATT], rest[RB.ATT + 1], rest[RB.ATT + 2], rest[RB.ATT + 3]]))
	var accel := func(x: float, v: float, rpm: float) -> float:
		var pitch: float = rest_euler[1] if hist_x.is_empty() else _interp(hist_x, hist_pitch, x)
		var q := M.q_from_euler(rest_euler[0], pitch, rest_euler[2])
		var body_v := M.q_rotate(M.q_conj(q), M.v3(0.0, v, 0.0))
		var s := rest.duplicate()
		for k in 4:
			s[RB.ATT + k] = q[k]
		for k in 3:
			s[RB.VEL + k] = body_v[k]
		var l := Dynamics.loads(s, model, d, rpm, Air.RHO_SEA_LEVEL, PackedFloat64Array([0.0, 0.0, 0.0]))
		var fw := M.q_rotate(q, M.v3(l[0], l[1], l[2]))
		var n: float = maxf(0.0, model.mass_kg * G + fw[2])
		return (fw[1] - c_rr * n) / model.mass_kg
	var x := 0.0
	var v := 0.0
	var rpm := rpm0
	var t := 0.0
	var v_at := PackedFloat64Array()
	var x_at_lof := -1.0
	while (v_at.size() < MARKS.size() or x_at_lof < 0.0) and t < 6.0:
		var rpm_mid := Propulsion.rpm_step(rpm, 1.0, DT_1D / 2.0, model.propulsion)
		var rpm_end := Propulsion.rpm_step(rpm, 1.0, DT_1D, model.propulsion)
		var k1: float = accel.call(x, v, rpm)
		var k2: float = accel.call(x + 0.5 * DT_1D * v, v + 0.5 * DT_1D * k1, rpm_mid)
		var k3: float = accel.call(x + 0.5 * DT_1D * (v + 0.5 * DT_1D * k1), v + 0.5 * DT_1D * k2, rpm_mid)
		var k4: float = accel.call(x + DT_1D * (v + 0.5 * DT_1D * k2), v + DT_1D * k3, rpm_end)
		x += DT_1D / 6.0 * (v + 2.0 * (v + 0.5 * DT_1D * k1) + 2.0 * (v + 0.5 * DT_1D * k2) + (v + DT_1D * k3))
		v += DT_1D / 6.0 * (k1 + 2.0 * k2 + 2.0 * k3 + k4)
		rpm = rpm_end
		t += DT_1D
		while v_at.size() < MARKS.size() and x >= MARKS[v_at.size()]:
			v_at.append(v)
		if x_at_lof < 0.0 and v >= v_lof:
			x_at_lof = x
	return { v_at = v_at, x_at_lof = x_at_lof }


func _pitch(s: PackedFloat64Array) -> float:
	return M.q_to_euler(PackedFloat64Array([s[RB.ATT], s[RB.ATT + 1], s[RB.ATT + 2], s[RB.ATT + 3]]))[1]


func _interp(xs: PackedFloat64Array, ys: PackedFloat64Array, x: float) -> float:
	if x <= xs[0]:
		return ys[0]
	for i in range(1, xs.size()):
		if xs[i] >= x:
			return lerpf(ys[i - 1], ys[i], (x - xs[i - 1]) / (xs[i] - xs[i - 1]))
	return ys[-1]
