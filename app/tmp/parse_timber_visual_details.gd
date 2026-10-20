extends SceneTree

const TimberModel := preload("res://aircraft/timber_model.gd")
const TimberVisualDetails := preload("res://aircraft/timber_visual_details.gd")


func _initialize() -> void:
	var model := TimberModel.build()
	if model.is_empty():
		push_error("Timber model did not build")
		quit(1)
		return
	var root := model.root as Node3D
	get_root().add_child(root)
	var result := TimberVisualDetails.apply(root)
	print("Timber visual detail layer: ", result, " / children=", root.get_child_count())
	quit(0 if result else 1)
