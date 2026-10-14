extends SceneTree

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Air := preload("res://physics/air_data.gd")
const Aero := preload("res://physics/aero.gd")
const AD := preload("res://physics/aircraft_data.gd")
const Controls := preload("res://physics/control_surfaces.gd")

const INPUTS := [
	"res://data/aircraft/sebart_avanti_s_a200.json",
	"res://data/aircraft/jensen_ugly_stik_60.json",
]
const RATE_STEP := 0.01


func _initialize() -> void:
	for path: String in INPUTS:
		var loaded: Dictionary = AD.load_file(path)
		if not loaded.get("ok", false):
			printerr("LOAD_FAIL %s %s" % [path, loaded.get("errors", [])])
			continue
		_audit_model(path, loaded)
	quit(0)


func _state(speed: float, alpha: float, beta: float, rates: PackedFloat64Array) -> PackedFloat64Array:
	return RB.make_state(M.v3(0.0, 0.0, -50.0),
		M.v3(speed * cos(alpha) * cos(beta), speed * sin(beta), speed * sin(alpha) * cos(beta)),
		M.q_identity(), rates)


func _air(speed: float, alpha: float, beta: float, rates := PackedFloat64Array([0.0, 0.0, 0.0])) -> Dictionary:
	var state := _state(speed, alpha, beta, rates)
	return Air.compute(state, M.v3(0.0, 0.0, 0.0))


func _loads(model: Dictionary, speed: float, alpha: float, beta: float,
		rates := PackedFloat64Array([0.0, 0.0, 0.0]), d := {}) -> PackedFloat64Array:
	var state := _state(speed, alpha, beta, rates)
	var air: Dictionary = Air.compute(state, M.v3(0.0, 0.0, 0.0))
	var deflections: Dictionary = d if not d.is_empty() else _neutral()
	return Aero.loads(state, air, deflections, model, Air.RHO_SEA_LEVEL)


func _neutral() -> Dictionary:
	return {elevator = 0.0, aileron_right = 0.0, aileron_left = 0.0, rudder = 0.0}


func _wind_coefficients(load: PackedFloat64Array, air: Dictionary, model: Dictionary) -> Dictionary:
	var alpha: float = air.alpha
	var beta: float = air.beta
	var ca := cos(alpha)
	var sa := sin(alpha)
	var cb := cos(beta)
	var sb := sin(beta)
	var fx: float = load[0]
	var fy: float = load[1]
	var fz: float = load[2]
	var x_wind := ca * cb * fx + sb * fy + sa * cb * fz
	var y_wind := -ca * sb * fx + cb * fy - sa * sb * fz
	var z_wind := -sa * fx + ca * fz
	var reference: Dictionary = model.reference
	var cg: PackedFloat64Array = model.cg_le
	var arp: PackedFloat64Array = reference.arp_le
	var rx := -(arp[0] - cg[0])
	var ry := arp[1] - cg[1]
	var rz := -(arp[2] - cg[2])
	var transfer_x := ry * fz - rz * fy
	var transfer_y := rz * fx - rx * fz
	var transfer_z := rx * fy - ry * fx
	var qS: float = air.qbar * reference.S
	var moment_scale: float = qS * reference.c
	var roll_scale: float = qS * reference.b
	return {
		CL = -z_wind / qS,
		CD = -x_wind / qS,
		CY = y_wind / qS,
		Cl = (load[3] - transfer_x) / roll_scale,
		Cm = (load[4] - transfer_y) / moment_scale,
		Cn = (load[5] - transfer_z) / roll_scale,
	}


func _power(load: PackedFloat64Array, state: PackedFloat64Array, air: Dictionary) -> float:
	var v: PackedFloat64Array = air.v_air
	return load[0] * v[0] + load[1] * v[1] + load[2] * v[2] \
		+ load[3] * state[RB.RATE] + load[4] * state[RB.RATE + 1] + load[5] * state[RB.RATE + 2]


func _pilot_deflections(model: Dictionary, command: Dictionary) -> Dictionary:
	var angles: Dictionary = Controls.surface_deflections_deg(command, model.controls.throw_deg)
	return Aero.deflections_from_surfaces(angles)


func _finite_load(load: PackedFloat64Array) -> bool:
	for value: float in load:
		if not is_finite(value):
			return false
	return true


func _audit_model(path: String, loaded: Dictionary) -> void:
	var model: Dictionary = loaded.model
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var speed: float = float(raw.get("start", {}).get("level_speed", {}).get("value", 15.0))
	var id: String = str(raw.get("id", path))
	var identity: String = str(loaded.get("input_identity", {}).get("sha256", "missing"))
	var ref: Dictionary = model.reference
	var envelope: Dictionary = model.envelope
	var aero: Dictionary = model.aero
	print("MODEL id=%s input=%s sha256=%s V=%0.3f S=%0.6f b=%0.6f c=%0.6f" %
		[id, path, identity, speed, ref.S, ref.b, ref.c])
	_wind_basis_self_test()
	print("DATA CL0=%0.6f CLa=%0.6f CLmax=%0.6f CLmin=%0.6f a1=%0.6fdeg a2=%0.6fdeg n1=%0.6fdeg n2=%0.6fdeg beta=%0.6f..%0.6fdeg CD90=%0.6f wing_polar=%s" %
		[aero.CL0, aero.CLa, envelope.CL_max, envelope.CL_min, rad_to_deg(envelope.a1), rad_to_deg(envelope.a2),
		rad_to_deg(envelope.n1), rad_to_deg(envelope.n2), rad_to_deg(envelope.b1), rad_to_deg(envelope.b2),
		envelope.CD90, str(not envelope.get("wing_polar", {}).is_empty())])
	_envelope_sweep(model, speed)
	_boundary_sweep(model, speed)
	_control_sweep(model, speed)
	_rate_recovery(model, speed)
	_power_sweep(model, speed)
	_cartesian_crossflow_sweep(model, speed)
	print("END_MODEL id=%s" % id)


func _wind_basis_self_test() -> void:
	var alpha := deg_to_rad(30.0)
	var dummy_model := {
		reference = {S = 1.0, b = 1.0, c = 1.0, arp_le = M.v3(0.0, 0.0, 0.0)},
		cg_le = M.v3(0.0, 0.0, 0.0),
	}
	var air := {alpha = alpha, beta = 0.0, qbar = 1.0}
	var drag_load := PackedFloat64Array([-cos(alpha), 0.0, -sin(alpha), 0.0, 0.0, 0.0])
	var lift_load := PackedFloat64Array([sin(alpha), 0.0, -cos(alpha), 0.0, 0.0, 0.0])
	var drag := _wind_coefficients(drag_load, air, dummy_model)
	var lift := _wind_coefficients(lift_load, air, dummy_model)
	var ok := absf(drag.CD - 1.0) < 1e-12 and absf(drag.CL) < 1e-12 \
		and absf(lift.CL - 1.0) < 1e-12 and absf(lift.CD) < 1e-12
	print("WIND_BASIS_SELFTEST alpha=30deg pure_drag=%s pure_lift=%s ok=%s" % [str(drag), str(lift), str(ok)])


func _envelope_sweep(model: Dictionary, speed: float) -> void:
	var rates := M.v3(0.0, 0.0, 0.0)
	var d := _neutral()
	var max_cl := -INF
	var max_at := 0.0
	var min_cl := INF
	var min_at := 0.0
	var min_cd := INF
	var min_cd_at := 0.0
	var min_drag := INF
	var finite := true
	for sample in range(-1800, 1801):
		var angle_deg := float(sample) * 0.1
		var alpha := deg_to_rad(angle_deg)
		var state := _state(speed, alpha, 0.0, rates)
		var air: Dictionary = Air.compute(state, M.v3(0.0, 0.0, 0.0))
		var load: PackedFloat64Array = Aero.loads(state, air, d, model, Air.RHO_SEA_LEVEL)
		var coeff: Dictionary = _wind_coefficients(load, air, model)
		finite = finite and _finite_load(load)
		for key: String in coeff:
			finite = finite and is_finite(coeff[key])
		if coeff.CL > max_cl:
			max_cl = coeff.CL
			max_at = angle_deg
		if coeff.CL < min_cl:
			min_cl = coeff.CL
			min_at = angle_deg
		if coeff.CD < min_cd:
			min_cd = coeff.CD
			min_cd_at = angle_deg
		min_drag = minf(min_drag, -load[0] * air.v_air[0] - load[1] * air.v_air[1] - load[2] * air.v_air[2])
	var declared: Dictionary = model.envelope
	print("ENVELOPE loaded_CL_max=%0.6f@%0.2fdeg loaded_CL_min=%0.6f@%0.2fdeg min_CD=%0.6f@%0.2fdeg min_translational_drag_power=%0.6fW finite=%s" %
		[max_cl, max_at, min_cl, min_at, min_cd, min_cd_at, min_drag, str(finite)])
	print("ENVELOPE_TARGET declared_CLmax=%0.6f declared_CLmin=%0.6f" % [declared.CL_max, declared.CL_min])
	for angle_deg in [-180.0, -150.0, -120.0, -90.0, -30.0, 0.0, 30.0, 90.0, 120.0, 150.0, 180.0]:
		var alpha := deg_to_rad(angle_deg)
		var state := _state(speed, alpha, 0.0, rates)
		var air: Dictionary = Air.compute(state, M.v3(0.0, 0.0, 0.0))
		var load: PackedFloat64Array = Aero.loads(state, air, d, model, Air.RHO_SEA_LEVEL)
		var blend: float = Aero.local_flow_weight(state, air, d, model)
		var coeff: Dictionary = _wind_coefficients(load, air, model)
		print("ALPHA deg=%0.2f blend=%0.6f CL=%0.6f CD=%0.6f CY=%0.6f Cm=%0.6f power=%0.6fW" %
			[angle_deg, blend, coeff.CL, coeff.CD, coeff.CY, coeff.Cm, _power(load, state, air)])


func _boundary_sweep(model: Dictionary, speed: float) -> void:
	var rates := M.v3(0.0, 0.0, 0.0)
	var d := _neutral()
	for angle_deg in [-25.01, -25.0, -24.99, -15.01, -15.0, -14.99, -8.01, -8.0, -7.99,
		7.99, 8.0, 8.01, 14.99, 15.0, 15.01, 24.99, 25.0, 25.01]:
		var alpha := deg_to_rad(angle_deg)
		var state := _state(speed, alpha, 0.0, rates)
		var air: Dictionary = Air.compute(state, M.v3(0.0, 0.0, 0.0))
		var load: PackedFloat64Array = Aero.loads(state, air, d, model, Air.RHO_SEA_LEVEL)
		var coeff: Dictionary = _wind_coefficients(load, air, model)
		print("ALPHA_BOUND deg=%0.2f w=%0.8f CL=%0.8f CD=%0.8f Cm=%0.8f" %
			[angle_deg, Aero.local_flow_weight(state, air, d, model), coeff.CL, coeff.CD, coeff.Cm])
	for angle_deg in [0.0]:
		for beta_deg in [-25.01, -25.0, -24.99, -15.01, -15.0, -14.99, 14.99, 15.0, 15.01, 24.99, 25.0, 25.01]:
			var state := _state(speed, deg_to_rad(angle_deg), deg_to_rad(beta_deg), rates)
			var air: Dictionary = Air.compute(state, M.v3(0.0, 0.0, 0.0))
			var load: PackedFloat64Array = Aero.loads(state, air, d, model, Air.RHO_SEA_LEVEL)
			var coeff: Dictionary = _wind_coefficients(load, air, model)
			print("BETA_BOUND deg=%0.2f w=%0.8f CL=%0.8f CY=%0.8f Cl=%0.8f Cn=%0.8f" %
				[beta_deg, Aero.local_flow_weight(state, air, d, model), coeff.CL, coeff.CY, coeff.Cl, coeff.Cn])


func _control_sweep(model: Dictionary, speed: float) -> void:
	var state := _state(speed, 0.0, 0.0, M.v3(0.0, 0.0, 0.0))
	var air: Dictionary = Air.compute(state, M.v3(0.0, 0.0, 0.0))
	var base: PackedFloat64Array = Aero.loads(state, air, _neutral(), model, Air.RHO_SEA_LEVEL)
	var axis_to_moment := {roll = 3, pitch = 4, yaw = 5}
	for axis: String in ["roll", "pitch", "yaw"]:
		for sign: float in [-1.0, 1.0]:
			var command := {roll = 0.0, pitch = 0.0, yaw = 0.0}
			command[axis] = sign
			var d: Dictionary = _pilot_deflections(model, command)
			var load: PackedFloat64Array = Aero.loads(state, air, d, model, Air.RHO_SEA_LEVEL)
			var idx: int = axis_to_moment[axis]
			var expected_sign: bool = signf(load[idx] - base[idx]) == sign
			var angles: Dictionary = Controls.surface_deflections_deg(command, model.controls.throw_deg)
			print("CONTROL axis=%s cmd=%+0.1f data_d=%s pilot_deg=%s delta_F=%0.6f,%0.6f,%0.6f delta_M=%0.6f,%0.6f,%0.6f w=%0.6f expected_axis_sign=%s" %
				[axis, sign, str(d), str(angles), load[0]-base[0], load[1]-base[1], load[2]-base[2],
				load[3]-base[3], load[4]-base[4], load[5]-base[5],
				Aero.local_flow_weight(state, air, d, model), str(expected_sign)])


func _rate_recovery(model: Dictionary, speed: float) -> void:
	var checks := [
		{"axis": 0, "force": "CY", "moment": "Cl", "other": "Cn", "length": model.reference.b,
			"force_coeff": "CYp", "moment_coeff": "Clp", "other_coeff": "Cnp"},
		{"axis": 1, "force": "CL", "moment": "Cm", "other": "", "length": model.reference.c,
			"force_coeff": "CLq", "moment_coeff": "Cmq", "other_coeff": ""},
		{"axis": 2, "force": "CY", "moment": "Cn", "other": "Cl", "length": model.reference.b,
			"force_coeff": "CYr", "moment_coeff": "Cnr", "other_coeff": "Clr"},
	]
	for check: Dictionary in checks:
		var rates_pos := M.v3(0.0, 0.0, 0.0)
		var rates_neg := M.v3(0.0, 0.0, 0.0)
		rates_pos[int(check.axis)] = RATE_STEP
		rates_neg[int(check.axis)] = -RATE_STEP
		var state_pos := _state(speed, 0.0, 0.0, rates_pos)
		var state_neg := _state(speed, 0.0, 0.0, rates_neg)
		var air_pos: Dictionary = Air.compute(state_pos, M.v3(0.0, 0.0, 0.0))
		var air_neg: Dictionary = Air.compute(state_neg, M.v3(0.0, 0.0, 0.0))
		var load_pos: PackedFloat64Array = Aero.loads(state_pos, air_pos, _neutral(), model, Air.RHO_SEA_LEVEL)
		var load_neg: PackedFloat64Array = Aero.loads(state_neg, air_neg, _neutral(), model, Air.RHO_SEA_LEVEL)
		var coeff_pos: Dictionary = _wind_coefficients(load_pos, air_pos, model)
		var coeff_neg: Dictionary = _wind_coefficients(load_neg, air_neg, model)
		var hat: float = RATE_STEP * float(check.length) / (2.0 * speed)
		var recovered: Dictionary = {}
		for metric: String in [str(check.force), str(check.moment)]:
			recovered[metric] = (float(coeff_pos[metric]) - float(coeff_neg[metric])) / (2.0 * hat)
		if not str(check.other).is_empty():
			recovered[str(check.other)] = (float(coeff_pos[str(check.other)]) - float(coeff_neg[str(check.other)])) / (2.0 * hat)
		var expected: Dictionary = {}
		for metric in [str(check.force), str(check.moment)]:
			var coeff_name: String = str(check.force_coeff) if metric == str(check.force) else str(check.moment_coeff)
			expected[metric] = float(model.aero[coeff_name])
		if not str(check.other).is_empty():
			expected[str(check.other)] = float(model.aero[str(check.other_coeff)])
		print("RATE axis=%s step=%0.4f blend=%0.8f recovered=%s data=%s" %
			["pqr"[int(check.axis)], RATE_STEP, maxf(Aero.local_flow_weight(state_pos, air_pos, _neutral(), model),
				Aero.local_flow_weight(state_neg, air_neg, _neutral(), model)), str(recovered), str(expected)])


func _power_sweep(model: Dictionary, speed: float) -> void:
	var angles := [-180.0, -150.0, -120.0, -90.0, -60.0, -30.0, -25.0, -15.0, 0.0, 15.0, 25.0,
		30.0, 60.0, 90.0, 120.0, 150.0, 180.0]
	var slips := [-90.0, -75.0, -45.0, -25.0, -15.0, 0.0, 15.0, 25.0, 45.0, 75.0, 90.0]
	var rates := [M.v3(0.0, 0.0, 0.0), M.v3(1.0, 0.0, 0.0), M.v3(-1.0, 0.0, 0.0),
		M.v3(0.0, 1.0, 0.0), M.v3(0.0, -1.0, 0.0), M.v3(0.0, 0.0, 1.0), M.v3(0.0, 0.0, -1.0),
		M.v3(2.0, -2.0, 2.0), M.v3(-2.0, 2.0, -2.0)]
	var max_power := -INF
	var max_where := ""
	var positive_count := 0
	var finite := true
	var samples := 0
	for alpha_deg: float in angles:
		for beta_deg: float in slips:
			for rate: PackedFloat64Array in rates:
				var state := _state(speed, deg_to_rad(alpha_deg), deg_to_rad(beta_deg), rate)
				var air: Dictionary = Air.compute(state, M.v3(0.0, 0.0, 0.0))
				var load: PackedFloat64Array = Aero.loads(state, air, _neutral(), model, Air.RHO_SEA_LEVEL)
				var power := _power(load, state, air)
				finite = finite and _finite_load(load) and is_finite(power)
				if power > 1e-9:
					positive_count += 1
				if power > max_power:
					max_power = power
					max_where = "alpha=%0.1f beta=%0.1f rates=%s blend=%0.6f" % [
						alpha_deg, beta_deg, str(rate), Aero.local_flow_weight(state, air, _neutral(), model)
					]
				samples += 1
	print("POWER_GRID n=%d positive=%d max=%0.9fW at=%s finite=%s" % [samples, positive_count, max_power, max_where, str(finite)])
	for beta_deg in [-90.0, 0.0, 90.0]:
		for alpha_deg in [-180.0, -90.0, 0.0, 90.0, 180.0]:
			var state := _state(speed, deg_to_rad(alpha_deg), deg_to_rad(beta_deg), M.v3(0.0, 0.0, 0.0))
			var air: Dictionary = Air.compute(state, M.v3(0.0, 0.0, 0.0))
			var load: PackedFloat64Array = Aero.loads(state, air, _neutral(), model, Air.RHO_SEA_LEVEL)
			var coeff: Dictionary = _wind_coefficients(load, air, model)
			print("AXIS alpha=%+0.1f beta=%+0.1f alpha_air=%+0.3f beta_air=%+0.3f blend=%0.6f CL=%0.6f CD=%0.6f CY=%0.6f P=%0.6fW" %
				[alpha_deg, beta_deg, rad_to_deg(air.alpha), rad_to_deg(air.beta),
				Aero.local_flow_weight(state, air, _neutral(), model), coeff.CL, coeff.CD, coeff.CY,
				_power(load, state, air)])


func _cartesian_crossflow_sweep(model: Dictionary, speed: float) -> void:
	var epsilons := [1e-2, 1e-4, 1e-6, 1e-9]
	var rates := M.v3(0.0, 0.0, 0.0)
	var zero_controls := _neutral()
	for epsilon: float in epsilons:
		var residual_speed := sqrt(speed * speed - epsilon * epsilon)
		for axis_case: String in ["+u", "-u", "+w", "-w"]:
			var v := M.v3(0.0, residual_speed, 0.0)
			if axis_case == "+u":
				v[0] = epsilon
			elif axis_case == "-u":
				v[0] = -epsilon
			elif axis_case == "+w":
				v[2] = epsilon
			else:
				v[2] = -epsilon
			_cartesian_crossflow_case(model, speed, epsilon, axis_case, v, rates, zero_controls)
	var exact := M.v3(0.0, speed, 0.0)
	_cartesian_crossflow_case(model, speed, 0.0, "exact_side", exact, rates, zero_controls)


func _cartesian_crossflow_case(model: Dictionary, speed: float, epsilon: float, axis_case: String,
		v: PackedFloat64Array, rates: PackedFloat64Array, d: Dictionary) -> void:
	var state := RB.make_state(M.v3(0.0, 0.0, -50.0), v, M.q_identity(), rates)
	var air: Dictionary = Air.compute(state, M.v3(0.0, 0.0, 0.0))
	var strip_diagnostics: Array = []
	var local: PackedFloat64Array = Aero._local_loads(state, air, d, model, Air.RHO_SEA_LEVEL,
		NAN, strip_diagnostics)
	var total: PackedFloat64Array = Aero.loads(state, air, d, model, Air.RHO_SEA_LEVEL)
	var wing_force := M.v3(0.0, 0.0, 0.0)
	var wing_moment := M.v3(0.0, 0.0, 0.0)
	var wing_drag := 0.0
	for detail: Dictionary in strip_diagnostics:
		var force: PackedFloat64Array = detail.force_body_n
		var moment: PackedFloat64Array = detail.moment_body_nm
		for axis in 3:
			wing_force[axis] += force[axis]
			wing_moment[axis] += moment[axis]
		wing_drag += float(detail.drag_n)
	var qS: float = air.qbar * float(model.reference.S)
	var V: float = sqrt(M.dot(v, v))
	var wing_cd: float = wing_drag / qS if qS > 0.0 else NAN
	var total_cd: float = -(total[0] * v[0] + total[1] * v[1] + total[2] * v[2]) / (V * qS) if qS > 0.0 else NAN
	print("CART_CROSSFLOW eps=%s case=%s v=%s alpha=%0.6fdeg beta=%0.6fdeg blend=%0.8f wing_CD=%0.9f wing_F=%0.9f,%0.9f,%0.9f wing_M=%0.9f,%0.9f,%0.9f total_F=%0.9f,%0.9f,%0.9f total_M=%0.9f,%0.9f,%0.9f total_CD=%0.9f P=%0.9fW strips=%d local_match=%s" %
		[str(epsilon), axis_case, str(v), rad_to_deg(air.alpha), rad_to_deg(air.beta),
		Aero.local_flow_weight(state, air, d, model), wing_cd, wing_force[0], wing_force[1], wing_force[2],
		wing_moment[0], wing_moment[1], wing_moment[2], total[0], total[1], total[2],
		total[3], total[4], total[5], total_cd, _power(total, state, air), strip_diagnostics.size(),
		str(local.to_byte_array() == total.to_byte_array())])
