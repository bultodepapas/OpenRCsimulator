extends SceneTree

const AD := preload("res://physics/aircraft_data.gd")
const Air := preload("res://physics/air_data.gd")
const Aero := preload("res://physics/aero.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Slipstream := preload("res://physics/slipstream.gd")
const WingPolar := preload("res://physics/wing_polar.gd")

const STIK := "jensen-das-ugly-stik-60"
const AVANTI := "sebart-avanti-s-a200-p100rx"
const RHO := 1.225
const SPEED := 20.0
const ZERO := { elevator = 0.0, aileron_right = 0.0, aileron_left = 0.0, rudder = 0.0 }

var checks := 0
var failures := 0
var zero_rates := PackedFloat64Array([0.0, 0.0, 0.0])


func check(label: String, ok: bool, detail := "") -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label, " ", detail)


func _initialize() -> void:
	for id in [STIK, AVANTI]:
		var loaded: Dictionary = AD.load_file(Catalog.entry(id).data)
		check("%s data loads" % id, bool(loaded.get("ok", false)), str(loaded.get("errors", [])))
		if not loaded.get("ok", false):
			continue
		var model: Dictionary = loaded.model
		if id == AVANTI:
			_test_authored_avanti_polar(model)
		_test_cartesian_boundary(id, model)
		_test_mixed_stagnant_strip(id, model)
		_test_isolated_plane_power(id, model)
		_test_tail_wash_continuity(id, model)
		if id == STIK:
			_test_propwashed_tail_continuity(model)
	print("R02 continuity: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)


func _test_authored_avanti_polar(model: Dictionary) -> void:
	var polar: Dictionary = model.envelope.get("wing_polar", {})
	check("Avanti production model loads its authored positive/negative wing polar",
		polar.has("positive") and polar.has("negative") and polar.positive.values.size() >= 12 and polar.negative.values.size() >= 12,
		"polar keys=%s" % str(polar.keys()))
	if polar.is_empty():
		return
	check("Avanti table keeps its authored 8 deg asymmetric positive/negative data",
		absf(float(polar.positive.angles[0]) - deg_to_rad(8.0)) < 1e-15 \
			and absf(float(polar.positive.values[0]) - 0.5884998174197593) < 1e-12 \
			and absf(float(polar.negative.values[0]) - 0.5944935880193594) < 1e-12,
		"positive=%s negative=%s" % [str(polar.positive.values.slice(0, 3)), str(polar.negative.values.slice(0, 3))])
	var with_polar := _wing_only(model)
	var without_polar := with_polar.duplicate(true)
	without_polar.envelope.erase("wing_polar")
	var alpha := deg_to_rad(25.0)
	var state := _state(M.v3(SPEED * cos(alpha), 0.0, SPEED * sin(alpha)), zero_rates)
	var air := _air(state)
	var polar_rows: Array = Aero.wing_strip_loads(state, air, ZERO, with_polar, RHO)
	var linear_rows: Array = Aero.wing_strip_loads(state, air, ZERO, without_polar, RHO)
	var max_cl_delta := 0.0
	var max_cd_delta := 0.0
	var evaluator_match := true
	var slope: float = float(model.envelope.get("strip_slope", model.aero.CLa))
	var cl0s: PackedFloat64Array = model.envelope.get("strip_cl0", PackedFloat64Array())
	for i in polar_rows.size():
		var row: Dictionary = polar_rows[i]
		var linear_row: Dictionary = linear_rows[i]
		max_cl_delta = maxf(max_cl_delta, absf(float(row.cl) - float(linear_row.cl)))
		max_cd_delta = maxf(max_cd_delta, absf(float(row.cd) - float(linear_row.cd)))
		var base: float = float(model.aero.CL0) + float(model.aero.CLa) * float(row.alpha_geometric_rad)
		if cl0s.size() == polar_rows.size():
			base = float(cl0s[i]) + slope * float(row.alpha_effective_rad)
		var sample: PackedFloat64Array = WingPolar.evaluate(float(row.alpha_geometric_rad), base, polar)
		var expected_cd: float = sample[1] + sample[2] * float(model.aero.k_induced) \
			* pow(sample[0] - float(model.aero.CL_minD), 2.0)
		evaluator_match = evaluator_match and absf(float(row.cl) - sample[0]) < 1e-12 \
			and absf(float(row.cd) - expected_cd) < 1e-12
	check("Avanti authored polar changes runtime post-stall section coefficients at 25 deg",
		max_cl_delta > 0.02 or max_cd_delta > 0.02,
		"max |dCL|=%.9f max |dCD|=%.9f" % [max_cl_delta, max_cd_delta])
	check("Avanti runtime section coefficients match its authored polar evaluator", evaluator_match)


func _state(velocity: PackedFloat64Array, rates: PackedFloat64Array) -> PackedFloat64Array:
	return RB.make_state(M.v3(0.0, 0.0, -50.0), velocity, M.q_identity(), rates)


func _air(state: PackedFloat64Array) -> Dictionary:
	return Air.compute(state, M.v3(0.0, 0.0, 0.0), RHO)


func _wing_only(model: Dictionary) -> Dictionary:
	var isolated: Dictionary = model.duplicate(true)
	isolated.surfaces.horizontal.area = 0.0
	isolated.surfaces.vertical.area = 0.0
	isolated.surfaces.erase("wing_cm_ac")
	return isolated


func _scaled_error(a: PackedFloat64Array, b: PackedFloat64Array, model: Dictionary, speed_scale: float) -> float:
	var q_s: float = 0.5 * RHO * speed_scale * speed_scale * float(model.reference.S)
	var q_s_c: float = q_s * float(model.reference.c)
	var force_sq := 0.0
	var moment_sq := 0.0
	for i in 3:
		force_sq += (a[i] - b[i]) * (a[i] - b[i])
		moment_sq += (a[i + 3] - b[i + 3]) * (a[i + 3] - b[i + 3])
	return maxf(sqrt(force_sq) / q_s, sqrt(moment_sq) / q_s_c)


func _all_finite(values: PackedFloat64Array) -> bool:
	for value in values:
		if not is_finite(value):
			return false
	return true


func _test_cartesian_boundary(id: String, authored: Dictionary) -> void:
	var model := _wing_only(authored)
	var boundary_state := _state(M.v3(0.0, SPEED, 0.0), zero_rates)
	var boundary_air := _air(boundary_state)
	var reference: PackedFloat64Array = Aero._local_loads(boundary_state, boundary_air, ZERO, model, RHO)
	var reference_wake: float = Aero.wing_lift_coefficient(boundary_state, boundary_air, ZERO, model)
	var rows: Array = Aero.wing_strip_loads(boundary_state, boundary_air, ZERO, model, RHO)
	check("%s exact spanwise boundary is finite and retains all wing strips" % id,
		_all_finite(reference) and rows.size() == model.envelope.station_ys.size(), str(reference))
	for exponent in range(2, 10):
		var epsilon: float = SPEED * pow(10.0, -float(exponent))
		for path in [0, 1, 2, 3]:
			var velocity := M.v3(0.0, SPEED, 0.0)
			if path == 0:
				velocity[0] = epsilon
			elif path == 1:
				velocity[0] = -epsilon
			elif path == 2:
				velocity[2] = epsilon
			else:
				velocity[2] = -epsilon
			var state := _state(velocity, zero_rates)
			var air := _air(state)
			var actual: PackedFloat64Array = Aero._local_loads(state, air, ZERO, model, RHO)
			var wake: float = Aero.wing_lift_coefficient(state, air, ZERO, model)
			var error := _scaled_error(actual, reference, model, SPEED)
			var wake_scale: float = maxf(1.0, absf(reference_wake))
			var wake_error: float = absf(wake - reference_wake) / wake_scale
			if exponent == 9:
				check("%s Cartesian approach %d force/moment converges at epsilon/V ratio 1e-9" % [id, path],
					_all_finite(actual) and error < 1e-7, "normalized=%.9f" % error)
				check("%s Cartesian approach %d wake target converges at epsilon/V ratio 1e-9" % [id, path],
					is_finite(wake) and wake_error < 1e-7, "normalized=%.9f" % wake_error)
			elif exponent == 6 and path == 0:
				print("info %s spanwise boundary epsilon/V ratio 1e-6: force-moment %.9f, wake %.9f" % [id, error, wake_error])


func _arm_for_station(model: Dictionary, y: float) -> PackedFloat64Array:
	var arp: PackedFloat64Array = model.reference.arp_le
	var cg: PackedFloat64Array = model.cg_le
	return M.v3(-(arp[0] - cg[0]), arp[1] - cg[1] + y, -(arp[2] - cg[2]))


func _test_mixed_stagnant_strip(id: String, authored: Dictionary) -> void:
	var model := _wing_only(authored)
	var ys: PackedFloat64Array = model.envelope.station_ys
	if ys.size() < 3:
		check("%s has at least three wing strips" % id, false)
		return
	var target: int = ys.size() / 2
	var rates := M.v3(0.31, -0.22, 0.37)
	var spin_velocity := M.cross(rates, _arm_for_station(model, ys[target]))
	var stagnant_velocity := M.scale(spin_velocity, -1.0)
	var base_state := _state(stagnant_velocity, rates)
	var base_air := _air(base_state)
	var base_rows: Array = Aero.wing_strip_loads(base_state, base_air, ZERO, model, RHO)
	var base_wake: float = Aero.wing_lift_coefficient(base_state, base_air, ZERO, model)
	var target_row: Dictionary = base_rows[target]
	check("%s mixed case has one numerically stagnant station" % id,
		float(target_row.speed_mps) < 1e-8 and float(target_row.lift_n) == 0.0 and float(target_row.drag_n) == 0.0,
		"station=%d speed=%.9f" % [target, target_row.speed_mps])
	var loaded_count := 0
	for i in base_rows.size():
		if i != target and float(base_rows[i].speed_mps) > 1e-4:
			loaded_count += 1
	check("%s mixed case retains loaded wing stations around the stagnant one" % id, loaded_count >= 2,
		"loaded=%d" % loaded_count)
	var q_s: float = 0.5 * RHO * SPEED * SPEED * float(model.reference.S)
	var q_s_c: float = q_s * float(model.reference.c)
	for path in [0, 1]:
		var epsilon: float = SPEED * 1e-9
		var velocity := stagnant_velocity.duplicate()
		velocity[0 if path == 0 else 2] += epsilon
		var state := _state(velocity, rates)
		var air := _air(state)
		var rows: Array = Aero.wing_strip_loads(state, air, ZERO, model, RHO)
		var max_force_error := 0.0
		var max_moment_error := 0.0
		for i in rows.size():
			if i == target:
				continue # the undefined section coefficient itself is not a load oracle at zero projected flow
			for axis in 3:
				max_force_error = maxf(max_force_error,
					absf(rows[i].force_body_n[axis] - base_rows[i].force_body_n[axis]) / q_s)
				max_moment_error = maxf(max_moment_error,
					absf(rows[i].moment_body_nm[axis] - base_rows[i].moment_body_nm[axis]) / q_s_c)
		var wake: float = Aero.wing_lift_coefficient(state, air, ZERO, model)
		var wake_error: float = absf(wake - base_wake) / maxf(1.0, absf(base_wake))
		check("%s mixed stagnant/loaded path %d leaves loaded strips continuous" % [id, path],
			max_force_error < 1e-7 and max_moment_error < 1e-7,
			"force=%.9f moment=%.9f" % [max_force_error, max_moment_error])
		check("%s mixed stagnant/loaded path %d leaves wake continuous" % [id, path],
			is_finite(wake) and wake_error < 1e-7, "wake=%.9f" % wake_error)


func _test_isolated_plane_power(id: String, authored: Dictionary) -> void:
	var model := _wing_only(authored)
	var alpha := deg_to_rad(7.0)
	var velocity := M.v3(SPEED * cos(alpha), 0.0, SPEED * sin(alpha))
	var rates := M.v3(0.0, 0.4, 0.0) # pitch rate varies the local plane flow without adding spanwise velocity
	var state := _state(velocity, rates)
	var air := _air(state)
	var rows: Array = Aero.wing_strip_loads(state, air, ZERO, model, RHO)
	var station_area: float = float(model.reference.S) / float(rows.size())
	var plane_work_ok := true
	var lateral_force_ok := true
	var application_power := 0.0
	for i in rows.size():
		var flow := M.add(air.v_air, M.cross(rates, _arm_for_station(model, model.envelope.station_ys[i])))
		var vp := sqrt(flow[0] * flow[0] + flow[2] * flow[2])
		var force: PackedFloat64Array = rows[i].force_body_n
		var work: float = force[0] * flow[0] + force[2] * flow[2]
		var expected_drag_work: float = -0.5 * RHO * station_area * float(rows[i].cd) * vp * vp * vp
		var tolerance: float = maxf(1e-9, absf(expected_drag_work) * 1e-9)
		plane_work_ok = plane_work_ok and absf(work - expected_drag_work) <= tolerance
		lateral_force_ok = lateral_force_ok and absf(force[1]) <= maxf(1e-9, absf(work) / maxf(vp, 1.0) * 1e-9)
		application_power += M.dot(force, flow)
	var loads: PackedFloat64Array = Aero._local_loads(state, air, ZERO, model, RHO)
	var body_power: float = M.dot(loads.slice(0, 3), air.v_air) + M.dot(loads.slice(3, 6), rates)
	check("%s plane-section work equals negative drag work" % id, plane_work_ok)
	check("%s pure-plane wing load has no span force" % id, lateral_force_ok)
	check("%s application-point force/moment power identity holds" % id,
		absf(body_power - application_power) <= maxf(1e-8, absf(application_power) * 1e-10),
		"body=%.12f local-sum=%.12f W" % [body_power, application_power])
	check("%s isolated fixed-control wing is passive" % id, body_power <= 1e-8, "power=%.12f W" % body_power)
	for name in ["horizontal", "vertical"]:
		var vertical: bool = name == "vertical"
		var tail: Dictionary = model.surfaces[name]
		var tail_velocity := M.v3(SPEED * cos(alpha), SPEED * sin(alpha) if vertical else 0.0,
			0.0 if vertical else SPEED * sin(alpha))
		var tail_load: PackedFloat64Array = Aero.tail_surface_load(tail_velocity, zero_rates, ZERO,
			model, name, tail.area, M.v3(0.0, 0.0, 0.0), M.v3(0.0, 0.0, 0.0), RHO)
		var arm := _tail_arm(model, name)
		var moment_from_force := M.cross(arm, tail_load.slice(0, 3))
		var tail_power: float = M.dot(tail_load.slice(0, 3), tail_velocity)
		check("%s %s tail moment is the force moment about its application point" % [id, name],
			maxf(absf(tail_load[3] - moment_from_force[0]), maxf(absf(tail_load[4] - moment_from_force[1]),
				absf(tail_load[5] - moment_from_force[2]))) < 1e-10)
		check("%s isolated %s tail is passive" % [id, name], tail_power <= 1e-8,
			"power=%.12f W" % tail_power)


func _tail_arm(model: Dictionary, name: String) -> PackedFloat64Array:
	var tail: Dictionary = model.surfaces[name]
	var position: PackedFloat64Array = tail.position
	var cg: PackedFloat64Array = model.cg_le
	return M.v3(-(position[0] - cg[0]), position[1] - cg[1], -(position[2] - cg[2]))


func _test_tail_wash_continuity(id: String, model: Dictionary) -> void:
	var extra := M.v3(0.7, -0.15, 0.22)
	var boundary := M.v3(0.0, SPEED, 0.0)
	for name in ["horizontal", "vertical"]:
		var tail: Dictionary = model.surfaces[name]
		var area: float = float(tail.area) * 0.5
		var reference: PackedFloat64Array = Aero.tail_surface_increment(boundary, zero_rates, ZERO, model,
			name, area, M.v3(0.0, 0.0, 0.0), extra, RHO)
		var max_error := 0.0
		for path in [0, 1, 2, 3]:
			var epsilon: float = SPEED * 1e-9
			var velocity := boundary.duplicate()
			if path == 0:
				velocity[0] = epsilon
			elif path == 1:
				velocity[0] = -epsilon
			elif path == 2:
				velocity[2] = epsilon
			else:
				velocity[2] = -epsilon
			var actual: PackedFloat64Array = Aero.tail_surface_increment(velocity, zero_rates, ZERO, model,
				name, area, M.v3(0.0, 0.0, 0.0), extra, RHO)
			max_error = maxf(max_error, _scaled_error(actual, reference, model, SPEED))
		check("%s washed-minus-free %s tail is Cartesian-continuous" % [id, name],
			_all_finite(reference) and max_error < 1e-7, "normalized=%.9f" % max_error)


func _test_propwashed_tail_continuity(model: Dictionary) -> void:
	var boundary := M.v3(0.0, SPEED, 0.0)
	var state := _state(boundary, zero_rates)
	var air := _air(state)
	var rpm := 6000.0
	var reference: PackedFloat64Array = Slipstream.loads(state, air, ZERO, model, rpm, RHO)
	for path in [0, 2]:
		var epsilon: float = SPEED * 1e-9
		var velocity := boundary.duplicate()
		velocity[0 if path == 0 else 2] = epsilon
		var candidate_state := _state(velocity, zero_rates)
		var candidate_air := _air(candidate_state)
		var actual: PackedFloat64Array = Slipstream.loads(candidate_state, candidate_air, ZERO, model, rpm, RHO)
		var error := _scaled_error(actual, reference, model, SPEED)
		check("Stik active propwash output remains continuous at a cross-flow boundary %d" % path,
			_all_finite(actual) and error < 1e-7, "normalized=%.9f" % error)
