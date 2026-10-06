# Stable render interface; visual geometry is separate from simulation data.
# One adapter for every catalog aircraft (app_state/aircraft_catalog.gd): build(id) dispatches to the model team's
# builder for that ID; with no argument it is the Ugly Stik, as before. Every build returns at least
# { root, propeller, hinges, aircraft_id } and keeps the `airplane`, `propeller` and `*_hinge` node names.
extends RefCounted

const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Controls := preload("res://aircraft/ugly_stik_controls.gd")
const UglyStik := preload("res://aircraft/ugly_stik_model.gd")
const StikGeometry := preload("res://aircraft/ugly_stik_geometry.gd")
const Extra := preload("res://aircraft/extra_300s_model.gd")
const ExtraGeometry := preload("res://aircraft/extra_300s_geometry.gd")
const Avanti := preload("res://aircraft/avanti_s_model.gd")
const P51 := preload("res://aircraft/p51d_model.gd")
const P51Geometry := preload("res://aircraft/p51d_geometry.gd")

const STIK_ID := "jensen-das-ugly-stik-60"
const EXTRA_ID := "gp-extra-300s-60"
const AVANTI_ID := "sebart-avanti-s-a200-p100rx"
const P51_ID := "p51d-mustang-120"


static func _mat(color: Color) -> StandardMaterial3D:
	return UglyStik.material(color)


## Returns { root: Node3D, propeller: Node3D, hinges: { name: … }, aircraft_id, … } for a catalog ID; {} for an
## unknown one (never another airplane in its place).
static func build(id := STIK_ID) -> Dictionary:
	var airplane: Dictionary
	match id:
		STIK_ID:
			airplane = UglyStik.build()
		EXTRA_ID:
			airplane = Extra.build()
		AVANTI_ID:
			airplane = Avanti.build()
		P51_ID:
			airplane = P51.build()
		_:
			push_error("render/airplane.gd: unknown aircraft '%s'" % id)
			return {}
	airplane.aircraft_id = id
	return airplane


## Where the data file's le frame sits in the model: x = model z of the wing leading edge the data measures from,
## y = model y of the thrust line. Read from the model team's generated geometry (never copied numbers).
## Preview-only aircraft have no flight data: Vector2.ZERO.
static func datum(id: String) -> Vector2:
	match id:
		STIK_ID:
			return Vector2(StikGeometry.DATA.wing.leading_z, StikGeometry.DATA.equipment.shaft_y)
		EXTRA_ID:
			# geometry.json: y = 0 on the spinner axis; the physics le frame starts at the trapezoid's root LE.
			return Vector2(ExtraGeometry.DATA.wing.le_z_root, 0.0)
		P51_ID:
			# geometry.json: z = 0 at the root leading edge, y = 0 on the spinner axis: the le frame's own datum.
			return Vector2(P51Geometry.DATA.wing.le_z_root, 0.0)
		AVANTI_ID:
			# geometry.json: z = 0 at the root leading edge beside the fuselage, y = 0 on the root wing mid-plane; the
			# physics le frame (AV-06) uses the same origin, and its thrust line sits where the data file says.
			return Vector2(0.0, 0.0)
	return Vector2.ZERO


## Hinge rotations from input/commands.gd hinge_rotations(). Stik, Extra and P-51: wing rest frames carry the dihedral
## (Stik) or the swept hinge line (Extra); the hinge rotates only in its own frame. The Avanti drives its own
## axis/rest hinges from the same deflections in degrees.
static func apply_surfaces(airplane: Dictionary, rotations: Dictionary) -> void:
	if airplane.get("aircraft_id", STIK_ID) == AVANTI_ID:
		Avanti.apply_surfaces(airplane, surface_degrees(rotations))
		return
	for surface_name in rotations:
		var r: Dictionary = rotations[surface_name]
		airplane.hinges[surface_name].rotation = Vector3(r.x, r.y, 0)
	if airplane.has("controls"): Controls.update(airplane.controls)


## The inverse of Commands.hinge_rotations(): trailing-edge deflections in degrees (up for ailerons/elevator,
## right for the rudder), as Commands.surface_deflections_deg() gives them.
static func surface_degrees(rotations: Dictionary) -> Dictionary:
	return {
		aileron_right = -rad_to_deg(rotations.aileron_right.x),
		aileron_left = -rad_to_deg(rotations.aileron_left.x),
		elevator = -rad_to_deg(rotations.elevator.x),
		rudder = rad_to_deg(rotations.rudder.y),
	}


## Optional visual gear state from simulation; angles in radians around model axes. Each aircraft has its own wheels
## (Stik: left, right, nose; Extra: left, right, tail; Avanti: none yet). Positive wheel rotation is around +X;
## positive steering is around +Y.
static func apply_gear(airplane: Dictionary, wheel_angles: Dictionary, steering_rad: float) -> void:
	var gear: Dictionary = airplane.get("gear", {})
	for key in ["left", "right", "nose", "tail"]:
		if gear.has(key):
			gear[key].rotation.x = float(wheel_angles.get(key, 0.0))
	if gear.has("steering"):
		gear.steering.rotation.y = steering_rad


## Inspector-only access: restore false before returning to assembled views.
static func set_maintenance(airplane: Dictionary, visible: bool) -> void:
	if airplane.has("controls"): Controls.set_maintenance(airplane.controls, visible)
