# C7-R2: metadata follows loaded configuration and recording-start state, never catalog identity.
extends SceneTree

const Session := preload("res://sim/flight_session.gd")
const Recorder := preload("res://sim/recorder.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const RB := preload("res://physics/rigid_body.gd")
const Trace := preload("res://sim/trace.gd")

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
		_check("metadata schema", meta.metadata_schema == "openrc-flight-meta v1")
		_check("rigid body layout", JSON.parse_string(meta.state_layout).size() == RB.SIZE)
		_check("auxiliary layout", JSON.parse_string(meta.aux_layout) == Trace.COLUMNS.slice(30))
		_check("initial auxiliary snapshot", _aux_matches(meta.recording_start_aux, session.sim.aux))
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
		_check("mid-flight aux snapshot", _aux_matches(snapshot.recording_start_aux, session.sim.aux))
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
	recorder.detach()
	session.free()
	print("C7-R2: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)
