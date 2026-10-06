# UI capture (MENU-PLAN UI-01a): renders the Home screen and saves a PNG, for layout and focus review.
# Needs a renderer (run under Xvfb, see capture.sh):
#   godot --path . --rendering-driver opengl3 --script res://tests/capture_ui.gd -- --out=/path/home.png [--lang=es] [--no-ui] [--no-scene] [--screen=pause|help|hint]
#     [--aircraft=<catalog id>] (Home only: the airplane on the card and in the backdrop)
# Software rendering proves layout and focus drawing, not GPU quality or legibility on the pilot's monitor.
extends SceneTree

const Home := preload("res://ui/home.gd")
const HomeScene := preload("res://ui/home_scene.gd")


func _initialize() -> void:
	_run()


func _run() -> void:
	var out := "user://home.png"
	var lang := "en"
	var aircraft := "jensen-das-ugly-stik-60"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--aircraft="):
			aircraft = a.trim_prefix("--aircraft=")
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
		elif a.begins_with("--lang="):
			lang = a.trim_prefix("--lang=")
	TranslationServer.set_locale(lang) # never the OS locale: captures must not depend on the machine
	var args := OS.get_cmdline_user_args()
	if "--screen=help" in args or "--screen=hint" in args:
		var app: Node = load("res://app_root.tscn").instantiate()
		app.user_args = PackedStringArray()
		app.preferences_path = "user://capture_ui_hint_settings.cfg"
		DirAccess.remove_absolute(ProjectSettings.globalize_path(app.preferences_path)) # first flight: the hint shows
		root.add_child(app)
		await process_frame
		await process_frame # Home drawn once before anything else (see below)
		TranslationServer.set_locale(lang)
		if "--screen=help" in args:
			app.open_help(app.home.help_button)
		else:
			app.start_flight()
			await create_timer(1.0).timeout
	elif "--screen=pause" in args:
		# The real app: Home, Fly, one second of flight, then the pause menu over the frozen flight.
		var app: Node = load("res://app_root.tscn").instantiate()
		app.user_args = PackedStringArray()
		app.preferences_path = "user://capture_ui_settings.cfg" # never the player's own settings
		root.add_child(app)
		# Home must be drawn once before Fly (as with a person): freeing the Home scene before its first draw
		# reports two 256x256 GL textures as leaked at exit (observed 2026-10-06, Compatibility, llvmpipe).
		await process_frame
		await process_frame
		TranslationServer.set_locale(lang)
		app.start_flight()
		await create_timer(1.0).timeout
		app.open_pause()
	else:
		if not "--no-scene" in OS.get_cmdline_user_args():
			root.add_child(HomeScene.new(aircraft))
		if not "--no-ui" in OS.get_cmdline_user_args():
			var home: Control = Home.new()
			home.set_aircraft(aircraft)
			root.add_child(home)
	await process_frame
	await process_frame # deferred initial focus, then a frame drawn with it
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out).get_base_dir())
	var err := root.get_texture().get_image().save_png(out)
	print("saved %s (error %d)" % [out, err])
	for n in root.get_children():
		n.queue_free() # free scenes before quitting: a live render at exit reports leaked GL textures as errors
	for i in 3:
		await process_frame # the renderer releases GPU resources a frame after the nodes go
	quit(err)
