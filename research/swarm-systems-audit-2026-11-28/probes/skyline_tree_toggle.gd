extends SceneTree

const FieldDetail = preload("res://render/field_detail_preferences.gd")
const GlareLayer = preload("res://render/landscape_upgrade/sun_glare.gd")
const FieldSkyline = preload("res://render/sun/skyline.gd")
const EYE := Vector3(0.0, 1.7, 0.0)
const RADIUS := 0.0047

func _initialize() -> void:
	_run.call_deferred()

func _read_current(glare: GlareLayer, camera: Camera3D, ray: Vector3) -> float:
	glare._skyline_prior(camera, ray, RADIUS, true)
	glare.skyline().finish()
	return glare._skyline_prior(camera, ray, RADIUS, true)

func _fresh(field: Node3D, camera: Camera3D, ray: Vector3) -> float:
	var rebuilt := FieldSkyline.new(field, camera.global_position)
	rebuilt.finish()
	return rebuilt.visibility(ray, RADIUS)

func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var field := Node3D.new()
	field.name = "Field"
	stage.add_child(field)
	var tree := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(10.0, 20.0, 10.0)
	tree.mesh = box
	tree.position = Vector3(60.0, 10.0, 0.0)
	field.add_child(tree)
	FieldDetail.apply(self, {"tree_detail": "full"})
	FieldDetail.register_tree(tree)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.position = EYE
	var layer := GlareLayer.new()
	stage.add_child(layer)
	var angle := deg_to_rad(8.0)
	var ray := Vector3(cos(angle), sin(angle), 0.0)
	var before := _read_current(layer, camera, ray)
	FieldDetail.apply(self, {"tree_detail": "off"})
	var off_visible := tree.is_visible_in_tree()
	var off_cached := _read_current(layer, camera, ray)
	var off_fresh := _fresh(field, camera, ray)
	camera.position += Vector3(0.0, 0.0, GlareLayer.SKYLINE_REBUILD_M + 0.1)
	var off_moved := _read_current(layer, camera, ray)
	FieldDetail.apply(self, {"tree_detail": "full"})
	var full_visible := tree.is_visible_in_tree()
	var full_cached := _read_current(layer, camera, ray)
	var full_fresh := _fresh(field, camera, ray)
	camera.position = EYE
	var full_moved := _read_current(layer, camera, ray)
	print("AUDIT_TREE_SKYLINE ", JSON.stringify({"prior_at_full": before, "off_visible": off_visible,
		"off_cached": off_cached, "off_fresh": off_fresh, "off_after_2_1m": off_moved,
		"full_visible": full_visible, "full_cached": full_cached, "full_fresh": full_fresh,
		"full_after_2_1m": full_moved}))
	var confirmed := not off_visible and full_visible and before < 0.01 and off_cached < 0.01 and off_fresh > 0.99 \
		and off_moved > 0.99 and full_cached > 0.99 and full_fresh < 0.01 and full_moved < 0.01
	stage.free()
	quit(0 if confirmed else 1)
