# Frozen pre-DATA-2 exhaustive grid solve; verification oracle, not a flight model.
extends RefCounted

const Aero = preload("res://physics/aero.gd")
const M = preload("res://physics/math3d.gd")

static func _solve_stall_start(aero: Dictionary, cd90: float, width: float, target: float, sign: float) -> float:
	var lo := 0.0
	var hi := (target - float(aero.CL0)) / float(aero.CLa) * sign # where the linear lift alone reaches the target
	for i in 60:
		var mid := 0.5 * (lo + hi)
		if _blend_extreme(aero, cd90, width, mid, sign) * sign < target * sign:
			lo = mid
		else:
			hi = mid
	return 0.5 * (lo + hi)


static func _blend_extreme(aero: Dictionary, cd90: float, width: float, start: float, sign: float) -> float:
	var env := { a1 = start, a2 = start + width, n1 = start, n2 = start + width, b1 = 1.0, b2 = 2.0, CD90 = cd90 }
	var best := 0.0
	for k in 801: # 0.01·width steps across the blend, plus its edges
		var alpha := sign * (start + width * (float(k) / 800.0) * 1.25)
		var cl := Aero.lift_alpha(alpha, aero, env)
		if cl * sign > best * sign:
			best = cl
	return best

