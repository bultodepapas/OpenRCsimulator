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
	var faces := face.mesh.get_faces()
	for side in [-1.0, 1.0]:
		var center := Vector2(side * Extra.profile(z, 1) * 0.67, center_y)
		var covered := false
		for i in range(0, faces.size(), 3):
			var triangle := PackedVector2Array()
			for k in 3: triangle.append(Vector2(faces[i + k].x, faces[i + k].y))
			covered = covered or Geometry2D.is_point_in_polygon(center, triangle)
		_check("cooling opening %s is open through the front face" % side, not covered)
	_check("cooling throats are recessed", ducts.get_aabb().end.z > z + 0.015)
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
	for label in ["pilot", "cockpit"]:
		var interior_meshes: Array[MeshInstance3D] = []
		_meshes(root.get_node(label), interior_meshes)
		var outside := 0
		for mesh in interior_meshes:
			for point in _vertices(mesh):
				if not _inside_canopy(point): outside += 1
		_check(label + " fits the curved canopy", outside == 0, "%d vertices outside" % outside)
	var wing: Dictionary = Geometry.DATA.wing
	for side in ["left", "right"]:
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


func _closed_surface(mesh: MeshInstance3D) -> bool:
	var arrays := mesh.mesh.surface_get_arrays(0)
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for normal in normals:
		if not normal.is_finite() or absf(normal.length() - 1.0) > 0.001: return false
	var faces := mesh.mesh.get_faces()
	var edges := {}
	for i in range(0, faces.size(), 3):
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
