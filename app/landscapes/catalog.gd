extends RefCounted

const ClubField = preload("res://landscapes/club_field/landscape.gd")
const GreenParadise = preload("res://landscapes/green_paradise/landscape.gd")

const DEFAULT_ID: String = "club_field"


static func ids() -> Array[String]:
	var ordered: Array[String] = []
	ordered.append(ClubField.ID)
	ordered.append(GreenParadise.ID)
	return ordered


static func has(id: String) -> bool:
	return id == ClubField.ID or id == GreenParadise.ID


static func entry(id: String) -> Dictionary:
	if id == ClubField.ID:
		return {id = ClubField.ID, name = ClubField.DISPLAY_NAME, field_path = ClubField.FIELD_PATH}
	if id == GreenParadise.ID:
		return {
			id = GreenParadise.ID,
			name = GreenParadise.DISPLAY_NAME,
			field_path = GreenParadise.FIELD_PATH,
		}
	return {}


static func build(id: String, field: Dictionary, lighting: Dictionary = {}) -> Node3D:
	if id == ClubField.ID:
		return ClubField.build(field, lighting)
	if id == GreenParadise.ID:
		return GreenParadise.build(field, lighting)
	return null


static func collision_world(id: String, field: Dictionary) -> Dictionary:
	if id == ClubField.ID:
		return ClubField.collision_world(field)
	if id == GreenParadise.ID:
		return GreenParadise.collision_world(field)
	return {
		ok = false,
		world = {},
		errors = PackedStringArray(["landscape: unknown id '%s'" % id]),
	}