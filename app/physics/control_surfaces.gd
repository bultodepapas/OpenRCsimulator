extends RefCounted
class_name ControlSurfaces


## Pure pilot-command to surface mapping. Throws are explicit so this module does not load aircraft data.
## Input axes and the returned trailing-edge angles are unitless and degrees respectively.
## Positive roll raises the right aileron; aileron_down optionally sets the down-going throw.
static func surface_deflections_deg(c: Dictionary, throws_deg: Dictionary) -> Dictionary:
	var t: Dictionary = throws_deg
	return {
		aileron_right = _aileron(c.roll, t),
		aileron_left = _aileron(-c.roll, t),
		elevator = c.pitch * t.elevator,
		rudder = c.yaw * t.rudder,
	}


## One aileron's trailing-edge angle (degrees, + = up) for its own command x (+ = up).
static func _aileron(x: float, t: Dictionary) -> float:
	return x * (t.aileron if x >= 0.0 else t.get("aileron_down", t.aileron))


## Model-space hinge rotations in radians. Surface panels extend aft (+z) from each hinge.
static func hinge_rotations(c: Dictionary, throws_deg: Dictionary) -> Dictionary:
	var d := surface_deflections_deg(c, throws_deg)
	return hinge_rotations_from_surfaces(d)


## Maps pilot-side TE angles (up/right positive) into the aircraft data sign conventions.
static func deflections_from_surfaces(surfaces_deg: Dictionary) -> Dictionary:
	return {
		elevator = -deg_to_rad(surfaces_deg.elevator),
		aileron_right = -deg_to_rad(surfaces_deg.aileron_right),
		aileron_left = -deg_to_rad(surfaces_deg.aileron_left),
		rudder = -deg_to_rad(surfaces_deg.rudder),
	}


## About +x, an aft edge rises for negative rotation; about +y, the rudder goes right for positive rotation.
static func hinge_rotations_from_surfaces(surfaces_deg: Dictionary) -> Dictionary:
	return {
		aileron_right = { x = -deg_to_rad(surfaces_deg.aileron_right), y = 0.0 },
		aileron_left = { x = -deg_to_rad(surfaces_deg.aileron_left), y = 0.0 },
		elevator = { x = -deg_to_rad(surfaces_deg.elevator), y = 0.0 },
		rudder = { x = 0.0, y = deg_to_rad(surfaces_deg.rudder) },
	}


## Inverse for renderer-facing hinge poses: rotations in radians to pilot-side TE degrees.
static func from_hinge_rotations(rotations: Dictionary) -> Dictionary:
	return {
		aileron_right = -rad_to_deg(rotations.aileron_right.x),
		aileron_left = -rad_to_deg(rotations.aileron_left.x),
		elevator = -rad_to_deg(rotations.elevator.x),
		rudder = rad_to_deg(rotations.rudder.y),
	}
