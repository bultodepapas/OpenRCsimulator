extends RefCounted


## Candidate independent surface positions: right aileron, left aileron, elevator,
## rudder. Each normalized position is positive trailing-edge up/right; a healthy
## conventional roll maps to [roll, -roll]. This conversion does not declare
## independent hardware on an aircraft. Throws must be validated aircraft data.
static func independent_deflections_deg(positions: PackedFloat64Array, throws_deg: Dictionary) -> Dictionary:
	if positions.size() != 4:
		return {}
	for position: float in positions:
		if not is_finite(position) or absf(position) > 1.0:
			return {}
	return {
		aileron_right = _aileron(positions[0], throws_deg),
		aileron_left = _aileron(positions[1], throws_deg),
		elevator = positions[2] * throws_deg.elevator,
		rudder = positions[3] * throws_deg.rudder,
	}


## Pure pilot-command to surface mapping. Throws are explicit so this module does not load aircraft data.
## Input axes and the returned trailing-edge angles are unitless and degrees respectively.
## Positive roll raises the right aileron; aileron_down optionally sets the down-going throw.
static func surface_deflections_deg(c: Dictionary, throws_deg: Dictionary) -> Dictionary:
	var t: Dictionary = throws_deg
	if t.has("elevon"):
		return elevon_deflections_deg(c, t)
	return {
		aileron_right = _aileron(c.roll, t),
		aileron_left = _aileron(-c.roll, t),
		elevator = c.pitch * t.elevator,
		rudder = c.yaw * t.rudder,
	}


## X8-03: a radio's elevon mix. Each elevon (trailing edge up +) takes pitch × elevator share ± roll × aileron share,
## clipped at the servo end point `elevon`; the yaw stick moves nothing. The result is the exact symmetric (elevator)
## and antisymmetric (aileron) decomposition of the two clipped elevons, so physics and the rendered elevons
## (elevon = elevator + that side's aileron) see the same surfaces, saturation included.
static func elevon_deflections_deg(c: Dictionary, t: Dictionary) -> Dictionary:
	var pitch: float = c.pitch * t.elevator
	var roll: float = c.roll * t.aileron
	var limit: float = t.elevon
	var right := clampf(pitch + roll, -limit, limit)
	var left := clampf(pitch - roll, -limit, limit)
	return {
		aileron_right = 0.5 * (right - left),
		aileron_left = 0.5 * (left - right),
		elevator = 0.5 * (right + left),
		rudder = 0.0,
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
