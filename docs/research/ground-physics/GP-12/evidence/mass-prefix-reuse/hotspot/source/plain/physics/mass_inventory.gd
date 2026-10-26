## Geometry-only mass inventory for quantities expressed about one fixed body datum.
## Resource shapes stay fixed as their remaining mass scales; this is an explicit distribution assumption.
extends RefCounted

const RB := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-hotspot-review/plain/physics/rigid_body.gd")
const M := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-hotspot-review/plain/physics/math3d.gd")

const LAW := "fixed-datum-fixed-shape-mass-inventory-geometry-v1"
const REFERENCE_LAW := "fixed-datum-reference-state-resources-v1"
const RESOURCE_DISTRIBUTION := "fixed_geometry_uniform_density_v1"
const PSD_ROUNDING_TOLERANCE := 1.0e-12
const MIN_NORMAL_FLOAT64 := M.MIN_NORMAL_FLOAT64


## Parallel-axis tensor per kilogram in [Jxx, Jyy, Jzz, Jxy, Jxz, Jyz] order.
static func parallel_axis_per_kg(center_body_m: PackedFloat64Array) -> PackedFloat64Array:
	if not _valid_vec3(center_body_m):
		return PackedFloat64Array()
	var x: float = center_body_m[0]
	var y: float = center_body_m[1]
	var z: float = center_body_m[2]
	return PackedFloat64Array([y * y + z * z, x * x + z * z, x * x + y * y,
		-x * y, -x * z, -y * z])


## Rectangular uniform-density component tensor per kilogram, about its center and then the fixed datum.
## This preserves the arithmetic/order used by the historical Glow helper.
static func rectangular_box_per_kg(center_body_m: PackedFloat64Array,
		size_body_m: PackedFloat64Array) -> PackedFloat64Array:
	if not _valid_vec3(center_body_m) or not _valid_vec3(size_body_m):
		return PackedFloat64Array()
	for value in size_body_m:
		if value < 0.0:
			return PackedFloat64Array()
	var x: float = center_body_m[0]
	var y: float = center_body_m[1]
	var z: float = center_body_m[2]
	return PackedFloat64Array([(size_body_m[1] * size_body_m[1] + size_body_m[2] * size_body_m[2]) / 12.0 + y * y + z * z,
		(size_body_m[0] * size_body_m[0] + size_body_m[2] * size_body_m[2]) / 12.0 + x * x + z * z,
		(size_body_m[0] * size_body_m[0] + size_body_m[1] * size_body_m[1]) / 12.0 + x * x + y * y,
		-x * y, -x * z, -y * z])


## Public tensor predicate for consumers that receive one validated mass-properties sample and need to
## verify a derived tensor without reimplementing the physical second-moment constraints.
static func is_physical_tensor(tensor: Variant) -> bool:
	return _valid_physical_tensor(tensor)


## Prepare immutable-by-convention geometry. Dry entries have id, mass_kg, center_body_m,
## and inertia_centroid_kgm2. Resource entries have id, capacity_mass_kg, center_body_m,
## inertia_centroid_at_capacity_kgm2, and distribution_model. Resource tensors are scaled
## linearly with remaining mass under RESOURCE_DISTRIBUTION; no flux law is implied.
static func prepare(reference_datum_id: String, dry_components: Array, resources: Array) -> Dictionary:
	if reference_datum_id.strip_edges().is_empty():
		return _failure("reference datum id must be nonempty")
	var ids: Dictionary = {}
	var dry: Array[Dictionary] = []
	for raw: Variant in dry_components:
		if not raw is Dictionary:
			return _failure("dry component must be a dictionary")
		var normalized: Dictionary = _normalize_component(raw, ids)
		if not normalized.ok:
			return normalized
		dry.append(normalized.component)
	dry.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.id) < String(b.id))

	var prepared_resources: Array[Dictionary] = []
	for raw: Variant in resources:
		if not raw is Dictionary:
			return _failure("resource must be a dictionary")
		var normalized: Dictionary = _normalize_resource(raw, ids)
		if not normalized.ok:
			return normalized
		prepared_resources.append(normalized.resource)
	prepared_resources.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.id) < String(b.id))

	if dry.is_empty() and prepared_resources.is_empty():
		return _failure("inventory must contain at least one dry component or resource")
	var dry_mass: float = 0.0
	var dry_first_moment := PackedFloat64Array([0.0, 0.0, 0.0])
	var dry_inertia_datum := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	for component: Dictionary in dry:
		var component_mass: float = component.mass_kg
		dry_mass += component_mass
		_add_scaled3(dry_first_moment, component.center_body_m, component_mass)
		var offset_tensor: PackedFloat64Array = parallel_axis_per_kg(component.center_body_m)
		for i: int in 6:
			dry_inertia_datum[i] += component.inertia_centroid_kgm2[i] + component_mass * offset_tensor[i]
	if not is_finite(dry_mass) or not _finite_array(dry_first_moment) or not _valid_physical_tensor(dry_inertia_datum):
		return _failure("dry aggregate overflowed or became nonfinite")

	var resource_ids := PackedStringArray()
	var capacity_mass: float = 0.0
	for resource: Dictionary in prepared_resources:
		resource_ids.append(resource.id)
		capacity_mass += resource.capacity_mass_kg
	if not is_finite(capacity_mass) or not is_finite(dry_mass + capacity_mass):
		return _failure("inventory capacity overflowed")
	return {
		ok = true,
		law = LAW,
		reference_datum_id = reference_datum_id.strip_edges(),
		resource_distribution_model = RESOURCE_DISTRIBUTION,
		dry_component_ids = PackedStringArray(dry.map(func(item: Dictionary) -> String: return item.id)),
		resource_ids = resource_ids,
		dry_mass_kg = dry_mass,
		dry_first_moment_kg_m = dry_first_moment,
		dry_inertia_datum_kgm2 = dry_inertia_datum,
		resources = prepared_resources,
		capacity_mass_kg = capacity_mass,
	}


## Evaluate exact remaining masses by stable resource id. All outputs use the same fixed datum.
static func evaluate(prepared: Dictionary, remaining_mass_kg_by_id: Dictionary) -> Dictionary:
	if not prepared.get("ok", false) or prepared.get("law", "") != LAW:
		return _failure("prepared inventory is invalid or has an unsupported law")
	if not _prepared_is_well_formed(prepared):
		return _failure("prepared inventory geometry is malformed")
	var ids: PackedStringArray = prepared.get("resource_ids", PackedStringArray())
	if remaining_mass_kg_by_id.size() != ids.size():
		return _failure("remaining resource set does not match prepared ids")
	for key: Variant in remaining_mass_kg_by_id.keys():
		if not (key is String) or not ids.has(key):
			return _failure("remaining resource set contains an unknown id")

	var mass: float = float(prepared.dry_mass_kg)
	var first_moment: PackedFloat64Array = prepared.dry_first_moment_kg_m.duplicate()
	var inertia_datum: PackedFloat64Array = prepared.dry_inertia_datum_kgm2.duplicate()
	var remaining_copy: Dictionary = {}
	for resource: Dictionary in prepared.resources:
		var id: String = resource.id
		var amount_value: Variant = remaining_mass_kg_by_id.get(id)
		if not _is_finite_number(amount_value):
			return _failure("remaining mass for %s must be finite" % id)
		var amount: float = float(amount_value)
		if amount < 0.0 or amount > float(resource.capacity_mass_kg):
			return _failure("remaining mass for %s is outside [0, capacity]" % id)
		remaining_copy[id] = amount
		mass += amount
		_add_scaled3(first_moment, resource.center_body_m, amount)
		var fraction: float = amount / float(resource.capacity_mass_kg)
		var offset_tensor: PackedFloat64Array = parallel_axis_per_kg(resource.center_body_m)
		for i: int in 6:
			inertia_datum[i] += amount * offset_tensor[i] + fraction * resource.inertia_centroid_at_capacity_kgm2[i]

	if not is_finite(mass) or mass <= 0.0 or not _finite_array(first_moment) or not _valid_physical_tensor(inertia_datum):
		return _failure("evaluated mass properties are nonfinite or mass is not positive")
	var cg := PackedFloat64Array([first_moment[0] / mass, first_moment[1] / mass, first_moment[2] / mass])
	var cg_offset_tensor: PackedFloat64Array = parallel_axis_per_kg(cg)
	var inertia_cg: PackedFloat64Array = inertia_datum.duplicate()
	for i: int in 6:
		inertia_cg[i] -= mass * cg_offset_tensor[i]
	if not _finite_array(cg) or not _valid_physical_tensor(inertia_cg) or not _is_spd(inertia_cg):
		return _failure("center-of-mass inertia must be finite, physical, and positive definite")
	var inverse: PackedFloat64Array = _scaled_spd_inverse(inertia_cg)
	if inverse.is_empty() or not _finite_array(inverse):
		return _failure("center-of-mass inertia inverse is nonfinite")
	return {
		ok = true,
		law = LAW,
		reference_datum_id = prepared.reference_datum_id,
		resource_ids = ids.duplicate(),
		remaining_mass_kg_by_id = remaining_copy,
		mass_kg = mass,
		first_moment_kg_m = first_moment,
		cg_body_m = cg,
		inertia_datum_kgm2 = inertia_datum,
		inertia_cg_kgm2 = inertia_cg,
		inverse_inertia_cg_kgm2 = inverse,
	}


## FUEL-04: finite resources about the fixed datum O = CG of the authored (reference) state, the per-stage form
## every finite-fuel vehicle uses. The reference state is the validated aircraft: its mass and CG-centred inertia
## with each resource at its reference amount. Each resource is a uniform box of fixed centre and size whose
## remaining mass scales its density (RESOURCE_DISTRIBUTION); amounts may run from 0 to capacity, so a start fill
## above the authored one is representable. Entries: {id, reference_mass_kg, capacity_mass_kg, center_body_m,
## size_body_m}, body FRD metres about O. Prepare once per installation; evaluate per stage.
static func prepare_reference(reference_mass_kg: float, reference_inertia_kgm2: PackedFloat64Array,
		resources: Array) -> Dictionary:
	if not is_finite(reference_mass_kg) or reference_mass_kg <= 0.0 or not _valid_tensor(reference_inertia_kgm2):
		return _failure("reference mass must be finite and positive, inertia six finite entries")
	if resources.is_empty():
		return _failure("reference inventory needs at least one resource")
	var ids: Dictionary = {}
	var reference_total: float = 0.0
	var prepared_resources: Array[Dictionary] = []
	for raw: Variant in resources:
		if not raw is Dictionary:
			return _failure("resource must be a dictionary")
		var id_result: Dictionary = _stable_id(raw, ids)
		if not id_result.ok:
			return id_result
		var reference: Variant = raw.get("reference_mass_kg")
		var capacity: Variant = raw.get("capacity_mass_kg")
		var center: Variant = raw.get("center_body_m")
		var size: Variant = raw.get("size_body_m")
		if not _is_finite_number(reference) or not _is_finite_number(capacity) or float(reference) < 0.0 \
				or float(capacity) < float(reference):
			return _failure("resource %s needs 0 <= reference_mass_kg <= capacity_mass_kg" % id_result.id)
		if not _valid_vec3(center) or not _valid_vec3(size) or size[0] < 0.0 or size[1] < 0.0 or size[2] < 0.0:
			return _failure("resource %s needs a finite center and a nonnegative size" % id_result.id)
		reference_total += float(reference)
		prepared_resources.append({id = id_result.id, reference_mass_kg = float(reference),
			capacity_mass_kg = float(capacity), center_body_m = center.duplicate(), size_body_m = size.duplicate(),
			tensor_per_kg = rectangular_box_per_kg(center, size)})
	if reference_mass_kg <= reference_total:
		return _failure("reference mass must exceed the resources it contains")
	# Parallel typed arrays for the per-stage evaluation; `resources` keeps the readable records.
	var references := PackedFloat64Array()
	var capacities := PackedFloat64Array()
	var centers: Array[PackedFloat64Array] = []
	var tensors: Array[PackedFloat64Array] = []
	for resource: Dictionary in prepared_resources:
		references.append(resource.reference_mass_kg)
		capacities.append(resource.capacity_mass_kg)
		centers.append(resource.center_body_m)
		tensors.append(resource.tensor_per_kg)
	return {ok = true, law = REFERENCE_LAW, resource_distribution_model = RESOURCE_DISTRIBUTION,
		reference_mass_kg = reference_mass_kg, reference_inertia_kgm2 = reference_inertia_kgm2.duplicate(),
		resources = prepared_resources, references = references, capacities = capacities, centers = centers,
		tensors = tensors}


## Mass, CG and inertia about O for the given remaining amounts (same order as the prepared resources).
## Each resource removes (reference − amount) from the reference state. With one resource this is exactly the
## historical glow FuelMass arithmetic, operation for operation, so existing trajectories stay bit-identical.
## Returns {ok, mass_kg, cg_body_m, inertia (about the CG), inverse, inertia_origin (about O)}.
static func evaluate_reference(prepared: Dictionary, amounts: PackedFloat64Array) -> Dictionary:
	var references: PackedFloat64Array = prepared.get("references", PackedFloat64Array())
	var count: int = references.size()
	if prepared.get("law", "") != REFERENCE_LAW or amounts.size() != count or count == 0:
		return {ok = false, error = "prepared reference inventory or amount count is invalid"}
	var capacities: PackedFloat64Array = prepared.capacities
	var centers: Array = prepared.centers
	var tensors: Array = prepared.tensors
	var mass: float = prepared.reference_mass_kg
	var removed: PackedFloat64Array = amounts.duplicate()
	for i: int in count:
		var amount: float = amounts[i]
		if not is_finite(amount) or amount < 0.0 or amount > capacities[i]:
			return {ok = false, error = "amount of %s is outside [0, capacity]" % prepared.resources[i].id}
		removed[i] = references[i] - amount
		mass -= removed[i]
	var cg: PackedFloat64Array = M.scale(centers[0], -removed[0] / mass)
	var inertia_origin: PackedFloat64Array = prepared.reference_inertia_kgm2.duplicate()
	for i: int in count:
		if i > 0:
			cg = M.add(cg, M.scale(centers[i], -removed[i] / mass))
		var tensor: PackedFloat64Array = tensors[i]
		var r: float = removed[i]
		for k: int in 6:
			inertia_origin[k] -= r * tensor[k]
	var parallel: PackedFloat64Array = rectangular_box_per_kg(cg, PackedFloat64Array([0.0, 0.0, 0.0]))
	var inertia: PackedFloat64Array = prepared.reference_inertia_kgm2.duplicate()
	for k: int in 6:
		inertia[k] = inertia_origin[k] - mass * parallel[k]
	var minor2: float = inertia[0] * inertia[1] - inertia[3] * inertia[3]
	# Match the raw inverse's determinant arithmetic before entering its asserting helper.
	var determinant: float = inertia[0] * (inertia[1] * inertia[2] - inertia[5] * inertia[5]) \
		+ inertia[3] * (inertia[4] * inertia[5] - inertia[3] * inertia[2]) \
		+ inertia[4] * (inertia[3] * inertia[5] - inertia[4] * inertia[1])
	var inverse := PackedFloat64Array()
	if inertia[0] > 0.0 and is_finite(minor2) and minor2 >= MIN_NORMAL_FLOAT64 \
			and is_finite(determinant) and determinant >= MIN_NORMAL_FLOAT64:
		# Preserve the historical arithmetic for ordinary aircraft and exact replay.
		inverse = RB.inertia_inverse(inertia)
	# Overflow, underflow, singularity and indefiniteness need the scaled SPD check.
	# In particular, an infinite determinant must never produce an accepted zero inverse.
	if inverse.size() != 6 or not _finite_array(inverse):
		inverse = _scaled_spd_inverse(inertia)
	if inverse.is_empty():
		return {ok = false, error = "inertia is not positive definite or its inverse is not finite"}
	return {ok = true, mass_kg = mass, cg_body_m = cg, inertia = inertia, inverse = inverse, inertia_origin = inertia_origin}


static func _normalize_component(raw: Dictionary, ids: Dictionary) -> Dictionary:
	var id_result: Dictionary = _stable_id(raw, ids)
	if not id_result.ok:
		return id_result
	var mass_value: Variant = raw.get("mass_kg")
	var center: Variant = raw.get("center_body_m")
	var tensor: Variant = raw.get("inertia_centroid_kgm2")
	if not _is_finite_number(mass_value) or float(mass_value) <= 0.0:
		return _failure("dry component %s mass_kg must be finite and positive" % id_result.id)
	if not _valid_vec3(center) or not _valid_physical_tensor(tensor):
		return _failure("dry component %s has invalid center or nonphysical centroid inertia" % id_result.id)
	return {ok = true, component = {id = id_result.id, mass_kg = float(mass_value),
		center_body_m = center.duplicate(), inertia_centroid_kgm2 = tensor.duplicate()}}


static func _normalize_resource(raw: Dictionary, ids: Dictionary) -> Dictionary:
	var id_result: Dictionary = _stable_id(raw, ids)
	if not id_result.ok:
		return id_result
	if str(raw.get("distribution_model", "")) != RESOURCE_DISTRIBUTION:
		return _failure("resource %s must declare %s" % [id_result.id, RESOURCE_DISTRIBUTION])
	var capacity_value: Variant = raw.get("capacity_mass_kg")
	var center: Variant = raw.get("center_body_m")
	var tensor: Variant = raw.get("inertia_centroid_at_capacity_kgm2")
	if not _is_finite_number(capacity_value) or float(capacity_value) <= 0.0:
		return _failure("resource %s capacity_mass_kg must be finite and positive" % id_result.id)
	if not _valid_vec3(center) or not _valid_physical_tensor(tensor):
		return _failure("resource %s has invalid center or nonphysical capacity inertia" % id_result.id)
	return {ok = true, resource = {id = id_result.id, capacity_mass_kg = float(capacity_value),
		center_body_m = center.duplicate(),
		inertia_centroid_at_capacity_kgm2 = tensor.duplicate(), distribution_model = RESOURCE_DISTRIBUTION}}


static func _stable_id(raw: Dictionary, ids: Dictionary) -> Dictionary:
	var id_value: Variant = raw.get("id")
	if not (id_value is String) or id_value.strip_edges().is_empty():
		return _failure("component/resource id must be a nonempty stable string")
	var id: String = id_value.strip_edges()
	if ids.has(id):
		return _failure("duplicate inventory id: %s" % id)
	ids[id] = true
	return {ok = true, id = id}


static func _prepared_is_well_formed(prepared: Dictionary) -> bool:
	for key: String in ["reference_datum_id", "resource_distribution_model", "resource_ids",
			"dry_component_ids", "dry_mass_kg", "dry_first_moment_kg_m", "dry_inertia_datum_kgm2", "resources"]:
		if not prepared.has(key):
			return false
	if not (prepared.reference_datum_id is String) or prepared.reference_datum_id.strip_edges().is_empty():
		return false
	if prepared.resource_distribution_model != RESOURCE_DISTRIBUTION or not _is_finite_number(prepared.dry_mass_kg) or float(prepared.dry_mass_kg) < 0.0:
		return false
	if not _valid_vec3(prepared.dry_first_moment_kg_m) or not _valid_tensor(prepared.dry_inertia_datum_kgm2):
		return false
	if not (prepared.resource_ids is PackedStringArray) or not (prepared.resources is Array):
		return false
	if prepared.resource_ids.size() != prepared.resources.size():
		return false
	var seen: Dictionary = {}
	for i: int in prepared.resources.size():
		var resource: Variant = prepared.resources[i]
		if not (resource is Dictionary):
			return false
		for key: String in ["id", "capacity_mass_kg", "center_body_m", "inertia_centroid_at_capacity_kgm2", "distribution_model"]:
			if not resource.has(key):
				return false
		if not (resource.id is String) or resource.id.is_empty() or resource.id != prepared.resource_ids[i] or seen.has(resource.id):
			return false
		if resource.distribution_model != RESOURCE_DISTRIBUTION or not _is_finite_number(resource.capacity_mass_kg) or float(resource.capacity_mass_kg) <= 0.0:
			return false
		if not _valid_vec3(resource.center_body_m) or not _valid_physical_tensor(resource.inertia_centroid_at_capacity_kgm2):
			return false
		seen[resource.id] = true
	return true


static func _is_finite_number(value: Variant) -> bool:
	if typeof(value) not in [TYPE_FLOAT, TYPE_INT]:
		return false
	return is_finite(float(value))


static func _valid_vec3(value: Variant) -> bool:
	if not (value is PackedFloat64Array) or value.size() != 3:
		return false
	for entry: float in value:
		if not is_finite(entry):
			return false
	return true


static func _valid_tensor(value: Variant) -> bool:
	if not (value is PackedFloat64Array) or value.size() != 6:
		return false
	for entry: float in value:
		if not is_finite(entry):
			return false
	return true


## Physical component tensors may be semidefinite (a point mass has a zero centroid tensor).
static func _valid_psd_tensor(tensor: Variant) -> bool:
	if not _valid_tensor(tensor):
		return false
	var a: float = tensor[0]
	var b: float = tensor[1]
	var c: float = tensor[2]
	var d: float = tensor[3]
	var e: float = tensor[4]
	var f: float = tensor[5]
	var scale: float = maxf(maxf(absf(a), absf(b)), maxf(absf(c), maxf(absf(d), maxf(absf(e), absf(f)))))
	if scale == 0.0:
		return true
	var an: float = a / scale
	var bn: float = b / scale
	var cn: float = c / scale
	var dn: float = d / scale
	var en: float = e / scale
	var fn: float = f / scale
	if an < -PSD_ROUNDING_TOLERANCE or bn < -PSD_ROUNDING_TOLERANCE or cn < -PSD_ROUNDING_TOLERANCE:
		return false
	if an * bn - dn * dn < -PSD_ROUNDING_TOLERANCE or an * cn - en * en < -PSD_ROUNDING_TOLERANCE or bn * cn - fn * fn < -PSD_ROUNDING_TOLERANCE:
		return false
	return an * (bn * cn - fn * fn) + dn * (en * fn - dn * cn) + en * (dn * fn - bn * en) >= -PSD_ROUNDING_TOLERANCE


## A mass-distribution inertia tensor I is physical iff I and C = tr(I)/2·Id − I are PSD.
## C is the second-moment tensor, so this enforces principal-moment triangle inequalities
## without diagonalization. Scale first to keep finite large/small entries numerically bounded.
static func _valid_physical_tensor(tensor: Variant) -> bool:
	if not _valid_psd_tensor(tensor):
		return false
	var scale: float = _tensor_scale(tensor)
	if scale == 0.0:
		return true
	var normalized: PackedFloat64Array = _normalized_tensor(tensor, scale)
	var half_trace: float = (normalized[0] + normalized[1] + normalized[2]) * 0.5
	var second_moment := PackedFloat64Array([half_trace - normalized[0], half_trace - normalized[1],
	half_trace - normalized[2], -normalized[3], -normalized[4], -normalized[5]])
	return _valid_psd_tensor(second_moment)


## Sylvester's criterion for a symmetric 3x3 tensor, applied after scaling so its minors
## cannot overflow or underflow merely because the original finite entries are extreme.
static func _is_spd(tensor: PackedFloat64Array) -> bool:
	if not _valid_tensor(tensor):
		return false
	var scale: float = _tensor_scale(tensor)
	if scale == 0.0:
		return false
	var normalized: PackedFloat64Array = _normalized_tensor(tensor, scale)
	var a: float = normalized[0]
	var b: float = normalized[1]
	var c: float = normalized[2]
	var d: float = normalized[3]
	var e: float = normalized[4]
	var f: float = normalized[5]
	return a > 0.0 and b > 0.0 and c > 0.0 \
		and a * b - d * d > 0.0 and a * c - e * e > 0.0 and b * c - f * f > 0.0 \
		and _determinant(tensor) > 0.0


## Return the determinant after normalizing by the largest absolute entry (det(I / scale)).
## Its sign is the determinant sign while avoiding scale³ overflow/underflow.
static func _determinant(tensor: PackedFloat64Array) -> float:
	if not _valid_tensor(tensor):
		return NAN
	var scale: float = _tensor_scale(tensor)
	if scale == 0.0:
		return 0.0
	var normalized: PackedFloat64Array = _normalized_tensor(tensor, scale)
	var a: float = normalized[0]
	var b: float = normalized[1]
	var c: float = normalized[2]
	var d: float = normalized[3]
	var e: float = normalized[4]
	var f: float = normalized[5]
	var c00: float = b * c - f * f
	var c01: float = e * f - d * c
	var c02: float = d * f - b * e
	return a * c00 + d * c01 + e * c02


## Invert normalized entries, then divide by scale. The rigid-body helper operates on raw
## entries and can overflow/underflow its cofactors for extreme finite tensors.
static func _scaled_spd_inverse(tensor: PackedFloat64Array) -> PackedFloat64Array:
	if not _is_spd(tensor):
		return PackedFloat64Array()
	var scale: float = _tensor_scale(tensor)
	var normalized: PackedFloat64Array = _normalized_tensor(tensor, scale)
	var inverse_normalized: PackedFloat64Array = RB.inertia_inverse(normalized)
	if not _finite_array(inverse_normalized):
		return PackedFloat64Array()
	var inverse: PackedFloat64Array = inverse_normalized.duplicate()
	for i: int in 6:
		inverse[i] /= scale
	if not _finite_array(inverse) or not _is_spd(inverse):
		return PackedFloat64Array()
	return inverse


static func _tensor_scale(tensor: PackedFloat64Array) -> float:
	var scale: float = 0.0
	for value: float in tensor:
		scale = maxf(scale, absf(value))
	return scale


static func _normalized_tensor(tensor: PackedFloat64Array, scale: float) -> PackedFloat64Array:
	var normalized := PackedFloat64Array()
	for value: float in tensor:
		normalized.append(value / scale)
	return normalized


static func _add_scaled3(target: PackedFloat64Array, vector: PackedFloat64Array, scale: float) -> void:
	for i: int in 3:
		target[i] += scale * vector[i]


static func _finite_array(values: PackedFloat64Array) -> bool:
	for value: float in values:
		if not is_finite(value):
			return false
	return true


static func _failure(message: String) -> Dictionary:
	return {ok = false, error = message}
