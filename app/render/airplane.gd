# Stable render interface; visual .61 geometry is separate from simulation data.
extends RefCounted

const Controls := preload("res://aircraft/ugly_stik_controls.gd")
const UglyStik := preload("res://aircraft/ugly_stik_model.gd")


static func _mat(color: Color) -> StandardMaterial3D:
	return UglyStik.material(color)


## Returns { root: Node3D, propeller: Node3D, hinges: { name: Node3D } }.
static func build() -> Dictionary:
	return UglyStik.build()


## Wing rest frames carry the dihedral; the hinge rotates only in its own frame.
static func apply_surfaces(airplane: Dictionary, rotations: Dictionary) -> void:
	for surface_name in rotations:
		var r: Dictionary = rotations[surface_name]
		airplane.hinges[surface_name].rotation = Vector3(r.x, r.y, 0)
	if airplane.has("controls"): Controls.update(airplane.controls)


## Optional visual gear state from simulation; angles in radians around model axes.
## Positive wheel rotation is around +X; positive steering is around +Y.
static func apply_gear(airplane: Dictionary, wheel_angles: Dictionary, steering_rad: float) -> void:
	for key in ["left", "right", "nose"]:
		airplane.gear[key].rotation.x = float(wheel_angles.get(key, 0.0))
	airplane.gear.steering.rotation.y = steering_rad


## Inspector-only access: restore false before returning to assembled views.
static func set_maintenance(airplane: Dictionary, visible: bool) -> void:
	if airplane.has("controls"): Controls.set_maintenance(airplane.controls, visible)
