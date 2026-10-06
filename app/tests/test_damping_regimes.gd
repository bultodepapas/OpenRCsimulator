# D11b: the aerodynamic damping and lift slope must not change with the model's regime. Loads blend from the linear
# oracle (attached flow) to the local wing and tail elements between α ≈ 6° and 10°, which is where an approach at
# 1.3 V_s flies. Found by plan review #4 (docs/research/roadmap-investigations/02-aerodynamics-rc-scale.md) and
# re-measured by its lead: the local elements roll-damp 1.7× harder and pitch-damp 3× softer than the oracle.
# Derivatives are central differences of Aero.loads at 15 m/s, controls neutral, nondimensionalised like the data.
# KNOWN_DEFECT pins the defect at its documented size, so the suite stays green while it exists and fails on any
# change: worse, or fixed by D11d (strips) and E0a2 (tail). Whoever fixes it sets KNOWN_DEFECT to false, which turns
# the same measurements into the acceptance test (each derivative within ±15 % of the oracle at every α).
# Run: godot --headless --path . --script res://tests/test_damping_regimes.gd
extends SceneTree

const AD := preload("res://physics/aircraft_data.gd")
const Air := preload("res://physics/air_data.gd")
const Aero := preload("res://physics/aero.gd")
const Scenarios := preload("res://sim/scenarios.gd")

const KNOWN_DEFECT := true
## Documented size of the defect: worst ratio to the oracle (α 2°) over α 0…11°, measured 2026-10-06; checked within
## ±10 %. Roll damping 1.73× harder, pitch damping 0.28×, yaw damping 0.72×, and a lift-slope bump of 1.34× at α 7–8°.
const DEFECT := { Clp = 1.73, Cmq = 0.28, Cnr = 0.72, CLa = 1.34 }
## Acceptance band once fixed: every derivative within ±15 % of the oracle value at every α.
const BAND := 0.15
const V := 15.0
const RHO := 1.225

var _failures := 0
var _count := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	print("%s %s  %s" % ["ok  " if ok else "FAIL", label, detail])
	if not ok:
		_failures += 1


func _initialize() -> void:
	var data := AD.load_file(Scenarios.AIRCRAFT)
	_check("the Stik data loads", data.ok, str(data.errors))
	if not data.ok:
		quit(1)
		return
	var model: Dictionary = data.model
	var a: Dictionary = model.aero
	var rows := {}
	for deg in [0.0, 2.0, 4.0, 6.0, 7.0, 8.0, 9.0, 10.0, 11.0]:
		rows[deg] = _derivatives(model, deg_to_rad(deg))
	print("| α° | blend | Clp | Cmq | Cnr | CLα |")
	for deg in rows:
		var r: Dictionary = rows[deg]
		print("| %4.1f | %.2f | %.3f | %.2f | %.4f | %.3f |" % [deg, r.blend, r.Clp, r.Cmq, r.Cnr, r.CLa])

	# Verification: below the blend the loads are the oracle, so each derivative is the data's coefficient, within 1 %:
	# the oracle's moments are taken about the aerodynamic reference point (0.07 m above the CG) and moved to the CG, so
	# the force derivatives (CLq, CYp, CYr) add small α-dependent terms (≤ 0.7 % at α ≤ 4°).
	for deg in [0.0, 2.0, 4.0]:
		var r: Dictionary = rows[deg]
		_check("oracle region α %.0f°: blend weight is 0" % deg, r.blend == 0.0, str(r.blend))
		for key in ["Clp", "Cmq", "Cnr"]:
			_check("oracle region α %.0f°: %s equals the data's %.4f within 1 %%" % [deg, key, a[key]],
				absf(r[key] / a[key] - 1.0) <= 1e-2, "%.5f" % r[key])

	# Consistency across the blend: worst ratio to the oracle (α 2°) over α 0…11°.
	var worst := {}
	for key in ["Clp", "Cmq", "Cnr", "CLa"]:
		var ref: float = rows[2.0][key]
		var far := 1.0
		for deg in rows:
			var ratio: float = rows[deg][key] / ref
			if absf(ratio - 1.0) > absf(far - 1.0):
				far = ratio
		worst[key] = far
	print("worst ratio to the oracle over α 0…11°: %s" % str(worst))
	if KNOWN_DEFECT:
		for key in DEFECT:
			_check("D11b known defect still has its documented size: %s ×%.2f ± 10 %% (if fixed, set KNOWN_DEFECT = false)"
				% [key, DEFECT[key]], absf(worst[key] / DEFECT[key] - 1.0) <= 0.10, "×%.3f" % worst[key])
	else:
		for key in worst:
			_check("%s within ±%.0f %% of the oracle at every α from 0° to 11°" % [key, 100.0 * BAND], absf(worst[key] - 1.0) <= BAND,
				"×%.3f" % worst[key])

	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)


## Nondimensional Clp, Cmq, Cnr (central differences in p, q, r) and CLα (in α) at angle of attack `alpha`.
func _derivatives(model: Dictionary, alpha: float) -> Dictionary:
	var S: float = model.reference.S
	var b: float = model.reference.b
	var c: float = model.reference.c
	var qbar := 0.5 * RHO * V * V
	var h := 0.05
	var out := { blend = Aero.local_flow_weight(_state(alpha, 0, 0.0), Air.compute(_state(alpha, 0, 0.0), _zero(), RHO), _neutral(), model) }
	var specs := { Clp = [0, 3, b], Cmq = [1, 4, c], Cnr = [2, 5, b] } # rate index, moment index, length
	for key in specs:
		var spec: Array = specs[key]
		var plus := _loads(model, _state(alpha, spec[0], h))
		var minus := _loads(model, _state(alpha, spec[0], -h))
		var length: float = spec[2]
		out[key] = (plus[spec[1]] - minus[spec[1]]) / (2.0 * h) / (qbar * S * length * length / (2.0 * V))
	var da := deg_to_rad(0.25)
	out.CLa = (_lift(model, alpha + da) - _lift(model, alpha - da)) / (2.0 * da) / (qbar * S)
	return out


func _lift(model: Dictionary, alpha: float) -> float:
	var l := _loads(model, _state(alpha, 0, 0.0))
	return l[0] * sin(alpha) - l[2] * cos(alpha)


func _loads(model: Dictionary, s: PackedFloat64Array) -> PackedFloat64Array:
	return Aero.loads(s, Air.compute(s, _zero(), RHO), _neutral(), model, RHO)


## Level attitude, velocity at angle of attack `alpha`, one body rate set.
func _state(alpha: float, rate_axis: int, rate: float) -> PackedFloat64Array:
	var s := PackedFloat64Array([0, 0, -100, V * cos(alpha), 0, V * sin(alpha), 1, 0, 0, 0, 0, 0, 0])
	s[10 + rate_axis] = rate
	return s


func _zero() -> PackedFloat64Array:
	return PackedFloat64Array([0.0, 0.0, 0.0])


func _neutral() -> Dictionary:
	return { elevator = 0.0, aileron_right = 0.0, aileron_left = 0.0, rudder = 0.0 }
