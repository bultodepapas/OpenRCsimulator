extends SceneTree
const Policy := preload("res://render/lighting/lighting_policy.gd")
const Rig := preload("res://render/lighting/aircraft_lighting_rig_3d.gd")
const Profile := preload("res://render/lighting/lighting_profile.gd")
const Lights := preload("res://render/world/aircraft_lights.gd")
const ShaderClock := preload("res://render/shader_clock.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	ShaderClock.register()
	var stage := Node3D.new()
	root.add_child(stage)
	var aircraft := Node3D.new()
	stage.add_child(aircraft)
	var body := MeshInstance3D.new()
	body.mesh = BoxMesh.new()
	body.mesh.size = Vector3(2, 0.1, 1)
	aircraft.add_child(body)
	var kit := Lights.attach(aircraft)
	for name in ["strip_left", "strip_right"]:
		if kit.get_node_or_null(name) == null:
			kit.add_child(Lights.strip(name, PackedVector3Array([Vector3.ZERO, Vector3.RIGHT])))
	var rig := Rig.new()
	stage.add_child(rig)
	var profile := Profile.preset("festival")
	var original := JSON.stringify(profile)
	Policy.apply({"aircraft_lighting_quality": "high"})
	check("full quality configures the accepted Festival profile", rig.configure(aircraft, profile).ok)
	var telemetry := {"effects_allowed": true, "distance_m": 0.0, "exposure": 1.0, "throttle": 1.0}
	rig.advance(8.02, telemetry)
	check("High emits 64 particles across two tips", _particle_count(stage) == 64)
	Policy.apply({"aircraft_lighting_quality": "standard"})
	rig.reset()
	rig.advance(8.02, telemetry)
	check("Standard emits 32 particles across two tips", _particle_count(stage) == 32)
	Policy.apply({"aircraft_lighting_show_vfx": false})
	rig.advance(8.02, telemetry)
	check("disabling VFX clears existing particles at a paused clock", _particle_count(stage) == 0)
	Policy.apply({"aircraft_lighting_show_vfx": true})
	rig.advance(8.02, telemetry)
	check("reenabling VFX does not replay the current cue", _particle_count(stage) == 0)
	Policy.apply({"aircraft_lighting_quality": "low"})
	rig.reset()
	rig.advance(8.02, telemetry)
	var spills: Array[Node] = kit.find_children("strip_spill_*", "OmniLight3D", false, false)
	check("Low hides decorative spill and show effects", spills.size() == 2 and spills.all(func(light: Node) -> bool: return not light.visible) and _particle_count(stage) == 0)
	check("Low preserves navigation and orientation equipment", kit.get_node("nav_left").visible and kit.get_node("strip_left").visible)
	Policy.apply({"aircraft_lighting_reduced_flashes": true})
	rig.advance(8.02, telemetry)
	var mat := kit.get_node("strip_left").get_surface_override_material(0) as ShaderMaterial
	var first: Vector4 = mat.get_shader_parameter("pattern_settings")
	rig.advance(9.21, telemetry)
	check("Reduced flashes turns animated strip patterns into steady colors", first.x == 0 and mat.get_shader_parameter("pattern_settings") == first)
	check("Reduced flashes suppresses VFX and reactive intensity", _particle_count(stage) == 0 and Policy.reaction({"source": "throttle", "gain": 1.0}, telemetry).multiplier == 1.0)
	check("Reduced flashes preserves static segmented colors", Policy.pattern({"id": "segments", "segments": 3}).id == "segments")
	# Inspect a real standalone legacy material; shared non-aircraft lamps retain their default policy.
	var legacy := Lights.sprite("legacy", Color.WHITE, Vector3.ZERO, 1.0, 0.02)
	check("legacy aircraft material carries accessibility scope", legacy.get_active_material(0).get_shader_parameter("aircraft_emitter") == true)
	legacy.free()
	Policy.apply({})
	rig.advance(9.21, telemetry)
	check("restoring preferences resumes the authored animated pattern", (mat.get_shader_parameter("pattern_settings") as Vector4).x != 0)
	check("preferences never rewrite the accepted profile", JSON.stringify(profile) == original)
	await process_frame
	rig.dispose()
	stage.free()
	Policy.apply({})
	if DisplayServer.get_name() != "headless":
		await _native_flashes()
	else:
		print("Native flash pixels skipped: headless renderer.")
	print("Lighting policy: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)

func _particle_count(stage: Node) -> int:
	var count := 0
	for node in stage.find_children("show_*", "MultiMeshInstance3D", true, false):
		count += node.multimesh.visible_instance_count
	return count

func _native_flashes() -> void:
	var view := SubViewport.new()
	view.size = Vector2i(1920, 1080)
	view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.0
	camera.position = Vector3(0, 0, 5)
	view.add_child(camera)
	camera.current = true
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color.BLACK
	view.add_child(environment)
	var lamps: Array[MeshInstance3D] = []
	for index in 3:
		var lamp := Lights.sprite("probe_%d" % index, Color.WHITE, Vector3((index - 1) * 0.5, 0, 0), 0.05, 1.0)
		var mat := lamp.get_active_material(0) as ShaderMaterial
		if index == 1:
			mat = ShaderMaterial.new()
			mat.shader = preload("res://render/lighting/rgb_lamp.gdshader")
			mat.set_shader_parameter("size_m", 0.05)
			mat.set_shader_parameter("local_clock", 0.4)
			lamp.set_surface_override_material(0, mat)
		elif index == 2:
			mat.set_shader_parameter("aircraft_emitter", false)
		mat.set_shader_parameter("flash", Vector4(1, 0.1, 0, 1))
		view.add_child(lamp)
		lamps.append(lamp)
	RenderingServer.global_shader_parameter_set(&"world_exposure", 1.0)
	ShaderClock.update(0.4)
	var off := await _pixels(view)
	check("native legacy and RGB strobes have a dark interval", _lamp_level(off, camera, lamps[0]) < 0.01 and _lamp_level(off, camera, lamps[1]) < 0.01)
	Policy.apply({"aircraft_lighting_reduced_flashes": true})
	var steady := await _pixels(view)
	check("native Reduced flashes keeps legacy and RGB aircraft lamps lit", _lamp_level(steady, camera, lamps[0]) > 0.1 and _lamp_level(steady, camera, lamps[1]) > 0.1)
	check("native aircraft accessibility does not rewrite unrelated field strobes", _lamp_level(steady, camera, lamps[2]) < 0.01)
	Policy.apply({})
	var restored := await _pixels(view)
	check("native turning Reduced flashes off restores the dark interval", _lamp_level(restored, camera, lamps[0]) < 0.01 and _lamp_level(restored, camera, lamps[1]) < 0.01)
	ShaderClock.update(0.05)
	lamps[1].get_active_material(0).set_shader_parameter("local_clock", 0.05)
	var pulse := await _pixels(view)
	check("native original strobe pulse remains visible", _lamp_level(pulse, camera, lamps[0]) > 0.1 and _lamp_level(pulse, camera, lamps[1]) > 0.1)
	view.free()
	await process_frame

func _pixels(view: SubViewport) -> Image:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	return view.get_texture().get_image()

func _lamp_level(image: Image, camera: Camera3D, lamp: Node3D) -> float:
	return image.get_pixelv(Vector2i(camera.unproject_position(lamp.global_position))).r

func check(label: String, ok: bool) -> void:
	checks += 1
	print(("ok   " if ok else "FAIL ") + label)
	if not ok: failures += 1
