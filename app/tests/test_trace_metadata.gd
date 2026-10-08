# C7-R2: metadata follows loaded configuration and recording-start state, never catalog identity.
extends SceneTree

const Session := preload("res://sim/flight_session.gd")
const Recorder := preload("res://sim/recorder.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const RB := preload("res://physics/rigid_body.gd")
const Trace := preload("res://sim/trace.gd")
const AircraftData := preload("res://physics/aircraft_data.gd")

var _failures: int = 0
var _checks: int = 0


func _check(label: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL ", label)


func _aux_matches(encoded: String, aux: PackedFloat64Array) -> bool:
	var decoded: Array = JSON.parse_string(encoded)
	if decoded.size() != aux.size():
		return false
	for index in aux.size():
		# JSON decimal conversion is not a bit-exact replay format. Stay stricter
		# than the CSV's nine-place tolerance while allowing a float64 ULP.
		if absf(float(decoded[index]) - aux[index]) > maxf(1e-15, absf(aux[index]) * 2e-15):
			return false
	return true


func _initialize() -> void:
	var session: Node = Session.new()
	session.input_enabled = false
	session.setup()
	root.add_child(session)
	var recorder: RefCounted = Recorder.new(session.sim)
	for entry in Catalog.ENTRIES:
		session.aircraft_path = entry.data
		_check("reload " + entry.id, session.reload().begins_with("aircraft reloaded:"))
		var meta: Dictionary = session.trace_meta()
		_check("active aircraft " + entry.id, meta.aircraft.begins_with(entry.id))
		_check("metadata schema", meta.metadata_schema == "openrc-flight-meta v2")
		_check("input schema", meta.aircraft_input_format == AircraftData.FORMAT)
		_check("raw input identity " + entry.id, meta.aircraft_input_sha256 == FileAccess.get_sha256(entry.data))
		_check("semantic hash is separately named", meta.aircraft_semantic_sha256 == session.aircraft.model.data_sha256)
		_check("ambiguous legacy hash absent", not meta.has("aircraft_data_sha256"))
		_check("rigid body layout", JSON.parse_string(meta.state_layout).size() == RB.SIZE)
		_check("auxiliary layout", JSON.parse_string(meta.aux_layout) == Trace.COLUMNS.slice(30))
		_check("initial auxiliary snapshot", _aux_matches(meta.recording_start_aux, session.sim.aux.slice(0, Session.AUX_LAYOUT.size())))
		_check("powered start", meta.recording_start_engine_running == "true")
		if entry.id == "p51d-mustang-120":
			_check("P-51 shaft balance", meta.propulsion_model == "propeller-shaft-balance-v1")
			_check("P-51 slipstream", meta.propwash_model == "tail-slipstream-increment-v1")
		elif entry.id == "sebart-avanti-s-a200-p100rx":
			_check("Avanti spool", meta.propulsion_model == "turbine-ecu-spool-v1")
			_check("Avanti no propwash", meta.propwash_model == "none")
		else:
			_check("Stik/Extra lag", meta.propulsion_model == "propeller-rpm-lag-v1")
			_check("Stik/Extra no propwash", meta.propwash_model == "none")

		# T may start recording after takeoff. The snapshot must describe that instant,
		# not the trim solution or the previous aircraft's initial state.
		session.sim.inputs[0] = 0.7
		for _tick in 12:
			session.sim.step()
		recorder.start(session.trace_meta())
		var snapshot: Dictionary = recorder.trace.meta.duplicate(true)
		_check("mid-flight recording tick", snapshot.recording_start_tick == 12)
		_check("mid-flight aux snapshot", _aux_matches(snapshot.recording_start_aux, session.sim.aux.slice(0, Session.AUX_LAYOUT.size())))
		_check("CSV keeps new metadata", recorder.trace.to_csv().contains("# propulsion_model: " + snapshot.propulsion_model))
		for index in RB.SIZE:
			_check("state layout maps sample %d" % index, absf(recorder.trace.value(0, RB.STATE_LAYOUT[index]) - session.sim.state[index]) < 1e-12)
		for index in Session.AUX_LAYOUT.size():
			_check("aux layout maps sample %d" % index, recorder.trace.value(0, Session.AUX_LAYOUT[index]) == session.sim.aux[index])
		session.sim.step()
		_check("metadata snapshot remains at recording start", recorder.trace.meta == snapshot)
		recorder.recording = false

	# Remove opt-ins while retaining the P-51 ID: dispatch must follow configuration.
	session.aircraft_path = Catalog.entry("p51d-mustang-120").data
	session.reload()
	var prop: Dictionary = session.aircraft.model.propulsion
	prop.erase("shaft")
	prop.erase("slipstream")
	prop.erase("normal_force")
	prop.erase("pfactor_moment")
	session.aircraft.model.envelope = {}
	var changed: Dictionary = session.trace_meta()
	_check("same ID, lag path", changed.propulsion_model == "propeller-rpm-lag-v1")
	_check("same ID, no slipstream", changed.propwash_model == "none")
	_check("same ID, global aero", changed.aero_model == "global-derivatives-v1")
	var features: Dictionary = JSON.parse_string(changed.propulsion_features)
	_check("same ID, no propeller normal force/P-factor", not features.propeller_normal_force and not features.propeller_pfactor)

	session.aircraft_path = Catalog.entry(Catalog.DEFAULT_ID).data
	session.reload()
	_check("glide trim succeeds", session.trim_at(15.0, "glide").ok)
	session.reset()
	var glide: Dictionary = session.trace_meta()
	_check("glide retains configured propulsion model", glide.propulsion_model == "propeller-rpm-lag-v1")
	_check("glide engine stopped", glide.recording_start_engine_running == "false")
	_check("glide RPM snapshot zero", JSON.parse_string(glide.recording_start_aux)[0] == 0.0)
	_test_input_identity(session)
	recorder.detach()
	session.free()
	print("C7-R2 / DATA-3: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)


func _write(path: String, content: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	_check("temporary input opens", file != null)
	if file != null:
		file.store_buffer(content.to_utf8_buffer())
		file.close()


func _test_input_identity(session: Node) -> void:
	var source_path: String = Catalog.entry(Catalog.DEFAULT_ID).data
	var source: String = FileAccess.get_file_as_string(source_path)
	var original: Dictionary = AircraftData.load_file(source_path)
	var path: String = "user://data3-input-%d.json" % OS.get_process_id()
	var output: String = "user://data3-trace-%d.csv" % OS.get_process_id()
	var raw: Dictionary = JSON.parse_string(source)
	var memory: Dictionary = AircraftData.validate_and_derive(raw)
	_check("in-memory input has no file identity", memory.ok and not memory.has("input_identity"))
	_check("file identity does not change derived model/checkpoints", original.model == memory.model)

	# Both formatting-only changes and late numerical digits escaped the old fingerprint.
	var formatted: String = source.replace("\n", "\r\n") + " \t\r\n"
	var late_digit: String = source.replace('"value": 0.1068,', '"value": 0.1068000000000001,')
	_check("late-digit fixture changes input", source != late_digit)
	for changed in [formatted, late_digit]:
		_write(path, changed)
		var loaded: Dictionary = AircraftData.load_file(path)
		_check("changed input loads", loaded.ok)
		if not loaded.ok:
			continue
		_check("exact hash matches independent file hashing", loaded.input_identity.sha256 == FileAccess.get_sha256(path))
		_check("raw hash distinguishes changed bytes", loaded.input_identity.sha256 != original.input_identity.sha256)
		_check("legacy rounded semantic digest collides", loaded.model.data_sha256 == original.model.data_sha256)
		if changed == late_digit:
			_check("late digit reaches physics model", loaded.model.aero.CL0 != original.model.aero.CL0)

	_write(path, source)
	session.aircraft_path = path
	_check("temporary source reloads", session.reload().begins_with("aircraft reloaded:"))
	var before: Dictionary = session.trace_meta()
	_write(path, "{}")
	_check("recording identifies loaded bytes, not later disk content", session.trace_meta().aircraft_input_sha256 == before.aircraft_input_sha256)
	_check("failed reload refuses replacement", session.reload().begins_with("reload failed"))
	_check("failed reload retains source identity", session.trace_meta().aircraft_input_sha256 == before.aircraft_input_sha256)
	var trace: RefCounted = Trace.new()
	trace.meta = session.trace_meta()
	_check("trace artifact saves", trace.save(output) == OK)
	_check("saved trace preserves exact digest", FileAccess.get_file_as_string(output).contains(
		"# aircraft_input_sha256: " + FileAccess.get_sha256(source_path)))
	_check("in-memory candidate applies", session._apply(memory))
	_check("in-memory replacement cannot inherit file identity", session.trace_meta().aircraft_input_sha256 == "unavailable: in-memory input")
	_check("invalid input has no identity", not AircraftData.load_file(path).has("input_identity"))
	_check("temporary input removed", DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK)
	_check("temporary trace removed", DirAccess.remove_absolute(ProjectSettings.globalize_path(output)) == OK)
