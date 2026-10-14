# HELI-25a: standalone import/transform checks of the existing static visual.
# Render-boundary Vector3/Basis are intentional; no simulation state here.
extends SceneTree

var checks: int = 0
var failures: int = 0


func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", label)


func _initialize() -> void:
	call_deferred("_verify")


func _verify() -> void:
	var source_path: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--glb="):
			source_path = argument.substr(6)
	check("explicit preview GLB path exists", not source_path.is_empty() and FileAccess.file_exists(source_path))
	if failures:
		quit(1)
		return
	var document: GLTFDocument = GLTFDocument.new()
	var state: GLTFState = GLTFState.new()
	check("Godot imports supplied-source preview", document.append_from_file(source_path, state) == OK)
	if failures:
		quit(1)
		return
	var visual: Node = document.generate_scene(state)
	check("preview generates a native scene", visual != null)
	if failures:
		quit(1)
		return
	root.add_child(visual)
	var named: Dictionary = {}
	var all_nodes: Array[Node] = []
	_visit(visual, named, all_nodes)
	for expected: String in ["HX-700", "Pivote_Rotor_Principal", "Pivote_Rotor_Cola",
		"Pala_Principal_A", "Pala_Principal_B", "Pala_Cola_A", "Pala_Cola_B"]:
		check("source node preserved " + expected, named.has(expected))
	check("static preview has no animation player", visual.find_children("*", "AnimationPlayer", true, false).is_empty())
	if failures:
		visual.free()
		quit(1)
		return
	var main_pivot: Node3D = named.Pivote_Rotor_Principal
	var tail_pivot: Node3D = named.Pivote_Rotor_Cola
	var main_blade: Node3D = named.Pala_Principal_A
	var tail_blade: Node3D = named.Pala_Cola_A
	check("metric main hub survives Z-up to Y-up export", main_pivot.global_position.is_equal_approx(Vector3(0.0, 0.345, 0.0)))
	check("metric tail hub survives Z-up to Y-up export", tail_pivot.global_position.is_equal_approx(Vector3(-0.942, 0.197, 0.0)))
	check("main blades belong to main pivot", main_pivot.is_ancestor_of(main_blade) and main_pivot.is_ancestor_of(named.Pala_Principal_B))
	check("tail blades belong to tail pivot", tail_pivot.is_ancestor_of(tail_blade) and tail_pivot.is_ancestor_of(named.Pala_Cola_B))
	var main_before: Transform3D = main_blade.global_transform
	var tail_before: Transform3D = tail_blade.global_transform
	var main_transform: Transform3D = main_pivot.transform
	main_pivot.rotate_y(0.2)
	check("main pivot moves its blade transform", not main_blade.global_transform.is_equal_approx(main_before))
	check("main pivot leaves tail blade independent", tail_blade.global_transform.is_equal_approx(tail_before))
	main_pivot.transform = main_transform
	var tail_transform: Transform3D = tail_pivot.transform
	tail_pivot.rotate_z(0.2)
	check("tail pivot moves its blade transform", not tail_blade.global_transform.is_equal_approx(tail_before))
	check("tail pivot leaves main blade independent", main_blade.global_transform.is_equal_approx(main_before))
	tail_pivot.transform = tail_transform
	var meshes: int = 0
	var triangles: int = 0
	var surfaces: int = 0
	for node: Node in all_nodes:
		if node is MeshInstance3D:
			meshes += 1
			for surface: int in range(node.mesh.get_surface_count()):
				surfaces += 1
				check("triangular mesh " + node.name, node.mesh.surface_get_primitive_type(surface) == Mesh.PRIMITIVE_TRIANGLES)
				var arrays: Array = node.mesh.surface_get_arrays(surface)
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				var count: int = indices.size() if not indices.is_empty() else arrays[Mesh.ARRAY_VERTEX].size()
				triangles += count / 3
	check("aircraft-only mesh count", meshes == 22)
	check("no source studio/camera/light in export", visual.find_children("*", "Camera3D", true, false).is_empty()
		and visual.find_children("*", "Light3D", true, false).is_empty() and not named.has("Ciclorama"))
	print(JSON.stringify({"format": "openrc-hx700-native-preview-v1", "godot": Engine.get_version_info().string,
		"checks": checks, "failed": failures, "nodes": all_nodes.size(), "mesh_instances": meshes,
		"surfaces": surfaces, "triangles": triangles,
		"scope": "static source import, metric pivots and independent visual articulation; no flight or presentation budget acceptance"}))
	visual.free()
	quit(1 if failures else 0)


func _visit(node: Node, named: Dictionary, all_nodes: Array[Node]) -> void:
	named[str(node.name)] = node
	all_nodes.append(node)
	for child: Node in node.get_children():
		_visit(child, named, all_nodes)
