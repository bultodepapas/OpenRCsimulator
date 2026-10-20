## LU-22-R2: aquatic assets stay on the validated shelf and render as bounded batches.
extends SceneTree

const Loader := preload("res://data/lake_loader.gd")
const Plants := preload("res://render/lake/lake_plants.gd")
const Surface := preload("res://physics/lake_surface.gd")

var failures := 0


func _initialize() -> void:
	var result := Loader.load_from()
	_check("normalized lake loads", bool(result.ok))
	if not result.ok:
		quit(1)
		return
	var lake: Dictionary = result.lake
	var first := Plants.layout(lake)
	var second := Plants.layout(lake)
	_check("deterministic, bounded colonies", first == second and first.pads.size() == 105
		and first.flowers.size() == 14 and first.reeds.size() == 21)
	for pad in first.pads:
		var sample := Surface.sample_terrain_validated(lake, float(pad.north), float(pad.east))
		_check("pad on 0.3–1.15 m shelf", str(sample.region) == "bed"
			and is_equal_approx(float(sample.bed_depth_m), float(pad.depth_m))
			and float(pad.depth_m) >= 0.30 and float(pad.depth_m) <= 1.15
			and float(pad.shore_m) > 1.15)
	for flower in first.flowers:
		_check("flower stays inside water", Surface.shore_distance_validated(lake,
			float(flower.north), float(flower.east)) > 0.75)
	for reed in first.reeds:
		var sample := Surface.sample_terrain_validated(lake, float(reed.north), float(reed.east))
		_check("emergent reed roots in shallow bed", str(sample.region) == "bed"
			and float(sample.bed_depth_m) <= 0.38 and float(reed.shore_m) > 0.45)
	var node := Plants.build(lake)
	var leaves := node.get_node_or_null("NymphaeaLeaves") as MultiMeshInstance3D
	var blossoms := node.get_node_or_null("WaterlilyBlossoms") as MultiMeshInstance3D
	var reeds := node.get_node_or_null("EmergentReeds") as Node3D
	_check("downloaded meshes are instanced in three aquatic layers", leaves != null
		and blossoms != null and reeds != null and reeds.get_child_count() > 0
		and leaves.multimesh.instance_count == first.pads.size()
		and blossoms.multimesh.instance_count == first.flowers.size())
	_check("no new collision geometry", node.find_children("*", "CollisionShape3D", true, false).is_empty())
	_check("vegetation costs remain bounded", first.pads.size() * 148
		+ first.flowers.size() * 128 + first.reeds.size() * 380 < 26000)
	node.free()
	print("Lake plant checks: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(1 if failures > 0 else 0)


func _check(label: String, passed: bool) -> void:
	if not passed:
		failures += 1
		printerr("FAIL: ", label)
