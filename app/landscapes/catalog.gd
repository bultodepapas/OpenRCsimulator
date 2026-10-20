extends RefCounted

const ADAPTERS: Array = [
	preload("res://landscapes/club_field/landscape.gd"),
	preload("res://landscapes/green_paradise/landscape.gd"),
]

const DEFAULT_ID: String = "club_field"


static func ids() -> Array[String]:
	var ordered: Array[String] = []
	for adapter in ADAPTERS:
		ordered.append(str(adapter.ID))
	return ordered


static func has(id: String) -> bool:
	return _adapter(id) != null


static func entry(id: String) -> Dictionary:
	var adapter: Variant = _adapter(id)
	if adapter == null:
		return {}
	return {id = adapter.ID, name = adapter.DISPLAY_NAME, field_path = adapter.FIELD_PATH}


static func build(id: String, field: Dictionary, lighting: Dictionary = {}) -> Node3D:
	var adapter: Variant = _adapter(id)
	return adapter.build(field, lighting) if adapter != null else null


static func collision_world(id: String, field: Dictionary) -> Dictionary:
	var adapter: Variant = _adapter(id)
	if adapter != null:
		return adapter.collision_world(field)
	return {
		ok = false,
		world = {},
		errors = PackedStringArray(["landscape: unknown id '%s'" % id]),
	}


static func _adapter(id: String) -> Variant:
	for adapter in ADAPTERS:
		if str(adapter.ID) == id:
			return adapter
	return null