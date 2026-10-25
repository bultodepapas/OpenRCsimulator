extends SceneTree

var checks := 0
var failures := 0
var actual_root: Node3D

func _check(label: String, ok: bool, detail := "") -> void:
	checks += 1
	if not ok: failures += 1
	print(("ok   " if ok else "FAIL ") + label + ("" if detail.is_empty() else " (" + detail + ")"))

func _convert_blender_transform(rows: Array) -> Transform3D:
	var bx := Vector3(float(rows[0][0]), float(rows[1][0]), float(rows[2][0]))
	var by := Vector3(float(rows[0][1]), float(rows[1][1]), float(rows[2][1]))
	var bz := Vector3(float(rows[0][2]), float(rows[1][2]), float(rows[2][2]))
	var bl_basis := Basis(bx, by, bz)
	# Blender axes (right, nose, up) -> Godot axes (right, up, backward).
	var axis_map := Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0))
	var basis := axis_map * bl_basis * axis_map.inverse()
	var origin := axis_map * Vector3(float(rows[0][3]), float(rows[1][3]), float(rows[2][3]))
	return Transform3D(basis, origin)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		print("FAIL usage: godot --headless --path app --script godot_g2_glb_contract.gd -- GLB METADATA")
		quit(2)
		return
	var glb_path := str(args[0])
	var meta_path := str(args[1])
	var metadata: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(meta_path))
	var bytes := FileAccess.get_file_as_bytes(glb_path)
	var sha := HashingContext.new()
	sha.start(HashingContext.HASH_SHA256)
	sha.update(bytes)
	var digest := sha.finish().hex_encode()
	_check("GLB SHA-256 equals sidecar metadata", digest == str(metadata.get("glb_sha256", "")), digest)
	_check("GLB bytes equal sidecar and stay below 30 MB", bytes.size() == int(metadata.get("glb_bytes", -1)) and bytes.size() <= 30000000, str(bytes.size()))
	_check("metadata identifies Naval 308 as default first livery", metadata.get("default_livery") == "midnight" and metadata.get("liveries", []).size() > 0 and metadata.liveries[0].get("id") == "midnight" and bool(metadata.liveries[0].get("default", false)))
	_check("metadata records GearRetract with 101 samples", metadata.get("gear", {}).get("action", "") == "GearRetract" and int(metadata.get("gear", {}).get("samples", 0)) == 101)

	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var error_code := doc.append_from_file(glb_path, state)
	_check("Godot GLTFDocument parses final GLB", error_code == OK, "Error %d" % error_code)
	if error_code != OK:
		print("FAIL cannot continue scene inspection")
		quit(1)
		return
	actual_root = doc.generate_scene(state)
	_check("Godot generates a Node3D scene", actual_root != null and actual_root is Node3D)
	if actual_root == null:
		quit(1)
		return

	var nodes: Array[Node] = [actual_root]
	nodes.append_array(actual_root.find_children("*", "", true, false))
	var by_name := {}
	for node in nodes:
		if node is Node3D:
			var key := str(node.name)
			if not by_name.has(key): by_name[key] = []
			by_name[key].append(node)
	var meshes := actual_root.find_children("*", "MeshInstance3D", true, false)
	var surface_count := 0
	var triangle_count := 0
	var materials := {}
	var untagged := []
	var invalid_tags := []
	var bad_primitives := []
	var null_surfaces := []
	for mesh_node in meshes:
		var mi := mesh_node as MeshInstance3D
		if mi.mesh == null: continue
		for s in mi.mesh.get_surface_count():
			surface_count += 1
			if mi.mesh.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES: bad_primitives.append("%s:%d" % [mi.name, s])
			var arrays: Array = mi.mesh.surface_get_arrays(s)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			triangle_count += int(indices.size() / 3) if not indices.is_empty() else int(verts.size() / 3)
			var material := mi.mesh.surface_get_material(s)
			if material == null:
				null_surfaces.append("%s:%d" % [mi.name, s])
			else:
				materials[material.get_instance_id()] = str(material.resource_name)
		var extras: Variant = mi.get_meta("extras", {})
		var section := str((extras as Dictionary).get("openrc_section", "")) if extras is Dictionary else ""
		if section.is_empty(): untagged.append(mi.name)
		elif not ["core", "wing_left", "wing_right", "wing_center", "horizontal_tail", "vertical_tail", "engine", "propeller", "gear", "canopy"].has(section): invalid_tags.append(mi.name + ":" + section)

	_check("mesh-node count matches metadata", meshes.size() == int(metadata.get("meshes", []).size()), "%d" % meshes.size())
	_check("imported triangles equal metadata and stay in 300–350k target", triangle_count == int(metadata.get("triangle_count", -1)) and triangle_count >= 300000 and triangle_count <= 350000, "%d" % triangle_count)
	_check("imported surfaces equal metadata and stay under 70", surface_count == int(metadata.get("surface_count", -1)) and surface_count <= 70, "%d" % surface_count)
	_check("imported material resources stay under 16", materials.size() <= 16, "%d" % materials.size())
	_check("all mesh surfaces are triangles and have materials", bad_primitives.is_empty() and null_surfaces.is_empty(), "bad %s; null %s" % [str(bad_primitives), str(null_surfaces)])
	_check("all mesh extras carry valid openrc_section tags", untagged.is_empty() and invalid_tags.is_empty(), "untagged %s; invalid %s" % [str(untagged), str(invalid_tags)])

	var expected_nodes: Dictionary = metadata.get("nodes", {})
	var missing := []
	var duplicate := []
	var unexpected_nodes := []
	for key in by_name:
		if not expected_nodes.has(str(key)): unexpected_nodes.append(str(key))
	var wrapper_ok := not expected_nodes.has(str(actual_root.name)) and actual_root.transform.is_equal_approx(Transform3D.IDENTITY)
	var parent_errors := []
	var transform_errors := []
	var worst_translation := 0.0
	var worst_basis := 0.0
	for name in expected_nodes:
		var found: Array = by_name.get(str(name), [])
		if found.is_empty():
			missing.append(str(name))
			continue
		if found.size() != 1:
			duplicate.append(str(name))
			continue
		var node := found[0] as Node3D
		var record: Dictionary = expected_nodes[name]
		var parent_value: Variant = record.get("parent")
		var expected_parent := "" if parent_value == null else str(parent_value)
		var actual_parent := str(node.get_parent().name) if node.get_parent() != null else ""
		var parent_matches := actual_parent == expected_parent
		# GLTFDocument adds one identity scene wrapper around the exported Blender root object.
		if expected_parent.is_empty() and node.get_parent() == actual_root and wrapper_ok: parent_matches = true
		if not parent_matches: parent_errors.append("%s:%s!=%s" % [name, actual_parent, expected_parent])
		var expected := _convert_blender_transform(record.get("rest_matrix_local", []))
		var dt := node.transform.origin.distance_to(expected.origin)
		var db := maxf((node.transform.basis.x - expected.basis.x).length(), maxf((node.transform.basis.y - expected.basis.y).length(), (node.transform.basis.z - expected.basis.z).length()))
		worst_translation = maxf(worst_translation, dt)
		worst_basis = maxf(worst_basis, db)
		if dt > 0.00002 or db > 0.00002: transform_errors.append("%s: %.8fm/%.8f" % [name, dt, db])
	_check("all exported object nodes are present once", missing.is_empty() and duplicate.is_empty(), "missing %s; duplicate %s" % [str(missing), str(duplicate)])
	_check("only an identity GLTF scene wrapper is outside sidecar node set", wrapper_ok and unexpected_nodes.size() == 1 and unexpected_nodes[0] == str(actual_root.name), "wrapper %s; extras %s" % [str(actual_root.name), str(unexpected_nodes)])
	_check("exported hierarchy parents match frame-100 sidecar", parent_errors.is_empty(), str(parent_errors.slice(0, 12)))
	_check("Godot transforms match Blender frame-100 local matrices within 0.02 mm", transform_errors.is_empty(), "worst %.9f m / basis %.9f; errors %s" % [worst_translation, worst_basis, str(transform_errors.slice(0, 12))])
	print("G2 Godot GLB contract: %d checks, %d failures; nodes %d/%d; meshes %d; surfaces %d; triangles %d; materials %d" % [checks, failures, by_name.size(), expected_nodes.size(), meshes.size(), surface_count, triangle_count, materials.size()])
	print("G2 GLB geometry is frame 100 (stowed gear); native 101-frame GearRetract evaluation is covered by the separate Blender audit.")
	actual_root.free()
	await process_frame
	quit(1 if failures else 0)
