extends RefCounted

const LakeLoader := preload("res://data/lake_loader.gd")
const LakeSurface := preload("res://physics/lake_surface.gd")
const LakeCollision := preload("res://sim/lake_collision.gd")
const SceneryCollision := preload("res://sim/scenery_collision.gd")

var _lake: Dictionary = {}
var _collision_world: Dictionary = {}
var sim: Object
var aircraft: Dictionary = {}
var soft_hull_contacts: bool = false
var _prop_disc: Dictionary = {}

func set_lake_context(normalized_lake: Dictionary) -> bool:
	if normalized_lake.is_empty():
		_lake = {}
		return true
	if not LakeSurface.is_valid_definition(normalized_lake):
		return false
	var expected_identity: String = LakeLoader.identity(normalized_lake)
	if expected_identity.is_empty() or expected_identity != str(normalized_lake.identity):
		return false
	_lake = normalized_lake.duplicate(true)
	return true

func lake_context() -> Dictionary:
	return _lake.duplicate(true)

func _lake_first_hit(previous: PackedFloat64Array, candidate: PackedFloat64Array,
		next_tick: int) -> LakeCollision.WaterEvent:
	if _lake.is_empty() or not aircraft.get("ok", false):
		return null
	return LakeCollision.first_hit(_lake, previous, candidate, aircraft.model.crash_hull,
		aircraft.model.get("landing_gear", {}), next_tick, sim.dt(), sim.mass, sim.inertia,
		soft_hull_contacts, _prop_disc)

func _lake_identity() -> String:
	return str(_lake.get("identity", ""))
