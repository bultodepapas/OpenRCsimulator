## RCV-39 paired equivalence and CPU benchmark for Monster Car 2 render effects.
## Run from the app project with --script pointing to this file and --output=<fresh-dir>.
extends SceneTree

const Model := preload("res://vehicles/ground/monster_car_2_model.gd")
const CORNERS := ["FL", "FR", "RL", "RR"]
const EXPECTED_SHELL_MESHES := 66
const EXPECTED_OVERLAYS := 70
const EXPECTED_CANDIDATE_MATERIALS := 5
const BENCH_WARMUP := 100
const BENCH_ITERATIONS := 2000
const BENCH_BATCHES := 5
const PERF_DIAGNOSTIC_KEYS := ["grime_material_count"]
const GRIME_SHADER_UNIFORMS := [
	"dirt_amount",
	"dirt_opacity_gain",
	"wet_amount",
	"dirt_band_bottom",
	"dirt_band_top",
	"use_vehicle_space",
	"vehicle_from_world",
]
const BASELINE_RELATIVE_PATH := "research/rc-monster-truck/monster-car-2/rcv39/baseline_effects.gd"
const CURRENT_RELATIVE_PATH := "app/vehicles/ground/ground_effects.gd"
const MODEL_RELATIVE_PATH := "app/vehicles/ground/monster_car_2_model.gd"
const SHADER_RELATIVE_PATH := "app/vehicles/ground/ground_grime_overlay.gdshader"
const FIXTURE_RELATIVE_PATH := "app/tests/test_rcv36_effects.gd"

var _output_dir := ""
var _candidate_argument := ""
var _checks := 0
var _failures := 0
var _comparison_snapshots := 0
var _overlay_uniform_comparisons := 0
var _mismatches: Array[String] = []
var _road_surface_id := "gravel"
var _road_water_depth := 0.0
var _road_water_height := 0.0
var _bench_samples: Dictionary = {"stable_paused": [], "moving_dirty": []}
var _baseline_path := ""
var _candidate_path := ""
var _bench_path := ""
var _repo_root := ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_parse_arguments()
	_repo_root = ProjectSettings.globalize_path("res://").path_join("..").simplify_path()
	_bench_path = _script_absolute_path()
	_baseline_path = _repo_root.path_join(BASELINE_RELATIVE_PATH).simplify_path()
	_candidate_path = _resolve_candidate_path()
	if not _prepare_output_directory():
		_write_failure_receipt("output directory could not be prepared")
		quit(1)
		return
	if not FileAccess.file_exists(_baseline_path):
		_expect(false, "baseline script exists: " + _baseline_path)
		_write_receipt(false, {}, {})
		quit(1)
		return
	if not FileAccess.file_exists(_candidate_path):
		_expect(false, "candidate script exists: " + _candidate_path)
		_write_receipt(false, {}, {})
		quit(1)
		return

	var baseline_script := load(_baseline_path) as Script
	var candidate_script := load(_candidate_path) as Script
	if baseline_script == null or candidate_script == null:
		_expect(false, "baseline and candidate scripts load")
		_write_receipt(false, {}, {})
		quit(1)
		return

	var world := Node3D.new()
	world.name = "RCV39EffectsBenchWorld"
	root.add_child(world)
	var baseline_visual: Dictionary = Model.build()
	var candidate_visual: Dictionary = Model.build()
	if not baseline_visual.get("ok", false) or not candidate_visual.get("ok", false):
		_expect(false, "two real Monster Car 2 models build")
		_write_receipt(false, {}, {})
		world.free()
		quit(1)
		return

	var baseline_holder := Node3D.new()
	baseline_holder.name = "BaselineVehicleHolder"
	var candidate_holder := Node3D.new()
	candidate_holder.name = "CandidateVehicleHolder"
	world.add_child(baseline_holder)
	world.add_child(candidate_holder)
	baseline_holder.add_child(baseline_visual.root)
	candidate_holder.add_child(candidate_visual.root)
	await process_frame

	var baseline_sources := _snapshot_source_resources(baseline_visual)
	var candidate_sources := _snapshot_source_resources(candidate_visual)
	var baseline_effects: Variant = baseline_script.new()
	var candidate_effects: Variant = candidate_script.new()
	world.add_child(baseline_effects)
	world.add_child(candidate_effects)
	_expect(baseline_effects.prepare(baseline_visual, world), "baseline effects prepare")
	_expect(candidate_effects.prepare(candidate_visual, world), "candidate effects prepare")
	await process_frame

	var baseline_slots := _overlay_slots(baseline_effects)
	var candidate_slots := _overlay_slots(candidate_effects)
	_check_shader_uniform_contract()
	var baseline_unique := _unique_material_count(baseline_slots)
	var candidate_unique := _unique_material_count(candidate_slots)
	_expect(baseline_slots.size() == EXPECTED_OVERLAYS, "baseline retains all 70 shell/tire overlays")
	_expect(candidate_slots.size() == EXPECTED_OVERLAYS, "candidate retains all 70 shell/tire overlay bindings")
	_expect(baseline_unique == EXPECTED_OVERLAYS, "baseline uses one overlay material per mesh")
	_expect(candidate_unique == EXPECTED_CANDIDATE_MATERIALS,
		"candidate uses one shared shell material and four separate wheel materials")
	_expect(_model_shell_count(baseline_visual) == EXPECTED_SHELL_MESHES,
		"baseline model exposes 66 shell meshes")
	_expect(_model_shell_count(candidate_visual) == EXPECTED_SHELL_MESHES,
		"candidate model exposes 66 shell meshes")
	_check_material_binding_array(baseline_effects, baseline_slots, "baseline")
	_check_material_binding_array(candidate_effects, candidate_slots, "candidate")
	_check_distinct_vehicle_ownership(baseline_visual, candidate_visual,
		baseline_slots, candidate_slots)
	_check_source_resources_unchanged(baseline_sources, "baseline")
	_check_source_resources_unchanged(candidate_sources, "candidate")

	var tape := _build_update_tape()
	_run_update_tape(tape, baseline_effects, candidate_effects,
		baseline_visual, candidate_visual, baseline_holder, candidate_holder)
	_check_source_resources_unchanged(baseline_sources, "baseline after tape")
	_check_source_resources_unchanged(candidate_sources, "candidate after tape")

	var performance := _run_benchmarks(baseline_effects, candidate_effects,
		baseline_holder, candidate_holder)
	var structure := {
		"shell_meshes": EXPECTED_SHELL_MESHES,
		"overlays_attached_per_vehicle": [baseline_slots.size(), candidate_slots.size()],
		"unique_overlay_materials": [baseline_unique, candidate_unique],
		"candidate_diagnostic_grime_material_count": int(
			candidate_effects.diagnostic_snapshot().get("grime_material_count", -1)),
		"cross_vehicle_overlay_materials_shared": _shared_material_count(baseline_slots, candidate_slots),
		"source_mesh_nodes_distinct": _mesh_nodes_are_distinct(baseline_visual, candidate_visual),
		"source_mesh_resource_overlap": _shared_source_resource_count(
			baseline_sources, candidate_sources, "mesh"),
		"source_material_resource_overlap": _shared_source_material_count(
			baseline_sources, candidate_sources),
	}
	var complete: bool = _failures == 0 and bool(performance.get("complete", false))
	_write_receipt(complete, structure, {"tape": _tape_summary(tape), "performance": performance})
	world.queue_free()
	await process_frame
	print("RCV-39 effects: checks=%d failures=%d receipt=%s" % [
		_checks, _failures, _output_dir.path_join("receipt.json")])
	quit(0 if complete else 1)


func _parse_arguments() -> void:
	var args := OS.get_cmdline_user_args()
	var index := 0
	while index < args.size():
		var argument: String = str(args[index])
		if argument.begins_with("--output="):
			_output_dir = argument.trim_prefix("--output=")
		elif argument == "--output" and index + 1 < args.size():
			index += 1
			_output_dir = str(args[index])
		elif argument.begins_with("--candidate="):
			_candidate_argument = argument.trim_prefix("--candidate=")
		elif argument == "--candidate" and index + 1 < args.size():
			index += 1
			_candidate_argument = str(args[index])
		index += 1


func _prepare_output_directory() -> bool:
	if _output_dir.is_empty():
		printerr("Missing --output=<directory>")
		return false
	_output_dir = _resolve_path(_output_dir)
	if DirAccess.dir_exists_absolute(_output_dir):
		return true
	return DirAccess.make_dir_recursive_absolute(_output_dir) == OK


func _resolve_candidate_path() -> String:
	if _candidate_argument.is_empty():
		return _repo_root.path_join(CURRENT_RELATIVE_PATH).simplify_path()
	return _resolve_path(_candidate_argument)


func _resolve_path(path: String) -> String:
	if path.begins_with("res://"):
		return ProjectSettings.globalize_path(path).simplify_path()
	if path.is_absolute_path():
		return path.simplify_path()
	return _repo_root.path_join(path).simplify_path()


func _script_absolute_path() -> String:
	var script := get_script() as Script
	if script == null:
		return ""
	var script_path := script.resource_path
	if script_path.begins_with("res://"):
		return ProjectSettings.globalize_path(script_path).simplify_path()
	return script_path.simplify_path()


func _build_update_tape() -> Array[Dictionary]:
	var all_contacts := PackedByteArray([1, 1, 1, 1])
	return [
		{
			"name": "dry-moving",
			"steps": 12,
			"dt": 0.1,
			"telemetry": _telemetry(all_contacts, PackedFloat64Array([0.6, 0.6, 0.6, 0.6]), 6.0),
			"controls": {"brake": 0.0, "reverse": false},
			"paused": false,
			"night": 0.0,
			"surface_id": "gravel",
			"water_depth": 0.0,
			"water_height": 0.0,
		},
		{
			"name": "dirt",
			"steps": 12,
			"dt": 0.1,
			"telemetry": _telemetry(all_contacts, PackedFloat64Array([0.25, 0.45, 0.7, 0.9]), 4.2),
			"controls": {"brake": 0.12, "reverse": false},
			"paused": false,
			"night": 0.18,
			"surface_id": "dirt",
			"water_depth": 0.0,
			"water_height": 0.0,
		},
		{
			"name": "mud",
			"steps": 12,
			"dt": 0.1,
			"telemetry": _telemetry(all_contacts, PackedFloat64Array([0.25, 0.5, 0.8, 1.0]), 2.8,
				_accepted_environment(0.0, PackedFloat64Array([0.0, 0.0, 0.0, 0.0]),
					PackedFloat64Array([0.0, 0.0, 0.0, 0.0]), PackedFloat64Array([0.75, 0.5, 0.85, 0.4]))),
			"controls": {"brake": 0.0, "reverse": false},
			"paused": false,
			"night": 0.0,
			"surface_id": "mud",
			"water_depth": 0.0,
			"water_height": 0.0,
		},
		{
			"name": "wet",
			"steps": 12,
			"dt": 0.1,
			"telemetry": _telemetry(all_contacts, PackedFloat64Array([0.15, 0.2, 0.3, 0.45]), 1.8,
				_accepted_environment(0.58, PackedFloat64Array([0.2, 0.4, 0.25, 0.3]),
					PackedFloat64Array([0.04, 0.04, 0.04, 0.04]), PackedFloat64Array([0.0, 0.0, 0.0, 0.0]))),
			"controls": {"brake": 0.0, "reverse": false},
			"paused": false,
			"night": 0.0,
			"surface_id": "dirt",
			"water_depth": 0.04,
			"water_height": 0.025,
		},
		{
			"name": "drying",
			"steps": 24,
			"dt": 0.1,
			"telemetry": _telemetry(all_contacts, PackedFloat64Array([0.0, 0.05, 0.02, 0.04]), 0.4),
			"controls": {"brake": 0.0, "reverse": false},
			"paused": false,
			"night": 0.0,
			"surface_id": "asphalt",
			"water_depth": 0.0,
			"water_height": 0.0,
		},
		{
			"name": "pause",
			"steps": 3,
			"dt": 0.1,
			"telemetry": _telemetry(all_contacts, PackedFloat64Array([0.6, 0.6, 0.6, 0.6]), 6.0),
			"controls": {"brake": 0.0, "reverse": true},
			"paused": true,
			"night": 0.45,
			"surface_id": "gravel",
			"water_depth": 0.0,
			"water_height": 0.0,
		},
		{
			"name": "transform-motion",
			"steps": 10,
			"dt": 0.05,
			"telemetry": _telemetry(all_contacts, PackedFloat64Array([0.4, 0.5, 0.7, 0.8]), 3.7),
			"controls": {"brake": 0.0, "reverse": false},
			"paused": false,
			"night": 0.2,
			"surface_id": "gravel",
			"water_depth": 0.0,
			"water_height": 0.0,
			"transform_motion": true,
		},
		{
			"name": "pause-before-clean",
			"steps": 1,
			"dt": 0.1,
			"telemetry": _telemetry(all_contacts, PackedFloat64Array([0.6, 0.6, 0.6, 0.6]), 6.0),
			"controls": {},
			"paused": true,
			"night": 0.0,
			"surface_id": "gravel",
			"water_depth": 0.0,
			"water_height": 0.0,
		},
		{
			"name": "clean-while-paused",
			"operation": "clean",
		},
		{
			"name": "resume-after-clean",
			"steps": 1,
			"dt": 0.1,
			"telemetry": _telemetry(all_contacts, PackedFloat64Array([0.0, 0.0, 0.0, 0.0]), 0.0),
			"controls": {},
			"paused": false,
			"night": 0.0,
			"surface_id": "asphalt",
			"water_depth": 0.0,
			"water_height": 0.0,
		},
		{
			"name": "dirty-before-reset",
			"steps": 8,
			"dt": 0.1,
			"telemetry": _telemetry(all_contacts, PackedFloat64Array([0.8, 0.8, 0.8, 0.8]), 5.2),
			"controls": {},
			"paused": false,
			"night": 0.0,
			"surface_id": "gravel",
			"water_depth": 0.0,
			"water_height": 0.0,
		},
		{
			"name": "reset",
			"operation": "reset",
		},
	]


func _run_update_tape(
	tape: Array[Dictionary],
	baseline_effects: Variant,
	candidate_effects: Variant,
	baseline_visual: Dictionary,
	candidate_visual: Dictionary,
	baseline_holder: Node3D,
	candidate_holder: Node3D,
) -> void:
	var road := Callable(self, "_sample_road")
	for event: Dictionary in tape:
		var event_name := str(event.get("name", "unnamed"))
		var operation := str(event.get("operation", ""))
		if operation == "clean":
			baseline_effects.clean_vehicle()
			candidate_effects.clean_vehicle()
			_compare_pair(event_name, baseline_effects, candidate_effects,
				baseline_visual, candidate_visual)
			continue
		if operation == "reset":
			baseline_effects.reset()
			candidate_effects.reset()
			_compare_pair(event_name, baseline_effects, candidate_effects,
				baseline_visual, candidate_visual)
			continue
		_road_surface_id = str(event.get("surface_id", "gravel"))
		_road_water_depth = float(event.get("water_depth", 0.0))
		_road_water_height = float(event.get("water_height", 0.0))
		for step in int(event.get("steps", 0)):
			if event.get("transform_motion", false):
				var vehicle_transform := _tape_transform(step)
				baseline_holder.transform = vehicle_transform
				candidate_holder.transform = vehicle_transform
			baseline_effects.update_render(
				float(event.get("dt", 0.0)), event.telemetry, event.controls, road,
				bool(event.get("paused", false)), float(event.get("night", 0.0)))
			candidate_effects.update_render(
				float(event.get("dt", 0.0)), event.telemetry, event.controls, road,
				bool(event.get("paused", false)), float(event.get("night", 0.0)))
			_compare_pair("%s[%d]" % [event_name, step], baseline_effects, candidate_effects,
				baseline_visual, candidate_visual)


func _tape_transform(step: int) -> Transform3D:
	var yaw := 0.11 + float(step) * 0.017
	var basis := Basis(Vector3.UP, yaw).scaled(Vector3(1.0 + float(step) * 0.0005, 1.0, 1.0))
	return Transform3D(basis, Vector3(0.035 * float(step), 0.012 * float(step), -0.021 * float(step)))


func _compare_pair(
	label: String,
	baseline_effects: Variant,
	candidate_effects: Variant,
	baseline_visual: Dictionary,
	candidate_visual: Dictionary,
) -> void:
	_comparison_snapshots += 1
	var baseline_diagnostics: Dictionary = _diagnostics_without_performance(
		baseline_effects.diagnostic_snapshot())
	var candidate_diagnostics: Dictionary = _diagnostics_without_performance(
		candidate_effects.diagnostic_snapshot())
	_expect(_same_value(baseline_diagnostics, candidate_diagnostics),
		label + " diagnostics agree")
	_compare_overlay_uniforms(label, baseline_effects, candidate_effects)
	_compare_emitter_state(label, baseline_effects, candidate_effects)
	_expect(_all_overlays_attached(baseline_effects, baseline_visual),
		label + " baseline overlays remain attached")
	_expect(_all_overlays_attached(candidate_effects, candidate_visual),
		label + " candidate overlays remain attached")


func _compare_overlay_uniforms(label: String, baseline_effects: Variant, candidate_effects: Variant) -> void:
	var baseline_slots := _overlay_slots(baseline_effects)
	var candidate_slots := _overlay_slots(candidate_effects)
	_expect(baseline_slots.size() == candidate_slots.size(), label + " overlay slot counts agree")
	var common_count: int = mini(baseline_slots.size(), candidate_slots.size())
	for index in common_count:
		var baseline_material := baseline_slots[index].material as ShaderMaterial
		var candidate_material := candidate_slots[index].material as ShaderMaterial
		var slot_name := str(baseline_slots[index].slot)
		if baseline_material == null or candidate_material == null:
			_expect(false, "%s %s has shader materials" % [label, slot_name])
			continue
		var baseline_parameters := _shader_parameters(baseline_material)
		var candidate_parameters := _shader_parameters(candidate_material)
		_expect(baseline_parameters.size() == candidate_parameters.size(),
			"%s %s uniform counts agree" % [label, slot_name])
		_expect(baseline_parameters.size() == GRIME_SHADER_UNIFORMS.size(),
			"%s %s has all declared grime shader uniforms" % [label, slot_name])
		for parameter_name: String in GRIME_SHADER_UNIFORMS:
			_expect(candidate_parameters.has(parameter_name),
				"%s %s uniform %s exists" % [label, slot_name, parameter_name])
			_expect(baseline_parameters.has(parameter_name),
				"%s %s baseline uniform %s exists" % [label, slot_name, parameter_name])
			if baseline_parameters.has(parameter_name) and candidate_parameters.has(parameter_name):
				_expect(baseline_parameters[parameter_name] != null
					and candidate_parameters[parameter_name] != null,
					"%s %s uniform %s is initialized" % [label, slot_name, parameter_name])
				_expect(_same_value(baseline_parameters[parameter_name], candidate_parameters[parameter_name]),
					"%s %s uniform %s agrees" % [label, slot_name, parameter_name])
				_overlay_uniform_comparisons += 1


func _compare_emitter_state(label: String, baseline_effects: Variant, candidate_effects: Variant) -> void:
	var baseline_emitters: Array = baseline_effects.get("_emitters")
	var candidate_emitters: Array = candidate_effects.get("_emitters")
	_expect(baseline_emitters.size() == candidate_emitters.size(), label + " emitter counts agree")
	var common_count: int = mini(baseline_emitters.size(), candidate_emitters.size())
	for index in common_count:
		var baseline_emitter := baseline_emitters[index] as CPUParticles3D
		var candidate_emitter := candidate_emitters[index] as CPUParticles3D
		_expect(_same_value(_emitter_state(baseline_emitter), _emitter_state(candidate_emitter)),
			"%s emitter[%d] state agrees" % [label, index])


func _emitter_state(emitter: CPUParticles3D) -> Dictionary:
	return {
		"name": emitter.name,
		"emitting": emitter.emitting,
		"speed_scale": emitter.speed_scale,
		"global_transform": emitter.global_transform,
		"initial_velocity_min": emitter.initial_velocity_min,
		"initial_velocity_max": emitter.initial_velocity_max,
		"scale_amount_min": emitter.scale_amount_min,
		"scale_amount_max": emitter.scale_amount_max,
		"color": emitter.color,
		"amount": emitter.amount,
	}


func _diagnostics_without_performance(snapshot: Dictionary) -> Dictionary:
	var comparable := snapshot.duplicate(true)
	for key: String in PERF_DIAGNOSTIC_KEYS:
		comparable.erase(key)
	return comparable


func _shader_parameters(material: ShaderMaterial) -> Dictionary:
	var result := {}
	if material.shader == null:
		return result
	for parameter_name: String in GRIME_SHADER_UNIFORMS:
		result[parameter_name] = material.get_shader_parameter(parameter_name)
	return result


func _check_shader_uniform_contract() -> void:
	var shader_path := _repo_root.path_join(SHADER_RELATIVE_PATH).simplify_path()
	var shader_source := FileAccess.get_file_as_string(shader_path)
	var declared_count := 0
	for line: String in shader_source.split("\n"):
		if line.strip_edges().begins_with("uniform "):
			declared_count += 1
	_expect(declared_count == GRIME_SHADER_UNIFORMS.size(),
		"grime shader declares exactly the seven listed uniforms")
	for parameter_name: String in GRIME_SHADER_UNIFORMS:
		_expect(shader_source.contains(parameter_name),
			"grime shader source declares " + parameter_name)


func _overlay_slots(effects: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var shells: Array = effects.get("_shell_meshes")
	for index in shells.size():
		var mesh := shells[index] as MeshInstance3D
		result.append({
			"slot": "shell[%02d:%s]" % [index, mesh.name if mesh != null else "null"],
			"mesh": mesh,
			"material": mesh.material_overlay if mesh != null else null,
		})
	var wheels: Array = effects.get("_wheel_nodes")
	for index in wheels.size():
		var mesh := wheels[index] as MeshInstance3D
		result.append({
			"slot": "wheel[%s]" % (mesh.name if mesh != null else str(index)),
			"mesh": mesh,
			"material": mesh.material_overlay if mesh != null else null,
		})
	return result


func _all_overlays_attached(effects: Variant, visual: Dictionary) -> bool:
	var slots := _overlay_slots(effects)
	if slots.size() != EXPECTED_OVERLAYS:
		return false
	for slot: Dictionary in slots:
		if not is_instance_valid(slot.mesh) or not slot.material is ShaderMaterial:
			return false
	return _model_shell_count(visual) == EXPECTED_SHELL_MESHES


func _check_material_binding_array(effects: Variant, slots: Array[Dictionary], label: String) -> void:
	var references: Array = effects.get("_grime_materials")
	_expect(references.size() == slots.size(), label + " compatibility material-reference count is 70")
	var common_count: int = mini(references.size(), slots.size())
	for index in common_count:
		_expect(references[index] == slots[index].material,
			"%s compatibility reference %d matches its mesh overlay" % [label, index])


func _check_distinct_vehicle_ownership(
	baseline_visual: Dictionary,
	candidate_visual: Dictionary,
	baseline_slots: Array[Dictionary],
	candidate_slots: Array[Dictionary],
) -> void:
	_expect(baseline_visual.root != candidate_visual.root, "two model builds own distinct scene nodes")
	_expect(_mesh_nodes_are_distinct(baseline_visual, candidate_visual),
		"two model builds own distinct MeshInstance3D nodes")
	_expect(_shared_material_count(baseline_slots, candidate_slots) == 0,
		"baseline and candidate do not share overlay material instances")
	for slot: Dictionary in baseline_slots + candidate_slots:
		var mesh := slot.mesh as MeshInstance3D
		var material := slot.material as ShaderMaterial
		_expect(mesh != null and material != null, "every source mesh has a grime overlay")
		if mesh == null or material == null:
			continue
		_expect(mesh.material_override != material, "grime overlay does not replace the source override")
		if mesh.mesh != null:
			for surface in mesh.mesh.get_surface_count():
				_expect(mesh.mesh.surface_get_material(surface) != material,
					"grime overlay is separate from every source surface material")


func _snapshot_source_resources(visual: Dictionary) -> Dictionary:
	var result := {}
	var meshes: Array[MeshInstance3D] = []
	var effects_shells: Array = visual.get("body_nodes", [])
	for value in effects_shells:
		if value is MeshInstance3D and not meshes.has(value):
			meshes.append(value as MeshInstance3D)
	var nodes: Dictionary = visual.get("nodes", {})
	var body: Variant = nodes.get("Body")
	if body is MeshInstance3D and not meshes.has(body):
		meshes.append(body as MeshInstance3D)
	for corner: String in CORNERS:
		var wheel: Variant = nodes.get(corner + "_WheelMesh")
		if wheel is MeshInstance3D and not meshes.has(wheel):
			meshes.append(wheel as MeshInstance3D)
	for mesh in meshes:
		var surfaces: Array = []
		if mesh.mesh != null:
			for surface in mesh.mesh.get_surface_count():
				surfaces.append(mesh.mesh.surface_get_material(surface))
		result[mesh] = {
			"mesh": mesh.mesh,
			"override": mesh.material_override,
			"surfaces": surfaces,
		}
	return result


func _check_source_resources_unchanged(snapshot: Dictionary, label: String) -> void:
	for mesh_value: Variant in snapshot.keys():
		var mesh := mesh_value as MeshInstance3D
		var before: Dictionary = snapshot[mesh_value]
		_expect(is_instance_valid(mesh), label + " source mesh instance remains valid")
		if not is_instance_valid(mesh):
			continue
		_expect(mesh.mesh == before.mesh, label + " source Mesh resource identity is unchanged")
		_expect(mesh.material_override == before.override,
			label + " source material override identity is unchanged")
		var surfaces: Array = before.surfaces
		_expect((mesh.mesh.get_surface_count() if mesh.mesh != null else 0) == surfaces.size(),
			label + " source surface count is unchanged")
		if mesh.mesh != null:
			for surface in mini(mesh.mesh.get_surface_count(), surfaces.size()):
				_expect(mesh.mesh.surface_get_material(surface) == surfaces[surface],
					label + " source surface material identity is unchanged")


func _mesh_nodes_are_distinct(first_visual: Dictionary, second_visual: Dictionary) -> bool:
	var first := _snapshot_source_resources(first_visual)
	var second := _snapshot_source_resources(second_visual)
	for mesh in first.keys():
		if second.has(mesh):
			return false
	return true


func _model_shell_count(visual: Dictionary) -> int:
	var count := 0
	var seen: Array[MeshInstance3D] = []
	for value in visual.get("body_nodes", []):
		if value is MeshInstance3D and not seen.has(value):
			seen.append(value as MeshInstance3D)
	var body: Variant = visual.get("nodes", {}).get("Body")
	if body is MeshInstance3D and not seen.has(body):
		seen.append(body as MeshInstance3D)
	count = seen.size()
	return count


func _unique_material_count(slots: Array[Dictionary]) -> int:
	var ids := {}
	for slot: Dictionary in slots:
		var material := slot.material as ShaderMaterial
		if material != null:
			ids[material.get_instance_id()] = true
	return ids.size()


func _shared_material_count(first_slots: Array[Dictionary], second_slots: Array[Dictionary]) -> int:
	var first_ids := {}
	for slot: Dictionary in first_slots:
		var material := slot.material as ShaderMaterial
		if material != null:
			first_ids[material.get_instance_id()] = true
	var shared := {}
	for slot: Dictionary in second_slots:
		var material := slot.material as ShaderMaterial
		if material != null and first_ids.has(material.get_instance_id()):
			shared[material.get_instance_id()] = true
	return shared.size()


func _shared_source_resource_count(first: Dictionary, second: Dictionary, key: String) -> int:
	var first_ids := {}
	for mesh in first:
		var resource: Resource = first[mesh].get(key)
		if resource != null:
			first_ids[resource.get_instance_id()] = true
	var overlap := {}
	for mesh in second:
		var resource: Resource = second[mesh].get(key)
		if resource != null and first_ids.has(resource.get_instance_id()):
			overlap[resource.get_instance_id()] = true
	return overlap.size()


func _shared_source_material_count(first: Dictionary, second: Dictionary) -> int:
	var first_ids := {}
	for mesh in first:
		var before: Dictionary = first[mesh]
		var override_material: Material = before.get("override")
		if override_material != null:
			first_ids[override_material.get_instance_id()] = true
		for surface_material: Variant in before.get("surfaces", []):
			if surface_material is Material:
				first_ids[surface_material.get_instance_id()] = true
	var overlap := {}
	for mesh in second:
		var before: Dictionary = second[mesh]
		var override_material: Material = before.get("override")
		if override_material != null and first_ids.has(override_material.get_instance_id()):
			overlap[override_material.get_instance_id()] = true
		for surface_material: Variant in before.get("surfaces", []):
			if surface_material is Material and first_ids.has(surface_material.get_instance_id()):
				overlap[surface_material.get_instance_id()] = true
	return overlap.size()


func _run_benchmarks(
	baseline_effects: Variant,
	candidate_effects: Variant,
	baseline_holder: Node3D,
	candidate_holder: Node3D,
) -> Dictionary:
	var road := Callable(self, "_sample_road")
	var case_inputs := {
		"stable_paused": {
			"name": "stable-paused",
			"dt": 1.0 / 60.0,
			"telemetry": _telemetry(PackedByteArray([1, 1, 1, 1]),
				PackedFloat64Array([0.6, 0.6, 0.6, 0.6]), 6.0),
			"controls": {},
			"paused": true,
			"night": 0.0,
			"surface_id": "gravel",
			"moving_transform": false,
		},
		"moving_dirty": {
			"name": "moving-dirty",
			"dt": 1.0 / 60.0,
			"telemetry": _telemetry(PackedByteArray([1, 1, 1, 1]),
				PackedFloat64Array([0.6, 0.6, 0.6, 0.6]), 6.0),
			"controls": {},
			"paused": false,
			"night": 0.0,
			"surface_id": "gravel",
			"moving_transform": true,
		},
	}
	var results := {}
	var all_samples: Array[Dictionary] = []
	for case_key: String in ["stable_paused", "moving_dirty"]:
		var inputs: Dictionary = case_inputs[case_key]
		_road_surface_id = str(inputs.surface_id)
		_road_water_depth = 0.0
		_road_water_height = 0.0
		var samples: Array[Dictionary] = []
		for batch in BENCH_BATCHES:
			var order: Array[String] = ["baseline", "candidate"]
			if batch % 2 == 1:
				order.reverse()
			for implementation: String in order:
				var effects: Variant = baseline_effects if implementation == "baseline" else candidate_effects
				var holder: Node3D = baseline_holder if implementation == "baseline" else candidate_holder
				effects.reset()
				holder.transform = Transform3D.IDENTITY
				var sample := _measure_case(effects, holder, inputs, road)
				sample["case"] = str(inputs.name)
				sample["implementation"] = implementation
				sample["batch"] = batch
				sample["order"] = order.duplicate()
				samples.append(sample)
				all_samples.append(sample)
		var baseline_values := _sample_values(samples, "baseline")
		var candidate_values := _sample_values(samples, "candidate")
		var baseline_median := _median(baseline_values)
		var candidate_median := _median(candidate_values)
		results[case_key] = {
			"samples": samples,
			"warmup_updates_per_sample": BENCH_WARMUP,
			"measured_updates_per_sample": BENCH_ITERATIONS,
			"batches": BENCH_BATCHES,
			"baseline_median_us_per_update": baseline_median,
			"candidate_median_us_per_update": candidate_median,
			"median_speedup_ratio": baseline_median / candidate_median if candidate_median > 0.0 else 0.0,
			"moving_transform_assignment_in_timed_loop": bool(inputs.moving_transform),
		}
	_bench_samples["stable_paused"] = results.get("stable_paused", {}).get("samples", [])
	_bench_samples["moving_dirty"] = results.get("moving_dirty", {}).get("samples", [])
	return {
		"complete": all_samples.size() == 2 * BENCH_BATCHES * 2,
		"warmup_updates": BENCH_WARMUP,
		"measured_updates": BENCH_ITERATIONS,
		"alternating_batches": BENCH_BATCHES,
		"case_results": results,
		"sample_count": all_samples.size(),
	}


func _measure_case(effects: Variant, holder: Node3D, inputs: Dictionary, road: Callable) -> Dictionary:
	for index in BENCH_WARMUP:
		_set_bench_transform(holder, bool(inputs.moving_transform), index)
		effects.update_render(float(inputs.dt), inputs.telemetry, inputs.controls, road,
			bool(inputs.paused), float(inputs.night))
	var started := Time.get_ticks_usec()
	for index in BENCH_ITERATIONS:
		_set_bench_transform(holder, bool(inputs.moving_transform), BENCH_WARMUP + index)
		effects.update_render(float(inputs.dt), inputs.telemetry, inputs.controls, road,
			bool(inputs.paused), float(inputs.night))
	var elapsed_usec := Time.get_ticks_usec() - started
	return {
		"elapsed_usec": elapsed_usec,
		"us_per_update": float(elapsed_usec) / float(BENCH_ITERATIONS),
	}


func _set_bench_transform(holder: Node3D, moving: bool, index: int) -> void:
	if not moving:
		return
	var step := float(index)
	var basis := Basis(Vector3.UP, 0.0007 * step).scaled(Vector3(1.0 + 0.0000005 * step, 1.0, 1.0))
	holder.transform = Transform3D(basis, Vector3(0.0002 * step, 0.0, -0.0001 * step))


func _sample_values(samples: Array[Dictionary], implementation: String) -> Array[float]:
	var values: Array[float] = []
	for sample: Dictionary in samples:
		if sample.get("implementation") == implementation:
			values.append(float(sample.us_per_update))
	values.sort()
	return values


func _median(sorted_values: Array[float]) -> float:
	if sorted_values.is_empty():
		return 0.0
	var middle := sorted_values.size() / 2
	if sorted_values.size() % 2 == 1:
		return sorted_values[middle]
	return 0.5 * (sorted_values[middle - 1] + sorted_values[middle])


func _tape_summary(tape: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for event: Dictionary in tape:
		result.append({
			"name": event.get("name", ""),
			"operation": event.get("operation", "update"),
			"steps": event.get("steps", 0),
	})
	return result


func _telemetry(
	contacts: PackedByteArray,
	slips: PackedFloat64Array,
	speed: float,
	environment: Dictionary = {},
) -> Dictionary:
	var result := {
		"wheel_in_contact": contacts,
		"wheel_slip_speed_m_per_s": slips,
		"speed_m_per_s": speed,
	}
	if not environment.is_empty():
		result["environment"] = environment
	return result


func _accepted_environment(
	body_submersion: float,
	wheel_submersion: PackedFloat64Array,
	wheel_depth: PackedFloat64Array,
	wheel_mud: PackedFloat64Array,
) -> Dictionary:
	return {
		"ok": true,
		"body_submersion": body_submersion,
		"water_depth_m": 0.04 if body_submersion > 0.0 else 0.0,
		"buoyancy_n": 0.0,
		"drag_power_w": 0.0,
		"power_w": 0.0,
		"wheel_submersion": wheel_submersion,
		"wheel_water_height_m": PackedFloat64Array([0.0, 0.0, 0.0, 0.0]),
		"wheel_depth_m": wheel_depth,
		"wheel_mud": wheel_mud,
	}


func _sample_road(_north: float, _east: float) -> Dictionary:
	return {
		"surface_id": _road_surface_id,
		"height_m": 0.0,
		"water_depth_m": _road_water_depth,
		"water_height_m": _road_water_height,
	}


func _same_value(first: Variant, second: Variant) -> bool:
	if typeof(first) != typeof(second):
		return false
	if typeof(first) == TYPE_FLOAT or typeof(first) == TYPE_INT:
		return first == second
	if typeof(first) == TYPE_DICTIONARY:
		if first.size() != second.size():
			return false
		for key in first:
			if not second.has(key) or not _same_value(first[key], second[key]):
				return false
		return true
	if typeof(first) == TYPE_ARRAY:
		if first.size() != second.size():
			return false
		for index in first.size():
			if not _same_value(first[index], second[index]):
				return false
		return true
	return first == second


func _expect(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	if _mismatches.size() < 40:
		_mismatches.append(label)
	printerr("FAIL: " + label)


func _source_hashes() -> Dictionary:
	var paths := {
		"bench_effects.gd": _bench_path,
		"baseline_effects.gd": _baseline_path,
		"candidate_effects.gd": _candidate_path,
		"production_ground_effects.gd": _repo_root.path_join(CURRENT_RELATIVE_PATH).simplify_path(),
		"monster_car_2_model.gd": _repo_root.path_join(MODEL_RELATIVE_PATH).simplify_path(),
		"ground_grime_overlay.gdshader": _repo_root.path_join(SHADER_RELATIVE_PATH).simplify_path(),
		"test_rcv36_effects.gd": _repo_root.path_join(FIXTURE_RELATIVE_PATH).simplify_path(),
	}
	var result := {}
	for label: String in paths:
		var path := str(paths[label])
		result[label] = {
			"path": path,
			"sha256": FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "missing",
		}
	return result


func _write_failure_receipt(reason: String) -> void:
	_expect(false, reason)
	_write_receipt(false, {}, {"error": reason})


func _write_receipt(complete: bool, structure: Dictionary, result: Dictionary) -> void:
	if _output_dir.is_empty() or not DirAccess.dir_exists_absolute(_output_dir):
		return
	var engine_info := Engine.get_version_info()
	var receipt := {
		"schema": "rcv39-ground-effects-bench-v1",
		"complete": complete,
		"equivalent": _failures == 0,
		"created_utc": Time.get_datetime_string_from_system(true),
		"engine": engine_info,
		"os": OS.get_name(),
		"baseline_path": _baseline_path,
		"candidate_path": _candidate_path,
		"source_hashes": _source_hashes(),
		"structure": structure,
		"result": result,
		"verification": {
			"checks": _checks,
			"failures": _failures,
			"comparison_snapshots": _comparison_snapshots,
			"overlay_uniform_comparisons": _overlay_uniform_comparisons,
			"mismatches": _mismatches,
			"diagnostic_performance_fields_excluded": PERF_DIAGNOSTIC_KEYS,
		},
	}
	var path := _output_dir.path_join("receipt.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		printerr("Could not write receipt: " + path)
		return
	file.store_string(JSON.stringify(receipt, "\t", true) + "\n")
	file.close()
