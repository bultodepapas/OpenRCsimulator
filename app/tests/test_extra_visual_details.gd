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
	second.root.free()
	root.free()
	super._run()
