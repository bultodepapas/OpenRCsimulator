extends SceneTree
const After = preload("res://scenery/scenery.gd")
const Before = preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/landscape-perf/baseline_scenery.gd")
const Field = preload("res://data/field_loader.gd")
const Loader = preload("res://scenery/scenery_loader.gd")
const Lake = preload("res://data/lake_loader.gd")
var field: Dictionary
var scenery: Dictionary
var lake: Dictionary
var geometry_hash := ""

func run_one(fast: bool) -> Dictionary:
	var opts := {audio=false, birds=false, quality="high", theme=""}
	var root: Node3D = After.build(field, scenery, opts, {}, lake) if fast \
		else Before.build(field, scenery, opts, {}, lake)
	var stats: Dictionary = root.get_meta("stats").duplicate(true)
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	for child: Node in root.get_children():
		if child is MeshInstance3D and str(child.name).begins_with("cell_"):
			for surface in child.mesh.get_surface_count():
				var arrays: Array = child.mesh.surface_get_arrays(surface)
				for slot in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_COLOR]:
					hash.update(arrays[slot].to_byte_array())
	var digest := hash.finish().hex_encode()
	if geometry_hash.is_empty(): geometry_hash = digest
	assert(digest == geometry_hash)
	root.free()
	return stats

func _initialize() -> void:
	preload("res://render/shader_clock.gd").register()
	field = Field.load_from().field
	scenery = Loader.load_from(Loader.DEFAULT_PATH, field).scenery
	lake = Lake.load_from().lake
	# Both static caches must be populated; compare rebuilds, not cold startup.
	run_one(false)
	run_one(true)
	var rows: Array = []
	for pair in 5:
		var before: Dictionary
		var after: Dictionary
		if pair % 2 == 0:
			before = run_one(false)
			after = run_one(true)
		else:
			after = run_one(true)
			before = run_one(false)
		assert(before.botanical_plants == after.botanical_plants)
		assert(before.botanical_triangles == after.botanical_triangles)
		rows.append({before=before, after=after})
	var report := {format="landscape-rebuild-pairs-v1", geometry_sha256=geometry_hash, pairs=rows}
	var file := FileAccess.open("C:/DEVELOPMENT/OpenRCsimulator/tmp/landscape-perf/build-pairs.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	print("Paired rebuilds complete; geometry SHA256 ", geometry_hash)
	quit()
