extends RefCounted

const Field = preload("res://render/field.gd")
const CollisionSetup = preload("res://scenery/collision_setup.gd")

const ID: String = "club_field"
const DISPLAY_NAME: String = "Club field"
const FIELD_PATH: String = "res://data/fields/default.json"


static func build(field: Dictionary, lighting: Dictionary = {}) -> Node3D:
	return Field.build(field, lighting)


static func build_staged(field: Dictionary, lighting: Dictionary, checkpoint: Callable) -> Node3D:
	return await Field.build_staged(field, lighting, [], checkpoint)


static func collision_world(field: Dictionary) -> Dictionary:
	return CollisionSetup.build(field)
