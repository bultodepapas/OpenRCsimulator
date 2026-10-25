## FUEL-12 research-only bridge for the frozen, line-free Stik MAX-61FX v2 recording.
## This is a one-aircraft counterfactual mapper, not a production compatibility reader.
extends SceneTree

const Log := preload("res://sim/flight_log.gd")
const Reader := preload("res://tools/flight_log_cli.gd")
const Flight := preload("res://sim/flight_session.gd")
const Data := preload("res://physics/aircraft_data.gd")
const Glow := preload("res://physics/glow/flight.gd")
const RB := preload("res://physics/rigid_body.gd")

const SOURCE_AIRCRAFT := "res://data/aircraft/stik_glow_61fx_2t.json"
const V2_LAW := "glow-mean-cycle-finite-tank-hub-inflow-v2"
const V3_LAW := "glow-mean-cycle-finite-tank-line-pickup-v3"
const SOURCE_ORFL_SHA256 := "9d4204c0f2919e48b2e2cb0ff34725744935febb345be7cac0434a9b8c824cf8"
const SOURCE_SOLVER_SHA256 := "dc05854341fa4e8a5a29e06c0e855ce6c76ac259694c659b6e0c08a255cad66f"
const INPUT_SHA256 := "c29f86fa72b89cd7f46206da875f28632229e5892c2db60a692959f472a73f6a"
const INSTALL_SHA256 := "e3157d77fe82a02dcac2dfc17faad3bd40b2e099fcecbda21c07c306b3ef7233"
const PROFILE_SHA256 := "f3a8fcd246e45bd37d586f5ef90fc978a2ead9fda1a2936d4177344e9987ca54"
const REGISTRY_SHA256 := "cae59374afdc9345a05774342c9c9be1fdec8573f6f75c97eed8aae6257d5df1"
const OLD_CORE_SIZE := 17
const OLD_LAYOUT_SIZE := 20 # 17 v2 Glow values followed by three wheel rim speeds.
const OLD_ROW_COUNT := 261
const EXPECTED_FINAL_TICK := 260

var options: Dictionary = {}
var _error := ""


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		var pair := argument.trim_prefix("--").split("=", true, 1)
		options[pair[0]] = pair[1] if pair.size() > 1 else true
	call_deferred("_run")


func _run() -> void:
	var source_path := str(options.get("source", ""))
	var candidate_path := str(options.get("candidate", SOURCE_AIRCRAFT))
	if source_path.is_empty():
		_finish_error("Required: --source=<frozen .orfl> [--candidate=res://data/aircraft/stik_glow_61fx_2t.json] [--out=<new evidence directory>] [--check-only]")
		return
	if candidate_path != SOURCE_AIRCRAFT:
		_finish_error("This research bridge is restricted to the frozen Stik MAX-61FX aircraft path.")
		return
	if not options.has("check-only") and str(options.get("out", "")).is_empty():
		_finish_error("A new output directory is required: --out=<new evidence directory>.")
		return
	var source_sha256 := FileAccess.get_sha256(source_path)
	if source_sha256.is_empty():
		_finish_error("Cannot hash the protected baseline ORFL.")
		return
	if source_sha256 != SOURCE_ORFL_SHA256:
		_finish_error("Source ORFL hash differs from the protected 61FX baseline; refusing to map it.")
		return
	var checked: Dictionary = Reader.inspect(source_path)
	if not checked.get("ok", false) or not checked.get("complete", false):
		_finish_error("Protected baseline must pass complete bounded ORFL inspection: " + str(checked.get("error", "incomplete")))
		return
	var header: Dictionary = checked.header
	var source_rows_result := _read_rows(source_path)
	if not source_rows_result.get("ok", false):
		_finish_error(str(source_rows_result.get("error", "Cannot read baseline samples.")))
		return
	var source_rows: Array = source_rows_result.rows
	if source_rows.size() != OLD_ROW_COUNT or int(checked.first_tick) != 0 \
			or int(checked.footer.final_tick) != EXPECTED_FINAL_TICK:
		_finish_error("Protected baseline is not the expected complete 0..260, 261-row Stik tape.")
		return
	var identity_error := _validate_source(header, source_rows)
	if not identity_error.is_empty():
		_finish_error(identity_error)
		return
	var candidate_data: Dictionary = Data.load_file(candidate_path)
	if not candidate_data.get("ok", false):
		_finish_error("Current Stik candidate data is invalid: " + str(candidate_data.get("errors", [])))
		return
	var candidate_flight: Node = _new_flight(header, candidate_data)
	if candidate_flight == null:
		_finish_error("Could not build a fresh current-law Stik session for the mapping check.")
		return
	var candidate_checkpoint: Dictionary = candidate_flight.checkpoint()
	var mapping_error := _validate_candidate(header, source_rows, candidate_data, candidate_checkpoint)
	if not mapping_error.is_empty():
		candidate_flight.free()
		_finish_error(mapping_error)
		return
	var adapted_header := _adapt_header(header, source_rows[0], candidate_checkpoint,
		float(candidate_flight.aircraft.model.propulsion.glow.capacity_fuel_kg))
	var restored: Dictionary = Reader.prepare_replay(adapted_header, candidate_path)
	if not restored.get("ok", false):
		candidate_flight.free()
		_finish_error("Mapped checkpoint restore refused: " + str(restored.get("error", "unknown error")))
		return
	candidate_flight.free()
	candidate_flight = restored.flight
	if not _mapped_boundary_matches(source_rows[0], candidate_flight):
		candidate_flight.free()
		_finish_error("Current restore did not preserve the mapped tick-zero boundary.")
		return
	if options.has("check-only"):
		print(JSON.stringify({
			"status": "preflight_ok",
			"source_sha256": source_sha256,
			"source_solver_sha256": header.solver_sha256,
			"candidate_solver_sha256": Log.solver_identity(),
			"solver_changed": header.solver_sha256 != Log.solver_identity(),
			"rows": source_rows.size(),
			"source_law": V2_LAW,
			"candidate_law": Glow.LAW,
			"mapped_continuous_size": candidate_checkpoint.simulation.continuous.size(),
			"mapping": "copy v2 slots 0..16; insert feed-line mass 0 kg and MAIN source mode at slots 17..18; shift the three wheel speeds to 19..21",
			"selection_known": false,
			"fuel_above_unusable_all_rows": true,
		}, "\t", true, true))
		candidate_flight.free()
		quit(0)
		return
	var output_dir := str(options.out)
	if DirAccess.dir_exists_absolute(output_dir) or FileAccess.file_exists(output_dir):
		candidate_flight.free()
		_finish_error("Output directory already exists; refusing to overwrite: " + output_dir)
		return
	var make_error := DirAccess.make_dir_recursive_absolute(output_dir)
	if make_error != OK:
		candidate_flight.free()
		_finish_error("Cannot create output directory (%d)." % make_error)
		return
	var artifact_paths := {
		"baseline_orfl": output_dir.path_join("stik-61fx-glow-v2-baseline.orfl"),
		"candidate_orfl": output_dir.path_join("stik-61fx-glow-v2-to-v3-candidate.orfl"),
		"candidate_csv": output_dir.path_join("candidate.csv"),
		"baseline_csv": output_dir.path_join("baseline.csv"),
		"comparison_csv": output_dir.path_join("comparison.csv"),
		"report_json": output_dir.path_join("report.json"),
	}
	for artifact_path: String in artifact_paths.values():
		if FileAccess.file_exists(artifact_path):
			candidate_flight.free()
			_finish_error("Output artifact already exists; refusing to overwrite: " + artifact_path)
			return
	var candidate_solver := Log.solver_identity()
	if candidate_solver == header.solver_sha256:
		candidate_flight.free()
		_finish_error("Expected a changed solver identity for the v2-to-v3 counterfactual.")
		return
	var baseline_bytes := FileAccess.get_file_as_bytes(source_path)
	var baseline_copy := FileAccess.open(artifact_paths.baseline_orfl, FileAccess.WRITE)
	if baseline_bytes.is_empty() or baseline_copy == null:
		candidate_flight.free()
		_finish_error("Cannot make the protected baseline ORFL evidence copy.")
		return
	baseline_copy.store_buffer(baseline_bytes)
	baseline_copy.close()
	if FileAccess.get_sha256(artifact_paths.baseline_orfl) != source_sha256:
		candidate_flight.free()
		_finish_error("Baseline ORFL evidence copy is not byte-identical to the protected source.")
		return
	var run_result := _run_candidate(candidate_flight, source_rows, artifact_paths.candidate_orfl)
	if not run_result.get("ok", false):
		_finish_error(str(run_result.get("error", "Candidate run failed.")))
		return
	var candidate_checked: Dictionary = Reader.inspect(artifact_paths.candidate_orfl)
	if not candidate_checked.get("ok", false) or not candidate_checked.get("complete", false) \
			or int(candidate_checked.rows) != OLD_ROW_COUNT or int(candidate_checked.footer.final_tick) != EXPECTED_FINAL_TICK:
		_finish_error("Candidate ORFL did not complete the full absolute tick tape: " + str(candidate_checked.get("error", "coverage mismatch")))
		return
	var candidate_header: Dictionary = candidate_checked.header
	if candidate_header.solver_sha256 != candidate_solver or Log.solver_identity() != candidate_solver:
		_finish_error("Candidate runtime source changed during recording; do not compare this artifact.")
		return
	var candidate_rows_result := _read_rows(artifact_paths.candidate_orfl)
	if not candidate_rows_result.get("ok", false):
		_finish_error(str(candidate_rows_result.get("error", "Cannot read candidate samples.")))
		return
	var candidate_rows: Array = candidate_rows_result.rows
	var tape_error := _validate_tape(source_rows, candidate_rows)
	if not tape_error.is_empty():
		_finish_error(tape_error)
		return
	var exact_result := _verify_exact_replay(candidate_header, candidate_rows)
	if not exact_result.get("ok", false):
		_finish_error("New candidate ORFL did not exact-replay: " + str(exact_result.get("error", "unknown divergence")))
		return
	var csv_error := _write_full_csv(artifact_paths.candidate_csv, candidate_header.layout, candidate_rows, float(candidate_header.dt_s))
	if not csv_error.is_empty():
		_finish_error(csv_error)
		return
	csv_error = _write_full_csv(artifact_paths.baseline_csv, header.layout, source_rows, float(header.dt_s))
	if not csv_error.is_empty():
		_finish_error(csv_error)
		return
	var comparison := _comparison_metrics(source_rows, candidate_rows)
	csv_error = _write_comparison_csv(artifact_paths.comparison_csv, source_rows, candidate_rows)
	if not csv_error.is_empty():
		_finish_error(csv_error)
		return
	if FileAccess.get_sha256(source_path) != source_sha256:
		_finish_error("Protected baseline ORFL changed during the research run.")
		return
	var report := _build_report(header, candidate_header, checked, candidate_checked, source_sha256,
		candidate_solver, exact_result, comparison, artifact_paths)
	var report_file := FileAccess.open(artifact_paths.report_json, FileAccess.WRITE)
	if report_file == null:
		_finish_error("Cannot write report.json.")
		return
	report_file.store_string(JSON.stringify(report, "\t", true, true) + "\n")
	report_file.close()
	print(JSON.stringify(report, "\t", true, true))
	quit(0)


func _validate_source(header: Dictionary, rows: Array) -> String:
	if header.get("aircraft_path") != SOURCE_AIRCRAFT:
		return "Protected baseline is not the canonical Stik MAX-61FX aircraft path."
	if header.get("engine") != Engine.get_version_info().string:
		return "Godot engine version differs from the frozen baseline."
	if header.get("dt_s") != 1.0 / Engine.physics_ticks_per_second:
		return "The protected baseline timestep differs from the current fixed tick."
	if header.get("solver_sha256", "") != SOURCE_SOLVER_SHA256 or header.solver_sha256 == Log.solver_identity():
		return "The protected source must have a solver fingerprint different from the candidate."
	if header.get("layout", {}).get("continuous") != OLD_LAYOUT_SIZE \
			or header.get("checkpoint", {}).get("simulation", {}).get("continuous", PackedFloat64Array()).size() != OLD_LAYOUT_SIZE:
		return "Protected source is not the expected 17-value Glow v2 plus three-wheel layout."
	if header.get("metadata", {}).get("propulsion_model") != V2_LAW \
			or header.get("checkpoint", {}).get("glow_law") != V2_LAW:
		return "Protected source is not the frozen finite-tank Glow v2 law."
	if not str(header.get("metadata", {}).get("continuous_layout", "")).begins_with("rpm; fuel kg, temperature K, servo, admission, fuel transport kg/s, crank revolutions;"):
		return "Protected source continuous-layout identity does not describe the v2 Glow state."
	if not header.get("metadata", {}).has("wheel_state_layout"):
		return "Protected v2 source lacks the wheel-layout identity required by the explicit shift."
	var old_wheels: Variant = JSON.parse_string(str(header.metadata.wheel_state_layout))
	if not old_wheels is Array or old_wheels.size() != 3:
		return "Protected source must have exactly three wheel states after its v2 Glow slots."
	for i in old_wheels.size():
		if int(old_wheels[i].get("index", -1)) != OLD_CORE_SIZE + i:
			return "Protected source wheel-state indexes are not the expected old tail layout."
	var aircraft: Dictionary = header.get("aircraft", {})
	var model: Dictionary = aircraft.get("model", {})
	var glow: Dictionary = model.get("propulsion", {}).get("glow", {})
	if aircraft.get("input_identity", {}).get("sha256", "") != INPUT_SHA256 \
			or str(header.get("metadata", {}).get("aircraft_input_sha256", "")) != INPUT_SHA256:
		return "Protected baseline aircraft input hash does not match the reviewed 61FX source."
	if glow.get("identity", {}).get("sha256", "") != INSTALL_SHA256 \
			or glow.get("identity", {}).get("profile", {}).get("sha256", "") != PROFILE_SHA256:
		return "Protected baseline Glow installation/profile identity differs from the reviewed 61FX pair."
	var fuel_system: Dictionary = model.get("fuel_system", {})
	var tanks: Variant = fuel_system.get("tanks", null)
	if fuel_system.get("registry_sha256", "") != REGISTRY_SHA256 or not tanks is Array or tanks.size() != 1 \
			or not tanks[0] is Dictionary:
		return "Protected baseline must contain the reviewed registry-backed single main tank."
	var old_tank: Dictionary = tanks[0]
	if old_tank.get("id") != "main_tank" or old_tank.get("liquid_inventory_id") != "item_fuel_main" \
			or old_tank.has("feed_line") or old_tank.has("pickup_position_inventory_le_m"):
		return "Protected baseline is not a line-free, source-free main-tank case."
	for row: Dictionary in rows:
		if row.continuous.size() != OLD_LAYOUT_SIZE or not is_finite(float(row.continuous[1])) \
				or float(row.continuous[1]) <= float(old_tank.get("unusable_kg", INF)):
			return "Source row %d reaches or crosses the unusable-fuel boundary; old v2 residue semantics cannot be mapped." % int(row.get("tick", -1))
	return ""


func _validate_candidate(header: Dictionary, source_rows: Array, candidate_data: Dictionary, candidate_checkpoint: Dictionary) -> String:
	if not candidate_data.get("ok", false) or candidate_data.get("input_identity", {}).get("sha256", "") != INPUT_SHA256:
		return "Current candidate does not load the exact frozen Stik aircraft bytes."
	var old_model: Dictionary = header.aircraft.model
	var new_model: Dictionary = candidate_data.model
	for key: String in ["mass_kg", "inertia", "cg_le", "reference", "landing_gear", "wheel_profile"]:
		if not old_model.has(key) or not new_model.has(key) or var_to_bytes(old_model[key]) != var_to_bytes(new_model[key]):
			return "Candidate physical aircraft geometry/mass identity differs in '%s'." % key
	var old_glow: Dictionary = old_model.propulsion.glow
	var new_glow: Dictionary = new_model.propulsion.glow
	if new_glow.get("identity", {}).get("sha256", "") != INSTALL_SHA256 \
			or new_glow.get("identity", {}).get("profile", {}).get("sha256", "") != PROFILE_SHA256:
		return "Current candidate Glow installation/profile identity differs from the protected baseline."
	var old_system: Dictionary = old_model.get("fuel_system", {})
	var new_system: Dictionary = new_model.get("fuel_system", {})
	if old_system.get("registry_sha256", "") != new_system.get("registry_sha256", "") \
			or new_system.get("registry_sha256", "") != REGISTRY_SHA256:
		return "Fuel-registry identity changed between baseline and candidate."
	var old_tanks: Variant = old_system.get("tanks", null)
	var new_tanks: Variant = new_system.get("tanks", null)
	if not old_tanks is Array or old_tanks.size() != 1 or not new_tanks is Array or new_tanks.size() != 1:
		return "The 61FX comparison requires exactly one normalized main tank on each side."
	if _tank_signature(old_tanks[0]) != _tank_signature(new_tanks[0]):
		return "Main-tank ID, blend, density, capacity, unusable amount, fill, or inventory bindings differ."
	if old_tanks[0].has("feed_line") or old_tanks[0].has("pickup_position_inventory_le_m") \
			or new_tanks[0].has("feed_line") or new_tanks[0].has("pickup_position_inventory_le_m") \
			or new_glow.has("feed_line") or new_glow.has("pickup_position"):
		return "This mapping only covers line-free, unmodified tank-pickup geometry."
	if absf(float(new_glow.get("capacity_fuel_kg", NAN)) - float(old_tanks[0].capacity_kg)) > 1e-12 \
			or absf(float(new_glow.get("reference_fuel_kg", NAN)) - float(old_tanks[0].liquid_mass_kg)) > 1e-12 \
			or absf(float(new_glow.get("unusable_fuel_kg", NAN)) - float(old_tanks[0].unusable_kg)) > 1e-12 \
			or absf(float(new_glow.get("total_capacity_kg", NAN)) - float(new_glow.capacity_fuel_kg)) > 1e-12:
		return "Current Glow adapter does not preserve the same main resource mass/capacity."
	if candidate_checkpoint.is_empty() or candidate_checkpoint.get("glow_law") != V3_LAW \
			or candidate_checkpoint.get("simulation", {}).get("continuous", PackedFloat64Array()).size() != 22:
		return "Current Stik checkpoint does not expose the expected 19 Glow values plus three wheel states."
	var old_sim: Dictionary = header.checkpoint.simulation
	var new_sim: Dictionary = candidate_checkpoint.simulation
	for key: String in ["tick", "dt", "state", "previous", "aux", "inputs", "modes", "mass", "inertia", "gravity"]:
		if not old_sim.has(key) or not new_sim.has(key) or var_to_bytes(old_sim[key]) != var_to_bytes(new_sim[key]):
			return "Candidate fresh tick-zero body/checkpoint differs in '%s'." % key
	if old_sim.continuous.size() != OLD_LAYOUT_SIZE or new_sim.continuous.size() != 22:
		return "Unexpected tick-zero continuous layout before adaptation."
	if var_to_bytes(_map_continuous(old_sim.continuous)) != var_to_bytes(new_sim.continuous):
		return "The fresh current candidate's initial internal state is not the exact declared v2-to-v3 map."
	var fill := float(old_sim.continuous[1]) / float(new_glow.capacity_fuel_kg)
	if not is_finite(fill) or fill <= 0.0 or fill > 1.0 \
			or float(old_sim.continuous[1]) <= float(new_glow.unusable_fuel_kg):
		return "Tick-zero fuel cannot be represented by a valid current start-fill boundary."
	if absf(float(source_rows[0].continuous[1]) - float(old_sim.continuous[1])) > 0.0:
		return "Baseline row zero does not match the checkpoint's exact initial main-tank amount."
	var old_wheel_profile := str(header.checkpoint.get("wheel_profile_sha256", ""))
	var new_wheel_profile := str(candidate_checkpoint.get("wheel_profile_sha256", ""))
	if old_wheel_profile.is_empty() or old_wheel_profile != new_wheel_profile \
			or str(header.checkpoint.get("wheel_profile_input_sha256", "")) != str(candidate_checkpoint.get("wheel_profile_input_sha256", "")):
		return "Wheel profiles differ, so the v2-tail to v3-tail shift is not justified."
	return ""


func _new_flight(header: Dictionary, candidate_data: Dictionary) -> Node:
	var flight: Node = Flight.new()
	flight.input_enabled = false
	flight.crash_auto_restart = false
	flight.soft_hull_contacts = bool(header.soft_hull_contacts)
	flight.setup(SOURCE_AIRCRAFT, "", candidate_data)
	flight.ground_surfaces = header.ground_surfaces.duplicate()
	flight.airframe_surfaces = header.get("airframe_surfaces", PackedFloat64Array()) # GP-07c
	flight.ground_field_id = str(header.ground_field_id)
	var ready: bool = flight.setup_shaft_integrator(str(header.shaft_integrator)) \
		and flight.setup_weather(header.weather) and flight.set_collision_world(header.collision_world) \
		and flight.set_lake_context(header.lake)
	flight.reset()
	if not ready or not flight.physics_enabled or flight.sim == null:
		flight.free()
		return null
	return flight


func _tank_signature(tank: Dictionary) -> Dictionary:
	var keys := ["id", "fuel", "family", "density_kg_m3", "capacity_m3", "capacity_kg", "unusable_kg",
		"liquid_inventory_id", "shell_inventory_id", "liquid_mass_kg", "start_fill", "pickup", "feed"]
	var signature := {}
	for key: String in keys:
		if not tank.has(key):
			return {}
		signature[key] = tank[key]
	return signature


func _map_continuous(old: PackedFloat64Array) -> PackedFloat64Array:
	if old.size() != OLD_LAYOUT_SIZE:
		return PackedFloat64Array()
	var mapped := PackedFloat64Array()
	for i in OLD_CORE_SIZE:
		mapped.append(old[i])
	mapped.append(0.0) # no authored line inventory in either frozen/candidate Stik data.
	mapped.append(float(Glow.MODE_MAIN_TANK))
	for i in range(OLD_CORE_SIZE, old.size()):
		mapped.append(old[i])
	return mapped


func _adapt_header(header: Dictionary, first_row: Dictionary, candidate_checkpoint: Dictionary, capacity_kg: float) -> Dictionary:
	var adapted: Dictionary = header.duplicate(true)
	adapted.checkpoint = header.checkpoint.duplicate(true)
	adapted.checkpoint.configuration = candidate_checkpoint.configuration
	adapted.checkpoint.glow_law = V3_LAW
	adapted.checkpoint.wheel_state_layout = candidate_checkpoint.wheel_state_layout
	adapted.checkpoint.simulation.continuous = _map_continuous(first_row.continuous)
	# The frozen v2 checkpoint predates fill-selection provenance. Carry the measured tick-zero fill ratio,
	# but state plainly that the launch selection itself is unknown.
	adapted.checkpoint.fuel_session = {
		"format": Flight.FUEL_SESSION_FORMAT,
		"start_fill": float(first_row.continuous[1]) / capacity_kg,
		"selection_known": false,
	}
	adapted.layout = header.layout.duplicate(true)
	adapted.layout.continuous = candidate_checkpoint.simulation.continuous.size()
	return adapted


func _mapped_boundary_matches(source_row: Dictionary, flight: Node) -> bool:
	var expected := _map_continuous(source_row.continuous)
	return flight.sim.tick == source_row.tick \
		and flight.sim.state.to_byte_array() == source_row.state.to_byte_array() \
		and flight.sim.inputs.to_byte_array() == source_row.inputs.to_byte_array() \
		and flight.sim.aux.to_byte_array() == source_row.aux.to_byte_array() \
		and flight.sim.modes.to_byte_array() == source_row.modes.to_byte_array() \
		and flight.sim.continuous.to_byte_array() == expected.to_byte_array()


func _run_candidate(flight: Node, source_rows: Array, destination: String) -> Dictionary:
	var recorder: RefCounted = Log.new(flight)
	var start_error: Error = recorder.start(destination)
	if start_error != OK:
		flight.free()
		return {ok = false, error = "Candidate recorder start failed: %d %s" % [start_error, recorder.failure]}
	if flight.sim.tick != int(source_rows[0].tick) \
			or flight.sim.inputs.to_byte_array() != source_rows[0].inputs.to_byte_array():
		recorder.stop("FUEL-12 initial boundary mismatch")
		flight.free()
		return {ok = false, error = "Candidate did not begin at the source absolute tick/input boundary."}
	for i in range(1, source_rows.size()):
		var row: Dictionary = source_rows[i]
		for key: String in row.intervention:
			var value: Variant = row.intervention[key].duplicate()
			if key == "continuous":
				value = _map_continuous(value)
				if value.size() != 22:
					recorder.stop("FUEL-12 intervention mapping failed")
					flight.free()
					return {ok = false, error = "Source continuous intervention has an unsupported layout."}
			flight.sim.set(key, value)
		flight.sim.inputs = row.inputs.duplicate()
		flight.sim.step()
		if not flight.sim.fault_reason.is_empty() or flight.sim.tick != int(row.tick):
			var reason: String = flight.sim.fault_reason
			recorder.stop("FUEL-12 counterfactual stopped: " + reason)
			flight.free()
			return {ok = false, error = "Candidate stopped before source tick %d: %s" % [int(row.tick), reason]}
		if flight.sim.inputs.to_byte_array() != row.inputs.to_byte_array():
			recorder.stop("FUEL-12 input tape mismatch")
			flight.free()
			return {ok = false, error = "Candidate did not preserve source inputs through tick %d." % int(row.tick)}
	var stop_error: Error = recorder.stop("FUEL-12 mapped counterfactual complete")
	if stop_error != OK:
		var reason: String = recorder.failure
		flight.free()
		return {ok = false, error = "Candidate recorder stop failed: %d %s" % [stop_error, reason]}
	var solver_after := Log.solver_identity()
	flight.free()
	if solver_after != recorder.header.solver_sha256:
		return {ok = false, error = "Solver sources changed while recording; candidate identity is unstable."}
	return {ok = true, candidate_solver_sha256 = solver_after}


func _read_rows(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {ok = false, error = "Cannot open ORFL samples: " + path}
	file.seek(8)
	var header_packet: Dictionary = Log.read_packet(file)
	if not header_packet.get("ok", false) or header_packet.value.get("kind") != "header":
		file.close()
		return {ok = false, error = "Invalid ORFL header while reading samples."}
	var rows: Array = []
	while file.get_position() < file.get_length():
		var packet: Dictionary = Log.read_packet(file)
		if not packet.get("ok", false):
			file.close()
			return {ok = false, error = str(packet.get("error", "Malformed ORFL packet."))}
		if packet.value.get("kind") == "footer":
			break
		if packet.value.get("kind") != "block":
			file.close()
			return {ok = false, error = "Unexpected ORFL packet kind while reading samples."}
		rows.append_array(packet.value.rows)
	file.close()
	return {ok = true, rows = rows}


func _validate_tape(source_rows: Array, candidate_rows: Array) -> String:
	if candidate_rows.size() != source_rows.size():
		return "Candidate sample count differs from the baseline tape."
	for i in source_rows.size():
		var old: Dictionary = source_rows[i]
		var now: Dictionary = candidate_rows[i]
		if int(now.tick) != int(old.tick) or now.inputs.to_byte_array() != old.inputs.to_byte_array():
			return "Candidate tick/input tape differs at row %d (tick %d)." % [i, int(old.tick)]
		if i == 0 and now.continuous.to_byte_array() != _map_continuous(old.continuous).to_byte_array():
			return "Candidate tick-zero state does not equal the exact declared v2-to-v3 mapping."
	return ""


func _verify_exact_replay(header: Dictionary, rows: Array) -> Dictionary:
	var prepared: Dictionary = Reader.prepare_replay(header)
	if not prepared.get("ok", false):
		return {ok = false, error = str(prepared.get("error", "Replay preflight refused."))}
	var flight: Node = prepared.flight
	var observer: RefCounted = Log.new(flight)
	for i in rows.size():
		var expected: Dictionary = rows[i]
		var actual: Dictionary
		if i == 0:
			actual = observer._sample({})
		else:
			for key: String in expected.intervention:
				flight.sim.set(key, expected.intervention[key].duplicate())
			flight.sim.inputs = expected.inputs.duplicate()
			flight.sim.step()
			if not flight.sim.fault_reason.is_empty() or flight.sim.tick != int(expected.tick):
				var reason: String = flight.sim.fault_reason
				flight.free()
				return {ok = false, error = "Replay stopped at tick %d: %s" % [int(expected.tick), reason]}
			actual = observer._sample(expected.intervention)
		actual.raw = expected.raw
		actual.sticks = expected.sticks
		var disagreement := Reader.disagreement(expected, actual)
		if not disagreement.is_empty():
			flight.free()
			return {ok = false, error = disagreement}
	flight.free()
	return {ok = true, rows = rows.size(), final_tick = int(rows.back().tick), comparison = "all recorded state/load/input/aux/continuous/mode/air/mass samples byte-exact"}


func _write_full_csv(path: String, layout: Dictionary, rows: Array, dt: float) -> String:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return "Cannot create CSV: " + path
	file.store_csv_line(Reader.columns(layout))
	for row: Dictionary in rows:
		Reader.write_row(file, row, dt, 0)
	if file.get_error() != OK:
		file.close()
		return "CSV write failed; discard incomplete file: " + path
	file.close()
	return ""


func _comparison_metrics(source_rows: Array, candidate_rows: Array) -> Dictionary:
	var max_state := PackedFloat64Array()
	max_state.resize(RB.SIZE)
	max_state.fill(0.0)
	var max_abs_fuel := 0.0
	var max_abs_mass := 0.0
	var first_state_divergence := -1
	var first_fuel_divergence := -1
	for i in source_rows.size():
		var old: Dictionary = source_rows[i]
		var now: Dictionary = candidate_rows[i]
		var any_state_diff := false
		for j in RB.SIZE:
			var delta := absf(float(now.state[j]) - float(old.state[j]))
			max_state[j] = maxf(max_state[j], delta)
			if now.state[j] != old.state[j]:
				any_state_diff = true
		if any_state_diff and first_state_divergence < 0:
			first_state_divergence = int(old.tick)
		var candidate_main := float(now.continuous[1]) - float(now.continuous[Glow.LINE_FUEL_INDEX])
		var source_main := float(old.continuous[1])
		var fuel_delta := absf(candidate_main - source_main)
		max_abs_fuel = maxf(max_abs_fuel, fuel_delta)
		max_abs_mass = maxf(max_abs_mass, absf(float(now.mass[0]) - float(old.mass[0])))
		if fuel_delta > 0.0 and first_fuel_divergence < 0:
			first_fuel_divergence = int(old.tick)
	var state_by_channel := {}
	for i in RB.SIZE:
		state_by_channel[str(RB.STATE_LAYOUT[i])] = max_state[i]
	return {"max_abs_state_difference_by_channel": state_by_channel,
		"max_abs_main_fuel_difference_kg": max_abs_fuel,
		"max_abs_live_mass_difference_kg": max_abs_mass,
		"first_body_state_divergence_tick": first_state_divergence,
		"first_main_fuel_divergence_tick": first_fuel_divergence}


func _write_comparison_csv(path: String, source_rows: Array, candidate_rows: Array) -> String:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return "Cannot create comparison CSV: " + path
	var columns := PackedStringArray(["tick", "time_s", "input_tape_equal"])
	for name: String in RB.STATE_LAYOUT:
		columns.append("delta_" + name)
	columns.append_array(PackedStringArray(["source_main_fuel_kg", "candidate_main_fuel_kg", "candidate_line_fuel_kg",
		"candidate_fuel_source_mode", "source_live_mass_kg", "candidate_live_mass_kg", "live_mass_delta_kg"]))
	file.store_csv_line(columns)
	for i in source_rows.size():
		var old: Dictionary = source_rows[i]
		var now: Dictionary = candidate_rows[i]
		var values := PackedStringArray([str(now.tick), JSON.stringify(float(now.tick) * (1.0 / Engine.physics_ticks_per_second), "", false, true),
			str(now.inputs.to_byte_array() == old.inputs.to_byte_array())])
		for j in RB.SIZE:
			values.append(JSON.stringify(float(now.state[j]) - float(old.state[j]), "", false, true))
		values.append(JSON.stringify(float(old.continuous[1]), "", false, true))
		values.append(JSON.stringify(float(now.continuous[1]) - float(now.continuous[Glow.LINE_FUEL_INDEX]), "", false, true))
		values.append(JSON.stringify(float(now.continuous[Glow.LINE_FUEL_INDEX]), "", false, true))
		values.append(str(int(now.continuous[Glow.SOURCE_MODE_INDEX])))
		values.append(JSON.stringify(float(old.mass[0]), "", false, true))
		values.append(JSON.stringify(float(now.mass[0]), "", false, true))
		values.append(JSON.stringify(float(now.mass[0]) - float(old.mass[0]), "", false, true))
		file.store_csv_line(values)
	if file.get_error() != OK:
		file.close()
		return "Comparison CSV write failed; discard incomplete file."
	file.close()
	return ""


func _build_report(old_header: Dictionary, new_header: Dictionary, old_checked: Dictionary,
		new_checked: Dictionary, source_sha256: String, candidate_solver: String, exact: Dictionary,
		comparison: Dictionary, artifacts: Dictionary) -> Dictionary:
	return {
		"format": "openrc-fuel-v2-v3-counterfactual v1",
		"status": "complete",
		"scope": "Single protected, line-free Stik MAX-61FX recording; research-only v2-to-v3 layout map.",
		"created_utc": Time.get_datetime_string_from_system(true),
		"source": {
			"path": options.source,
			"sha256": source_sha256,
			"complete": old_checked.complete,
			"rows": old_checked.rows,
			"first_tick": old_checked.first_tick,
			"final_tick": old_checked.footer.final_tick,
			"solver_sha256": old_header.solver_sha256,
			"law": V2_LAW,
			"continuous_slots": old_header.layout.continuous,
			"aircraft_path": old_header.aircraft_path,
			"aircraft_input_sha256": old_header.metadata.aircraft_input_sha256,
			"installation_sha256": INSTALL_SHA256,
			"profile_sha256": PROFILE_SHA256,
			"fuel_registry_sha256": REGISTRY_SHA256,
			"line_free": true,
			"pickup_geometry_absent": true,
			"main_fuel_above_unusable_on_every_sample": true,
		},
		"candidate": {
			"path": artifacts.candidate_orfl,
			"sha256": FileAccess.get_sha256(artifacts.candidate_orfl),
			"complete": new_checked.complete,
			"rows": new_checked.rows,
			"first_tick": new_checked.first_tick,
			"final_tick": new_checked.footer.final_tick,
			"solver_sha256": candidate_solver,
			"law": V3_LAW,
			"continuous_slots": new_header.layout.continuous,
			"exact_replay": exact.ok,
			"exact_replay_rows": exact.rows,
			"exact_replay_comparison": exact.comparison,
		},
		"solver_changed": old_header.solver_sha256 != candidate_solver,
		"same_aircraft_bytes_geometry_and_initial_body": true,
		"same_absolute_tick_and_input_tape": true,
		"counterfactual_mapping": {
			"source_core_slots_0_to_16": "copied byte-for-byte from Glow v2",
			"candidate_slot_17": "feed-line liquid mass = 0 kg; no line inventory exists in this aircraft",
			"candidate_slot_18": "source mode = 1 (main tank) because all source rows remain strictly above unusable residue",
			"wheel_slots": "old indices 17..19 copied to current indices 19..21 after the two inserted Glow slots",
			"checkpoint": "same body, controls, aux/modes and environment; candidate configuration is current, with aircraft/tank/wheel identity plus mass/inertia/gravity checked before restore",
			"start_fill": "tick-zero main mass divided by current main capacity; selection_known=false because the v2 checkpoint had no fill-selection provenance",
			"production_compatibility_bypass": false,
		},
		"equivalence": {
			"exact_equivalence_claimed": false,
			"reason": "The solver fingerprint and Glow law changed. This is an open-loop numerical counterfactual with an explicit state-layout mapping, not an equivalence result or physical validation.",
			"max_abs_state_difference_by_channel": comparison.max_abs_state_difference_by_channel,
			"first_body_state_divergence_tick": comparison.first_body_state_divergence_tick,
			"max_abs_main_fuel_difference_kg": comparison.max_abs_main_fuel_difference_kg,
			"first_main_fuel_divergence_tick": comparison.first_main_fuel_divergence_tick,
			"max_abs_live_mass_difference_kg": comparison.max_abs_live_mass_difference_kg,
		},
		"artifacts": artifacts,
		"physical_validation": "not established",
	}


func _finish_error(message: String) -> void:
	printerr(message)
	quit(1)
