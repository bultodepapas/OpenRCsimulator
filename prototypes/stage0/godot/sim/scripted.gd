# Scripted Stage 0 motion in the world NED frame. No rendering nodes.
# Positions stay in GDScript floats (64-bit), not Vector3 (32-bit).
extends RefCounted

const Spec := preload("res://spec.gd")


static func pose_at(t: float) -> Dictionary:
	var c: Dictionary = Spec.CIRCLE
	var omega: float = c.speed / c.radius
	var a: float = omega * t
	return {
		ned = [c.center_north + c.radius * cos(a), c.center_east + c.radius * sin(a), -c.altitude],
		yaw = a + PI / 2.0,
		pitch = 0.0,
		roll = atan(c.speed * c.speed / (Spec.G * c.radius)),
	}
