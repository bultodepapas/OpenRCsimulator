extends SceneTree
const World = preload("res://render/world/world.gd")
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var app = load("res://app_root.tscn").instantiate()
	app.user_args = PackedStringArray(["--quick-flight", "--start=airborne", "--battery=ideal", "--date=2026-09-26", "--time=18:00", "--time_scale=20"])
	root.add_child(app)
	await process_frame
	var environment_ref = weakref(app.flight._env)
	app.free()
	await process_frame
	print("environment retained after owner free: ", environment_ref.get_ref() != null)
	World._flow = {}
	await process_frame
	print("environment retained after clearing flow: ", environment_ref.get_ref() != null)
	quit()
