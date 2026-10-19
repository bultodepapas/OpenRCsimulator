# D10-R5: the optional aero.surfaces.wing_body_cl_beta module (the wing-body dihedral effect the flat strips lack, a
# rolling couple ½ρ·S·b·Clβ_WB·u·v faded out over the declared linear-sideslip range b1→b2). Absent or zero leaves every
# load byte-identical; the local couple is exactly the stated law; oracle and local agree on it at small sideslip, so
# the production roll due to sideslip no longer collapses to the fin term where the local law takes over; the couple
# vanishes at zero flow, broadside and beyond b2, and is continuous through the fade; the loader rejects invalid or
# inconsistent data.
extends SceneTree

const AD := preload("res://physics/aircraft_data.gd")
const Aero := preload("res://physics/aero.gd")
const Air := preload("res://physics/air_data.gd")
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")

const DATA := "res://data/aircraft/jensen_ugly_stik_60.json"
const RHO := 1.225
const ZERO := {elevator = 0.0, aileron_right = 0.0, aileron_left = 0.0, rudder = 0.0}

var _count := 0
var _failures := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	print(("ok   " if ok else "FAIL ") + label + ("" if detail.is_empty() else "  " + detail))
	if not ok:
		_failures += 1


func _raw() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(DATA))


## The same aircraft with the wing-body term removed (Clb kept, no rule applies) or set to `value` (Clb kept consistent).
func _variant(raw: Dictionary, value: Variant) -> Dictionary:
	var out: Dictionary = raw.duplicate(true)
	if value == null:
		out.aero.surfaces.erase("wing_body_cl_beta")
	else:
		var declared: float = float(raw.aero.surfaces.wing_body_cl_beta.value)
		out.aero.coefficients.Clb.value = float(raw.aero.coefficients.Clb.value) - declared + float(value)
		out.aero.surfaces.wing_body_cl_beta.value = float(value)
	return out


func _state(u: float, v: float, w: float, p := 0.0, q := 0.0, r := 0.0) -> PackedFloat64Array:
	return RB.make_state(M.v3(0, 0, -100), M.v3(u, v, w), M.q_identity(), M.v3(p, q, r))


func _local(s: PackedFloat64Array, model: Dictionary, d := {elevator = -0.02, aileron_right = 0.01, aileron_left = -0.01, rudder = 0.03}) -> PackedFloat64Array:
	return Aero._local_loads(s, Air.compute(s, M.v3(0, 0, 0), RHO), d, model, RHO)


func _global(s: PackedFloat64Array, model: Dictionary, d := {elevator = -0.02, aileron_right = 0.01, aileron_left = -0.01, rudder = 0.03}) -> PackedFloat64Array:
	return Aero._global_loads(s, Air.compute(s, M.v3(0, 0, 0), RHO), d, model, RHO)


## Static body-axis Clβ about the CG (per rad) at angle of attack `alpha`, β = ±1°, 25 m/s, controls neutral.
func _clb(model: Dictionary, alpha: float, local: bool) -> float:
	var db := deg_to_rad(1.0)
	var V := 25.0
	var plus := _state(V * cos(alpha) * cos(db), V * sin(db), V * sin(alpha) * cos(db))
	var minus := _state(V * cos(alpha) * cos(db), -V * sin(db), V * sin(alpha) * cos(db))
	var mx_plus: float = (_local(plus, model, ZERO) if local else _global(plus, model, ZERO))[3]
	var mx_minus: float = (_local(minus, model, ZERO) if local else _global(minus, model, ZERO))[3]
	return (mx_plus - mx_minus) / (2.0 * db * 0.5 * RHO * V * V * float(model.reference.S) * float(model.reference.b))


func _initialize() -> void:
	var raw := _raw()
	_check("the Stik declares aero.surfaces.wing_body_cl_beta", raw.aero.surfaces.has("wing_body_cl_beta"))
	var with_term := AD.validate_and_derive(raw)
	var without := AD.validate_and_derive(_variant(raw, null))
	var zero := AD.validate_and_derive(_variant(raw, 0.0))
	_check("loader accepts the module, its absence and an explicit zero", with_term.ok and without.ok and zero.ok,
		str(with_term.get("errors", [])) + str(without.get("errors", [])) + str(zero.get("errors", [])))
	if not (with_term.ok and without.ok and zero.ok):
		_finish()
		return
	var mw: Dictionary = with_term.model
	var m0: Dictionary = without.model
	var mz: Dictionary = zero.model
	var cl_wb: float = float(raw.aero.surfaces.wing_body_cl_beta.value)
	var S: float = mw.reference.S
	var b: float = mw.reference.b

	# 1. Absent and explicit zero: byte-identical local loads over random states.
	var rng := RandomNumberGenerator.new()
	rng.seed = 1005
	var identical := true
	var others_unchanged := true
	var worst_rel := 0.0
	for i in 400:
		var s := _state(rng.randf_range(-5.0, 40.0), rng.randf_range(-15.0, 15.0), rng.randf_range(-10.0, 12.0),
			rng.randf_range(-2, 2), rng.randf_range(-2, 2), rng.randf_range(-2, 2))
		var l0 := _local(s, m0)
		var lz := _local(s, mz)
		identical = identical and l0.to_byte_array() == lz.to_byte_array()
		# 2. With the module, only Mx changes, by exactly ½ρ·S·b·Clβ_WB·u·v·(1 − w_β).
		var lw := _local(s, mw)
		for k in 6:
			if k != 3:
				others_unchanged = others_unchanged and lw[k] == l0[k]
		var fade: float = 1.0 - Aero.sideslip_weight(float(Air.compute(s, M.v3(0, 0, 0), RHO).beta), mw.envelope)
		var expected: float = 0.5 * RHO * S * b * cl_wb * s[RB.VEL] * s[RB.VEL + 1] * fade
		worst_rel = maxf(worst_rel, absf(lw[3] - l0[3] - expected) / maxf(1.0, absf(expected)))
	_check("absent and zero wing-body term give byte-identical local loads (400 states)", identical)
	_check("the module changes only the rolling moment", others_unchanged)
	_check("local roll couple equals ½ρ·S·b·Clβ_WB·u·v·(1 − sideslip weight)", worst_rel < 1e-12,
		"worst %s" % String.num_scientific(worst_rel))

	# 3. Oracle and local agree on the wing-body increment at small sideslip (attached flow, no rates): the oracle adds
	# Clβ_WB·β·qSb, the couple qSb·Clβ_WB·cos α·cos β·sin β, within 1 − cos 8° over |α| ≤ attached_limit.
	var worst_ratio := 0.0
	var worst_small := 0.0
	for alpha: float in [-0.14, -0.06, 0.0, 0.06, 0.12, 0.14]:
		for beta_deg: float in [-2.0, -1.0, 0.5, 1.0, 2.0]:
			var beta := deg_to_rad(beta_deg)
			var V := 25.0
			var s := _state(V * cos(beta) * cos(alpha), V * sin(beta), V * cos(beta) * sin(alpha))
			var oracle_increment: float = _global(s, mw)[3] - _global(s, mz)[3]
			var local_increment: float = _local(s, mw)[3] - _local(s, mz)[3]
			var air := Air.compute(s, M.v3(0, 0, 0), RHO)
			var analytic: float = cos(float(air.alpha)) * cos(float(air.beta)) * sin(float(air.beta)) / float(air.beta)
			worst_ratio = maxf(worst_ratio, absf(local_increment / oracle_increment - analytic))
			worst_small = maxf(worst_small, absf(oracle_increment - local_increment) / absf(local_increment))
	_check("local/oracle wing-body increment ratio equals cos(alpha)cos(beta)sin(beta)/beta", worst_ratio < 1e-9,
		"worst %s" % String.num_scientific(worst_ratio))
	_check("oracle and local wing-body increments agree within 1.2 % for |alpha| <= 8 deg, |beta| <= 2 deg", worst_small < 1.2e-2,
		"worst %.5f" % worst_small)

	# 4. The purpose: where the local law takes over, the Stik's static Clβ about the CG keeps the oracle's magnitude
	# within the fuselage side-force transfer the local law does not have (D10-R3), instead of collapsing to the fin.
	var worst_without := 0.0
	var worst_with := INF
	for alpha_deg: float in [0.0, 4.0, 8.0]:
		var oracle := _clb(mw, deg_to_rad(alpha_deg), false)
		worst_without = maxf(worst_without, _clb(m0, deg_to_rad(alpha_deg), true) / oracle)
		worst_with = minf(worst_with, _clb(mw, deg_to_rad(alpha_deg), true) / oracle)
	_check("without the module the local Clβ is under 20 % of the oracle's (fin only)", worst_without < 0.2, "%.3f" % worst_without)
	_check("with the module the local Clβ keeps over 80 % of the oracle's at α 0–8°", worst_with > 0.8, "%.3f" % worst_with)

	# 5. Zero flow, broadside and continuity toward zero speed.
	var at_zero := _local(_state(0, 0, 0), mw)[3] - _local(_state(0, 0, 0), m0)[3]
	var broadside := _local(_state(0, 20, 0), mw)[3] - _local(_state(0, 20, 0), m0)[3]
	var shrinking := true
	var previous := INF
	for speed: float in [10.0, 1.0, 1e-2, 1e-4, 1e-8]:
		var s := _state(speed * cos(0.3), speed * sin(0.3), 0.0)
		var inc: float = absf(_local(s, mw)[3] - _local(s, m0)[3])
		shrinking = shrinking and inc < previous
		previous = inc
	_check("the couple is zero at zero flow and broadside", at_zero == 0.0 and broadside == 0.0, "%s %s" % [at_zero, broadside])
	_check("the couple vanishes continuously (quadratically) as the flow speed tends to zero", shrinking and previous < 1e-12,
		"last %s" % String.num_scientific(previous))

	# 6. The fade: full law up to b1, zero from b2 on, continuous in between.
	var b1: float = mw.envelope.b1
	var b2: float = mw.envelope.b2
	var law := func(beta: float) -> float:
		var st := _state(25.0 * cos(beta), 25.0 * sin(beta), 0.0)
		return _local(st, mw)[3] - _local(st, m0)[3]
	var full := func(beta: float) -> float: return 0.5 * RHO * S * b * cl_wb * 625.0 * cos(beta) * sin(beta)
	var at_b1: float = law.call(b1)
	var past_b2: float = law.call(b2 + 1e-9)
	var largest_step := 0.0
	var previous_inc: float = law.call(b1 - 0.01)
	for i in range(1, 2001):
		var inc: float = law.call(b1 - 0.01 + (b2 - b1 + 0.02) * i / 2000.0)
		largest_step = maxf(largest_step, absf(inc - previous_inc))
		previous_inc = inc
	_check("the fade keeps the full couple at b1 and none past b2", absf(at_b1 - full.call(b1)) < 1e-12 * absf(full.call(b1)) and past_b2 == 0.0,
		"%s %s" % [at_b1 - full.call(b1), past_b2])
	_check("the faded couple is continuous through b1..b2 (largest step over 2000 samples < 0.2 % of its b1 value)",
		largest_step < 2e-3 * absf(at_b1), "%s of %s" % [String.num_scientific(largest_step), String.num_scientific(absf(at_b1))])

	# 7. The loader rejects an out-of-range value, a wrong unit and a Clb that is not fin + wing-body.
	var too_large := _variant(raw, -0.4)
	var bad_unit := _raw()
	bad_unit.aero.surfaces.wing_body_cl_beta.unit = "1/deg"
	var inconsistent := _raw()
	inconsistent.aero.coefficients.Clb.value = float(inconsistent.aero.coefficients.Clb.value) - 0.01
	_check("loader rejects a value outside -0.3..0.1", not AD.validate_and_derive(too_large).ok)
	_check("loader rejects a wrong unit", not AD.validate_and_derive(bad_unit).ok)
	_check("loader rejects Clb that is not fin + wing-body", not AD.validate_and_derive(inconsistent).ok)
	_finish()


func _finish() -> void:
	print("D10-R5 wing-body roll: %d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)
