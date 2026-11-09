## SC-13-R1: one static CC0 tractor, fitted inside the unchanged gameplay proxy.
## No asset preload/cache: scenery-off, Low and Green keep its mesh/textures unloaded.
extends RefCounted

const MESH_PATH := "res://assets/scenery/farm_tractor/tractor.res"
const DAMAGE_ID := "prop:tractor:00"
const MAX_SOURCE_TRIANGLES := 4000
const MAX_SURFACES := 5
static var _canonical_definition := PackedByteArray()


## Match the complete normalized bundled scenery, not a user file's group name.
static func eligible(scenery: Dictionary) -> bool:
	if _canonical_definition.is_empty():
		var field_loader: Script = load("res://data/field_loader.gd")
		var loader: Script = load("res://scenery/scenery_loader.gd")
		var field_result: Dictionary = field_loader.load_from()
		if not field_result.ok: return false
		var loaded: Dictionary = loader.load_from(loader.DEFAULT_PATH, field_result.field)
		if not loaded.ok: return false
		_canonical_definition = var_to_bytes(loaded.scenery)
	return var_to_bytes(scenery) == _canonical_definition


static func create(transform: Transform3D, envelope: Vector3) -> MeshInstance3D:
	var mesh := load(MESH_PATH) as ArrayMesh
	if mesh == null: return null
	var bounds := mesh.get_aabb()
	if bounds.size.x > envelope.x + 0.001 or bounds.size.y > envelope.y + 0.001 \
			or bounds.size.z > envelope.z + 0.001 or absf(bounds.position.y) > 0.001 \
			or absf(bounds.get_center().x) > 0.001 or absf(bounds.get_center().z) > 0.001:
		push_error("Imported tractor escapes its existing collision envelope")
		return null
	var node := MeshInstance3D.new()
	node.name = "FarmTractor"
	node.mesh = mesh
	node.transform = transform
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	node.process_mode = Node.PROCESS_MODE_DISABLED
	node.set_meta("damage_motion_id", DAMAGE_ID)
	return node


static func apply_damage(scenery: Node3D, damage: Dictionary) -> void:
	var node := scenery.get_node_or_null("FarmTractor") as MeshInstance3D
	if node != null:
		node.visible = damage.get(DAMAGE_ID, {}).get("state", "") != "broken"
