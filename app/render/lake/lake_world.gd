## LU-25: one scene/session lake definition, explicit default-field boundary and reversible comparison switch.
extends RefCounted
const Loader := preload("res://data/lake_loader.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const GroundSurfaces := preload("res://physics/ground_surfaces.gd")
const Terrain := preload("res://render/lake/lake_terrain.gd")
const LakePlants := preload("res://render/lake/lake_plants.gd")
const WaterEffects := preload("res://render/lake/water_effects.gd")
static var _default_signature := PackedByteArray()

static func options() -> Dictionary:
	var value := OS.get_environment("OPENRC_LAKE")
	var path := Loader.DEFAULT_PATH
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--lake="):
			value = arg.get_slice("=", 1)
		elif arg.begins_with("--lake-file="):
			path = arg.trim_prefix("--lake-file=")
	return {enabled = value.to_lower() not in ["off", "false", "0"], path = path}

static func resolve(field: Dictionary, scenery_options: Dictionary = {}) -> Dictionary:
	if not options().enabled or not bool(scenery_options.get("enabled", true)) \
			or bool(scenery_options.get("file_explicit", false)) or not _matches_default(field):
		return {ok = true, enabled = false, lake = {}, errors = PackedStringArray()}
	var loaded := Loader.load_from(str(options().path))
	if not loaded.ok:
		return {ok = false, enabled = true, lake = {}, errors = loaded.errors}
	var total_amplitude := 0.0
	for wave: Dictionary in loaded.lake.waves:
		total_amplitude += float(wave.amplitude_m)
	if total_amplitude > 0.06:
		return {ok = false, enabled = true, lake = {}, errors = PackedStringArray(["lake: selected renderer supports at most 0.06 m total wave amplitude"])}
	return {ok = true, enabled = true, lake = loaded.lake, errors = PackedStringArray()}

static func _matches_default(field: Dictionary) -> bool:
	if str(field.get("id", "")) != "default":
		return false
	if _default_signature.is_empty():
		var loaded := FieldLoader.load_from(FieldLoader.DEFAULT_PATH)
		if not loaded.ok:
			return false
		_default_signature = _signature(loaded.field)
	return _signature(field) == _default_signature

static func _signature(field: Dictionary) -> PackedByteArray:
	return var_to_bytes([field.get("runway", ""), field.get("pilot", {}), field.get("surfaces", []), field.get("objects", [])])

static func attach(field_node: Node3D, field: Dictionary, ground_material: ShaderMaterial,
		lake: Dictionary, lighting: Dictionary, audio_on := false) -> Node3D:
	if lake.is_empty():
		return null
	var table := GroundSurfaces.load_table()
	var surfaces := GroundSurfaces.build(table.table, field) if table.ok else {ok = false}
	if not surfaces.ok:
		push_error("lake: cannot build matching physical ground surfaces")
		return null
	var node := Terrain.build(lake, ground_material, surfaces.rects, lighting)
	# Bind the already licensed soil maps after building the basin. The geometry
	# source stays byte-identical to the pinned, verified lake bake.
	var bank_material := (node.get_node("Basin") as MeshInstance3D).material_override as ShaderMaterial
	bank_material.set_shader_parameter("rc_dirt_albedo", load("res://assets/landscape/rc-ground/dirt-albedo.jpg"))
	bank_material.set_shader_parameter("rc_dirt_normal", load("res://assets/landscape/rc-ground/dirt-normal.jpg"))
	bank_material.set_shader_parameter("rc_dirt_roughness", load("res://assets/landscape/rc-ground/dirt-roughness.jpg"))
	for parameter: String in ["grass_photo_enabled", "rc_grass_albedo", "rc_grass_normal",
			"rc_grass_roughness", "turf_detail", "turf_detail_strength"]:
		bank_material.set_shader_parameter(parameter, ground_material.get_shader_parameter(parameter))
	Terrain.mask_parameters(ground_material, lake)
	ground_material.set_shader_parameter("lake_mask_mode", 1)
	field_node.add_child(node)
	node.add_child(LakePlants.build(lake))
	field_node.set_meta("lake_context", lake.duplicate(true))
	field_node.set_meta("lake_identity", lake.identity)
	var ambience := WaterEffects.ambient_player(lake, audio_on)
	if ambience != null:
		node.add_child(ambience)
	return node


static func ambience_player(field_node: Node) -> AudioStreamPlayer3D:
	if not is_instance_valid(field_node):
		return null
	return field_node.find_child("LakeWaterAmbience", true, false) as AudioStreamPlayer3D


## The soundscape creates scene-local buses after the field is built. Route this
## field-owned loop to that actual Environment bus once both owners are ready.
static func set_ambience_bus(field_node: Node, bus_name: StringName) -> bool:
	var player: AudioStreamPlayer3D = ambience_player(field_node)
	if player == null or bus_name.is_empty() or AudioServer.get_bus_index(bus_name) < 0:
		return false
	player.bus = bus_name
	return true
