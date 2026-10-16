extends SceneTree

const Prefabs = preload("res://scenery/prefabs.gd")
const MeshKit = preload("res://scenery/mesh_kit.gd")
const Palette = preload("res://scenery/palette.gd")
const PitChair = preload("res://scenery/pit_chair.gd")

# Recorded full-prefab totals from the simple-prefab baseline before LU-11.
const LEGACY_BASELINE_TRIANGLES := {"pavilion": 816, "pit_shelter": 1830}
const BASELINE_MIN := {
	"pavilion": Vector3(-5.0, 0.0, -6.2),
	"pit_shelter": Vector3(-14.3175, 0.0, -2.901742),
}
const BASELINE_MAX := {
	"pavilion": Vector3(5.0, 4.65, 3.5),
	"pit_shelter": Vector3(14.5317, 3.477413, 3.01),
}
const SHELTER_SEED := 1234
const SHELTER_CHAIR_SLOTS := 5
const DEFAULT_SHELTER_CHAIR_COUNT := 4
const TRIANGLE_BUDGET := 3000 # Pavilion and two shelters' structural additions; shared furniture is held constant.

var _failures := 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _initialize() -> void:
	var legacy_chairs := _shelter_chairs(SHELTER_SEED, false)
	var current_chairs := _shelter_chairs(SHELTER_SEED, true)
	_check("reference and production shelter retain the same four chair placements",
		legacy_chairs.count == DEFAULT_SHELTER_CHAIR_COUNT
		and current_chairs.count == DEFAULT_SHELTER_CHAIR_COUNT,
		"legacy=%d, production=%d" % [legacy_chairs.count, current_chairs.count])
	var legacy_shelter_without_chairs: int = LEGACY_BASELINE_TRIANGLES.pit_shelter - legacy_chairs.triangles
	var structural_shelter_baseline: int = legacy_shelter_without_chairs + current_chairs.triangles
	print("     structural shelter reference: %d = %d legacy structure + %d current shared-chair triangles; removed %d legacy-chair triangles" % [
		structural_shelter_baseline, legacy_shelter_without_chairs, current_chairs.triangles, legacy_chairs.triangles
	])

	var builds := {}
	for id: String in ["pavilion", "pit_shelter"]:
		var kit := MeshKit.new()
		var moving: Array = Prefabs.build(id, kit, SHELTER_SEED, "temperate")
		var repeat_kit := MeshKit.new()
		var repeat_moving: Array = Prefabs.build(id, repeat_kit, SHELTER_SEED, "temperate")
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

	var pavilion_delta: int = int(builds.pavilion.triangles) - LEGACY_BASELINE_TRIANGLES.pavilion
	var shelter_delta: int = int(builds.pit_shelter.triangles) - structural_shelter_baseline
	var default_layout_delta := pavilion_delta + 2 * shelter_delta
	_check("structural additions stay under the 3k default-layout triangle budget",
		default_layout_delta > 0 and default_layout_delta <= TRIANGLE_BUDGET,
		"pavilion +%d, each shelter +%d, default total +%d" % [pavilion_delta, shelter_delta, default_layout_delta])
	print("     structural additions: pavilion +%d, shelter +%d each, default total +%d (budget %d)" % [
		pavilion_delta, shelter_delta, default_layout_delta, TRIANGLE_BUDGET
	])
	print("all architecture checks passed" if _failures == 0 else "%d architecture checks failed" % _failures)
	quit(1 if _failures > 0 else 0)


func _shelter_chairs(seed: int, shared_builder: bool) -> Dictionary:
	var count := 0
	var triangles := 0
	for i in SHELTER_CHAIR_SLOTS:
		if Palette.hash01(seed, i, 3) >= 0.75:
			continue
		var chair := MeshKit.new()
		if shared_builder:
			PitChair.build(chair, Vector3.ZERO, 0.0, seed + i)
		else:
			_legacy_simple_chair(chair)
		count += 1
		triangles += chair.triangle_count()
	return {"count": count, "triangles": triangles}


# Historical _folding_chair shape from the simple-prefab baseline; geometry only.
func _legacy_simple_chair(kit: MeshKit) -> void:
	var fabric := Color.WHITE
	kit.block(Vector3(0.5, 0.05, 0.45), Vector3(0, 0.42, 0), fabric)
	kit.quad(Vector3(-0.25, 0.45, 0.22), Vector3(0.25, 0.45, 0.22), Vector3(0.25, 0.92, 0.3), Vector3(-0.25, 0.92, 0.3), fabric)
	kit.quad(Vector3(0.25, 0.45, 0.23), Vector3(-0.25, 0.45, 0.23), Vector3(-0.25, 0.92, 0.31), Vector3(0.25, 0.92, 0.31), fabric)
	for sx: float in [-0.24, 0.24]:
		kit.beam(Vector3(sx, 0, -0.2), Vector3(sx, 0.45, 0.2), 0.025, Color.DIM_GRAY)
		kit.beam(Vector3(sx, 0, 0.2), Vector3(sx, 0.45, -0.2), 0.025, Color.DIM_GRAY)


func _bounds(kit: MeshKit) -> AABB:
	var bounds := AABB(kit.verts[0], Vector3.ZERO)
	for vertex: Vector3 in kit.verts:
		bounds = bounds.expand(vertex)
	return bounds
