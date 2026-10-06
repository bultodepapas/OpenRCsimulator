# UI capture (MENU-PLAN UI-01a): renders the Home screen and saves a PNG, for layout and focus review.
# Needs a renderer (run under Xvfb, see capture.sh):
#   godot --path . --rendering-driver opengl3 --script res://tests/capture_ui.gd -- --out=/path/home.png [--lang=es] [--no-ui] [--no-scene]
# Software rendering proves layout and focus drawing, not GPU quality or legibility on the pilot's monitor.
extends SceneTree

const Home := preload("res://ui/home.gd")
const HomeScene := preload("res://ui/home_scene.gd")


func _initialize() -> void:
	_run()


func _run() -> void:
	var out := "user://home.png"
	var lang := "en"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
		elif a.begins_with("--lang="):
			lang = a.trim_prefix("--lang=")
	TranslationServer.set_locale(lang) # never the OS locale: captures must not depend on the machine
	if not "--no-scene" in OS.get_cmdline_user_args():
		root.add_child(HomeScene.new())
	if not "--no-ui" in OS.get_cmdline_user_args():
		root.add_child(Home.new())
	await process_frame
	await process_frame # deferred initial focus, then a frame drawn with it
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out).get_base_dir())
	var err := root.get_texture().get_image().save_png(out)
	print("saved %s (error %d)" % [out, err])
	quit(err)
