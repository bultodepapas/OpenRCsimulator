# AV-31: inspector compatibility facade; the catalog uses the common imported builder.
extends RefCounted

const Geometry := preload("res://aircraft/avanti_s_blender_geometry.gd")
const Imported := preload("res://aircraft/imported_model.gd")
const VISUAL_REVISION: String = Geometry.DATA.revision

static func build() -> Dictionary:
	var registry: Script = load("res://aircraft/model_registry.gd")
	var result: Dictionary = registry.describe("sebart-avanti-s-a200-p100rx")
	if not result.ok:
		push_warning("Vantage Jet model: " + str(result.errors))
		return {}
	var model := Imported.build(result.manifest)
	if not model.is_empty(): model.data = Geometry.DATA
	return model

static func apply_surfaces(model: Dictionary, surfaces_deg: Dictionary) -> void:
	Imported.apply_surfaces(model, surfaces_deg)

static func set_flaps(model: Dictionary, degrees: float) -> void:
	Imported.set_flaps(model, degrees)

static func apply_controls(model: Dictionary, roll: float, pitch: float, yaw: float, flap_deg: float) -> void:
	roll = clampf(roll, -1.0, 1.0)
	pitch = clampf(pitch, -1.0, 1.0)
	yaw = clampf(yaw, -1.0, 1.0)
	var right := roll * (30.0 if roll >= 0.0 else 25.0)
	var left := -roll * (25.0 if roll >= 0.0 else 30.0)
	apply_surfaces(model, {aileron_right = right, aileron_left = left, elevator = pitch * 30.0, rudder = yaw * 30.0})
	set_flaps(model, flap_deg)
