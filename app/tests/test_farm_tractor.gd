## SC-13-R1: portable PBR asset, unchanged contacts and bounded one-placement routing.
extends SceneTree
const Tractor := preload("res://scenery/farm_tractor.gd")
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
	check("loading tractor code does not preload its asset", not ResourceLoader.has_cached(Tractor.MESH_PATH))
	if OS.get_cmdline_user_args().has("--low-only"):
		_check_low()
	else:
		_asset()
		if not OS.get_cmdline_user_args().has("--asset-only"):
			_integration()
	print("Farm tractor: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)


func _asset() -> void:
	var mesh := load(Tractor.MESH_PATH) as ArrayMesh
	check("self-contained tractor resource loads", mesh != null)
	if mesh == null: return
	check("five PBR material surfaces", mesh.get_surface_count() == 5)
	check("no external resource references in derivative", ResourceLoader.get_dependencies(Tractor.MESH_PATH).is_empty())
	var box := mesh.get_aabb()
	check("uniformly fitted mesh remains in the existing gameplay envelope", box.size.x <= 2.351 and box.size.y <= 2.351 and box.size.z <= 3.601)
	check("grounded and centred", absf(box.position.y) < 0.001 and absf(box.get_center().x) < 0.001 and absf(box.get_center().z) < 0.001)
	var serialized: Array = mesh.get("_surfaces")
	var triangles := 0
	var lod_count := 0
	var textures := 0
	var wheel_samples := 0
	var expected_wheel_samples := 0
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		triangles += indices.size() / 3
		check("complete normal channel %d" % surface, arrays[Mesh.ARRAY_NORMAL].size() == vertices.size())
		var material := mesh.surface_get_material(surface) as StandardMaterial3D
		check("opaque source material %d" % surface, material != null and material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED)
		if material == null: continue
		print("Tractor surface ", surface, " ", material.resource_name, " vertices=", vertices.size(), " triangles=", indices.size() / 3, " lods=", serialized[surface].get("lods", []).size() / 2)
		if material.albedo_texture != null:
			check("textured body retains UVs and normal mapping", arrays[Mesh.ARRAY_TEX_UV].size() == vertices.size() and material.normal_enabled)
		for slot in [BaseMaterial3D.TEXTURE_ALBEDO, BaseMaterial3D.TEXTURE_NORMAL, BaseMaterial3D.TEXTURE_METALLIC, BaseMaterial3D.TEXTURE_ROUGHNESS]:
			var texture := material.get_texture(slot)
			if texture == null: continue
			textures += 1
			var image := texture.get_image()
			check("portable mip-filtered 1K texture", image != null and not image.is_empty() and image.has_mipmaps() and image.get_width() <= 1024 and image.get_height() <= 1024)
		var rendered_sets: Array[PackedInt32Array] = [indices]
		var decoded := _saved_lods(serialized[surface])
		for size: float in decoded:
			var lod_indices: PackedInt32Array = decoded[size]
			check("LOD %d/%f reduces submitted geometry" % [surface, size], lod_indices.size() < indices.size() and lod_indices.size() >= 12 and size > 0)
			rendered_sets.append(lod_indices)
			lod_count += 1
		if material.resource_name.contains("tire"):
			expected_wheel_samples += rendered_sets.size() * 4
			var minimum_z := INF
			var maximum_z := -INF
			for index: int in indices:
				minimum_z = minf(minimum_z, vertices[index].z)
				maximum_z = maxf(maximum_z, vertices[index].z)
			print("Rendered tire Z range: ", minimum_z, " .. ", maximum_z)
			for rendered: PackedInt32Array in rendered_sets:
				var minima := [INF, INF, INF, INF]
				for index: int in rendered:
					var vertex := vertices[index]
					var region := (0 if vertex.x < 0.0 else 1) + (0 if vertex.z < 0.0 else 2)
					minima[region] = minf(float(minima[region]), vertex.y)
				for minimum: float in minima:
					check("rendered wheel bottom stays grounded at every LOD: " + str(minima), is_finite(minimum) and absf(minimum) <= 0.01)
					wheel_samples += 1
	check("bounded source geometry", triangles > 0 and triangles <= Tractor.MAX_SOURCE_TRIANGLES)
	check("multiple saved material LOD buffers", lod_count >= 2)
	check("every retained tire index set covers all four grounded wheels", wheel_samples >= 4 and wheel_samples == expected_wheel_samples)
	check("all four PBR texture bindings survive save/load", textures == 4)
	var info: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/scenery/farm_tractor/tractor.json"))
	check("metadata agrees with the derivative", int(info.triangles) == triangles and int(info.surfaces) == mesh.get_surface_count())
	check("source credit and licence ship with the asset", str(info.author) == "Grab3D" and str(info.license) == "CC0-1.0" and FileAccess.get_file_as_string("res://assets/scenery/farm_tractor/LICENSE.txt").begins_with("CC0 1.0 Universal"))
	if OS.get_cmdline_user_args().has("--asset-only"): return
	var baker: Script = load("res://../tools/scenery/bake_farm_tractor.gd")
	var original: String = baker.signature(mesh)
	check("canonical mesh/material signature matches metadata", original == str(info.content_sha256))
	var altered := mesh.duplicate(false) as ArrayMesh
	var altered_material := mesh.surface_get_material(0).duplicate(false) as StandardMaterial3D
	altered.surface_set_material(0, altered_material)
	for setting: String in ["metallic_texture_channel", "roughness_texture_channel", "texture_filter"]:
		var old_value: int = altered_material.get(setting)
		altered_material.set(setting, (old_value + 1) % 4)
		check(setting + " mutation changes regeneration signature", str(baker.signature(altered)) != original)
		altered_material.set(setting, old_value)
	altered_material.uv1_offset = Vector3(0.1, 0.2, 0.0)
	check("UV transform mutation changes regeneration signature", str(baker.signature(altered)) != original)


## Read the actual saved index sets, as procedural_skin.gd::_lods does; an
## ImporterMesh.from_mesh round trip would silently omit these ArrayMesh LODs.
func _saved_lods(surface: Dictionary) -> Dictionary:
	var records: Array = surface.get("lods", [])
	check("saved LOD records have size/buffer pairs", records.size() % 2 == 0)
	var stride := 2 if int(surface.vertex_count) <= 65536 else 4
	var result := {}
	for i in range(0, records.size(), 2):
		var bytes: PackedByteArray = records[i + 1]
		check("saved LOD indices are complete", bytes.size() % (stride * 3) == 0)
		var indices := PackedInt32Array()
		for j in bytes.size() / stride: indices.append(bytes.decode_u16(j * stride) if stride == 2 else bytes.decode_u32(j * stride))
		result[float(records[i])] = indices
	return result


func _inputs() -> Dictionary:
	load("res://render/shader_clock.gd").register()
	var field_loader: Script = load("res://data/field_loader.gd")
	var loader: Script = load("res://scenery/scenery_loader.gd")
	var field: Dictionary = field_loader.load_from().field
	return {field = field, scenery = loader.load_from(loader.DEFAULT_PATH, field).scenery}


func _check_low() -> void:
	var inputs := _inputs()
	var scenery_script: Script = load("res://scenery/scenery.gd")
	var built: Node3D = scenery_script.build(inputs.field, inputs.scenery, {theme = "", quality = "low", audio = false, birds = false, farm_tractor = true})
	check("Low uses a simple batched tractor", built.get_node_or_null("FarmTractor") == null)
	var visible := {}
	for child: Node in built.get_children():
		for entry: Dictionary in child.get_meta("damage_ranges", []):
			if int(entry.end) > int(entry.first): visible[str(entry.id)] = int(entry.end) - int(entry.first)
	var categories := {bench = 0, tractor = 0, person = 0}
	for group: Dictionary in inputs.scenery.groups:
		if str(group.type) != "instances": continue
		for index in group.placements.size():
			var prefab := str(group.placements[index].prefab)
			var category := "person" if prefab.begins_with("person_") else prefab
			if categories.has(category):
				categories[category] += 1
				var id := "prop:%s:%02d" % [group.id, index]
				check("Low renders physical %s %s:%d" % [prefab, group.id, index], visible.has(id))
				if category == "person" and visible.has(id):
					var kit: Variant = load("res://scenery/mesh_kit.gd").new()
					var parts: Array = load("res://scenery/prefabs.gd").build(prefab, kit,
						int(group.placements[index].seed), "summer")
					var vertices: int = kit.verts.size()
					for part: Dictionary in parts: vertices += part.kit.verts.size()
					check("Low retains the complete static person including arms", visible[id] == vertices)
	for category: String in categories:
		check("Low fixture includes " + category, categories[category] > 0)
	check("Low does not load tractor resources or textures", not ResourceLoader.has_cached(Tractor.MESH_PATH))
	built.free()


func _integration() -> void:
	var inputs := _inputs()
	var script: Script = load("res://scenery/scenery.gd")
	var source_budget: Script = load("res://tests/scene_source_budget.gd")
	var opts := {theme = "", quality = "high", audio = false, birds = false, farm_tractor = true}
	check("bundled definition is eligible", Tractor.eligible(inputs.scenery))
	var changed: Dictionary = inputs.scenery.duplicate(true)
	changed.theme = "summer"
	check("custom scenery with the same tractor name is ineligible", not Tractor.eligible(changed))
	var built: Node3D = script.build(inputs.field, inputs.scenery, opts)
	var node := built.get_node_or_null("FarmTractor") as MeshInstance3D
	check("exactly the nearest placement uses the imported tractor", node != null and int(built.get_meta("stats").get("farm_tractor_instances", 0)) == 1)
	if node != null:
		check("original transform and damage identity retained", node.transform == script._placement_xf(-27.0, 326.0, 250.0) and node.get_meta("damage_motion_id") == Tractor.DAMAGE_ID)
		check("no callbacks, shadows or range-based disappearance", node.get_script() == null and node.process_mode == Node.PROCESS_MODE_DISABLED and node.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and node.visibility_range_end == 0.0)
		var pristine := node.mesh
		var law: Script = load("res://sim/scenery_damage.gd")
		var impact_state: String = law.impact_state("metal", 16.0)
		check("retained metal policy produces a mark", impact_state == "marked")
		script.apply_damage(built, {Tractor.DAMAGE_ID: {state = impact_state}})
		check("normal metal impact keeps the tractor visible", node.visible)
		var scars: Node3D = load("res://render/crash/scenery_damage.gd").new()
		root.add_child(scars)
		scars._spawn(Tractor.DAMAGE_ID, {state = impact_state, profile = "metal", point_ned = [-27.0, 326.0, -1.0], normal_ned = [1.0, 0.0, 0.0], velocity_ned = [0.0, 0.0, 0.0]}, 3.0)
		check("normal impact retains the existing scar presentation", scars.get_child_count() == 1 and scars.get_child(0).get_child_count() > 0 and node.visible)
		scars.free()
		script.apply_damage(built, {Tractor.DAMAGE_ID: {state = "broken"}})
		check("damage presentation targets the original id", not node.visible)
		script.apply_damage(built, {})
		check("reset restores original appearance and resource", node.visible and node.mesh == pristine)
	check("existing source-budget allowances are respected", source_budget.failures(built).is_empty())
	check("imported prop is charged to the existing cell budget", source_budget.subsystem("FarmTractor") == "cells")
	var attribution: Script = load("res://../tools/scenery/attribute_views.gd")
	check("per-view attribution charges the same prop group", attribution.SCENERY_PATTERNS.get("FarmTractor") == "scenery_cells")
	built.free()
	opts.farm_tractor = false
	built = script.build(inputs.field, inputs.scenery, opts)
	check("comparison off retains the procedural path", built.get_node_or_null("FarmTractor") == null)
	built.free()
	opts.farm_tractor = true
	opts.file_explicit = true
	built = script.build(inputs.field, inputs.scenery, opts)
	check("explicit scenery files keep their own visual choice", built.get_node_or_null("FarmTractor") == null)
	built.free()
	var collision: Script = load("res://scenery/collision_setup.gd")
	var saved := {}
	for key: String in ["OPENRC_FARM_TRACTOR", "OPENRC_SCENERY", "OPENRC_SCENERY_QUALITY", "OPENRC_LANDSCAPE_UPGRADE", "OPENRC_SCENERY_FILE"]:
		saved[key] = OS.get_environment(key)
	OS.set_environment("OPENRC_SCENERY", "on")
	OS.set_environment("OPENRC_SCENERY_QUALITY", "high")
	OS.set_environment("OPENRC_LANDSCAPE_UPGRADE", "on")
	OS.set_environment("OPENRC_SCENERY_FILE", "")
	OS.set_environment("OPENRC_FARM_TRACTOR", "on")
	var on_world: Dictionary = collision.build(inputs.field)
	OS.set_environment("OPENRC_FARM_TRACTOR", "off")
	var off_world: Dictionary = collision.build(inputs.field)
	check("visual switch leaves the complete collision world identical", on_world.ok and off_world.ok and var_to_bytes(on_world.world) == var_to_bytes(off_world.world))
	for key: String in saved: OS.set_environment(key, saved[key])
