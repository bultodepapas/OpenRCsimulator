## AV-09: rate-limited gear actuator, declared contact paths and incremental drag.
## All values are float64. Full-down contacts retain the qualified ground law.
extends RefCounted

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const LAW := "retractable-point-gear-v1"


static func enabled(gear: Dictionary) -> bool:
	return not gear.get("retraction", {}).is_empty()


static func valid_fraction(value: float) -> bool:
	return is_finite(value) and value >= 0.0 and value <= 1.0


static func advance(extension: float, target: float, dt: float, gear: Dictionary) -> float:
	if not valid_fraction(extension) or target not in [0.0, 1.0] or not is_finite(dt) or dt <= 0.0 or not enabled(gear):
		return NAN
	var duration: float = gear.retraction.extension_time if target > extension else gear.retraction.retraction_time
	if not is_finite(duration) or duration <= 0.0:
		return NAN
	var step: float = dt / duration
	# Snap the mathematically reached endpoint despite repeated-addition roundoff.
	if absf(target - extension) <= step + 1.0e-12:
		return target
	return extension + step * signf(target - extension)


static func path_point(path: PackedFloat64Array, extension: float) -> PackedFloat64Array:
	var count: int = path.size() / 3
	if count < 2 or path.size() % 3 != 0 or not valid_fraction(extension):
		return PackedFloat64Array([NAN, NAN, NAN])
	var at: float = extension * float(count - 1)
	var left: int = mini(int(floor(at)), count - 2)
	var fraction: float = at - float(left)
	var point := PackedFloat64Array()
	for axis in 3:
		point.append(path[left * 3 + axis] + fraction * (path[(left + 1) * 3 + axis] - path[left * 3 + axis]))
	return point


## Partial gear has geometry but no load-bearing downlock. Touching an unlocked
## wheel is terminal (zero admitted travel), instead of supporting the airplane invisibly.
static func pose(gear: Dictionary, extension: float) -> Dictionary:
	if not enabled(gear) or extension == 1.0:
		return gear
	if not valid_fraction(extension):
		return {}
	var result: Dictionary = gear.duplicate()
	var contacts: Array = []
	for original: Dictionary in gear.contacts:
		var contact: Dictionary = original.duplicate()
		contact.position = path_point(original.retraction_path, extension)
		contact.stiffness = 0.0
		contact.damping = 0.0
		contact.max_compression = 0.0
		contact.max_steering = 0.0
		contact.anchor_stiffness = 0.0
		contact.anchor_damping = 0.0
		contacts.append(contact)
	result.contacts = contacts
	return result


## Estimated exposed-gear drag area, zero exactly when stowed. The declared
## application point gives its moment; no hidden change to clean-aircraft coefficients.
static func drag_loads(state: PackedFloat64Array, air_velocity: PackedFloat64Array,
		gear: Dictionary, extension: float, density: float,
		ambient_delta_body: PackedFloat64Array = PackedFloat64Array()) -> PackedFloat64Array:
	if not enabled(gear) or extension == 0.0:
		return PackedFloat64Array()
	if not valid_fraction(extension) or not is_finite(density) or density <= 0.0:
		return PackedFloat64Array([NAN])
	var has_spatial_delta := not ambient_delta_body.is_empty()
	var has_local_delta := false
	var local_air: PackedFloat64Array = air_velocity
	if has_spatial_delta:
		if ambient_delta_body.size() != 3 or not _finite3(ambient_delta_body):
			return PackedFloat64Array([NAN])
		if not _finite3(air_velocity):
			return PackedFloat64Array([NAN])
		if state.size() < RB.RATE + 3:
			return PackedFloat64Array([NAN])
		var retraction_value: Variant = gear.get("retraction", {})
		if typeof(retraction_value) != TYPE_DICTIONARY:
			return PackedFloat64Array([NAN])
		var retraction: Dictionary = retraction_value
		var arm_value: Variant = retraction.get("drag_center", PackedFloat64Array())
		var area_value: Variant = retraction.get("drag_area", NAN)
		if typeof(arm_value) != TYPE_PACKED_FLOAT64_ARRAY or not _finite3(arm_value):
			return PackedFloat64Array([NAN])
		if typeof(area_value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(area_value)) or float(area_value) < 0.0:
			return PackedFloat64Array([NAN])
		for axis in 3:
			if not is_finite(state[RB.RATE + axis]):
				return PackedFloat64Array([NAN])
		# Preserve the exact zero-gradient result even when a spatial provider returns an explicit zero vector.
		has_local_delta = ambient_delta_body[0] != 0.0 or ambient_delta_body[1] != 0.0 or ambient_delta_body[2] != 0.0
	if has_local_delta:
		local_air = air_velocity.duplicate()
		for axis in 3:
			local_air[axis] += ambient_delta_body[axis]
			if not is_finite(local_air[axis]):
				return PackedFloat64Array([NAN])
	var arm: PackedFloat64Array = gear.retraction.drag_center
	var rates := PackedFloat64Array([state[RB.RATE], state[RB.RATE + 1], state[RB.RATE + 2]])
	# Ambient point delta is applied before the one existing body-rate term; it never includes omega × r.
	var velocity: PackedFloat64Array = M.add(local_air, M.cross(rates, arm))
	if has_spatial_delta and not _finite3(velocity):
		return PackedFloat64Array([NAN])
	var speed: float = M.norm(velocity)
	if has_spatial_delta and not is_finite(speed):
		return PackedFloat64Array([NAN])
	var force: PackedFloat64Array = M.scale(velocity, -0.5 * density * gear.retraction.drag_area * extension * speed)
	var moment: PackedFloat64Array = M.cross(arm, force)
	if has_spatial_delta and (not _finite3(force) or not _finite3(moment)):
		return PackedFloat64Array([NAN])
	force.append_array(moment)
	return force


static func _finite3(values: PackedFloat64Array) -> bool:
	if values.size() != 3:
		return false
	for value: float in values:
		if not is_finite(value):
			return false
	return true
