# E1: landing gear as point contacts with the flat ground (world NED, ground at down = 0).
# Each contact is a spring-damper on its compression: F_up = max(0, k·δ + c·δ̇), applied at the contact point, so
# an off-centre wheel also produces the moment r × F about the CG.
# E2: tangential tyre forces in the ground plane, along each wheel's heading projected on the ground (the nose wheel
# turned by the steering angle). Rolling resistance F_roll = −C_rr·N·sat(v_long / v_creep); side force from the
# slip angle, linear up to the peak slip angle and saturated at μ·N: F_side = −μ·N·sat(tan(slip) / tan(α_peak)) with
# tan(slip) = v_lat / max(|v_long|, SLIP_FLOOR); both inside the friction circle |F| ≤ μ·N. Each opposes its own
# velocity component, so friction never adds energy. Brakes: none (brakes off).
# E3a: the surface under each wheel (runway, mown, rough) scales μ and C_rr (physics/ground_surfaces.gd).
# Pure functions of the state (every RK4 stage sees the same law), 64-bit floats only (guarded).
# A contact above the ground adds exactly 0.0, so flight in the air is bit-identical with or without gear.
extends RefCounted

const M := preload("res://physics/math3d.gd")

const RB := preload("res://physics/rigid_body.gd")

## Below this wheel rolling speed (m/s) the slip angle is measured against it instead of |v_long|: the side force
## becomes a stiff damper, F = −(μ·N / (tan α_peak · SLIP_FLOOR))·v_lat, instead of dividing by zero at rest. Summed
## over the wheels its rate is λ = μ·g / (tan α_peak · SLIP_FLOOR) for any airplane (ΣN = m·g); the loader requires
## λ·dt ≤ SIDE_LAMBDA_DT_MAX so RK4 resolves it. Numerical regularisation, not a tyre property.
const SLIP_FLOOR := 1.0
## Rolling resistance reaches its full C_rr·N at this rolling speed (m/s); linear below it, so a wheel at rest feels
## no force (no chatter about zero). The price: a steady push F below C_rr·N is not held but creeps at
## v_creep·F/(C_rr·N) (≤ 1 cm/s); true stiction needs state (an anchor per wheel), not a pure law.
const ROLL_CREEP := 0.01
## E3a: above C_rr 0.1 the creep speed grows with C_rr (ROLL_CREEP_PER_CRR · C_rr), so the rolling resistance's
## low-speed rate C_rr·g / v_creep never exceeds g / ROLL_CREEP_PER_CRR = 98 /s (λ·dt 0.41 at 240 Hz) on any
## surface. Numerical, like SLIP_FLOOR. At C_rr 0.3 (rough grass) the force is full above 0.03 m/s.
const ROLL_CREEP_PER_CRR := 0.1
## Floats per surface in the flat table built by physics/ground_surfaces.gd: north_min, north_max, east_min,
## east_max, friction_factor, rolling_factor; the last block is a catch-all (±INF).
const SURFACE_STRIDE := 6
## Upper bound for the side force's damping rate times the tick (see SLIP_FLOOR). RK4's real-axis limit is 2.78;
## 0.5 keeps the per-tick error of the decay below 3·10⁻⁴.
const SIDE_LAMBDA_DT_MAX := 0.5

## Derived gear (AircraftData): { contacts: [{ name, position (body FRD about the CG, m), stiffness (N/m),
## damping (N·s/m), max_compression (m), max_steering (rad, 0 = fixed wheel) }], reach (m: no point can touch above
## this CG altitude), rolling_resistance (C_rr), side_friction (μ), tan_peak_slip (tan α_peak) }.


## Body loads [Fx, Fy, Fz, Mx, My, Mz] from every contact pushing on the ground, or an EMPTY array when none does
## (callers then add nothing, so even the sign of a zero in the air stays as it was).
## steer: the steering command (−1…1, +1 = nose wheel turned right: the rudder servo's position); each contact turns
## by steer × its max_steering. surfaces: the field's flat surface table (ground_surfaces.gd); empty = dry pavement
## everywhere (factors 1, the gear's own coefficients).
static func loads(s: PackedFloat64Array, gear: Dictionary, steer := 0.0, surfaces := PackedFloat64Array()) -> PackedFloat64Array:
	if gear.is_empty() or -s[RB.POS + 2] > gear.reach:
		return PackedFloat64Array()
	var out := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	var touched := false
	var rows := _rows(s)
	var north: PackedFloat64Array = rows[0]
	var east: PackedFloat64Array = rows[1]
	var down: PackedFloat64Array = rows[2]
	var mu: float = gear.get("side_friction", 0.0) # 0 (or absent): normal force only, exactly E1
	var c_rr: float = gear.get("rolling_resistance", 0.0)
	var tan_peak: float = gear.get("tan_peak_slip", 1.0)
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
		# E2: tyre forces in the ground plane. Wheel heading in body axes (cos δ, sin δ, 0), projected on the ground.
		var delta: float = steer * float(contact.get("max_steering", 0.0))
		var hx := M.cos_(delta)
		var hy := M.sin_(delta)
		var hn := north[0] * hx + north[1] * hy
		var he := east[0] * hx + east[1] * hy
		var h_len := M.sqrt_(hn * hn + he * he)
		var f_n := 0.0
		var f_e := 0.0
		if mu > 0.0 and h_len > 1e-6: # a wheel standing on its edge (heading vertical) gets the normal force only
			hn /= h_len
			he /= h_len
			var vn := north[0] * vx + north[1] * vy + north[2] * vz
			var ve := east[0] * vx + east[1] * vy + east[2] * vz
			var v_long := vn * hn + ve * he
			var v_lat := -vn * he + ve * hn # lateral axis: heading turned 90° right, (−he, hn)
			var mu_n := mu * f_up
			var c := c_rr
			if not surfaces.is_empty():
				var i := surface_at(surfaces, s[RB.POS] + north[0] * r[0] + north[1] * r[1] + north[2] * r[2],
					s[RB.POS + 1] + east[0] * r[0] + east[1] * r[1] + east[2] * r[2])
				mu_n *= surfaces[i + 4]
				c *= surfaces[i + 5]
			var f_long := -c * f_up * clampf(v_long / maxf(ROLL_CREEP, c * ROLL_CREEP_PER_CRR), -1.0, 1.0)
			var f_lat := -mu_n * clampf(v_lat / (tan_peak * maxf(absf(v_long), SLIP_FLOOR)), -1.0, 1.0)
			var f_t := M.sqrt_(f_long * f_long + f_lat * f_lat)
			if f_t > mu_n: # friction circle
				f_long *= mu_n / f_t
				f_lat *= mu_n / f_t
			f_n = f_long * hn - f_lat * he
			f_e = f_long * he + f_lat * hn
		# NED force (f_n, f_e, −f_up) in body axes: Rᵀ·F = f_n·row₀ + f_e·row₁ − f_up·row₂.
		var fx := f_n * north[0] + f_e * east[0] - f_up * down[0]
		var fy := f_n * north[1] + f_e * east[1] - f_up * down[1]
		var fz := f_n * north[2] + f_e * east[2] - f_up * down[2]
		out[0] += fx
		out[1] += fy
		out[2] += fz
		out[3] += r[1] * fz - r[2] * fy
		out[4] += r[2] * fx - r[0] * fz
		out[5] += r[0] * fy - r[1] * fx
		touched = true
	return out if touched else PackedFloat64Array()


## Offset in a flat surface table of the surface at (north, east): the first block containing the point (edges
## included), else the last (catch-all) block. Its factors are table[i + 4] (friction) and table[i + 5] (rolling).
static func surface_at(table: PackedFloat64Array, north: float, east: float) -> int:
	var i := 0
	while i + SURFACE_STRIDE < table.size():
		if north >= table[i] and north <= table[i + 1] and east >= table[i + 2] and east <= table[i + 3]:
			return i
		i += SURFACE_STRIDE
	return i


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


## The three rows of the body→NED rotation matrix: the NED components of a body vector b are row_i·b.
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


## Third row of the body→NED rotation matrix: the NED down component of a body vector b is down·b.
static func _down_row(s: PackedFloat64Array) -> PackedFloat64Array:
	var w := s[RB.ATT]
	var x := s[RB.ATT + 1]
	var y := s[RB.ATT + 2]
	var z := s[RB.ATT + 3]
	return PackedFloat64Array([2.0 * (x * z - w * y), 2.0 * (y * z + w * x), 1.0 - 2.0 * (x * x + y * y)])
