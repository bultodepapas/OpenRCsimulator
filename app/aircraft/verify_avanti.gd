# AV-31 scratch qualification for the imported VentageJet Avanti GLB.
# Copy into app/aircraft/verify_avanti.gd only after the generated model is accepted.
# Run from app with: godot --headless --path app --script res://aircraft/verify_avanti.gd
extends SceneTree

const AD := preload("res://physics/aircraft_data.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Builder := preload("res://render/airplane.gd")
const Commands := preload("res://input/commands.gd")
const Imported := preload("res://aircraft/imported_model.gd")
const Registry := preload("res://aircraft/model_registry.gd")

const EXPECTED_ARTICULATIONS := [
	"aileron_left_hinge", "aileron_right_hinge",
	"elevator_left_hinge", "elevator_right_hinge",
	"rudder_hinge", "flap_left_hinge", "flap_right_hinge",
]
const ARTICULATION_TO_BINDING := {
	"aileron_left_hinge": "aileron_left",
	"aileron_right_hinge": "aileron_right",
	"elevator_left_hinge": "elevator_left",
	"elevator_right_hinge": "elevator_right",
	"rudder_hinge": "rudder",
	"flap_left_hinge": "flap_left",
	"flap_right_hinge": "flap_right",
}
const BINDING_TO_CONTROL := {
	"aileron_left": "aileron_left", "aileron_right": "aileron_right",
	"elevator_left": "elevator", "elevator_right": "elevator",
	"rudder": "rudder", "flap_left": "flap_left", "flap_right": "flap_right",
}
const EXPECTED_SURFACE_SECTIONS := {
	"aileron_left": "wing_left", "flap_left": "wing_left",
	"aileron_right": "wing_right", "flap_right": "wing_right",
	"elevator_left": "horizontal_tail", "elevator_right": "horizontal_tail",
	"rudder": "vertical_tail",
}
const CRASH_SECTIONS := ["core", "wing_left", "wing_right", "wing_center", "engine", "propeller",
	"horizontal_tail", "vertical_tail", "gear", "canopy"]
const REST_TOLERANCE_M := 0.00002
const GEOMETRY_TOLERANCE_M := 0.002
const NOMINAL_SPAN_TOLERANCE_M := 0.01
const NOMINAL_LENGTH_TOLERANCE_M := 0.02
const MIN_PANEL_TRAVEL_M := 0.001
const POSE_TOLERANCE_M := 0.00005
const ANGLE_TOLERANCE_RAD := 0.00001

var _checks := 0
var _failures := 0


func _check(label: String, passed: bool, detail := "") -> void:
	_checks += 1
	if not passed:
		_failures += 1
		printerr("FAIL AV-31 " + label + (" · " + detail if not detail.is_empty() else ""))


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var aircraft_id := Builder.AVANTI_ID
	var family := Catalog.visual_family(aircraft_id)
	var described: Dictionary = Registry.describe(family)
	_check("catalog family resolves", not family.is_empty())
	_check("model manifest resolves", described.get("ok", false), str(described.get("errors", [])))
	if not described.get("ok", false):
		_finish()
		return
	var manifest: Dictionary = described.manifest
	_check("version 2 common imported builder", manifest.version == 2
		and manifest.builder.script == "res://aircraft/imported_model.gd"
		and manifest.builder.adapter == "imported_glb")
	_check("imported GLB asset", manifest.asset.kind == "imported_glb")
	_check("local +X hinge construction", manifest.construction.hinge_axis == "+X")
	_check("rotor is absent in construction", manifest.construction.get("rotor", {}).is_empty())
	_check("gear is absent in construction", manifest.construction.get("gear", []).is_empty())
	_check("no rotor or gear bindings", not manifest.bindings.rotor.present
		and manifest.bindings.gear.keys.is_empty())
	_check("GLTF extras crash sections enabled", manifest.bindings.crash.provider == "gltf_extras")

	var geometry_script := load(str(manifest.geometry.script)) as Script
	_check("generated geometry script loads", geometry_script != null)
	if geometry_script == null:
		_finish()
		return
	var geometry_data: Variant = geometry_script.get("DATA")
	_check("generated geometry DATA is a dictionary", typeof(geometry_data) == TYPE_DICTIONARY)
	if typeof(geometry_data) != TYPE_DICTIONARY:
		_finish()
		return
	var data: Dictionary = geometry_data
	_check("geometry articulations are the canonical seven", _same_string_keys(data.get("articulations", {}), EXPECTED_ARTICULATIONS))
	_check("geometry revision matches asset", data.get("revision", "") == manifest.asset.revision)
	_check("geometry carries nominal bounds and turbine metadata",
		data.has_all(["nominal", "bounds", "turbine", "gear_pose"]))
	_check("source model is in gear-stowed pose", data.get("gear_pose", {}).get("state", "") == "stowed"
		and int(data.get("gear_pose", {}).get("source_frame", -1)) == 211)

	var build: Dictionary = Builder.build(aircraft_id)
	var root := build.get("root") as Node3D
	_check("generic registry/renderer builds Avanti", root != null and build.get("aircraft_id", "") == aircraft_id)
	if root == null:
		_finish()
		return
	get_root().add_child(root)
	await process_frame
	_check("public root name", root.name == "airplane")
	_check("builder uses generated geometry DATA", build.has("data") and is_same(build.data, data))
	_check("root revision matches generated geometry", root.get_meta("visual_revision", "") == data.revision)
	var derived: Dictionary = Registry.validate_derived(manifest, build)
	_check("registry derived validation", derived.get("ok", false), str(derived.get("errors", [])))

	var propeller := build.get("propeller") as Node3D
	_check("public propeller marker is empty", propeller != null and propeller.name == "propeller"
		and propeller.get_child_count() == 0 and not build.get("has_propeller", true))
	_check("gear wrappers are empty", build.get("gear", {}) is Dictionary and build.gear.is_empty())
	_check("no imported propeller mesh", _no_propeller_mesh(root))
	_check("stowed gear geometry is present", root.find_child("gear_stowed", true, false) is MeshInstance3D)

	_check_sections(root)
	_check_articulations(build, data)
	var bounds_result := _mesh_bounds(root, root)
	_check("visible imported geometry has finite vertices", bounds_result.valid and bounds_result.mesh_count > 0)
	if bounds_result.valid:
		_check_bounds_against_geometry(bounds_result.box, data)
	_check_turbine_geometry(root, data)

	var physical_result: Dictionary = AD.load_file(Catalog.entry(aircraft_id).data)
	_check("physical Avanti data loads", physical_result.get("ok", false), str(physical_result.get("errors", [])))
	var raw_physical: Variant = JSON.parse_string(FileAccess.get_file_as_string(Catalog.entry(aircraft_id).data))
	var witnesses := _capture_witnesses(build, data)
	var rest_transforms := _rest_transforms(build)
	if physical_result.get("ok", false) and not witnesses.is_empty():
		var physical: Dictionary = physical_result.model
		var engine_name := str(raw_physical.get("propulsion", {}).get("engine", {}).get("name", "")) \
			if typeof(raw_physical) == TYPE_DICTIONARY else ""
		_check("physics configuration names the P100-RX turbine", physical.propulsion.kind == "turbine"
			and engine_name.contains(str(data.turbine.model)))
		_run_full_throw_cases(build, data, witnesses, rest_transforms, physical.controls.throw_deg)
		_run_visual_flap_case(build, data, witnesses, rest_transforms, physical.controls.throw_deg)
	else:
		_check("actual mesh witnesses are available for travel checks", false)

	_check("first instance geometry source remains pure", build.get("data", {}) == data)
	var second: Dictionary = Builder.build(aircraft_id)
	var second_root := second.get("root") as Node3D
	_check("second instance builds", second_root != null)
	if second_root != null:
		get_root().add_child(second_root)
		await process_frame
		_check("instances own distinct nodes", _instances_have_distinct_nodes(build, second))
		_check("second instance shares the same immutable source data", second.get("data", {}) == data)
		var second_witnesses := _capture_witnesses(second, data)
		var second_rest := _rest_transforms(second)
		var original_snapshot: Dictionary = data.duplicate(true)
		if physical_result.get("ok", false):
			var command := {roll = 1.0, pitch = 1.0, yaw = 1.0, throttle = 0.0}
			Builder.apply_surfaces(build, Commands.hinge_rotations(command, physical_result.model.controls.throw_deg))
			Imported.set_visual_surfaces(build, {flap_left = 999.0, flap_right = 999.0})
			_check("posing first instance leaves second instance neutral", _poses_match(second, second_witnesses,
				second_rest, _witness_positions(second, second_witnesses)))
			_check("per-instance pose leaves generated geometry data unchanged", data == original_snapshot)
			_neutralize(build, physical_result.model.controls.throw_deg)
			Imported.set_visual_surfaces(build, {flap_left = 0.0, flap_right = 0.0})
			_check("first instance returns to exact neutral", _poses_match(build, witnesses, rest_transforms,
				_witness_positions(build, witnesses)))
		_check("both instances retain source-data purity", build.data == original_snapshot and second.data == original_snapshot)

	var mesh_count: int = int(bounds_result.mesh_count) if bounds_result.valid else 0
	var art_count: int = data.get("articulations", {}).size()
	print("AV-31 Avanti imported model %s: %d meshes, %d articulations, %d checks, %d failures" %
		[data.revision, mesh_count, art_count, _checks, _failures])
	if second_root != null:
		second_root.free()
	root.free()
	_finish(false)


func _finish(print_summary := true) -> void:
	if print_summary:
		print("AV-31 Avanti imported model: %d checks, %d failures" % [_checks, _failures])
	if _failures == 0:
		print("PASS AV-31 %d checks" % _checks)
	else:
		printerr("FAIL AV-31 %d of %d checks" % [_failures, _checks])
	quit(1 if _failures > 0 else 0)


func _same_string_keys(value: Variant, expected: Array) -> bool:
	if typeof(value) != TYPE_DICTIONARY:
		return false
	var actual: Array[String] = []
	for key in value.keys():
		actual.append(str(key))
	actual.sort()
	var sorted_expected: Array[String] = []
	for key in expected:
		sorted_expected.append(str(key))
	sorted_expected.sort()
	return actual == sorted_expected


func _no_propeller_mesh(root: Node3D) -> bool:
	for mesh in _meshes_under(root):
		if str(mesh.name).to_lower().contains("propeller"):
			return false
	return true


func _meshes_under(subtree: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if subtree is MeshInstance3D:
		out.append(subtree)
	for child in subtree.get_children():
		out.append_array(_meshes_under(child))
	return out


func _check_sections(root: Node3D) -> void:
	var mesh_count := 0
	var missing_mesh_sections := 0
	var invalid_sections := 0
	for node in [root] + root.find_children("*", "", true, false):
		var extras: Variant = node.get_meta("extras", {})
		if node is MeshInstance3D:
			mesh_count += 1
			var section := str(extras.get("openrc_section", "")) if typeof(extras) == TYPE_DICTIONARY else ""
			if section.is_empty():
				missing_mesh_sections += 1
			elif not CRASH_SECTIONS.has(section):
				invalid_sections += 1
	_check("every imported mesh has an allowed GLTF extras section", mesh_count > 0
		and missing_mesh_sections == 0 and invalid_sections == 0,
		"meshes=%d missing=%d invalid=%d" % [mesh_count, missing_mesh_sections, invalid_sections])
	var hinge_sections := 0
	for hinge_name: String in EXPECTED_ARTICULATIONS:
		var binding := str(ARTICULATION_TO_BINDING[hinge_name])
		var node := root.find_child(hinge_name, true, false)
		var extras: Variant = node.get_meta("extras", {}) if node != null else {}
		var expected_section := str(EXPECTED_SURFACE_SECTIONS[binding])
		var section_matches: bool = typeof(extras) == TYPE_DICTIONARY and extras.get("openrc_section", "") == expected_section
		_check("%s section is %s" % [hinge_name, expected_section], section_matches)
		if section_matches:
			hinge_sections += 1
	_check("all seven articulated pivots carry GLTF extras sections", hinge_sections == EXPECTED_ARTICULATIONS.size(),
		"found=%d" % hinge_sections)


func _check_articulations(model: Dictionary, data: Dictionary) -> void:
	var articulations: Dictionary = data.get("articulations", {})
	var hinges: Dictionary = model.get("hinges", {})
	_check("runtime hinge map has all seven stable keys", hinges.size() == EXPECTED_ARTICULATIONS.size())
	for hinge_name: String in EXPECTED_ARTICULATIONS:
		var binding := str(ARTICULATION_TO_BINDING[hinge_name])
		var record: Dictionary = articulations.get(hinge_name, {})
		var entry: Dictionary = hinges.get(binding, {})
		var node := entry.get("node") as Node3D
		_check("%s metadata and runtime hinge exist" % hinge_name, not record.is_empty() and node != null)
		if node == null or record.is_empty():
			continue
		var source_parent := str(record.get("parent", ""))
		_check("%s remains under its authored sibling parent" % hinge_name,
			node.get_parent() != null and node.get_parent().name == source_parent
			and model.root.is_ancestor_of(node) and source_parent == "VentageJet",
			"actual parent=%s path=%s" % [str(node.get_parent().name), str(node.get_path())])
		var surface_name := str(record.get("surface_node", ""))
		var surface := model.root.find_child(surface_name, true, false) as MeshInstance3D
		_check("%s has a named physical surface mesh" % hinge_name, not surface_name.is_empty()
			and surface != null and node.is_ancestor_of(surface))
		var translation := _vector3(record.get("rest_translation", []))
		var rest_basis := _basis(record.get("rest_basis", {}))
		var range_value: Variant = record.get("range_deg", [])
		var valid_range: bool = range_value is Array and range_value.size() == 2
		if valid_range:
			valid_range = _finite_number(range_value[0]) and _finite_number(range_value[1]) and float(range_value[0]) < float(range_value[1])
		var app_sign := float(record.get("app_sign", 0.0))
		_check("%s has finite increasing app-deflection limits" % hinge_name, valid_range)
		_check("%s application sign is exactly +/-1" % hinge_name, absf(app_sign) == 1.0)
		_check("%s has the generated positive-motion description" % hinge_name,
			str(record.get("positive", "")).begins_with("trailing edge "))
		_check("%s rest translation matches the imported pivot" % hinge_name,
			translation.is_finite() and node.position.distance_to(translation) <= REST_TOLERANCE_M)
		_check("%s rest basis is proper and matches the imported pivot" % hinge_name,
			rest_basis.is_finite() and absf(rest_basis.determinant() - 1.0) <= 0.00002
			and (rest_basis.transposed() * rest_basis).is_equal_approx(Basis.IDENTITY)
			and node.basis.is_equal_approx(rest_basis))
		_check("%s articulation axis is local +X" % hinge_name,
			entry.get("axis") is Vector3 and node.basis.x.normalized().distance_to(entry.axis) <= 0.00001)
		_check("%s starts at authored neutral" % hinge_name, node.transform.is_finite()
			and node.position.distance_to(translation) <= REST_TOLERANCE_M and node.basis.is_equal_approx(rest_basis))
		_check("%s runtime range and positive semantics match data" % hinge_name,
			entry.get("range_deg", []) == range_value and entry.get("positive", "") == record.get("positive", "")
			and absf(float(entry.get("app_sign", 0.0)) - app_sign) < 1.0e-8)


func _capture_witnesses(model: Dictionary, data: Dictionary) -> Dictionary:
	var output := {}
	var articulations: Dictionary = data.get("articulations", {})
	for hinge_name: String in EXPECTED_ARTICULATIONS:
		var record: Dictionary = articulations.get(hinge_name, {})
		var surface_name := str(record.get("surface_node", ""))
		var surface := model.root.find_child(surface_name, true, false) as MeshInstance3D
		if surface == null or surface.mesh == null:
			_check("%s mesh witness source exists" % hinge_name, false, surface_name)
			continue
		var faces := surface.mesh.get_faces()
		var target := _vector3(record.get("witness_model", []))
		var root_from_mesh := Imported.relative(model.root, surface)
		var best_distance_sq := INF
		var best_vertex := Vector3.ZERO
		var best_point := Vector3.ZERO
		for vertex: Vector3 in faces:
			var point := root_from_mesh * vertex
			var distance_sq := point.distance_squared_to(target)
			if distance_sq < best_distance_sq:
				best_distance_sq = distance_sq
				best_vertex = vertex
				best_point = point
		_check("%s metadata witness resolves to an actual panel vertex" % hinge_name,
			target.is_finite() and best_distance_sq < 0.002 * 0.002 and not faces.is_empty(),
			"distance=%.6f m" % sqrt(best_distance_sq) if is_finite(best_distance_sq) else "no surface faces")
		if is_finite(best_distance_sq):
			output[hinge_name] = {"mesh": surface, "vertex": best_vertex, "rest": best_point,
				"record": record.duplicate(true)}
	return output


func _rest_transforms(model: Dictionary) -> Dictionary:
	var output := {}
	for hinge_name: String in EXPECTED_ARTICULATIONS:
		var binding := str(ARTICULATION_TO_BINDING[hinge_name])
		var entry: Dictionary = model.hinges.get(binding, {})
		if entry.get("node") is Node3D:
			output[hinge_name] = entry.node.transform
	return output


func _witness_positions(model: Dictionary, witnesses: Dictionary) -> Dictionary:
	var output := {}
	for hinge_name: String in witnesses:
		var witness: Dictionary = witnesses[hinge_name]
		output[hinge_name] = Imported.relative(model.root, witness.mesh) * witness.vertex
	return output


func _run_full_throw_cases(model: Dictionary, data: Dictionary, witnesses: Dictionary,
		rest_transforms: Dictionary, throws: Dictionary) -> void:
	var cases := [
		{"name": "right roll", "command": {roll = 1.0, pitch = 0.0, yaw = 0.0, throttle = 0.0}},
		{"name": "left roll", "command": {roll = -1.0, pitch = 0.0, yaw = 0.0, throttle = 0.0}},
		{"name": "pull", "command": {roll = 0.0, pitch = 1.0, yaw = 0.0, throttle = 0.0}},
		{"name": "push", "command": {roll = 0.0, pitch = -1.0, yaw = 0.0, throttle = 0.0}},
		{"name": "right yaw", "command": {roll = 0.0, pitch = 0.0, yaw = 1.0, throttle = 0.0}},
		{"name": "left yaw", "command": {roll = 0.0, pitch = 0.0, yaw = -1.0, throttle = 0.0}},
	]
	for case: Dictionary in cases:
		var command: Dictionary = case.command
		var deflections: Dictionary = Commands.surface_deflections_deg(command, throws)
		var rotations: Dictionary = Commands.hinge_rotations(command, throws)
		Builder.apply_surfaces(model, rotations)
		var current_positions := _witness_positions(model, witnesses)
		for hinge_name: String in EXPECTED_ARTICULATIONS:
			var binding := str(ARTICULATION_TO_BINDING[hinge_name])
			var role := str(BINDING_TO_CONTROL[binding])
			var degrees := float(deflections.get(role, 0.0))
			var entry: Dictionary = model.hinges.get(binding, {})
			if entry.is_empty() or not witnesses.has(hinge_name):
				continue
			var node := entry.node as Node3D
			var record: Dictionary = data.articulations[hinge_name]
			var app_sign := float(record.app_sign)
			var expected_angle := deg_to_rad(degrees * app_sign)
			var actual_angle := _hinge_angle(entry)
			_check("%s %s angle reaches full physical throw" % [case.name, binding],
				absf(actual_angle - expected_angle) <= ANGLE_TOLERANCE_RAD,
				"command=%.3f expected=%.6f actual=%.6f" % [degrees, expected_angle, actual_angle])
			var range_value: Array = record.range_deg
			_check("%s %s physical throw fits authored app range" % [case.name, binding],
				degrees >= float(range_value[0]) - 1.0e-6 and degrees <= float(range_value[1]) + 1.0e-6,
				"command=%.3f range=%s" % [degrees, str(range_value)])
			_check("%s %s pose remains finite" % [case.name, binding], node.transform.is_finite()
				and current_positions.get(hinge_name, Vector3(NAN, NAN, NAN)).is_finite())
			var witness: Dictionary = witnesses[hinge_name]
			var now: Vector3 = current_positions[hinge_name]
			var movement: Vector3 = now - witness.rest
			if absf(degrees) > 1.0e-8:
				var direction := _semantic_axis(str(record.positive))
				var expected_direction: float = movement.dot(direction) * signf(degrees)
				_check("%s %s physical command moves actual panel witness in semantic direction" % [case.name, binding],
					direction.length_squared() > 0.5 and expected_direction > MIN_PANEL_TRAVEL_M,
					"surface %.3f deg moved %s by %s" % [degrees, str(direction), str(movement)])
				var predicted := _expected_witness_position(model, witness, binding, degrees * app_sign)
				_check("%s %s actual mesh witness follows full hinge travel" % [case.name, binding],
					now.distance_to(predicted) <= POSE_TOLERANCE_M,
					"residual=%.6f m" % now.distance_to(predicted))
			else:
				_check("%s leaves %s panel witness neutral" % [case.name, hinge_name],
					movement.length() <= POSE_TOLERANCE_M,
					"moved %s" % str(movement))
		_neutralize(model, throws)
		_check("%s restores every hinge to authored neutral" % case.name,
			_poses_match(model, witnesses, rest_transforms, _witness_positions(model, witnesses)))


func _run_visual_flap_case(model: Dictionary, data: Dictionary, witnesses: Dictionary,
		rest_transforms: Dictionary, throws: Dictionary) -> void:
	var rest_points := _witness_positions(model, witnesses)
	Imported.set_visual_surfaces(model, {flap_left = -999.0, flap_right = -999.0})
	_check("visual flap lower clamp is neutral", _poses_match(model, witnesses, rest_transforms, rest_points))
	Imported.set_visual_surfaces(model, {flap_left = 999.0, flap_right = 999.0})
	var flap_points := _witness_positions(model, witnesses)
	for hinge_name: String in ["flap_left_hinge", "flap_right_hinge"]:
		var binding := str(ARTICULATION_TO_BINDING[hinge_name])
		var entry: Dictionary = model.hinges[binding]
		var record: Dictionary = data.articulations[hinge_name]
		var range_value: Array = record.range_deg
		var expected_angle := deg_to_rad(float(range_value[1]) * float(record.app_sign))
		_check("%s flap reaches its visual upper stop" % binding,
			absf(_hinge_angle(entry) - expected_angle) <= ANGLE_TOLERANCE_RAD)
		var movement: Vector3 = flap_points[hinge_name] - rest_points[hinge_name]
		_check("%s visual flap moves actual mesh witness down" % binding,
			movement.dot(Vector3.DOWN) > MIN_PANEL_TRAVEL_M, "moved %s" % str(movement))
	# Flight controls must not overwrite inspector-only flap poses.
	var command := {roll = 1.0, pitch = 1.0, yaw = 1.0, throttle = 0.0}
	Builder.apply_surfaces(model, Commands.hinge_rotations(command, throws))
	var after_physical := _witness_positions(model, witnesses)
	for hinge_name: String in ["flap_left_hinge", "flap_right_hinge"]:
		_check("physical commands leave visual flap pose independent %s" % hinge_name,
			after_physical[hinge_name].distance_to(flap_points[hinge_name]) <= POSE_TOLERANCE_M)
	_neutralize(model, throws)
	Imported.set_visual_surfaces(model, {flap_left = 0.0, flap_right = 0.0})
	_check("visual flap reset restores all authored neutrals", _poses_match(model, witnesses,
		rest_transforms, _witness_positions(model, witnesses)))


func _neutralize(model: Dictionary, throws: Dictionary) -> void:
	Builder.apply_surfaces(model, Commands.hinge_rotations(
		{roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0}, throws))


func _poses_match(model: Dictionary, witnesses: Dictionary, rest_transforms: Dictionary,
		positions: Dictionary) -> bool:
	var valid := true
	for hinge_name: String in EXPECTED_ARTICULATIONS:
		var binding := str(ARTICULATION_TO_BINDING[hinge_name])
		var entry: Dictionary = model.hinges.get(binding, {})
		if entry.is_empty() or not witnesses.has(hinge_name) or not rest_transforms.has(hinge_name):
			valid = false
			continue
		valid = valid and entry.node.transform == rest_transforms[hinge_name]
		valid = valid and positions.get(hinge_name, Vector3(NAN, NAN, NAN)).distance_to(witnesses[hinge_name].rest) <= POSE_TOLERANCE_M
	return valid


func _instances_have_distinct_nodes(first: Dictionary, second: Dictionary) -> bool:
	if first.root == second.root:
		return false
	for hinge_name: String in EXPECTED_ARTICULATIONS:
		var binding := str(ARTICULATION_TO_BINDING[hinge_name])
		if not first.hinges.has(binding) or not second.hinges.has(binding):
			return false
		if first.hinges[binding].node == second.hinges[binding].node:
			return false
	var first_mesh: Node = first.root.find_child("aileron_left", true, false)
	var second_mesh: Node = second.root.find_child("aileron_left", true, false)
	return first_mesh != null and second_mesh != null and first_mesh != second_mesh


func _check_bounds_against_geometry(actual: AABB, data: Dictionary) -> void:
	var bounds: Dictionary = data.get("bounds", {})
	var minimum := _vector3(bounds.get("min", []))
	var maximum := _vector3(bounds.get("max", []))
	_check("generated bounds metadata is finite and ordered", minimum.is_finite() and maximum.is_finite()
		and maximum.x > minimum.x and maximum.y > minimum.y and maximum.z > minimum.z)
	var actual_maximum := actual.position + actual.size
	_check("actual imported mesh bounds match generated Blender bounds",
		actual.position.distance_to(minimum) <= GEOMETRY_TOLERANCE_M
		and actual_maximum.distance_to(maximum) <= GEOMETRY_TOLERANCE_M,
		"actual=%s..%s expected=%s..%s" % [str(actual.position), str(actual_maximum), str(minimum), str(maximum)])
	var nominal: Dictionary = data.get("nominal", {})
	_check("model span agrees with nominal 2.00 m", absf(actual.size.x - float(nominal.get("span_m", NAN))) <= NOMINAL_SPAN_TOLERANCE_M,
		"span=%.5f m" % actual.size.x)
	_check("model length agrees with nominal 2.22 m", absf(actual.size.z - float(nominal.get("length_m", NAN))) <= NOMINAL_LENGTH_TOLERANCE_M,
		"length=%.5f m" % actual.size.z)
	_check("nose is -Z and model is laterally symmetric", actual.position.z < -0.8 and actual_maximum.z > 1.0
		and absf(actual.position.x + actual_maximum.x) <= GEOMETRY_TOLERANCE_M)


func _check_turbine_geometry(root: Node3D, data: Dictionary) -> void:
	var turbine: Dictionary = data.get("turbine", {})
	var outlet := _vector3(turbine.get("outlet_position", []))
	var direction := _vector3(turbine.get("outlet_direction", []))
	var outlet_name := str(turbine.get("outlet_node", ""))
	var engine_name := str(turbine.get("engine_node", ""))
	_check("geometry names the JetCat P100-RX", turbine.get("model", "") == "JetCat P100-RX")
	_check("turbine metadata has finite +Z exhaust geometry", outlet.is_finite() and direction.is_finite()
		and direction.distance_to(Vector3(0.0, 0.0, 1.0)) <= 0.00001
		and outlet_name == "exhaust_pipe" and engine_name == "turbine")
	var outlet_mesh := root.find_child(outlet_name, true, false) as MeshInstance3D
	var engine_mesh := root.find_child(engine_name, true, false) as MeshInstance3D
	_check("actual turbine and exhaust meshes exist", outlet_mesh != null and engine_mesh != null
		and outlet_mesh.mesh != null and engine_mesh.mesh != null)
	if outlet_mesh == null or engine_mesh == null or outlet_mesh.mesh == null or engine_mesh.mesh == null:
		return
	var outlet_bounds := _mesh_bounds(root, outlet_mesh)
	var engine_bounds := _mesh_bounds(root, engine_mesh)
	_check("outlet is on the actual exhaust geometry", outlet_bounds.valid and _contains_padded(outlet_bounds.box, outlet, 0.005)
		and absf((outlet_bounds.box.position.z + outlet_bounds.box.size.z) - outlet.z) <= 0.01,
		"outlet=%s exhaust=%s..%s" % [str(outlet), str(outlet_bounds.box.position), str(outlet_bounds.box.position + outlet_bounds.box.size)])
	_check("visible turbine mesh has finite nontrivial extent", engine_bounds.valid
		and engine_bounds.box.size.x > 0.05 and engine_bounds.box.size.z > 0.1)
	var nominal: Dictionary = data.get("nominal", {})
	_check("turbine mesh diameter agrees with nominal installation", engine_bounds.valid
		and absf(engine_bounds.box.size.x - float(nominal.get("engine_diameter_m", NAN))) <= 0.01)
	_check("turbine mesh length agrees with nominal installation", engine_bounds.valid
		and absf(engine_bounds.box.size.z - float(nominal.get("engine_length_m", NAN))) <= 0.02)


func _mesh_bounds(root: Node3D, subtree: Node) -> Dictionary:
	var box := AABB()
	var first := true
	var finite := true
	var mesh_count := 0
	for mesh in _meshes_under(subtree):
		if mesh.mesh == null or not mesh.is_visible_in_tree():
			continue
		mesh_count += 1
		var root_from_mesh := Imported.relative(root, mesh)
		for vertex: Vector3 in mesh.mesh.get_faces():
			var point := root_from_mesh * vertex
			finite = finite and point.is_finite()
			if first:
				box = AABB(point, Vector3.ZERO)
				first = false
			else:
				box = box.expand(point)
	return {"valid": finite and not first, "box": box, "mesh_count": mesh_count}


func _contains_padded(box: AABB, point: Vector3, tolerance: float) -> bool:
	var end := box.position + box.size
	return (point.x >= box.position.x - tolerance and point.x <= end.x + tolerance
		and point.y >= box.position.y - tolerance and point.y <= end.y + tolerance
		and point.z >= box.position.z - tolerance and point.z <= end.z + tolerance)


func _expected_witness_position(model: Dictionary, witness: Dictionary, binding: String, angle_deg: float) -> Vector3:
	var entry: Dictionary = model.hinges[binding]
	var node := entry.node as Node3D
	var parent := node.get_parent() as Node3D
	var parent_to_root := Imported.relative(model.root, parent)
	var hinge_pose := Transform3D(Basis(entry.axis, deg_to_rad(angle_deg)) * entry.rest, entry.pivot)
	var mesh_to_hinge := Imported.relative(node, witness.mesh)
	return parent_to_root * hinge_pose * mesh_to_hinge * witness.vertex


func _hinge_angle(entry: Dictionary) -> float:
	var node := entry.node as Node3D
	var relative: Basis = node.basis * entry.rest.inverse()
	var witness := Vector3.FORWARD.cross(entry.axis).normalized()
	if witness.length_squared() < 0.5:
		return NAN
	return witness.signed_angle_to(relative * witness, entry.axis)


func _semantic_axis(positive: String) -> Vector3:
	if positive.ends_with("up"):
		return Vector3.UP
	if positive.ends_with("down"):
		return Vector3.DOWN
	if positive.ends_with("right"):
		return Vector3.RIGHT
	return Vector3.ZERO


func _basis(value: Variant) -> Basis:
	# The sidecar records the three basis columns as an array; a normalized
	# runtime DATA generator may expose the same columns under x/y/z keys.
	if typeof(value) == TYPE_ARRAY and value.size() == 3:
		return Basis(_vector3(value[0]), _vector3(value[1]), _vector3(value[2]))
	if typeof(value) == TYPE_DICTIONARY and value.has_all(["x", "y", "z"]):
		return Basis(_vector3(value.x), _vector3(value.y), _vector3(value.z))
	return Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)


func _vector3(value: Variant) -> Vector3:
	if typeof(value) != TYPE_ARRAY or value.size() != 3:
		return Vector3(NAN, NAN, NAN)
	return Vector3(float(value[0]), float(value[1]), float(value[2]))


func _finite_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))
