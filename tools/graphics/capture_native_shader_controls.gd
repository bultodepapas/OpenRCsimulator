## Isolated 1080p render controls for the shipped RC circuit surface and pilot lens stack.
## Run on a drawing renderer with --script <this-file> -- --out=<new absolute directory>.
extends SceneTree

const Field := preload("res://data/field_loader.gd")
const Course := preload("res://physics/ground_vehicle/airfield_course.gd")
const TrackView := preload("res://vehicles/ground/airfield_track_view.gd")
const TrackMaterial := preload("res://render/rc_ground_material.gd")
const Ground := preload("res://render/ground.gd")
const Clock := preload("res://render/shader_clock.gd")
const Lens := preload("res://render/lens/lens_stack.gd")
const LensSettings := preload("res://render/lens/lens_settings.gd")
const SIZE := Vector2i(1920, 1080)
const SEED := 1253
const EVENT_KEY := "native-shader-controls-pilot"
const START_S := 3.0
const GROUND_PATH := "res://render/ground.gdshader"
const FILM_PATH := "res://render/lens/lens_film.gdshader"

var out := ""
var viewport := SubViewport.new()
var camera := Camera3D.new()
var target := Vector3.ZERO
var records: Array[Dictionary] = []


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1 or not args[0].begins_with("--out="):
		fail("expected --out=<new absolute directory>")
		return
	out = args[0].trim_prefix("--out=").simplify_path()
	if (not out.is_absolute_path() or FileAccess.file_exists(out) or DirAccess.dir_exists_absolute(out)
			or DisplayServer.get_name() == "headless"):
		fail("a drawing renderer and new absolute output directory are required")
		return
	if DirAccess.make_dir_recursive_absolute(out) != OK:
		fail("could not create output directory")
		return

	RenderingServer.render_loop_enabled = false
	viewport.size = SIZE
	viewport.world_3d = World3D.new()
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.scaling_3d_scale = 1.0
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.12, 0.12, 0.12)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.08
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	viewport.world_3d.environment = environment
	camera.fov = 32.0
	viewport.add_child(camera)
	camera.current = true
	Clock.register()
	Clock.update(START_S)
	if not await capture_dirt() or not await capture_lens():
		fail("missing production material, control state, or image readback")
		return
	var report := {"complete": true, "method": RenderingServer.get_current_rendering_method(),
		"adapter": RenderingServer.get_video_adapter_name(), "driver": RenderingServer.get_current_rendering_driver_name(),
		"engine": Engine.get_version_info(), "viewport": [SIZE.x, SIZE.y], "seed": SEED, "records": records}
	var file := FileAccess.open(out.path_join("capture.json"), FileAccess.WRITE)
	if file == null:
		fail("could not create capture.json")
		return
	file.store_string(JSON.stringify(report, "\t") + "\n")
	file.flush()
	if file.get_error() != OK:
		fail("could not finish capture.json")
		return
	file.close()
	viewport.free()
	print("Native shader controls complete: ", records.size(), " views")
	quit(0)


func capture_dirt() -> bool:
	var built := Course.build(Field.load_from())
	if not built.ok or not built.course.has("track"):
		return false
	var course: Dictionary = built.course
	var road := func(n: float, e: float) -> Dictionary: return Course.sample(course, n, e)
	var ground := Ground.grass_material()
	TrackMaterial.configure(ground)
	var track := TrackView.build(course, road, ground)
	var surface := track.get_node_or_null("DirtLoopSurface") as MeshInstance3D
	if surface == null:
		track.free()
		return false
	# Isolate the actual drive-grid mesh so barriers, vehicle lamps and sky reflections cannot add highlights.
	track.remove_child(surface)
	track.free()
	viewport.add_child(surface)
	var material := surface.material_override as ShaderMaterial
	if (material == null or material.shader.resource_path != GROUND_PATH
			or material.get_shader_parameter("rc_surface_enabled") != true
			or material.get_shader_parameter("rc_track_surface") != true):
		return false
	for binding: String in TrackMaterial.TEXTURES:
		var texture := material.get_shader_parameter(binding) as Texture2D
		if texture == null or texture.resource_path != TrackMaterial.TEXTURES[binding]:
			return false
	var sample_at_target := Course.sample(course, 39.0, 2.0)
	if float(sample_at_target.get("track_coverage", 0.0)) < 0.99:
		return false
	target = Vector3(2.0, float(sample_at_target.height_m) + 0.002, -39.0)
	camera.position = target + Vector3(0.0, 1.0, 2.0)
	camera.look_at(target)
	var spot := SpotLight3D.new()
	viewport.add_child(spot)
	spot.position = target + Vector3(0.0, 0.95, -1.9)
	spot.look_at(target)
	spot.spot_range = 7.0
	spot.spot_angle = 30.0
	spot.spot_attenuation = 1.15
	spot.spot_angle_attenuation = 1.6
	spot.light_energy = 2.1
	spot.light_indirect_energy = 0.0
	spot.light_color = Color(0.82, 0.91, 1.0)
	spot.shadow_enabled = false
	for setting: Array in [["dirt_light_off", false, 0.0], ["dirt_specular_000", true, 0.0],
			["dirt_specular_035", true, 0.35], ["dirt_specular_050", true, 0.5]]:
		spot.visible = bool(setting[1])
		spot.light_specular = float(setting[2])
		var controls := {"shader": material.shader.resource_path, "surface": str(surface.name),
			"mesh_vertices": surface.mesh.surface_get_array_len(0), "track_coverage": sample_at_target.track_coverage,
			"spot_position": xyz(spot.position), "light_visible": spot.visible, "light_energy": spot.light_energy,
			"light_specular": spot.light_specular, "ambient_energy": viewport.world_3d.environment.ambient_light_energy}
		if not await capture(str(setting[0]), controls):
			return false
	surface.free()
	spot.free()
	# This comparison must work on baseline and candidate. The baseline may ignore the specular setting.
	return records[1].sampled_luma > records[0].sampled_luma


func capture_lens() -> bool:
	# A fixed canvas chart keeps the background and refraction cues independent of all audited 3D shaders.
	var chart := CanvasLayer.new()
	chart.layer = -11
	viewport.add_child(chart)
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color(0.2, 0.4, 0.6), Color(0.85, 0.7, 0.46)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_to = Vector2(1.0, 0.35)
	var panel := TextureRect.new()
	panel.texture = texture
	panel.size = Vector2(SIZE)
	chart.add_child(panel)
	for y in [260, 540, 820]:
		var stripe := ColorRect.new()
		stripe.position = Vector2(0.0, y)
		stripe.size = Vector2(SIZE.x, 10.0)
		stripe.color = Color(0.85, 0.86, 0.85)
		chart.add_child(stripe)
	var stack := Lens.new()
	viewport.add_child(stack)
	var flags := {"lens-effects": "medium", "impact-fx": "curtain", "lens-grime": "off", "lens-rain": "off"}
	var context := {"camera": camera, "view_provider": func() -> String: return "pilot",
		"seed": SEED, "settings": LensSettings.resolve({"lens-effects": "off"}, false, LensSettings.DEFAULTS)}
	if stack.configure(context) or stack.snapshot().nodes.film:
		return false
	if not await capture("lens_disabled", {"enabled": false, "shader": "", "age_s": 0.0}):
		return false
	context.settings = LensSettings.resolve(flags, false, LensSettings.DEFAULTS)
	if not stack.configure(context):
		return false
	stack.strike_person(1.0, Vector3.INF, true, EVENT_KEY)
	var film := stack.get_node_or_null("LensLayer/LensFilm") as ColorRect
	if film == null:
		return false
	var mat := film.material as ShaderMaterial
	if mat == null or mat.shader.resource_path != FILM_PATH:
		return false
	# Submit 60 Hz presentation samples at exact multiples of the 240 Hz clock. No simulation is instantiated.
	for frame in range(1, 91):
		var clock_s := START_S + float(frame) / 60.0
		Clock.update(clock_s)
		stack.advance(1.0 / 60.0, clock_s, false)
		if frame != 30 and frame != 90:
			continue
		stack.advance(0.0, clock_s, true)
		var snapshot := stack.snapshot()
		var age := float(mat.get_shader_parameter("curtain_t"))
		if (not snapshot.blood or not film.is_visible_in_tree() or film.size != Vector2(SIZE)
				or not is_equal_approx(age, float(frame) / 60.0) or mat.get_shader_parameter("curtain_on") != 1.0):
			return false
		var controls := {"enabled": true, "shader": mat.shader.resource_path, "age_s": age,
			"seed": SEED, "event_key": EVENT_KEY, "film_seed": mat.get_shader_parameter("seed"),
			"depth": mat.get_shader_parameter("depth"), "view": snapshot.view, "stamps": snapshot.stamps}
		var name_value := "lens_curtain_partial" if frame == 30 else "lens_curtain_held"
		if not await capture(name_value, controls):
			return false
	return records[5].sha256 != records[4].sha256 and records[6].sha256 != records[5].sha256


func capture(id: String, controls: Dictionary) -> bool:
	for settle_frame in 5:
		await process_frame
		RenderingServer.force_draw(false)
	var image := viewport.get_texture().get_image()
	if image == null or image.is_empty() or image.get_size() != SIZE:
		return false
	var path := out.path_join(id + ".png")
	if image.save_png(path) != OK:
		return false
	# A fixed central readback in output encoding detects blank or unlit receiver captures.
	var brightness := 0.0
	var samples := 0
	for y in range(468, 613, 8):
		for x in range(816, 1105, 8):
			brightness += image.get_pixel(x, y).get_luminance()
			samples += 1
	records.append({"view": id, "eye": xyz(camera.position), "at": xyz(target), "fov": camera.fov,
		"clock_s": Clock.last_clock, "controls": controls, "sha256": FileAccess.get_sha256(path),
		"sampled_luma": brightness / float(samples)})
	return true


func xyz(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


func fail(message: String) -> void:
	printerr("Native shader controls failed: ", message)
	if is_instance_valid(camera) and camera.get_parent() == null:
		camera.free()
	if is_instance_valid(viewport):
		viewport.free()
	quit(1)
