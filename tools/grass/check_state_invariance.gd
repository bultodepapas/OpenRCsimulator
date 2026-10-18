## Headless grass renderer/state invariance gate. Builds the production field first,
## observes its effective materials, then exact-replays a complete ORFL in-process.
extends SceneTree

const FieldLoader := preload("res://data/field_loader.gd")
const Field := preload("res://render/field.gd")
const Scenery := preload("res://scenery/scenery.gd")
const GrassQuality := preload("res://render/grass_quality.gd")
const Reader := preload("res://tools/flight_log_cli.gd")
const Log := preload("res://sim/flight_log.gd")
const Flight := preload("res://sim/flight_session.gd")
const RCVSession := preload("res://sim/ground_vehicle/session.gd")
const RCVDynamics := preload("res://physics/ground_vehicle/vehicle_dynamics.gd")

const FORMAT := "openrc-grass-state-invariance v1"
const RC_VEHICLE_IDS := ["mt8-bisonte", "monster-car-2"]
const EXPECTED_COUNTS := {
	"default": {"grass_common_short": 67, "grass_common_tall": 42, "grass_wispy_tall": 41},
	"enhanced": {"grass_common_short": 100, "grass_common_tall": 30, "grass_wispy_tall": 20},
}

var options: Dictionary = {}
var report: Dictionary = {"format": FORMAT, "status": "error", "error": "Not started"}


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		var pair := argument.trim_prefix("--").split("=", true, 1)
		options[pair[0]] = pair[1] if pair.size() > 1 else true
	call_deferred("_run")


func _run() -> void:
	if options.has("capture-runway"):
		await _capture_runway_mode()
		return
	for key in ["mode", "log", "csv", "report"]:
		if typeof(options.get(key)) != TYPE_STRING or str(options[key]).is_empty():
			_fail("Required: --mode=default|enhanced --log=<complete.orfl> --csv=<new.csv> --report=<new.json>")
			return
	var mode := str(options.mode)
	if mode not in ["default", "enhanced"]:
		_fail("Mode must be default or enhanced.")
		return
	for key in ["csv", "report"]:
		if FileAccess.file_exists(str(options[key])):
			printerr("Output already exists: " + str(options[key]))
			quit(1)
			return
	if _canonical_path(str(options.csv)) == _canonical_path(str(options.report)):
		_fail("CSV and report must have different output paths.")
		return

	report.merge({"mode": mode, "source": str(options.log), "renderer": {}, "replay": {}}, true)
	var renderer := _build_and_check_renderer(mode)
	if not renderer.ok:
		_fail(str(renderer.error))
		return
	report.renderer = renderer.observed
	# Keep the production field in the same SceneTree until replay finishes. This
	# proves that this exact process loaded the selected materials before running it.
	await process_frame
	if not renderer.field_root.is_inside_tree():
		_fail("Production field did not enter the active SceneTree.")
		return

	var replay := _exact_replay(str(options.log), str(options.csv))
	if not replay.ok:
		_fail(str(replay.error))
		return
	report.replay = replay.result
	var rcv := _rc_state_probe()
	if not rcv.ok:
		_fail(str(rcv.error))
		return
	report.rc_ground_vehicle = rcv.result
	report.status = "ok"
	report.error = ""
	_write_report()
	print("PASS: %s grass renderer initialized; exact replay verified (%d rows)." % [mode, int(replay.result.rows)])
	quit(0)


func _capture_runway_mode() -> void:
	var aircraft_kind := str(options.get("capture-runway", ""))
	if aircraft_kind not in ["stik", "p51"] \
			or typeof(options.get("log")) != TYPE_STRING or str(options.log).is_empty() \
			or typeof(options.get("report")) != TYPE_STRING or str(options.report).is_empty():
		printerr("Capture requires --capture-runway=stik|p51 --log=<new.orfl> --report=<new.json>.")
		quit(1)
		return
	for path in [str(options.log), str(options.report)]:
		if FileAccess.file_exists(path):
			printerr("Output already exists: " + path)
			quit(1)
			return
	report.format = "openrc-grass-state-capture v1"
	report.mode = "default"
	var renderer := _build_and_check_renderer("default")
	if not renderer.ok:
		_fail(str(renderer.error))
		return
	report.renderer = renderer.observed
	await process_frame
	var aircraft_path := "res://data/aircraft/jensen_ugly_stik_60.json" if aircraft_kind == "stik" \
		else "res://data/aircraft/p51d_mustang_120.json"
	var capture := _record_runway(aircraft_path, aircraft_kind, str(options.log))
	if not capture.ok:
		_fail(str(capture.error))
		return
	report.recording = capture.recording
	report.status = "ok"
	report.error = ""
	_write_report()
	print("PASS: current-solver %s runway tape recorded by the existing FlightLog recorder (%d rows)." % [aircraft_kind, int(capture.recording.rows)])
	quit(0)


func _record_runway(aircraft_path: String, aircraft_kind: String, path: String) -> Dictionary:
	var loaded := FieldLoader.load_from()
	if not loaded.get("ok", false):
		return {"ok": false, "error": "Could not load the default field for the P-51 runway tape."}
	var flight: Node = Flight.new()
	flight.input_enabled = false
	flight.crash_auto_restart = false
	flight.soft_hull_contacts = true
	flight.start_choice = "runway"
	flight.setup(aircraft_path)
	if not flight.set_field(loaded.field):
		flight.free()
		return {"ok": false, "error": "P-51 session or default-field setup failed."}
	flight.reset()
	if not flight.is_flyable() or str(flight.trace_meta().get("launch_choice", "")) != "runway":
		flight.free()
		return {"ok": false, "error": "P-51 runway start was not accepted by the existing flight setup."}
	var initial_compressions: PackedFloat64Array = flight.gear_compressions(flight.sim.state)
	var initial_contacts := _positive_indices(initial_compressions)
	if initial_contacts.is_empty():
		flight.free()
		return {"ok": false, "error": "Runway tape did not start with an observed gear/terrain contact."}
	var recorder: RefCounted = Log.new(flight)
	if recorder.start(path) != OK:
		flight.free()
		return {"ok": false, "error": "Existing FlightLog recorder refused the fresh runway tape: " + str(recorder.failure)}
	recorder.mark("Grass state invariance software fixture; scripted %s runway gear contact; not physical acceptance." % aircraft_kind)
	var requested_ticks := 2880
	for _tick in requested_ticks:
		var inputs: PackedFloat64Array = flight.sim.inputs.duplicate()
		for index in mini(4, inputs.size()):
			inputs[index] = 0.0
		if inputs.size() > 4:
			inputs[4] = 1.0
		if inputs.size() > 5:
			inputs[5] = 0.0
		if inputs.size() > 6:
			inputs[6] = 0.0
		flight.sim.inputs = inputs
		flight.sim.step()
		if not flight.sim.fault_reason.is_empty() or flight.sim.tick != _tick + 1:
			break
	if recorder.recording:
		recorder.stop("completed scripted 12-second runway state tape")
	var checked := Reader.inspect(path, false)
	var final_compressions: PackedFloat64Array = flight.gear_compressions(flight.sim.state)
	var final_contacts := _positive_indices(final_compressions)
	var faults: String = str(flight.sim.fault_reason)
	var crashed: bool = not flight.crash.is_empty()
	flight.free()
	if not checked.get("ok", false) or not checked.get("complete", false):
		return {"ok": false, "error": "Fresh runway ORFL did not pass complete FlightLog preflight: " + str(checked.get("error", "unknown error"))}
	if int(checked.rows) != requested_ticks + 1 or faults != "" or crashed or recorder.failure != "":
		return {"ok": false, "error": "Fresh runway tape did not finish the full requested interval without a fault/crash."}
	return {
		"ok": true,
		"recording": {
			"source": path,
			"source_sha256": FileAccess.get_sha256(path),
			"aircraft_kind": aircraft_kind,
			"complete": true,
			"rows": int(checked.rows),
			"first_tick": int(checked.first_tick),
			"final_tick": int(checked.footer.final_tick),
			"engine": Engine.get_version_info().string,
			"dt_s": float(checked.header.dt_s),
			"solver_sha256": Log.solver_identity(),
			"aircraft_path": str(checked.header.aircraft_path),
			"aircraft_identity": checked.header.aircraft.get("input_identity", {}),
			"configuration": str(checked.header.metadata.get("configuration", "")),
			"ground_field_id": str(checked.header.ground_field_id),
			"ground_description": str(checked.header.metadata.get("ground", "")),
			"launch_choice": str(checked.header.metadata.get("launch_choice", "")),
			"launch_ground_anchors": str(checked.header.metadata.get("launch_ground_anchors", "")),
			"initial_gear_compressions_m": initial_compressions,
			"initial_contact_indices": initial_contacts,
			"final_gear_compressions_m": final_compressions,
			"final_contact_indices": final_contacts,
			"capture_kind": "existing FlightLog API; scripted fixed-step neutral-input recording",
			"purpose": "software state/contact invariance only; not physical or owner acceptance",
		},
	}


func _positive_indices(values: PackedFloat64Array) -> Array[int]:
	var result: Array[int] = []
	for index in values.size():
		if values[index] > 1.0e-5:
			result.append(index)
	return result


func _rc_state_probe() -> Dictionary:
	# Exercise the existing RC vehicle recorder, checkpoint and replay APIs under
	# a deterministic GDScript backend, without starting the staged native module.
	if not RCVDynamics.set_backend_override_for_tests(RCVDynamics.BACKEND_GDSCRIPT_REFERENCE):
		return {"ok": false, "error": "Could not select the GDScript-only RC session backend."}
	var vehicles: Dictionary = {}
	var error := ""
	for vehicle_id: String in RC_VEHICLE_IDS:
		var vehicle_result := _rc_vehicle_probe(vehicle_id)
		if not vehicle_result.get("ok", false):
			error = str(vehicle_result.get("error", "RC vehicle state probe failed for " + vehicle_id))
			break
		vehicles[vehicle_id] = vehicle_result.evidence
	var backend_identity: Dictionary = RCVDynamics.backend_identity()
	RCVDynamics.set_backend_override_for_tests("")
	if not error.is_empty():
		return {"ok": false, "error": error}
	return {"ok": true, "result": {
		"backend": str(backend_identity.get("backend", "")),
		"backend_identity": backend_identity,
		"vehicle_ids": RC_VEHICLE_IDS,
		"vehicles": vehicles,
		"native_backend_used": false,
	}}


func _rc_vehicle_probe(vehicle_id: String) -> Dictionary:
	var source = RCVSession.new()
	var fork = RCVSession.new()
	var error := ""
	var evidence: Dictionary = {}
	if not source.prepare_default({}, vehicle_id):
		error = "RC ground-vehicle session did not prepare for %s." % vehicle_id
	else:
		var neutral := {"throttle": 0.0, "steering": 0.0, "brake": 0.0, "reverse": false,
			"source": "keyboard", "armed": true}
		if not source.tick_once(neutral) or not source.resume():
			error = "RC ground-vehicle session did not arm and resume for %s." % vehicle_id
		var checkpoint: Dictionary = source.checkpoint() if error.is_empty() else {}
		if error.is_empty() and (checkpoint.is_empty() or not source.start_recording()):
			error = "RC recorder did not start from a complete %s checkpoint." % vehicle_id
		var tick_count := 240
		if error.is_empty():
			for tick in tick_count:
				var controls := {"throttle": 0.22 if tick < 180 else 0.0,
					"steering": 0.06 if tick < 120 else -0.04, "brake": 0.0,
					"reverse": false, "source": "keyboard", "armed": true}
				if not source.tick_once(controls):
					error = "%s RC recorder stopped accepting its deterministic control tape at tick %d." % [vehicle_id, tick]
					break
		if source.recording and not source.stop_recording() and error.is_empty():
			error = "%s RC recorder did not close its complete sample stream." % vehicle_id
		if error.is_empty():
			var expected_state: PackedFloat64Array = source.state_snapshot()
			var expected_damage: PackedFloat64Array = source.damage_snapshot()
			var expected_tape: PackedFloat64Array = source.control_tape_snapshot()
			var expected_events: Array[Dictionary] = source.event_tape_snapshot()
			var expected_samples: PackedFloat64Array = source._record_samples.duplicate()
			var identities: Dictionary = source.identities_snapshot()
			var restored: bool = fork.prepare_default({}, vehicle_id) and fork.restore_checkpoint(checkpoint)
			var replayed: bool = restored and fork.replay(expected_tape)
			var exact := replayed and fork.state_snapshot().to_byte_array() == expected_state.to_byte_array() \
				and fork.damage_snapshot().to_byte_array() == expected_damage.to_byte_array() \
				and fork.control_tape_snapshot().to_byte_array() == expected_tape.to_byte_array() \
				and fork.event_tape_snapshot() == expected_events
			if not exact:
				error = "%s RC session replay did not reproduce state, damage, controls and events exactly." % vehicle_id
			else:
				var trace_bytes := var_to_bytes([identities, expected_samples, expected_state,
					expected_damage, expected_tape, expected_events])
				evidence = {
					"vehicle_id": str(identities.get("vehicle_id", "")),
					"backend": str(RCVDynamics.backend_identity().get("backend", "")),
					"backend_identity": RCVDynamics.backend_identity(),
					"ticks": tick_count,
					"recorded_samples": source._recording_sample_count(),
					"recording_complete": source._recording_sample_count() == tick_count + 1,
					"checkpoint_sha256": _sha256_text(JSON.stringify(checkpoint, "", true, true)),
					"model_identity": identities.get("model", {}),
					"course_identity": identities.get("course", {}),
					"recorded_samples_sha256": _sha256_bytes(expected_samples.to_byte_array()),
					"state_damage_controls_events_sha256": _sha256_bytes(trace_bytes),
					"checkpoint_control_tape_replay_exact": true,
					"recorder_api": "ground_vehicle.Session.start_recording/stop_recording",
					"replay_api": "ground_vehicle.Session.restore_checkpoint/replay",
					"native_backend_used": false,
				}
				if evidence.vehicle_id != vehicle_id:
					error = "Prepared RC vehicle identity %s does not match requested %s." % [evidence.vehicle_id, vehicle_id]
	source.free()
	fork.free()
	if not error.is_empty():
		return {"ok": false, "error": error}
	return {"ok": true, "evidence": evidence}


func _build_and_check_renderer(mode: String) -> Dictionary:
	var expect_enhanced := mode == "enhanced"
	var selected_enhanced := GrassQuality.enhanced()
	if selected_enhanced != expect_enhanced:
		return {"ok": false, "error": "OPENRC_GRASS_QUALITY does not select the requested mode."}
	var scenery_options := Scenery.options()
	if not bool(scenery_options.enabled) or str(scenery_options.quality) != "high" \
			or not bool(scenery_options.file_explicit) \
			or str(scenery_options.file) != "res://data/scenery/default.json":
		return {"ok": false, "error": "Renderer probe requires the explicit bundled scenery layout at high quality."}
	var loaded := FieldLoader.load_from()
	if not loaded.get("ok", false):
		return {"ok": false, "error": "Could not load default field: " + "; ".join(loaded.get("errors", PackedStringArray()))}
	# The default field's separate L6b tree line needs imported atlas resources and
	# is unrelated to grass. Keep the production field/surfaces and bundled scenery
	# layout, while omitting only this optional tree-only object for CPU headless runs.
	var render_field: Dictionary = loaded.field.duplicate(true)
	var omitted_objects: Array = render_field.get("objects", []) as Array
	var omitted_object_types: Array[String] = []
	for object_data: Dictionary in omitted_objects:
		omitted_object_types.append(str(object_data.get("type", "")))
	if omitted_object_types != ["treeline"]:
		return {"ok": false, "error": "Headless field probe only supports omitting the one tree-only Treeline.build object; found %s." % str(omitted_object_types)}
	render_field.objects = []
	var field_root := Field.build(render_field)
	if field_root == null:
		return {"ok": false, "error": "Production Field.build returned no field."}
	field_root.name = "GrassStateInvarianceField"
	get_root().add_child(field_root)
	var ground := field_root.get_node_or_null("rough") as MeshInstance3D
	var ground_material := ground.material_override as ShaderMaterial if ground != null else null
	if ground_material == null:
		field_root.free()
		return {"ok": false, "error": "Production rough-ground ShaderMaterial is unavailable."}
	var photo_enabled: bool = ground_material.get_shader_parameter("grass_photo_enabled") == true
	if photo_enabled != expect_enhanced:
		field_root.free()
		return {"ok": false, "error": "Effective rough-ground grass_photo_enabled does not match the selected mode."}
	var near_grass := field_root.find_child("NearGrass", true, false) as Node3D
	if near_grass == null or not bool(near_grass.get_meta("imported", false)):
		field_root.free()
		return {"ok": false, "error": "Production imported NearGrass root was not built."}
	var expected_counts: Dictionary = EXPECTED_COUNTS[mode]
	var observed_counts: Dictionary = {}
	var material_paths: Array[String] = []
	var material_route_ok := true
	for child: Node in near_grass.get_children():
		if not child is MultiMeshInstance3D:
			material_route_ok = false
			continue
		var batch := child as MultiMeshInstance3D
		var asset_id := str(batch.name).get_slice("_Part_", 0)
		observed_counts[asset_id] = batch.multimesh.instance_count if batch.multimesh != null else -1
		var mesh := batch.multimesh.mesh if batch.multimesh != null else null
		if mesh == null or mesh.get_surface_count() < 1:
			material_route_ok = false
			continue
		for surface_index in range(mesh.get_surface_count()):
			var material := mesh.surface_get_material(surface_index)
			if expect_enhanced:
				var shader_material := material as ShaderMaterial
				var shader := shader_material.shader if shader_material != null else null
				var path := shader.resource_path if shader != null else ""
				material_paths.append(path)
				material_route_ok = material_route_ok and path == "res://scenery/imported_grass.gdshader"
			else:
				material_paths.append(material.get_class() if material != null else "null")
				material_route_ok = material_route_ok and material is StandardMaterial3D
	var count_ok := observed_counts == expected_counts \
		and int(near_grass.get_meta("clumps", -1)) == 150 \
		and near_grass.get_child_count() == 3
	if not count_ok or not material_route_ok:
		field_root.free()
		return {"ok": false, "error": "Effective imported-grass batches/counts/materials failed the %s contract (counts=%s)." % [mode, str(observed_counts)]}
	return {
		"ok": true,
		"field_root": field_root,
		"observed": {
			"selector": OS.get_environment("OPENRC_GRASS_QUALITY"),
			"enhanced": selected_enhanced,
			"scene_tree_initialized": true,
			"field_id": str(render_field.get("id", "")),
			"tree_only_objects_omitted_for_headless_probe": omitted_objects.size(),
			"tree_only_object_types_omitted": omitted_object_types,
			"tree_branch_omission_scope": "one default-field treeline object passed to Treeline.build; field surfaces and flight cues remain present",
			"bundled_scenery_file": str(scenery_options.file),
			"scenery_enabled": bool(scenery_options.enabled),
			"scenery_quality": str(scenery_options.quality),
			"scenery_file_explicit": bool(scenery_options.file_explicit),
			"rough_material_shader": ground_material.shader.resource_path if ground_material.shader != null else "",
			"rough_grass_photo_enabled": photo_enabled,
			"near_grass_imported": true,
			"near_grass_clumps": int(near_grass.get_meta("clumps", -1)),
			"near_grass_source_triangles": int(near_grass.get_meta("source_triangles", -1)),
			"near_grass_counts_by_asset": observed_counts,
			"near_grass_material_paths_or_types": material_paths,
			"material_route_ok": material_route_ok,
			"field_built_in_same_process_as_replay": true,
			"gpu_frame_rendered": false,
		},
	}


func _exact_replay(path: String, csv_path: String) -> Dictionary:
	var source_sha256 := FileAccess.get_sha256(path)
	if source_sha256.is_empty():
		return {"ok": false, "error": "Cannot hash source ORFL."}
	var checked := Reader.inspect(path, false)
	if not checked.get("ok", false):
		return {"ok": false, "error": "ORFL preflight failed: " + str(checked.get("error", "unknown error"))}
	if not bool(checked.get("complete", false)):
		return {"ok": false, "error": "Exact replay refuses an incomplete or recovered prefix."}
	var header: Dictionary = checked.header
	var prepared := Reader.prepare_replay(header)
	if not prepared.get("ok", false):
		return {"ok": false, "error": "Exact replay setup refused: " + str(prepared.get("error", "unknown error"))}
	var flight: Node = prepared.flight
	var csv := FileAccess.open(csv_path, FileAccess.WRITE)
	if csv == null:
		flight.free()
		return {"ok": false, "error": "Cannot create replay CSV."}
	csv.store_csv_line(Reader.columns(header.layout))
	var input := FileAccess.open(path, FileAccess.READ)
	if input == null:
		csv.close()
		flight.free()
		return {"ok": false, "error": "Cannot reopen source ORFL."}
	input.seek(8)
	var header_packet := Log.read_packet(input)
	if not header_packet.get("ok", false):
		input.close()
		csv.close()
		flight.free()
		return {"ok": false, "error": "Cannot read preflighted ORFL header."}
	var observer: RefCounted = Log.new(flight)
	var first := true
	var rows := 0
	var error := ""
	while input.get_position() < input.get_length():
		var packet := Log.read_packet(input)
		if not packet.get("ok", false):
			error = str(packet.get("error", "Invalid ORFL packet during replay."))
			break
		if packet.value.kind == "footer":
			break
		for row: Dictionary in packet.value.rows:
			var output := row
			if first:
				output = observer._sample({})
			else:
				for key: String in row.intervention:
					flight.sim.set(key, row.intervention[key].duplicate())
				flight.sim.inputs = row.inputs.duplicate()
				flight.sim.step()
				if not flight.sim.fault_reason.is_empty() or flight.sim.tick != row.tick:
					error = "Replay stopped at tick %d: %s" % [row.tick, flight.sim.fault_reason]
					break
				output = observer._sample(row.intervention)
			output.raw = row.raw
			output.sticks = row.sticks
			if error.is_empty():
				error = Reader.disagreement(row, output)
			if not error.is_empty():
				break
			Reader.write_row(csv, output, float(header.dt_s), int(checked.first_tick))
			rows += 1
			first = false
		if not error.is_empty():
			break
	if csv.get_error() != OK:
		error = "Replay CSV write failed."
	csv.close()
	input.close()
	flight.free()
	if error.is_empty() and rows != int(checked.rows):
		error = "Replay row count differs from complete ORFL preflight."
	if error.is_empty() and FileAccess.get_sha256(path) != source_sha256:
		error = "Source ORFL changed during replay."
	if not error.is_empty():
		return {"ok": false, "error": error}
	var checkpoint_text := JSON.stringify(header.checkpoint, "", true, true)
	var checkpoint_hash := _sha256_text(checkpoint_text)
	var metadata: Dictionary = header.metadata
	var current_solver := Log.solver_identity()
	var baseline_solver := str(header.solver_sha256)
	var replay_result := {
		"source_sha256": source_sha256,
		"complete": true,
		"mode": "exact",
		"rows": int(checked.rows),
		"first_tick": int(checked.first_tick),
		"final_tick": int(checked.footer.final_tick),
		"engine": Engine.get_version_info().string,
		"dt_s": float(header.dt_s),
		"baseline_solver_sha256": baseline_solver,
		"current_solver_sha256": current_solver,
		"solver_changed": baseline_solver != current_solver,
		"checkpoint_sha256": checkpoint_hash,
		"aircraft_path": str(header.aircraft_path),
		"aircraft_identity": header.aircraft.get("input_identity", {}),
		"configuration": str(metadata.get("configuration", "")),
		"ground_field_id": str(header.ground_field_id),
		"ground_surfaces": header.ground_surfaces,
		"ground_description": str(metadata.get("ground", "")),
		"collision_world_identity": str(metadata.get("collision_world_identity", header.collision_world.get("identity", ""))),
		"lake_id": str(header.lake.get("id", "")),
		"events": checked.events,
		"compared_fields": ["state", "loads", "inputs", "aux", "continuous", "modes", "air"],
	}
	if baseline_solver != current_solver:
		return {"ok": false, "error": "Solver identity changed during exact replay; no invariance result claimed."}
	return {"ok": true, "result": replay_result}


func _sha256_text(value: String) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	context.update(value.to_utf8_buffer())
	return context.finish().hex_encode()


func _sha256_bytes(value: PackedByteArray) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	context.update(value)
	return context.finish().hex_encode()


func _canonical_path(path: String) -> String:
	return ProjectSettings.globalize_path(path).simplify_path().to_lower()


func _fail(message: String) -> void:
	report.status = "error"
	report.error = message
	_write_report()
	printerr(message)
	quit(1)


func _write_report() -> void:
	var report_path := str(options.get("report", ""))
	if report_path.is_empty() or FileAccess.file_exists(report_path):
		return
	var parent := report_path.get_base_dir()
	var error := DirAccess.make_dir_recursive_absolute(parent)
	if error != OK and not DirAccess.dir_exists_absolute(parent):
		printerr("Could not create report directory: " + parent)
		return
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	if file == null:
		printerr("Could not write replay report: " + report_path)
		return
	file.store_string(JSON.stringify(report, "\t", true, true) + "\n")
	file.close()
