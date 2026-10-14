# HELI-06b: passive FRD extension of Gavrilets §§4.3–4.5 forms.
# Wake inputs are AIR-velocity increments at each CP, not body velocities.
# No source sign correction or rotor-wake closure is hidden in this kernel.
extends RefCounted

const M = preload("res://physics/math3d.gd")
const LAW: String = "openrc-passive-rotorcraft-airframe-v1"
const PARAMETER_KEYS: Array = ["rho_kg_m3", "fuselage_drag_area_body_m2", "fuselage_cp_body_frd_m",
	"vertical_fin_area_m2", "vertical_fin_lift_curve_slope_per_rad", "vertical_fin_cp_body_frd_m",
	"horizontal_tail_area_m2", "horizontal_tail_lift_curve_slope_per_rad", "horizontal_tail_cp_body_frd_m"]
const PREPARED_KEYS: Array = ["law", "rho_kg_m3",
	"fuselage_area_x_m2", "fuselage_area_y_m2", "fuselage_area_z_m2", "fuselage_x_m", "fuselage_y_m", "fuselage_z_m",
	"vertical_fin_area_m2", "vertical_fin_lift_curve_slope_per_rad", "vertical_fin_x_m", "vertical_fin_y_m", "vertical_fin_z_m",
	"horizontal_tail_area_m2", "horizontal_tail_lift_curve_slope_per_rad", "horizontal_tail_x_m", "horizontal_tail_y_m", "horizontal_tail_z_m"]


static func prepare(parameters: Dictionary) -> Dictionary:
	if parameters.size() != PARAMETER_KEYS.size() or not parameters.has_all(PARAMETER_KEYS):
		return {"ok": false}
	var model: Dictionary = {"law": LAW}
	for key: String in ["rho_kg_m3", "vertical_fin_area_m2", "vertical_fin_lift_curve_slope_per_rad",
		"horizontal_tail_area_m2", "horizontal_tail_lift_curve_slope_per_rad"]:
		if not _number(parameters[key]) or float(parameters[key]) < 0.0:
			return {"ok": false}
		model[key] = float(parameters[key])
	if model.rho_kg_m3 <= 0.0:
		return {"ok": false}
	for prefix: String in ["fuselage", "vertical_fin", "horizontal_tail"]:
		var arm: Variant = parameters[prefix + "_cp_body_frd_m"]
		if not _parameter_vector(arm):
			return {"ok": false}
		for i: int in range(3):
			model[prefix + "_" + ["x", "y", "z"][i] + "_m"] = float(arm[i])
	var areas: Variant = parameters.fuselage_drag_area_body_m2
	if not _parameter_vector(areas):
		return {"ok": false}
	for i: int in range(3):
		if float(areas[i]) < 0.0:
			return {"ok": false}
		model["fuselage_area_" + ["x", "y", "z"][i] + "_m2"] = float(areas[i])
	model.make_read_only() # Flat, detached scalars; no mutable arm/area arrays.
	return {"ok": true, "model": model}


# Vrel = Vcg_air + omega_body × arm - Vwake_air at the same RK stage.
# Forces resist local relative flow; body work can be supplied by moving air.
static func evaluate(model: Dictionary, cg_air: PackedFloat64Array, rates: PackedFloat64Array,
		fuselage_wake: PackedFloat64Array, fin_wake: PackedFloat64Array, tail_wake: PackedFloat64Array,
		diagnostics: bool = true) -> Dictionary:
	if not _prepared(model):
		return {"ok": false}
	return _evaluate_prepared(model, cg_air, rates, fuselage_wake, fin_wake, tail_wake, diagnostics)


# Internal stage entry after its immutable stage context was prepared.
static func _evaluate_prepared(model: Dictionary, cg_air: PackedFloat64Array, rates: PackedFloat64Array,
		fuselage_wake: PackedFloat64Array, fin_wake: PackedFloat64Array, tail_wake: PackedFloat64Array,
		diagnostics: bool = true) -> Dictionary:
	if not _vector(cg_air) or not _vector(rates) \
		or not _vector(fuselage_wake) or not _vector(fin_wake) or not _vector(tail_wake):
		return {"ok": false}
	var fuselage: Dictionary = _piece(model, "fuselage", cg_air, rates, fuselage_wake, diagnostics)
	var fin: Dictionary = _piece(model, "vertical_fin", cg_air, rates, fin_wake, diagnostics)
	var tail: Dictionary = _piece(model, "horizontal_tail", cg_air, rates, tail_wake, diagnostics)
	if not fuselage.ok or not fin.ok or not tail.ok:
		return {"ok": false}
	var loads: PackedFloat64Array = PackedFloat64Array()
	loads.resize(6)
	for i: int in range(6):
		loads[i] = fuselage.loads[i] + fin.loads[i] + tail.loads[i]
	var relative_power: float = fuselage.relative_power + fin.relative_power + tail.relative_power
	var body_power: float = fuselage.body_power + fin.body_power + tail.body_power
	var wake_power: float = fuselage.wake_power + fin.wake_power + tail.wake_power
	if not _vector6(loads) or not _finite([relative_power, body_power, wake_power]):
		return {"ok": false}
	var result: Dictionary = {"ok": true, "loads": loads, "relative_power_w": relative_power,
		"body_air_power_w": body_power, "wake_power_w": wake_power}
	if diagnostics:
		for item: Array in [["fuselage", fuselage], ["vertical_fin", fin], ["horizontal_tail", tail]]:
			var prefix: String = item[0]
			var piece: Dictionary = item[1]
			result[prefix + "_loads"] = piece.loads
			result[prefix + "_relative_air_m_s"] = piece.relative_air
			result[prefix + "_force_body_frd_n"] = piece.force
			result[prefix + "_moment_body_frd_nm"] = piece.moment
			result[prefix + "_relative_power_w"] = piece.relative_power
			result[prefix + "_body_air_power_w"] = piece.body_power
			result[prefix + "_wake_power_w"] = piece.wake_power
		for item: Array in [["vertical_fin", fin], ["horizontal_tail", tail]]:
			result[item[0] + "_force_ideal_n"] = item[1].ideal
			result[item[0] + "_force_n"] = item[1].normal_force
			result[item[0] + "_limited"] = item[1].limited
	return result


# Compact joint-stage path. The caller has checked cg/rates and the prepared
# context. Evaluate all three CPs into one scalar buffer so no per-piece
# dictionaries, packed load arrays, key-prefix strings or temporary finite
# arrays are created. Full diagnostics continue to use the reference path above.
static func _evaluate_compact_stage_prepared(model: Dictionary, cg_air: PackedFloat64Array,
		rates: PackedFloat64Array, fuselage_wake: PackedFloat64Array,
		fin_wake: PackedFloat64Array, tail_wake: PackedFloat64Array) -> Dictionary:
	var density_scale: float = 0.5 * model.rho_kg_m3
	var pieces: PackedFloat64Array = PackedFloat64Array()
	pieces.resize(27)
	for index: int in range(3):
		var rx: float
		var ry: float
		var rz: float
		var area_x: float = 0.0
		var area_y: float = 0.0
		var area_z: float = 0.0
		var lift_slope: float = 0.0
		var wake: PackedFloat64Array
		if index == 0:
			rx = model.fuselage_x_m
			ry = model.fuselage_y_m
			rz = model.fuselage_z_m
			area_x = model.fuselage_area_x_m2
			area_y = model.fuselage_area_y_m2
			area_z = model.fuselage_area_z_m2
			wake = fuselage_wake
		elif index == 1:
			rx = model.vertical_fin_x_m
			ry = model.vertical_fin_y_m
			rz = model.vertical_fin_z_m
			area_x = model.vertical_fin_area_m2
			lift_slope = model.vertical_fin_lift_curve_slope_per_rad
			wake = fin_wake
		else:
			rx = model.horizontal_tail_x_m
			ry = model.horizontal_tail_y_m
			rz = model.horizontal_tail_z_m
			area_x = model.horizontal_tail_area_m2
			lift_slope = model.horizontal_tail_lift_curve_slope_per_rad
			wake = tail_wake
		var point_x: float = cg_air[0] + rates[1] * rz - rates[2] * ry
		var point_y: float = cg_air[1] + rates[2] * rx - rates[0] * rz
		var point_z: float = cg_air[2] + rates[0] * ry - rates[1] * rx
		var ux: float = point_x - wake[0]
		var uy: float = point_y - wake[1]
		var uz: float = point_z - wake[2]
		var speed_squared: float = ux * ux + uy * uy + uz * uz
		if not is_finite(point_x) or not is_finite(point_y) or not is_finite(point_z) \
			or not is_finite(ux) or not is_finite(uy) or not is_finite(uz) or not is_finite(speed_squared):
			return {"ok": false}
		var fx: float = 0.0
		var fy: float = 0.0
		var fz: float = 0.0
		var ideal: float = 0.0
		var normal_force: float = 0.0
		if index == 0:
			var speed: float = M.sqrt_(speed_squared)
			fx = -density_scale * area_x * ux * speed
			fy = -density_scale * area_y * uy * speed
			fz = -density_scale * area_z * uz * speed
		else:
			var scale: float = density_scale * area_x
			if index == 1:
				var in_plane: float = M.sqrt_(ux * ux + uz * uz)
				ideal = -scale * (lift_slope * in_plane + absf(uy)) * uy
				var cap: float = scale * speed_squared
				if not is_finite(scale) or not is_finite(in_plane) or not is_finite(cap):
					return {"ok": false}
				fy = clampf(ideal, -cap, cap)
				normal_force = fy
			else:
				ideal = -scale * (lift_slope * absf(ux) + absf(uz)) * uz
				var cap: float = scale * (ux * ux + uz * uz)
				if not is_finite(scale) or not is_finite(cap):
					return {"ok": false}
				fz = clampf(ideal, -cap, cap)
				normal_force = fz
		var mx: float = ry * fz - rz * fy
		var my: float = rz * fx - rx * fz
		var mz: float = rx * fy - ry * fx
		var relative_power: float = fx * ux + fy * uy + fz * uz
		var body_power: float = fx * point_x + fy * point_y + fz * point_z
		var wake_power: float = fx * wake[0] + fy * wake[1] + fz * wake[2]
		if not is_finite(fx) or not is_finite(fy) or not is_finite(fz) \
			or not is_finite(ideal) or not is_finite(normal_force) \
			or not is_finite(mx) or not is_finite(my) or not is_finite(mz) \
			or not is_finite(relative_power) or not is_finite(body_power) or not is_finite(wake_power):
			return {"ok": false}
		var base: int = index * 9
		pieces[base] = fx
		pieces[base + 1] = fy
		pieces[base + 2] = fz
		pieces[base + 3] = mx
		pieces[base + 4] = my
		pieces[base + 5] = mz
		pieces[base + 6] = relative_power
		pieces[base + 7] = body_power
		pieces[base + 8] = wake_power
	var loads: PackedFloat64Array = PackedFloat64Array([
		pieces[0] + pieces[9] + pieces[18], pieces[1] + pieces[10] + pieces[19],
		pieces[2] + pieces[11] + pieces[20], pieces[3] + pieces[12] + pieces[21],
		pieces[4] + pieces[13] + pieces[22], pieces[5] + pieces[14] + pieces[23]])
	var relative_power: float = pieces[6] + pieces[15] + pieces[24]
	var body_power: float = pieces[7] + pieces[16] + pieces[25]
	var wake_power: float = pieces[8] + pieces[17] + pieces[26]
	if not _vector6(loads) or not _finite([relative_power, body_power, wake_power]):
		return {"ok": false}
	return {"ok": true, "loads": loads, "relative_power_w": relative_power,
		"body_air_power_w": body_power, "wake_power_w": wake_power}


static func _piece(model: Dictionary, prefix: String, cg_air: PackedFloat64Array,
		rates: PackedFloat64Array, wake: PackedFloat64Array, diagnostics: bool) -> Dictionary:
	var rx: float = model[prefix + "_x_m"]
	var ry: float = model[prefix + "_y_m"]
	var rz: float = model[prefix + "_z_m"]
	var point_x: float = cg_air[0] + rates[1] * rz - rates[2] * ry
	var point_y: float = cg_air[1] + rates[2] * rx - rates[0] * rz
	var point_z: float = cg_air[2] + rates[0] * ry - rates[1] * rx
	var ux: float = point_x - wake[0]
	var uy: float = point_y - wake[1]
	var uz: float = point_z - wake[2]
	var speed_squared: float = ux * ux + uy * uy + uz * uz
	if not _finite([point_x, point_y, point_z, ux, uy, uz, speed_squared]):
		return {"ok": false}
	var density_scale: float = 0.5 * model.rho_kg_m3
	var fx: float = 0.0
	var fy: float = 0.0
	var fz: float = 0.0
	var ideal: float = 0.0
	var normal_force: float = 0.0
	var limited: bool = false
	if prefix == "fuselage":
		var speed: float = M.sqrt_(speed_squared)
		fx = -density_scale * model.fuselage_area_x_m2 * ux * speed
		fy = -density_scale * model.fuselage_area_y_m2 * uy * speed
		fz = -density_scale * model.fuselage_area_z_m2 * uz * speed
	elif prefix == "vertical_fin":
		var scale: float = density_scale * model.vertical_fin_area_m2
		var in_plane: float = M.sqrt_(ux * ux + uz * uz)
		ideal = -scale * (model.vertical_fin_lift_curve_slope_per_rad * in_plane + absf(uy)) * uy
		var cap: float = scale * speed_squared
		if not _finite([scale, in_plane, cap]):
			return {"ok": false}
		fy = clampf(ideal, -cap, cap)
		normal_force = fy
		limited = fy != ideal
	else:
		var scale: float = density_scale * model.horizontal_tail_area_m2
		# Preserve the source's longitudinal |u| lift term and x/z cap;
		# lateral flow is not silently treated as longitudinal tail flow.
		ideal = -scale * (model.horizontal_tail_lift_curve_slope_per_rad * absf(ux) + absf(uz)) * uz
		var cap: float = scale * (ux * ux + uz * uz)
		if not _finite([scale, cap]):
			return {"ok": false}
		fz = clampf(ideal, -cap, cap)
		normal_force = fz
		limited = fz != ideal
	var mx: float = ry * fz - rz * fy
	var my: float = rz * fx - rx * fz
	var mz: float = rx * fy - ry * fx
	var relative_power: float = fx * ux + fy * uy + fz * uz
	var body_power: float = fx * point_x + fy * point_y + fz * point_z
	var wake_power: float = fx * wake[0] + fy * wake[1] + fz * wake[2]
	if not _finite([fx, fy, fz, ideal, normal_force, mx, my, mz, relative_power, body_power, wake_power]):
		return {"ok": false}
	var result: Dictionary = {"ok": true, "loads": PackedFloat64Array([fx, fy, fz, mx, my, mz]),
		"relative_power": relative_power, "body_power": body_power, "wake_power": wake_power}
	if diagnostics:
		result.merge({"relative_air": M.v3(ux, uy, uz), "force": M.v3(fx, fy, fz), "moment": M.v3(mx, my, mz),
			"ideal": ideal, "normal_force": normal_force, "limited": limited})
	return result


static func _parameter_vector(value: Variant) -> bool:
	if typeof(value) != TYPE_ARRAY and typeof(value) != TYPE_PACKED_FLOAT64_ARRAY:
		return false
	if value.size() != 3:
		return false
	for entry: Variant in value:
		if not _number(entry):
			return false
	return true


static func _number(value: Variant) -> bool:
	return (typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT) and is_finite(float(value))


static func _finite(values: Array) -> bool:
	for value: float in values:
		if not is_finite(value):
			return false
	return true


static func _vector(value: PackedFloat64Array) -> bool:
	return value.size() == 3 and _finite(Array(value))


static func _vector6(value: PackedFloat64Array) -> bool:
	return value.size() == 6 and _finite(Array(value))


static func _prepared(model: Dictionary) -> bool:
	if not _prepared_header(model):
		return false
	var numbers: Array = model.values()
	numbers.erase(LAW)
	for value: Variant in numbers:
		if typeof(value) != TYPE_FLOAT or not is_finite(value):
			return false
	return model.rho_kg_m3 > 0.0 and model.fuselage_area_x_m2 >= 0.0 and model.fuselage_area_y_m2 >= 0.0 \
		and model.fuselage_area_z_m2 >= 0.0 and model.vertical_fin_area_m2 >= 0.0 \
		and model.vertical_fin_lift_curve_slope_per_rad >= 0.0 and model.horizontal_tail_area_m2 >= 0.0 \
		and model.horizontal_tail_lift_curve_slope_per_rad >= 0.0


static func _prepared_header(model: Dictionary) -> bool:
	return model.is_read_only() and model.get("law") == LAW and model.size() == PREPARED_KEYS.size() \
		and model.has_all(PREPARED_KEYS)
