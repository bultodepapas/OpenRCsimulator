extends SceneTree
const Timber := preload("res://aircraft/timber_model.gd")
const VisualDetails := preload("res://aircraft/timber_visual_details.gd")
const VisualLighting := preload("res://aircraft/timber_visual_lighting.gd")
const SKY := Color("#9bcef0")
var camera: Camera3D
var root: Node3D
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	DirAccess.make_dir_recursive_absolute("C:/DEVELOPMENT/OpenRCsimulator/tmp/timber-overhaul/source-isolation")
	get_root().size = Vector2i(1280,720)
	var env := Environment.new(); env.background_mode = Environment.BG_COLOR; env.background_color = SKY; env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; env.ambient_light_color = Color(0.75,0.78,0.82); env.ambient_light_energy = 0.55
	var world := WorldEnvironment.new(); world.environment=env; get_root().add_child(world)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees=Vector3(-50,-35,0); sun.light_energy=1.1; get_root().add_child(sun)
	var model := Timber.build(); root=model.root as Node3D; VisualDetails.apply(root); VisualLighting.apply(root); get_root().add_child(root)
	camera=Camera3D.new(); camera.near=0.02; camera.far=400.0; camera.fov=30.0; get_root().add_child(camera); camera.current=true
	camera.look_at_from_position(Vector3(-0.45,0.05,-0.55),Vector3(0,-0.01,-0.2),Vector3.UP)
	for frame in 3: await process_frame
	await RenderingServer.frame_post_draw
	var cowl:=root.find_child("cowl",true,false) as MeshInstance3D
	var fuselage:=root.find_child("fuselage_core",true,false) as MeshInstance3D
	cowl.visible=false; await _capture("cowl_hidden.png"); cowl.visible=true
	fuselage.visible=false; await _capture("fuselage_hidden.png"); fuselage.visible=true
	var debug_material:=StandardMaterial3D.new(); debug_material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED; debug_material.albedo_color=Color.MAGENTA; cowl.material_override=debug_material; await _capture("cowl_magenta.png")
	quit()
func _capture(name:String) -> void:
	for frame in 2: await process_frame
	await RenderingServer.frame_post_draw
	var path="C:/DEVELOPMENT/OpenRCsimulator/tmp/timber-overhaul/source-isolation/"+name
	get_root().get_texture().get_image().save_png(path); print("CAPTURE ",path)
