# AS-09/10: declarative Blender scene construction. Rendering transforms only.
extends RefCounted

const Manifest := preload("res://aircraft/model_manifest.gd")
const Construction := preload("res://aircraft/imported_model_contract.gd")
const Retraction := preload("res://aircraft/retractable_model.gd")
const REST_TOLERANCE := 0.00002 # Source measurements rounded to six decimal places.


static func build(manifest: Dictionary, livery_id := "") -> Dictionary:
	var result := build_checked(manifest, livery_id)
	if not result.ok:
		push_warning("Imported aircraft: " + str(result.errors))
	return result.model


static func build_checked(manifest: Dictionary, livery_id := "") -> Dictionary:
	var checked := Manifest.validate(manifest)
	if not checked.ok: return _failure(checked.errors)
	if manifest.get("version") != 2 or manifest.builder.script != "res://aircraft/imported_model.gd":
		return _failure(["The common importer requires a version 2 imported model manifest."])
	# F4U-16: a livery is another GLB of the same airframe; the registry verifies its bytes before this boundary,
	# and build_scene checks it against the same generated geometry.
	var livery := _livery(manifest, livery_id)
	if livery.is_empty(): return _failure(["Unknown livery: " + livery_id])
	var geometry: Script = load(str(manifest.geometry.script))
	var scene: PackedScene = load(str(livery.path)) as PackedScene
	if geometry == null or scene == null: return _failure(["Missing imported scene or generated geometry."])
	var data: Variant = geometry.get("DATA")
	if not data is Dictionary: return _failure(["Generated geometry must expose DATA."])
	var instance := scene.instantiate()
	if not instance is Node3D:
		instance.free()
		return _failure(["Imported scene root must be Node3D."])
	return build_scene(instance, data, manifest, livery)


## The manifest's livery record by id ({} if unknown); an empty id selects the default asset.
static func _livery(manifest: Dictionary, livery_id: String) -> Dictionary:
	var options: Array = manifest.get("liveries", [])
	if options.is_empty():
		return {id = "", path = str(manifest.asset.path), sha256 = str(manifest.asset.sha256)} if livery_id.is_empty() else {}
	for record: Dictionary in options:
		if record.id == (livery_id if not livery_id.is_empty() else str(options[0].id)): return record
	return {}


## Takes ownership of the unmodified instance, freeing it on any validation failure.
## The registry verifies provenance before this boundary; fixtures may pass an in-memory scene.
static func build_scene(root: Node3D, data: Dictionary, manifest: Dictionary, livery: Dictionary = {}) -> Dictionary:
	var checked := Manifest.validate(manifest)
	if not checked.ok:
		root.free()
		return _failure(checked.errors)
	if manifest.get("version") != 2 or manifest.builder.script != "res://aircraft/imported_model.gd":
		root.free()
		return _failure(["The common importer requires a version 2 imported model manifest."])
	var references := Construction.validate_geometry(data, manifest.construction, manifest.bindings)
	if not references.ok:
		root.free()
		return _failure(references.errors)
	var errors := PackedStringArray()
	var nodes := {}
	for node in [root] + root.find_children("*", "", true, false):
		var key := str(node.name)
		if not nodes.has(key): nodes[key] = []
		nodes[key].append(node)
		if node is Node3D and not node.transform.is_finite(): errors.append("Non-finite scene transform: " + key)
	var config: Dictionary = manifest.construction
	var bindings: Dictionary = manifest.bindings
	var hinges := {}
	for role: String in bindings.controls:
		for binding: Dictionary in bindings.controls[role].hinges:
			var node := _unique(nodes, binding.node, errors)
			var record := _record(data, binding.geometry_ref, errors)
			_check_rest(root, node, record, errors)
			if node == null: continue
			var travel: Variant = record.get("range_deg")
			var sign: Variant = record.get("app_sign")
			if not travel is Array or travel.size() != 2 or not _number(travel[0]) or not _number(travel[1]):
				errors.append("Control range must contain two finite bounds: " + binding.node)
				continue
			if float(travel[0]) >= float(travel[1]) or not _number(sign) or absf(float(sign)) != 1.0 or not record.get("positive") is String or str(record.get("positive", "")).strip_edges().is_empty():
				errors.append("Invalid control range or signed direction: " + binding.node)
				continue
			hinges[binding.key] = {node = node, axis = node.basis.x.normalized(), rest = node.basis,
				pivot = node.position, range_deg = travel.duplicate(), positive = record.positive, app_sign = float(sign)}
	var rotor: Node3D = null
	var frame: Node3D = null
	if bindings.rotor.present:
		frame = _unique(nodes, config.rotor.frame_node, errors)
		rotor = _unique(nodes, bindings.rotor.spin_node, errors)
		var frame_record := _record(data, config.rotor.geometry_ref, errors)
		_check_rest(root, frame, frame_record, errors)
		_check_rest(root, rotor, _record(data, bindings.rotor.geometry_ref, errors), errors)
		if frame_record.get("spin_node") != bindings.rotor.spin_node: errors.append("Rotor frame does not reference the declared spin node.")
		if rotor != null and rotor.get_parent() != frame: errors.append("Rotor spin node must be a direct child of its frame.")
	var gear_pivots := {}
	for binding: Dictionary in config.gear:
		var pivot := _unique(nodes, binding.node, errors)
		_check_rest(root, pivot, _record(data, binding.geometry_ref, errors), errors)
		gear_pivots[binding.role] = pivot
		for name in [binding.wrapper, binding.wrapper + "_mount"]:
			if nodes.has(name): errors.append("Generated gear wrapper already exists: " + name)
	for name in ["propeller", "propeller_mount"]:
		if nodes.has(name): errors.append("Generated rotor wrapper already exists: " + name)
	_validate_materials(config.material_grow, nodes, errors)
	var retract := {}
	if config.has("retraction"):
		retract = Retraction.bind(_record(data, config.retraction.geometry_ref, errors), nodes)
		errors.append_array(retract.errors)
		for role: String in retract.get("gear", {}):
			if not bindings.gear.keys.has(role): errors.append("Gear rig wheel has no manifest binding: " + role)
	var folds := {}
	for binding: Dictionary in config.get("folds", []):
		var fold := _bind_fold(root, nodes, _record(data, binding.geometry_ref, errors), hinges, errors)
		if not fold.is_empty(): folds[binding.key] = fold
	if not errors.is_empty():
		root.free()
		return _failure(errors)

	root.name = "airplane"
	# Wreck duplication must copy the constructed hierarchy, not re-instantiate the original GLB.
	root.scene_file_path = ""
	root.set_meta("status", data.get("status", ""))
	root.set_meta("visual_revision", manifest.asset.revision)
	root.set_meta("asset_sha256", livery.get("sha256", manifest.asset.sha256))
	root.set_meta("livery", str(livery.get("id", "")))
	root.set_meta("aircraft_id", manifest.family_id)
	_apply_materials(config.material_grow, nodes)
	var propeller := Node3D.new()
	propeller.name = "propeller"
	if bindings.rotor.present:
		var rest := rotor.transform
		var mount := Node3D.new()
		mount.name = "propeller_mount"
		mount.basis = _rotor_basis(config.rotor.axis)
		mount.position = rest.origin
		_reparent(rotor, frame, mount, propeller)
		rotor.transform = mount.transform.affine_inverse() * rest
	else:
		root.add_child(propeller)
	var gear := {}
	# Ancestors first: a steerable axle spins about the steered axis after construction.
	var ordered: Array = config.gear.duplicate()
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _depth(gear_pivots[a.role]) < _depth(gear_pivots[b.role]))
	for binding: Dictionary in ordered:
		gear[bindings.gear.keys[binding.role]] = _wrap(root, gear_pivots[binding.role], binding.wrapper)
	if not retract.is_empty():
		for role: String in retract.gear:
			gear[bindings.gear.keys[role]] = retract.gear[role]
	return {ok = true, errors = PackedStringArray(), model = {
		root = root, propeller = propeller, hinges = hinges, gear = gear,
		gear_retraction = retract.get("rig", {}), folds = folds, livery = str(livery.get("id", "")),
		has_propeller = bindings.rotor.present, data = data, aircraft_id = manifest.family_id,
		model_manifest = manifest.duplicate(true)}}


static func _failure(errors: Variant) -> Dictionary:
	return {ok = false, errors = PackedStringArray(errors), model = {}}


static func _number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))


static func _record(data: Dictionary, ref: String, errors: PackedStringArray) -> Dictionary:
	var value: Variant = data
	for key in ref.split("."):
		if not value is Dictionary or not value.has(key):
			errors.append("Unresolved geometry reference: " + ref)
			return {}
		value = value[key]
	if not value is Dictionary:
		errors.append("Geometry reference must identify a record: " + ref)
		return {}
	return value


static func _unique(nodes: Dictionary, key: String, errors: PackedStringArray) -> Node3D:
	var found: Array = nodes.get(key, [])
	if found.size() != 1 or not found[0] is Node3D:
		errors.append("Binding requires exactly one Node3D: " + key)
		return null
	return found[0]


static func _vector(value: Variant) -> bool:
	return value is Array and value.size() == 3 and _number(value[0]) and _number(value[1]) and _number(value[2])


static func _v3(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))


static func _check_rest(root: Node3D, node: Node3D, record: Dictionary, errors: PackedStringArray) -> void:
	if node == null: return
	if node == root or not node.get_parent() is Node3D:
		errors.append("Articulated node requires a Node3D parent: " + str(node.name))
		return
	if record.get("node") != str(node.name) or record.get("parent") != str(node.get_parent().name):
		errors.append("Geometry node/parent does not match scene: " + str(node.name))
	var ancestor: Node = node
	while ancestor != null:
		if not ancestor is Node3D:
			errors.append("Articulation ancestors must be Node3D: " + str(node.name))
			break
		var basis: Basis = ancestor.basis
		if not basis.is_finite() or absf(basis.determinant() - 1.0) > 0.00001 or not (basis.transposed() * basis).is_equal_approx(Basis.IDENTITY):
			errors.append("Articulation transforms must be rigid, without scale/shear/reflection: " + str(ancestor.name))
			break
		if ancestor == root: break
		ancestor = ancestor.get_parent()
	var position: Variant = record.get("rest_translation")
	var rest: Variant = record.get("rest_basis")
	if not _vector(position) or not rest is Dictionary or not _vector(rest.get("x")) or not _vector(rest.get("y")) or not _vector(rest.get("z")):
		errors.append("Geometry record requires a finite local rest transform: " + str(node.name))
		return
	if node.position.distance_to(_v3(position)) > REST_TOLERANCE or node.basis.x.distance_to(_v3(rest.x)) > REST_TOLERANCE or node.basis.y.distance_to(_v3(rest.y)) > REST_TOLERANCE or node.basis.z.distance_to(_v3(rest.z)) > REST_TOLERANCE:
		errors.append("Imported rest transform disagrees with geometry: " + str(node.name))


static func _validate_materials(bindings: Array, nodes: Dictionary, errors: PackedStringArray) -> void:
	for binding: Dictionary in bindings:
		var mesh := _unique(nodes, binding.node, errors) as MeshInstance3D
		if mesh == null or mesh.mesh == null:
			errors.append("Material binding requires a mesh: " + binding.node)
			continue
		var found := {}
		for index in mesh.mesh.get_surface_count():
			var material := mesh.get_active_material(index) as StandardMaterial3D
			if material != null and binding.materials.has(str(material.resource_name)):
				found[str(material.resource_name)] = true
		for name in binding.materials:
			if not found.has(name): errors.append("Missing standard material on " + binding.node + ": " + name)


static func _apply_materials(bindings: Array, nodes: Dictionary) -> void:
	for binding: Dictionary in bindings:
		var mesh: MeshInstance3D = nodes[binding.node][0]
		for index in mesh.mesh.get_surface_count():
			var source := mesh.get_active_material(index) as StandardMaterial3D
			if source == null or not binding.materials.has(str(source.resource_name)): continue
			var material := source.duplicate() as StandardMaterial3D
			material.resource_name = source.resource_name
			material.grow = true
			material.grow_amount = float(binding.amount_m)
			mesh.set_surface_override_material(index, material)


static func _rotor_basis(axis: String) -> Basis:
	var basis := Basis.IDENTITY
	match axis.right(1):
		"X": basis = Basis(Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(1, 0, 0))
		"Y": basis = Basis(Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0))
	if axis.begins_with("-"):
		basis.x = -basis.x
		basis.z = -basis.z
	return basis


static func _depth(node: Node) -> int:
	var depth := 0
	while node != null:
		depth += 1
		node = node.get_parent()
	return depth


static func relative(root: Node3D, node: Node3D) -> Transform3D:
	var transform := Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != root:
		if current is Node3D: transform = current.transform * transform
		current = current.get_parent()
	return transform


static func _wrap(root: Node3D, pivot: Node3D, label: String) -> Node3D:
	var parent := pivot.get_parent() as Node3D
	var parent_basis := relative(root, parent).basis
	var rest := pivot.transform
	var mount := Node3D.new()
	mount.name = label + "_mount"
	mount.basis = parent_basis.inverse()
	var exposed := Node3D.new()
	exposed.name = label
	exposed.position = parent_basis * rest.origin
	_reparent(pivot, parent, mount, exposed)
	pivot.transform = Transform3D(parent_basis * rest.basis, Vector3.ZERO)
	return exposed


static func _reparent(pivot: Node3D, parent: Node3D, mount: Node3D, exposed: Node3D) -> void:
	for node in [pivot] + pivot.find_children("*", "", true, false): node.owner = null
	parent.remove_child(pivot)
	parent.add_child(mount)
	mount.add_child(exposed)
	exposed.add_child(pivot)


static func _set_hinge(hinge: Dictionary, degrees: float) -> void:
	var basis: Basis = hinge.rest if degrees == 0.0 else Basis(hinge.axis, deg_to_rad(degrees)) * hinge.rest
	var fold: Dictionary = hinge.get("fold", {})
	if fold.is_empty():
		hinge.node.basis = basis
		return
	# A hinge on a folding panel turns in the panel's frame: the fold carries its pivot too.
	hinge.unfolded_basis = basis
	hinge.node.transform = fold.transform * Transform3D(basis, hinge.pivot)


## F4U-17: a fold group turns rigid members at the model frame (a panel and the hinges it carries) about one fixed axis,
## in place, so node paths, paint targets and crash sections are unchanged. Presentation only.
static func _bind_fold(root: Node3D, nodes: Dictionary, record: Dictionary, hinges: Dictionary, errors: PackedStringArray) -> Dictionary:
	var members: Variant = record.get("members")
	var limit: Variant = record.get("max_angle_deg")
	var sign: Variant = record.get("sign")
	if not members is Array or members.is_empty() or not _vector(record.get("pivot")) or not _vector(record.get("axis")) \
			or not _number(limit) or float(limit) <= 0.0 or float(limit) > 180.0 or not _number(sign) or absf(float(sign)) != 1.0:
		errors.append("Fold record needs members, a pivot, an axis, a sign and a 0-180 degree limit.")
		return {}
	var axis := _v3(record.axis)
	if absf(axis.length() - 1.0) > 1e-6:
		errors.append("Fold axis must be a unit vector.")
		return {}
	var release: Variant = record.get("lock_release_fraction", 0.0)
	var travel: Variant = record.get("travel_fraction", 1.0)
	if not _number(release) or not _number(travel) or float(release) < 0.0 or float(travel) <= 0.0 or float(release) + float(travel) > 1.0:
		errors.append("Fold lock release and travel must divide the mechanism's 0-1 range.")
		return {}
	var time: Variant = record.get("time_s", 0.0)
	if not _number(time) or float(time) < 0.0:
		errors.append("Fold cycle time must be a finite, non-negative number of seconds.")
		return {}
	var fold := {pivot = _v3(record.pivot), axis = axis, sign = float(sign), max_deg = float(limit),
		release = float(release), travel = float(travel), time_s = float(time), degrees = 0.0, transform = Transform3D.IDENTITY, members = []}
	for name: Variant in members:
		var node := _unique(nodes, str(name), errors)
		if node == null: continue
		# The fold transform is in the model frame: each member's parent must sit at it (the GLB's own root).
		var parent := node.get_parent() as Node3D
		if parent == null or not relative(root, parent).is_equal_approx(Transform3D.IDENTITY):
			errors.append("Fold member's parent must be at the model frame: " + str(name))
			continue
		var hinge := {}
		for key: String in hinges:
			if hinges[key].node == node:
				hinge = hinges[key]
				hinge.fold = fold
		fold.members.append({node = node, rest = node.transform, hinge = hinge})
	return fold


## Fold angle of a mechanism state q (0 spread and locked, 1 folded): the locks release over the first part of the
## travel, then the panel turns linearly to its limit (R59's law).
static func fold_degrees(fold: Dictionary, q: float) -> float:
	return fold.max_deg * clampf((q - fold.release) / fold.travel, 0.0, 1.0)


## Fold pose per fold key from its mechanism state q in 0-1; unchanged folds are not rewritten.
static func apply_folds(model: Dictionary, fractions: Dictionary) -> void:
	for key: String in model.get("folds", {}):
		var fold: Dictionary = model.folds[key]
		var q := float(fractions.get(key, 0.0))
		if not is_finite(q): continue
		var degrees := fold_degrees(fold, q)
		if degrees == fold.degrees: continue
		fold.degrees = degrees
		fold.transform = Transform3D(Basis(), fold.pivot) * Transform3D(Basis(fold.axis, deg_to_rad(fold.sign * degrees)), Vector3.ZERO) \
			* Transform3D(Basis(), -fold.pivot)
		for member: Dictionary in fold.members:
			var hinge: Dictionary = member.hinge
			member.node.transform = fold.transform * (Transform3D(hinge.get("unfolded_basis", hinge.rest), hinge.pivot) if not hinge.is_empty() else member.rest)


static func apply_surfaces(model: Dictionary, surfaces_deg: Dictionary) -> void:
	for role: String in model.model_manifest.bindings.controls:
		var control: Dictionary = model.model_manifest.bindings.controls[role]
		if control.visual_only: continue
		for binding: Dictionary in control.hinges:
			var hinge: Dictionary = model.hinges[binding.key]
			_set_hinge(hinge, float(surfaces_deg.get(role, 0.0)) * hinge.app_sign)


## Inspector-only poses. Declaring a visual flap does not enable aerodynamic flaps.
static func set_visual_surfaces(model: Dictionary, surfaces_deg: Dictionary) -> void:
	for role: String in model.model_manifest.bindings.controls:
		var control: Dictionary = model.model_manifest.bindings.controls[role]
		if not control.visual_only: continue
		for binding: Dictionary in control.hinges:
			var hinge: Dictionary = model.hinges[binding.key]
			_set_hinge(hinge, clampf(float(surfaces_deg.get(role, 0.0)), hinge.range_deg[0], hinge.range_deg[1]) * hinge.app_sign)


## Session-driven flap pose. Only manifest-declared physical flap hinges move here.
static func set_flaps(model: Dictionary, degrees: float) -> void:
	if not is_finite(degrees): return
	for role in ["flap_left", "flap_right"]:
		var control: Dictionary = model.model_manifest.bindings.controls.get(role, {})
		if control.is_empty() or control.get("visual_only", true): continue
		for binding: Dictionary in control.hinges:
			var hinge: Dictionary = model.hinges.get(binding.key, {})
			if hinge.is_empty(): continue
			_set_hinge(hinge, clampf(degrees, hinge.range_deg[0], hinge.range_deg[1]) * hinge.app_sign)
