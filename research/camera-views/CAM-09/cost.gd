# CAM-09 probe: camera clearance query cost beside the church, over the pilot area and in open air (three rounds
# of 4000 queries). Run from the repository root:
#   godot --headless --path app --audio-driver Dummy --script "$PWD/research/camera-views/CAM-09/cost.gd"
extends SceneTree
const FieldLoader := preload("res://data/field_loader.gd")
const Landscapes := preload("res://landscapes/catalog.gd")
const CameraCollision := preload("res://render/camera/camera_collision.gd")
func _initialize() -> void:
	var loaded: Dictionary = FieldLoader.load_from(FieldLoader.DEFAULT_PATH)
	var world: Dictionary = Landscapes.collision_world(Landscapes.DEFAULT_ID, loaded.field).world
	var church: Dictionary = {}
	for p: Dictionary in world.proxies:
		if str(p.get("part", "")) == "church":
			church = p
	var building := Vector3(float(church.east), -float(church.down), -float(church.north))
	var n := 4000
	for round_index in 3:
		var row := []
		for centre: Vector3 in [building, Vector3(0, 0, -40), Vector3(0, 400, 0)]:
			var started := Time.get_ticks_usec()
			for i in n:
				var from := centre + Vector3(sin(i * 0.1) * 20.0, 2.0, cos(i * 0.1) * 20.0)
				CameraCollision.free_fraction(world, from, from + Vector3(0, 1.8, 5.2))
			row.append("%.1f" % (float(Time.get_ticks_usec() - started) / n))
		print("COST church / pilot area / open air µs: ", row)
	quit(0)
