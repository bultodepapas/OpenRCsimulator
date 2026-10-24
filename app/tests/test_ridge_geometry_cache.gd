extends SceneTree

const Ridges := preload("res://render/landscape_upgrade/ridges.gd")
const Clock := preload("res://render/shader_clock.gd")
var _failed := 0
var _checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(passed: bool, label: String) -> void:
	_checks += 1
	if not passed:
		_failed += 1
		printerr("FAIL ", label)

func _geometry(node: Node3D) -> PackedByteArray:
	var geometry: Array = []
	for child: MeshInstance3D in node.get_children():
		geometry.append([child.name, child.mesh.surface_get_arrays(0), child.mesh.get_aabb(), child.cast_shadow])
	return var_to_bytes(geometry)

func _run() -> void:
	Clock.register()
	var first: Node3D = Ridges.build()
	var expected := _geometry(first)
	var second: Node3D = Ridges.build()
	_check(first.get_child_count() == 4 and first.get_meta("triangles") == 27648, "four complete ridge chunks")
	_check(expected == _geometry(second), "warm construction retains exact geometry")
	var first_material: ShaderMaterial = first.get_meta("lighting_material")
	var second_material: ShaderMaterial = second.get_meta("lighting_material")
	_check(first_material != second_material, "worlds own separate lighting materials")
	var original: Variant = first_material.get_shader_parameter("exposure")
	second_material.set_shader_parameter("exposure", 7.0)
	_check(first_material.get_shader_parameter("exposure") == original, "lighting change cannot leak between worlds")
	for chunk in 4:
		_check(first.get_child(chunk).mesh != second.get_child(chunk).mesh, "scene-local mesh %d" % chunk)
	second.get_child(0).mesh.clear_surfaces()
	var third: Node3D = Ridges.build()
	_check(_geometry(first) == expected and _geometry(third) == expected, "scene mesh mutation cannot damage cached geometry")
	first.free()
	second.free()
	third.free()
	_check(Ridges._load_profile(), "source profile reload validates")
	_check(Ridges._geometry.is_empty(), "source reload invalidates cached buffers")
	var reloaded: Node3D = Ridges.build()
	_check(_geometry(reloaded) == expected, "reloaded source reproduces geometry")
	_check(Ridges._geometry.size() == 4, "geometry cache stays bounded to four chunks")
	reloaded.free()
	first_material = null
	second_material = null
	await process_frame
	print("ridge geometry cache: %d checks, %d failed" % [_checks, _failed])
	quit(1 if _failed else 0)
