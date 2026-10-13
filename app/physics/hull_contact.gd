## E3d1: soft crash-hull contacts. Each hull point touching the flat field becomes a spring-damper along the ground
## normal with regularized Coulomb friction in the ground plane, so a wingtip brush, a tail touch or a belly slide
## no longer ends the flight. FlightSession decides when a contact is a crash (terminal()). Pure float64.
## Stiffness and damping are numerical contact choices (estimates), not measured airframe or turf compliance.
extends RefCounted

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const EffectiveMass := preload("res://physics/effective_mass.gd")

## Contact natural frequency against each point's smallest effective mass: ω·dt = 0.25 at 240 Hz, so no point is
## stiffer than this for RK4 in any attitude. A belly carrying the whole airplane sags g/ω² ≈ 2.7 mm.
const OMEGA_RAD_S := 60.0
const ZETA := 0.7
## Damping grows from zero over this compression so the force does not jump at touchdown (cf. E1b).
const DAMPING_ONSET_M := 0.004
## Airframe on turf or pavement; research 04 §6 estimates 0.3–0.5.
const FRICTION_MU := 0.4
## Below this ground-plane slip speed friction scales linearly (no chatter at rest).
const SLIP_REGULARIZATION_MPS := 0.2
## A contact is a crash when the struck point's normal energy per kilogram of airplane reaches the CR-08b C2 cut
## (surface transfer 1, conservative), or when any point is pushed this deep (a slow crush).
const TERMINAL_J_PER_KG := 2.5
const CRASH_DEPTH_M := 0.08

const _DIRECTIONS := [
	[1, 0, 0], [-1, 0, 0], [0, 1, 0], [0, -1, 0], [0, 0, 1], [0, 0, -1],
	[1, 1, 0], [1, -1, 0], [-1, 1, 0], [-1, -1, 0], [1, 0, 1], [1, 0, -1], [-1, 0, 1], [-1, 0, -1],
	[0, 1, 1], [0, 1, -1], [0, -1, 1], [0, -1, -1],
	[1, 1, 1], [1, 1, -1], [1, -1, 1], [1, -1, -1], [-1, 1, 1], [-1, 1, -1], [-1, -1, 1], [-1, -1, -1],
]


## Per-point stiffness/damping for `hull` (body FRD about the CG, flattened) from the smallest effective mass over
## 26 body directions. Returns {} when the inputs cannot support a contact (callers then add no hull forces).
static func prepare(hull: PackedFloat64Array, mass: float, inertia: PackedFloat64Array) -> Dictionary:
	if hull.is_empty() or hull.size() % 3 != 0 or not is_finite(mass) or mass <= 0.0:
		return {}
	var identity := PackedFloat64Array([1.0, 0.0, 0.0, 0.0])
	var k := PackedFloat64Array()
	var c := PackedFloat64Array()
	var reach := 0.0
	for i in range(0, hull.size(), 3):
		var r := hull.slice(i, i + 3)
		var smallest := mass
		for d: Array in _DIRECTIONS:
			var m_eff := EffectiveMass.at_point(identity, r, PackedFloat64Array([float(d[0]), float(d[1]), float(d[2])]), mass, inertia)
			if m_eff <= 0.0:
				return {}
			smallest = minf(smallest, m_eff)
		k.append(smallest * OMEGA_RAD_S * OMEGA_RAD_S)
		c.append(2.0 * ZETA * smallest * OMEGA_RAD_S)
		reach = maxf(reach, M.norm(r))
	return {points = hull.duplicate(), stiffness = k, damping = c, reach = reach, mass = mass, inertia = inertia.duplicate()}


## Body loads [Fx, Fy, Fz, Mx, My, Mz] from every touching hull point, or EMPTY when none touches (callers add
## nothing, so flight away from the ground is bit-identical).
static func loads(s: PackedFloat64Array, prepared: Dictionary) -> PackedFloat64Array:
	if prepared.is_empty() or -s[RB.POS + 2] > float(prepared.reach):
		return PackedFloat64Array()
	var hull: PackedFloat64Array = prepared.points
	var rows := _rows(s)
	var north: PackedFloat64Array = rows[0]
	var east: PackedFloat64Array = rows[1]
	var down: PackedFloat64Array = rows[2]
	var out := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	var touched := false
	for i in range(0, hull.size(), 3):
		var rx := hull[i]
		var ry := hull[i + 1]
		var rz := hull[i + 2]
		var depth := s[RB.POS + 2] + down[0] * rx + down[1] * ry + down[2] * rz
		if depth <= 0.0:
			continue
		var vx := s[RB.VEL] + s[RB.RATE + 1] * rz - s[RB.RATE + 2] * ry
		var vy := s[RB.VEL + 1] + s[RB.RATE + 2] * rx - s[RB.RATE] * rz
		var vz := s[RB.VEL + 2] + s[RB.RATE] * ry - s[RB.RATE + 1] * rx
		var rate := down[0] * vx + down[1] * vy + down[2] * vz
		var point := i / 3
		var onset := minf(depth / DAMPING_ONSET_M, 1.0)
		var f_up: float = prepared.stiffness[point] * depth + prepared.damping[point] * onset * rate
		if f_up <= 0.0:
			continue # a damper never pulls the airframe into the ground
		var vn := north[0] * vx + north[1] * vy + north[2] * vz
		var ve := east[0] * vx + east[1] * vy + east[2] * vz
		var slip := M.sqrt_(vn * vn + ve * ve)
		var scale := FRICTION_MU * f_up / maxf(slip, SLIP_REGULARIZATION_MPS)
		var f_n := -scale * vn
		var f_e := -scale * ve
		# NED force (f_n, f_e, −f_up) in body axes.
		var fx := f_n * north[0] + f_e * east[0] - f_up * down[0]
		var fy := f_n * north[1] + f_e * east[1] - f_up * down[1]
		var fz := f_n * north[2] + f_e * east[2] - f_up * down[2]
		out[0] += fx
		out[1] += fy
		out[2] += fz
		out[3] += ry * fz - rz * fy
		out[4] += rz * fx - rx * fz
		out[5] += rx * fy - ry * fx
		touched = true
	return out if touched else PackedFloat64Array()


## The hull point that makes the step previous → s a crash, or -1. Graded on the point's state in `previous` (just
## before it touched): a point newly below the ground crashes when transfer-free ½·m_eff·v_n²/m reaches
## TERMINAL_J_PER_KG; any point deeper than CRASH_DEPTH_M crashes too. Returns {index, rule, specific_j_per_kg,
## normal_speed_mps, depth_m}.
static func terminal(previous: PackedFloat64Array, s: PackedFloat64Array, prepared: Dictionary) -> Dictionary:
	var none := {index = -1, rule = "", specific_j_per_kg = 0.0, normal_speed_mps = 0.0, depth_m = 0.0}
	if prepared.is_empty() or previous.size() != s.size():
		return none
	var hull: PackedFloat64Array = prepared.points
	var down_now: PackedFloat64Array = _down_row(s)
	var down_before: PackedFloat64Array = _down_row(previous)
	var q_before := RB._att(previous)
	var worst := none.duplicate()
	for i in range(0, hull.size(), 3):
		var r := hull.slice(i, i + 3)
		var depth := s[RB.POS + 2] + down_now[0] * r[0] + down_now[1] * r[1] + down_now[2] * r[2]
		if depth <= 0.0:
			continue
		if depth > CRASH_DEPTH_M:
			return {index = i / 3, rule = "depth", specific_j_per_kg = 0.0, normal_speed_mps = 0.0, depth_m = depth}
		var depth_before := previous[RB.POS + 2] + down_before[0] * r[0] + down_before[1] * r[1] + down_before[2] * r[2]
		if depth_before > 0.0:
			continue # already in contact: a resting or sliding point is not a new impact
		var v_ned := M.q_rotate(q_before, M.add(RB._slice3(previous, RB.VEL), M.cross(RB._slice3(previous, RB.RATE), r)))
		var v_n := maxf(0.0, v_ned[2])
		var m_eff := EffectiveMass.at_point(q_before, r, PackedFloat64Array([0.0, 0.0, -1.0]), float(prepared.mass), prepared.inertia)
		if m_eff <= 0.0:
			m_eff = float(prepared.mass)
		var specific := 0.5 * m_eff * v_n * v_n / float(prepared.mass)
		if specific >= TERMINAL_J_PER_KG and specific > float(worst.specific_j_per_kg):
			worst = {index = i / 3, rule = "impact", specific_j_per_kg = specific, normal_speed_mps = v_n, depth_m = depth}
	return worst


static func _rows(s: PackedFloat64Array) -> Array:
	var w := s[RB.ATT]
	var x := s[RB.ATT + 1]
	var y := s[RB.ATT + 2]
	var z := s[RB.ATT + 3]
	return [
		PackedFloat64Array([1.0 - 2.0 * (y * y + z * z), 2.0 * (x * y - w * z), 2.0 * (x * z + w * y)]),
		PackedFloat64Array([2.0 * (x * y + w * z), 1.0 - 2.0 * (x * x + z * z), 2.0 * (y * z - w * x)]),
		_down_row(s),
	]


static func _down_row(s: PackedFloat64Array) -> PackedFloat64Array:
	var w := s[RB.ATT]
	var x := s[RB.ATT + 1]
	var y := s[RB.ATT + 2]
	var z := s[RB.ATT + 3]
	return PackedFloat64Array([2.0 * (x * z - w * y), 2.0 * (y * z + w * x), 1.0 - 2.0 * (x * x + y * y)])
