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
		gear: Dictionary, extension: float, density: float) -> PackedFloat64Array:
	if not enabled(gear) or extension == 0.0:
		return PackedFloat64Array()
	if not valid_fraction(extension) or not is_finite(density) or density <= 0.0:
		return PackedFloat64Array([NAN])
	var arm: PackedFloat64Array = gear.retraction.drag_center
	var rates := PackedFloat64Array([state[RB.RATE], state[RB.RATE + 1], state[RB.RATE + 2]])
	var velocity: PackedFloat64Array = M.add(air_velocity, M.cross(rates, arm))
	var speed: float = M.norm(velocity)
	var force: PackedFloat64Array = M.scale(velocity, -0.5 * density * gear.retraction.drag_area * extension * speed)
	var moment: PackedFloat64Array = M.cross(arm, force)
	force.append_array(moment)
	return force
