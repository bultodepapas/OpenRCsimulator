# DR-06a (foundation slice): three-axis quadratic airframe drag at the CG, F_k = −½·ρ·S_k·v_k·|v_k| (Heffley form,
# no angle-of-attack singularity), from estimated frontal areas. Rotor-induced body loads live in rotor.gd.
extends RefCounted

const M := preload("res://physics/math3d.gd")


static func loads(v_air: PackedFloat64Array, rho: float, airframe: Dictionary) -> PackedFloat64Array:
	var areas: PackedFloat64Array = airframe.drag_areas_m2
	return M.v3(
		-0.5 * rho * areas[0] * v_air[0] * absf(v_air[0]),
		-0.5 * rho * areas[1] * v_air[1] * absf(v_air[1]),
		-0.5 * rho * areas[2] * v_air[2] * absf(v_air[2]),
	)
