extends SceneTree

const LakeCollision := preload("res://../drafts/lake_collision.gd")

func _initialize() -> void:
	print("lake collision draft loaded: ", LakeCollision)
	quit()
