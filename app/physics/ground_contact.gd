# E1: landing gear as point contacts with the flat ground (world NED, ground at down = 0).
# Each contact is a spring-damper on its compression: F_up = max(0, k·δ + c·δ̇), applied at the contact point, so
# an off-centre wheel also produces the moment r × F about the CG. Normal force only: rolling friction, steering
# and brakes are E2. Pure functions of the state (every RK4 stage sees the same law), 64-bit floats only (guarded).
# A contact above the ground adds exactly 0.0, so flight in the air is bit-identical with or without gear.
extends RefCounted

const RB := preload("res://physics/rigid_body.gd")

## Derived gear (AircraftData): { contacts: [{ name, position (body FRD about the CG, m), stiffness (N/m),
## damping (N·s/m), max_compression (m) }], reach (m: no point can touch above this CG altitude) }.


## Body loads [Fx, Fy, Fz, Mx, My, Mz] from every contact pushing on the ground, or an EMPTY array when none does
## (callers then add nothing, so even the sign of a zero in the air stays as it was).
static func loads(s: PackedFloat64Array, gear: Dictionary) -> PackedFloat64Array:
	if gear.is_empty() or -s[RB.POS + 2] > gear.reach:
		return PackedFloat64Array()
	var out := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	var touched := false
	var down := _down_row(s)
	for contact in gear.contacts:
		var r: PackedFloat64Array = contact.position
		var compression := s[RB.POS + 2] + down[0] * r[0] + down[1] * r[1] + down[2] * r[2]
		if compression <= 0.0:
			continue
		# Contact point velocity in body axes: v + ω × r; its NED down component is the compression rate.
		var vx := s[RB.VEL] + s[RB.RATE + 1] * r[2] - s[RB.RATE + 2] * r[1]
		var vy := s[RB.VEL + 1] + s[RB.RATE + 2] * r[0] - s[RB.RATE] * r[2]
		var vz := s[RB.VEL + 2] + s[RB.RATE] * r[1] - s[RB.RATE + 1] * r[0]
		var rate := down[0] * vx + down[1] * vy + down[2] * vz
		var f_up: float = contact.stiffness * compression + contact.damping * rate
		if f_up <= 0.0:
			continue # a damper never pulls the wheel into the ground
		# Force (0, 0, −f_up) in NED is −f_up × (third row of R) in body axes.
		var fx := -f_up * down[0]
		var fy := -f_up * down[1]
		var fz := -f_up * down[2]
		out[0] += fx
		out[1] += fy
		out[2] += fz
		out[3] += r[1] * fz - r[2] * fy
		out[4] += r[2] * fx - r[0] * fz
		out[5] += r[0] * fy - r[1] * fx
		touched = true
	return out if touched else PackedFloat64Array()


## Compression of every contact (m, ≤ 0 when above the ground), in the order of gear.contacts.
static func compressions(s: PackedFloat64Array, gear: Dictionary) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	if gear.is_empty():
		return out
	var down := _down_row(s)
	for contact in gear.contacts:
		var r: PackedFloat64Array = contact.position
		out.append(s[RB.POS + 2] + down[0] * r[0] + down[1] * r[1] + down[2] * r[2])
	return out


## True when any contact is pushed past its travel: the gear has collapsed (a crash, like any other hull point).
static func collapsed(s: PackedFloat64Array, gear: Dictionary) -> bool:
	if gear.is_empty() or -s[RB.POS + 2] > gear.reach:
		return false
	var c := compressions(s, gear)
	for i in c.size():
		if c[i] > gear.contacts[i].max_compression:
			return true
	return false


## Potential energy stored in the springs (J), for energy checks.
static func spring_energy(s: PackedFloat64Array, gear: Dictionary) -> float:
	var e := 0.0
	var c := compressions(s, gear)
	for i in c.size():
		if c[i] > 0.0:
			e += 0.5 * gear.contacts[i].stiffness * c[i] * c[i]
	return e


## Third row of the body→NED rotation matrix: the NED down component of a body vector b is down·b.
static func _down_row(s: PackedFloat64Array) -> PackedFloat64Array:
	var w := s[RB.ATT]
	var x := s[RB.ATT + 1]
	var y := s[RB.ATT + 2]
	var z := s[RB.ATT + 3]
	return PackedFloat64Array([2.0 * (x * z - w * y), 2.0 * (y * z + w * x), 1.0 - 2.0 * (x * x + y * y)])
