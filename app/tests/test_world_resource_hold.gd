extends SceneTree
## A33: a departing world's disk-backed resources stay cached while held, and only those are held.

const WorldResourceHold := preload("res://render/world/world_resource_hold.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const FieldBuilder := preload("res://render/field.gd")
const Clock := preload("res://render/shader_clock.gd")
const MESH_PATH := "res://assets/scenery/aircraft/extra_assembled.res"

var _checks := 0
var _failures := 0


func _initialize() -> void:
	Clock.register()
	_test_selection()
	_test_cache_retention()
	_test_real_field()
	print("world resource hold: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _check(name: String, ok: bool, detail: Variant = "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL: %s %s" % [name, str(detail)])


func _test_selection() -> void:
	_check("null and freed roots hold nothing", WorldResourceHold.collect(null).is_empty())
	var root := Node3D.new()
	var loaded := MeshInstance3D.new()
	loaded.mesh = load(MESH_PATH)
	root.add_child(loaded)
	var generated := MeshInstance3D.new()
	generated.mesh = BoxMesh.new()
	var override := StandardMaterial3D.new()
	var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	override.albedo_texture = ImageTexture.create_from_image(image)
	generated.material_override = override
	root.add_child(generated)
	var batch := MultiMeshInstance3D.new()
	batch.multimesh = MultiMesh.new()
	batch.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	batch.multimesh.mesh = loaded.mesh # shared: counted once
	root.add_child(batch)
	var held := WorldResourceHold.collect(root)
	var paths: Array[String] = []
	for resource: Resource in held:
		paths.append(resource.resource_path)
	_check("the loaded mesh is held once", paths.count(MESH_PATH) == 1, paths)
	_check("generated meshes, materials and textures are not held", held.all(func(r: Resource) -> bool:
		return not r.resource_path.is_empty()), paths)
	_check("a shared resource appears once", paths.size() == _unique(paths).size(), paths)
	root.free()


func _test_cache_retention() -> void:
	var root := Node3D.new()
	var instance := MeshInstance3D.new()
	instance.mesh = load(MESH_PATH)
	root.add_child(instance)
	var held := WorldResourceHold.collect(root)
	root.free()
	_check("a held mesh stays in the resource cache after its world is freed", ResourceLoader.has_cached(MESH_PATH))
	var reloaded: Resource = load(MESH_PATH)
	_check("the next load reuses the held object", held.has(reloaded))
	reloaded = null
	held.clear()
	_check("releasing the hold lets the mesh unload", not ResourceLoader.has_cached(MESH_PATH))


func _test_real_field() -> void:
	var field: Dictionary = FieldLoader.load_from(FieldLoader.DEFAULT_PATH).field
	var first: Node3D = FieldBuilder.build(field, {})
	var started := Time.get_ticks_usec()
	var held := WorldResourceHold.collect(first)
	var collect_ms := (Time.get_ticks_usec() - started) / 1000.0
	first.free()
	var parked := 0
	for resource: Resource in held:
		if resource.resource_path.begins_with("res://assets/scenery/aircraft/"):
			parked += 1
	_check("the default field holds its parked aircraft meshes", parked >= 3, parked)
	_check("the default field holds a few hundred resources", held.size() > 100, held.size())
	_check("collection stays cheap (< 50 ms headless)", collect_ms < 50.0, collect_ms)
	var second: Node3D = FieldBuilder.build(field, {})
	var reused := 0
	for resource: Resource in WorldResourceHold.collect(second):
		if held.has(resource):
			reused += 1
	_check("the rebuilt field reuses the held objects", reused * 10 >= held.size() * 9, "%d of %d" % [reused, held.size()])
	second.free()
	held.clear()


func _unique(values: Array[String]) -> Array[String]:
	var out: Array[String] = []
	for value: String in values:
		if not out.has(value):
			out.append(value)
	return out
