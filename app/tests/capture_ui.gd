# UI captures use the real Home and app_root routes where a screen transition matters.
# Needs a renderer (run under Xvfb, see capture.sh):
#   godot --path . --rendering-driver opengl3 --script res://tests/capture_ui.gd -- --out=/path/flight.png --lang=en --screen=flight
#   [--screen=home|pause|help|hint] [--aircraft=<catalog id>]
# Software rendering proves layout and focus drawing, not GPU quality or legibility on the pilot's monitor.
extends SceneTree

const Home := preload("res://ui/home.gd")
const HomeScene := preload("res://ui/home_scene.gd")
const Preferences := preload("res://app_state/preferences.gd")
const Commands := preload("res://input/commands.gd")
const VisualEvidence := preload("res://render/visual_evidence.gd")
const ShaderClock := preload("res://render/shader_clock.gd")
const TARGET_FLIGHT_TIME_S: float = 1.5
const FLIGHT_PREFERENCES_PATH: String = "user://capture_ui_flight_settings.cfg"


func _initialize() -> void:
	_run()


func _run() -> void:
	var out: String = "user://home.png"
	var lang: String = "en"
	var screen: String = "home"
	var aircraft: String = "jensen-das-ugly-stik-60"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--aircraft="):
			aircraft = arg.trim_prefix("--aircraft=")
		elif arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
		elif arg.begins_with("--lang="):
			lang = arg.trim_prefix("--lang=")
		elif arg.begins_with("--screen="):
			screen = arg.trim_prefix("--screen=")
	TranslationServer.set_locale(lang) # never the OS locale: captures must not depend on the machine
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var app: Node = null
	var home_field: Node3D = null
	var flight: Node = null
	var transition_timing: Dictionary = {}
	var visual_state: Dictionary = {}
	var route: String = "standalone-home"

	if screen == "flight":
		# The capture still follows the interactive route: no CLI args reach app_root, and the real Home Fly button
		# emits its normal signal. A private settings file fixes language and suppresses only the first-flight hint.
		var prefs: Dictionary = Preferences.DEFAULTS.duplicate()
		prefs.language = lang
		prefs.first_flight_hint_seen = true
		prefs.aircraft = aircraft
		var prefs_error: Error = Preferences.save_to(FLIGHT_PREFERENCES_PATH, prefs)
		if prefs_error != OK:
			push_error("Cannot write deterministic UI capture preferences: %s" % error_string(prefs_error))
			quit(1)
			return
		app = _new_app(PackedStringArray(), FLIGHT_PREFERENCES_PATH)
		root.add_child(app)
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw # Home is genuinely drawn before its render resources are freed.
		var home: Node = app.get("home")
		if home == null:
			push_error("Flight capture did not start at Home")
			quit(1)
			return
		var fly_button: Button = home.get("fly_button")
		if fly_button.disabled:
			push_error("Flight capture Home Fly button is disabled for %s" % aircraft)
			quit(1)
			return
		var transition_start_usec: int = Time.get_ticks_usec()
		fly_button.pressed.emit()
		flight = app.get("flight")
		if flight == null:
			push_error("Home Fly did not create the flight scene")
			quit(1)
			return
		var session: Node = flight.get("session")
		var sim: Node = session.get("sim")
		# Draw the initial state before measuring transition completion. A newly built main scene has not yet run its
		# first _process callback, so without this pose the first frame would show the airplane at its origin.
		flight.set("_show_perf", false) # elapsed-frame and physics-cost diagnostics must not enter the PNG
		session.set("input_enabled", false)
		flight.call("_process", 0.0)
		var initial_state: PackedFloat64Array = sim.get("state")
		var initial_pose: Dictionary = flight.call("_pose_of", initial_state)
		var initial_surfaces: Dictionary = session.call("surfaces")
		flight.call("_render_pose", initial_pose, initial_surfaces, 0.0)
		# Freeze before the next frame so startup scheduling can never add a variable physics tick.
		flight.set_process(false)
		sim.process_mode = Node.PROCESS_MODE_DISABLED
		await process_frame
		await RenderingServer.frame_post_draw
		var transition_elapsed_usec: int = Time.get_ticks_usec() - transition_start_usec
		transition_timing = {
			"elapsed_usec": transition_elapsed_usec,
			"scope": "Home Fly activation through the first rendered flight frame",
			"renderer": RenderingServer.get_current_rendering_method(),
			"adapter": RenderingServer.get_video_adapter_name(),
			"cache_state": "unknown",
			"performance_claim": false,
			"note": "Diagnostic wall-clock sample only. Software rendering, including llvmpipe, is not a performance measurement.",
		}
		var tick_seconds: float = sim.dt()
		var target_ticks: int = roundi(TARGET_FLIGHT_TIME_S / tick_seconds)
		for tick_index in range(target_ticks):
			sim.step()
		var simulation_time: float = float(sim.call("time"))
		if int(sim.get("tick")) != target_ticks or not is_equal_approx(simulation_time, TARGET_FLIGHT_TIME_S):
			push_error("Flight capture simulation did not stop at the fixed 1.5 s state (%d ticks, %.9f s)" % [int(sim.get("tick")), simulation_time])
			quit(1)
			return
		# Update the real flight's labels and atmosphere with the fixed state, then pin the exact integrated pose.
		flight.call("_process", 0.0)
		var commands: Dictionary = session.get("commands")
		var surfaces: Dictionary = session.call("surfaces")
		var state: PackedFloat64Array = sim.get("state")
		var pose: Dictionary = flight.call("_pose_of", state)
		var prop_angle: float = TAU * Commands.prop_rev_per_sec(commands) * simulation_time
		flight.call("_render_pose", pose, surfaces, prop_angle)
		flight.call("_update_hud")
		visual_state = flight.call("capture_evidence")
		route = "interactive-home-fly"
	elif screen == "help" or screen == "hint":
		app = _new_app(PackedStringArray(), "user://capture_ui_hint_settings.cfg")
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://capture_ui_hint_settings.cfg")) # first flight: the hint shows
		root.add_child(app)
		await process_frame
		await process_frame # Home drawn once before it is freed, as in the interactive route
		TranslationServer.set_locale(lang)
		if screen == "help":
			app.call("open_help", app.get("home").get("help_button"))
		else:
			app.call("start_flight")
			flight = app.get("flight")
			await create_timer(1.0).timeout
			route = "interactive-home-fly-first-flight-hint"
		if screen == "help":
			route = "interactive-home-help"
	elif screen == "pause":
		# The real app: Home, Fly, one second of flight, then the pause menu over the frozen flight.
		app = _new_app(PackedStringArray(), "user://capture_ui_settings.cfg") # never the player's own settings
		root.add_child(app)
		await process_frame
		await process_frame
		TranslationServer.set_locale(lang)
		app.call("start_flight")
		flight = app.get("flight")
		await create_timer(1.0).timeout
		app.call("open_pause")
		route = "interactive-home-fly-pause"
	else:
		if not "--no-scene" in args:
			home_field = HomeScene.new(aircraft)
			root.add_child(home_field)
		if not "--no-ui" in args:
			var home_ui: Control = Home.new()
			home_ui.set_aircraft(aircraft)
			root.add_child(home_ui)
		if screen != "home":
			push_error("Unknown UI capture screen '%s'" % screen)
			quit(1)
			return

	# Resolve the active scene after transitions: Home's field is detached during Fly, Help, Hint and Pause routes.
	if app != null and home_field == null:
		var app_field: Variant = app.get("home_scene")
		if app_field is Node3D:
			home_field = app_field as Node3D
	if screen != "flight" and flight != null and (screen == "pause" or screen == "hint"):
		var session: Node = flight.get("session")
		var sim: Node = session.get("sim")
		if screen == "hint":
			# Sample the latest live pose, then freeze it while the final capture frames draw.
			flight.call("_process", 0.0)
			session.set("input_enabled", false)
			flight.set_process(false)
			sim.process_mode = Node.PROCESS_MODE_DISABLED
		else:
			flight.set_process(false)
			sim.process_mode = Node.PROCESS_MODE_DISABLED
		visual_state = flight.call("capture_evidence")
		visual_state["route"] = "live-input-snapshot" # CLI-style physics-fixed would misstate this interactive state.

	await process_frame
	await process_frame # deferred initial focus, then a frame drawn with it
	await RenderingServer.frame_post_draw
	var viewport: Viewport = root.get_viewport()
	var camera_count: int = _count_nodes(viewport, "Camera3D")
	var environment_count: int = _count_nodes(viewport, "WorldEnvironment")
	var active_camera: Camera3D = viewport.get_camera_3d()
	if screen == "flight":
		var flight_camera: Camera3D = flight.get("_camera")
		if camera_count != 1 or environment_count != 1 or active_camera != flight_camera:
			push_error("After Home Fly expected one active flight camera and one WorldEnvironment under the viewport; got %d cameras, %d environments, active=%s" % [camera_count, environment_count, "none" if active_camera == null else str(active_camera.get_path())])
			quit(1)
			return
		if _count_named_nodes(viewport, "Home") != 0 or _count_named_nodes(viewport, "HomeScene") != 0:
			push_error("Home nodes remain under the viewport after Home Fly")
			quit(1)
			return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out).get_base_dir())
	var image: Image = viewport.get_texture().get_image()
	var image_error: Error = image.save_png(out)
	if image_error != OK:
		push_error("Could not save UI capture %s (error %d)" % [out, image_error])
		quit(1)
		return
	var evidence: Dictionary = {
		"state": screen,
		"route": route,
		"language": lang,
		"viewport": {
			"camera_3d_count": camera_count,
			"world_environment_count": environment_count,
			"active_camera": "" if active_camera == null else str(active_camera.get_path()),
		},
		"flight_snapshot_frozen": flight != null,
		"visual": visual_state,
	}
	if home_field != null:
		evidence["home_field"] = _home_field_evidence(home_field)
	var manifest: Dictionary = {
		"format": "openrc-ui-capture v2",
		"producer": "capture_ui",
		"image": out.get_file(),
		"sha256": FileAccess.get_sha256(out),
		"size": [image.get_width(), image.get_height()],
		"capture_scene": screen,
		"ui_evidence": evidence,
	}
	if not transition_timing.is_empty():
		manifest["transition_timing"] = transition_timing # diagnostic only; never drawn into the PNG
	var manifest_path: String = out.get_basename() + ".json"
	var manifest_file: FileAccess = FileAccess.open(manifest_path, FileAccess.WRITE)
	if manifest_file == null:
		push_error("Cannot write UI capture evidence: %s" % error_string(FileAccess.get_open_error()))
		quit(1)
		return
	manifest_file.store_string(JSON.stringify(manifest, "  ", true) + "\n")
	manifest_file.flush()
	var manifest_error: Error = manifest_file.get_error()
	manifest_file.close()
	print("saved %s (error 0) scene=%s camera3d=%d worldenvironment=%d%s" % [out, screen, camera_count, environment_count,
		" transition_usec=%d (diagnostic only; cache unknown)" % int(transition_timing.elapsed_usec) if not transition_timing.is_empty() else ""])
	for child in root.get_children():
		child.queue_free() # freeing render scenes before quit avoids false GL leak errors at process exit
	for frame_index in range(3):
		await process_frame # let the renderer release GPU resources after nodes leave the tree
	DirAccess.remove_absolute(ProjectSettings.globalize_path(FLIGHT_PREFERENCES_PATH))
	quit(1 if manifest_error != OK else 0)


func _new_app(user_args: PackedStringArray, preferences_path: String) -> Node:
	var app: Node = load("res://app_root.tscn").instantiate()
	app.set("user_args", user_args)
	app.set("preferences_path", preferences_path)
	return app


func _count_nodes(parent: Node, type_name: String) -> int:
	var count: int = 0
	for child in parent.get_children():
		if child.is_class(type_name):
			count += 1
		count += _count_nodes(child, type_name)
	return count


func _count_named_nodes(parent: Node, target_name: String) -> int:
	var count: int = 0
	for child in parent.get_children():
		if child.name == target_name:
			count += 1
		count += _count_named_nodes(child, target_name)
	return count


func _home_field_evidence(field: Node3D) -> Dictionary:
	var camera: Camera3D = field.get("camera")
	var aircraft: Dictionary = field.get("airplane")
	var airplane_root: Node3D = aircraft.get("root")
	var environment_nodes: Array[Node] = field.find_children("*", "WorldEnvironment", true, false)
	var environment: Environment = null
	if not environment_nodes.is_empty():
		environment = (environment_nodes[0] as WorldEnvironment).environment
	return {
		"camera_transform": VisualEvidence.transform(camera.global_transform),
		"pilot_eye_position": VisualEvidence.vector(camera.global_position),
		"camera_fov_deg": camera.fov,
		"airplane_transform": VisualEvidence.transform(airplane_root.global_transform),
		"exposure": environment.tonemap_exposure if environment != null else null,
		"tonemapper": int(environment.tonemap_mode) if environment != null else null,
		"shader_clock_s": ShaderClock.last_clock,
		"seed": {"kind": "not-used", "note": "Home uses fixed analytic clouds and no RNG"},
		"provenance": VisualEvidence.provenance(),
	}
