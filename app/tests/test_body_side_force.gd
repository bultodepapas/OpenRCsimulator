# D10-R3: the optional fuselage side force of the local aerodynamic model (aero.surfaces.body_cy_beta and
# body_crossflow_area, Allen-Perkins at the ARP). Checks the law against its formula, its symmetry and crossflow growth,
# the small-sideslip agreement with the oracle, the loader's CYb rule, and that aircraft without the fields are untouched.
# The Extra 300S declares it (EX-14d). This verifies the implementation; it does not validate the coefficients.
# D10-R3-R1 adds Extra/F4U reverse-flow domain, crossflow retention and continuity regressions.
# Run: godot --headless --path . --script res://tests/test_body_side_force.gd
extends SceneTree

const AD := preload("res://physics/aircraft_data.gd")
const Air := preload("res://physics/air_data.gd")
const Aero := preload("res://physics/aero.gd")
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")

const EXTRA := "res://data/aircraft/gp_extra_300s_60.json"
const STIK := "res://data/aircraft/jensen_ugly_stik_60.json"
const RHO := 1.225

var _failures := 0
var _count := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	print(("ok   " if ok else "FAIL ") + label + "  " + detail)
	if not ok:
		_failures += 1


func _state(speed: float, alpha_deg: float, beta_deg: float, rates := PackedFloat64Array([0.0, 0.0, 0.0])) -> PackedFloat64Array:
	var a := deg_to_rad(alpha_deg)
	var b := deg_to_rad(beta_deg)
	var v := M.v3(speed * cos(a) * cos(b), speed * sin(b), speed * sin(a) * cos(b))
	return RB.make_state(M.v3(0.0, 0.0, -300.0), v, M.q_from_euler(0.0, 0.0, 0.0), rates)


func _local(model: Dictionary, s: PackedFloat64Array, d: Dictionary) -> PackedFloat64Array:
	return Aero._local_loads(s, Air.compute(s, M.v3(0.0, 0.0, 0.0), RHO), d, model, RHO)


func _initialize() -> void:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(EXTRA))
	var loaded: Dictionary = AD.validate_and_derive(raw.duplicate(true))
	_check("Extra loads with its D10-R3 fuselage side force", loaded.get("ok", false), str(loaded.get("errors", [])))
	if not loaded.get("ok", false):
		_finish()
		return
	var model: Dictionary = loaded.model
	var surfaces: Dictionary = model.surfaces
	var body_cy: float = surfaces.get("body_cy_beta", 0.0)
	var body_cda: float = surfaces.get("body_crossflow_area", 0.0)
	_check("Extra declares an attached slope and a crossflow area", body_cy < 0.0 and body_cda > 0.0, "CYb_B %.4f/rad, eta cd S_side %.4f m2" % [body_cy, body_cda])
	var bare: Dictionary = model.duplicate(true)
	bare.surfaces.erase("body_cy_beta")
	bare.surfaces.erase("body_crossflow_area")
	var neutral := { elevator = 0.0, aileron_right = 0.0, aileron_left = 0.0, rudder = 0.0 }
	var cg: PackedFloat64Array = model.cg_le
	var arp: PackedFloat64Array = model.reference.arp_le
	var arm := M.v3(-(arp[0] - cg[0]), arp[1] - cg[1], -(arp[2] - cg[2]))
	var S: float = model.reference.S

	# The increment over the same model without the fields is exactly the Allen-Perkins force at the ARP.
	var worst := 0.0
	var cases := 0
	for speed in [8.0, 22.0, 40.0]:
		for alpha in [-12.0, 0.0, 6.0, 25.0]:
			for beta in [-60.0, -25.0, -5.0, 0.0, 3.0, 20.0, 45.0]:
				var s := _state(speed, alpha, beta, PackedFloat64Array([0.4, -0.2, 0.3]))
				var with_force := _local(model, s, neutral)
				var without := _local(bare, s, neutral)
				var v: PackedFloat64Array = Air.compute(s, M.v3(0.0, 0.0, 0.0), RHO).v_air
				var fy: float = 0.5 * RHO * (S * body_cy * v[0] * v[1] - body_cda * sqrt(v[1] * v[1] + v[2] * v[2]) * v[1])
				var moment := M.cross(arm, M.v3(0.0, fy, 0.0))
				var expected := [0.0, fy, 0.0, moment[0], moment[1], moment[2]]
				var scale: float = 0.5 * RHO * speed * speed * S
				for i in 6:
					worst = maxf(worst, absf((with_force[i] - without[i]) - expected[i]) / scale)
				cases += 1
	_check("increment equals the formula at the ARP over %d states (incl. rates, reverse sideslip)" % cases, worst < 1e-12, "max error %s q S" % String.num_scientific(worst))

	# Odd in sideslip: the fuselage pushes away from the wind on either side.
	var right := _local(model, _state(30.0, 3.0, 22.0), neutral)
	var left := _local(model, _state(30.0, 3.0, -22.0), neutral)
	var right_bare := _local(bare, _state(30.0, 3.0, 22.0), neutral)
	var left_bare := _local(bare, _state(30.0, 3.0, -22.0), neutral)
	var dy_right := right[1] - right_bare[1]
	var dy_left := left[1] - left_bare[1]
	_check("side force opposes sideslip and is odd in beta", dy_right < 0.0 and absf(dy_right + dy_left) < 1e-9 * absf(dy_right),
		"%.4f N / %.4f N at +/-22 deg" % [dy_right, dy_left])

	# Crossflow grows with the body's crossflow speed: at 20 deg alpha the same 10 deg sideslip gives more side force.
	var q_ := 0.5 * RHO * 900.0 * S
	var cross_level := (_local(model, _state(30.0, 0.0, 10.0), neutral)[1] - _local(bare, _state(30.0, 0.0, 10.0), neutral)[1]) / q_
	var cross_alpha := (_local(model, _state(30.0, 20.0, 10.0), neutral)[1] - _local(bare, _state(30.0, 20.0, 10.0), neutral)[1]) / q_
	_check("crossflow side force grows with alpha (Letko & Williams' deep-body trend)", cross_alpha < cross_level and cross_level < 0.0,
		"CY body %.4f at alpha 0, %.4f at alpha 20" % [cross_level, cross_alpha])

	# Small sideslip: local and oracle side-force slopes now agree (the fin alone fell 26 % short).
	var s2 := _state(22.0, 3.4, 2.0)
	var air2 := Air.compute(s2, M.v3(0.0, 0.0, 0.0), RHO)
	var oracle := Aero._global_loads(s2, air2, neutral, model, RHO)
	var local := _local(model, s2, neutral)
	var fin_only := _local(bare, s2, neutral)
	var oracle_y := oracle[1]
	_check("local side force at beta 2 deg within 3 % of the oracle", absf(local[1] - oracle_y) <= 0.03 * absf(oracle_y),
		"local %.4f N, oracle %.4f N, fin only %.4f N" % [local[1], oracle_y, fin_only[1]])

	# Knife-edge capability with controls neutral: at 0.8 of the 41 m/s level Vmax, beta 25 deg gives |CY| > W/(qS).
	var v_ke := 0.8 * 41.0
	var ke := _local(model, _state(v_ke, 0.0, 25.0), neutral)
	var need: float = float(model.mass_kg) * 9.80665 / (0.5 * RHO * v_ke * v_ke * S)
	_check("fuselage + fin side force exceeds the knife-edge need at beta 25 deg, 0.8 Vmax", absf(ke[1]) / (0.5 * RHO * v_ke * v_ke * S) > need,
		"|CY| %.4f against W/qS %.4f" % [absf(ke[1]) / (0.5 * RHO * v_ke * v_ke * S), need])

	# Loader rule: with body_cy_beta declared the oracle's CYb must equal fin + body.
	var broken: Dictionary = raw.duplicate(true)
	broken.aero.coefficients.CYb.value = float(broken.aero.coefficients.CYb.value) - 1e-6
	var refused: Dictionary = AD.validate_and_derive(broken)
	_check("loader refuses a CYb that is not fin + body_cy_beta", not refused.get("ok", false)
		and str(refused.get("errors", [])).contains("CYb"), str(refused.get("errors", [])).left(160))
	var negative: Dictionary = raw.duplicate(true)
	negative.aero.surfaces.body_crossflow_area.value = -0.01
	_check("loader refuses a negative crossflow area", not AD.validate_and_derive(negative).get("ok", false))
	var undeclared: Dictionary = raw.duplicate(true)
	undeclared.aero.surfaces.erase("body_cy_beta")
	undeclared.aero.surfaces.erase("body_crossflow_area")
	_check("without the fields the old data form (CYb free) still loads", AD.validate_and_derive(undeclared).get("ok", false))

	# Aircraft without the fields: no D10-R3 keys reach the model.
	var stik: Dictionary = AD.load_file(STIK)
	_check("Stik model carries no fuselage side force (opt-in)", stik.get("ok", false)
		and not stik.model.surfaces.has("body_cy_beta") and not stik.model.surfaces.has("body_crossflow_area"))
	_reverse_flow_checks()
	_finish()


## D10-R3-R1: the forward-flight derivative must not turn into a side-force source
## in tail-first translation. This is a model-domain check, not aircraft validation.
func _reverse_flow_checks() -> void:
	var neutral := {elevator = 0.0, aileron_right = 0.0, aileron_left = 0.0, rudder = 0.0}
	for path in [EXTRA, "res://data/aircraft/f4u_corsair_250.json"]:
		var loaded := AD.load_file(path)
		_check("reverse-flow fixture loads: " + path, loaded.get("ok", false))
		if not loaded.get("ok", false):
			continue
		var model: Dictionary = loaded.model
		_check("reverse fixture declares both nonzero body terms: " + path,
			float(model.surfaces.get("body_cy_beta", 0.0)) < 0.0 and float(model.surfaces.get("body_crossflow_area", 0.0)) > 0.0)
		var bare: Dictionary = model.duplicate(true)
		bare.surfaces.erase("body_cy_beta")
		bare.surfaces.erase("body_crossflow_area")
		var crossflow: Dictionary = model.duplicate(true)
		crossflow.surfaces.erase("body_cy_beta")
		var worst_power := 0.0
		var worst_attached := 0.0
		var worst_crossflow := 0.0
		var negative_power_seen := false
		var arm := M.v3(-(model.reference.arp_le[0] - model.cg_le[0]), model.reference.arp_le[1] - model.cg_le[1],
			-(model.reference.arp_le[2] - model.cg_le[2]))
		var cases := 0
		for speed in [0.0, 2.0, 20.0, 40.0]:
			for alpha in [-180.0, -179.0, -120.0, -91.0, 91.0, 120.0, 179.0, 180.0]:
				for beta in [-60.0, -5.0, 0.0, 5.0, 60.0]:
					var s := _state(speed, alpha, beta)
					var air := Air.compute(s, M.v3(0.0, 0.0, 0.0), RHO)
					var with_body := Aero.loads(s, air, neutral, model, RHO)
					var without := Aero.loads(s, air, neutral, bare, RHO)
					var cross_only := Aero.loads(s, air, neutral, crossflow, RHO)
					var power: float = (with_body[1] - without[1]) * s[RB.VEL + 1]
					worst_power = maxf(worst_power, power)
					negative_power_seen = negative_power_seen or power < -1e-6
					var v: PackedFloat64Array = air.v_air
					var expected_fy: float = -0.5 * RHO * float(model.surfaces.body_crossflow_area) * sqrt(v[1]*v[1] + v[2]*v[2]) * v[1]
					var expected := [0.0, expected_fy, 0.0, -arm[2]*expected_fy, 0.0, arm[0]*expected_fy]
					for i in 6:
						worst_attached = maxf(worst_attached, absf(with_body[i] - cross_only[i]))
						worst_crossflow = maxf(worst_crossflow, absf((with_body[i] - without[i]) - expected[i]))
					cases += 1
		_check("tail-first body force resists lateral translation: " + path, worst_power <= 1e-10,
			"%d zero-rate states; max positive body work %.9f W" % [cases, worst_power])
		_check("reverse flow retains crossflow without extrapolated attached loads: " + path, worst_attached <= 1e-10,
			"max six-load difference %.9f" % worst_attached)
		_check("reverse crossflow remains nonzero with its ARP moments: " + path, worst_crossflow <= 1e-10 and negative_power_seen,
			"max six-load error %.9f" % worst_crossflow)

		# With fixed crossflow, approaching u=0 from either side must not jump.
		var jumps: Array[float] = []
		for epsilon in [1e-3, 1e-6, 1e-9]:
			var ends: Array[float] = []
			for u in [-epsilon, 0.0, epsilon]:
				var s := RB.make_state(M.v3(0.0, 0.0, -300.0), M.v3(u, 1.0, 0.3), M.q_identity(), M.v3(0.0, 0.0, 0.0))
				ends.append(_local(model, s, neutral)[1] - _local(bare, s, neutral)[1])
			jumps.append(maxf(absf(ends[0] - ends[1]), absf(ends[2] - ends[1])))
		_check("body-force jump tends to zero at axial-flow reversal: " + path,
			jumps[1] < jumps[0] * 0.002 and jumps[2] < jumps[1] * 0.002,
			"one-sided differences %s N" % str(jumps))

		# Preserve the historical forward-flight map, including its existing rate convention.
		var max_forward_error := 0.0
		for alpha in [-25.0, 0.0, 30.0, 80.0]:
			for beta in [-25.0, -5.0, 5.0, 25.0]:
				var s := _state(22.0, alpha, beta, M.v3(0.4, -0.2, 0.3))
				var v := s.slice(RB.VEL, RB.VEL + 3)
				var expected: float = 0.5 * RHO * (float(model.reference.S) * float(model.surfaces.body_cy_beta) * v[0] * v[1]
					- float(model.surfaces.body_crossflow_area) * sqrt(v[1]*v[1] + v[2]*v[2]) * v[1])
				max_forward_error = maxf(max_forward_error, absf((_local(model, s, neutral)[1] - _local(bare, s, neutral)[1]) - expected))
		_check("forward body-side law preserved: " + path, max_forward_error < 1e-10, str(max_forward_error))


func _finish() -> void:
	print("D10-R3 body side force: %d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)
