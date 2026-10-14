extends SceneTree

const Imported := preload("res://aircraft/imported_model.gd")
const Registry := preload("res://aircraft/model_registry.gd")
const Timber := preload("res://aircraft/timber_model.gd")
const TimberGeometry := preload("res://aircraft/timber_geometry.gd")
const TimberScene := preload("res://assets/aircraft/turbo-lumber-evolution/timber.glb")
const FAMILY_ID := "turbo-lumber-evolution"
const EXPECTED_GEAR_WRAPPERS := {
	"left": "wheel_left_spin",
	"right": "wheel_right_spin",
	"tail": "wheel_tail_spin",
	"steering": "tail_steering",
}

var _checks := 0
var _failures := 0
var _manifest: Dictionary = {}


func _initialize() -> void:
	var described: Dictionary = Registry.describe(FAMILY_ID)
	_check("registered Timber manifest is valid", bool(described.get("ok", false)), str(described.get("errors", [])))
	if not described.get("ok", false):
		print("Imported aircraft model: %d checks, %d failures" % [_checks, _failures])
		quit(1)
		return
	_manifest = described.manifest
	_check("Timber uses the shared v2 imported builder", _manifest.version == 2 and _manifest.builder.script == "res://aircraft/imported_model.gd")
	_test_real_timber_and_instance_isolation()
	_test_renamed_nodes()
	_test_split_elevator()
	_test_zero_rotor_marker()
	_test_signed_rotor_axes()
	_test_rejections_and_ownership()
	print("Imported aircraft model: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_real_timber_and_instance_isolation() -> void:
	var first_result: Dictionary = Imported.build_checked(_manifest.duplicate(true))
	_check("build_checked constructs the real Timber scene", first_result.get("ok", false), str(first_result.get("errors", [])))
	if not first_result.get("ok", false):
		return
	var first: Dictionary = first_result.model
	var first_root := first.get("root") as Node3D
	var second_result: Dictionary = Imported.build_checked(_manifest.duplicate(true))
	_check("a second Timber instance constructs", second_result.get("ok", false), str(second_result.get("errors", [])))
	if not second_result.get("ok", false):
		first_root.free()
		return
	var second: Dictionary = second_result.model
	var second_root := second.get("root") as Node3D
	_check("public root uses stable airplane name", first_root.name == "airplane")
	_check("instances own distinct roots", first_root != second_root)
	_check("built identity comes from manifest family", first.aircraft_id == FAMILY_ID)
	_check("asset hash and revision are carried on root",
		str(first_root.get_meta("asset_sha256", "")) == str(_manifest.asset.sha256) and
		str(first_root.get_meta("visual_revision", "")) == str(_manifest.asset.revision))
	_check("shared derived checks accept Timber", Registry.validate_derived(_manifest, first).ok)

	var cowl_a := _find_mesh(first_root, "cowl")
	var cowl_b := _find_mesh(second_root, "cowl")
	_check("independent builds share immutable cowl mesh resource", cowl_a != null and cowl_b != null and cowl_a.mesh == cowl_b.mesh)
	var black_a := _override_for(cowl_a, "black")
	var red_a := _override_for(cowl_a, "red")
	var black_b := _override_for(cowl_b, "black")
	var red_b := _override_for(cowl_b, "red")
	_check("cowl black and red materials are instance-local overrides", black_a != null and red_a != null and black_b != null and red_b != null and black_a != black_b and red_a != red_b)
	_check("cowl override names and grow settings match authoring rule",
		black_a != null and black_a.resource_name == "black" and black_a.grow and is_equal_approx(black_a.grow_amount, 0.0008) and
		red_a != null and red_a.resource_name == "red" and red_a.grow and is_equal_approx(red_a.grow_amount, 0.0008))
	if cowl_a != null and cowl_a.mesh != null:
		var source_materials_unchanged := true
		for surface in cowl_a.mesh.get_surface_count():
			var source := cowl_a.mesh.surface_get_material(surface) as StandardMaterial3D
			if source != null and (source.resource_name == "black" or source.resource_name == "red"):
				source_materials_unchanged = source_materials_unchanged and not source.grow and is_zero_approx(source.grow_amount)
		_check("shared cowl materials remain unchanged", source_materials_unchanged)

	var hinges_are_independent := true
	var rest_is_preserved := true
	for control in _manifest.bindings.controls.values():
		for binding in control.hinges:
			var key := str(binding.key)
			var first_hinge: Dictionary = first.hinges.get(key, {})
			var second_hinge: Dictionary = second.hinges.get(key, {})
			var node_a := first_hinge.get("node") as Node3D
			var node_b := second_hinge.get("node") as Node3D
			hinges_are_independent = hinges_are_independent and node_a != null and node_b != null and node_a != node_b
			if node_a != null:
				rest_is_preserved = rest_is_preserved and node_a.basis.is_equal_approx(first_hinge.rest)
	_check("independent models have distinct hinge pivots", hinges_are_independent)
	_check("control and visual hinge entries start at their imported rest bases", rest_is_preserved)

	var physical_surfaces := {"aileron_left": -12.0, "aileron_right": 18.0, "elevator": 9.0, "rudder": -8.0,
		"flap_left": 35.0, "flap_right": 35.0}
	var flap_left: Dictionary = first.hinges["flap_left"]
	var flap_right: Dictionary = first.hinges["flap_right"]
	var flap_left_rest: Basis = flap_left.rest
	var flap_right_rest: Basis = flap_right.rest
	Imported.apply_surfaces(first, physical_surfaces)
	var physical_changed := true
	for role in ["aileron_left", "aileron_right", "elevator", "rudder"]:
		var binding: Dictionary = _manifest.bindings.controls[role].hinges[0]
		physical_changed = physical_changed and not first.hinges[binding.key].node.basis.is_equal_approx(first.hinges[binding.key].rest)
	_check("physical surface commands move authored controls", physical_changed)
	_check("apply_surfaces ignores nonphysical flap bindings",
		flap_left.node.basis.is_equal_approx(flap_left_rest) and flap_right.node.basis.is_equal_approx(flap_right_rest))
	_check("posing one model leaves the second at rest", _all_hinges_at_rest(second))
	Imported.set_visual_surfaces(first, {"flap_left": 99.0, "flap_right": 99.0})
	_check("visual flap commands clamp to authored travel",
		_basis_matches_angle(flap_left, 40.0) and _basis_matches_angle(flap_right, 40.0))
	Imported.apply_surfaces(first, {"aileron_left": 0.0, "aileron_right": 0.0, "elevator": 0.0, "rudder": 0.0})
	Imported.set_visual_surfaces(first, {"flap_left": 0.0, "flap_right": 0.0})
	_check("zero surface command restores imported rest bases", _all_hinges_at_rest(first))

	var gear_keys: Dictionary = _manifest.bindings.gear.keys
	var gear_wrappers_match := true
	for role_variant in gear_keys.keys():
		var role := str(role_variant)
		var gear_key := str(gear_keys[role_variant])
		var wrapper: Node3D = first.gear.get(gear_key) as Node3D
		var entry := _gear_construction(first.model_manifest, role)
		gear_wrappers_match = (gear_wrappers_match and wrapper != null and entry != null and
			wrapper.name == str(entry.wrapper) and str(entry.wrapper) == EXPECTED_GEAR_WRAPPERS.get(role, ""))
	_check("gear roles map through manifest aliases to stable wrappers", gear_wrappers_match)
	_check("Timber rotor wrapper and presence are explicit", first.get("has_propeller", false) and first.propeller.name == "propeller")

	var wreck := first_root.duplicate() as Node3D
	_check("scene root is safe to duplicate for wreck creation", wreck != null and first_root.scene_file_path.is_empty())
	if wreck != null:
		var copied_wing := wreck.find_child("wing_left_fixed", true, false)
		var extras: Variant = copied_wing.get_meta("extras", {}) if copied_wing != null else {}
		_check("wreck copy retains imported crash section metadata",
			typeof(extras) == TYPE_DICTIONARY and extras.get("openrc_section") == "wing_left")
		_check("wreck copy retains generated propeller wrapper", wreck.find_child("propeller", true, false) is Node3D)
		wreck.free()

	var facade_model: Dictionary = Timber.build()
	_check("Timber compatibility facade builds through the shared registry", facade_model.get("root") is Node3D)
	if facade_model.get("root") is Node3D:
		facade_model.root.free()
	second_root.free()
	first_root.free()


func _test_renamed_nodes() -> void:
	var manifest := _manifest.duplicate(true)
	var data: Dictionary = TimberGeometry.DATA.duplicate(true)
	var root := _new_scene()
	var hinge_name := "synthetic_aileron_left_hinge"
	var frame_name := "synthetic_thrust_frame"
	var spin_name := "synthetic_propeller_spin"
	var wheel_name := "synthetic_wheel_left_axle"
	_find_node(root, "aileron_left_hinge").name = hinge_name
	manifest.bindings.controls.aileron_left.hinges[0].node = hinge_name
	data.articulations.aileron_left_hinge.node = hinge_name
	_find_node(root, "thrust_frame").name = frame_name
	_find_node(root, "propeller_spin").name = spin_name
	manifest.construction.rotor.frame_node = frame_name
	manifest.bindings.rotor.spin_node = spin_name
	data.thrust.node = frame_name
	data.thrust.spin_node = spin_name
	data.articulations.propeller_spin.node = spin_name
	data.articulations.propeller_spin.parent = frame_name
	_find_node(root, "wheel_left_axle").name = wheel_name
	data.articulations.wheel_left_axle.node = wheel_name
	for entry in manifest.construction.gear:
		if entry.role == "left":
			entry.node = wheel_name
	var result := Imported.build_scene(root, data, manifest)
	_check("imported builder accepts authored renamed nodes with stable hinge suffix", result.get("ok", false), str(result.get("errors", [])))
	if result.get("ok", false):
		var model: Dictionary = result.model
		_check("renamed hinge is returned under its declared key", model.hinges.aileron_left.node.name == hinge_name)
		_check("signed rotor binding resolves renamed frame and spin node",
			model.propeller.name == "propeller" and model.root.find_child(spin_name, true, false) != null)
		_check("gear alias resolves the renamed axle wrapper", model.gear[_manifest.bindings.gear.keys.left].name == str(_gear_construction(manifest, "left").wrapper))
		model.root.free()


func _test_split_elevator() -> void:
	var manifest := _manifest.duplicate(true)
	var data: Dictionary = TimberGeometry.DATA.duplicate(true)
	var root := _new_scene()
	var original := _find_node(root, "elevator_hinge")
	var parent := original.get_parent() as Node3D
	var right_hinge := original.duplicate() as Node3D
	var left_mesh := original.get_node("elevator") as MeshInstance3D
	var right_mesh := right_hinge.get_node("elevator") as MeshInstance3D
	var rest_record: Dictionary = data.articulations.elevator_hinge.duplicate(true)
	original.name = "elevator_left_hinge"
	left_mesh.name = "elevator_left"
	right_hinge.name = "elevator_right_hinge"
	right_mesh.name = "elevator_right"
	parent.add_child(right_hinge)
	var left_position := original.position + Vector3(-0.05, 0.0, 0.0)
	var right_position := right_hinge.position + Vector3(0.05, 0.0, 0.0)
	original.position = left_position
	right_hinge.position = right_position
	data.articulations["elevator_split_left"] = _split_articulation(rest_record, "elevator_left_hinge", parent.name, left_position)
	data.articulations["elevator_split_right"] = _split_articulation(rest_record, "elevator_right_hinge", parent.name, right_position)
	manifest.bindings.controls.elevator.hinges = [
		{"key": "elevator_left", "node": "elevator_left_hinge", "source": "geometry_articulation", "geometry_ref": "articulations.elevator_split_left"},
		{"key": "elevator_right", "node": "elevator_right_hinge", "source": "geometry_articulation", "geometry_ref": "articulations.elevator_split_right"},
	]
	var result := Imported.build_scene(root, data, manifest)
	_check("synthetic duplicated subtree supports a split two-hinge elevator", result.get("ok", false), str(result.get("errors", [])))
	if not result.get("ok", false):
		return
	var model: Dictionary = result.model
	_check("both split elevator hinges resolve from distinct data references",
		model.hinges.has("elevator_left") and model.hinges.has("elevator_right") and
		model.hinges.elevator_left.node.name == "elevator_left_hinge" and model.hinges.elevator_right.node.name == "elevator_right_hinge")
	_check("split elevator subtree meshes remain attached to their hinges",
		model.root.find_child("elevator_left", true, false).get_parent() == model.hinges.elevator_left.node and
		model.root.find_child("elevator_right", true, false).get_parent() == model.hinges.elevator_right.node)
	Imported.apply_surfaces(model, {"elevator": 11.0})
	_check("one physical elevator command moves both split hinges",
		_basis_matches_angle(model.hinges.elevator_left, 11.0) and _basis_matches_angle(model.hinges.elevator_right, 11.0))
	model.root.free()


func _test_zero_rotor_marker() -> void:
	var manifest := _manifest.duplicate(true)
	var data: Dictionary = TimberGeometry.DATA.duplicate(true)
	var root := _new_scene()
	var spin := _find_node(root, str(manifest.bindings.rotor.spin_node))
	spin.get_parent().remove_child(spin)
	spin.free()
	manifest.bindings.rotor.present = false
	manifest.bindings.rotor.spin_node = ""
	manifest.bindings.rotor.authored_diameter_m = 0.0
	manifest.bindings.rotor.source = "none"
	manifest.bindings.rotor.geometry_ref = ""
	manifest.construction.rotor = {}
	var result := Imported.build_scene(root, data, manifest)
	_check("zero-rotor imported aircraft builds without a rotor subtree", result.get("ok", false), str(result.get("errors", [])))
	if result.get("ok", false):
		var model: Dictionary = result.model
		_check("zero-rotor model still exposes its public propeller marker",
			not model.has_propeller and model.propeller is Node3D and model.propeller.name == "propeller" and model.root.is_ancestor_of(model.propeller))
		_check("zero-rotor marker does not capture deleted rotor geometry", model.root.find_child("propeller_spin", true, false) == null)
		model.root.free()


func _test_signed_rotor_axes() -> void:
	for axis_name in Imported.Construction.AXES:
		var manifest := _manifest.duplicate(true)
		manifest.construction.rotor.axis = axis_name
		var root := _new_scene()
		var result := Imported.build_scene(root, TimberGeometry.DATA.duplicate(true), manifest)
		_check("signed rotor axis builds: " + axis_name, result.get("ok", false), str(result.get("errors", [])))
		if not result.get("ok", false):
			continue
		var model: Dictionary = result.model
		var frame := _find_node(model.root, str(manifest.construction.rotor.frame_node))
		var axis := _axis_vector(axis_name)
		var expected_root_axis := (Imported.relative(model.root, frame).basis * axis).normalized()
		var actual_root_axis := (Imported.relative(model.root, model.propeller).basis.z).normalized()
		_check("signed rotor axis maps to the propeller Euler Z axis: " + axis_name,
			actual_root_axis.dot(expected_root_axis) > 0.99999,
			"actual=%s expected=%s" % [str(actual_root_axis), str(expected_root_axis)])
		model.root.free()


func _test_rejections_and_ownership() -> void:
	var manifest := _manifest.duplicate(true)
	var data: Dictionary = TimberGeometry.DATA.duplicate(true)
	var root := _new_scene()
	var missing := _find_node(root, "aileron_left_hinge")
	missing.get_parent().remove_child(missing)
	missing.free()
	_expect_rejected_and_freed("missing bound node rejects and frees ownership", root, data, manifest)

	root = _new_scene()
	var duplicate := Node3D.new()
	root.add_child(duplicate)
	duplicate.name = "aileron_left_hinge"
	_check("duplicate fixture contains two matching names", _count_name(root, "aileron_left_hinge") == 2)
	_expect_rejected_and_freed("duplicate bound node rejects and frees ownership", root, TimberGeometry.DATA.duplicate(true), _manifest.duplicate(true))

	root = _new_scene()
	var nonfinite := _find_node(root, "wing_left_fixed")
	var nonfinite_transform := nonfinite.transform
	nonfinite_transform.origin.x = INF
	nonfinite.transform = nonfinite_transform
	_expect_rejected_and_freed("non-finite scene transform rejects and frees ownership", root, TimberGeometry.DATA.duplicate(true), _manifest.duplicate(true))

	root = _new_scene()
	var singular := _find_node(root, "aileron_left_hinge")
	var singular_transform := singular.transform
	singular_transform.basis.x = Vector3.ZERO
	singular.transform = singular_transform
	_expect_rejected_and_freed("singular mechanical transform rejects and frees ownership", root, TimberGeometry.DATA.duplicate(true), _manifest.duplicate(true))

	root = _new_scene()
	var nonorthogonal_parent := _find_node(root, "aileron_left_hinge").get_parent() as Node3D
	nonorthogonal_parent.scale = Vector3(1.03, 1.0, 1.0)
	_expect_rejected_and_freed("scaled non-orthonormal mechanism ancestor rejects and frees ownership", root, TimberGeometry.DATA.duplicate(true), _manifest.duplicate(true))

	var wrong_ref_manifest := _manifest.duplicate(true)
	wrong_ref_manifest.construction.rotor.geometry_ref = "thrust.missing"
	_expect_rejected_and_freed("unresolved source reference rejects and frees ownership", _new_scene(), TimberGeometry.DATA.duplicate(true), wrong_ref_manifest)

	var mismatched_ref_manifest := _manifest.duplicate(true)
	for entry in mismatched_ref_manifest.construction.gear:
		if entry.role == "left": entry.geometry_ref = "articulations.rudder_hinge"
	_expect_rejected_and_freed("reference resolving to the wrong articulation rejects and frees ownership",
		_new_scene(), TimberGeometry.DATA.duplicate(true), mismatched_ref_manifest)

	var wrong_parent_data: Dictionary = TimberGeometry.DATA.duplicate(true)
	wrong_parent_data.articulations.aileron_left_hinge.parent = "not_the_scene_parent"
	_expect_rejected_and_freed("geometry parent reference mismatch rejects and frees ownership",
		_new_scene(), wrong_parent_data, _manifest.duplicate(true))

	var wrong_node_data: Dictionary = TimberGeometry.DATA.duplicate(true)
	wrong_node_data.articulations.aileron_left_hinge.node = "a_different_hinge"
	_expect_rejected_and_freed("geometry node reference mismatch rejects and frees ownership",
		_new_scene(), wrong_node_data, _manifest.duplicate(true))


func _expect_rejected_and_freed(label: String, root: Node3D, data: Dictionary, manifest: Dictionary) -> void:
	var result: Dictionary = Imported.build_scene(root, data, manifest)
	_check(label, not bool(result.get("ok", true)), str(result.get("errors", [])))
	_check(label + " (ownership transferred)", not is_instance_valid(root))


func _all_hinges_at_rest(model: Dictionary) -> bool:
	for hinge in model.hinges.values():
		if not (hinge is Dictionary) or not (hinge.get("node") is Node3D):
			return false
		if not hinge.node.basis.is_equal_approx(hinge.rest):
			return false
	return true


func _basis_matches_angle(hinge: Dictionary, degrees: float) -> bool:
	var expected: Basis = hinge.rest if degrees == 0.0 else Basis(hinge.axis, deg_to_rad(degrees * float(hinge.app_sign))) * hinge.rest
	return (hinge.node as Node3D).basis.is_equal_approx(expected)


func _split_articulation(original: Dictionary, node_name: String, parent_name: String, position: Vector3) -> Dictionary:
	var result: Dictionary = original.duplicate(true)
	result.node = node_name
	result.parent = parent_name
	result.pivot = _vector_array(position)
	result.rest_translation = _vector_array(position)
	return result


func _vector_array(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]


func _axis_vector(axis_name: String) -> Vector3:
	var sign := -1.0 if axis_name.begins_with("-") else 1.0
	match axis_name.right(1):
		"X": return Vector3(sign, 0.0, 0.0)
		"Y": return Vector3(0.0, sign, 0.0)
		"Z": return Vector3(0.0, 0.0, sign)
	return Vector3.ZERO


func _gear_construction(manifest: Dictionary, role: String) -> Dictionary:
	for entry in manifest.construction.gear:
		if str(entry.get("role", "")) == role:
			return entry
	return {}


func _find_node(root: Node, name: String) -> Node3D:
	return root.find_child(name, true, false) as Node3D


func _find_mesh(root: Node, name: String) -> MeshInstance3D:
	return root.find_child(name, true, false) as MeshInstance3D


func _override_for(mesh: MeshInstance3D, material_name: String) -> StandardMaterial3D:
	if mesh == null or mesh.mesh == null:
		return null
	for surface in mesh.mesh.get_surface_count():
		var material := mesh.get_surface_override_material(surface) as StandardMaterial3D
		if material != null and str(material.resource_name) == material_name:
			return material
	return null


func _new_scene() -> Node3D:
	return TimberScene.instantiate() as Node3D


func _count_name(root: Node, name: String) -> int:
	var count := 1 if str(root.name) == name else 0
	for node in root.find_children("*", "", true, false):
		if str(node.name) == name:
			count += 1
	return count


func _check(label: String, condition: bool, detail := "") -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])
