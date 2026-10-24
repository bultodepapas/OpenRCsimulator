extends SceneTree

const World := preload("res://render/world/world.gd")
const Atmosphere := preload("res://render/atmosphere.gd")

var _checks := 0
var _failures := 0
var _checkpoint_stages: Array[String] = []
var _cancel_stages: Array[String] = []


func _check(label: String, condition: bool, detail := "") -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var baseline: Dictionary = World.presentation_context()
	var field := {id = "staged-world-test", runway = "", surfaces = []}
	var conditions := {time_of_day = false}
	var night_options := {field_lighting = "off", field_activation = "auto", campfire = false}
	var sync_parent := Node3D.new()
	sync_parent.name = "SyncWorld"
	root.add_child(sync_parent)
	var sync_result: Dictionary = World.build(sync_parent, field,
		Callable(self, "_build_probe_field").bind(sync_parent), conditions, {}, night_options)
	var async_parent := Node3D.new()
	async_parent.name = "StagedWorld"
	root.add_child(async_parent)
	var staged_result: Dictionary = await World.build_staged(async_parent, field,
		Callable(self, "_build_probe_field_async").bind(async_parent), conditions, {}, night_options,
		Callable(self, "_yielding_checkpoint"))

	_check("staged build completes", not bool(staged_result.get("cancelled", true)))
	_check("sync and staged builds attach the same ordered children",
		_child_names(sync_parent) == _child_names(async_parent), "%s != %s" % [_child_names(sync_parent), _child_names(async_parent)])
	_check("custom field attaches to the candidate parent",
		async_parent.get_node_or_null("Field") != null and async_result_has_field_reference(staged_result))
	_check("staged checkpoints preserve the declared phase order",
		_checkpoint_stages == ["Preparing world", "Building landscape", "Preparing sky", "Preparing field lighting", "Finalizing world"],
		str(_checkpoint_stages))
	_check("async field callback can report synchronous builder time",
		is_equal_approx(float(staged_result.field_build_ms), 0.25), str(staged_result.field_build_ms))
	_check("staged result reports field wall time and phase spans",
		is_finite(float(staged_result.field_work_ms)) and float(staged_result.field_work_ms) >= 0.0
			and staged_result.construction_spans.has("field") and staged_result.construction_spans.has("finalize"))
	_check("sync API still returns immediately with existing result fields",
		sync_result.has("environment") and sync_result.has("world_environment") and sync_result.has("sun")
			and sync_result.has("conditions") and sync_result.has("sky") and sync_result.has("field_build_ms"))
	_check("successful sync and staged builds leave equivalent presentation globals",
		World._flow.is_empty() and Atmosphere.state.is_empty()
			and World._night_owner.get_ref() == async_parent
			and str(World._night_options) == str(night_options))

	var cancelled_parent := Node3D.new()
	cancelled_parent.name = "CancelledWorld"
	root.add_child(cancelled_parent)
	var cancelled_result: Dictionary = await World.build_staged(cancelled_parent, field,
		Callable(self, "_build_probe_field").bind(cancelled_parent), conditions, {}, night_options,
		Callable(self, "_cancel_at_landscape"))
	_check("checkpoint refusal returns a cancelled result",
		bool(cancelled_result.get("cancelled", false)) and cancelled_result.get("cancelled_at", "") == "Building landscape")
	_check("cancelled partial nodes remain owned by the candidate parent",
		cancelled_parent.get_child_count() > 0 and cancelled_parent.get_node_or_null("Field") == null)
	_check("cancellation stops before later phases", _cancel_stages == ["Preparing world", "Building landscape"], str(_cancel_stages))

	for candidate: Node in [sync_parent, async_parent, cancelled_parent]:
		if is_instance_valid(candidate):
			candidate.free()
	World.restore_presentation_context(baseline)
	print("world staged build checks=%d failures=%d" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _build_probe_field(parent: Node) -> void:
	var field_node := Node3D.new()
	field_node.name = "Field"
	var marker := Node3D.new()
	marker.name = "Probe"
	field_node.add_child(marker)
	parent.add_child(field_node)


func _build_probe_field_async(parent: Node) -> Dictionary:
	_build_probe_field(parent)
	await process_frame
	return {field_build_ms = 0.25}


func _yielding_checkpoint(stage: String) -> bool:
	_checkpoint_stages.append(stage)
	await process_frame
	return true


func _cancel_at_landscape(stage: String) -> bool:
	_cancel_stages.append(stage)
	return stage != "Building landscape"


func _child_names(parent: Node) -> Array[String]:
	var names: Array[String] = []
	for child: Node in parent.get_children():
		var child_name := str(child.name)
		names.append(child.get_class() if child_name.begins_with("@") else "%s:%s" % [child.get_class(), child_name])
	return names


func async_result_has_field_reference(result: Dictionary) -> bool:
	var reference: Variant = result.environment.get_meta("fw_wind_field", null)
	return reference is WeakRef and reference.get_ref() != null
