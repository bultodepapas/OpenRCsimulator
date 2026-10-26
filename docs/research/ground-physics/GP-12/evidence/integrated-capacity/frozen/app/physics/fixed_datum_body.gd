## FUEL-04: rigid-body derivative of a finite-resource vehicle whose state is referenced to a fixed body datum O
## (the CG of its authored state) while its mass, CG and inertia change. Shared by every finite-fuel law.
## Co-moving efflux: departing fuel leaves with the velocity of the body point it leaves from, so it adds no
## thrust-like reaction, no jet damping and no dm/dt or dI/dt term; adding -İω would create spin-up.
## Moved verbatim from the glow FuelMass (NITRO-02); verified by test_glow_flight_physics and
## test_fuel_mass_reference (momentum of body plus ejected fuel is conserved).
extends RefCounted

const M := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-capacity-production/review-v1/frozen/app/physics/math3d.gd")
const RB := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-capacity-production/review-v1/frozen/app/physics/rigid_body.gd")
const Inventory := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-capacity-production/review-v1/frozen/app/physics/mass_inventory.gd")

const LAW := "fixed-datum-co-moving-efflux-v1"
## Same nondegenerate raw-stage floor as Simulation.MIN_QUATERNION_NORM_SQ.
## Kept here to avoid a physics->Simulation preload cycle; RK stages are not unit quaternions.
const MIN_STAGE_QUATERNION_NORM_SQ := 1e-24


## Convert a derivative evaluated for CM acceleration into the fixed datum's acceleration.
## `properties` is one MassInventory.evaluate_reference sample {mass_kg, cg_body_m, inertia, inverse}.
static func derivative(s: PackedFloat64Array, properties: Dictionary, force: PackedFloat64Array,
		moment_cm: PackedFloat64Array, gravity: float, rotor: PackedFloat64Array) -> PackedFloat64Array:
	var out: PackedFloat64Array = RB.derivative(s, properties.mass_kg, properties.inertia, properties.inverse,
		force, moment_cm, gravity, rotor)
	var w: PackedFloat64Array = s.slice(RB.RATE, RB.RATE+3)
	var alpha: PackedFloat64Array = out.slice(RB.RATE, RB.RATE+3)
	var correction: PackedFloat64Array = M.add(M.cross(alpha, properties.cg_body_m), M.cross(w, M.cross(w, properties.cg_body_m)))
	for i in 3: out[RB.VEL+i] -= correction[i]
	return out


## Compose an already coupled FINAL body angular acceleration with the same
## co-moving-efflux datum law. The caller transfers the external moment O->CG
## once before its angular solve; this helper neither transfers moments nor
## adds rotor reaction, fuel I_dot, changing-CG velocity or resource flux terms.
## Empty means malformed/nonfinite input or derivative; no partial result escapes.
static func derivative_with_angular_acceleration(s: PackedFloat64Array, properties: Dictionary,
		force_body: PackedFloat64Array, gravity: float, alpha_body: PackedFloat64Array) -> PackedFloat64Array:
	if not _finite_shape(s, RB.SIZE) or not _finite_shape(force_body, 3) or not _finite_shape(alpha_body, 3) \
		or not is_finite(gravity) or not _coupled_properties_valid(properties):
		return PackedFloat64Array()
	var q := s.slice(RB.ATT, RB.ATT + 4)
	var norm_sq: float = q[0] * q[0] + q[1] * q[1] + q[2] * q[2] + q[3] * q[3]
	if not is_finite(norm_sq) or norm_sq <= MIN_STAGE_QUATERNION_NORM_SQ:
		return PackedFloat64Array()
	# Ground geometry uses orthonormal rotations at an RK stage. Match that local
	# extension for position/gravity without projecting the ODE's raw quaternion.
	var rotation_state := s
	if norm_sq != 1.0:
		rotation_state = s.duplicate()
		var inverse_norm := 1.0 / M.sqrt_(norm_sq)
		for i in 4: rotation_state[RB.ATT + i] = q[i] * inverse_norm
	# Start from CM translation, never the old derivative's already corrected datum.
	var out := RB.derivative(rotation_state, properties.mass_kg, properties.inertia, properties.inverse,
		force_body, PackedFloat64Array([0.0, 0.0, 0.0]), gravity)
	# Verbatim RB.derivative quaternion arithmetic, evaluated on RAW stage q.
	var w := s.slice(RB.RATE, RB.RATE + 3)
	out[RB.ATT] = (q[0] * 0.0 - q[1] * w[0] - q[2] * w[1] - q[3] * w[2]) * 0.5
	out[RB.ATT + 1] = (q[0] * w[0] + q[1] * 0.0 + q[2] * w[2] - q[3] * w[1]) * 0.5
	out[RB.ATT + 2] = (q[0] * w[1] - q[1] * w[2] + q[2] * 0.0 + q[3] * w[0]) * 0.5
	out[RB.ATT + 3] = (q[0] * w[2] + q[1] * w[1] - q[2] * w[0] + q[3] * 0.0) * 0.5
	for i in 3: out[RB.RATE + i] = alpha_body[i]
	var correction := M.add(M.cross(alpha_body, properties.cg_body_m), M.cross(w, M.cross(w, properties.cg_body_m)))
	for i in 3: out[RB.VEL + i] -= correction[i]
	return out if _finite_shape(out, RB.SIZE) else PackedFloat64Array()


static func _coupled_properties_valid(properties: Dictionary) -> bool:
	if not properties.has_all(["mass_kg", "inertia", "inverse", "cg_body_m"]) \
		or typeof(properties.mass_kg) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(properties.mass_kg)) \
		or float(properties.mass_kg) <= 0.0 or not Inventory.is_physical_tensor(properties.inertia) \
		or not _finite_shape(properties.inverse, 6) or not _finite_shape(properties.cg_body_m, 3) \
		or (properties.has("ok") and properties.ok != true):
		return false
	# The sample owner computes the inverse; verify its tensor pairing without
	# entering RB.inertia_inverse's singular-tensor assertion or duplicating inventory.
	for column in 3:
		var basis_column := PackedFloat64Array([0.0, 0.0, 0.0])
		basis_column[column] = 1.0
		var product := RB.inertia_mul(properties.inertia, RB.inertia_mul(properties.inverse, basis_column))
		for row in 3:
			if not is_finite(product[row]) or absf(product[row] - basis_column[row]) > 1.0e-8:
				return false
	return true


static func _finite_shape(value: Variant, count: int) -> bool:
	if typeof(value) != TYPE_PACKED_FLOAT64_ARRAY or value.size() != count: return false
	for number: float in value:
		if not is_finite(number): return false
	return true
