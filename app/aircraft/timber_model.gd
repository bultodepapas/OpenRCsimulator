# Lumber inspector compatibility facade. Construction and poses use the shared Blender adapter.
extends RefCounted

const TimberGeometry := preload("res://aircraft/timber_geometry.gd")
const SCENE := preload("res://assets/aircraft/turbo-lumber-evolution/timber.glb")
const ImportedModel := preload("res://aircraft/imported_model.gd")
const VISUAL_REVISION := "r2-d75ae605aa3a"
# Public inspector keys retained for Lumber metrology and clearance tools.
const HINGE_NODES := {aileron_left = "aileron_left_hinge", aileron_right = "aileron_right_hinge", elevator = "elevator_hinge",
	rudder = "rudder_hinge", flap_left = "flap_left_hinge", flap_right = "flap_right_hinge"}


static func build() -> Dictionary:
	var registry: Script = load("res://aircraft/model_registry.gd")
	var result: Dictionary = registry.describe("turbo-lumber-evolution")
	if not result.ok:
		push_warning("Lumber model manifest: " + str(result.errors))
		return {}
	var model := ImportedModel.build(result.manifest)
	# Older Lumber metrology tools retain the generated constant by identity.
	# Dynamic Script.get() in the common loader returns an equivalent dictionary snapshot.
	if not model.is_empty(): model.data = TimberGeometry.DATA
	return model


static func relative(root: Node3D, node: Node3D) -> Transform3D:
	return ImportedModel.relative(root, node)


static func apply_surfaces(model: Dictionary, surfaces_deg: Dictionary) -> void:
	ImportedModel.apply_surfaces(model, surfaces_deg)


static func set_flaps(model: Dictionary, degrees: float) -> void:
	ImportedModel.set_visual_surfaces(model, {flap_left = degrees, flap_right = degrees})


static func manual_throws_deg() -> Dictionary:
	var controls: Dictionary = TimberGeometry.DATA.controls
	return {aileron = float(controls.aileron.high_deg.value), elevator = float(controls.elevator.high_deg.value),
		rudder = float(controls.rudder.high_deg.value)}


static func apply_controls(model: Dictionary, roll: float, pitch: float, yaw: float, flap_deg: float) -> void:
	var throws := manual_throws_deg()
	roll = clampf(roll, -1, 1)
	pitch = clampf(pitch, -1, 1)
	yaw = clampf(yaw, -1, 1)
	apply_surfaces(model, {aileron_right = roll * throws.aileron, aileron_left = -roll * throws.aileron,
		elevator = pitch * throws.elevator, rudder = yaw * throws.rudder})
	set_flaps(model, flap_deg)
