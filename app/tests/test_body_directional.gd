# P51-25: the optional aero.surfaces.body_cn_beta module (fuselage yaw as a Munk-type couple ½ρ·S·b·Cnβ_B·u·v, faded
# out over the declared linear-sideslip range b1→b2). Absent or zero leaves every load byte-identical; the local couple
# is exactly the stated law; oracle and local agree at small sideslip; the couple vanishes at zero flow, broadside and
# beyond b2, and is continuous through the fade; the loader rejects invalid or inconsistent data.
extends SceneTree

const AD := preload("res://physics/aircraft_data.gd")
const Aero := preload("res://physics/aero.gd")
const Air := preload("res://physics/air_data.gd")
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")

const DATA := "res://data/aircraft/p51d_mustang_120.json"
const RHO := 1.225

var _count := 0
var _failures := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	print(("ok   " if ok else "FAIL ") + label + ("" if detail.is_empty() else "  " + detail))
	if not ok:
		_failures += 1


func _raw() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(DATA))


## The same aircraft with the body term removed (or set to `value`) and Cnb kept consistent with the fin.
func _variant(raw: Dictionary, value: Variant) -> Dictionary:
	var out: Dictionary = raw.duplicate(true)
	var body: float = float(raw.aero.surfaces.body_cn_beta.value)
	out.aero.coefficients.Cnb.value = float(raw.aero.coefficients.Cnb.value) - body + (0.0 if value == null else float(value))
	if value == null:
		out.aero.surfaces.erase("body_cn_beta")
	else:
		out.aero.surfaces.body_cn_beta.value = float(value)
	return out


func _state(u: float, v: float, w: float, p := 0.0, q := 0.0, r := 0.0) -> PackedFloat64Array:
	return RB.make_state(M.v3(0, 0, -100), M.v3(u, v, w), M.q_identity(), M.v3(p, q, r))


func _local(s: PackedFloat64Array, model: Dictionary) -> PackedFloat64Array:
	var d := {elevator = -0.02, aileron_right = 0.01, aileron_left = -0.01, rudder = 0.03}
	return Aero._local_loads(s, Air.compute(s, M.v3(0, 0, 0), RHO), d, model, RHO)


func _global(s: PackedFloat64Array, model: Dictionary) -> PackedFloat64Array:
	var d := {elevator = -0.02, aileron_right = 0.01, aileron_left = -0.01, rudder = 0.03}
	return Aero._global_loads(s, Air.compute(s, M.v3(0, 0, 0), RHO), d, model, RHO)


func _initialize() -> void:
	var raw := _raw()
	_check("the P-51 declares aero.surfaces.body_cn_beta", raw.aero.surfaces.has("body_cn_beta"))
	var with_body := AD.validate_and_derive(raw)
	var without := AD.validate_and_derive(_variant(raw, null))
	var zero := AD.validate_and_derive(_variant(raw, 0.0))
	_check("loader accepts the module, its absence and an explicit zero", with_body.ok and without.ok and zero.ok,
		str(with_body.get("errors", [])) + str(without.get("errors", [])) + str(zero.get("errors", [])))
	if not (with_body.ok and without.ok and zero.ok):
		_finish()
		return
	var mb: Dictionary = with_body.model
	var m0: Dictionary = without.model
	var mz: Dictionary = zero.model
	var cn_b: float = float(raw.aero.surfaces.body_cn_beta.value)
	var S: float = mb.reference.S
	var b: float = mb.reference.b

	# 1. Absent and explicit zero: byte-identical local loads over random states.
	var rng := RandomNumberGenerator.new()
	rng.seed = 2510
	var identical := true
	var exact := true
	var others_unchanged := true
	var worst_rel := 0.0
	for i in 400:
		var s := _state(rng.randf_range(-5.0, 40.0), rng.randf_range(-15.0, 15.0), rng.randf_range(-10.0, 12.0),
			rng.randf_range(-2, 2), rng.randf_range(-2, 2), rng.randf_range(-2, 2))
		var l0 := _local(s, m0)
		var lz := _local(s, mz)
		identical = identical and l0.to_byte_array() == lz.to_byte_array()
		# 2. With the module, only Mz changes, by exactly ½ρ·S·b·Cnβ_B·u·v·(1 − w_β).
		var lb := _local(s, mb)
		for k in 5:
			others_unchanged = others_unchanged and lb[k] == l0[k]
		var fade: float = 1.0 - Aero.sideslip_weight(float(Air.compute(s, M.v3(0, 0, 0), RHO).beta), mb.envelope)
		var expected: float = 0.5 * RHO * S * b * cn_b * s[RB.VEL] * s[RB.VEL + 1] * fade
		var got: float = lb[5] - l0[5]
		worst_rel = maxf(worst_rel, absf(got - expected) / maxf(1.0, absf(expected)))
	exact = worst_rel < 1e-12
	_check("absent and zero body term give byte-identical local loads (400 states)", identical)
	_check("the module changes only the yaw moment", others_unchanged)
	_check("local yaw couple equals ½ρ·S·b·Cnβ_B·u·v·(1 − sideslip weight)", exact, "worst %s" % String.num_scientific(worst_rel))

	# 3. Oracle and local agree on the body increment at small sideslip (attached flow, no rates). The oracle applies
	# Cnb·beta·qSb; the Munk couple is qSb·Cnb·cos(alpha)·cos(beta)·sin(beta): their exact ratio is checked, and the two
	# must agree within 1 - cos(8 deg) ≈ 1 % (+ margin) over the oracle's attached range (|alpha| <= attached_limit 8 deg).
	var worst_ratio := 0.0
	var worst_small := 0.0
	for alpha: float in [-0.14, -0.06, 0.0, 0.06, 0.12, 0.14]:
		for beta_deg: float in [-2.0, -1.0, 0.5, 1.0, 2.0]:
			var beta := deg_to_rad(beta_deg)
			var V := 25.0
			var s := _state(V * cos(beta) * cos(alpha), V * sin(beta), V * cos(beta) * sin(alpha))
			var oracle_increment: float = _global(s, mb)[5] - _global(s, m0)[5]
			var local_increment: float = _local(s, mb)[5] - _local(s, m0)[5]
			var air := Air.compute(s, M.v3(0, 0, 0), RHO)
			var analytic: float = cos(float(air.alpha)) * cos(float(air.beta)) * sin(float(air.beta)) / float(air.beta)
			worst_ratio = maxf(worst_ratio, absf(local_increment / oracle_increment - analytic))
			worst_small = maxf(worst_small, absf(oracle_increment - local_increment) / absf(local_increment))
	_check("local/oracle body increment ratio equals cos(alpha)cos(beta)sin(beta)/beta", worst_ratio < 1e-9,
		"worst %s" % String.num_scientific(worst_ratio))
	_check("oracle and local body increments agree within 1.2 % (1 - cos 8 deg) for |alpha| <= 8 deg, |beta| <= 2 deg", worst_small < 1.2e-2,
		"worst %.5f" % worst_small)

	# 4. Zero flow, broadside and continuity toward zero speed.
	var at_zero := _local(_state(0, 0, 0), mb)[5] - _local(_state(0, 0, 0), m0)[5]
	var broadside := _local(_state(0, 20, 0), mb)[5] - _local(_state(0, 20, 0), m0)[5]
	var shrinking := true
	var previous := INF
	for speed: float in [10.0, 1.0, 1e-2, 1e-4, 1e-8]:
		var s := _state(speed * cos(0.3), speed * sin(0.3), 0.0)
		var inc: float = absf(_local(s, mb)[5] - _local(s, m0)[5])
		shrinking = shrinking and inc < previous
		previous = inc
	_check("the couple is zero at zero flow and broadside", at_zero == 0.0 and broadside == 0.0, "%s %s" % [at_zero, broadside])
	_check("the couple vanishes continuously (quadratically) as the flow speed tends to zero", shrinking and previous < 1e-12,
		"last %s" % String.num_scientific(previous))

	# 5. The fade: full law up to b1, zero from b2 on, continuous in between (no step at either end).
	var b1: float = mb.envelope.b1
	var b2: float = mb.envelope.b2
	var law := func(beta: float) -> float:
		var st := _state(25.0 * cos(beta), 25.0 * sin(beta), 0.0)
		return _local(st, mb)[5] - _local(st, m0)[5]
	var munk := func(beta: float) -> float: return 0.5 * RHO * S * b * cn_b * 625.0 * cos(beta) * sin(beta)
	var at_b1: float = law.call(b1)
	var past_b2: float = law.call(b2 + 1e-9)
	var largest_step := 0.0
	var previous_inc: float = law.call(b1 - 0.01)
	for i in range(1, 2001):
		var inc: float = law.call(b1 - 0.01 + (b2 - b1 + 0.02) * i / 2000.0)
		largest_step = maxf(largest_step, absf(inc - previous_inc))
		previous_inc = inc
	_check("the fade keeps the full couple at b1 and none past b2", absf(at_b1 - munk.call(b1)) < 1e-12 * absf(munk.call(b1)) and past_b2 == 0.0,
		"%s %s" % [at_b1 - munk.call(b1), past_b2])
	_check("the faded couple is continuous through b1..b2 (largest step over 2000 samples < 0.2 % of its b1 value)",
		largest_step < 2e-3 * absf(at_b1), "%s of %s" % [String.num_scientific(largest_step), String.num_scientific(absf(at_b1))])

	# 6. The loader rejects a positive value, a wrong unit and a Cnb that omits the body term.
	var positive := _variant(raw, 0.01)
	var bad_unit := _raw()
	bad_unit.aero.surfaces.body_cn_beta.unit = "1/deg"
	var inconsistent := _raw()
	inconsistent.aero.coefficients.Cnb.value = float(inconsistent.aero.coefficients.Cnb.value) - cn_b
	_check("loader rejects a stabilizing (positive) body term", not AD.validate_and_derive(positive).ok)
	_check("loader rejects a wrong unit", not AD.validate_and_derive(bad_unit).ok)
	_check("loader rejects Cnb that is not fin + body", not AD.validate_and_derive(inconsistent).ok)
	_finish()


func _finish() -> void:
	print("P51-25 body directional: %d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)
