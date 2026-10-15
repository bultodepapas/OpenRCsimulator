# UI-20-R1: native rendered audit; run with the pinned Godot from the repository root.
# --path app --borderless --position 0,0 --script <absolute audit.gd> -- --out=<directory>
# Uses isolated preferences and existing production routes. Does not save drafts or change runtime code.
extends SceneTree

const Preferences = preload("res://app_state/preferences.gd")
const Driver = preload("res://tests/ui_driver.gd")
var output := ""
var app: Node
var records: Array = []
var flow: Array = []
var case_id := ""
var driver: RefCounted

func _initialize() -> void:
	_run.call_deferred()

func settle() -> void:
	for frame in range(8):
		await process_frame
	await create_timer(0.22).timeout
	await RenderingServer.frame_post_draw

func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): output = arg.trim_prefix("--out=")
	if output.is_empty():
		push_error("--out is required")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(output)
	driver = Driver.new(self)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	DisplayServer.window_set_position(Vector2i.ZERO)
	for dimensions in [Vector2i(1280,720), Vector2i(1920,1080), Vector2i(2560,1440), Vector2i(3840,2160)]:
		DisplayServer.window_set_size(dimensions)
		await settle()
		for language in ["en", "es"]:
			case_id = "%s-%d" % [language, dimensions.y]
			var prefs := Preferences.DEFAULTS.duplicate(true)
			prefs.language = language
			prefs.first_flight_hint_seen = true
			prefs.latency_marker = false
			var prefs_path: String = output.path_join("settings-" + case_id + ".cfg")
			if Preferences.save_to(prefs_path, prefs) != OK:
				quit(2)
				return
			app = load("res://app_root.tscn").instantiate()
			app.user_args = PackedStringArray()
			app.preferences_path = prefs_path
			app.random_seed_source = func(): return 20261015
			root.add_child(app)
			await settle()
			app.open_settings(app.home.settings_button)
			await capture("settings")
			if dimensions.y in [720, 2160]:
				app.screens.get_screen("settings")._scale_picker.select(4)
				app.screens.get_screen("settings")._scale_selected(4)
				await capture("settings-large")
				app.screens.get_screen("settings")._scroll.scroll_vertical = 99999
				await capture("settings-large-bottom")
				app.screens.get_screen("settings")._revert()

			root.remove_child(app)
			app.queue_free()
			await settle()
	var file := FileAccess.open(output.path_join("audit.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"captures":records,"flows":flow}, "  ") + "\n")
	file.close()
	print("AUDIT COMPLETE: %d captures, %d flow checks" % [records.size(), flow.size()])
	quit()

func capture(screen: String) -> void:
	await settle()
	var im := root.get_texture().get_image()
	var filename := "%s-%s.webp" % [case_id, screen]
	im.save_webp(output.path_join(filename), true)
	var controls: Array = []
	walk(app.screens.top(), controls)
	var focused := root.gui_get_focus_owner()
	records.append({"case":case_id, "screen":screen, "image":filename,
		"pixels":[im.get_width(),im.get_height()], "window_size":str(DisplayServer.window_get_size()),
		"screen_size":str(DisplayServer.screen_get_size()), "screen_dpi":DisplayServer.screen_get_dpi(),
		"screen_scale":DisplayServer.screen_get_scale(), "content_scale":root.content_scale_factor, "logical_size":str(root.get_visible_rect().size), "automatic_scale":preload("res://ui/ui_scale.gd").automatic_factor(DisplayServer.window_get_size()),
		"renderer":RenderingServer.get_current_rendering_method(), "gpu":RenderingServer.get_video_adapter_name(),
		"focus":"" if focused == null else str(focused.get_path()), "controls":controls})
	print("CAPTURE %s %dx%d" % [filename,im.get_width(),im.get_height()])
	var file := FileAccess.open(output.path_join("audit-progress.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"captures":records,"flows":flow}, "  ") + "\n")
	file.close()

func walk(node: Node, rows: Array) -> void:
	if node == null: return
	if node is Control and node.is_visible_in_tree():
		var rect: Rect2 = node.get_global_rect()
		if node is Label or node is BaseButton or node is PanelContainer or node is ScrollContainer:
			var row := {"path":str(node.get_path()), "type":node.get_class(), "rect":[rect.position.x,rect.position.y,rect.size.x,rect.size.y]}
			if node is Label or node is Button:
				row.text = node.tr(node.text)
				row.font_size = node.get_theme_font_size("font_size")
			if node is Button:
				row.disabled = node.disabled
				row.clip_text = node.clip_text
				row.wrap = node.autowrap_mode
				row.text_width = node.get_theme_font("font").get_string_size(row.text, HORIZONTAL_ALIGNMENT_LEFT, -1, row.font_size).x
				row.available_width = rect.size.x - node.get_theme_stylebox("normal").get_minimum_size().x
			rows.append(row)
	for child in node.get_children(): walk(child, rows)

