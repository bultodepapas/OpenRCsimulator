## Analytic course tessellation. Vertices and normals come from the physics sampler.
extends RefCounted
const Course = preload("res://physics/ground_vehicle/course.gd")

static func build(parent: Node3D, course: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "PracticeCourse"
	parent.add_child(root)
	var norths := _coordinates(course.north_min_m, course.north_max_m, 0.20)
	var easts := _coordinates(course.east_min_m, course.east_max_m, 0.20)
	for region in course.regions:
		norths.append(region.north_min_m)
		norths.append(region.north_max_m)
		easts.append(region.east_min_m)
		easts.append(region.east_max_m)
	for feature in course.features:
		# Dense local sampling resolves the small RC bump lane and curved ramp transitions.
		for n in _coordinates(feature.center_north_m - 5.0, feature.center_north_m + 5.0, 0.05):
			if n > course.north_min_m and n < course.north_max_m:
				norths.append(n)
		var half_width: float = feature.width_m * 0.5
		for e in [feature.center_east_m - half_width - feature.shoulder_width_m, feature.center_east_m - half_width, feature.center_east_m + half_width, feature.center_east_m + half_width + feature.shoulder_width_m]:
			easts.append(e)
	norths = _unique(norths)
	easts = _unique(easts)
	var material_by_id := {}
	for id in course.surface_by_id:
		var data: Dictionary = course.surface_by_id[id]
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(data.color_srgb[0], data.color_srgb[1], data.color_srgb[2])
		material.roughness = data.roughness
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material_by_id[id] = material
	var builders := {}
	for id in material_by_id:
		var builder := SurfaceTool.new()
		builder.begin(Mesh.PRIMITIVE_TRIANGLES)
		builder.set_material(material_by_id[id])
		builders[id] = builder
	var rows := []
	for n in norths:
		var row := []
		for e in easts:
			row.append(Course.sample(course, n, e))
		rows.append(row)
	for ni in norths.size() - 1:
		for ei in easts.size() - 1:
			var middle := Course.sample(course, (norths[ni] + norths[ni + 1]) * 0.5, (easts[ei] + easts[ei + 1]) * 0.5)
			var builder: SurfaceTool = builders[middle.surface_id]
			for corner in [[0, 0], [0, 1], [1, 1], [0, 0], [1, 1], [1, 0]]:
				var nidx: int = ni + corner[0]
				var eidx: int = ei + corner[1]
				var sample: Dictionary = rows[nidx][eidx]
				var normal: PackedFloat64Array = sample.normal_ned
				builder.set_normal(Vector3(normal[1], -normal[2], -normal[0]))
				builder.add_vertex(Vector3(easts[eidx], sample.height_m, -norths[nidx]))
	for id in builders:
		var instance := MeshInstance3D.new()
		instance.name = str(id)
		instance.mesh = builders[id].commit()
		root.add_child(instance)
	for region in course.regions:
		_sign(root, course, str(course.surface_by_id[region.surface_id].name).to_upper(), region.north_min_m - 0.3, (region.east_min_m + region.east_max_m) * 0.5)
	for feature in course.features:
		_sign(root, course, str(feature.id).to_upper(), feature.center_north_m, feature.center_east_m + feature.width_m * 0.5 + feature.shoulder_width_m + 0.5)
	_sign(root, course, "OPENRC / MT8", -1.0, 0.0)
	# These paint strips are decoration, placed 2 mm above the same sampled surface.
	for n in range(-1, 24):
		for e in [-1.8, 1.8]:
			var mark := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(0.035, 0.003, 0.35)
			mark.mesh = box
			var paint := StandardMaterial3D.new()
			paint.albedo_color = Color("ead9b0")
			mark.material_override = paint
			mark.position = Vector3(e, Course.sample(course, n, e).height_m + 0.002, -n)
			root.add_child(mark)
	return root

static func _coordinates(low: float, high: float, spacing: float) -> Array[float]:
	var values: Array[float] = []
	for i in ceili((high - low) / spacing) + 1:
		values.append(minf(high, low + i * spacing))
	return values

static func _unique(values: Array[float]) -> Array[float]:
	values.sort()
	var result: Array[float] = []
	for value in values:
		if result.is_empty() or value - result[-1] > 0.0001:
			result.append(value)
	return result

static func _sign(parent: Node3D, course: Dictionary, text: String, north: float, east: float) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 48
	label.pixel_size = 0.002
	label.modulate = Color("f0d197")
	label.outline_size = 8
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3(east, Course.sample(course, north, east).height_m + 0.32, -north)
	parent.add_child(label)
