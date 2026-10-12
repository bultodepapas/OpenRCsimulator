## LU-08: guard conservative proxy bounds, deterministic geometry and wind-part budget.
extends SceneTree
const Vegetation := preload("res://scenery/vegetation.gd")
const MeshKit := preload("res://scenery/mesh_kit.gd")
const STATIC_TRIANGLE_BUDGET := 1500
var failures := 0
func _initialize() -> void:
	var max_triangles := 0
	var max_size := Vector3.ZERO
	var signatures := {}
	for theme: String in ["temperate", "summer", "autumn"]:
		for seed in range(64):
			var kit := MeshKit.new()
			var moving := Vegetation.shade_tree(kit, seed * 173 + 41, theme)
			var repeat := MeshKit.new()
			Vegetation.shade_tree(repeat, seed * 173 + 41, theme)
			if kit.verts != repeat.verts or kit.cols != repeat.cols:
				failures += 1
			var bounds := AABB(Vector3.ZERO, Vector3.ZERO)
			for v: Vector3 in kit.verts:
				if not v.is_finite(): failures += 1
				bounds = bounds.expand(v)
			if moving.size() != 1 or moving[0].motion_mode != 3: failures += 1
			for v: Vector3 in moving[0].kit.verts:
				bounds = bounds.expand(v + moving[0].pivot + Vector3(0.06, 0.003, 0.06))
				bounds = bounds.expand(v + moving[0].pivot - Vector3(0.06, 0.003, 0.06))
			if bounds.position.y < -0.001 or bounds.end.y > 10.5 or maxf(absf(bounds.position.x), absf(bounds.end.x)) > 4.0 or maxf(absf(bounds.position.z), absf(bounds.end.z)) > 4.0:
				printerr("outside proxy envelope seed=", seed, " bounds=", bounds)
				failures += 1
			max_size = max_size.max(bounds.size)
			max_triangles = maxi(max_triangles, kit.triangle_count())
			signatures[hash(kit.verts)] = true
	# The current branch/lobe form measures up to 1,463 triangles in this sample; keep an explicit 37-triangle margin.
	if max_triangles > STATIC_TRIANGLE_BUDGET or signatures.size() < 60: failures += 1
	print("LU08 trees: 192 seeded/theme builds, deterministic replay, finite bounds incl. 6cm wind; max static triangles=", max_triangles, "/", STATIC_TRIANGLE_BUDGET, " size=", max_size, " unique shapes=", signatures.size(), " failures=", failures)
	quit(1 if failures else 0)
