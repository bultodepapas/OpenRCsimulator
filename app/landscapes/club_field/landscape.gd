extends RefCounted

const Field = preload("res://render/field.gd")
const CollisionSetup = preload("res://scenery/collision_setup.gd")

const ID: String = "club_field"
const DISPLAY_NAME: String = "Club field"
const FIELD_PATH: String = "res://data/fields/default.json"


## `rc_track`: the airplane flight's RC-TRACK circuit, or {} (scenery/rc_track_option.gd).
static func build(field: Dictionary, lighting: Dictionary = {}, rc_track: Dictionary = {}) -> Node3D:
	return Field.build(field, lighting, [], rc_track)


static func build_staged(field: Dictionary, lighting: Dictionary, checkpoint: Callable,
		rc_track: Dictionary = {}) -> Node3D:
	return await Field.build_staged(field, lighting, [], checkpoint, rc_track)


static func collision_world(field: Dictionary, rc_track: Dictionary = {}) -> Dictionary:
	return CollisionSetup.build(field, rc_track)
