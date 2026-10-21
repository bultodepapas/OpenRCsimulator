## LU-22-R2: source-derived aquatic plants on the validated lake shelf.
extends RefCounted

const Surface := preload("res://physics/lake_surface.gd")
const Vegetation := preload("res://scenery/imported_vegetation.gd")
const LEAF_SCENE := preload("res://assets/landscape/pond-plants/nymphaea_leaf.glb")
const FLOWER_SCENE := preload("res://assets/landscape/pond-plants/white_waterlily_flower.glb")
const LEAF_SHADER := preload("res://render/lake/lily_pad.gdshader")
const SEED := 221022
const LILY_ANCHORS := [1, 4, 7, 10, 13, 15, 18]
const REED_ANCHORS := [3, 9, 16]


static func layout(lake: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var pads: Array[Dictionary] = []
	var flowers: Array[Dictionary] = []
	var reeds: Array[Dictionary] = []
	for anchor_index in LILY_ANCHORS:
		var anchor := _anchor(lake, anchor_index)
		if anchor.is_empty():
			continue
		var cluster_count := 0
		for attempt in 80:
			if cluster_count >= 15:
				break
			var tangent_m := rng.randf_range(-5.5, 5.5)
			var inset_m := rng.randf_range(2.4, 7.6)
			var point: Vector2 = anchor.point + anchor.tangent * tangent_m - anchor.outward * inset_m
			var distance := Surface.shore_distance_validated(lake, point.x, point.y)
			if distance < 1.15 or distance > 9.0 or _too_close(pads, point, 0.60):
				continue
			var sample := Surface.sample_terrain_validated(lake, point.x, point.y)
			if str(sample.get("region", "")) != "bed" or float(sample.get("bed_depth_m", 0.0)) < 0.30 \
					or float(sample.get("bed_depth_m", 0.0)) > 1.15:
				continue
			pads.append({"north": point.x, "east": point.y, "shore_m": distance,
				"depth_m": float(sample.bed_depth_m), "diameter_m": rng.randf_range(0.56, 0.94),
				"angle": rng.randf_range(-PI, PI), "tint": rng.randf_range(0.80, 1.18),
				"cluster": anchor_index})
			cluster_count += 1
			if cluster_count == 5 or cluster_count == 12:
				var flower_point: Vector2 = point + anchor.tangent * 0.46
				var flower_shore := Surface.shore_distance_validated(lake, flower_point.x, flower_point.y)
				if flower_shore > 0.75:
					flowers.append({"north": flower_point.x, "east": flower_point.y,
						"shore_m": flower_shore, "angle": rng.randf_range(-PI, PI),
						"cluster": anchor_index})
	for anchor_index in REED_ANCHORS:
		var anchor := _anchor(lake, anchor_index)
		if anchor.is_empty():
			continue
		var cluster_count := 0
		for attempt in 70:
			if cluster_count >= 9:
				break
			var point: Vector2 = anchor.point + anchor.tangent * rng.randf_range(-4.2, 4.2) \
				- anchor.outward * rng.randf_range(0.55, 2.25)
			var distance := Surface.shore_distance_validated(lake, point.x, point.y)
			if distance < 0.45 or distance > 2.5 or _too_close(reeds, point, 0.9):
				continue
			var sample := Surface.sample_terrain_validated(lake, point.x, point.y)
			if str(sample.get("region", "")) != "bed" or float(sample.get("bed_depth_m", 1.0)) > 0.38:
				continue
			reeds.append({"north": point.x, "east": point.y, "shore_m": distance,
				"depth_m": float(sample.bed_depth_m), "ground_down_m": float(sample.ground_down_m),
				"height_m": rng.randf_range(1.00, 1.55), "angle": rng.randf_range(-PI, PI),
				"cluster": anchor_index})
			cluster_count += 1
	return {"pads": pads, "flowers": flowers, "reeds": reeds}


static func build(lake: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "LakePlants"
	var records := layout(lake)
	var wave_data := _wave_data(lake)
	root.set_meta("layout", records)
	var source := LEAF_SCENE.instantiate()
	var source_mesh := _first_mesh(source)
	if source_mesh != null and not records.pads.is_empty():
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_colors = true
		multimesh.use_custom_data = true
		multimesh.mesh = source_mesh.mesh
		multimesh.instance_count = records.pads.size()
		for i in range(records.pads.size()):
			var pad: Dictionary = records.pads[i]
			var scale := float(pad.diameter_m) * 0.5
			var basis := Basis(Vector3.UP, float(pad.angle)).scaled(Vector3.ONE * scale)
			var center := Vector3(float(pad.east), -float(lake.water_level_down_m) + 0.035,
				-float(pad.north))
			multimesh.set_instance_transform(i, Transform3D(basis, center))
			multimesh.set_instance_color(i, Color(float(pad.tint),
				float(pad.tint) * 0.98, float(pad.tint) * 0.88, 1.0))
			multimesh.set_instance_custom_data(i, Color(float(pad.shore_m), 0.0, 0.0, 1.0))
		var instance := MultiMeshInstance3D.new()
		instance.name = "NymphaeaLeaves"
		instance.multimesh = multimesh
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var material := _water_plant_material(lake, wave_data, false, Color.WHITE)
		instance.material_override = material
		root.add_child(instance)
	source.free()
	var flower_source := FLOWER_SCENE.instantiate()
	var flower_part := _first_mesh(flower_source)
	if flower_part != null and not records.flowers.is_empty():
		var flower_mesh := flower_part.mesh.duplicate() as Mesh
		var flower_colors := [Color(0.78, 0.75, 0.61), Color(0.90, 0.69, 0.29)]
		for surface_index in flower_mesh.get_surface_count():
			flower_mesh.surface_set_material(surface_index, _water_plant_material(lake,
				wave_data, true, flower_colors[mini(surface_index, 1)]))
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_custom_data = true
		multimesh.mesh = flower_mesh
		multimesh.instance_count = records.flowers.size()
		for i in range(records.flowers.size()):
			var flower: Dictionary = records.flowers[i]
			multimesh.set_instance_transform(i, Transform3D(Basis(Vector3.UP, float(flower.angle))
				.scaled(Vector3.ONE * 1.25), Vector3(float(flower.east),
				-float(lake.water_level_down_m) + 0.050, -float(flower.north))))
			multimesh.set_instance_custom_data(i, Color(float(flower.shore_m), 0.0, 0.0, 1.0))
		var blossoms := MultiMeshInstance3D.new()
		blossoms.name = "WaterlilyBlossoms"
		blossoms.multimesh = multimesh
		blossoms.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(blossoms)
	flower_source.free()
	var batches := {}
	for i in range(records.reeds.size()):
		var reed: Dictionary = records.reeds[i]
		var origin := Vector3(float(reed.east), -float(reed.ground_down_m), -float(reed.north))
		var transform := Transform3D(Basis(Vector3.UP, float(reed.angle)), origin)
		Vegetation.queue(batches, "reed_aredon", Vegetation.fit_to_height("reed_aredon",
			float(reed.height_m), transform), i + SEED)
	if not batches.is_empty():
		var emergents := Vegetation.build(batches)
		emergents.name = "EmergentReeds"
		_tone_reeds(emergents)
		root.add_child(emergents)
	return root


static func _wave_data(lake: Dictionary) -> Dictionary:
	var water: Array = lake.waves
	var params := PackedVector4Array([Vector4.ZERO, Vector4.ZERO])
	var phases := PackedFloat32Array([0.0, 0.0])
	for i in mini(2, water.size()):
		var wave: Dictionary = water[i]
		params[i] = Vector4(float(wave.amplitude_m), float(wave.wavelength_m),
			float(wave.period_s), float(wave.heading_rad))
		phases[i] = float(wave.phase_rad)
	return {"count": mini(2, water.size()), "params": params, "phases": phases}


static func _water_plant_material(lake: Dictionary, wave_data: Dictionary,
		flower: bool, color: Color) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = LEAF_SHADER
	material.set_shader_parameter("wave_count", int(wave_data.count))
	material.set_shader_parameter("wave_params", wave_data.params)
	material.set_shader_parameter("wave_phase_rad", wave_data.phases)
	material.set_shader_parameter("shore_fade_m", float(lake.wave_bounds.shore_fade_m))
	material.set_shader_parameter("flower_mode", flower)
	material.set_shader_parameter("flower_color", Vector3(color.r, color.g, color.b))
	return material


static func _tone_reeds(root: Node3D) -> void:
	# The retained OBJ has fluorescent green source materials. Keep its four
	# stem/leaf/head surfaces, with muted freshwater colors on local copies.
	var palette := [Color(0.21, 0.12, 0.07), Color(0.18, 0.26, 0.08),
		Color(0.18, 0.31, 0.10), Color(0.25, 0.36, 0.12)]
	for child in root.get_children():
		if not child is MultiMeshInstance3D:
			continue
		var mesh := (child as MultiMeshInstance3D).multimesh.mesh
		for surface_index in range(mesh.get_surface_count()):
			var original := mesh.surface_get_material(surface_index)
			if original is StandardMaterial3D:
				var material := original.duplicate() as StandardMaterial3D
				material.albedo_color = palette[mini(surface_index, palette.size() - 1)]
				material.roughness = 0.86
				mesh.surface_set_material(surface_index, material)


static func _anchor(lake: Dictionary, index: int) -> Dictionary:
	var shore: PackedFloat64Array = lake.shoreline_ne_m
	var bank: PackedFloat64Array = lake.bank_ne_m
	var count := shore.size() / 2
	if count < 3 or index >= count:
		return {}
	var before := posmod(index - 1, count)
	var after := posmod(index + 1, count)
	var point := Vector2(shore[index * 2], shore[index * 2 + 1])
	var tangent := Vector2(shore[after * 2] - shore[before * 2],
		shore[after * 2 + 1] - shore[before * 2 + 1]).normalized()
	var outward := (Vector2(bank[index * 2], bank[index * 2 + 1]) - point).normalized()
	return {"point": point, "tangent": tangent, "outward": outward}


static func _too_close(records: Array[Dictionary], point: Vector2, spacing: float) -> bool:
	for record in records:
		if point.distance_to(Vector2(float(record.north), float(record.east))) < spacing:
			return true
	return false


static func _first_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child in node.get_children():
		var found := _first_mesh(child)
		if found != null:
			return found
	return null
