extends RefCounted
## CR-30: read-only, bounded interpretation of accepted contact events. No solver writes.

signal assessment_changed(report: Dictionary, terminal: bool)

const Catalog = preload("res://economy/catalog.gd")
const Calculator = preload("res://economy/calculator.gd")
const Events = preload("res://sim/aircraft_contact_events.gd")
const MAX_EVENTS := 128
const ARCHIVE_PATH := "user://last_accident.json"
const ARCHIVE_MAX_BYTES := 262144

var dossier: Dictionary = {}
var report: Dictionary = {}
var last_report: Dictionary = {}
var journal: Array = []
var archive_path := ARCHIVE_PATH
var terminal := false
var _assessment: Dictionary = {}
var _seen: Dictionary = {}
var _last_tick := -1
var _catalog_hash := ""
var _identity: Dictionary = {}
var _catalog_errors: Array = []
var _dirty := false
var _revision := 0
var _persisted_revision := -1
var _flush_attempt_revision := -1
var _flush_error := OK


func begin(aircraft_id: String, source_hash: String) -> void:
	begin_with_catalog(Catalog.load_for(aircraft_id, source_hash), aircraft_id, source_hash)


func begin_with_catalog(loaded: Dictionary, aircraft_id: String, source_hash: String) -> void:
	dossier = loaded.get("dossier", {}).duplicate(true) if loaded.get("ok", false) else {}
	_catalog_errors = Array(loaded.get("errors", []))
	_catalog_hash = str(loaded.get("catalog_hash", ""))
	_identity = {aircraft_id = aircraft_id, source_sha256 = source_hash,
		incident_id = "%s-%d" % [Time.get_datetime_string_from_system(true), Time.get_ticks_usec()]}
	report = {}
	journal = []
	_assessment = {components = {}, terminal = false, total_loss = false, unresolved = []}
	_seen = {}
	_last_tick = -1
	terminal = false
	_dirty = false
	_revision = 0
	_persisted_revision = -1
	_flush_attempt_revision = -1
	_flush_error = OK


func observe(snapshot: Dictionary, bindings: Dictionary, crashed: bool, restored := false) -> void:
	var tick := int(snapshot.get("tick", -1))
	if tick < 0 or tick < _last_tick:
		return # A reset must establish a fresh ledger before the physics clock goes backwards.
	_last_tick = tick
	var events: Variant = snapshot.get("events", [])
	if not Events.validate_events(events, tick, bindings):
		var invalid_changed := _add_unresolved("Contact evidence is invalid; inspection required.")
		if crashed and not terminal:
			terminal = true
			_assessment.terminal = true
			invalid_changed = true
		if invalid_changed:
			_recalculate()
		return
	var changed := false
	for event: Dictionary in events:
		if event.get("lifecycle") != "new":
			continue # Sustained and ended contacts cannot produce repeated purchases.
		var key := str(event.event_id) + ":" + str(event.response)
		if _seen.has(key):
			continue
		if journal.size() >= MAX_EVENTS:
			changed = _add_unresolved("Contact journal limit reached; inspection required.") or changed
			continue
		_seen[key] = true
		journal.append(event.duplicate(true))
		changed = true
		if event.source == "propeller" and event.event_type == "strike":
			_mark_propeller()
		else:
			_add_unresolved("Impact or surface contact requires structural inspection.")
		if event.source == "lake":
			_add_unresolved("Water exposure requires inspection of electronics and powertrain.")
	if restored and (not snapshot.get("prop_strike", {}).is_empty() or not journal.is_empty()):
		changed = _add_unresolved("Restored physics checkpoint: earlier damage history is unavailable.") or changed
		if not snapshot.get("prop_strike", {}).is_empty() and not _assessment.components.has(str(dossier.get("propeller_component_id", ""))):
			_mark_propeller()
			changed = true
	if crashed and not terminal:
		terminal = true
		_assessment.terminal = true
		_add_unresolved("Crash inspection pending; component survival is not yet established.")
		changed = true
	if changed:
		_recalculate()


func _mark_propeller() -> void:
	var id := str(dossier.get("propeller_component_id", ""))
	if id.is_empty():
		_add_unresolved("A propeller strike was recorded; no compatible replacement price is available.")
		return
	_assessment.components[id] = {disposition = "replace", quantity = 1}
	for inspection_id: String in dossier.get("propeller_inspection_ids", []):
		_assessment.components[inspection_id] = {disposition = "inspect"}
	_add_unresolved("Propeller strike: inspect the powertrain, shaft and mount before return to service.")


func _add_unresolved(reason: String) -> bool:
	if _assessment.unresolved.has(reason):
		return false
	_assessment.unresolved.append(reason)
	return true


func _recalculate() -> void:
	if dossier.is_empty():
		report = {ok = false, currency = "USD", known_subtotal_minor = 0, total_minor = null,
			low_minor = null, high_minor = null, complete = false, outcome = "unavailable",
			lines = [], salvage_minor = 0, replacement_minor = null, price_date = "",
			valuation_kind = "unavailable", unresolved = _assessment.unresolved.duplicate(),
			errors = _catalog_errors.duplicate()}
		report.unresolved.append("Compatible aircraft cost dossier is unavailable.")
	else:
		report = Calculator.calculate(dossier, _assessment)
	report["format"] = "openrc-accident-report v1"
	report["identity"] = _identity.duplicate(true)
	report["aircraft_name"] = _identity.aircraft_id
	report["incident_id"] = _identity.incident_id
	report["catalog_hash"] = _catalog_hash
	report["evidence"] = journal.duplicate(true)
	report["terminal"] = terminal
	report["tick"] = _last_tick
	_revision += 1
	report["revision"] = _revision
	_dirty = true
	assessment_changed.emit(report.duplicate(true), terminal)


## Called outside accepted-tick callbacks. Persistence is a single bounded latest-report snapshot.
func flush() -> Error:
	if not _dirty or report.is_empty() or _persisted_revision == _revision:
		return OK
	if _flush_attempt_revision == _revision:
		return _flush_error as Error
	_flush_attempt_revision = _revision
	_flush_error = _write_archive()
	return _flush_error as Error


func _write_archive() -> Error:
	var encoded := JSON.stringify(report, "\t", true, true)
	if encoded.to_utf8_buffer().size() > ARCHIVE_MAX_BYTES:
		return ERR_OUT_OF_MEMORY
	var file := FileAccess.open(archive_path + ".tmp", FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(encoded)
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		return write_error
	var rename_error := DirAccess.rename_absolute(archive_path + ".tmp", archive_path)
	if rename_error == OK:
		_dirty = false
		_persisted_revision = _revision
	return rename_error


func archive() -> Dictionary:
	if not report.is_empty():
		flush()
		last_report = report.duplicate(true)
	return last_report.duplicate(true)


func load_archive() -> Dictionary:
	if not FileAccess.file_exists(archive_path):
		return {}
	var file := FileAccess.open(archive_path, FileAccess.READ)
	if file == null or file.get_length() > ARCHIVE_MAX_BYTES:
		return {}
	var value: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(value) != TYPE_DICTIONARY or value.get("format") != "openrc-accident-report v1":
		return {}
	# Disk history is presentation-only; it never enters a new flight's ledger or credits a wallet.
	if typeof(value.get("identity")) != TYPE_DICTIONARY or typeof(value.get("lines")) != TYPE_ARRAY \
		or typeof(value.get("unresolved")) != TYPE_ARRAY or typeof(value.get("complete")) != TYPE_BOOL:
		return {}
	for line: Variant in value.lines:
		if typeof(line) != TYPE_DICTIONARY:
			return {}
	for reason: Variant in value.unresolved:
		if typeof(reason) != TYPE_STRING:
			return {}
	for field: String in ["known_subtotal_minor", "salvage_minor", "total_minor", "low_minor", "high_minor", "replacement_minor"]:
		var amount: Variant = value.get(field)
		if amount != null and (typeof(amount) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(amount)) \
			or float(amount) < 0.0 or float(amount) != floor(float(amount)) or float(amount) > 9000000000000000.0):
			return {}
	if value.complete and value.get("total_minor") == null:
		return {}
	last_report = value.duplicate(true)
	return last_report.duplicate(true)
