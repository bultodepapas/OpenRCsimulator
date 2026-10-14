## AV-09: rendering-only sampled gear rig. Simulation owns deployment and loads.
extends RefCounted


static func _number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))


static func _vector(value: Variant, count: int) -> bool:
	if not value is Array or value.size() != count: return false
	for item in value:
		if not _number(item): return false
	return true


static func _v3(value: Array) -> Vector3:
	return Vector3(value[0], value[1], value[2])


static func _rotation(value: Array) -> Quaternion:
	return Quaternion(value[1], value[2], value[3], value[0])


static func validate(data: Variant) -> PackedStringArray:
	var errors := PackedStringArray()
	if not data is Dictionary or data.get("version") != 1 or not data.get("retraction") is Dictionary or not data.get("bindings") is Dictionary or not data.get("wheels") is Dictionary:
		return PackedStringArray(["Gear rig requires version 1, retraction, bindings and wheels."])
	var samples: Variant = data.retraction.get("samples")
	if not samples is Array or samples.size() < 2 or samples.size() > 513:
		return PackedStringArray(["Gear rig needs 2..513 uniform samples."])
	var names: Array = []
	for index in samples.size():
		var sample: Variant = samples[index]
		if not sample is Dictionary or not _number(sample.get("extension")) or absf(float(sample.extension) - float(index) / (samples.size() - 1)) > 1.0e-8 or not sample.get("nodes") is Dictionary or sample.nodes.is_empty():
			errors.append("Invalid uniform gear sample: %d" % index)
			continue
		if index == 0: names = sample.nodes.keys()
		if sample.nodes.size() != names.size(): errors.append("Gear samples must share their node set.")
		for name in names:
			var pose: Variant = sample.nodes.get(name)
			if not pose is Dictionary or not _vector(pose.get("translation"), 3) or not _vector(pose.get("rotation_wxyz"), 4):
				errors.append("Invalid gear pose: " + str(name))
			elif absf(_rotation(pose.rotation_wxyz).length_squared() - 1.0) > 0.00001:
				errors.append("Gear rotation must be normalized: " + str(name))
			if not data.bindings.has(name): errors.append("Missing gear carrier rest binding: " + str(name))
	if data.wheels.size() != 3 or not data.wheels.has_all(["left", "right", "nose"]): errors.append("Retractable rig needs left/right/nose wheels.")
	var used := {}
	for role in data.wheels:
		var wheel: Variant = data.wheels[role]
		if not wheel is Dictionary or not _number(wheel.get("radius_m")) or float(wheel.radius_m) <= 0.0 or float(wheel.radius_m) > 1.0:
			errors.append("Invalid gear wheel: " + str(role))
			continue
		for key in ["spin_node", "compression_node"] + (["steer_node"] if role == "nose" else []):
			var name: Variant = wheel.get(key)
			if not name is String or not data.bindings.has(name) or used.has(name) or names.has(name):
				errors.append("Invalid or reused wheel helper: " + str(name))
			used[name] = true
		for key in ["center_model", "contact_model"]:
			var path: Variant = wheel.get(key)
			if not path is Array or path.size() != samples.size():
				errors.append("Wheel path must match pose samples: " + str(role))
				continue
			for point in path:
				if not _vector(point, 3): errors.append("Invalid wheel path point: " + str(role))
	return errors


static func bind(data: Dictionary, nodes: Dictionary) -> Dictionary:
	var errors := validate(data)
	var bound := {}
	if not errors.is_empty(): return {ok = false, errors = errors}
	for name in data.bindings:
		var record: Variant = data.bindings[name]
		var found: Array = nodes.get(name, [])
		if found.size() != 1 or not found[0] is Node3D:
			errors.append("Gear binding needs a unique Node3D: " + str(name))
			continue
		var node: Node3D = found[0]
		if not record is Dictionary or record.get("node") != name or record.get("parent") != str(node.get_parent().name) or not _vector(record.get("rest_translation"), 3) or not record.get("rest_basis") is Dictionary:
			errors.append("Invalid gear rest binding: " + str(name))
			continue
		var axes: Dictionary = record.rest_basis
		if not _vector(axes.get("x"), 3) or not _vector(axes.get("y"), 3) or not _vector(axes.get("z"), 3):
			errors.append("Invalid gear rest basis: " + str(name))
			continue
		var rest := Basis(_v3(axes.x), _v3(axes.y), _v3(axes.z))
		if absf(rest.determinant() - 1.0) > 0.00001 or not (rest.transposed() * rest).is_equal_approx(Basis.IDENTITY) or node.position.distance_to(_v3(record.rest_translation)) > 0.00002 or node.basis.x.distance_to(rest.x) > 0.00002 or node.basis.y.distance_to(rest.y) > 0.00002 or node.basis.z.distance_to(rest.z) > 0.00002:
			errors.append("Gear rest transform disagrees with scene: " + str(name))
		bound[name] = node
	if not errors.is_empty(): return {ok = false, errors = errors}
	var gear := {}
	var compression := {}
	var rest := {}
	for role: String in data.wheels:
		var wheel: Dictionary = data.wheels[role]
		gear[role] = bound[wheel.spin_node]
		compression[role] = bound[wheel.compression_node]
		rest[role] = compression[role].transform
		if role == "nose": gear.steering = bound[wheel.steer_node]
	var rig := {data = data, nodes = bound, gear = gear, compression = compression, rest = rest}
	# The imported asset must be at the first (fully stowed) sample exactly.
	for name in data.retraction.samples[0].nodes:
		var sample: Dictionary = data.retraction.samples[0].nodes[name]
		var node: Node3D = bound[name]
		if node.position.distance_to(_v3(sample.translation)) > 0.00002 or node.quaternion.angle_to(_rotation(sample.rotation_wxyz)) > 0.0001:
			errors.append("Imported gear is not at its declared stowed pose: " + str(name))
	return {ok = errors.is_empty(), errors = errors, rig = rig, gear = gear}


static func apply(rig: Dictionary, extension: float) -> void:
	if rig.is_empty() or not is_finite(extension) or extension < 0.0 or extension > 1.0: return
	var samples: Array = rig.data.retraction.samples
	var at := extension * (samples.size() - 1)
	var left := mini(int(floor(at)), samples.size() - 2)
	var fraction := at - left
	for name in samples[left].nodes:
		var a: Dictionary = samples[left].nodes[name]
		var b: Dictionary = samples[left + 1].nodes[name]
		var node: Node3D = rig.nodes[name]
		node.position = _v3(a.translation).lerp(_v3(b.translation), fraction)
		node.quaternion = _rotation(a.rotation_wxyz).slerp(_rotation(b.rotation_wxyz), fraction).normalized()
