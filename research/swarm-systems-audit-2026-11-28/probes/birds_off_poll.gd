extends SceneTree

const FieldData = preload("res://data/field_loader.gd")
const SceneryBuilder = preload("res://scenery/scenery.gd")
const BirdPreference = preload("res://scenery/birds/bird_director.gd")
const BirdLayer = preload("res://scenery/birds.gd")
const SkyState = preload("res://render/atmosphere.gd")
const DayClock = preload("res://render/shader_clock.gd")

# The runtime already calls a replaceable script receiver. Forward the three calls
# to the real implementation, observing dispatch without changing any bird results.
class Counter:
	const StockBirds = preload("res://scenery/birds.gd")
	static var pending_calls := 0
	static var settled_scans := 0
	static var applications := 0
	static var settle_calls := 0

	static func pending(layer: Node) -> bool:
		pending_calls += 1
		var result := StockBirds.pending(layer)
		if not result:
			settled_scans += 1
		return result

	static func apply_lighting(layer: Node, lighting: Dictionary) -> void:
		applications += 1
		StockBirds.apply_lighting(layer, lighting)

	static func settle(layer: Node, clock: float, force: bool) -> bool:
		settle_calls += 1
		return StockBirds.settle(layer, clock, force)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var loaded: Dictionary = FieldData.load_from()
	if not loaded.ok:
		printerr("field fixture unavailable")
		quit(2)
		return
	var noon := {"sun_elevation_deg": 45.0, "sun_azimuth_deg": 180.0}
	SkyState.state = noon.duplicate()
	BirdPreference.set_preference("off")
	OS.set_environment("OPENRC_SCENERY_BIRDS", "on")
	var job := SceneryBuilder.begin_attach(loaded.field, noon)
	SceneryBuilder.advance_build(job)
	var layer: Node3D = job.birds_node
	if layer == null:
		printerr("stock field yielded no bird layer")
		quit(2)
		return
	var groups: Array = layer.get_meta("bird_groups")
	var state_slots := 0
	var instance_slots := 0
	var visible_instances := 0
	var meshes := 0
	var shaders := 0
	for group: MultiMeshInstance3D in groups:
		state_slots += (group.get_meta("states") as PackedFloat32Array).size()
		instance_slots += group.multimesh.instance_count
		visible_instances += group.multimesh.visible_instance_count
		if group.multimesh.mesh != null:
			meshes += 1
		if group.material_override is ShaderMaterial:
			shaders += 1
	layer.set("_birds", Counter)
	var result_changes := 0
	for i: int in 120:
		DayClock.update(10.0 + i * 0.02)
		if layer.call("poll"):
			result_changes += 1
	var stable_pending := Counter.pending_calls
	var stable_full := Counter.settled_scans
	var stable_settle := Counter.settle_calls
	var stable_applications := Counter.applications
	for n: int in 6:
		SkyState.state.sun_elevation_deg = 46.0 + n
		layer.call("poll")
	var flow_applications := Counter.applications - stable_applications
	var flow_drawn := BirdLayer.drawn_primitives(layer)
	BirdPreference.set_preference("many")
	layer.call("poll")
	DayClock.update(220.0)
	layer.call("poll")
	var enabled_drawn := BirdLayer.drawn_primitives(layer)
	SceneryBuilder.cancel_build(job)
	OS.set_environment("OPENRC_SCENERY_BIRDS", "off")
	var disabled_job := SceneryBuilder.begin_attach(loaded.field, noon)
	SceneryBuilder.advance_build(disabled_job)
	var disabled_has_node: bool = disabled_job.birds_node != null
	SceneryBuilder.cancel_build(disabled_job)
	print("AUDIT_BIRDS_OFF ", JSON.stringify({"groups": groups.size(), "meshes": meshes, "shader_materials": shaders,
		"state_slots": state_slots, "allocated_instances": instance_slots, "visible_off": visible_instances,
		"stable_polls": 120, "pending_calls": stable_pending, "full_pending_scans": stable_full,
		"state_visits_implied_by_loop": stable_full * state_slots, "settles": stable_settle,
		"stable_applications": stable_applications, "stable_changes": result_changes,
		"off_sun_changes": 6, "flow_reapplications": flow_applications, "flow_drawn_primitives": flow_drawn,
		"many_after_settle_drawn_primitives": enabled_drawn, "hard_off_has_node": disabled_has_node}))
	var ok := stable_pending == 120 and stable_full == 120 and stable_settle == 0 and stable_applications == 0 \
		and result_changes == 0 and visible_instances == 0 and instance_slots > 0 and state_slots == instance_slots \
		and flow_applications == 6 and flow_drawn == 0 and enabled_drawn > 0 and not disabled_has_node
	quit(0 if ok else 1)
