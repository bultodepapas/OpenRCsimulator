# SCENERY-PLAN SC-02…SC-24: the scenery builds deterministically, within budget, with the catalog's real sizes, Godot's
# winding, the quality tiers and themes, and changes nothing when it is off.
# Run: godot --headless --path . --script res://tests/test_scenery_build.gd
extends SceneTree

const Scenery = preload("res://scenery/scenery.gd")
const Loader = preload("res://scenery/scenery_loader.gd")
const Prefabs = preload("res://scenery/prefabs.gd")
const Models = preload("res://scenery/models.gd")
const Population = preload("res://scenery/population.gd")
const ImportedVegetation = preload("res://scenery/imported_vegetation.gd")
const VegetationPlacement = preload("res://scenery/vegetation_placement.gd")
const MeshKit = preload("res://scenery/mesh_kit.gd")
const Palette = preload("res://scenery/palette.gd")
const FieldLoader = preload("res://data/field_loader.gd")
const FieldBuilder = preload("res://render/field.gd")
const ShaderClock = preload("res://render/shader_clock.gd")

const OPTS := {audio = false, birds = false, theme = "", quality = "high"}
const SourceBudget = preload("res://tests/scene_source_budget.gd") # LU-34 per-subsystem allowances
const BUDGET_FLEET_TRIANGLES := 350000 # Full near meshes, before per-view automatic LOD; native evidence in SC-09-R1.
const BUDGET_BUILD_MS := 800.0 # Warm scene-construction gate. Cold source import/parsing remains a measured performance target.

var _failures := 0
var _field: Dictionary
var _scenery: Dictionary


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _initialize() -> void:
	ShaderClock.register()
	_field = FieldLoader.load_from(FieldLoader.DEFAULT_PATH).field
	_scenery = Loader.load_from(Loader.DEFAULT_PATH, _field).scenery
	_test_off_is_noop()
	_test_build()
	_test_determinism()
	_test_catalog_sizes()
	_test_models()
	_test_winding()
	_test_tiers()
	_test_themes()
	print("all scenery build checks passed" if _failures == 0 else "%d scenery build checks failed" % _failures)
	quit(1 if _failures > 0 else 0)


func _test_off_is_noop() -> void:
	var previous_scenery := OS.get_environment("OPENRC_SCENERY")
	OS.set_environment("OPENRC_SCENERY", "off")
	var node := FieldBuilder.build(_field)
	_check("switch off: the field has no Scenery node", node.get_node_or_null("Scenery") == null)
	var rough := node.get_node_or_null("rough") as MeshInstance3D
	_check("switch off: the field owns the contiguous L7 ground independently of scenery",
		rough != null and rough.mesh is ArrayMesh and rough.mesh.get_surface_count() == 1
		and rough.mesh.get_aabb().size.x == 40000.0)
	node.free()
	OS.unset_environment("OPENRC_SCENERY")
	if not previous_scenery.is_empty():
		OS.set_environment("OPENRC_SCENERY", previous_scenery)


func _mesh_triangles(mesh: Mesh) -> int:
	return Population.triangles(mesh)


func _triangles(root: Node) -> int:
	var n := 0
	for c in root.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).mesh:
			n += _mesh_triangles((c as MeshInstance3D).mesh)
		elif c is MultiMeshInstance3D:
			var mm := (c as MultiMeshInstance3D).multimesh
			if mm != null and mm.mesh != null:
				n += mm.instance_count * _mesh_triangles(mm.mesh)
		if c.get_child_count() > 0:
			n += _triangles(c)
	return n


func _test_build() -> void:
	var root := Scenery.build(_field, _scenery, OPTS)
	var stats: Dictionary = root.get_meta("stats")
	print("     stats: ", stats)
	_check("instances built (> 120)", int(stats.instances) > 120)
	_check("the parked fleet: 13 aircraft across ready, grass and service bays", int(stats.fleet) == 13)
	var parked_fleet := root.get_node("ParkedAircraft")
	_check("parked aircraft are eight static batches with no active scripts",
		parked_fleet.process_mode == Node.PROCESS_MODE_DISABLED and parked_fleet.get_child_count() == 8
		and parked_fleet.get_children().all(func(child: Node) -> bool:
			return child is MultiMeshInstance3D and child.get_script() == null and child.get_child_count() == 0))
	_check("repeated aircraft share draws within each shelter",
		int(stats.fleet_batch_surfaces) < int(stats.fleet_surfaces) and int(stats.fleet_batch_surfaces) <= 180)
	var motion_counts := {rotor = 0, flag = 0, crown = 0, bush_tips = 0}
	var motion_node: Node = root.get_node("Motion")
	for part: Node in motion_node.get_children():
		for kind: String in motion_counts:
			if str(part.name).begins_with(kind + "_"):
				motion_counts[kind] += 1
	_check("moving parts preserve 4 rotors + 1 flag", motion_counts.rotor == 4 and motion_counts.flag == 1,
		str(motion_counts))
	_check("trees and shrubs use imported source batches instead of procedural motion nodes",
		motion_counts.crown == 0 and motion_counts.bush_tips == 0)
	_check("Motion contains only the 4 rotor and 1 flag source meshes",
		motion_node.get_child_count() == 5 and motion_counts.rotor + motion_counts.flag == 5,
		str(motion_counts))
	_check("motion stats count every emitted animated mesh", int(stats.motion) == motion_node.get_child_count(),
		"stats=%d nodes=%d" % [int(stats.motion), motion_node.get_child_count()])
	var population: Node3D = root.get_node_or_null("Population") as Node3D
	_check("population batching retains all 24 placements (11 cars + 13 people)",
		population != null and int(stats.get("population", -1)) == 24
		and int(population.get_meta("instances", -1)) == 24,
		"stats=%s metadata=%s" % [stats.get("population", -1), population.get_meta("instances", -1) if population != null else -1])
	var moving_people := int(stats.get("moving_people", -1))
	_check("only 2–9 people receive shader-driven motion", moving_people >= 2 and moving_people <= 9,
		"moving_people=%d" % moving_people)
	_check("population triangle stats match indexed MultiMesh geometry",
		population != null and int(stats.get("population_triangles", -1)) == _triangles(population),
		"stats=%s rendered=%s" % [stats.get("population_triangles", -1), _triangles(population) if population != null else -1])
	var primitive_quad := QuadMesh.new()
	var quad_triangles := Population.triangles(primitive_quad)
	_check("mesh triangle counting handles primitive QuadMesh surfaces", quad_triangles == 2,
		"actual=%d" % quad_triangles)
	_check("contact shadows for the near props", int(stats.shadows) > 50)
	var imported_plants: Node3D = root.get_node_or_null("ImportedVegetationBatches") as Node3D
	var botanical: Node3D = root.get_node_or_null("BotanicalHabitats") as Node3D
	var botanical_plants: Array = botanical.get_meta("plants", []) if botanical != null else []
	_check("downloaded trees and shrubs are source-material MultiMesh batches",
		imported_plants != null and int(stats.get("vegetation_instances", 0)) >= 16
		and int(stats.get("vegetation_triangles", 0)) > 0
		and imported_plants.get_children().all(func(child: Node) -> bool: return child is MultiMeshInstance3D))
	_check("downloaded habitat flowers replace the procedural cushion group",
		int(stats.flowers) == 0 and botanical != null and botanical_plants.size() == int(stats.get("botanical_plants", -1)))
	_check("downloaded habitat geometry stays within the 90k plant-triangle and 24-batch limits",
		int(stats.get("botanical_triangles", -1)) > 0 and int(stats.botanical_triangles) <= 90000
		and int(stats.get("botanical_batches", 99)) <= 24,
		"triangles=%s batches=%s" % [stats.get("botanical_triangles", -1), stats.get("botanical_batches", -1)])
	_check_imported_vegetation_damage(imported_plants)
	_check("compact cells (≤ 64 merged meshes)", int(stats.cells) <= 64)
	var cell_surfaces := 0
	for c in root.get_children():
		if c is MeshInstance3D and str(c.name).begins_with("cell_"):
			cell_surfaces += (c as MeshInstance3D).mesh.get_surface_count()
	_check("one surface per cell (one shared material)", cell_surfaces == int(stats.cells))
	var shelter_nodes: Array[MeshInstance3D] = []
	for child: Node in root.get_children():
		if child is MeshInstance3D and str(child.name).begins_with("PitShelter_"):
			shelter_nodes.append(child as MeshInstance3D)
	_check("two open shelters each retain one independent damage-aware surface",
		shelter_nodes.size() == 2 and int(stats.get("pit_shelter_surfaces", -1)) == 2)
	for shelter_mesh: MeshInstance3D in shelter_nodes:
		var material := shelter_mesh.mesh.surface_get_material(0) as ShaderMaterial
		var ranges: Array = shelter_mesh.get_meta("damage_ranges", [])
		_check("%s keeps its roof, timber, slab and furniture in one PBR surface" % shelter_mesh.name,
			shelter_mesh.mesh.get_surface_count() == 1 and material != null
			and material.shader == load("res://scenery/pit_shelter_roof.gdshader")
			and material.get_shader_parameter("roof_albedo") is Texture2D
			and material.get_shader_parameter("wood_albedo") is Texture2D
			and material.get_shader_parameter("slab_albedo") is Texture2D
			and ranges.size() == 1 and str(ranges[0].id).begins_with("prop:pit-shelters:"))
	var building_roofs: Node3D = root.get_node_or_null("BuildingRoofs")
	var roof_count := building_roofs.get_child_count() if building_roofs != null else 0
	var fitted_roofs := roof_count >= 20
	if building_roofs != null:
		for roof_node: Node in building_roofs.get_children():
			var roof := roof_node as MeshInstance3D
			if roof == null or roof.mesh == null or roof.mesh.get_surface_count() != 1:
				fitted_roofs = false
				break
			var arrays := roof.mesh.surface_get_arrays(0)
			var material := roof.mesh.surface_get_material(0) as ShaderMaterial
			if arrays[Mesh.ARRAY_TEX_UV].size() != arrays[Mesh.ARRAY_VERTEX].size() \
					or material == null or material.shader != load("res://scenery/building_roofs.gdshader") \
					or not (material.get_shader_parameter("albedo_map") is Texture2D) \
					or not roof.has_meta("damage_motion_id"):
				fitted_roofs = false
				break
	_check("building roofs have fitted UVs, PBR maps and damage ids", fitted_roofs,
		"roof nodes=%d" % roof_count)
	var fleet_triangles := _triangles(root.get_node("ParkedAircraft"))
	var tris := _triangles(root)
	_check("static modern fleet stays below 350k full-detail triangles", fleet_triangles > 0 and fleet_triangles <= BUDGET_FLEET_TRIANGLES, str(fleet_triangles))
	print("     triangles: %d, build %.1f ms" % [tris, stats.build_ms])
	var source_failures := SourceBudget.failures(root)
	_check("every scenery subsystem stays within its LU-34 source allowance", source_failures.is_empty(),
		", ".join(source_failures) + " " + str(SourceBudget.counts(root)))
	print("     cold build %.1f ms (%.0f ms target remains open; source import and runner load included)" % [
		float(stats.build_ms), BUDGET_BUILD_MS])
	for c in root.get_children():
		if c is GeometryInstance3D and (c as GeometryInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			_check("no engine shadow casting (0 shadow-pass draws)", false, str(c.name))
	if building_roofs != null and roof_count > 0:
		var first_id: String = building_roofs.get_child(0).get_meta("damage_motion_id")
		Scenery.apply_damage(root, {first_id: {state = "broken"}})
		var hidden := true
		for roof_node: Node in building_roofs.get_children():
			if roof_node.get_meta("damage_motion_id") == first_id and (roof_node as Node3D).visible:
				hidden = false
		Scenery.apply_damage(root, {})
		var restored := true
		for roof_node: Node in building_roofs.get_children():
			if roof_node.get_meta("damage_motion_id") == first_id and not (roof_node as Node3D).visible:
				restored = false
		_check("roof skins hide with a broken building and restore on reset", hidden and restored)
	root.free()


func _digest(root: Node) -> String:
	var bytes := PackedByteArray()
	for c in root.get_children():
		bytes.append_array(str(c.name).to_utf8_buffer())
		if c is MeshInstance3D and (c as MeshInstance3D).mesh:
			var m := (c as MeshInstance3D).mesh
			for s in m.get_surface_count():
				var a := m.surface_get_arrays(s)
				bytes.append_array((a[Mesh.ARRAY_VERTEX] as PackedVector3Array).to_byte_array())
				if a[Mesh.ARRAY_COLOR] != null:
					bytes.append_array((a[Mesh.ARRAY_COLOR] as PackedColorArray).to_byte_array())
		elif c is MultiMeshInstance3D:
			bytes.append_array((c as MultiMeshInstance3D).multimesh.buffer.to_byte_array())
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(bytes)
	return ctx.finish().hex_encode()


func _test_determinism() -> void:
	var a := Scenery.build(_field, _scenery, OPTS)
	var b := Scenery.build(_field, _scenery, OPTS)
	_check("two builds are byte-identical (no RNG, no clock)", _digest(a) == _digest(b))
	print("     warm scene-build times: %.1f ms / %.1f ms" % [
		float(a.get_meta("stats").build_ms), float(b.get_meta("stats").build_ms)])
	_check("repeatable warm scene builds stay under %.0f ms on this CPU" % BUDGET_BUILD_MS,
		float(a.get_meta("stats").build_ms) < BUDGET_BUILD_MS
		and float(b.get_meta("stats").build_ms) < BUDGET_BUILD_MS)
	a.free()
	b.free()


func _test_catalog_sizes() -> void:
	for id: String in Prefabs.CATALOG:
		var spec: Dictionary = Prefabs.CATALOG[id]
		if bool(spec.get("imported_vegetation", false)):
			var imported_spec := VegetationPlacement.spec(id, 1234)
			_check("%s downloaded source fits its catalog height" % id,
				not imported_spec.is_empty() and float(imported_spec.height) <= spec.size.y \
				and float(imported_spec.height) >= 3.2)
			_check("%s has evidence (kind and source)" % id,
				["borrowed", "estimated", "manual", "measured"].has(spec.kind) and not str(spec.source).is_empty())
			continue
		var k := MeshKit.new()
		var moving: Array = Prefabs.build(id, k, 1234, "temperate")
		var box := AABB(k.verts[0], Vector3.ZERO)
		for v: Vector3 in k.verts:
			box = box.expand(v)
		# Person catalogs describe the full body, including the selected shader-driven arm.
		if id.begins_with("person_"):
			for part: Dictionary in moving:
				var part_kit: MeshKit = part.kit
				for v: Vector3 in part_kit.verts:
					box = box.expand(v + part.pivot)
		var want: Vector3 = spec.size
		if id.begins_with("person_"):
			# These production IDs now render the imported posed mesh; legacy
			# procedural body proportions have their separate population regression.
			box = Population._source(Population.ASSETS[id]).bounds
		var tol := 0.3 if spec.get("variable", false) else 0.1
		var ok := true
		for i in 3:
			if absf(box.size[i] - want[i]) > maxf(tol * want[i], 0.1):
				ok = false
		_check("%s size %.2f × %.2f × %.2f m matches the catalog %s" % [id, box.size.x, box.size.y, box.size.z, want], ok)
		_check("%s has evidence (kind and source)" % id, ["borrowed", "estimated", "manual", "measured"].has(spec.kind) and not str(spec.source).is_empty())


func _test_models() -> void:
	for id: String in Models.CATALOG:
		var arr := Models.arrays(id)
		_check("model %s loads" % id, not arr.is_empty())
		if arr.is_empty():
			continue
		var box := AABB((arr.pos as PackedVector3Array)[0], Vector3.ZERO)
		for v: Vector3 in arr.pos:
			box = box.expand(v)
		var want: Vector3 = Models.CATALOG[id].size
		var ok := absf(box.size.z - want.z) < 0.02 * want.z + 0.01 and absf(box.size.y - want.y) < 0.03 * want.y + 0.02
		_check("model %s is %.2f × %.2f × %.2f m (catalog %s)" % [id, box.size.x, box.size.y, box.size.z, want], ok)
		_check("model %s rests on the ground" % id, absf(box.position.y) < 0.005)
		var bad := 0
		for n: Vector3 in arr.nrm:
			if absf(n.length() - 1.0) > 1e-3:
				bad += 1
		_check("model %s normals are unit length" % id, bad == 0, str(bad))
	for id: String in ["car_sedan", "car_hatch", "car_suv", "car_sport"]:
		var paint := 0
		for c: Color in Models.arrays(id).col:
			if c.a < 0.5:
				paint += 1
		_check("%s marks its paint for per-car colours" % id, paint > 100)


## Every emitted triangle (p0, p1, p2) must be clockwise from its normal's side: (p2 − p0) × (p1 − p0) · n > 0.
func _test_winding() -> void:
	var root := Scenery.build(_field, _scenery, OPTS)
	var bad := 0
	var total := 0
	for c in root.get_children():
		if c is MeshInstance3D and str(c.name).begins_with("cell_"):
			var a := (c as MeshInstance3D).mesh.surface_get_arrays(0)
			var p: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var n: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
			for i in range(0, p.size(), 3):
				var face := (p[i + 2] - p[i]).cross(p[i + 1] - p[i])
				if face.length_squared() < 1e-12:
					continue
				total += 1
				if face.dot(n[i]) <= 0.0:
					bad += 1
	_check("all %d cell triangles wind clockwise toward their normal (Godot front faces)" % total, bad == 0, "%d reversed" % bad)
	root.free()


func _test_tiers() -> void:
	var counts := {}
	var motion_counts := {}
	for q: String in ["low", "balanced", "high"]:
		var r := Scenery.build(_field, _scenery, {audio = false, birds = false, theme = "", quality = q})
		counts[q] = r.get_meta("stats")
		motion_counts[q] = {rotor = 0, flag = 0, crown = 0, bush_tips = 0}
		for part: Node in r.get_node("Motion").get_children():
			for kind: String in motion_counts[q]:
				if str(part.name).begins_with(kind + "_"):
					motion_counts[q][kind] += 1
		r.free()
	_check("tiers: low < balanced < high instances", int(counts.low.instances) < int(counts.balanced.instances) and int(counts.balanced.instances) < int(counts.high.instances))
	_check("tiers: low keeps no ornamental flowers", int(counts.low.flowers) == 0)
	_check("tiers: low retains flightline rotors and flag without vegetation motion nodes",
		motion_counts.low.rotor == 4 and motion_counts.low.flag == 1 and motion_counts.low.crown == 0
		and motion_counts.low.bush_tips == 0 and int(counts.low.moving_people) == 0, str(motion_counts.low))
	_check("tiers: high retains flightline landmarks and bounded population motion",
		motion_counts.high.rotor == 4 and motion_counts.high.flag == 1 and motion_counts.high.crown == 0
		and motion_counts.high.bush_tips == 0 and int(counts.high.moving_people) >= 2
		and int(counts.high.moving_people) <= 9 and int(counts.high.botanical_plants) > 0,
		"%s moving_people=%d" % [motion_counts.high, int(counts.high.moving_people)])
	_check("tiers: downloaded habitat plants use stable density subsets",
		int(counts.low.botanical_plants) < int(counts.balanced.botanical_plants)
		and int(counts.balanced.botanical_plants) < int(counts.high.botanical_plants))


func _test_themes() -> void:
	var t := Palette.veg("hedge", "temperate")
	var s := Palette.veg("hedge", "summer")
	var a := Palette.veg("hedge", "autumn")
	_check("themes recolour vegetation", not t.is_equal_approx(s) and not t.is_equal_approx(a))
	_check("summer is paler and drier (lower saturation)", s.s < t.s)
	var r := Scenery.build(_field, _scenery, {audio = false, birds = false, theme = "autumn", quality = "high"})
	_check("a themed build reports its theme", r.get_meta("stats").theme == "autumn")
	r.free()


func _check_imported_vegetation_damage(vegetation: Node3D) -> void:
	if vegetation == null:
		_check("downloaded vegetation exposes damage IDs", false)
		return
	var state: Dictionary = vegetation.get_meta("_imported_vegetation_state", {})
	var damage: Dictionary = state.get("damage", {})
	var damage_ids: Array = damage.keys()
	damage_ids.sort()
	if damage_ids.is_empty():
		_check("downloaded vegetation exposes damage IDs", false)
		return
	var damage_id := str(damage_ids[0])
	var hidden := ImportedVegetation.set_damage_hidden(vegetation, damage_id, true)
	var after_hide: Dictionary = vegetation.get_meta("_imported_vegetation_state", {})
	var all_records_hidden := hidden
	var bounds_records: Array = after_hide.get("bounds", [])
	for item: Dictionary in damage.get(damage_id, []):
		var bounds_index := int(item.get("bounds_index", -1))
		all_records_hidden = all_records_hidden and bounds_index >= 0 and bounds_index < bounds_records.size()
		if bounds_index >= 0 and bounds_index < bounds_records.size():
			all_records_hidden = all_records_hidden and bool(bounds_records[bounds_index].get("hidden", false))
	_check("a production vegetation damage ID hides only its imported source record", all_records_hidden, damage_id)
	var restored := ImportedVegetation.set_damage_hidden(vegetation, damage_id, false)
	_check("the production vegetation source record restores after damage reset", restored)
