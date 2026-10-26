extends SceneTree

const Flight := preload("res://sim/flight_session.gd")
const FlightLog := preload("res://sim/flight_log.gd")
const FlightLogReader := preload("res://tools/flight_log_cli.gd")
const RigidBody := preload("res://physics/rigid_body.gd")
const Profile := preload("res://render/lighting/lighting_profile.gd")
const LightingRig := preload("res://render/lighting/aircraft_lighting_rig_3d.gd")
const LightingPolicy := preload("res://render/lighting/lighting_policy.gd")

const AIRCRAFT_PATH := "res://data/aircraft/jensen_ugly_stik_60.json"
const FLIGHT_TICKS := 120

var _checks := 0
var _failures := 0
var _output_dir := ""


func _initialize() -> void:
	_output_dir = ProjectSettings.globalize_path("res://../tmp/fw-rgb-10-%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(_output_dir)
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var variants: Array[Dictionary] = [
		{"name": "off", "preset": "disabled", "quality": "low", "reduced_flashes": true, "show_vfx": false},
		{"name": "classic", "preset": "classic_rc", "quality": "standard", "reduced_flashes": false, "show_vfx": true},
		{"name": "festival", "preset": "festival", "quality": "high", "reduced_flashes": false, "show_vfx": true},
	]
	var reports: Array[Dictionary] = []
	for variant: Dictionary in variants:
		reports.append(await _run_variant(variant))
	var runs_valid := reports.size() == variants.size()
	for report: Dictionary in reports:
		runs_valid = runs_valid and bool(report.get("ok", false))
	_check("all OFF/Classic/Festival fixed-wing runs logged and exactly replayed", runs_valid)
	if runs_valid:
		var reference_rows: Array = reports[0].rows
		var reference_hashes: Array = reports[0].hashes
		for index in range(1, reports.size()):
			_check("%s used the same accepted aircraft source and model" % reports[index].name,
				reports[index].aircraft_path == reports[0].aircraft_path
				and reports[index].aircraft_input_sha256 == reports[0].aircraft_input_sha256
				and reports[index].aircraft_semantic_sha256 == reports[0].aircraft_semantic_sha256)
			_check("%s recorded physics rows match OFF at every tick" % reports[index].name,
				_same_rows(reference_rows, reports[index].rows))
			_check("%s recorded row SHA-256 values match OFF" % reports[index].name,
				reference_hashes == reports[index].hashes)
		var digest := FlightLog.sha256(var_to_bytes(reference_hashes)).hex_encode()
		print("FW-RGB-10 lighting independence: %d ticks per profile; physical row SHA-256 %s; %d checks, %d failures" % [
			FLIGHT_TICKS, digest, _checks, _failures])
	else:
		printerr("FW-RGB-10 lighting independence: %d checks, %d failures; output %s" % [_checks, _failures, _output_dir])
	quit(1 if _failures > 0 else 0)


func _run_variant(spec: Dictionary) -> Dictionary:
	var stage := Node3D.new()
	stage.name = "LightingPhysicsBoundary_%s" % spec.name
	root.add_child(stage)
	await process_frame
	var aircraft := _make_aircraft(stage)
	var profile: Dictionary = Profile.defaults() if str(spec.preset) == "disabled" else Profile.preset(str(spec.preset))
	if str(spec.preset) == "disabled":
		profile.selection = "disabled"
	else:
		for index in profile.zones.size():
			var zone: Dictionary = profile.zones[index]
			if str(zone.get("id", "")) == "nav_left":
				zone["reactive"] = {"source": "throttle", "gain": 0.75}
				profile.zones[index] = zone
		var checked_profile: Dictionary = Profile.validate(profile)
		_check("%s reactive profile validates" % spec.name, bool(checked_profile.get("ok", false)))
		profile = checked_profile.get("profile", {})
	LightingPolicy.apply({
		"aircraft_lighting_quality": spec.quality,
		"aircraft_lighting_reduced_flashes": spec.reduced_flashes,
		"aircraft_lighting_show_vfx": spec.show_vfx,
	})
	var rig := LightingRig.new()
	rig.name = "AircraftLightingRig"
	stage.add_child(rig)
	var configured: Dictionary = rig.configure(aircraft, profile)
	_check("%s real lighting rig configures" % spec.name, bool(configured.get("ok", false)))
	var red_lens := aircraft.get_node("LightRed") as MeshInstance3D
	var red_material := red_lens.material_override as StandardMaterial3D
	var initial_light_energy := red_material.emission_energy_multiplier
	var low_throttle_energy := NAN
	var high_throttle_energy := NAN

	var flight := Flight.new()
	flight.input_enabled = false
	flight.setup(AIRCRAFT_PATH)
	_check("%s fixed-wing session is flyable" % spec.name, flight.is_flyable())
	if not flight.is_flyable() or not bool(configured.get("ok", false)):
		rig.dispose()
		flight.free()
		stage.free()
		return {"name": spec.name, "ok": false}
	var log_path := _output_dir.path_join("%s.orfl" % spec.name)
	var logger := FlightLog.new(flight)
	_check("%s .orfl recording starts" % spec.name, logger.start(log_path) == OK)
	if not logger.recording:
		rig.dispose()
		flight.free()
		stage.free()
		return {"name": spec.name, "ok": false}
	for tick in FLIGHT_TICKS:
		_set_controls(flight, tick)
		flight.sim.step()
		if not flight.sim.fault_reason.is_empty():
			_check("%s session remains fault-free at tick %d" % [spec.name, tick + 1], false)
			break
		var air_data: Dictionary = flight.air_data(flight.sim.state, flight.sim.time())
		rig.advance(flight.sim.time(), {
			"lighting_priority": 100,
			"throttle": flight.propulsion_throttle(),
			"speed_mps": Vector3(flight.sim.state[RigidBody.VEL], flight.sim.state[RigidBody.VEL + 1], flight.sim.state[RigidBody.VEL + 2]).length(),
			"airspeed": float(air_data.get("V", 0.0)),
			"roll_rate": flight.sim.state[RigidBody.RATE],
			"pitch_rate": flight.sim.state[RigidBody.RATE + 1],
			"maneuver": clampf(Vector3(flight.sim.state[RigidBody.RATE], flight.sim.state[RigidBody.RATE + 1], flight.sim.state[RigidBody.RATE + 2]).length() / TAU, 0.0, 1.0),
			"exposure": 10000.0,
			"distance_m": 0.0,
			"effects_allowed": LightingPolicy.effects_allowed() and not flight.sim.paused and flight.sim.fault_reason.is_empty(),
		})
		if tick == 20:
			low_throttle_energy = red_material.emission_energy_multiplier
		elif tick == 80:
			high_throttle_energy = red_material.emission_energy_multiplier
	_check("%s logging stops cleanly" % spec.name, logger.stop() == OK)
	if str(spec.name) == "off":
		_check("OFF keeps the model emission dark", is_zero_approx(initial_light_energy) and is_zero_approx(red_material.emission_energy_multiplier))
	else:
		_check("%s lighting remains available" % spec.name, initial_light_energy > 0.0)
		_check("%s reactive throttle changes actual emission across the same clock" % spec.name,
			is_finite(low_throttle_energy) and is_finite(high_throttle_energy) and absf(high_throttle_energy - low_throttle_energy) > 0.000001)
	var inspected: Dictionary = FlightLogReader.inspect(log_path)
	_check("%s log is complete with verified packet checksums" % spec.name,
		bool(inspected.get("ok", false)) and bool(inspected.get("complete", false)) and int(inspected.get("rows", 0)) == FLIGHT_TICKS + 1)
	var rows := _read_rows(log_path) if bool(inspected.get("ok", false)) else []
	var solver_matches := bool(inspected.get("ok", false)) and str(inspected.header.get("solver_sha256", "")) == FlightLog.solver_identity()
	_check("%s exact solver identity is unchanged" % spec.name, solver_matches)
	var replay_ok := bool(inspected.get("ok", false)) and _verify_exact_replay(log_path, inspected.header, int(inspected.rows))
	_check("%s replay matches all recorded physics samples exactly" % spec.name, replay_ok)
	var hashes: Array[String] = []
	for row: Dictionary in rows:
		hashes.append(FlightLog.sha256(var_to_bytes(_row_signature(row))).hex_encode())
	var header: Dictionary = inspected.get("header", {})
	var metadata: Dictionary = header.get("metadata", {})
	rig.dispose()
	flight.free()
	stage.free()
	return {"name": spec.name, "ok": bool(inspected.get("ok", false)) and replay_ok and rows.size() == FLIGHT_TICKS + 1,
		"rows": rows, "hashes": hashes, "aircraft_path": str(header.get("aircraft_path", "")),
		"aircraft_input_sha256": str(metadata.get("aircraft_input_sha256", "")),
		"aircraft_semantic_sha256": str(metadata.get("aircraft_semantic_sha256", ""))}


func _set_controls(flight: Node, tick: int) -> void:
	flight.sim.inputs[0] = 0.12 if tick < 36 else -0.08
	flight.sim.inputs[1] = -0.04 if tick < 72 else 0.03
	flight.sim.inputs[2] = 0.02
	flight.sim.inputs[3] = 0.2 if tick < 48 else 0.8


func _make_aircraft(parent: Node3D) -> Node3D:
	var aircraft := Node3D.new()
	aircraft.name = "LightingPhysicsAircraft"
	var body := MeshInstance3D.new()
	body.name = "Body"
	var box := BoxMesh.new()
	box.size = Vector3(0.5, 0.12, 0.9)
	body.mesh = box
	aircraft.add_child(body)
	_add_emission_lens(aircraft, "LightRed", "light_red")
	_add_emission_lens(aircraft, "LightGreen", "light_green")
	parent.add_child(aircraft)
	return aircraft


func _add_emission_lens(parent: Node3D, node_name: String, material_name: String) -> void:
	var lens := MeshInstance3D.new()
	lens.name = node_name
	lens.mesh = SphereMesh.new()
	var material := StandardMaterial3D.new()
	material.resource_name = material_name
	material.emission_enabled = true
	material.emission = Color.WHITE
	material.emission_energy_multiplier = 2.0
	lens.material_override = material
	parent.add_child(lens)


func _read_rows(path: String) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return rows
	file.seek(8)
	var header_packet: Dictionary = FlightLog.read_packet(file)
	if not bool(header_packet.get("ok", false)):
		file.close()
		return rows
	while file.get_position() < file.get_length():
		var packet: Dictionary = FlightLog.read_packet(file)
		if not bool(packet.get("ok", false)) or str(packet.value.get("kind", "")) == "footer":
			break
		for row: Dictionary in packet.value.get("rows", []):
			rows.append(row)
	file.close()
	return rows


func _verify_exact_replay(path: String, header: Dictionary, expected_rows: int) -> bool:
	var prepared: Dictionary = FlightLogReader.prepare_replay(header)
	if not bool(prepared.get("ok", false)):
		return false
	var replay_flight: Node = prepared.flight
	var observer := FlightLog.new(replay_flight)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		replay_flight.free()
		return false
	file.seek(8)
	FlightLog.read_packet(file)
	var first_sample := true
	var rows_seen := 0
	var exact := true
	while file.get_position() < file.get_length() and exact:
		var packet: Dictionary = FlightLog.read_packet(file)
		if not bool(packet.get("ok", false)):
			exact = false
			break
		if str(packet.value.get("kind", "")) == "footer":
			break
		for row: Dictionary in packet.value.get("rows", []):
			var actual: Dictionary
			if first_sample:
				first_sample = false
				actual = observer._sample({})
			else:
				for key: String in row.get("intervention", {}):
					replay_flight.sim.set(key, row.intervention[key].duplicate())
				replay_flight.sim.inputs = row.inputs.duplicate()
				replay_flight.sim.step()
				if not replay_flight.sim.fault_reason.is_empty() or replay_flight.sim.tick != row.tick:
					exact = false
					break
				actual = observer._sample(row.intervention)
			actual.raw = row.raw
			actual.sticks = row.sticks
			if not FlightLogReader.disagreement(row, actual).is_empty():
				exact = false
				break
			rows_seen += 1
	file.close()
	replay_flight.free()
	return exact and rows_seen == expected_rows


func _row_signature(row: Dictionary) -> Array:
	return [row.tick, row.state, row.loads, row.inputs, row.aux, row.continuous, row.modes,
		row.air, row.get("mass", PackedFloat64Array()), row.raw, row.sticks, row.intervention]


func _same_rows(reference: Array, candidate: Array) -> bool:
	if reference.size() != candidate.size():
		return false
	for index in reference.size():
		var first: Dictionary = reference[index]
		var second: Dictionary = candidate[index]
		if int(first.get("tick", -1)) != int(second.get("tick", -2)):
			return false
		if not FlightLogReader.disagreement(first, second).is_empty():
			return false
		if var_to_bytes([first.raw, first.sticks, first.intervention]) != var_to_bytes([second.raw, second.sticks, second.intervention]):
			return false
	return true


func _check(label: String, passed: bool) -> void:
	_checks += 1
	if not passed:
		_failures += 1
		printerr("FAIL " + label)
