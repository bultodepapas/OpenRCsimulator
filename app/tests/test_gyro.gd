# D9c: gyroscopic precession of the propeller and crankshaft (clockwise seen from behind).
# Run: godot --headless --path . --script res://tests/test_gyro.gd
extends SceneTree

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const RK := preload("res://physics/integrator.gd")
const AD := preload("res://physics/aircraft_data.gd")
const Scenarios := preload("res://sim/scenarios.gd")
const FlightSession := preload("res://sim/flight_session.gd")
const Maneuvers := preload("res://sim/maneuvers.gd")

var _failures := 0
var _count := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	print(("ok   " if ok else "FAIL ") + label + "  " + detail)
	if not ok:
		_failures += 1


func _initialize() -> void:
	var model: Dictionary = AD.load_file(Scenarios.AIRCRAFT).model
	var j: PackedFloat64Array = model.inertia
	var j_inv := RB.inertia_inverse(j)
	var jp: float = model.propulsion.rotor_inertia
	var h := jp * 11149.0 * TAU / 60.0
	_check("rotor angular momentum at full rpm ≈ 0.41 N·m·s", absf(h - 0.4086) < 0.001, "%.4f" % h)

	# Sign and size: pitching up at 1 rad/s with a clockwise rotor → nose-right yaw acceleration = J⁻¹·(0, 0, q·h).
	var s := RB.make_state(M.v3(0, 0, -50), M.v3(15, 0, 0), M.q_identity(), M.v3(0.0, 1.0, 0.0))
	var hv := M.v3(h, 0.0, 0.0)
	var with := RB.derivative(s, model.mass_kg, j, j_inv, M.v3(0, 0, 0), M.v3(0, 0, 0), 9.80665, hv)
	var without := RB.derivative(s, model.mass_kg, j, j_inv, M.v3(0, 0, 0), M.v3(0, 0, 0), 9.80665)
	var expect := RB.inertia_mul(j_inv, M.v3(0.0, 0.0, 1.0 * h))
	var dr := with[RB.RATE + 2] - without[RB.RATE + 2]
	_check("pull up (q > 0), clockwise prop → nose yaws RIGHT (ṙ > 0)", dr > 0.0, "Δṙ %.3f rad/s²" % dr)
	_check("size: Δω̇ = J⁻¹·(0, 0, q·h)", absf(dr - expect[2]) < 1e-12 and absf(with[RB.RATE] - without[RB.RATE] - expect[0]) < 1e-12)
	var s2 := RB.make_state(M.v3(0, 0, -50), M.v3(15, 0, 0), M.q_identity(), M.v3(0.0, 0.0, 1.0))
	var dq := RB.derivative(s2, model.mass_kg, j, j_inv, M.v3(0, 0, 0), M.v3(0, 0, 0), 9.80665, hv)[RB.RATE + 1] \
		- RB.derivative(s2, model.mass_kg, j, j_inv, M.v3(0, 0, 0), M.v3(0, 0, 0), 9.80665)[RB.RATE + 1]
	_check("yaw right (r > 0), clockwise prop → nose pitches DOWN (q̇ < 0)", dq < 0.0, "Δq̇ %.3f rad/s²" % dq)

	# Torque-free tumble with a spinning rotor: total angular momentum R·(Jω + h) is conserved over 60 s.
	var st := RB.make_state(M.v3(0, 0, 0), M.v3(0, 0, 0), M.q_identity(), M.v3(2.0, 1.0, -1.5))
	var l0 := M.q_rotate(M.quat(st[RB.ATT], st[RB.ATT + 1], st[RB.ATT + 2], st[RB.ATT + 3]), M.add(RB.inertia_mul(j, M.v3(st[RB.RATE], st[RB.RATE + 1], st[RB.RATE + 2])), hv))
	var f := func(x: PackedFloat64Array) -> PackedFloat64Array:
		return RB.derivative(x, model.mass_kg, j, j_inv, M.v3(0, 0, 0), M.v3(0, 0, 0), 0.0, hv)
	for i in 60 * 240:
		st = RK.rk4_step(st, 1.0 / 240.0, f)
	var l1 := M.q_rotate(M.quat(st[RB.ATT], st[RB.ATT + 1], st[RB.ATT + 2], st[RB.ATT + 3]), M.add(RB.inertia_mul(j, M.v3(st[RB.RATE], st[RB.RATE + 1], st[RB.RATE + 2])), hv))
	var rel := M.norm(M.sub(l1, l0)) / M.norm(l0)
	_check("torque-free tumble with the rotor: total angular momentum conserved to 1e-6 over 60 s", rel < 1e-6, String.num_scientific(rel))

	# Flown: the full-throttle pull-up yaws further right with the gyro than without it.
	var session := FlightSession.new()
	session.setup()
	root.add_child(session)
	var tr: RefCounted = Maneuvers.fly(session, Maneuvers.all().pull_throttle)
	var row := roundi(1.5 * 240)
	var r_with: float = tr.value(row, "r_radps")
	session.aircraft.model.propulsion.rotor_inertia = 0.0
	tr = Maneuvers.fly(session, Maneuvers.all().pull_throttle)
	var r_without: float = tr.value(row, "r_radps")
	_check("flown pull-up at full throttle: yaw rate more to the right with the gyro", r_with > r_without + 0.01, "r %.3f vs %.3f rad/s" % [r_with, r_without])

	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)
