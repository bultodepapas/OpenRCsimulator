extends SceneTree

const Ground := preload("res://render/ground.gd")
const GrassDetail := preload("res://render/grass_ground_material.gd")
const RcDetail := preload("res://render/rc_ground_material.gd")
const Track := preload("res://vehicles/ground/airfield_track_view.gd")
const Field := preload("res://data/field_loader.gd")
const Course := preload("res://physics/ground_vehicle/airfield_course.gd")

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var previous_quality: String = OS.get_environment("OPENRC_GRASS_QUALITY")
	# An absent variable reads as empty in Godot. The empty/default branch and
	# an unrelated value must both leave the candidate photo maps unbound.
	OS.set_environment("OPENRC_GRASS_QUALITY", "")
	var ordinary := Ground.grass_material()
	var independent := Ground.grass_material()
	_check("ground builds own separate material instances", ordinary != independent)
	_check_photo_disabled(ordinary, "default ground")
	_check_photo_disabled(independent, "independent default ground")
	_check("ordinary ground has no RC soil or track coverage", ordinary.get_shader_parameter("rc_surface_enabled") != true
		and ordinary.get_shader_parameter("rc_track_surface") != true)
	_check("ordinary ground retains existing turf detail", ordinary.get_shader_parameter("turf_detail") != null
		and ordinary.get_shader_parameter("turf_detail_strength") == 1.0)
	_check("ordinary ground leaves all dirt samplers unbound",
		ordinary.get_shader_parameter("rc_dirt_albedo") == null
		and ordinary.get_shader_parameter("rc_dirt_normal") == null
		and ordinary.get_shader_parameter("rc_dirt_roughness") == null)

	var surfaces: Array[Dictionary] = [
		{"type": "rough", "center_north": 0.0, "center_east": 0.0, "length_east_west": 40000.0, "width_north_south": 40000.0},
		{"type": "runway", "center_north": 6.0, "center_east": 0.0, "length_east_west": 100.0, "width_north_south": 12.0},
	]
	_check("grass material retains consolidated coverage and terrain masks", Ground.configure_surfaces(ordinary, surfaces)
		and ordinary.get_shader_parameter("surface_count") == 1
		and ordinary.get_shader_parameter("terrain_surface_count") == 1
		and ordinary.get_shader_parameter("terrain_surface_kinds")[0] == 2)
	var terrain_rects: PackedVector4Array = ordinary.get_shader_parameter("terrain_surface_rects")
	_check("terrain mask keeps the renderer runway rectangle", terrain_rects.size() == Ground.MAX_SURFACES
		and terrain_rects[0] == Vector4(0.0, -6.0, 50.0, 6.0))
	var runway := Ground.surface_material(ordinary, "runway", Vector2(0.0, -6.0), Vector2(50.0, 6.0))
	_check("cloned default runway material retains disabled photo binding and terrain mask",
		runway != ordinary
		and runway.get_shader_parameter("grass_photo_enabled") != true
		and runway.get_shader_parameter("rc_dirt_albedo") == null
		and runway.get_shader_parameter("surface_count") == ordinary.get_shader_parameter("surface_count")
		and runway.get_shader_parameter("terrain_surface_rects") == terrain_rects)
	runway.set_shader_parameter("grass_photo_enabled", false)
	_check("a cloned default surface keeps the source photo binding disabled", ordinary.get_shader_parameter("grass_photo_enabled") != true)

	var rc_ground := Ground.grass_material()
	RcDetail.configure(rc_ground)
	_check("RC binder still enables its existing surface route", rc_ground.get_shader_parameter("rc_surface_enabled") == true)
	_check("RC material leaves the optional grass photo branch disabled", rc_ground.get_shader_parameter("grass_photo_enabled") != true)
	_check_six_rc_maps(rc_ground)
	var loaded: Dictionary = Field.load_from()
	var built: Dictionary = Course.build(loaded)
	_check("default RC course loads for the existing dirt-mask path", bool(built.get("ok", false)))
	if bool(built.get("ok", false)):
		var road := func(north: float, east: float) -> Dictionary: return Course.sample(built.course, north, east)
		var baseline := Track.build(built.course, road)
		var proposed := Track.build(built.course, road, rc_ground)
		var baseline_surface := baseline.get_node_or_null("DirtLoopSurface") as MeshInstance3D
		var proposed_surface := proposed.get_node_or_null("DirtLoopSurface") as MeshInstance3D
		var track_material := proposed_surface.material_override as ShaderMaterial if proposed_surface != null else null
		_check("RC track clone keeps private dirt coverage and six grass/dirt binders",
			track_material != null
			and track_material.get_shader_parameter("rc_track_surface") == true
			and track_material.get_shader_parameter("rc_dirt_albedo") != null
			and track_material.get_shader_parameter("rc_dirt_normal") != null
			and track_material.get_shader_parameter("rc_dirt_roughness") != null
			and track_material.get_shader_parameter("rc_grass_albedo") != null
			and track_material.get_shader_parameter("rc_grass_normal") != null
			and track_material.get_shader_parameter("rc_grass_roughness") != null)
		_check("track material clone preserves exact coverage mesh arrays",
			baseline_surface != null and proposed_surface != null
			and _same_mesh_arrays(baseline_surface.mesh, proposed_surface.mesh))
		_check("building the track cannot turn the shared RC field into a dirt surface",
			rc_ground.get_shader_parameter("rc_track_surface") != true)
		baseline.free()
		proposed.free()

	OS.set_environment("OPENRC_GRASS_QUALITY", "unrecognized")
	var unrecognized := Ground.grass_material()
	_check_photo_disabled(unrecognized, "unrecognized-value ground")
	_check("unrecognized-value ground keeps RC dirt samplers unbound",
		unrecognized.get_shader_parameter("rc_dirt_albedo") == null
		and unrecognized.get_shader_parameter("rc_dirt_normal") == null
		and unrecognized.get_shader_parameter("rc_dirt_roughness") == null)

	OS.set_environment("OPENRC_GRASS_QUALITY", "enhanced")
	var enhanced := Ground.grass_material()
	var enhanced_independent := Ground.grass_material()
	_check("enhanced ground builds private material instances", enhanced != enhanced_independent)
	_check("enhanced binder enables the grass photo branch", enhanced.get_shader_parameter("grass_photo_enabled") == true)
	_check_grass_maps(enhanced)
	_check("enhanced grass still has no RC soil or track coverage", enhanced.get_shader_parameter("rc_surface_enabled") != true
		and enhanced.get_shader_parameter("rc_track_surface") != true)
	_check("enhanced grass leaves all dirt samplers unbound",
		enhanced.get_shader_parameter("rc_dirt_albedo") == null
		and enhanced.get_shader_parameter("rc_dirt_normal") == null
		and enhanced.get_shader_parameter("rc_dirt_roughness") == null)
	_check("binding an enhanced material does not mutate its peer", enhanced_independent.get_shader_parameter("grass_photo_enabled") == true
		and enhanced_independent.get_shader_parameter("rc_surface_enabled") != true
		and enhanced_independent.get_shader_parameter("rc_dirt_albedo") == null)
	_check("enhanced material retains consolidated coverage and terrain masks", Ground.configure_surfaces(enhanced, surfaces)
		and enhanced.get_shader_parameter("surface_count") == 1
		and enhanced.get_shader_parameter("terrain_surface_count") == 1
		and enhanced.get_shader_parameter("terrain_surface_kinds")[0] == 2)
	var enhanced_runway := Ground.surface_material(enhanced, "runway", Vector2(0.0, -6.0), Vector2(50.0, 6.0))
	_check("cloned enhanced runway keeps photo maps and terrain masks",
		enhanced_runway != enhanced
		and enhanced_runway.get_shader_parameter("grass_photo_enabled") == true
		and enhanced_runway.get_shader_parameter("rc_grass_albedo") != null
		and enhanced_runway.get_shader_parameter("rc_dirt_albedo") == null
		and enhanced_runway.get_shader_parameter("terrain_surface_rects") == enhanced.get_shader_parameter("terrain_surface_rects"))
	enhanced_runway.set_shader_parameter("grass_photo_enabled", false)
	_check("changing an enhanced surface clone cannot mutate its source", enhanced.get_shader_parameter("grass_photo_enabled") == true)

	OS.set_environment("OPENRC_GRASS_QUALITY", previous_quality)
	print("Grass ground material: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures else 0)


func _check_photo_disabled(material: ShaderMaterial, label: String) -> void:
	_check("%s leaves the photo branch disabled" % label, material.get_shader_parameter("grass_photo_enabled") != true)
	_check("%s does not bind the optional 2K grass maps" % label,
		material.get_shader_parameter("rc_grass_albedo") == null
		and material.get_shader_parameter("rc_grass_normal") == null
		and material.get_shader_parameter("rc_grass_roughness") == null)


func _check_grass_maps(material: ShaderMaterial) -> void:
	for parameter: String in ["rc_grass_albedo", "rc_grass_normal", "rc_grass_roughness"]:
		_check_texture(material.get_shader_parameter(parameter), parameter)


func _check_six_rc_maps(material: ShaderMaterial) -> void:
	for parameter: String in ["rc_dirt_albedo", "rc_dirt_normal", "rc_dirt_roughness", "rc_grass_albedo", "rc_grass_normal", "rc_grass_roughness"]:
		_check_texture(material.get_shader_parameter(parameter), "RC " + parameter)


func _check_texture(value: Variant, label: String) -> void:
	var texture := value as Texture2D
	_check("%s binds the retained mipmapped 2K texture" % label,
		texture != null and texture.get_width() == 2048 and texture.get_height() == 2048
		and texture.get_image() != null and texture.get_image().has_mipmaps())


func _same_mesh_arrays(a: Mesh, b: Mesh) -> bool:
	if a.get_surface_count() != b.get_surface_count():
		return false
	for surface: int in a.get_surface_count():
		var aa := a.surface_get_arrays(surface)
		var ba := b.surface_get_arrays(surface)
		for slot: int in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_COLOR, Mesh.ARRAY_INDEX]:
			if var_to_bytes(aa[slot]) != var_to_bytes(ba[slot]):
				return false
	return true


func _check(label: String, ok: bool) -> void:
	_checks += 1
	print(("PASS: " if ok else "FAIL: ") + label)
	if not ok:
		_failures += 1
