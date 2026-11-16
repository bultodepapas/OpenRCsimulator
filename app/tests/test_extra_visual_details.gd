# Detail regressions plus the existing Extra geometry/articulation verifier.
extends "res://aircraft/verify_extra.gd"


func _run() -> void:
	var airplane := AirplaneBuilder.build(AirplaneBuilder.EXTRA_ID)
	var root: Node3D = airplane.root
	get_root().add_child(root)
	var face := root.get_node("cowl_face") as MeshInstance3D
	var ducts := root.get_node("cowl_intakes") as MeshInstance3D
	var z: float = Geometry.DATA.fuselage_stations[0][0]
	var center_y := (Extra.profile(z, 2) + Extra.profile(z, 3)) * 0.5
	var lips := root.get_node("cowl_lips") as MeshInstance3D
	var faces := face.mesh.get_faces()
	faces.append_array(lips.mesh.get_faces())
	for side in [-1.0, 1.0]:
		var center := Vector2(side * Extra.profile(z, 1) * 0.67, center_y)
		var covered := false
		for i in range(0, faces.size(), 3):
			var triangle := PackedVector2Array()
			for k in 3: triangle.append(Vector2(faces[i + k].x, faces[i + k].y))
			covered = covered or Geometry2D.is_point_in_polygon(center, triangle)
		_check("cooling opening %s is open through the front face" % side, not covered)
	_check("cooling throats are recessed", ducts.get_aabb().end.z > z + 0.015)
	var lip_bounds := lips.get_aabb()
	_check("painted intake lips have real curved depth", lip_bounds.size.z > 0.0014 and lip_bounds.size.z < 0.0016)
	var spinner := root.get_node("thrust_frame/spinner") as MeshInstance3D
	var backplate := root.get_node("thrust_frame/spinner_backplate") as MeshInstance3D
	_check("spinner cone is closed with finite outward unit normals", _closed_surface(spinner))
	_check("spinner backplate is closed with finite outward unit normals", _closed_surface(backplate))
	var spinner_data: Dictionary = Geometry.DATA.spinner
	var spin_arrays := spinner.mesh.surface_get_arrays(0)
	var spin_points: PackedVector3Array = spin_arrays[Mesh.ARRAY_VERTEX]
	var spin_normals: PackedVector3Array = spin_arrays[Mesh.ARRAY_NORMAL]
	var apex_ok := true
	var apex_count := 0
	for i in spin_points.size():
		if absf(spin_points[i].z - (float(spinner_data.tip_z) - float(spinner_data.back_z))) < 0.000001:
			apex_count += 1
			apex_ok = apex_ok and spin_normals[i].dot(Vector3.FORWARD) > 0.99999
	_check("spinner apex shades along the shaft", apex_ok and apex_count >= 20)
	_check("spinner retains its measured tip", absf(spinner.get_aabb().position.z - (float(spinner_data.tip_z) - float(spinner_data.back_z))) < 0.000001)
	_check("backplate retains the measured radius and back plane", absf(backplate.get_aabb().end.z) < 0.000001 and absf(backplate.get_aabb().size.x - 2.0 * float(spinner_data.radius)) < 0.000001)
	var cowl_gap := INF
	for point in _vertices(backplate): cowl_gap = minf(cowl_gap, z - point.z)
	_check("tilted spinner backplate clears the cowl front plane", cowl_gap > 0.0005, "%.3f mm" % (cowl_gap * 1000.0))
	var spinner_transform := spinner.global_transform
	var backplate_transform := backplate.global_transform
	_check("alternate blade diameter applies", AirplaneBuilder.apply_propeller_diameter(airplane, float(Geometry.DATA.propeller.diameter) * 1.15))
	_check("blade diameter leaves spinner and backplate unchanged", spinner.global_transform.is_equal_approx(spinner_transform) and backplate.global_transform.is_equal_approx(backplate_transform))
	AirplaneBuilder.apply_propeller_diameter(airplane, float(Geometry.DATA.propeller.diameter))
	var gear: Dictionary = Geometry.DATA.gear
	for entry in [["left", gear.main_wheel_diameter, 0.022], ["right", gear.main_wheel_diameter, 0.022],
		["tail", gear.tail_wheel_diameter, 0.01]]:
		var wheel: Node3D = airplane.gear[entry[0]]
		var tire := wheel.get_node("wheel_%s_tire" % entry[0]) as MeshInstance3D
		var hub := wheel.get_node("wheel_%s_hub" % entry[0]) as MeshInstance3D
		var bounds := tire.get_aabb()
		_check("%s tire diameter" % entry[0], absf(bounds.size.y - float(entry[1])) < 0.00001)
		_check("%s tire width" % entry[0], absf(bounds.size.x - float(entry[2])) < 0.00001)
		_check("%s hub follows its wheel" % entry[0], hub.get_parent() == wheel)
		var caps_outward := true
		var cap_faces := 0
		var tire_faces := tire.mesh.get_faces()
		for i in range(0, tire_faces.size(), 3):
			var a := tire_faces[i]
			var b := tire_faces[i + 1]
			var c := tire_faces[i + 2]
			if absf(a.x - b.x) > 0.000001 or absf(a.x - c.x) > 0.000001: continue
			cap_faces += 1
			caps_outward = caps_outward and (c - a).cross(b - a).x * a.x > 0.0
		_check("%s tire caps face outward on both sides" % entry[0], caps_outward and cap_faces == 48)
	var second := AirplaneBuilder.build(AirplaneBuilder.EXTRA_ID)
	var custom := preload("res://render/aircraft_customization.gd")
	var paint := {"paint": [{"slot": "body", "color": "#00A088FF", "pattern": "solid", "accent": "none"}]}
	_check("fuselage paint applies to detail model", custom.apply(airplane, paint).get("ok", false))
	var painted := face.get_active_material(0) as ShaderMaterial
	var stock := second.root.get_node("cowl_face").get_active_material(0) as ShaderMaterial
	_check("cowl face follows body paint", Color(painted.get_shader_parameter("red")).is_equal_approx(Color("#00A088FF")))
	_check("cowl paint is isolated between instances", painted != stock and Color(stock.get_shader_parameter("red")).is_equal_approx(Extra.RED))
	var lip_paint := lips.get_active_material(0) as ShaderMaterial
	var stock_lips := second.root.get_node("cowl_lips").get_active_material(0) as ShaderMaterial
	_check("rounded intake lips follow body paint", Color(lip_paint.get_shader_parameter("red")).is_equal_approx(Color("#00A088FF")))
	_check("intake lip paint is isolated", lip_paint != stock_lips and Color(stock_lips.get_shader_parameter("red")).is_equal_approx(Extra.RED))
	var spinner_paint := spinner.get_active_material(0) as StandardMaterial3D
	var stock_spinner := second.root.get_node("thrust_frame/spinner").get_active_material(0) as StandardMaterial3D
	_check("spinner follows body paint", spinner_paint.albedo_color.is_equal_approx(Color("#00A088FF")))
	_check("spinner paint is isolated", spinner_paint != stock_spinner and stock_spinner.albedo_color.is_equal_approx(Extra.RED))
	var frame := root.get_node("canopy_frame") as MeshInstance3D
	var frame_paint := frame.get_active_material(0) as ShaderMaterial
	var stock_frame := second.root.get_node("canopy_frame").get_active_material(0) as ShaderMaterial
	_check("canopy frame follows body paint", Color(frame_paint.get_shader_parameter("red")).is_equal_approx(Color("#00A088FF")))
	_check("canopy frame paint is isolated", frame_paint != stock_frame and Color(stock_frame.get_shader_parameter("red")).is_equal_approx(Extra.RED))
	var glass := (root.get_node("canopy") as MeshInstance3D).get_active_material(0) as StandardMaterial3D
	_check("glass tint follows the appearance source", Color(glass.albedo_color, 1.0).is_equal_approx(Color(Finish.A.colors.glass)))
	_check("canopy uses a dielectric material", is_zero_approx(glass.metallic))
	var brim := root.get_node("pilot/pilot_cap_brim") as MeshInstance3D
	var front := INF
	for point in _vertices(brim): front = minf(front, point.z)
	_check("pilot visor follows the plan point", absf(front - float(Geometry.DATA.pilot.cap_brim_front[0])) < 0.001)
	var head := root.get_node("pilot/pilot_head") as MeshInstance3D
	_check("integrated head and neck form a closed surface", _closed_surface(head))
	var head_points: PackedVector3Array = head.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for landmark in ["chin", "nose_front", "head_back"]:
		var trace: Array = Geometry.DATA.pilot[landmark]
		var nearest := INF
		for point in head_points:
			if absf(point.x) > 0.00001: continue
			nearest = minf(nearest, Vector2(point.z, point.y).distance_to(Vector2(trace[0], trace[1])))
		_check("pilot %s follows its side-profile point" % landmark, nearest < 0.00015, "%.3f mm" % (nearest * 1000.0))
	var cap := root.get_node("pilot/pilot_cap") as MeshInstance3D
	var cap_points: PackedVector3Array = cap.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var crown_distance := INF
	for point in cap_points:
		crown_distance = minf(crown_distance, point.distance_to(Vector3(0, Geometry.DATA.pilot.cap_top[1], Geometry.DATA.pilot.cap_top[0])))
	_check("cap crown follows the plan point", crown_distance < 0.00015)
	var lens_margin := pilot_lens_margin(root)
	_check("eyewear faces clear the emitted skin", lens_margin > 0.0001, "%.3f mm" % (lens_margin * 1000.0))
	for label in ["pilot", "cockpit"]:
		var interior_meshes: Array[MeshInstance3D] = []
		_meshes(root.get_node(label), interior_meshes)
		var outside := 0
		for mesh in interior_meshes:
			var points: PackedVector3Array = mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = PackedInt32Array() if mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX] == null else mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
			var transform := root.global_transform.affine_inverse() * mesh.global_transform
			var count := points.size() if indices.is_empty() else indices.size()
			for i in range(0, count, 3):
				var a: Vector3 = transform * points[i if indices.is_empty() else indices[i]]
				var b: Vector3 = transform * points[i + 1 if indices.is_empty() else indices[i + 1]]
				var c: Vector3 = transform * points[i + 2 if indices.is_empty() else indices[i + 2]]
				for point in [a, b, c, (a + b) * 0.5, (b + c) * 0.5, (a + c) * 0.5, (a + b + c) / 3.0]:
					if not _inside_canopy(point): outside += 1
		_check(label + " fits the curved canopy", outside == 0, "%d vertices outside" % outside)
	var wing: Dictionary = Geometry.DATA.wing
	for side in ["left", "right"]:
		for outer in [false, true]:
			for upper in [false, true]:
				var error := wing_join_error(root, side, outer, upper)
				_check("%s %s wing join %s matches" % [side, "outer" if outer else "inner", "upper" if upper else "lower"], error <= 0.00001, "%.4f mm" % (error * 1000.0))
		for part in ["root", "ahead_of_aileron", "tip"]:
			_check("%s wing %s is closed" % [side, part], _closed_surface(root.get_node("wing_%s/wing_%s_%s" % [side, side, part])))
		var tip := root.get_node("wing_%s/wing_%s_tip" % [side, side]) as MeshInstance3D
		var inner_height := 0.0
		var outer_height := 0.0
		var planform_ok := true
		var uv_ok := true
		var arrays := tip.mesh.surface_get_arrays(0)
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		for i in points.size():
			var p := points[i]
			var span := absf(p.x)
			var chord := lerpf(wing.root_chord, wing.tip_chord, span / (float(wing.span) * 0.5))
			var le := lerpf(wing.le_z_root, wing.le_z_tip, span / (float(wing.span) * 0.5))
			planform_ok = planform_ok and p.z >= le - 0.000001 and p.z <= le + chord + 0.000001
			uv_ok = uv_ok and uv[i].distance_to(Vector2(span, (p.z - le) / chord)) < 0.00001
			if absf(span - float(wing.aileron_outer)) < 0.000001: inner_height = maxf(inner_height, absf(p.y - float(wing.chord_plane_y)))
			if absf(span - float(wing.span) * 0.5) < 0.000001: outer_height = maxf(outer_height, absf(p.y - float(wing.chord_plane_y)))
		var bounds := tip.get_aabb()
		_check(side + " tip preserves the measured planform", planform_ok and absf(bounds.position.z - Extra._le_z(wing.aileron_outer)) < 0.00001 and absf(bounds.size.z - Extra._chord(wing.aileron_outer)) < 0.00001 and absf(bounds.size.x - (float(wing.span) * 0.5 - float(wing.aileron_outer))) < 0.00001)
		_check(side + " tip retains a finite tapered cap", outer_height > 0.001 and outer_height < inner_height * 0.5)
		_check(side + " tip preserves paint coordinates", uv_ok)
		_check(side + " tip has a closed finite surface", _closed_surface(tip))
	var stab := root.get_node("tail_frame/stab") as MeshInstance3D
	var tail: Dictionary = Geometry.DATA.tail
	var outline := PackedVector2Array([Vector2(-tail.stab_half_span, tail.stab_tip_le_z - tail.elevator_hinge_z), Vector2(0, tail.stab_root_le_z - tail.elevator_hinge_z), Vector2(tail.stab_half_span, tail.stab_tip_le_z - tail.elevator_hinge_z), Vector2(tail.stab_half_span, -tail.hinge_gap * 0.5), Vector2(-tail.stab_half_span, -tail.hinge_gap * 0.5)])
	var inside := true
	for p in stab.mesh.get_faces():
		var point := Vector2(p.x, p.z)
		var on_edge := false
		for i in outline.size(): on_edge = on_edge or Geometry2D.get_closest_point_to_segment(point, outline[i], outline[(i + 1) % outline.size()]).distance_to(point) < 0.000001
		inside = inside and (on_edge or Geometry2D.is_point_in_polygon(point, outline)) and absf(p.y) <= float(tail.stab_thickness) * 0.5 + 0.000001
	_check("rounded stabilizer stays inside the original envelope", inside)
	_check("rounded stabilizer has a closed finite surface", _closed_surface(stab))
	second.root.free()
	root.free()
	super._run()


# Sample the rendered eyewear triangles against the actual head, rather than
# repeating its analytic section function. Side arms are outside this front test.
static func pilot_lens_margin(root: Node3D) -> float:
	var head := root.get_node("pilot/pilot_head") as MeshInstance3D
	var eyewear := root.get_node("pilot/pilot_eyewear") as MeshInstance3D
	var skin: PackedVector3Array = head.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var transform := root.global_transform.affine_inverse() * head.global_transform
	for i in skin.size(): skin[i] = (transform * skin[i]) * 1000.0
	var lens: PackedVector3Array = eyewear.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	transform = root.global_transform.affine_inverse() * eyewear.global_transform
	var margin := INF
	var count := 0
	for i in range(0, lens.size(), 3):
		var point: Vector3 = transform * ((lens[i] + lens[i + 1] + lens[i + 2]) / 3.0)
		if absf(point.x) > 0.0175: continue
		var origin := Vector3(point.x, point.y, float(Geometry.DATA.pilot.nose_front[0]) - 0.1) * 1000.0
		var front := INF
		for k in range(0, skin.size(), 3):
			var hit: Variant = Geometry3D.ray_intersects_triangle(origin, Vector3.BACK, skin[k], skin[k + 1], skin[k + 2])
			if hit is Vector3: front = minf(front, hit.z * 0.001)
		if not is_finite(front): return -INF
		margin = minf(margin, front - point.z)
		count += 1
	return margin if count > 10 else -INF


# Compare the actual boundary polylines, independent of the generator's sample
# list. The maximum difference of two piecewise-linear curves is at a vertex
# of either curve. Cap centres are excluded by height, except the shared LE.
static func wing_join_error(root: Node3D, side: String, outer: bool, upper: bool) -> float:
	var wing: Dictionary = Geometry.DATA.wing
	var seam: float = wing.aileron_outer if outer else wing.aileron_inner
	var names := ["ahead_of_aileron", "tip"] if outer else ["root", "ahead_of_aileron"]
	var curves: Array = []
	for part in names:
		var mesh := root.get_node("wing_%s/wing_%s_%s" % [side, side, part]) as MeshInstance3D
		var transform := root.global_transform.affine_inverse() * mesh.global_transform
		var points: Array[Vector2] = []
		var vertices: PackedVector3Array = mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for vertex in vertices:
			var p: Vector3 = transform * vertex
			if absf(absf(p.x) - seam) > 0.000001: continue
			var height := p.y - float(wing.chord_plane_y)
			if height * (1.0 if upper else -1.0) > 0.000001 or absf(p.z - Extra._le_z(seam)) < 0.000001:
				points.append(Vector2(p.z, p.y))
		points.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
		var unique: Array[Vector2] = []
		for point in points:
			if unique.is_empty() or point.x - unique[-1].x > 0.0000001: unique.append(point)
		if unique.size() < 2: return INF
		curves.append(unique)
	var start := maxf(curves[0][0].x, curves[1][0].x)
	var end := minf(curves[0][-1].x, curves[1][-1].x)
	if end <= start: return INF
	var worst := 0.0
	for curve in curves:
		for point in curve:
			if point.x < start or point.x > end: continue
			worst = maxf(worst, absf(_curve_height(curves[0], point.x) - _curve_height(curves[1], point.x)))
	return worst


static func _curve_height(points: Array[Vector2], z: float) -> float:
	for i in points.size() - 1:
		if z <= points[i + 1].x:
			return lerpf(points[i].y, points[i + 1].y, (z - points[i].x) / (points[i + 1].x - points[i].x))
	return points[-1].y


static func _closed_surface(mesh: MeshInstance3D) -> bool:
	var arrays := mesh.mesh.surface_get_arrays(0)
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for normal in normals:
		if not normal.is_finite() or absf(normal.length() - 1.0) > 0.001: return false
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = PackedInt32Array() if arrays[Mesh.ARRAY_INDEX] == null else arrays[Mesh.ARRAY_INDEX]
	var faces := PackedVector3Array()
	if indices.is_empty(): faces = vertices
	else:
		for index in indices: faces.append(vertices[index])
	var edges := {}
	for i in range(0, faces.size(), 3):
		var average := Vector3.ZERO
		for j in 3: average += normals[i + j if indices.is_empty() else indices[i + j]]
		if (faces[i + 2] - faces[i]).cross(faces[i + 1] - faces[i]).dot(average) <= 0.0: return false
		var keys := []
		for j in 3:
			var p := faces[i + j]
			if not p.is_finite(): return false
			keys.append("%d,%d,%d" % [roundi(p.x * 1000000.0), roundi(p.y * 1000000.0), roundi(p.z * 1000000.0)])
		for j in 3:
			var pair := [keys[j], keys[(j + 1) % 3]]
			pair.sort()
			var key := "%s/%s" % pair
			edges[key] = int(edges.get(key, 0)) + 1
	for count in edges.values():
		if count != 2: return false
	return true


# Independent containment gate for visible cabin parts. The centerline-only
# check in the original verifier cannot detect a shoulder through the glass.
func _inside_canopy(point: Vector3) -> bool:
	var canopy: Dictionary = Geometry.DATA.canopy
	var base := Extra.profile(point.z, 2) - 0.002
	if point.y <= base: return true
	var height := Extra.monotone(canopy.top, point.z) - base
	var start: float = canopy.top[0][0]
	var end: float = canopy.top[-1][0]
	var u := absf((point.z - (start + end) * 0.5) / ((end - start) * 0.5))
	var half: float = canopy.halfwidth_fraction * Extra.profile(point.z, 1) * pow(maxf(1.0 - pow(u, 4.0), 0.0), 0.25)
	half = minf(half, Extra.skin_half_width(point.z, base))
	if half <= 0.0 or height <= 0.0: return false
	return pow(point.x / half, 2.0) + pow((point.y - base) / height, 2.0) <= 1.001
