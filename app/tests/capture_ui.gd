# UI captures use the real Home and app_root routes where a screen transition matters.
# Needs a renderer (run under Xvfb, see capture.sh):
#   godot --path . --rendering-driver opengl3 --script res://tests/capture_ui.gd -- --out=/path/flight.png --lang=en --screen=flight
#   [--screen=home|pause|help|hint|weather] [--tab=wind|turbulence|atmosphere] [--size=1280x720]
#   [--weather-error] captures the localized invalid seed/temperature message on its selected tab.
#   [--weather-focus=period|seed|humidity] captures the last field after keyboard-follow scrolling.
#   [--weather=<id>] (alias: --weather-preset=<id>) supplies a real preset to Home, Weather or Flight routes.
#   [--aircraft=<catalog id>] [--start=airborne|runway]
# Software rendering proves layout and focus drawing, not GPU quality or legibility on the pilot's monitor.
extends SceneTree

const Home := preload("res://ui/home.gd")
const HomeScene := preload("res://ui/home_scene.gd")
const Preferences := preload("res://app_state/preferences.gd")
const Commands := preload("res://input/commands.gd")
const VisualEvidence := preload("res://render/visual_evidence.gd")
const ShaderClock := preload("res://render/shader_clock.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const WeatherSettings := preload("res://physics/wind_config.gd")
const TARGET_FLIGHT_TIME_S: float = 1.5
const FLIGHT_PREFERENCES_PATH: String = "user://capture_ui_flight_settings.cfg"
const WEATHER_PREFERENCES_PATH: String = "user://capture_ui_weather_settings.cfg"


func _initialize() -> void:
	_run()


func _run() -> void:
	var out: String = "user://home.png"
	var lang: String = "en"
	var screen: String = "home"
	var aircraft: String = "jensen-das-ugly-stik-60"
	var start_choice: String = "airborne"
	var weather_tab: String = "wind"
	var weather_focus: String = "default"
	var weather_preset: String = ""
	var requested_size: Vector2i = Vector2i.ZERO
	var show_weather_error: bool = false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--aircraft="):
			aircraft = arg.trim_prefix("--aircraft=")
		elif arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
		elif arg.begins_with("--lang="):
			lang = arg.trim_prefix("--lang=")
		elif arg.begins_with("--screen="):
			screen = arg.trim_prefix("--screen=")
		elif arg.begins_with("--start="):
			start_choice = arg.trim_prefix("--start=")
		elif arg.begins_with("--tab="):
			weather_tab = arg.trim_prefix("--tab=")
		elif arg.begins_with("--weather-focus="):
			weather_focus = arg.trim_prefix("--weather-focus=")
		elif arg.begins_with("--weather-preset="):
			weather_preset = arg.trim_prefix("--weather-preset=")
		elif arg.begins_with("--weather="):
			weather_preset = arg.trim_prefix("--weather=")
		elif arg.begins_with("--size="):
			var dimensions: PackedStringArray = arg.trim_prefix("--size=").split("x")
			if dimensions.size() == 2 and dimensions[0].is_valid_int() and dimensions[1].is_valid_int():
				requested_size = Vector2i(int(dimensions[0]), int(dimensions[1]))
			else:
				push_error("UI capture size must be WIDTHxHEIGHT")
				quit(ERR_INVALID_PARAMETER)
				return
		elif arg == "--weather-error":
			show_weather_error = true
	if requested_size.x > 0 and requested_size.y > 0:
		DisplayServer.window_set_size(requested_size)
		await process_frame
	if start_choice not in ["airborne", "runway"]:
		push_error("Unknown UI capture start choice '%s'" % start_choice)
		quit(ERR_INVALID_PARAMETER)
		return
	if start_choice == "runway" and aircraft != Catalog.DEFAULT_ID:
		push_error("Runway UI captures require the supported Ugly Stik")
		quit(ERR_INVALID_PARAMETER)
	if screen == "weather" and weather_tab not in ["wind", "turbulence", "atmosphere"]:
		push_error("Weather capture tab must be wind, turbulence or atmosphere")
		quit(ERR_INVALID_PARAMETER)
		return
	if weather_focus not in ["default", "period", "seed", "humidity"] \
		or (weather_focus == "period" and weather_tab != "wind") \
		or (weather_focus == "seed" and weather_tab != "turbulence") \
		or (weather_focus == "humidity" and weather_tab != "atmosphere"):
		push_error("Weather focus must be period on Wind, seed on Turbulence, or humidity on Atmosphere")
		quit(ERR_INVALID_PARAMETER)
		return
	if screen == "weather" and show_weather_error and weather_tab not in ["turbulence", "atmosphere"]:
		push_error("Weather validation error capture requires Turbulence or Atmosphere")
		quit(ERR_INVALID_PARAMETER)
		return
	TranslationServer.set_locale(lang) # never the OS locale: captures must not depend on the machine
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var app: Node = null
	var home_field: Node3D = null
	var flight: Node = null
	var transition_timing: Dictionary = {}
	var visual_state: Dictionary = {}
	var selector_evidence: Dictionary = {}
	var home_control: Control = null
	var route: String = "standalone-home"

	if screen == "flight":
		# The capture still follows the interactive route: no CLI args reach app_root, and the real Home Fly button
		# emits its normal signal. A private settings file fixes language and suppresses only the first-flight hint.
		var prefs: Dictionary = Preferences.DEFAULTS.duplicate()
		prefs.language = lang
		prefs.first_flight_hint_seen = true
		prefs.aircraft = aircraft
		prefs.start_choice = start_choice
		if weather_preset != "":
			var flight_weather: Dictionary = WeatherSettings.preset(weather_preset)
			if flight_weather.is_empty():
				push_error("Unknown UI capture weather preset '%s'" % weather_preset)
				quit(ERR_INVALID_PARAMETER)
				return
			prefs.weather_config = flight_weather
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
		home_control = home as Control
		selector_evidence = _check_start_selector(home_control, start_choice, lang)
		if selector_evidence.is_empty():
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
		var session_choice: String = str(flight.get("start_choice"))
		if session_choice != start_choice or not str(flight.get("startup_error")).is_empty():
			push_error("Flight capture start rejected or changed: requested=%s actual=%s error=%s" % [start_choice, session_choice, str(flight.get("startup_error"))])
			quit(1)
			return
		var session: Node = flight.get("session")
		if str(session.get("start_choice")) != start_choice or not str(session.get("start_error")).is_empty():
			push_error("Flight session start rejected or changed: requested=%s actual=%s error=%s" % [start_choice, str(session.get("start_choice")), str(session.get("start_error"))])
			quit(1)
			return
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
	elif screen == "weather":
		var prefs: Dictionary = Preferences.DEFAULTS.duplicate(true)
		prefs.language = lang
		prefs.first_flight_hint_seen = true
		prefs.weather_config = WeatherSettings.preset(weather_preset) if weather_preset != "" else WeatherSettings.preset("turbulent")
		if prefs.weather_config.is_empty():
			push_error("Unknown UI capture weather preset '%s'" % weather_preset)
			quit(ERR_INVALID_PARAMETER)
			return
		var prefs_error: Error = Preferences.save_to(WEATHER_PREFERENCES_PATH, prefs)
		if prefs_error != OK:
			push_error("Cannot write deterministic weather capture preferences: %s" % error_string(prefs_error))
			quit(1)
			return
		app = _new_app(PackedStringArray(), WEATHER_PREFERENCES_PATH)
		root.add_child(app)
		await process_frame
		await process_frame
		home_control = app.get("home") as Control
		if home_control == null:
			push_error("Weather capture did not start at Home")
			quit(1)
			return
		var weather_button: Control = home_control.get("weather_button") as Control
		app.call("open_weather", weather_button)
		await process_frame
		await process_frame
		var dialog: Node = app.get("weather_dialog") as Node
		if dialog == null:
			push_error("Home did not open the weather dialog")
			quit(1)
			return
		var tabs: TabBar = dialog.get("tab_container") as TabBar
		tabs.current_tab = {"wind": 0, "turbulence": 1, "atmosphere": 2}[weather_tab]
		await process_frame # lay out the selected tab before testing its focus-driven scroll
		var focus_control: Control
		if weather_tab == "turbulence":
			if weather_focus == "seed":
				var turbulence_inputs: Dictionary = dialog.get("turbulence_inputs")
				focus_control = turbulence_inputs["seed"] as Control
			else:
				focus_control = dialog.get("turbulence_enabled") as Control
		elif weather_tab == "atmosphere":
			if weather_focus == "humidity":
				var atmosphere_inputs: Dictionary = dialog.get("atmosphere_inputs")
				focus_control = atmosphere_inputs["relative_humidity_pct"] as Control
			else:
				focus_control = dialog.get("atmosphere_mode_picker") as Control
		else:
			if weather_focus == "period":
				var field_inputs: Dictionary = dialog.get("field_inputs")
				focus_control = field_inputs["gust_period_s"] as Control
			else:
				focus_control = dialog.get("preset_picker") as Control
		if show_weather_error:
			if weather_tab == "turbulence":
				var turbulence_inputs: Dictionary = dialog.get("turbulence_inputs")
				var seed_edit: LineEdit = turbulence_inputs["seed"]
				seed_edit.text = "-"
			else:
				var atmosphere_inputs: Dictionary = dialog.get("atmosphere_inputs")
				var temperature_edit: LineEdit = atmosphere_inputs["temperature_c"]
				temperature_edit.text = "46"
				dialog.call("_on_atmosphere_field_changed", "46", "temperature_c")
			dialog.call("_on_apply")
			await process_frame # let the error row reduce the body before asking scroll-follow to expose the focused field
		focus_control.grab_focus()
		route = "interactive-home-weather"
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
			home_ui.set_start_choice(start_choice)
			var weather_config: Dictionary = WeatherSettings.defaults()
			if weather_preset != "":
				weather_config = WeatherSettings.preset(weather_preset)
				if weather_config.is_empty():
					push_error("Unknown UI capture weather preset '%s'" % weather_preset)
					quit(ERR_INVALID_PARAMETER)
					return
			home_ui.set_weather_config(weather_config)
			home_control = home_ui
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
	if screen == "home" and home_control != null:
		selector_evidence = _check_start_selector(home_control, start_choice, lang)
		if selector_evidence.is_empty():
			quit(1)
			return
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
		"selected_start_choice": start_choice,
		"start_selector": selector_evidence,
		"visual": visual_state,
	}
	if screen == "weather":
		var weather_dialog: Node = app.get("weather_dialog") as Node
		var weather_tabs: TabBar = weather_dialog.get("tab_container") as TabBar
		var focus_owner: Control = viewport.gui_get_focus_owner()
		var panel_nodes: Array[Node] = weather_dialog.find_children("WeatherPanel", "PanelContainer", true, false)
		var weather_panel: Control = panel_nodes[0] as Control
		var panel_rect: Rect2 = weather_panel.get_global_rect()
		var view_size: Vector2 = viewport.get_visible_rect().size
		var dialog_scroll: ScrollContainer = weather_dialog.get("tab_scroll") as ScrollContainer
		var turbulence_inputs: Dictionary = weather_dialog.get("turbulence_inputs")
		var seed_rect: Rect2 = (turbulence_inputs["seed"] as Control).get_global_rect()
		var scroll_rect: Rect2 = dialog_scroll.get_global_rect()
		var focused_rect: Rect2 = focus_owner.get_global_rect() if focus_owner is Control else Rect2()
		var app_preferences: Dictionary = app.get("preferences")
		var weather_config: Dictionary = app_preferences.get("weather_config", {})
		var focus_visible_in_scroll: bool = focus_owner is Control and scroll_rect.encloses(focused_rect)
		var atmosphere_evidence: Dictionary = {}
		if weather_tab == "atmosphere":
			var atmosphere_inputs: Dictionary = weather_dialog.get("atmosphere_inputs")
			var temperature_edit: LineEdit = atmosphere_inputs["temperature_c"]
			var humidity_edit: LineEdit = atmosphere_inputs["relative_humidity_pct"]
			var error_label: Label = weather_dialog.get("error_label") as Label
			atmosphere_evidence = {
				"mode": "custom" if (weather_dialog.get("atmosphere_mode_picker") as OptionButton).selected == 1 else "reference",
				"preview": str((weather_dialog.get("atmosphere_preview") as Label).text),
				"temperature_text": temperature_edit.text,
				"temperature_editable": temperature_edit.editable,
				"invalid_temperature_error_visible": show_weather_error and error_label.visible and temperature_edit.text == "46",
				"error_text": error_label.text if error_label.visible else "",
				"humidity_focus_name": humidity_edit.name,
				"humidity_rect": [humidity_edit.get_global_rect().position.x, humidity_edit.get_global_rect().position.y,
					humidity_edit.get_global_rect().size.x, humidity_edit.get_global_rect().size.y],
			}
		evidence["weather"] = {
			"tab": weather_tab,
			"tab_title": weather_tabs.get_tab_title(weather_tabs.current_tab),
			"focus_name": "" if focus_owner == null else str(focus_owner.name),
			"focus_path": "" if focus_owner == null else str(focus_owner.get_path()),
			"panel_rect": [panel_rect.position.x, panel_rect.position.y, panel_rect.size.x, panel_rect.size.y],
			"scroll_rect": [scroll_rect.position.x, scroll_rect.position.y, scroll_rect.size.x, scroll_rect.size.y],
			"scroll_vertical": dialog_scroll.scroll_vertical,
			"seed_visible_in_scroll": weather_tab == "turbulence" and scroll_rect.encloses(seed_rect),
			"focused_control_rect": [focused_rect.position.x, focused_rect.position.y, focused_rect.size.x, focused_rect.size.y],
			"focused_control_visible_in_scroll": focus_visible_in_scroll,
			"fits_viewport": panel_rect.position.x >= 0.0 and panel_rect.position.y >= 0.0
				and panel_rect.end.x <= view_size.x and panel_rect.end.y <= view_size.y,
			"viewport_size": [view_size.x, view_size.y],
			"format": str(weather_config.get("format", "")),
			"atmosphere": atmosphere_evidence,
		}
	if screen == "home" and home_control != null:
		var home_focus: Control = viewport.gui_get_focus_owner()
		var weather_button: Control = home_control.get("weather_button") as Control
		evidence["home_ui"] = {
			"focus_name": "" if home_focus == null else str(home_focus.name),
			"focus_path": "" if home_focus == null else str(home_focus.get_path()),
			"weather_summary": "" if weather_button == null else weather_button.text,
			"weather_tooltip": "" if weather_button == null else weather_button.tooltip_text,
		}
	if screen == "flight" and flight != null:
		var session: Node = flight.get("session")
		var active_atmosphere: Dictionary = session.call("atmosphere_configuration")
		var hud: Label = flight.get("_hud") as Label
		evidence["flight_ui"] = {
			"weather_format": str(session.call("weather_configuration").get("format", "")),
			"atmosphere_mode": "reference" if session.call("atmosphere_is_reference") else "custom",
			"air_density_kgm3": session.call("air_density"),
			"density_altitude_m": active_atmosphere.get("density_altitude_m"),
			"trim_tas_mps": (session.get("start") as Dictionary).get("V"),
			"hud_text": "" if hud == null else hud.text,
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
	print("saved %s (error 0) scene=%s start=%s camera3d=%d worldenvironment=%d%s" % [out, screen, start_choice, camera_count, environment_count,
		" transition_usec=%d (diagnostic only; cache unknown)" % int(transition_timing.elapsed_usec) if not transition_timing.is_empty() else ""])
	for child in root.get_children():
		child.queue_free() # freeing render scenes before quit avoids false GL leak errors at process exit
	for frame_index in range(3):
		await process_frame # let the renderer release GPU resources after nodes leave the tree
	DirAccess.remove_absolute(ProjectSettings.globalize_path(FLIGHT_PREFERENCES_PATH))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(WEATHER_PREFERENCES_PATH))
	quit(1 if manifest_error != OK else 0)


func _new_app(user_args: PackedStringArray, preferences_path: String) -> Node:
	var app: Node = load("res://app_root.tscn").instantiate()
	app.set("user_args", user_args)
	app.set("preferences_path", preferences_path)
	return app


## Verifies that the translated selector is visible inside the Home sidebar and does not overlap Fly.
func _check_start_selector(home: Control, choice: String, lang: String) -> Dictionary:
	var button: Button = home.get("start_button") as Button
	var fly: Button = home.get("fly_button") as Button
	if button == null or fly == null:
		push_error("Home capture has no start selector or Fly button")
		return {}
	var rect: Rect2 = button.get_global_rect()
	var fly_rect: Rect2 = fly.get_global_rect()
	var sidebar: Control = home.get_node("Sidebar") as Control
	var sidebar_rect: Rect2 = sidebar.get_global_rect()
	var viewport_size: Vector2 = root.get_viewport().get_visible_rect().size
	var shown_text: String = button.atr(button.text)
	var expected: String = "Start: runway (experimental)" if choice == "runway" else "Start: in the air"
	if lang == "es":
		expected = "Inicio: pista (experimental)" if choice == "runway" else "Inicio: en el aire"
	var fits: bool = rect.has_area() and sidebar_rect.encloses(rect) and not rect.intersects(fly_rect) \
		and rect.position.x >= 0.0 and rect.position.y >= 0.0 and rect.end.x <= viewport_size.x and rect.end.y <= viewport_size.y
	if not button.is_visible_in_tree() or shown_text != expected or not fits:
		push_error("Home start selector layout/translation failed: language=%s text='%s' expected='%s' rect=%s sidebar=%s viewport=%s" % [lang, shown_text, expected, rect, sidebar_rect, viewport_size])
		return {}
	return {
		"choice": choice,
		"label": shown_text,
		"rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y],
		"sidebar_rect": [sidebar_rect.position.x, sidebar_rect.position.y, sidebar_rect.size.x, sidebar_rect.size.y],
		"fits_viewport": fits,
		"does_not_overlap_fly": not rect.intersects(fly_rect),
	}


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
