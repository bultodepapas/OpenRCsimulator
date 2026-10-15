extends SceneTree

const Flight := preload("res://sim/flight_session.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Air := preload("res://physics/air_data.gd")
const Aero := preload("res://physics/aero.gd")
const M := preload("res://physics/math3d.gd")
const Reference := preload("res://tests/aero_flow_reference.gd")
const RB := preload("res://physics/rigid_body.gd")

const TARGET_ID := "gp-extra-300s-60"
const TARGET_SAMPLE := 1894

func _initialize() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 44117
	for id in Catalog.airplane_flyable_ids():
		var flight := Flight.new()
		flight.setup(Catalog.entry(id).data)
		root.add_child(flight)
		var model: Dictionary = flight.aircraft.model.duplicate(true)
		for key in ["downwash_gradient", "free_slope", "elevator_tau", "downwash_per_cl", "free_incidence", "wing_cl0"]:
			model.surfaces.horizontal.erase(key)
		model.surfaces.erase("wing_cm_ac")
		var state: PackedFloat64Array = flight.sim.state.duplicate()
		var d: Dictionary = flight._deflections(flight.sim.aux).duplicate()
		for sample in 2500:
			state[RB.VEL] = rng.randf_range(-40.0, 40.0)
			state[RB.VEL + 1] = rng.randf_range(-8.0, 8.0)
			state[RB.VEL + 2] = rng.randf_range(-12.0, 12.0)
			for axis in 3:
				state[RB.RATE + axis] = rng.randf_range(-5.0, 5.0)
			for control in d:
				d[control] = rng.randf_range(-0.6, 0.6)
			if sample % 2 == 0:
				state[RB.VEL] = 30.0
				state[RB.VEL + 1] *= 0.1
				state[RB.VEL + 2] *= 0.1
				for control in d:
					d[control] *= 0.1
			if sample % 50 == 0:
				model.cg_le[0] += rng.randf_range(-0.01, 0.01)
				model.surfaces.horizontal.position[2] += rng.randf_range(-0.01, 0.01)
			if id == TARGET_ID and sample == TARGET_SAMPLE:
				_report_case(state, d, model)
		flight.free()
	quit()


func _report_case(state: PackedFloat64Array, d: Dictionary, model: Dictionary) -> void:
	var air: Dictionary = Air.compute(state, PackedFloat64Array([0.0, 0.0, 0.0]), Air.RHO_SEA_LEVEL)
	var frozen: float = Reference.local_flow_weight(state, air, d, model)
	var mul_guard: Dictionary = _rate_guard(state, air, model, false)
	var pow_guard: Dictionary = _rate_guard(state, air, model, true)
	var actual: float = Aero.local_flow_weight(state, air, d, model)
	var expected: float = maxf(frozen, float(mul_guard.weight))
	var report := {
		"case": {"test": "app/tests/test_aero_flow.gd", "seed": 44117, "aircraft_id": TARGET_ID, "sample": TARGET_SAMPLE},
		"environment": {"rho_kgm3": Air.RHO_SEA_LEVEL, "wind_ned_mps": [0.0, 0.0, 0.0]},
		"state_float64": Array(state),
		"deflections": d,
		"air": air,
		"model_rate_geometry": {
			"attached_limit_rad": model.surfaces.attached_limit,
			"wing_envelope_a1_rad": model.envelope.a1,
			"wing_station_ys_m": model.envelope.station_ys,
			"arp_le_m": model.reference.arp_le,
			"cg_le_m_after_test_jitter": model.cg_le,
			"horizontal_position_le_m_after_test_jitter": model.surfaces.horizontal.position,
			"vertical_position_le_m": model.surfaces.vertical.position,
			"tail_local_limit_rad": model.surfaces.tail_local_limit,
		},
		"frozen_reference_weight": frozen,
		"independent_guard_multiplication": mul_guard,
		"independent_guard_pow": pow_guard,
		"expected_test_weight": expected,
		"current_aero_weight": actual,
		"difference_current_minus_expected": actual - expected,
		"expected_float64_hex": PackedFloat64Array([expected]).to_byte_array().hex_encode(),
		"actual_float64_hex": PackedFloat64Array([actual]).to_byte_array().hex_encode(),
		"local_loads_current": Array(Aero._local_loads(state, air, d, model, Air.RHO_SEA_LEVEL)),
	}
	print("R11_H4_CASE_JSON=" + JSON.stringify(report))


func _rate_guard(s: PackedFloat64Array, air: Dictionary, model: Dictionary, use_pow: bool) -> Dictionary:
	var p: float = s[RB.RATE]
	var q: float = s[RB.RATE + 1]
	var r: float = s[RB.RATE + 2]
	var limit: float = float(model.surfaces.attached_limit)
	var span: float = float(model.envelope.a1) - limit
	var cg: PackedFloat64Array = model.cg_le
	var arp: PackedFloat64Array = model.reference.arp_le
	var arm_x: float = -(arp[0] - cg[0])
	var arm_y: float = arp[1] - cg[1]
	var arm_z: float = -(arp[2] - cg[2])
	var rows: Array[Dictionary] = []
	var blend := 0.0
	for station_index in model.envelope.station_ys.size():
		var station_y: float = arm_y + float(model.envelope.station_ys[station_index])
		var row := _rate_row("wing_%02d" % station_index, q * arm_z - r * station_y,
			r * arm_x - p * arm_z, p * station_y - q * arm_x, float(air.V), limit, span, use_pow)
		rows.append(row)
		blend = maxf(blend, float(row.weight))
	for name: String in ["horizontal", "vertical"]:
		var surface: Dictionary = model.surfaces[name]
		var tx: float = -(float(surface.position[0]) - cg[0])
		var ty: float = float(surface.position[1]) - cg[1]
		var tz: float = -(float(surface.position[2]) - cg[2])
		var row := _rate_row("tail_" + name, q * tz - r * ty, r * tx - p * tz,
			p * ty - q * tx, float(air.V), limit, span, use_pow)
		rows.append(row)
		blend = maxf(blend, float(row.weight))
	return {"weight": blend, "rows": rows, "square_method": "pow(component,2)" if use_pow else "component*component"}


func _rate_row(label: String, dx: float, dy: float, dz: float, speed: float, limit: float, span: float, use_pow: bool) -> Dictionary:
	var squared: float
	if use_pow:
		squared = M.pow_(dx, 2) + M.pow_(dy, 2) + M.pow_(dz, 2)
	else:
		squared = dx * dx + dy * dy + dz * dz
	var rate_speed: float = M.sqrt_(squared)
	var angle: float = M.atan2_(rate_speed, speed)
	var weight: float = Aero._smoothstep((angle - limit) / span)
	var square_x: float = M.pow_(dx, 2) if use_pow else dx * dx
	var square_y: float = M.pow_(dy, 2) if use_pow else dy * dy
	var square_z: float = M.pow_(dz, 2) if use_pow else dz * dz
	return {"arm": label, "rate_components_rad_s": [dx, dy, dz],
		"component_float64_hex": [PackedFloat64Array([dx]).to_byte_array().hex_encode(),
			PackedFloat64Array([dy]).to_byte_array().hex_encode(), PackedFloat64Array([dz]).to_byte_array().hex_encode()],
		"component_square_float64_hex": [PackedFloat64Array([square_x]).to_byte_array().hex_encode(),
			PackedFloat64Array([square_y]).to_byte_array().hex_encode(), PackedFloat64Array([square_z]).to_byte_array().hex_encode()],
		"squared_speed": squared, "squared_speed_float64_hex": PackedFloat64Array([squared]).to_byte_array().hex_encode(),
		"rate_speed_mps": rate_speed, "rate_speed_float64_hex": PackedFloat64Array([rate_speed]).to_byte_array().hex_encode(),
		"air_speed_mps": speed, "rate_angle_rad": angle,
		"weight": weight, "weight_float64_hex": PackedFloat64Array([weight]).to_byte_array().hex_encode()}
