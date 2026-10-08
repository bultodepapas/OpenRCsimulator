# CR-01a: diagnostic at the existing detector's tick boundary, not a collision solver.
# Inputs are validated aircraft data and the session's finite, normalized rigid-body state.
# No sub-tick time, physical failure threshold or deforming-gear point velocity is inferred.
extends RefCounted

const M = preload("res://physics/math3d.gd")
const RB = preload("res://physics/rigid_body.gd")
const Ground = preload("res://physics/ground_contact.gd")


class Snapshot:
	extends RefCounted
	var trigger: String = ""
	var tick: int = 0
	var detected_state: PackedFloat64Array = PackedFloat64Array()
	# Index is local to this exact model's hull/gear list, not a stable component ID.
	var point_index: int = -1
	var component_name: String = "" # Known only for named landing-gear contacts.
	var body_point: PackedFloat64Array = PackedFloat64Array()
	var has_kinematics: bool = false
	var point_ned: PackedFloat64Array = PackedFloat64Array()
	var velocity_ned: PackedFloat64Array = PackedFloat64Array()
	var normal_ned: PackedFloat64Array = PackedFloat64Array()
	var speed_mps: float = 0.0 # Unknown unless has_kinematics.
	var down_speed_mps: float = 0.0 # Signed into flat ground; unknown unless has_kinematics.
	var has_compression: bool = false
	var compression_m: float = 0.0 # Unknown unless has_compression.
	var travel_limit_m: float = 0.0 # Unknown unless has_compression.

	func description() -> String:
		if trigger == "gear_limit":
			return "landing gear travel limit" + (" (%s)" % component_name if not component_name.is_empty() else "")
		var cause: String = "airframe contact"
		if point_index >= 0:
			cause += " (hull point %d)" % (point_index + 1)
		if has_kinematics:
			cause += ", point speed %.1f m/s at detected tick" % speed_mps
		return cause


## First penetrating point in data order, preserving the existing detector's exact expression.
## This order is deterministic, but does not establish which point touched first within a tick.
static func hull_contact(s: PackedFloat64Array, tick: int, hull: PackedFloat64Array) -> Snapshot:
	var out: Snapshot = _start(s, tick, "hull_contact")
	var q: PackedFloat64Array = RB._att(s)
	for i in range(0, hull.size(), 3):
		var down: float = 2.0 * (q[1] * q[3] - q[0] * q[2]) * hull[i] + 2.0 * (q[2] * q[3] + q[0] * q[1]) * hull[i + 1] \
			+ (1.0 - 2.0 * (q[1] * q[1] + q[2] * q[2])) * hull[i + 2]
		if s[RB.POS + 2] + down >= 0.0:
			out.point_index = i / 3
			out.body_point = hull.slice(i, i + 3)
			_hull_kinematics(out, s, q)
			break
	return out


## A gear contact position is its undeformed reference. Its rigid-point velocity is NOT the
## deforming wheel's contact velocity; leave kinematics unknown instead of inventing that rate.
static func gear_limit(s: PackedFloat64Array, tick: int, gear: Dictionary) -> Snapshot:
	var out: Snapshot = _start(s, tick, "gear_limit")
	if gear.is_empty() or -s[RB.POS + 2] > gear.reach:
		return out
	var compressions: PackedFloat64Array = Ground.compressions(s, gear)
	for i in compressions.size():
		var contact: Dictionary = gear.contacts[i]
		if compressions[i] > contact.max_compression:
			out.point_index = i
			out.component_name = contact.name
			out.body_point = contact.position.duplicate()
			if is_finite(compressions[i]) and is_finite(contact.max_compression):
				out.has_compression = true
				out.compression_m = compressions[i]
				out.travel_limit_m = contact.max_compression
			break
	return out


static func _start(s: PackedFloat64Array, tick: int, trigger: String) -> Snapshot:
	var out: Snapshot = Snapshot.new()
	out.trigger = trigger
	out.tick = tick
	out.detected_state = s.duplicate()
	return out


static func _hull_kinematics(out: Snapshot, s: PackedFloat64Array, q: PackedFloat64Array) -> void:
	var point: PackedFloat64Array = M.add(RB._slice3(s, RB.POS), M.q_rotate(q, out.body_point))
	var velocity_body: PackedFloat64Array = M.add(RB._slice3(s, RB.VEL),
		M.cross(RB._slice3(s, RB.RATE), out.body_point))
	var velocity: PackedFloat64Array = M.q_rotate(q, velocity_body)
	var speed: float = M.norm(velocity)
	for value in point:
		if not is_finite(value):
			return
	for value in velocity:
		if not is_finite(value):
			return
	if not is_finite(speed):
		return
	out.has_kinematics = true
	out.point_ned = point
	out.velocity_ned = velocity
	out.normal_ned = PackedFloat64Array([0.0, 0.0, -1.0])
	out.speed_mps = speed
	out.down_speed_mps = velocity[2]
