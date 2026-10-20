extends SceneTree
const Observer = preload("observer.gd")

func _initialize() -> void:
	var recorder := Observer.new()
	root.add_child.call_deferred(recorder)
