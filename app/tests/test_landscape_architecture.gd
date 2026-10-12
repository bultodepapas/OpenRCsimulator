extends SceneTree

const Prefabs = preload("res://scenery/prefabs.gd")
const MeshKit = preload("res://scenery/mesh_kit.gd")

const BASELINE_TRIANGLES := {"pavilion": 816, "pit_shelter": 1830}
const BASELINE_MIN := {
	"pavilion": Vector3(-5.0, 0.0, -6.2),
	"pit_shelter": Vector3(-14.3175, 0.0, -2.901742),
}
const BASELINE_MAX := {
	"pavilion": Vector3(5.0, 4.65, 3.5),
	"pit_shelter": Vector3(14.5317, 3.477413, 3.01),
}
const TRIANGLE_BUDGET := 3000 # One pavilion plus the two default shelter placements.

var _failures := 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _initialize() -> void:
	var builds := {}
	for id: String in ["pavilion", "pit_shelter"]:
		var kit := MeshKit.new()
		var moving: Array = Prefabs.build(id, kit, 1234, "temperate")
		var repeat_kit := MeshKit.new()
		var repeat_moving: Array = Prefabs.build(id, repeat_kit, 1234, "temperate")
		var bounds := _bounds(kit)
		var expected_min: Vector3 = BASELINE_MIN[id]
		var expected_max: Vector3 = BASELINE_MAX[id]
		var inside_baseline := true
		for axis in 3:
			inside_baseline = inside_baseline and bounds.position[axis] >= expected_min[axis] - 0.002
			inside_baseline = inside_baseline and bounds.end[axis] <= expected_max[axis] + 0.002
		_check("%s stays within its recorded, offset-aware LU-11 mesh bounds" % id, inside_baseline,
			"min=%s max=%s" % [bounds.position, bounds.end])
		_check("%s remains deterministic for the same seed" % id,
			kit.verts == repeat_kit.verts and kit.norms == repeat_kit.norms and kit.cols == repeat_kit.cols)
		_check("%s adds no moving parts" % id, moving.is_empty() and repeat_moving.is_empty())
		var mesh := kit.to_mesh(StandardMaterial3D.new())
		_check("%s still emits one batched surface" % id, mesh.get_surface_count() == 1)
		builds[id] = {"triangles": kit.triangle_count(), "bounds": bounds}
		print("     %s: %d triangles; min=%s max=%s" % [id, kit.triangle_count(), bounds.position, bounds.end])

	var pavilion_delta: int = int(builds.pavilion.triangles) - BASELINE_TRIANGLES.pavilion
	var shelter_delta: int = int(builds.pit_shelter.triangles) - BASELINE_TRIANGLES.pit_shelter
	var default_layout_delta := pavilion_delta + 2 * shelter_delta
	_check("architecture stays under the 3k default-layout triangle budget",
		default_layout_delta > 0 and default_layout_delta <= TRIANGLE_BUDGET,
		"pavilion +%d, each shelter +%d, default total +%d" % [pavilion_delta, shelter_delta, default_layout_delta])
	print("     added triangles: pavilion +%d, shelter +%d each, default total +%d" % [
		pavilion_delta, shelter_delta, default_layout_delta
	])
	print("all architecture checks passed" if _failures == 0 else "%d architecture checks failed" % _failures)
	quit(1 if _failures > 0 else 0)


func _bounds(kit: MeshKit) -> AABB:
	var bounds := AABB(kit.verts[0], Vector3.ZERO)
	for vertex: Vector3 in kit.verts:
		bounds = bounds.expand(vertex)
	return bounds
