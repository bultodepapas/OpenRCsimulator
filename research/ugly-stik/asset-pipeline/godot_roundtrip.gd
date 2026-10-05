extends SceneTree

const TOLERANCE := 0.0001
const GLB_PATH := "res://hinge-roundtrip.glb"
const RESULT_PATH := "res://godot-roundtrip.json"


func _initialize() -> void:
	call_deferred("_run_check")


func _run_check() -> void:
	var resource := load(GLB_PATH)
	if not resource is PackedScene:
		_fail("Godot did not import the GLB as a PackedScene: %s" % [resource])
		return

	var scene_root := (resource as PackedScene).instantiate()
	root.add_child(scene_root)
	await process_frame
	var names := {}
	var nodes: Array[Node] = [scene_root]
	var index := 0
	while index < nodes.size():
		var node := nodes[index]
		names[node.name] = int(names.get(node.name, 0)) + 1
		for child in node.get_children():
			nodes.append(child)
		index += 1

	var airplane := _find_named(scene_root, "airplane") as Node3D
	var hinge := _find_named(scene_root, "elevator_hinge") as Node3D
	var elevator := _find_named(scene_root, "elevator") as MeshInstance3D
	var leading_probe := _find_named(scene_root, "elevator_hinge_probe") as Node3D
	var trailing_probe := _find_named(scene_root, "elevator_trailing_probe") as Node3D
	var nodes_present := airplane != null and hinge != null and elevator != null and leading_probe != null and trailing_probe != null
	var names_unique := nodes_present
	if nodes_present:
		for node_name in ["airplane", "elevator_hinge", "elevator", "elevator_hinge_probe", "elevator_trailing_probe"]:
			names_unique = names_unique and int(names.get(node_name, 0)) == 1

	var hierarchy_preserved := nodes_present and hinge.get_parent() == airplane and elevator.get_parent() == hinge
	var measured_size := Vector3.ZERO
	var hinge_global := Vector3.ZERO
	var leading_global := Vector3.ZERO
	var trailing_neutral := Vector3.ZERO
	var trailing_commanded := Vector3.ZERO
	var hinge_at_leading_edge := false
	var positive_pitch_raises_trailing_edge := false
	var size_preserved := false
	var root_transform := {}

	if nodes_present:
		measured_size = elevator.mesh.get_aabb().size
		hinge_global = hinge.to_global(Vector3.ZERO)
		leading_global = leading_probe.global_position
		trailing_neutral = trailing_probe.global_position
		root_transform = {
			"position": airplane.position,
			"rotation_radians": airplane.rotation,
			"scale": airplane.scale,
		}
		size_preserved = _near_vec3(measured_size, Vector3(0.8, 0.02, 0.25))
		hinge_at_leading_edge = _near_vec3(hinge_global, leading_global)
		hinge.rotation.x = -PI / 6.0
		await process_frame
		trailing_commanded = trailing_probe.global_position
		positive_pitch_raises_trailing_edge = trailing_commanded.y > trailing_neutral.y + TOLERANCE

	var result := {
		"result": "pass" if nodes_present and names_unique and hierarchy_preserved and size_preserved and hinge_at_leading_edge and positive_pitch_raises_trailing_edge else "fail",
		"godot": "4.7.2.stable.official.ed1daf0bf",
		"artifact": GLB_PATH,
		"scene_root_name": scene_root.name,
		"scene_root_class": scene_root.get_class(),
		"source_convention": {"nose": "-Z", "right": "+X", "up": "+Y"},
		"conversion_applied": false,
		"checks": {
			"required_nodes_present": nodes_present,
			"required_names_unique": names_unique,
			"pivot_hierarchy_preserved": hierarchy_preserved,
			"dimensions_meters": {
				"expected": Vector3(0.8, 0.02, 0.25),
				"after_import": measured_size,
				"preserved": size_preserved,
			},
			"hinge_at_leading_edge": {
				"hinge_global": hinge_global,
				"leading_edge_global": leading_global,
				"preserved": hinge_at_leading_edge,
			},
			"positive_pitch_raises_elevator_trailing_edge": {
				"neutral_global": trailing_neutral,
				"commanded_global": trailing_commanded,
				"command_rotation_about_local_x_radians": -PI / 6.0,
				"passed": positive_pitch_raises_trailing_edge,
			},
			"airplane_root_transform": root_transform,
		},
	}

	var json := JSON.stringify(result, "  ")
	var result_file := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if result_file == null:
		_fail("Cannot write the experiment report: %s" % [FileAccess.get_open_error()])
		return
	result_file.store_string(json + "\n")
	result_file.close()
	print(json)

	var passed: bool = result.result == "pass"
	scene_root.queue_free()
	await process_frame
	if passed:
		quit(0)
	else:
		quit(1)


func _find_named(root: Node, target: String) -> Node:
	if root.name == target:
		return root
	for child in root.get_children():
		var found := _find_named(child, target)
		if found != null:
			return found
	return null


func _near_vec3(a: Vector3, b: Vector3) -> bool:
	return absf(a.x - b.x) <= TOLERANCE and absf(a.y - b.y) <= TOLERANCE and absf(a.z - b.z) <= TOLERANCE


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
