# TOD-09b: retained shadow sources update in place and match fresh geometry.
extends SceneTree

const Scenery = preload("res://scenery/scenery.gd")
const Loader = preload("res://scenery/scenery_loader.gd")
const FieldLoader = preload("res://data/field_loader.gd")
const Spec = preload("res://spec.gd")

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	var field_result: Dictionary = FieldLoader.load_from(FieldLoader.DEFAULT_PATH)
	var field: Dictionary = field_result.field
	var scenery_result: Dictionary = Loader.load_from(Loader.DEFAULT_PATH, field)
	var scenery: Dictionary = scenery_result.scenery
	var options: Dictionary = {audio = false, birds = false, theme = "", quality = "high"}
	var legacy: Dictionary = Spec.ATMOSPHERE.duplicate(true)
	var field_node: Node3D = _field_node(field, scenery, options, legacy)
	var root: Node3D = field_node.get_node("Scenery") as Node3D
	var shadow_nodes: Dictionary = root.get_meta("directional_shadow_nodes")
	var population_shadow_node: MeshInstance3D = root.get_node_or_null("PopulationContacts") as MeshInstance3D
	var shadow_material: StandardMaterial3D = root.get_meta("directional_shadow_material")
	var static_meshes: Dictionary = _static_meshes(root)
	var retained_batches := shadow_nodes.size() + (1 if population_shadow_node != null else 0)
	_check("fixture has retained nearby and population shadow batches", retained_batches > 0)

	var night: Dictionary = _lighting(180.0, 0.05, 0.0)
	var before_night_hash: String = _shadow_digest(root)
	var prepared_night: Dictionary = Scenery.prepare_lighting(field_node, night)
	_check("day to night prepares one replacement per retained shadow batch",
		prepared_night.ok and prepared_night.changed and prepared_night.batches.size() == retained_batches)
	_check("prepare leaves live alpha and shadow geometry untouched",
		shadow_material.albedo_color.a == 1.0 and _shadow_digest(root) == before_night_hash)
	var commit_started: int = Time.get_ticks_usec()
	_check("night commit succeeds", Scenery.commit_lighting(field_node, prepared_night))
	var commit_ms: float = float(Time.get_ticks_usec() - commit_started) / 1000.0
	_check("night clears mesh surfaces and material alpha in place",
		shadow_material.albedo_color.a == 0.0 and _all_empty(shadow_nodes)
			and (population_shadow_node == null or population_shadow_node.mesh.get_surface_count() == 0))
	_check("night keeps shadow node and material identity",
		_same_nodes(root, shadow_nodes)
			and (population_shadow_node == null or population_shadow_node.get_parent() == root)
			and root.get_meta("directional_shadow_material") == shadow_material)
	_check("night keeps static scenery mesh resources", _same_meshes(root, static_meshes))
	print("     scenery night update: prepare %.3f ms, commit %.3f ms, %d cells, %d triangles" % [
		prepared_night.prepare_ms, commit_ms, prepared_night.batches.size(), prepared_night.triangles])

	var empty_meshes: Dictionary = _shadow_meshes(shadow_nodes)
	var empty_population_mesh: Mesh = population_shadow_node.mesh if population_shadow_node != null else null
	var later_night: Dictionary = _lighting(270.0, -8.0, 0.0)
	var hidden_prepare: Dictionary = Scenery.prepare_lighting(field_node, later_night)
	_check("zero-strength solar direction changes create no mesh replacements",
		not hidden_prepare.changed and hidden_prepare.batches.is_empty())
	_check("night no-op commit preserves empty mesh resources",
		Scenery.commit_lighting(field_node, hidden_prepare) and _same_shadow_meshes(shadow_nodes, empty_meshes)
			and (population_shadow_node == null or population_shadow_node.mesh == empty_population_mesh))

	var dawn: Dictionary = _lighting(80.0, 1.0, 0.18)
	var dawn_prepared: Dictionary = Scenery.prepare_lighting(field_node, dawn)
	_check("night to dawn prepares projected shadows", dawn_prepared.ok and dawn_prepared.changed
		and dawn_prepared.geometry_changed and dawn_prepared.batches.size() == retained_batches)
	var dawn_commit_started: int = Time.get_ticks_usec()
	_check("night to dawn commit succeeds", Scenery.commit_lighting(field_node, dawn_prepared))
	var dawn_commit_ms: float = float(Time.get_ticks_usec() - dawn_commit_started) / 1000.0
	print("     scenery dawn projection: prepare %.3f ms, commit %.3f ms, %d cells, %d triangles" % [
		dawn_prepared.prepare_ms, dawn_commit_ms, dawn_prepared.batches.size(), dawn_prepared.triangles])
	_check("dawn mesh hash equals a fresh build", _matches_fresh(field, scenery, options, root, dawn))
	_check("dawn preserves static geometry, batch nodes and material",
		_same_meshes(root, static_meshes) and _same_nodes(root, shadow_nodes)
		and (population_shadow_node == null or population_shadow_node.get_parent() == root)
		and root.get_meta("directional_shadow_material") == shadow_material)

	var stale: Dictionary = Scenery.prepare_lighting(field_node, night)
	var noon: Dictionary = _lighting(22.0, 70.0, 0.8)
	_check("dawn to noon update succeeds", Scenery.update_lighting(field_node, noon))
	var noon_hash: String = _shadow_digest(root)
	var noon_alpha: float = shadow_material.albedo_color.a
	_check("stale prepared snapshot is refused", not Scenery.commit_lighting(field_node, stale))
	_check("stale refusal leaves the newer noon state untouched",
		_shadow_digest(root) == noon_hash and shadow_material.albedo_color.a == noon_alpha)
	_check("noon mesh hash equals a fresh build", _matches_fresh(field, scenery, options, root, noon))

	var other_field: Node3D = _field_node(field, scenery, options, legacy)
	var other_root: Node3D = other_field.get_node("Scenery") as Node3D
	var other_prepared: Dictionary = Scenery.prepare_lighting(other_field, night)
	var host_hash_before: String = _shadow_digest(root)
	var other_hash_before: String = _shadow_digest(other_root)
	var other_material: StandardMaterial3D = other_root.get_meta("directional_shadow_material")
	var other_alpha_before: float = other_material.albedo_color.a
	_check("cross-scene prepared state is refused", not Scenery.commit_lighting(field_node, other_prepared))
	_check("cross-scene refusal mutates neither field",
		_shadow_digest(root) == host_hash_before and _shadow_digest(other_root) == other_hash_before
		and shadow_material.albedo_color.a == noon_alpha and other_material.albedo_color.a == other_alpha_before)
	var empty_field: Node3D = Node3D.new()
	_check("no scenery child is a safe no-op", Scenery.update_lighting(empty_field, night))
	empty_field.free()

	_check("noon to night update succeeds", Scenery.update_lighting(field_node, night))
	_check("night mesh hash equals a fresh build", _matches_fresh(field, scenery, options, root, night))
	_check("night to legacy reversal succeeds", Scenery.update_lighting(field_node, legacy))
	_check("legacy mesh hash equals a fresh build", _matches_fresh(field, scenery, options, root, legacy))
	_check("final identity remains stable", _same_meshes(root, static_meshes) and _same_nodes(root, shadow_nodes)
		and (population_shadow_node == null or population_shadow_node.get_parent() == root)
		and root.get_meta("directional_shadow_material") == shadow_material)

	field_node.free()
	other_field.free()
	print("%d scenery lighting checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _field_node(field: Dictionary, scenery: Dictionary, options: Dictionary, lighting: Dictionary) -> Node3D:
	var host: Node3D = Node3D.new()
	host.name = "Field"
	host.add_child(Scenery.build(field, scenery, options, lighting))
	return host


func _lighting(azimuth: float, elevation: float, strength: float) -> Dictionary:
	var value: Dictionary = Spec.ATMOSPHERE.duplicate(true)
	value.sun_azimuth_deg = azimuth
	value.sun_elevation_deg = elevation
	value.shadow_strength = strength
	return value


func _static_meshes(root: Node3D) -> Dictionary:
	var result: Dictionary = {}
	for child: Node in root.get_children():
		if child is MeshInstance3D and str(child.name).begins_with("cell_"):
			result[child.name] = (child as MeshInstance3D).mesh
	return result


func _shadow_meshes(nodes: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key: Vector2i in nodes:
		result[key] = (nodes[key] as MeshInstance3D).mesh
	return result


func _same_meshes(root: Node3D, expected: Dictionary) -> bool:
	for name: String in expected:
		var node: MeshInstance3D = root.get_node_or_null(NodePath(name)) as MeshInstance3D
		if node == null or node.mesh != expected[name]:
			return false
	return true


func _same_shadow_meshes(nodes: Dictionary, expected: Dictionary) -> bool:
	for key: Vector2i in expected:
		if not nodes.has(key) or (nodes[key] as MeshInstance3D).mesh != expected[key]:
			return false
	return true


func _same_nodes(root: Node3D, expected: Dictionary) -> bool:
	var current: Dictionary = root.get_meta("directional_shadow_nodes")
	for key: Vector2i in expected:
		var node: MeshInstance3D = expected[key] as MeshInstance3D
		if current.get(key) != node or node.get_parent() != root:
			return false
	return true


func _all_empty(nodes: Dictionary) -> bool:
	for node: MeshInstance3D in nodes.values():
		if node.mesh.get_surface_count() != 0:
			return false
	return true


func _shadow_digest(root: Node3D) -> String:
	var bytes: PackedByteArray = PackedByteArray()
	var names: Array[String] = []
	for child: Node in root.get_children():
		if child is MeshInstance3D and (str(child.name).begins_with("shadows_") or str(child.name) == "PopulationContacts"):
			names.append(str(child.name))
	names.sort()
	for name: String in names:
		var node: MeshInstance3D = root.get_node_or_null(NodePath(name)) as MeshInstance3D
		var mesh: ArrayMesh = node.mesh as ArrayMesh
		bytes.append_array(name.to_utf8_buffer())
		for surface: int in mesh.get_surface_count():
			var arrays: Array = mesh.surface_get_arrays(surface)
			bytes.append_array((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).to_byte_array())
			bytes.append_array((arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array).to_byte_array())
			bytes.append_array((arrays[Mesh.ARRAY_COLOR] as PackedColorArray).to_byte_array())
	var context: HashingContext = HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()


func _matches_fresh(field: Dictionary, scenery: Dictionary, options: Dictionary, current: Node3D, lighting: Dictionary) -> bool:
	var expected: Node3D = Scenery.build(field, scenery, options, lighting)
	var want: String = _shadow_digest(expected)
	var got: String = _shadow_digest(current)
	expected.free()
	return got == want


func _check(label: String, condition: bool) -> void:
	_checks += 1
	if condition:
		print("ok   " + label)
	else:
		_failures += 1
		printerr("FAIL " + label)
