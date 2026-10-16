extends SceneTree
const Ground = preload("res://render/ground.gd")
const Detail = preload("res://render/rc_ground_material.gd")
const Track = preload("res://vehicles/ground/airfield_track_view.gd")
const Field = preload("res://data/field_loader.gd")
const Course = preload("res://physics/ground_vehicle/airfield_course.gd")
var failures := 0
func check(ok: bool, label: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + label)
	if not ok: failures += 1
func _initialize() -> void:
	var ordinary := Ground.grass_material()
	var candidate := Ground.grass_material()
	Detail.configure(candidate)
	check(ordinary.get_shader_parameter("rc_surface_enabled") != true, "ordinary field does not opt into RC detail")
	check(candidate.get_shader_parameter("rc_surface_enabled") == true, "RC field opts in privately")
	var loaded := Field.load_from()
	var built := Course.build(loaded)
	check(built.ok, "default course loads")
	if not built.ok:
		quit(1)
		return
	var road := func(n: float, e: float) -> Dictionary: return Course.sample(built.course, n, e)
	var baseline := Track.build(built.course, road)
	var proposed := Track.build(built.course, road, candidate)
	var old_surface := baseline.get_node("DirtLoopSurface") as MeshInstance3D
	var new_surface := proposed.get_node("DirtLoopSurface") as MeshInstance3D
	var old_arrays := old_surface.mesh.surface_get_arrays(0)
	var new_arrays := new_surface.mesh.surface_get_arrays(0)
	for slot in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_COLOR, Mesh.ARRAY_INDEX]:
		check(var_to_bytes(old_arrays[slot]) == var_to_bytes(new_arrays[slot]), "material change preserves exact mesh array %d" % slot)
	var material := new_surface.material_override as ShaderMaterial
	check(material != candidate and material.shader == candidate.shader, "track privately duplicates the shared surface shader")
	check(material.get_shader_parameter("rc_track_surface") == true, "track uses coverage metadata")
	check(material.get_shader_parameter("terrain_relief_enabled") == false, "track retains sampled normals without applying micro-relief twice")
	check(candidate.get_shader_parameter("rc_track_surface") != true, "track setup cannot turn ordinary grass into dirt")
	check(proposed.find_children("*", "CollisionObject3D", true, false).is_empty(), "detail creates no collision objects")
	for map_name in ["rc_dirt_albedo", "rc_dirt_normal", "rc_dirt_roughness", "rc_grass_albedo", "rc_grass_normal", "rc_grass_roughness"]:
		var texture: Texture2D = material.get_shader_parameter(map_name)
		check(texture != null and texture.get_width() == 2048 and texture.get_height() == 2048, "%s binds the 2K asset" % map_name)
		var image := texture.get_image()
		check(image != null and image.has_mipmaps(), "%s has imported mipmaps" % map_name)
	baseline.free()
	proposed.free()
	print("RC ground material: %d failures" % failures)
	quit(1 if failures else 0)
