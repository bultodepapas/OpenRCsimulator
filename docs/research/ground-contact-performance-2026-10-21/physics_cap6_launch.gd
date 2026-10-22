extends SceneTree

func _initialize() -> void:
	Engine.max_physics_steps_per_frame = 6
	call_deferred("_start")

func _start() -> void:
	var error: Error = change_scene_to_file("res://app_root.tscn")
	if error != OK:
		printerr("scene launch failed: ", error)
		quit(1)
