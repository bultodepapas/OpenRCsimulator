## LU-24–26: full-footprint clearance, stable quality subsets, botanical sharing and real scene integration.
extends SceneTree
const Habitats := preload("res://scenery/botanical_habitats.gd")
const Shapes := preload("res://scenery/botanical_meshes.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const Loader := preload("res://scenery/scenery_loader.gd")
const Mask := preload("res://render/landscape_upgrade/scenery_grass_mask.gd")
const Grass := preload("res://render/near_grass.gd")
const Clock := preload("res://render/shader_clock.gd")
const Scenery := preload("res://scenery/scenery.gd")
var failures := 0
var checks := 0

func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func _initialize() -> void:
	Clock.register()
	var field: Dictionary = FieldLoader.load_from(FieldLoader.DEFAULT_PATH).field
	var scenery: Dictionary = Loader.load_from(Loader.DEFAULT_PATH, field).scenery
	var high := Habitats.layout(field, scenery, "high")
	check("repeatable complete planting", var_to_bytes(high) == var_to_bytes(Habitats.layout(field, scenery, "high")))
	check("new planting has useful density", high.size() > 1300 and high.size() < 1900)
	var ids := {}
	var species := {}
	var excludes := Habitats.exclusions_for(scenery)
	var clearance_ok := true
	for p: Dictionary in high:
		ids[p.seed] = p
		species[p.species] = true
		clearance_ok = clearance_ok and Grass.accepts(p.n, p.e, field, excludes)
	check("all 11 botanical silhouettes appear", species.size() == 11)
	check("all centres clear runway, paths, foundations and pilot", clearance_ok)
	for tier: String in ["balanced", "low"]:
		var plants := Habitats.layout(field, scenery, tier)
		var stable := plants.size() < high.size() and not plants.is_empty()
		for p: Dictionary in plants:
			stable = stable and ids.has(p.seed) and var_to_bytes(ids[p.seed]) == var_to_bytes(p)
		check(tier + " is an exact stable subset", stable)
	var custom := field.duplicate(true)
	custom.id = "other"
	check("unrelated field gets no authored planting", Habitats.layout(custom, scenery, "high").is_empty())
	check("custom scenery gets no bundled planting", Habitats.layout(field, {groups = []}, "high").is_empty())
	for theme: String in ["temperate", "summer", "autumn"]:
		var node := Habitats.build(field, scenery, theme, "high")
		check(theme + " added triangles below 46k", int(node.get_meta("triangles")) < 46000)
		check(theme + " at most 24 plant batches", int(node.get_meta("batches")) <= 24)
		var geometry_ok := true
		var sharing := {}
		for child: Node in node.get_children():
			if child is MultiMeshInstance3D:
				var mesh: Mesh = child.multimesh.mesh
				var plants: Array = child.get_meta("plants")
				var name: String = plants[0].species
				if sharing.has(name):
					geometry_ok = geometry_ok and sharing[name] == mesh
				sharing[name] = mesh
				var aabb := mesh.get_aabb()
				geometry_ok = geometry_ok and aabb.position.y >= -0.00001 and aabb.end.y * 1.08 < 1.0
				geometry_ok = geometry_ok and maxf(absf(aabb.position.x), absf(aabb.end.x)) * 1.08 + 0.07 < Grass.CLEARANCE_M
				geometry_ok = geometry_ok and maxf(absf(aabb.position.z), absf(aabb.end.z)) * 1.08 + 0.07 < Grass.CLEARANCE_M
				var arrays := mesh.surface_get_arrays(0)
				for vertex: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
					geometry_ok = geometry_ok and vertex.is_finite() and Vector2(vertex.x, vertex.z).length() * 1.08 + 0.07 < Grass.CLEARANCE_M
				for normal: Vector3 in arrays[Mesh.ARRAY_NORMAL]:
					geometry_ok = geometry_ok and absf(normal.length() - 1.0) < 0.0001
		check(theme + " finite shared grounded geometry and full radius clearance", geometry_ok)
		node.free()
	var built := Scenery.build(field, scenery, {theme = "", quality = "high", audio = false, birds = false})
	check("production scenery owns planting", built.get_node_or_null("BotanicalHabitats") != null)
	check("production stats retain all botanical plants", int(built.get_meta("stats").botanical_plants) == high.size())
	built.free()
	print("LU-24–26 botanicals: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
