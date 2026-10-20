extends SceneTree

const HillSettlements := preload("res://render/landscape_upgrade/hill_settlements.gd")
const PROFILE_PATH := "res://data/fields/mountains.json"
const LAYOUT_PATH := "res://data/scenery/hill_settlements.json"

var _checks := 0
var _failures := 0


func _initialize() -> void:
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_PATH))
	var built: Node3D = HillSettlements.build()
	var houses: Array = built.get_meta("houses", [])
	var stats: Dictionary = built.get_meta("stats", {})
	_check(houses.size() == 12, "twelve metadata entries")
	_check(stats.get("clusters", 0) == 3 and stats.get("houses", 0) == 12, "three clusters and twelve houses")
	_check(built.get_meta("profile_sha256", "") == FileAccess.get_sha256(PROFILE_PATH), "ridge source SHA is retained")
	_check(layout.get("profile_sha256", "") == FileAccess.get_sha256(PROFILE_PATH), "generated layout matches ridge source")
	_check(built.get_child_count() == 1 and built.get_child(0) is MeshInstance3D, "one static batched mesh")
	if built.get_child_count() == 1 and built.get_child(0) is MeshInstance3D:
		var instance := built.get_child(0) as MeshInstance3D
		var mesh := instance.mesh as ArrayMesh
		_check(mesh != null and mesh.get_surface_count() == 1, "one prefab-color surface")
		_check(instance.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "distant batch does not cast shadows")
		if mesh != null and mesh.get_surface_count() == 1:
			var arrays := mesh.surface_get_arrays(0)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			_check(vertices.size() / 3 == int(stats.get("triangles", 0)), "triangle metadata matches batched geometry")
	var ids := {}
	for value: Variant in houses:
		if not value is Dictionary:
			_check(false, "metadata entries are dictionaries")
			continue
		var house: Dictionary = value
		var position: Vector3 = house.get("position", Vector3.ZERO)
		var basis: Basis = house.get("basis", Basis.IDENTITY)
		var north := -position.z
		_check(not ids.has(house.get("id", "")), "house IDs are unique")
		ids[house.get("id", "")] = true
		_check(north >= 2000.0 and north <= 4500.0 and position.x >= -2500.0 and position.x <= 2500.0,
			"house lies inside the authored hill region")
		_check(absf(basis.x.length() - 1.0) < 0.0001 and absf(basis.y.length() - 1.0) < 0.0001
			and absf(basis.z.length() - 1.0) < 0.0001, "house basis is normalized")
		_check(basis.x.cross(basis.y).dot(basis.z) > 0.999, "house basis remains right-handed")
	var second: Node3D = HillSettlements.build()
	if built.get_child_count() == 1 and second.get_child_count() == 1:
		var first_mesh := (built.get_child(0) as MeshInstance3D).mesh as ArrayMesh
		var second_mesh := (second.get_child(0) as MeshInstance3D).mesh as ArrayMesh
		if first_mesh != null and second_mesh != null and first_mesh.get_surface_count() == 1 and second_mesh.get_surface_count() == 1:
			var first_arrays := first_mesh.surface_get_arrays(0)
			var second_arrays := second_mesh.surface_get_arrays(0)
			_check(first_arrays[Mesh.ARRAY_VERTEX] == second_arrays[Mesh.ARRAY_VERTEX], "build is deterministic")
		else:
			_check(false, "both builds have a batched mesh")
	else:
		_check(false, "both builds have a batched mesh")
	built.free()
	second.free()
	print("hill settlements: %d checks, %d failed; stats=%s" % [_checks, _failures, stats])
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("ok ", label)
	else:
		_failures += 1
		push_error("FAIL " + label)
