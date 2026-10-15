## RCV-water v1. Estimated open-truck displacement, not a sealed hull model.
## Memoryless float64 loads: applied before the coupled tire/friction solve.
extends RefCounted

const M := preload("res://physics/math3d.gd")
const VERSION := "openrc-rcv-environment-v1"
const DENSITY_KG_M3 := 998.0
const BODY_CELL_VOLUME_M3 := 0.00035
const WHEEL_VOLUME_M3 := 0.00030
const BODY_CELL_RADIUS_M := 0.065
const BODY_CELL_AREA_M2 := 0.009
const BODY_CD := 1.05
const WHEEL_CD := 1.10
const SPIN_DRAG_N_M_S2 := 0.00015
const WET_MAX_STEP_S := 1.0 / 480.0
const MUD_MU := 0.30
const MUD_ROLLING := 4.5
const MUD_BANK_WIDTH_M := 0.9
const WET_QUERY_MARGIN_M := 2.0


static func dry() -> Dictionary:
	return {"ok": true, "body_submersion": 0.0, "water_depth_m": 0.0,
		"buoyancy_n": 0.0, "drag_power_w": 0.0, "power_w": 0.0,
		"wheel_submersion": PackedFloat64Array([0.0, 0.0, 0.0, 0.0]),
		"wheel_water_height_m": PackedFloat64Array([0.0, 0.0, 0.0, 0.0]),
		"wheel_depth_m": PackedFloat64Array([0.0, 0.0, 0.0, 0.0]),
		"wheel_mud": PackedFloat64Array([0.0, 0.0, 0.0, 0.0])}


static func surface_is_valid(surface: Dictionary) -> bool:
	if not surface.has("wet_zone"):
		return not (surface.has("water_height_m") or surface.has("water_depth_m") or surface.has("mud_fraction"))
	if typeof(surface.wet_zone) != TYPE_BOOL:
		return false
	for key in ["water_height_m", "water_depth_m", "mud_fraction"]:
		var value: Variant = surface.get(key)
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
			return false
	return float(surface.water_depth_m) >= 0.0 and float(surface.mud_fraction) >= 0.0 \
		and float(surface.mud_fraction) <= 1.0 \
		and (surface.wet_zone or (float(surface.water_depth_m) == 0.0 and float(surface.mud_fraction) == 0.0))


## Smooth spherical-cap occupancy, h measured from the bottom (0..2r).
static func submerged_fraction(center_down: float, water_up: float, radius: float) -> float:
	var u := clampf((center_down + water_up + radius) / (2.0 * radius), 0.0, 1.0)
	return u * u * (3.0 - 2.0 * u)


static func evaluate(state: PackedFloat64Array, model: Dictionary, geometry: Dictionary,
		road: Callable, center: Dictionary) -> Dictionary:
	var result := dry()
	var rhs := PackedFloat64Array()
	rhs.resize(14)
	result["generalized_force"] = rhs
	if not surface_is_valid(center): return {"ok": false, "error": "Malformed wet road metadata"}
	result.water_depth_m = float(center.get("water_depth_m", 0.0))
	var q := M.q_normalized(PackedFloat64Array([state[6], state[7], state[8], state[9]]))
	var qc := M.q_conj(q)
	var position := PackedFloat64Array([state[0], state[1], state[2]])
	var velocity := PackedFloat64Array([state[3], state[4], state[5]])
	var rate := PackedFloat64Array([state[10], state[11], state[12]])
	var gravity := float(model.gravity_m_per_s2)
	for cell in 8:
		var wheel := cell >= 4
		var index := cell % 4
		var r: PackedFloat64Array = geometry.hub_position_body[index] if wheel else PackedFloat64Array([
			0.13 if index < 2 else -0.13, -0.08 if index % 2 == 0 else 0.08, -0.015])
		var point := M.add(position, M.q_rotate(q, r))
		var raw: Variant = road.call(point[0], point[1])
		if typeof(raw) != TYPE_DICTIONARY or not surface_is_valid(raw):
			return {"ok": false, "error": "Malformed wet road sample at vehicle cell"}
		var surface: Dictionary = raw
		var depth := float(surface.get("water_depth_m", 0.0))
		var water_up := float(surface.get("water_height_m", 0.0))
		var radius := float(model.tire_radius_m) if wheel else BODY_CELL_RADIUS_M
		var fraction := submerged_fraction(point[2], water_up, radius) if depth > 0.0 else 0.0
		if wheel:
			result.wheel_submersion[index] = fraction
			result.wheel_water_height_m[index] = water_up if depth > 0.0 else 0.0
			result.wheel_depth_m[index] = depth
			result.wheel_mud[index] = float(surface.get("mud_fraction", 0.0))
		else:
			result.body_submersion += fraction * 0.25
		if fraction == 0.0: continue
		var point_velocity: PackedFloat64Array = geometry.hub_speed_body[index] if wheel else M.add(velocity, M.cross(rate, r))
		var world_velocity := M.q_rotate(q, point_velocity)
		var area := PI * radius * radius if wheel else BODY_CELL_AREA_M2
		var cd := WHEEL_CD if wheel else BODY_CD
		var drag := M.scale(world_velocity, -0.5 * DENSITY_KG_M3 * cd * area * fraction * M.norm(world_velocity))
		var lift := DENSITY_KG_M3 * gravity * fraction * (WHEEL_VOLUME_M3 if wheel else BODY_CELL_VOLUME_M3)
		var force_world := M.add(drag, PackedFloat64Array([0.0, 0.0, -lift]))
		var force := M.q_rotate(qc, force_world)
		var moment := M.cross(r, force)
		for axis in 3:
			rhs[axis] += force[axis]
			rhs[3 + axis] += moment[axis]
		result.buoyancy_n += lift
		result.drag_power_w += M.dot(drag, world_velocity)
		result.power_w += M.dot(force, point_velocity)
		if wheel:
			rhs[6 + index] += M.dot(geometry.hub_position_derivative_body[index], force)
			var spin_axis: PackedFloat64Array = geometry.spin_axis_body[index]
			var spin := state[21 + index] + M.dot(rate, spin_axis)
			var torque := -SPIN_DRAG_N_M_S2 * fraction * absf(spin) * spin
			rhs[10 + index] += torque
			for axis in 3: rhs[3 + axis] += spin_axis[axis] * torque
			result.drag_power_w += torque * spin
			result.power_w += torque * spin
	for value in rhs:
		if not is_finite(value): return {"ok": false, "error": "Non-finite environmental load"}
	result.generalized_force = rhs
	return result if telemetry_is_valid(result) else {"ok": false, "error": "Non-finite environmental work"}


static func telemetry_is_valid(value: Variant) -> bool:
	if typeof(value) != TYPE_DICTIONARY or value.get("ok") != true: return false
	for key in ["body_submersion", "water_depth_m", "buoyancy_n", "drag_power_w", "power_w"]:
		if typeof(value.get(key)) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value[key])): return false
	if float(value.body_submersion) < 0.0 or float(value.body_submersion) > 1.0 \
			or float(value.water_depth_m) < 0.0 or float(value.buoyancy_n) < 0.0 or float(value.drag_power_w) > 0.000000001:
		return false
	for key in ["wheel_submersion", "wheel_water_height_m", "wheel_depth_m", "wheel_mud"]:
		var array: Variant = value.get(key)
		if typeof(array) != TYPE_PACKED_FLOAT64_ARRAY or array.size() != 4: return false
		for number in array:
			if not is_finite(number): return false
			if key != "wheel_water_height_m" and number < 0.0: return false
			if key in ["wheel_submersion", "wheel_mud"] and number > 1.0: return false
	return true
