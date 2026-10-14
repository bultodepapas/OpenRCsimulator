extends SceneTree
## AS-09/14: catalog-discovered physical/model/package conformance. No golden files are written.
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const AircraftData := preload("res://physics/aircraft_data.gd")
const Modules := preload("res://physics/aircraft_modules.gd")
const Contacts := preload("res://physics/aircraft_contact_contract.gd")
const Builder := preload("res://render/airplane.gd")
const Commands := preload("res://input/commands.gd")
const Descriptor := preload("res://workshop/descriptor.gd")


func inspect(entry: Dictionary) -> Dictionary:
	var errors := PackedStringArray()
	var report: Dictionary = {id = entry.id, visual_family = Catalog.visual_family(entry.id),
		catalog_status = entry.status, status_note = entry.get("status_note", ""),
		physical_validation = "not established by software conformance"}
	var bytes := FileAccess.get_file_as_bytes(entry.data)
	var raw: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	if not raw is Dictionary:
		return {id = entry.id, ok = false, errors = ["Aircraft JSON is unavailable."]}
	var classification := Modules.classify(raw)
	if not classification.ok:
		errors.append_array(classification.errors)
	var loaded := AircraftData.load_file(entry.data)
	if not loaded.ok:
		errors.append_array(loaded.errors)
	var descriptor := Descriptor.load_for(entry.id, bytes)
	if not descriptor.ok:
		errors.append_array(descriptor.errors)
	else:
		var presentation := Descriptor.verify_presentation(descriptor.descriptor)
		if not presentation.ok:
			errors.append_array(presentation.errors)
	if not errors.is_empty():
		report.ok = false
		report.errors = errors
		return report
	report.modules = classification.modules
	report.laws = classification.laws
	report.compiler_transforms = classification.compiler_transforms
	var model: Dictionary = loaded.model
	var contact := Contacts.describe(model, true)
	if not contact.ok:
		errors.append_array(contact.errors)
	else:
		report.contacts = {supports = contact.support_points.size(), hull_probes = contact.hull_probes.size(),
			wheel_profile = contact.wheel_profile.status, policy = contact.policy,
			visual_sections = "unbound physical hull labels; visual section provider declared separately"}
	var airplane := Builder.build(entry.id)
	if airplane.is_empty():
		errors.append("Model failed shared builder conformance.")
	else:
		var manifest: Dictionary = airplane.model_manifest
		report.model_adapter = manifest.builder.adapter
		report.asset = manifest.asset
		report.dependency_count = manifest.dependencies.size()
		_pose_checks(airplane, model.controls.throw_deg, errors)
		var independent := Builder.build(entry.id)
		if independent.is_empty():
			errors.append("Independent model instance failed to build.")
		else:
			if independent.root == airplane.root or independent.propeller == airplane.propeller:
				errors.append("Builder reused nodes across model instances.")
			for role: String in manifest.bindings.controls:
				for hinge: Dictionary in manifest.bindings.controls[role].hinges:
					if _node(independent.hinges[hinge.key]) == _node(airplane.hinges[hinge.key]):
						errors.append("Builder reused hinge " + role)
			independent.root.free()
		report.render_geometry = _mesh_counts(airplane.root)
		airplane.root.free()
	report.ok = errors.is_empty()
	report.errors = errors
	return report


func _node(value: Variant) -> Node3D:
	return value.node if value is Dictionary else value


func _pose_checks(airplane: Dictionary, throws: Dictionary, errors: PackedStringArray) -> void:
	var bindings: Dictionary = airplane.model_manifest.bindings.controls
	var rests: Dictionary = {}
	for role: String in bindings:
		for binding: Dictionary in bindings[role].hinges:
			rests[binding.key] = _node(airplane.hinges[binding.key]).basis
	for command_sign: float in [-1.0, 1.0, 0.0]:
		var command := {roll = command_sign, pitch = command_sign, yaw = command_sign, throttle = 0.0}
		var surfaces := Commands.surface_deflections_deg(command, throws)
		Builder.apply_surfaces(airplane, Commands.hinge_rotations(command, throws))
		for role: String in bindings:
			var binding: Dictionary = bindings[role]
			for declared: Dictionary in binding.hinges:
				var value: Variant = airplane.hinges[declared.key]
				var node := _node(value)
				if binding.visual_only:
					if node.basis != rests[declared.key]:
						errors.append("Visual-only surface moved under conventional flight commands: " + role)
					continue
				var expected: float = deg_to_rad(surfaces[role]) * (1.0 if role == "rudder" else -1.0)
				var actual: float
				if value is Dictionary:
					var relative: Basis = node.basis * value.rest.inverse()
					var witness: Vector3 = Vector3.FORWARD.cross(value.axis).normalized()
					actual = witness.signed_angle_to(relative * witness, value.axis)
				else:
					actual = node.rotation.y if role == "rudder" else node.rotation.x
				if not is_finite(actual) or absf(actual - expected) > 1.0e-6:
					errors.append("Surface sign/travel differs from physics: " + role + "/" + declared.key)
				if command_sign == 0.0 and not node.basis.is_equal_approx(rests[declared.key]):
					errors.append("Surface did not return to authored rest: " + declared.key)


func _mesh_counts(node: Node) -> Dictionary:
	var result := {meshes = 0, surfaces = 0, vertices = 0, triangles = 0}
	if node is MeshInstance3D and node.mesh != null:
		result.meshes += 1
		for surface in node.mesh.get_surface_count():
			result.surfaces += 1
			var arrays: Array = node.mesh.surface_get_arrays(surface)
			result.vertices += arrays[Mesh.ARRAY_VERTEX].size()
		result.triangles += node.mesh.get_faces().size() / 3
	for child: Node in node.get_children():
		var nested := _mesh_counts(child)
		for key: String in result:
			result[key] += nested[key]
	return result


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		printerr("usage: preflight.gd -- <report.json>")
		quit(2)
		return
	var rows: Array = []
	var ok := true
	for entry: Dictionary in Catalog.airplane_flyable_entries():
		var result := inspect(entry)
		rows.append(result)
		ok = ok and result.ok
		print("AS preflight ", entry.id, " ", "PASS" if result.ok else "FAIL", " ", result.errors)
	var file := FileAccess.open(args[0], FileAccess.WRITE)
	if file == null:
		printerr("Cannot write preflight report: ", FileAccess.get_open_error())
		quit(2)
		return
	file.store_string(JSON.stringify({format = "openrc-aircraft-preflight v1", ok = ok,
		godot = Engine.get_version_info().string, aircraft = rows}, "\t") + "\n")
	file.close()
	quit(0 if ok else 1)
