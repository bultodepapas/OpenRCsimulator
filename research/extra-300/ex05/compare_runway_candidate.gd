# Reproducible paired trace for the Extra breakaway-data change.
# The stock flight-log candidate reader rejects the longer aux layout. This script
# projects only the unchanged body/control state, maps wake state by downwash_index,
# and initializes the three new airborne anchors to zero. This is not exact replay
# or extended-state equivalence, and is not physical validation.
extends SceneTree

const Log := preload("res://sim/flight_log.gd")
const Reader := preload("res://tools/flight_log_cli.gd")
const Flight := preload("res://sim/flight_session.gd")
const Data := preload("res://physics/aircraft_data.gd")
const RB := preload("res://physics/rigid_body.gd")

const SOURCE := "res://../research/extra-300/ex05/extra-runway-baseline-20261016.orfl"
const CANDIDATE := "res://data/aircraft/gp_extra_300s_60.json"
var report_path := "res://../research/extra-300/ex05/candidate-paired-20261016/paired-report.json"
var csv_path := "res://../research/extra-300/ex05/candidate-paired-20261016/paired-common.csv"
const LOAD_NAMES := ["Fx_N", "Fy_N", "Fz_N", "Mx_Nm", "My_Nm", "Mz_Nm"]

var failure := ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			var directory := argument.trim_prefix("--out=")
			report_path = directory.path_join("paired-report.json")
			csv_path = directory.path_join("paired-common.csv")
	if FileAccess.file_exists(report_path) or FileAccess.file_exists(csv_path):
		_finish("paired outputs already exist; refusing overwrite")
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(report_path.get_base_dir()))
	var inspected: Dictionary = Reader.inspect(SOURCE)
	if not inspected.ok or not inspected.complete:
		_finish("baseline log is not complete: " + str(inspected.get("error", "")))
		return
	var header: Dictionary = inspected.header
	Engine.physics_ticks_per_second = roundi(1.0 / float(header.dt_s))
	var candidate_data: Dictionary = Data.load_file(CANDIDATE)
	if not candidate_data.get("ok", false):
		_finish("candidate aircraft data invalid")
		return
	var baseline := Flight.new()
	baseline.input_enabled = false
	baseline.crash_auto_restart = false
	baseline.soft_hull_contacts = header.soft_hull_contacts
	baseline.setup(header.aircraft_path, "", header.aircraft)
	baseline.ground_surfaces = header.ground_surfaces.duplicate()
	baseline.ground_field_id = header.ground_field_id
	var baseline_configured: bool = baseline.setup_shaft_integrator(header.shaft_integrator) \
		and baseline.setup_weather(header.weather) \
		and baseline.set_collision_world(header.collision_world) \
		and baseline.set_lake_context(header.lake)
	if not baseline_configured:
		baseline.free()
		_finish("baseline aircraft/environment could not be prepared under the current source tree")
		return
	baseline.reset()
	if not baseline.restore_checkpoint(header.checkpoint):
		baseline.free()
		_finish("captured baseline checkpoint did not restore under the current source tree")
		return
	var candidate := Flight.new()
	candidate.input_enabled = false
	candidate.crash_auto_restart = false
	candidate.soft_hull_contacts = header.soft_hull_contacts
	candidate.setup(header.aircraft_path, "", candidate_data)
	candidate.ground_surfaces = header.ground_surfaces.duplicate()
	candidate.ground_field_id = header.ground_field_id
	var configured: bool = candidate.setup_shaft_integrator(header.shaft_integrator) \
		and candidate.setup_weather(header.weather) \
		and candidate.set_collision_world(header.collision_world) \
		and candidate.set_lake_context(header.lake)
	if not configured:
		candidate.free()
		baseline.free()
		_finish("candidate replay environment could not be prepared")
		return
	candidate.reset()
	if not candidate.is_flyable():
		candidate.free()
		baseline.free()
		_finish("candidate session is not flyable: " + candidate.start_error)
		return
	var base_checkpoint: Dictionary = header.checkpoint.duplicate(true)
	var candidate_checkpoint: Dictionary = candidate.checkpoint()
	if base_checkpoint.is_empty() or candidate_checkpoint.is_empty():
		candidate.free()
		baseline.free()
		_finish("could not create source/candidate checkpoints")
		return
	var base_sim: Dictionary = base_checkpoint.simulation
	var candidate_sim: Dictionary = candidate_checkpoint.simulation.duplicate(true)
	var base_aux: PackedFloat64Array = base_sim.aux
	var mapped_aux: PackedFloat64Array = candidate_sim.aux.duplicate()
	if base_aux.size() < Flight.AUX_ANCHORS or mapped_aux.size() <= candidate.downwash_index():
		candidate.free()
		baseline.free()
		_finish("source or candidate auxiliary layout is shorter than expected")
		return
	# The first four entries (rpm and servo state) retain their existing indices.
	for i in Flight.AUX_ANCHORS:
		mapped_aux[i] = base_aux[i]
	# The old model has wake immediately after those four entries. Candidate anchors
	# occupy that range, so move the same stored wake scalar to the declared new index.
	var base_wake_index: int = baseline.downwash_index()
	var candidate_wake_index: int = candidate.downwash_index()
	if base_wake_index >= 0 and candidate_wake_index >= 0 and base_aux.size() > base_wake_index:
		mapped_aux[candidate_wake_index] = base_aux[base_wake_index]
	candidate.sim.state = base_sim.state.duplicate()
	candidate.sim.previous = base_sim.previous.duplicate()
	candidate.sim.inputs = base_sim.inputs.duplicate()
	candidate.sim.aux = mapped_aux.duplicate()
	candidate.sim.continuous = base_sim.get("continuous", PackedFloat64Array()).duplicate()
	candidate.sim.modes = base_sim.modes.duplicate()
	var migrated: Dictionary = base_checkpoint.duplicate(true)
	migrated.configuration = candidate_checkpoint.configuration
	for key in ["mass", "inertia", "gravity"]:
		candidate_sim[key] = candidate_checkpoint.simulation[key].duplicate() if candidate_checkpoint.simulation[key] is Array \
			or candidate_checkpoint.simulation[key] is PackedFloat64Array else candidate_checkpoint.simulation[key]
	candidate_sim.state = base_sim.state.duplicate()
	candidate_sim.previous = base_sim.previous.duplicate()
	candidate_sim.inputs = base_sim.inputs.duplicate()
	candidate_sim.aux = mapped_aux
	candidate_sim.continuous = base_sim.get("continuous", PackedFloat64Array()).duplicate()
	candidate_sim.modes = base_sim.modes.duplicate()
	candidate_sim.tick = base_sim.tick
	candidate_sim.dt = base_sim.dt
	candidate_sim.stop_at_tick = base_sim.stop_at_tick
	var combined: PackedFloat64Array = candidate_sim.state.duplicate()
	combined.append_array(candidate_sim.continuous)
	candidate_sim.last_loads = candidate.sim._stage_loads(combined, 0.0)
	migrated.simulation = candidate_sim
	if not candidate.restore_checkpoint(migrated):
		candidate.free()
		baseline.free()
		_finish("explicit shared-state projection could not restore into candidate session")
		return
	var base_aux_size: int = base_sim.aux.size()
	var candidate_aux_size: int = candidate.sim.aux.size()
	var source_sha := FileAccess.get_sha256(SOURCE)
	var candidate_sha := FileAccess.get_sha256(CANDIDATE)
	var report := {
		"format": "openrc-extra-paired-trace v1",
		"status": "ok",
		"complete": inspected.complete,
		"rows": inspected.rows,
		"first_tick": inspected.first_tick,
		"final_tick": inspected.footer.final_tick,
		"dt_s": header.dt_s,
		"source": SOURCE,
		"source_sha256": source_sha,
		"baseline_aircraft_input_sha256": header.aircraft.get("input_identity", {}).get("sha256", ""),
		"candidate_aircraft": CANDIDATE,
		"candidate_aircraft_input_sha256": candidate_data.get("input_identity", {}).get("sha256", ""),
		"candidate_identity": candidate_data.get("input_identity", {}),
		"candidate_file_sha256": candidate_sha,
		"baseline_solver_sha256": header.solver_sha256,
		"current_solver_sha256": Log.solver_identity(),
		"solver_changed": header.solver_sha256 != Log.solver_identity(),
		"comparison_method": "Same complete baseline ORFL body and recorded post-conditioning input/intervention tape. Baseline aircraft from the ORFL and candidate aircraft are both run under the current source tree; explicit auxiliary projection only (preserve four shared auxiliaries, move wake value from source downwash_index to candidate downwash_index, initialize three new airborne anchors to zero). The recorded solver identity differs from the current source identity where indicated; this is not exact replay or extended-state equivalence.",
		"layout_projection": {"baseline_aux_size": base_aux_size, "candidate_aux_size": candidate_aux_size,
			"baseline_downwash_index": base_wake_index, "candidate_downwash_index": candidate_wake_index,
			"new_anchor_count": candidate.anchor_count(), "new_anchor_values": "zero (airborne initial condition)"},
		"state": {},
		"loads": {},
		"first_divergence": null,
	}
	var state_max := PackedFloat64Array()
	var state_sums := PackedFloat64Array()
	var load_max := PackedFloat64Array()
	var load_sums := PackedFloat64Array()
	state_max.resize(RB.STATE_LAYOUT.size())
	state_sums.resize(RB.STATE_LAYOUT.size())
	load_max.resize(LOAD_NAMES.size())
	load_sums.resize(LOAD_NAMES.size())
	var csv_file := FileAccess.open(csv_path, FileAccess.WRITE)
	if csv_file == null:
		candidate.free()
		baseline.free()
		_finish("cannot write paired trace")
		return
	var headers := PackedStringArray(["tick", "t_s"])
	for name: String in RB.STATE_LAYOUT: headers.append("delta_" + name)
	for name: String in LOAD_NAMES: headers.append("delta_" + name)
	csv_file.store_csv_line(headers)
	var stream := FileAccess.open(SOURCE, FileAccess.READ)
	stream.seek(8)
	Log.read_packet(stream)
	var tick_count := 0
	while stream.get_position() < stream.get_length():
		var packet: Dictionary = Log.read_packet(stream)
		if not packet.ok:
			failure = "malformed packet during paired pass"
			break
		if packet.value.kind == "footer":
			break
		for row: Dictionary in packet.value.rows:
			if tick_count > 0:
				if row.intervention.has("aux"):
					failure = "auxiliary interventions need a separate layout projection"
					break
				for key: String in row.intervention:
					baseline.sim.set(key, row.intervention[key].duplicate())
					candidate.sim.set(key, row.intervention[key].duplicate())
				baseline.sim.inputs = row.inputs.duplicate()
				candidate.sim.inputs = row.inputs.duplicate()
				baseline.sim.step()
				candidate.sim.step()
				if baseline.sim.fault_reason != "" or candidate.sim.fault_reason != "":
					failure = "simulation fault at tick %d: baseline='%s' candidate='%s'" % [row.tick,
						baseline.sim.fault_reason, candidate.sim.fault_reason]
					break
			var deltas := PackedFloat64Array()
			var csv_row := PackedStringArray([str(row.tick), str(float(row.tick) * float(header.dt_s))])
			for i in RB.STATE_LAYOUT.size():
				var delta: float = candidate.sim.state[i] - baseline.sim.state[i]
				deltas.append(delta)
				csv_row.append(str(delta))
				state_max[i] = maxf(state_max[i], absf(delta))
				state_sums[i] += delta * delta
				if report.first_divergence == null and delta != 0.0:
					report.first_divergence = {"tick": row.tick, "channel": RB.STATE_LAYOUT[i], "delta": delta}
			for i in LOAD_NAMES.size():
				var delta: float = candidate.sim.last_loads[i] - baseline.sim.last_loads[i]
				csv_row.append(str(delta))
				load_max[i] = maxf(load_max[i], absf(delta))
				load_sums[i] += delta * delta
				if report.first_divergence == null and delta != 0.0:
					report.first_divergence = {"tick": row.tick, "channel": LOAD_NAMES[i], "delta": delta}
			csv_file.store_csv_line(csv_row)
			tick_count += 1
		if not failure.is_empty():
			break
	stream.close()
	csv_file.close()
	var state_metrics := {}
	for i in RB.STATE_LAYOUT.size():
		state_metrics[RB.STATE_LAYOUT[i]] = {"max_abs": state_max[i], "rmse": sqrt(state_sums[i] / maxf(1.0, tick_count))}
	var load_metrics := {}
	for i in LOAD_NAMES.size():
		load_metrics[LOAD_NAMES[i]] = {"max_abs": load_max[i], "rmse": sqrt(load_sums[i] / maxf(1.0, tick_count))}
	report.state = state_metrics
	report.loads = load_metrics
	report.rows_processed = tick_count
	report.candidate_fault = candidate.sim.fault_reason
	report.baseline_fault = baseline.sim.fault_reason
	if tick_count != inspected.rows and failure.is_empty():
		failure = "paired pass did not process every recorded row"
	report.complete = inspected.complete and failure.is_empty()
	if not failure.is_empty(): report.status = "error"; report.error = failure
	var output := FileAccess.open(report_path, FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "\t", true, true) + "\n")
	output.close()
	candidate.free()
	baseline.free()
	if not failure.is_empty():
		printerr(failure)
		quit(1)
		return
	print("paired Extra trace: %d rows, solver_changed=%s, max state delta %s, max load delta %s; not exact equivalence" % [
		tick_count, str(report.solver_changed), String.num_scientific(_max(state_max)), String.num_scientific(_max(load_max))])
	quit(0)


func _max(values: PackedFloat64Array) -> float:
	var value := 0.0
	for item in values: value = maxf(value, item)
	return value


func _finish(message: String) -> void:
	printerr(message)
	quit(1)
