# TRA-09. Renders the production brand intro (logo assembly and atmosphere) as a PNG sequence for the end card.
# Run with --path app --script <this file> -- --out-dir=<absolute> [--frames=330]
# The intro's own caption and loading footer are hidden; the trailer adds its own typography.
extends SceneTree

const BrandIntro = preload("res://ui/brand_intro.gd")
const FPS := 60

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var output := ""
	var frames := 330
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out-dir="):
			output = arg.trim_prefix("--out-dir=")
		elif arg.begins_with("--frames="):
			frames = int(arg.trim_prefix("--frames="))
	if output.is_empty() or frames <= 0:
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1920, 1080)
	var intro: Control = BrandIntro.new()
	root.add_child(intro)
	intro.size = Vector2(1920, 1080)
	intro.self_modulate = Color(1, 1, 1, 0) # caption/footer are the control's own drawing; children keep the logo
	for f: int in range(frames):
		intro.seek(float(f) / FPS)
		await process_frame
		await RenderingServer.frame_post_draw
		if root.get_texture().get_image().save_png(output.path_join("%05d.png" % f)) != OK:
			quit(1)
			return
	print("BRAND_OK ", frames)
	quit()
