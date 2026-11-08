## Read-only inspection of the existing ground checkpoint and recovery backups.
extends RefCounted

const Session = preload("res://sim/ground_vehicle/session.gd")
const VehicleData = preload("res://physics/ground_vehicle/vehicle_data.gd")


static func inspect(session: Node, cached: Dictionary, checkpoint_path: String) -> Dictionary:
	if not cached.is_empty():
		var result := _classify(session, cached)
		result["source"] = "memory"
		result["candidate"] = cached.duplicate(true)
		return result
	var destination := ProjectSettings.globalize_path(checkpoint_path)
	var directory_path := destination.get_base_dir()
	var directory := DirAccess.open(directory_path)
	if directory == null:
		return {"status": _missing_directory_status(directory_path)}
	if directory.list_dir_begin() != OK:
		return {"status": "unreadable"}
	var names: Array[String] = []
	var name := directory.get_next()
	while not name.is_empty():
		names.append(name)
		name = directory.get_next()
	directory.list_dir_end()
	var candidates: Array[String] = []
	for entry in names:
		if entry == destination.get_file() or (OS.get_name() == "Windows" and entry.to_lower() == destination.get_file().to_lower()):
			candidates.append(directory_path.path_join(entry))
			break
	var backups: Array[String] = []
	var prefix := destination.get_file() + ".tmp-"
	for entry in names:
		if entry.begins_with(prefix) and entry.ends_with(".previous"):
			backups.append(directory_path.path_join(entry))
	backups.sort_custom(func(a: String, b: String) -> bool:
		var a_time := FileAccess.get_modified_time(a)
		var b_time := FileAccess.get_modified_time(b)
		return a > b if a_time == b_time else a_time > b_time)
	candidates.append_array(backups)
	if candidates.is_empty(): return {"status": "absent"}
	var best := {"status": "unreadable"}
	for path in candidates:
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null: continue
		var contents := file.get_as_text()
		var read_error := file.get_error()
		file.close()
		if read_error != OK and read_error != ERR_FILE_EOF: continue
		var parser := JSON.new()
		if parser.parse(contents) != OK or typeof(parser.data) != TYPE_DICTIONARY: continue
		var result := _classify(session, parser.data)
		result["source"] = "backup" if path in backups else "primary"
		result["path"] = path
		result["candidate"] = parser.data
		if result.status == "compatible": return result
		if result.status == "incompatible" and best.status == "unreadable": best = result
	return best


## Absence is only asserted when an accessible parent can be listed and lacks the entry.
static func _missing_directory_status(path: String) -> String:
	var parent := path.get_base_dir()
	if parent == path or parent.is_empty(): return "unreadable"
	var dir := DirAccess.open(parent)
	if dir == null:
		return "absent" if _missing_directory_status(parent) == "absent" else "unreadable"
	if dir.list_dir_begin() != OK: return "unreadable"
	var entry := dir.get_next()
	var wanted := path.get_file().to_lower()
	while not entry.is_empty():
		if entry.to_lower() == wanted:
			dir.list_dir_end()
			return "unreadable"
		entry = dir.get_next()
	dir.list_dir_end()
	return "absent"


static func _classify(active: Node, candidate: Dictionary) -> Dictionary:
	var unreadable := {"status": "unreadable"}
	var incompatible := {"status": "incompatible"}
	if not active._identity_is_valid(candidate.get("model_identity")) \
			or not active._identity_is_valid(candidate.get("course_identity")) \
			or typeof(candidate.get("checkpoint_sha256")) != TYPE_STRING \
			or active._checkpoint_hash(candidate) != candidate.checkpoint_sha256:
		return unreadable
	if candidate.get("format") != Session.FORMAT: return incompatible
	var saved_tick: Variant = candidate.get("tick")
	var tape: Variant = candidate.get("control_tape")
	if typeof(saved_tick) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(saved_tick)) \
			or float(saved_tick) < 0.0 or floor(float(saved_tick)) != float(saved_tick) \
			or typeof(tape) != TYPE_ARRAY or float(saved_tick) != float(tape.size()) / 4.0:
		return unreadable
	var identities: Dictionary = active.identities_snapshot()
	var vehicle: Variant = candidate.get("vehicle_id", "mt8-bisonte")
	if typeof(vehicle) != TYPE_STRING or vehicle != identities.vehicle_id \
			or not active._identity_equal(candidate.course_identity, identities.course) \
			or not active._solver_identity_matches(candidate.get("solver_identity", {})):
		return incompatible
	var saved_model: Dictionary = candidate.model_identity
	var base: Dictionary = active._base_vehicle_result.duplicate(true)
	var course: Dictionary = active._course_result.duplicate(true)
	var base_identity: Dictionary = base.get("identity", {})
	var experiment := {}
	if not active._identity_equal(saved_model, base_identity):
		if saved_model.get("base_sha256") != base_identity.get("sha256"):
			return incompatible
		if typeof(saved_model.get("settings_json")) != TYPE_STRING:
			return unreadable
		var parser := JSON.new()
		if parser.parse(saved_model.settings_json) != OK or typeof(parser.data) != TYPE_DICTIONARY:
			return unreadable
		var changed: Dictionary = VehicleData.with_experiment(base, parser.data)
		if not changed.get("ok", false) or not active._identity_equal(saved_model, changed.get("identity", {})):
			return unreadable
		experiment = changed.experiment.duplicate(true)
	var probe = Session.new()
	var prepared: bool = probe.prepare(base, course, base)
	if prepared and not experiment.is_empty(): prepared = probe.set_experiment(experiment)
	var valid: bool = prepared and probe.can_restore_checkpoint(candidate)
	probe.free()
	if not valid: return unreadable
	return {"status": "compatible" if active._identity_equal(saved_model, identities.model) \
		and active._active_backend_matches_prepared() else "incompatible",
		"validated": true, "experiment": experiment}
