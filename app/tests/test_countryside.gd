## LU-28: bounded static surfaces, world-local light and field eligibility.
extends SceneTree

const Countryside := preload("res://render/landscape_upgrade/countryside.gd")
const FieldBuilder := preload("res://render/field.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const World := preload("res://render/world/world.gd")
const Atmosphere := preload("res://render/atmosphere.gd")
const LightingConfig := preload("res://environment/time_of_day_config.gd")
const Lighting := preload("res://render/time_of_day_lighting.gd")
const CollisionWorld := preload("res://scenery/collision_world.gd")
var checks := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL ", label)


func _run() -> void:
	var previous := {}
	for key: String in ["OPENRC_SCENERY", "OPENRC_SCENERY_FILE", "OPENRC_LANDSCAPE_UPGRADE", "OPENRC_SCENERY_QUALITY"]:
		previous[key] = OS.get_environment(key)
	OS.set_environment("OPENRC_SCENERY", "on")
	OS.set_environment("OPENRC_SCENERY_FILE", "")
	OS.set_environment("OPENRC_LANDSCAPE_UPGRADE", "on")
	OS.set_environment("OPENRC_SCENERY_QUALITY", "high")
	var field: Dictionary = FieldLoader.load_from().field
	var noon := Lighting.snapshot(LightingConfig.preset(LightingConfig.defaults(), "noon").config)
	var night := Lighting.snapshot(LightingConfig.preset(LightingConfig.defaults(), "night").config)
	var built := FieldBuilder.build(field, noon)
	root.add_child(built)
	var plain := built.get_node_or_null("Countryside")
	check("Club attaches countryside", plain != null)
	if plain != null:
		var stats: Dictionary = plain.get_meta("stats")
		check("spatial batch budget", stats.cells > 0 and stats.cells <= 40)
		check("surface triangle budget", stats.triangles > 0 and stats.triangles <= 14000)
		check("agricultural parcels and connected accesses exist", stats.parcels >= 20 and stats.roads >= 10)
		var mat: ShaderMaterial = plain.get_meta("lighting_material")
		check("registered in field light updates", built.get_meta("lighting_materials").has(mat))
		check("registered once in flowing haze collection", World.haze_materials(built).count(mat) == 1)
		var indices := 0
		var static_batches := not plain.is_processing() and not plain.is_physics_processing()
		for child: MeshInstance3D in plain.get_children():
			var arrays := child.mesh.surface_get_arrays(0)
			indices += arrays[Mesh.ARRAY_INDEX].size()
			static_batches = static_batches and child.mesh.surface_get_material(0) == mat \
				and child.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF \
				and not child.is_processing() and not child.is_physics_processing()
		check("all surfaces share material, disable shadows and callbacks", static_batches)
		check("loaded topology matches budget metadata", indices / 3 == stats.triangles)
		for texture_name: String in ["grass_tex", "soil_tex", "asphalt_tex"]:
			var texture: Texture2D = mat.get_shader_parameter(texture_name)
			check(texture_name + " has mipmaps", texture != null and texture.get_image().has_mipmaps())
		var second := Countryside.build(noon)
		var other: ShaderMaterial = second.get_meta("lighting_material")
		check("separate worlds own separate mutable material", other != mat)
		check("time update succeeds", FieldBuilder.update_lighting(built, night))
		check("night sun follows shared field lighting",
			(mat.get_shader_parameter("sun_lin") as Vector3).distance_to(Atmosphere.sun_linear(night)) < .00001)
		check("other world retains noon light",
			(other.get_shader_parameter("sun_lin") as Vector3).distance_to(Atmosphere.sun_linear(noon)) < .00001)
		second.free()
	_check_crop_proxies(field, built.get_node("Scenery"))
	built.free()
	OS.set_environment("OPENRC_SCENERY", "off")
	var disabled := FieldBuilder.build(field)
	check("scenery off omits countryside", disabled.get_node_or_null("Countryside") == null)
	disabled.free()
	OS.set_environment("OPENRC_SCENERY", "on")
	var custom: Dictionary = field.duplicate(true)
	custom.objects = []
	custom.pilot.north += 10.0
	var custom_world := FieldBuilder.build(custom)
	check("ineligible custom field omits countryside", custom_world.get_node_or_null("Countryside") == null)
	custom_world.free()
	OS.set_environment("OPENRC_LANDSCAPE_UPGRADE", "off")
	var baseline := FieldBuilder.build(field)
	check("comparison switch omits countryside", baseline.get_node_or_null("Countryside") == null)
	baseline.free()
	for key: String in previous:
		OS.set_environment(key, previous[key])
	print("LU-28 countryside: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)


func _check_crop_proxies(field: Dictionary, scenery: Node3D) -> void:
	var collision := CollisionWorld.build(field, scenery.get_meta("source_definition"))
	check("expanded scenery collision world builds", collision.ok)
	if not collision.ok:
		return
	var crop_proxies := {}
	for proxy: Dictionary in collision.world.proxies:
		if str(proxy.damage_id).begins_with("prop:countryside-orchard:"):
			crop_proxies[proxy.damage_id] = proxy
	var state: Dictionary = scenery.get_node("ImportedVegetationBatches").get_meta("_imported_vegetation_state")
	var count := 0
	var contained := true
	var retained_source := true
	for record: Dictionary in state.bounds:
		if not str(record.damage_id).begins_with("prop:countryside-orchard:"):
			continue
		count += 1
		retained_source = retained_source and record.asset_id == "forest_leafy_shrub"
		var proxy: Dictionary = crop_proxies.get(record.damage_id, {})
		if proxy.is_empty():
			contained = false
			continue
		var bounds: AABB = record.bounds
		var transform: Transform3D = record.transform
		for corner in 8:
			var point: Vector3 = transform * bounds.get_endpoint(corner)
			contained = contained and -point.z >= proxy.bounds_north_min - .01 \
				and -point.z <= proxy.bounds_north_max + .01 \
				and point.x >= proxy.bounds_east_min - .01 and point.x <= proxy.bounds_east_max + .01 \
				and -point.y >= proxy.bounds_down_min - .01 and -point.y <= proxy.bounds_down_max + .01
	check("all twelve crop shrubs retain render and collision entries", count == 12 and crop_proxies.size() == 12)
	check("crop rows use the retained low shrub source", retained_source)
	check("crop collision bounds contain actual transformed source bounds", contained)
