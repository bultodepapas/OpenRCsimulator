## Reuse the installed P-51 + synthetic compliant geometry fixture; run only
## this adapter's checks, not the parent suite's _initialize().
extends "res://tests/test_aircraft_ground_stage.gd"
const Traction := preload("res://physics/aircraft_ground_traction.gd")
const Impulse := preload("res://physics/aircraft_ground_impulse.gd")
var pairs: Array
var traction: Dictionary


func _initialize() -> void:
	_fixture()
	pairs = [_material("dry_pavement", 0.7, 0.5, 0.02), _material("test_grass", 0.45, 0.35, 0.1)]
	traction = Traction.prepare(prepared, model, pairs)
	check("installed wheel and explicit material pairs prepare", traction.ok, str(traction))
	if failed:
		quit(1)
		return
	_assembly()
	_moving_frame()
	_brakes()
	_reject_rows()
	print("Aircraft ground traction: %d checks, %d failed" % [checks, failed])
	quit(1 if failed else 0)


func _material(id: String, longitudinal: float, lateral: float, rolling: float) -> Dictionary:
	return {format = Traction.MATERIAL_FORMAT, law = Traction.MATERIAL_LAW, material_id = id,
		longitudinal_friction = _q(longitudinal, "1"), lateral_friction = _q(lateral, "1"), rolling_resistance = _q(rolling, "1")}


func _frame(down := -0.19, vx := 3.0, rims := PackedFloat64Array([0.0, 0.0, 0.0])) -> Dictionary:
	var body := RB.make_state(M.v3(0.0, 0.0, down), M.v3(vx, 0.2, 0.0), M.q_from_euler(0.0, 0.0, 0.0), M.v3(0.0, 0.0, 0.0))
	var result := Stage.evaluate(prepared, body, rims, 1400.0, motion, provider, 0.0, live, 0.0,
		PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0]), M.v3(0.0, 0.0, 0.0), 0.0)
	check("physical normal stage fixture evaluates", result.ok, str(result))
	return {body = body, result = result}


func _slips(rows: Dictionary, frame: Dictionary) -> PackedFloat64Array:
	var z := M.add(frame.body.slice(RB.VEL, RB.VEL + 3), M.cross(frame.body.slice(RB.RATE), live.cg_body_m))
	z.append_array(frame.result.rotor.stage.velocity)
	var slips := PackedFloat64Array()
	for row in rows.bias.size():
		var value: float = rows.bias[row]
		for coordinate in z.size(): value += rows.jacobian[row * z.size() + coordinate] * z[coordinate]
		slips.append(value)
	return slips


func _apply_rows(rows: Dictionary, frame: Dictionary, h := 0.01) -> Dictionary:
	var limits: PackedFloat64Array = rows.limit_rates.duplicate()
	for index in limits.size(): limits[index] *= h
	var body: PackedFloat64Array = frame.body
	return Impulse.apply(frame.result.rotor.stage, live.mass_kg,
		M.add(body.slice(RB.VEL, RB.VEL + 3), M.cross(body.slice(RB.RATE), live.cg_body_m)), rows.jacobian, rows.bias, limits, rows.groups)


func _assembly() -> void:
	var frame := _frame()
	var before := var_to_bytes([traction, frame, live])
	var rows := Traction.evaluate(traction, frame.body, live.cg_body_m, frame.result.ground, PackedFloat64Array([1.0, 0.4, 1.0]))
	check("three contacts assemble two ellipses plus independent torque rows", rows.ok and rows.bias.size() == 11 and rows.groups.size() == 8, str(rows))
	if not rows.ok: return
	check("assembly is detached and does not integrate or mutate caller state", before == var_to_bytes([traction, frame, live]))
	check("all tire row pairs remain a single combined traction group", rows.groups[0] == PackedInt32Array([0, 1])
		and rows.groups[3] == PackedInt32Array([4, 5]) and rows.groups[6] == PackedInt32Array([8, 9]))
	var slips := _slips(rows, frame)
	for index in rows.labels.size():
		var label: Dictionary = rows.labels[index]
		var wheel: int = prepared.rotor_order.find(label.contact_id) - 1
		var load_n: float = frame.result.ground.contacts[wheel].normal_load_n
		match label.kind:
			"longitudinal":
				check("longitudinal capacity is mu*N", absf(rows.limit_rates[index] - 0.7 * load_n) < 1e-12)
				check("full CM row reproduces wheel material longitudinal slip", absf(slips[index] - 3.0) < 1e-12)
			"lateral":
				check("lateral capacity remains distinct from rolling drag", absf(rows.limit_rates[index] - 0.5 * load_n) < 1e-12)
				check("lateral basis is right handed with actual normal", absf(slips[index] + 0.2) < 1e-12)
			"rolling_moment":
				check("rolling moment has correct load/radius units", absf(rows.limit_rates[index] - 0.02 * load_n * prepared.radii_m[wheel]) < 1e-12)
			"internal_brake":
				check("proportional brakes use hardware torque without normal-load scaling", absf(rows.limit_rates[index] - (2.0 if wheel == 0 else 0.8)) < 1e-12)
	var result := _apply_rows(rows, frame)
	check("actual common QP accepts assembled touchdown rows", result.ok, str(result))
	if result.ok:
		check("strong brake holds one wheel while other wheels spin up", absf(result.spin[1]) < 1e-12 and result.spin[2] > 0.0 and result.spin[3] > 0.0)
		check("combined static-ground traction is passive", result.kinetic_energy_change <= 0.0 and result.dissipated_energy >= 0.0 and absf(result.energy_balance_residual) < 1e-10)
		for group: PackedInt32Array in rows.groups:
			var utilized := 0.0
			for row in group:
				var capacity: float = 0.01 * rows.limit_rates[row]
				if capacity > 0.0: utilized += pow(result.impulse[row] / capacity, 2)
			check("simultaneous braking/cornering respects each combined capacity", utilized <= 1.0 + 1e-9)
	var no_brake := Traction.evaluate(traction, frame.body, live.cg_body_m, frame.result.ground, PackedFloat64Array([0.0, 0.0, 0.0]))
	var free_spin := _apply_rows(no_brake, frame)
	check("unbraked touchdown naturally spins all wheels forward", free_spin.ok and free_spin.spin[1] > 0.0 and free_spin.spin[2] > 0.0 and free_spin.spin[3] > 0.0)
	var lighter: Dictionary = frame.result.ground.duplicate(true)
	for record: Dictionary in lighter.contacts: record.normal_load_n *= 0.25
	var unloaded := Traction.evaluate(traction, frame.body, live.cg_body_m, lighter, PackedFloat64Array([1.0, 0.4, 1.0]))
	check("aerodynamic unloading continuously reduces tire/rolling limits", unloaded.ok and unloaded.limit_rates[0] == rows.limit_rates[0] * 0.25
		and unloaded.limit_rates[2] == rows.limit_rates[2] * 0.25 and unloaded.limit_rates[3] == rows.limit_rates[3])
	var grass: Dictionary = frame.result.ground.duplicate(true)
	grass.contacts[0].material_id = "test_grass"
	var mixed := Traction.evaluate(traction, frame.body, live.cg_body_m, grass, PackedFloat64Array([1.0, 0.4, 1.0]))
	check("per-wheel footpoint material independently changes resistance and traction", mixed.ok
		and mixed.limit_rates[0] < rows.limit_rates[0] and mixed.limit_rates[2] > rows.limit_rates[2]
		and mixed.limit_rates[4] == rows.limit_rates[4])
	var raw_q: PackedFloat64Array = frame.body.duplicate()
	for index in 4: raw_q[RB.ATT + index] *= 1.02
	var extended := Traction.evaluate(traction, raw_q, live.cg_body_m, frame.result.ground, PackedFloat64Array([1.0, 0.4, 1.0]))
	check("raw RK quaternion uses same normalized local geometry", extended.ok and _near(extended.jacobian, rows.jacobian))


func _moving_frame() -> void:
	var body := _body(-0.1)
	var moving := motion.duplicate(true)
	for row: Dictionary in moving:
		row.axle_body = M.q_rotate(M.q_from_euler(0.02, -0.1, 0.3), row.axle_body)
		row.carrier_rate_body = M.v3(0.2, -0.1, 0.3)
		row.carrier_accel_body = M.v3(-0.01, 0.02, 0.03)
	var result := _run(body, live, moving)
	check("rotating body and steering fixture evaluates", result.ok, str(result))
	if not result.ok: return
	var frame := {body = body, result = result}
	var rows := Traction.evaluate(traction, body, live.cg_body_m, result.ground, PackedFloat64Array([0.2, 0.3, 0.0]))
	check("bank/camber/steering/carrier rows assemble", rows.ok, str(rows))
	if not rows.ok: return
	var slips := _slips(rows, frame)
	var q := M.q_normalized(body.slice(RB.ATT, RB.ATT + 4))
	var inverse := PackedFloat64Array([q[0], -q[1], -q[2], -q[3]])
	for index in rows.labels.size():
		var label: Dictionary = rows.labels[index]
		var wheel: int = prepared.rotor_order.find(label.contact_id) - 1
		var record: Dictionary = result.ground.contacts[wheel]
		var axis: PackedFloat64Array = moving[wheel].axle_body
		var expected: float
		if label.kind in ["longitudinal", "lateral"]:
			var normal := M.q_rotate(inverse, record.normal_ned)
			var longitudinal := M.cross(axis, normal)
			longitudinal = M.scale(longitudinal, 1.0 / M.norm(longitudinal))
			var tangent := longitudinal if label.kind == "longitudinal" else M.cross(normal, longitudinal)
			expected = M.dot(tangent, record.point_velocity_body_mps)
		elif label.kind == "rolling_moment":
			expected = M.dot(axis, M.add(body.slice(RB.RATE), moving[wheel].carrier_rate_body)) + result.relative_spin_radps[wheel + 1]
		else: expected = result.relative_spin_radps[wheel + 1]
		check("complete row slip agrees with independently sampled contact kinematics: " + label.kind, absf(slips[index] - expected) < 1e-11)
	var applied := _apply_rows(rows, frame)
	check("moving prescribed carrier has a closed impulse work ledger", applied.ok and absf(applied.energy_balance_residual) < 1e-10, str(applied))


func _brakes() -> void:
	var air := _frame(-2.0, 3.0, PackedFloat64Array([3.0, 3.0, 3.0]))
	var rows := Traction.evaluate(traction, air.body, live.cg_body_m, air.result.ground, PackedFloat64Array([1.0, 0.0, 1.0]))
	check("airborne available brake remains internal and tail has no invented brake", rows.ok and rows.bias.size() == 1
		and rows.labels[0].kind == "internal_brake" and rows.limit_rates[0] == 2.0)
	var result := _apply_rows(rows, air)
	check("airborne brake slows its wheel with body reaction", result.ok and result.spin[1] < air.result.relative_spin_radps[1]
		and M.norm(result.delta_omega) > 0.0 and M.norm(result.delta_velocity_cm_body) == 0.0)
	if result.ok:
		check("internal brake produces no external angular impulse", result.generalized_impulse.slice(3, 6) == M.v3(0.0, 0.0, 0.0))
	var free := Traction.evaluate(traction, air.body, live.cg_body_m, air.result.ground, PackedFloat64Array([0.0, 0.0, 1.0]))
	check("no loaded contact and no installed demanded brake yields zero rows", free.ok and free.jacobian.is_empty() and free.groups.is_empty())
	var ground_frame := _frame(-0.19, 3.0, PackedFloat64Array([3.0, 3.0, 3.0]))
	var left := Traction.evaluate(traction, ground_frame.body, live.cg_body_m, ground_frame.result.ground, PackedFloat64Array([1.0, 0.0, 0.0]))
	var right := Traction.evaluate(traction, ground_frame.body, live.cg_body_m, ground_frame.result.ground, PackedFloat64Array([0.0, 1.0, 0.0]))
	var left_impulse := _apply_rows(left, ground_frame)
	var right_impulse := _apply_rows(right, ground_frame)
	check("differential braking creates the expected contact-induced yaw difference", left_impulse.ok and right_impulse.ok
		and left_impulse.omega[2] < right_impulse.omega[2], str([left_impulse.get("omega"), right_impulse.get("omega")]))


func _reject_rows() -> void:
	for kind: String in ["duplicate", "unknown", "unit", "negative", "nan", "extra", "source"]:
		var changed := pairs.duplicate(true)
		match kind:
			"duplicate": changed.append(changed[0].duplicate(true))
			"unknown": changed[0].material_id = "unspecified"
			"unit": changed[0].rolling_resistance.unit = "N"
			"negative": changed[0].lateral_friction.value = -1.0
			"nan": changed[0].longitudinal_friction.value = NAN
			"extra": changed[0].roughness = 0.2
			"source": changed[0].rolling_resistance.source = ""
		check("invalid material pair refuses: " + kind, not Traction.prepare(prepared, model, changed).ok)
	var frame := _frame()
	for kind: String in ["material", "unresolved", "unknown_geometry", "normal", "rho", "arm", "negative_load", "id", "index", "layout"]:
		var changed: Dictionary = frame.result.ground.duplicate(true)
		match kind:
			"material": changed.contacts[0].material_id = "unknown"
			"unresolved": changed.contacts[0].material_resolved = false
			"unknown_geometry": changed.contacts[0].geometry_status = "moving_support"
			"normal": changed.contacts[0].normal_ned = M.v3(0.0, 0.0, -2.0)
			"rho": changed.contacts[0].rho_body_m[2] *= 2.0
			"arm": changed.contacts[0].arm_datum_body_m[0] += 0.1
			"negative_load": changed.contacts[0].normal_load_n = -1.0
			"id": changed.contacts[0].contact_id = "unknown"
			"index": changed.contacts[0].contact_index = 1
			"layout": changed.contacts.pop_back()
		check("invalid normal receipt refuses: " + kind, not Traction.evaluate(traction, frame.body, live.cg_body_m, changed, PackedFloat64Array([0.0, 0.0, 0.0])).ok)
	for demand: PackedFloat64Array in [PackedFloat64Array(), PackedFloat64Array([NAN, 0.0, 0.0]), PackedFloat64Array([-1.0, 0.0, 0.0]), PackedFloat64Array([1.1, 0.0, 0.0])]:
		check("invalid proportional brake command refuses", not Traction.evaluate(traction, frame.body, live.cg_body_m, frame.result.ground, demand).ok)
	var bad := model.duplicate(true)
	bad.landing_gear.contacts[0].brake_torque = 7.0
	check("brake capacity cannot disagree with hardware provenance", not Traction.prepare(prepared, bad, pairs).ok)
	bad = model.duplicate(true)
	bad.landing_gear.contacts[2].brake_availability = "available"
	bad.landing_gear.contacts[2].wheel_provenance.brake_availability = "available"
	check("available brake cannot have zero torque", not Traction.prepare(prepared, bad, pairs).ok)
