# D11b: the aerodynamic damping and lift slope must not change with the model's regime. Loads blend from the linear
# oracle (attached flow) to the local wing and tail elements between α ≈ 6° and 10°, which is where an approach at
# 1.3 V_s flies. Found by plan review #4 (docs/research/roadmap-investigations/02-aerodynamics-rc-scale.md) and
# re-measured by its lead: the local elements roll-damp 1.7× harder and pitch-damp 3× softer than the oracle.
# Derivatives are central differences of Aero.loads at 15 m/s, controls neutral, nondimensionalised like the data.
# KNOWN_DEFECTS pins each remaining defect at its documented size, so the suite stays green while it exists and fails
# on any change: worse, or fixed. Whoever fixes one removes it from KNOWN_DEFECTS, which turns the same measurement into
# the acceptance test (within ±15 % of the oracle at every α). D11d (2026-10-07, wing induced-flow map) fixed Clp
# (×1.73 → ×1.12) and CLα (×1.34 → ×0.98). E0a2a (tail downwash split) raised Cmq from ×0.28 to ×0.64: the remaining
# gap is the oracle's lumped downwash lag (Cmα̇ ≈ −3.4, E0a2b through H8) and its borrowed 25e geometry. D11f found the
# local Cnr consistent with the Stik's own fin and wing (test_yaw_damping.gd); its gap to the oracle is the borrowed 25e Cnr.
# D11g (oracle data decision, DECISIONS.md 2026-10-07) replaced the borrowed Cmq, CLq and Cnr with the Stik's own, derived
# from the local model at the 15 m/s trim (research/aero/d11g/derive_rate_derivatives.gd), and gave the oracle the same
# downwash lag: both pins closed. The data must keep matching the local model there (checked below).
# Run: godot --headless --path . --script res://tests/test_damping_regimes.gd
extends SceneTree

const AD := preload("res://physics/aircraft_data.gd")
const Air := preload("res://physics/air_data.gd")
const Aero := preload("res://physics/aero.gd")
const Scenarios := preload("res://sim/scenarios.gd")
const Trim := preload("res://physics/trim.gd")

## Remaining documented gaps to the oracle: worst ratio (α 2°) over α 0…11°; checked within ±10 %. None since D11g
## (were Cmq ×0.64 and Cnr ×0.72 against the borrowed 25e values).
const KNOWN_DEFECTS := {}
## D11g: the data's rate derivatives equal the local model's at the 15 m/s level trim within this fraction.
const DERIVED_TOL := 0.005
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
	for key in worst:
		if KNOWN_DEFECTS.has(key):
			_check("D11b known defect still has its documented size: %s ×%.2f ± 10 %% (if fixed, remove it from KNOWN_DEFECTS)"
				% [key, KNOWN_DEFECTS[key]], absf(worst[key] / KNOWN_DEFECTS[key] - 1.0) <= 0.10, "×%.3f" % worst[key])
		else:
			_check("%s within ±%.0f %% of the oracle at every α from 0° to 11°" % [key, 100.0 * BAND], absf(worst[key] - 1.0) <= BAND,
				"×%.3f" % worst[key])

	# D11g derivation: the data's Cmq, CLq and Cnr are the local model's at the 15 m/s level trim (rerun the generator
	# when the geometry, tail or wing data change).
	var trim := Trim.solve("level", V, model, 9.80665, model.controls.throw_rad)
	var at_trim := _derivatives(model, trim.alpha, true)
	for key in ["Cmq", "CLq", "Cnr"]:
		_check("D11g: data %s %.4f = the local model's %.4f at the 15 m/s trim (α %.2f°) within %.1f %%"
			% [key, a[key], at_trim[key], rad_to_deg(trim.alpha), 100.0 * DERIVED_TOL],
			absf(at_trim[key] / a[key] - 1.0) <= DERIVED_TOL)

	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)


## Nondimensional Clp, Cmq, Cnr (central differences in p, q, r), CLq and CLα (in α) at angle of attack `alpha`, of
## Aero.loads or (local) of the local strip model alone.
func _derivatives(model: Dictionary, alpha: float, local := false) -> Dictionary:
	var S: float = model.reference.S
	var b: float = model.reference.b
	var c: float = model.reference.c
	var qbar := 0.5 * RHO * V * V
	var h := 0.05
	var out := { blend = Aero.local_flow_weight(_state(alpha, 0, 0.0), Air.compute(_state(alpha, 0, 0.0), _zero(), RHO), _neutral(), model) }
	var specs := { Clp = [0, 3, b], Cmq = [1, 4, c], Cnr = [2, 5, b] } # rate index, moment index, length
	for key in specs:
		var spec: Array = specs[key]
		var plus := _loads(model, _state(alpha, spec[0], h), local)
		var minus := _loads(model, _state(alpha, spec[0], -h), local)
		var length: float = spec[2]
		out[key] = (plus[spec[1]] - minus[spec[1]]) / (2.0 * h) / (qbar * S * length * length / (2.0 * V))
		if key == "Cmq":
			out.CLq = (_lift_of(plus, alpha) - _lift_of(minus, alpha)) / (2.0 * h) / (qbar * S * c / (2.0 * V))
	var da := deg_to_rad(0.25)
	out.CLa = (_lift(model, alpha + da, local) - _lift(model, alpha - da, local)) / (2.0 * da) / (qbar * S)
	return out


func _lift(model: Dictionary, alpha: float, local := false) -> float:
	return _lift_of(_loads(model, _state(alpha, 0, 0.0), local), alpha)


func _lift_of(l: PackedFloat64Array, alpha: float) -> float:
	return l[0] * sin(alpha) - l[2] * cos(alpha)


func _loads(model: Dictionary, s: PackedFloat64Array, local := false) -> PackedFloat64Array:
	var air := Air.compute(s, _zero(), RHO)
	return Aero._local_loads(s, air, _neutral(), model, RHO) if local else Aero.loads(s, air, _neutral(), model, RHO)


## Level attitude, velocity at angle of attack `alpha`, one body rate set.
func _state(alpha: float, rate_axis: int, rate: float) -> PackedFloat64Array:
	var s := PackedFloat64Array([0, 0, -100, V * cos(alpha), 0, V * sin(alpha), 1, 0, 0, 0, 0, 0, 0])
	s[10 + rate_axis] = rate
	return s


func _zero() -> PackedFloat64Array:
	return PackedFloat64Array([0.0, 0.0, 0.0])


func _neutral() -> Dictionary:
	return { elevator = 0.0, aileron_right = 0.0, aileron_left = 0.0, rudder = 0.0 }
