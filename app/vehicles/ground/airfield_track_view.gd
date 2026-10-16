## Render-only dirt-loop view. Contact heights and coverage come from the shared road sampler.
extends RefCounted

const GRAVEL_SHADER := preload("res://scenery/gravel.gdshader")
const PALETTE := preload("res://scenery/palette.gd")
const GRID_STEP_M := 0.10

static func build(course: Dictionary, road: Callable, ground_material: ShaderMaterial = null) -> Node3D:
	var root := Node3D.new()
	root.name = "RCObstacleTrack"
	var value: Variant = course.get("track", {})
	if typeof(value) != TYPE_DICTIONARY or value.is_empty() or not road.is_valid():
		return root
	var track: Dictionary = value
	var bounds := _bounds(track)
	var norths := _coordinates(bounds.north_min_m, bounds.north_max_m)
	var easts := _coordinates(bounds.east_min_m, bounds.east_max_m)
	var columns := easts.size()
	var count := norths.size() * columns
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var covered := PackedByteArray()
	vertices.resize(count)
	normals.resize(count)
	colors.resize(count)
	covered.resize(count)
	for ni in range(norths.size()):
		for ei in range(columns):
			var index := ni * columns + ei
			# Below the loop, only its narrow access lane needs road samples.
			if norths[ni] < float(track.center_north_m) - float(track.radius_m) - float(track.lane_width_m) * 0.5 - float(track.shoulder_m) and absf(easts[ei] - float(track.access.east_m)) > float(track.access.width_m) * 0.5 + float(track.shoulder_m):
				continue
			var sample := _sample(road, easts[ei], norths[ni])
			var coverage := _coverage(sample)
			if coverage <= 0.0001 or not _valid_height(sample):
				continue
			vertices[index] = Vector3(easts[ei], float(sample.height_m) + 0.002, -norths[ni])
			normals[index] = _normal(sample)
			colors[index] = _dirt_color(coverage)
			covered[index] = 1
	var indices := PackedInt32Array()
	for ni in range(norths.size() - 1):
		for ei in range(columns - 1):
			var a := ni * columns + ei
			var b := a + 1
			var c := a + columns
			var d := c + 1
			if covered[a] == 0 or covered[b] == 0 or covered[c] == 0 or covered[d] == 0:
				continue
			# E grows toward +X while N grows toward -Z; use an upward-facing winding.
			indices.append_array(PackedInt32Array([a, c, b, b, c, d]))
	if not indices.is_empty():
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_INDEX] = indices
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var material := ShaderMaterial.new()
		material.shader = GRAVEL_SHADER
		material.set_shader_parameter("detail_strength", 0.72)
		if ground_material != null:
			material = ground_material.duplicate() as ShaderMaterial
			material.set_shader_parameter("rc_track_surface", true)
			# The physical road already supplied geometric normals, including micro-relief.
			material.set_shader_parameter("terrain_relief_enabled", false)
		var surface := MeshInstance3D.new()
		surface.name = "DirtLoopSurface"
		surface.mesh = mesh
		surface.material_override = material
		surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(surface)
	_add_lane_edges(root, track, road)
	_add_start_line(root, track, road)
	_add_arrows(root, track, road)
	_add_flags(root, track, road)
	_add_walls(root, track)
	_add_signs(root, road)
	return root


static func _bounds(track: Dictionary) -> Dictionary:
	var cn := float(track.get("center_north_m", 45.0))
	var ce := float(track.get("center_east_m", 0.0))
	var radius := float(track.get("radius_m", 6.0))
	var half := float(track.get("half_straight_m", 12.0))
	var margin := float(track.get("lane_width_m", 3.2)) * 0.5 + float(track.get("shoulder_m", 1.2))
	var nmin := cn - radius - margin
	var nmax := cn + radius + margin
	var emin := ce - half - radius - margin
	var emax := ce + half + radius + margin
	var access: Variant = track.get("access", {})
	if typeof(access) == TYPE_DICTIONARY:
		nmin = minf(nmin, float(access.get("north_min_m", cn)) - margin)
		nmax = maxf(nmax, float(access.get("north_max_m", cn)) + margin)
		var ae := float(access.get("east_m", ce))
		var aw := float(access.get("width_m", 0.0)) * 0.5 + margin
		emin = minf(emin, ae - aw)
		emax = maxf(emax, ae + aw)
	var technical := float(track.get("technical_width_m", 3.8)) * 0.5 + float(track.get("shoulder_m", 1.2))
	nmin = minf(nmin, cn - technical)
	nmax = maxf(nmax, cn + technical)
	return {
		"north_min_m": maxf(20.0, nmin),
		"north_max_m": minf(55.0, nmax),
		"east_min_m": maxf(-22.0, emin),
		"east_max_m": minf(22.0, emax),
	}


static func _coordinates(low: float, high: float) -> Array[float]:
	var result: Array[float] = []
	var segments := maxi(1, ceili((high - low) / GRID_STEP_M))
	for i in range(segments + 1):
		result.append(lerpf(low, high, float(i) / float(segments)))
	return result


static func _sample(road: Callable, east: float, north: float) -> Dictionary:
	var value: Variant = road.call(north, east)
	return value if typeof(value) == TYPE_DICTIONARY else {}


static func _valid_height(sample: Dictionary) -> bool:
	var value: Variant = sample.get("height_m")
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))


static func _coverage(sample: Dictionary) -> float:
	var value: Variant = sample.get("track_coverage", sample.get("coverage", 0.0))
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
		return 0.0
	return clampf(float(value), 0.0, 1.0)


static func _normal(sample: Dictionary) -> Vector3:
	var ned: Variant = sample.get("normal_ned", PackedFloat64Array([0.0, 0.0, -1.0]))
	if not (ned is PackedFloat64Array or ned is PackedFloat32Array or ned is Array) or ned.size() < 3:
		return Vector3.UP
	var value := Vector3(float(ned[1]), -float(ned[2]), -float(ned[0]))
	return value.normalized() if value.length_squared() > 0.000001 else Vector3.UP


static func _dirt_color(coverage: float) -> Color:
	var blend := coverage * coverage * (3.0 - 2.0 * coverage)
	var color: Color = PALETTE.col("worn_grass").lerp(PALETTE.col("dirt"), blend)
	return Color(color.r, color.g, color.b, 1.0 - coverage)


static func _path(track: Dictionary) -> Array[Vector2]:
	var cn := float(track.center_north_m)
	var ce := float(track.center_east_m)
	var r := float(track.radius_m)
	var half := float(track.half_straight_m)
	var points: Array[Vector2] = []
	var straight_steps := maxi(2, ceili(2.0 * half / 0.10))
	var arc_steps := maxi(16, ceili(PI * r / 0.15))
	for i in range(straight_steps + 1):
		var t := float(i) / float(straight_steps)
		points.append(Vector2(ce - half + 2.0 * half * t, -(cn + r)))
	for i in range(1, arc_steps + 1):
		var angle := PI * float(i) / float(arc_steps)
		points.append(Vector2(ce + half + r * sin(angle), -(cn + r * cos(angle))))
	for i in range(1, straight_steps + 1):
		var t := float(i) / float(straight_steps)
		points.append(Vector2(ce + half - 2.0 * half * t, -(cn - r)))
	for i in range(1, arc_steps + 1):
		var angle := PI + PI * float(i) / float(arc_steps)
		points.append(Vector2(ce - half + r * sin(angle), -(cn + r * cos(angle))))
	return points


static func _add_lane_edges(root: Node3D, track: Dictionary, road: Callable) -> void:
	var path := _path(track)
	if path.size() < 4:
		return
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var half := float(track.lane_width_m) * 0.5
	var strip_width := 0.085
	for side in [-1.0, 1.0]:
		var base := vertices.size()
		for i in range(path.size()):
			var tangent := (path[mini(i + 1, path.size() - 1)] - path[maxi(i - 1, 0)]).normalized()
			if tangent.length_squared() < 0.000001:
				tangent = Vector2.RIGHT
			var lateral := Vector2(-tangent.y, tangent.x)
			var center := path[i] + lateral * float(side) * half
			for across in [-0.5, 0.5]:
				var point := center + lateral * float(across) * strip_width
				var sample := _sample(road, point.x, -point.y)
				vertices.append(Vector3(point.x, float(sample.get("height_m", 0.0)) + 0.012, point.y))
				normals.append(_normal(sample))
		for i in range(path.size() - 1):
			var index := base + i * 2
			indices.append_array(PackedInt32Array([index, index + 2, index + 1, index + 1, index + 2, index + 3]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var edge := MeshInstance3D.new()
	edge.name = "LaneEdgePaint"
	edge.mesh = mesh
	edge.material_override = _flat_material(Color("#ead9b0"))
	edge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(edge)


static func _add_start_line(root: Node3D, track: Dictionary, road: Callable) -> void:
	var width := float(track.lane_width_m)
	var n := float(track.center_north_m) - float(track.radius_m)
	var e := float(track.center_east_m) - float(track.half_straight_m) + 1.5
	for i in range(8):
		var mark_n := n - width * 0.5 + (float(i) + 0.5) * width / 8.0
		var sample := _sample(road, e, mark_n)
		var mark := MeshInstance3D.new()
		var paint := PlaneMesh.new()
		paint.size = Vector2(0.27, width / 8.0 * 0.97)
		mark.mesh = paint
		mark.material_override = _flat_material(Color("#f0eee8") if i % 2 == 0 else Color("#343434"))
		mark.position = Vector3(e, float(sample.get("height_m", 0.0)) + 0.004, -mark_n)
		mark.name = "StartGrid%02d" % i
		mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mark)


static func _add_arrows(root: Node3D, track: Dictionary, road: Callable) -> void:
	var ce := float(track.center_east_m)
	var cn := float(track.center_north_m)
	var r := float(track.radius_m)
	var access: Dictionary = track.get("access", {})
	var ae := float(access.get("east_m", ce))
	for north in [25.5, 31.5, 36.0]:
		_add_arrow(root, road, ae, float(north), Vector2(0.0, -1.0), "AccessArrow")
	_add_arrow(root, road, ce + 2.8, cn - r, Vector2(1.0, 0.0), "SouthLoopArrow")
	_add_arrow(root, road, ce + float(track.half_straight_m) - 3.0, cn + r, Vector2(-1.0, 0.0), "NorthLoopArrow")


static func _add_arrow(root: Node3D, road: Callable, east: float, north: float, direction: Vector2, node_name: String) -> void:
	var heading := direction.normalized()
	var side := Vector2(-heading.y, heading.x)
	var shape: Array[Vector2] = [
		heading * 0.55, heading * 0.045 + side * 0.24, heading * 0.045 + side * 0.075,
		-heading * 0.40 + side * 0.075, -heading * 0.40 - side * 0.075,
		heading * 0.045 - side * 0.075, heading * 0.045 - side * 0.24,
	]
	var center := Vector2(east, -north)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var sample := _sample(road, east, north)
	vertices.append(Vector3(east, float(sample.get("height_m", 0.0)) + 0.016, -north))
	normals.append(_normal(sample))
	for offset in shape:
		var point := center + offset
		sample = _sample(road, point.x, -point.y)
		vertices.append(Vector3(point.x, float(sample.get("height_m", 0.0)) + 0.016, point.y))
		normals.append(_normal(sample))
	for i in range(shape.size()):
		indices.append_array(PackedInt32Array([0, i + 1, (i + 1) % shape.size() + 1]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var arrow_mesh := ArrayMesh.new()
	arrow_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var arrow := MeshInstance3D.new()
	arrow.name = node_name
	arrow.mesh = arrow_mesh
	arrow.material_override = _flat_material(Color("#f0eee8"))
	arrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(arrow)


static func _add_flags(root: Node3D, track: Dictionary, road: Callable) -> void:
	var spawn: Dictionary = {}
	for value in track.get("spawns", []):
		if typeof(value) == TYPE_DICTIONARY and str(value.get("id", "")) == "track_start":
			spawn = value
			break
	if spawn.is_empty():
		return
	var n := float(spawn.get("north_m", 39.0))
	var e := float(spawn.get("east_m", -9.0))
	var half := float(track.lane_width_m) * 0.5
	for side in [-1.0, 1.0]:
		var flag_n := n + float(side) * (half + 0.58)
		var sample := _sample(road, e, flag_n)
		var ground := float(sample.get("height_m", 0.0))
		var pole := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 0.022
		cylinder.bottom_radius = 0.032
		cylinder.height = 1.45
		pole.mesh = cylinder
		pole.position = Vector3(e, ground + 0.725, -flag_n)
		pole.material_override = _flat_material(Color("#42494b"))
		pole.name = "StartFlagPole"
		pole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(pole)
		var cloth := MeshInstance3D.new()
		var flag_mesh := BoxMesh.new()
		flag_mesh.size = Vector3(0.42, 0.22, 0.025)
		cloth.mesh = flag_mesh
		cloth.position = Vector3(e + 0.22, ground + 1.28, -flag_n)
		cloth.material_override = _flat_material(PALETTE.col("flag_red") if side < 0.0 else PALETTE.col("flag_white"))
		cloth.name = "StartFlag"
		cloth.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(cloth)


static func _add_walls(root: Node3D, track: Dictionary) -> void:
	var walls: Array = track.get("walls", [])
	for i in range(walls.size()):
		if typeof(walls[i]) != TYPE_DICTIONARY:
			continue
		var wall: Dictionary = walls[i]
		var nmin := float(wall.north_min_m)
		var nmax := float(wall.north_max_m)
		var emin := float(wall.east_min_m)
		var emax := float(wall.east_max_m)
		var bottom := float(wall.bottom_up_m)
		var top := float(wall.top_up_m)
		var barrier := MeshInstance3D.new()
		var box := BoxMesh.new()
		# Match each authored wall AABB exactly. These meshes add no collision.
		box.size = Vector3(emax - emin, top - bottom, nmax - nmin)
		barrier.mesh = box
		barrier.position = Vector3((emin + emax) * 0.5, (bottom + top) * 0.5, -(nmin + nmax) * 0.5)
		barrier.material_override = _flat_material(Color("#c8682c") if i % 2 == 0 else Color("#e4e0d6"))
		barrier.name = str(wall.get("id", "TrackWall"))
		barrier.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(barrier)


static func _add_signs(root: Node3D, road: Callable) -> void:
	var es := TranslationServer.get_locale().begins_with("es")
	_add_label(root, road, "CIRCUITO RC\nACCESO" if es else "RC CIRCUIT\nACCESS", 22.8, -12.6, 1.18)
	_add_label(root, road, "SALTOS" if es else "JUMPS", 35.7, 1.0, 0.62)
	_add_label(root, road, "ONDULACIONES" if es else "ROLLERS", 54.6, 0.0, 0.62)
	_add_label(root, road, "ESLALON" if es else "SLALOM", 47.8, 0.0, 0.62)


static func _add_label(root: Node3D, road: Callable, text_value: String, north: float, east: float, lift: float) -> void:
	var sample := _sample(road, east, north)
	var label := Label3D.new()
	label.text = text_value
	label.font_size = 40
	label.pixel_size = 0.0007
	label.fixed_size = true
	label.visibility_range_end = 90.0
	label.modulate = Color("#f1d6a0")
	label.outline_size = 6
	label.outline_modulate = Color("#33302b")
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3(east, float(sample.get("height_m", 0.0)) + lift, -north)
	root.add_child(label)


static func _flat_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material

