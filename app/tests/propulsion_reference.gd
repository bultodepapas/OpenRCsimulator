# H14: frozen propulsion-load oracle, before scalar allocation removal. Verbatim copies of Propulsion.loads and every
# helper it reaches at 77cdae9, so later edits to propulsion.gd cannot move the oracle. Turbines delegate to the live
# Turbine.loads, which H14 does not change.
extends RefCounted

const M := preload("res://physics/math3d.gd")
const Turbine := preload("res://physics/turbine.gd")

const STOPPED_RPM := 1.0
const CT_FLOOR := -0.1
const CP_FLOOR := 0.0


static func loads(v_air: PackedFloat64Array, rpm: float, prop: Dictionary, rho: float) -> PackedFloat64Array:
	if Turbine.is_turbine(prop): # AV-05
		return Turbine.loads(v_air, rpm, prop, rho)
	if rpm < STOPPED_RPM:
		return PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	var tq := thrust_torque(v_air, rpm, prop, rho)
	var thrust := tq[0]
	var torque := tq[1]
	var r: PackedFloat64Array = prop.offset # [x_aft, y_right, z_up] from the CG
	var at := M.v3(-r[0], r[1], -r[2])
	if not prop.has("axis"):
		var arm := M.cross(at, M.v3(thrust, 0.0, 0.0))
		return PackedFloat64Array([thrust, 0.0, 0.0, -torque + arm[0], arm[1], arm[2]])
	var ax: PackedFloat64Array = prop.axis
	var force := M.add(M.scale(ax, thrust), normal_force(v_air, rpm, prop, rho))
	var moment := M.add(M.sub(M.cross(at, force), M.scale(ax, torque)), pfactor_moment(v_air, rpm, prop, rho))
	return PackedFloat64Array([force[0], force[1], force[2], moment[0], moment[1], moment[2]])


static func thrust_torque(v_air: PackedFloat64Array, rpm: float, prop: Dictionary, rho: float) -> PackedFloat64Array:
	if rpm < STOPPED_RPM:
		return PackedFloat64Array([0.0, 0.0, 0.0])
	var D: float = prop.diameter
	var n := rpm / 60.0
	var u := v_air[0] if not prop.has("axis") else M.dot(v_air, prop.axis)
	var J := maxf(u, 0.0) / (n * D)
	var thrust := coefficient(prop.ct, J, CT_FLOOR) * rho * n * n * M.pow_(D, 4)
	var power := coefficient(prop.cp, J, _cp_floor(prop)) * rho * n * n * n * M.pow_(D, 5)
	return PackedFloat64Array([thrust, power / (TAU * n), J])


static func normal_force(v_air: PackedFloat64Array, rpm: float, prop: Dictionary, rho: float) -> PackedFloat64Array:
	return _crossflow(v_air, rpm, prop, rho, "normal_force", 4)


static func pfactor_moment(v_air: PackedFloat64Array, rpm: float, prop: Dictionary, rho: float) -> PackedFloat64Array:
	return _crossflow(v_air, rpm, prop, rho, "pfactor_moment", 5)


static func _crossflow(v_air: PackedFloat64Array, rpm: float, prop: Dictionary, rho: float, key: String,
		power: int) -> PackedFloat64Array:
	var table: PackedFloat64Array = prop.get(key, PackedFloat64Array())
	var speed := M.sqrt_(M.dot(v_air, v_air))
	if table.is_empty() or rpm < STOPPED_RPM or speed < 1e-6:
		return M.v3(0.0, 0.0, 0.0)
	var ax := axis(prop)
	var along := M.dot(v_air, ax)
	var cross := M.sub(v_air, M.scale(ax, along))
	var D: float = prop.diameter
	var n := rpm / 60.0
	var J := maxf(along, 0.0) / (n * D)
	return M.scale(cross, -coefficient(table, J, 0.0) * rho * n * n * M.pow_(D, power) / speed)


static func coefficient(table: PackedFloat64Array, J: float, floor_value: float) -> float:
	var n := table.size() / 2
	if J <= table[0]:
		return table[1]
	for i in range(1, n):
		if J <= table[2 * i]:
			var j0 := table[2 * i - 2]
			var j1 := table[2 * i]
			return lerpf(table[2 * i - 1], table[2 * i + 1], (J - j0) / (j1 - j0))
	var ja := table[2 * n - 4]
	var jb := table[2 * n - 2]
	var slope := (table[2 * n - 1] - table[2 * n - 3]) / (jb - ja)
	return maxf(floor_value, table[2 * n - 1] + slope * (J - jb))


static func axis(prop: Dictionary) -> PackedFloat64Array:
	return prop.get("axis", PackedFloat64Array([1.0, 0.0, 0.0]))


static func _cp_floor(prop: Dictionary) -> float:
	return minf(CP_FLOOR, float(prop.get("cp_min", 0.0)))
