# SUN-09 (docs/plans/sun.md): the field's skyline from the pilot's eye, on a synthetic field with known geometry.
#   - a row of 10 m trees (MultiMesh) 100 m north rises the skyline there to atan(8.3/100) and only over their crowns;
#   - a 20 m building (mesh, vertex-sampled) east gives its roof's elevation; a flat ground plane changes nothing;
#   - a shelter within EXCLUDE_RADIUS_M of the eye and hidden nodes are ignored;
#   - visibility: a disc below the skyline is hidden, above it visible, with a smooth edge over its diameter;
#   - the result does not depend on the per-frame work budget (captures and replays finish it on the same frame).
# Run: godot --headless --path . --script res://tests/test_sun_skyline.gd
extends SceneTree

const Skyline := preload("res://render/sun/skyline.gd")

const EYE := Vector3(0.0, 1.7, 0.0)

var _failures := 0
var _count := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _initialize() -> void:
	_run.call_deferred()


static func _toward(azimuth_deg: float, elevation_deg: float) -> Vector3:
	var az := deg_to_rad(azimuth_deg)
	var el := deg_to_rad(elevation_deg)
	return Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el)) # north = −z, east = +x


## Whether this renderer keeps MultiMesh instance transforms readable (the headless dummy renderer does not).
static func _multimesh_readback() -> bool:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = BoxMesh.new()
	mm.instance_count = 1
	mm.set_instance_transform(0, Transform3D(Basis.IDENTITY, Vector3(1.0, 2.0, 3.0)))
	return mm.get_instance_transform(0).origin.is_equal_approx(Vector3(1.0, 2.0, 3.0))


func _field() -> Node3D:
	var field := Node3D.new()
	field.name = "Field"
	# Ten trees, 10 m tall and 4 m wide, 100 m north, 6 m apart (east-west): azimuths −27°…+27°.
	var tree := BoxMesh.new()
	tree.size = Vector3(4.0, 10.0, 4.0)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = tree
	mm.instance_count = 10
	for i in 10:
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(-27.0 + 6.0 * i, 5.0, -100.0)))
	var trees := MultiMeshInstance3D.new()
	trees.multimesh = mm
	field.add_child(trees)
	# A 20 m building 60 m east.
	var building := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(10.0, 20.0, 10.0)
	building.mesh = box
	building.position = Vector3(60.0, 10.0, 0.0)
	field.add_child(building)
	# A flat ground plane at the feet, and a shelter roof 2 m from the eye: both ignored.
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(2000.0, 2000.0)
	ground.mesh = plane
	field.add_child(ground)
	var shelter := MeshInstance3D.new()
	var roof := BoxMesh.new()
	roof.size = Vector3(2.0, 0.2, 2.0)
	shelter.mesh = roof
	shelter.position = Vector3(0.0, 3.0, 1.0) # every corner within EXCLUDE_RADIUS_M
	field.add_child(shelter)
	# A hidden 50 m mast west: ignored.
	var mast := MeshInstance3D.new()
	var pole := BoxMesh.new()
	pole.size = Vector3(1.0, 50.0, 1.0)
	mast.mesh = pole
	mast.position = Vector3(-40.0, 25.0, 0.0)
	mast.visible = false
	field.add_child(mast)
	return field


func _run() -> void:
	var field := _field()
	root.add_child(field)
	var sky := Skyline.new(field, EYE)
	sky.finish()
	_check("built", sky.done)
	# The tree at x = 3 m is 1.72° east of north and its crown spans ±0.8°; the gap at due north lets the sun through.
	# The headless dummy renderer keeps no MultiMesh instance data (every instance reads back at the origin, inside the
	# exclusion radius), so the tree checks need a real renderer: `xvfb-run … --rendering-driver opengl3`.
	var tree_top := atan2(10.0 - EYE.y, 100.0)
	var tree_az := rad_to_deg(atan2(3.0, 100.0))
	var trees_kept := _multimesh_readback()
	if trees_kept:
		_check("a tree raises the skyline to its top", absf(sky.elevation(_toward(tree_az, 0.0)) - tree_top) < 0.01,
			str(rad_to_deg(sky.elevation(_toward(tree_az, 0.0)))))
		_check("the gap between crowns stays open", sky.elevation(_toward(0.0, 0.0)) == Skyline.EMPTY)
	else:
		print("skipped: this renderer keeps no MultiMesh instance data (headless); tree checks need opengl3")
	_check("the sky beside the row stays open", sky.elevation(_toward(40.0, 0.0)) == Skyline.EMPTY)
	# Due east lies between the building's corners (84.8° and 95.2°): its edges cover the face at the roof's height.
	var roof_top := atan2(20.0 - EYE.y, 55.0)
	_check("a building's whole face gives its roof's elevation", absf(sky.elevation(_toward(90.0, 0.0)) - roof_top) < 0.01,
		str(rad_to_deg(sky.elevation(_toward(90.0, 0.0)))))
	_check("flat ground, the near shelter and a hidden mast add nothing",
		sky.elevation(_toward(180.0, 0.0)) == Skyline.EMPTY and sky.elevation(_toward(270.0, 0.0)) == Skyline.EMPTY)
	# Visibility against the building's roof (vertex data is kept by every renderer).
	var r := deg_to_rad(0.27)
	_check("a sun below the roof is hidden", sky.visibility(_toward(90.0, rad_to_deg(roof_top) - 1.0), r) == 0.0)
	_check("a sun above it is clear", sky.visibility(_toward(90.0, rad_to_deg(roof_top) + 1.0), r) == 1.0)
	var edge := sky.visibility(_toward(90.0, rad_to_deg(roof_top)), r)
	_check("half the disc at the roof line", absf(edge - 0.5) < 0.01, str(edge))
	if trees_kept:
		_check("a sun below the treetops is hidden", sky.visibility(_toward(tree_az, rad_to_deg(tree_top) - 1.0), r) == 0.0)
	_check("an open azimuth is clear", sky.visibility(_toward(200.0, 2.0), r) == 1.0)
	# The work budget only changes when it finishes, not what it builds.
	var stepped := Skyline.new(field, EYE)
	var frames := 0
	while not stepped.step(17):
		frames += 1
	_check("step-by-step equals finish", stepped.bins == sky.bins, "%d frames" % frames)
	_check("the azimuth wraps", Skyline.azimuth_bin(_toward(359.9, 0.0)) == Skyline.BINS - 1
		and Skyline.azimuth_bin(_toward(0.1, 0.0)) == 0)
	var none := Skyline.new(null, EYE)
	_check("no field: done and empty", none.done and none.visibility(_toward(0.0, 1.0), r) == 1.0)
	field.free()
	print("SUN skyline: %d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)
