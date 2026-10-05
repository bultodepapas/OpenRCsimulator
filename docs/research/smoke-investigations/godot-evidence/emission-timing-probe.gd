extends Node3D

var emitters: Array[GPUParticles3D] = []
var elapsed := 0.0
var saved := false
var rendered_frames := 0
var max_delta := 0.0
var output := "user://smoke-emission-timing.png"

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			output = arg.trim_prefix("--out=")
	Engine.max_fps = 30
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 48.0
	camera.position = Vector3(0.0, 0.0, 100.0)
	add_child(camera)
	camera.look_at(Vector3.ZERO, Vector3.UP)
	camera.current = true
	var variants := [
		{"y": -15.0, "fps": 30, "interpolate": false, "local": false},
		{"y": -5.0, "fps": 30, "interpolate": true, "local": false},
		{"y": 5.0, "fps": 60, "interpolate": true, "local": false},
		{"y": 15.0, "fps": 30, "interpolate": false, "local": true},
	]
	for item in variants:
		var p := GPUParticles3D.new()
		p.amount = 1200
		p.lifetime = 5.0
		p.one_shot = false
		p.emitting = false
		p.use_fixed_seed = true
		p.seed = 6161
		p.position = Vector3(-32.0, item.y, 0.0)
		p.local_coords = item.local
		p.fixed_fps = item.fps
		p.interpolate = item.interpolate
		p.fract_delta = true
		p.visibility_aabb = AABB(Vector3(-200.0, -200.0, -200.0), Vector3(400.0, 400.0, 400.0))
		var process := ParticleProcessMaterial.new()
		process.direction = Vector3.UP
		process.spread = 0.0
		process.initial_velocity_min = 0.0
		process.initial_velocity_max = 0.0
		process.gravity = Vector3.ZERO
		process.inherit_velocity_ratio = 0.0
		p.process_material = process
		var quad := QuadMesh.new()
		quad.size = Vector2(0.35, 0.35)
		p.draw_pass_1 = quad
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = Color(0.95, 0.22, 0.08)
		material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		material.no_depth_test = true
		quad.material = material
		add_child(p)
		p.restart()
		emitters.append(p)

func _process(delta: float) -> void:
	rendered_frames += 1
	max_delta = maxf(max_delta, delta)
	elapsed += delta
	var x := -32.0 + minf(elapsed, 1.6) * 40.0
	for p in emitters:
		p.position.x = x
	if elapsed >= 2.0 and not saved:
		saved = true
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output).get_base_dir())
		var error := image.save_png(output)
		print(JSON.stringify({"godot": Engine.get_version_info().string,
			"adapter": RenderingServer.get_video_adapter_name(),
			"api": RenderingServer.get_video_adapter_api_version(),
			"frames": rendered_frames, "elapsed_s": elapsed, "max_delta_s": max_delta,
			"output": output, "save_error": error}))
		get_tree().quit(error)
