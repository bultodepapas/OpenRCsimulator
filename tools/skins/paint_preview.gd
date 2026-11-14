extends SceneTree
## Studio renders of a vehicle with a stock paint, built through the game's own builders.
## Run windowed (a real renderer is needed), from the repository root:
##   .tools/Godot_v4.8-beta2_win64_console.exe --path app --audio-driver Dummy --windowed --resolution 320x200 \
##     --script ../tools/skins/paint_preview.gd -- --vehicle=sebart-avanti-s-a200-p100rx --skin=verde_neon_carbono \
##     --out=<absolute dir> [--views=front34,right,left,top,below,rear34] [--zoom=1.0]
## Ids: aircraft catalog ids (the HX-700 is xcell-60-research) or RC cars (mt8-bisonte, monster-car-2).
## Add OPENRC_SCENE_DETAIL=low to check the Low preset. Output: <out>/<vehicle>_<skin>_<view>.png at 1600x1000.

const AirplaneBuilder := preload("res://render/airplane.gd")
const GroundCatalog := preload("res://vehicles/ground/vehicle_catalog.gd")
const VIEW_DIRECTIONS := {
	"front34": Vector3(-0.9, 0.55, -1.0), "right": Vector3(1.0, 0.12, 0.0), "left": Vector3(-1.0, 0.12, 0.0),
	"top": Vector3(0.15, 1.0, 0.35), "below": Vector3(0.6, -0.8, -0.4), "rear34": Vector3(1.0, 0.45, 1.1),
	"front": Vector3(0.0, 0.15, -1.0), "rear": Vector3(0.0, 0.25, 1.0),
}
var _viewport: SubViewport
var _camera: Camera3D


func _init() -> void:
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1600, 1000)
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.own_world_3d = true
	root.add_child(_viewport)
	var environment := Environment.new()
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.30, 0.48, 0.78)
	sky_material.sky_horizon_color = Color(0.72, 0.79, 0.88)
	sky.sky_material = sky_material
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	var world := WorldEnvironment.new()
	world.environment = environment
	_viewport.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, 35, 0)
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	_viewport.add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 40)
	floor_mesh.mesh = plane
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.47, 0.47, 0.45)
	floor_material.roughness = 0.92
	floor_mesh.material_override = floor_material
	_viewport.add_child(floor_mesh)
	_camera = Camera3D.new()
	_camera.fov = 35
	_camera.near = 0.01
	_viewport.add_child(_camera)
	_run.call_deferred()


func _option(name: String, fallback: String) -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--" + name + "="):
			return argument.trim_prefix("--" + name + "=")
	return fallback


func _build(vehicle: String, skin: String) -> Node3D:
	if GroundCatalog.contains(vehicle):
		var builder := load(str(GroundCatalog.entry(vehicle).model_path)) as Script
		var visual: Dictionary = builder.call("build", skin)
		return visual.root if visual.get("ok", false) else null
	var built: Dictionary = AirplaneBuilder.build(vehicle, NAN, {}, skin)
	return built.get("root") as Node3D


func _bounds(node: Node) -> AABB:
	var result := AABB()
	var first := true
	for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		if not mesh.is_visible_in_tree():
			continue
		var box := mesh.global_transform * mesh.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result


func _run() -> void:
	var vehicle := _option("vehicle", "")
	var skin := _option("skin", "")
	var out := _option("out", "")
	var views := _option("views", "front34,right,left,top,below,rear34").split(",")
	var zoom := float(_option("zoom", "1.0"))
	if vehicle.is_empty() or out.is_empty():
		push_error("paint_preview: pass --vehicle=<id> and --out=<absolute dir>")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(out)
	var node := _build(vehicle, skin)
	if node == null:
		push_error("paint_preview: could not build %s with skin '%s'" % [vehicle, skin])
		quit(1)
		return
	_viewport.add_child(node)
	await process_frame
	node.position.y -= _bounds(node).position.y
	await process_frame
	var box := _bounds(node)
	var centre := box.get_center()
	var distance := box.size.length() * 1.25 / zoom
	for view: String in views:
		if not VIEW_DIRECTIONS.has(view):
			push_warning("paint_preview: unknown view " + view)
			continue
		var direction: Vector3 = (VIEW_DIRECTIONS[view] as Vector3).normalized()
		var lift := 0.0
		if view == "below":
			lift = box.size.length() * 0.6  # raise the model so the camera can look up at it from above the floor
		node.position.y += lift
		_camera.position = centre + Vector3(0, lift, 0) + direction * distance
		_camera.look_at(centre + Vector3(0, lift, 0), Vector3.UP if absf(direction.y) < 0.95 else Vector3.BACK)
		for i in 8:
			await process_frame
		var path := out.path_join("%s_%s_%s.png" % [vehicle, skin if not skin.is_empty() else "default", view])
		_viewport.get_texture().get_image().save_png(path)
		print("saved ", path)
		node.position.y -= lift
	node.queue_free()
	await process_frame
	quit(0)
