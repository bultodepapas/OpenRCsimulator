extends SceneTree

const Reflex := preload("res://render/nvidia_reflex.gd")
const Preferences := preload("res://app_state/display_preferences.gd")
const Reconstruction := preload("res://render/reconstruction.gd")
const PREFS := "user://test_nvidia_reflex.cfg"

class FakeBackend:
	extends RefCounted
	var state: Variant = {"available": false, "backend_failed": false, "applied_mode": -1}
	var calls: Array = []
	func get_reflex_status() -> Variant:
		return state
	func set_parameter(parameter: int, value: int) -> void:
		calls.append([parameter, value])

class MissingApi:
	extends RefCounted

var checks := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check("settings and runtime list the same modes", Preferences.NVIDIA_REFLEX_MODES == Reflex.MODES)
	_check("legacy preferences default to On", Preferences.validate(_legacy_candidate()).config.nvidia_reflex == "on")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	var legacy := ConfigFile.new()
	legacy.set_value("meta", "schema", Preferences.SCHEMA)
	legacy.set_value("graphics", "max_fps", 120)
	_check("write a legacy display file", legacy.save(PREFS) == OK)
	var migrated := Preferences.load_from(PREFS)
	_check("missing Reflex field migrates without changing other settings", migrated.nvidia_reflex == "on"
		and migrated.max_fps == 120 and migrated.writable and migrated.note.is_empty())
	for mode: String in Reflex.MODES:
		var candidate := Preferences.DEFAULTS.duplicate(true)
		candidate.nvidia_reflex = mode
		_check("mode round trips: " + mode, Preferences.save_to(PREFS, candidate) == OK
			and Preferences.load_from(PREFS).nvidia_reflex == mode)
	for invalid: Variant in ["ON", "", "ultra", 1, true, null]:
		var candidate := Preferences.DEFAULTS.duplicate(true)
		candidate.nvidia_reflex = invalid
		_check("invalid setting is rejected: " + str(invalid), not Preferences.validate(candidate).ok
			and Preferences.save_to(PREFS, candidate) == ERR_INVALID_DATA)
	var malformed := ConfigFile.new()
	malformed.set_value("meta", "schema", Preferences.SCHEMA)
	malformed.set_value("graphics", "max_fps", 120)
	malformed.set_value("graphics", "nvidia_reflex", "invalid")
	_check("write malformed preference", malformed.save(PREFS) == OK)
	var recovered := Preferences.load_from(PREFS)
	_check("malformed Reflex alone reverts to its default", recovered.nvidia_reflex == "on"
		and recovered.max_fps == 120 and recovered.note.contains("invalid display values"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))

	var had_env := OS.has_environment(Reflex.ENVIRONMENT_KEY)
	var old_env := OS.get_environment(Reflex.ENVIRONMENT_KEY)
	OS.unset_environment(Reflex.ENVIRONMENT_KEY)
	_check("direct startup defaults to On", Reconstruction.startup_config().nvidia_reflex == "on")
	OS.set_environment(Reflex.ENVIRONMENT_KEY, " BOOST ")
	_check("direct startup accepts explicit Boost", Reconstruction.startup_config().nvidia_reflex == "boost")
	OS.set_environment(Reflex.ENVIRONMENT_KEY, "invalid")
	_check("invalid startup override fails safely to Off", Reconstruction.startup_config().nvidia_reflex == "off")
	if had_env:
		OS.set_environment(Reflex.ENVIRONMENT_KEY, old_env)
	else:
		OS.unset_environment(Reflex.ENVIRONMENT_KEY)

	var backend := FakeBackend.new()
	var status := Reflex.describe("on", backend, 17)
	_check("pending availability does not claim an accepted mode", not status.available
		and status.accepted == "unconfirmed" and status.reason == "unavailable")
	_check("Off remains selectable when unsupported", Reflex.option_status("off", status).available)
	_check("On and Boost are gated by actual capability", not Reflex.option_status("on", status).available
		and not Reflex.option_status("boost", status).available)
	Reflex.apply("on", backend, 17)
	_check("startup request is sent while capability is pending", backend.calls == [[17, 1]])
	backend.state = {"available": true, "backend_failed": false, "applied_mode": 0}
	status = Reflex.describe("on", backend, 17)
	_check("available but not yet accepted is pending", status.available and status.pending and status.accepted == "off")
	_check("supported Boost is selectable", Reflex.option_status("boost", status).available)
	backend.state.applied_mode = 1
	status = Reflex.describe("on", backend, 17)
	_check("SDK acceptance is reported separately", status.available and not status.pending and status.accepted == "on")
	Reflex.apply("boost", backend, 17)
	Reflex.apply("on", backend, 17) # cancellation restores the saved request
	_check("preview rollback sends the previous mode", backend.calls.slice(-2) == [[17, 2], [17, 1]])
	Reflex.apply("invalid", backend, 17)
	_check("invalid runtime requests fail safely to Off", backend.calls.back() == [17, 0])
	backend.state = {"available": false, "backend_failed": true, "applied_mode": 0, "failure_result": 42}
	status = Reflex.describe("boost", backend, 17)
	_check("failure keeps the request and exposes accepted Off and evidence", status.requested == "boost"
		and status.accepted == "off" and status.reason == "runtime_failure" and status.backend.failure_result == 42)
	backend.state = {"available": true, "backend_failed": false}
	var calls_before := backend.calls.size()
	Reflex.apply("on", backend, 17)
	status = Reflex.describe("on", backend, 17)
	_check("malformed status cannot enable or claim support", backend.calls.size() == calls_before
		and not status.available and status.reason == "status_invalid" and status.accepted == "unconfirmed")
	for invalid_state: Dictionary in [
		{"available": "yes", "backend_failed": false, "applied_mode": 1},
		{"available": true, "backend_failed": 0, "applied_mode": 1},
		{"available": true, "backend_failed": false, "applied_mode": 3},
	]:
		backend.state = invalid_state
		Reflex.apply("on", backend, 17)
		status = Reflex.describe("on", backend, 17)
		_check("invalid status types and modes do not advertise support", backend.calls.size() == calls_before
			and not status.available and status.reason == "status_invalid")
	var missing := Reflex.describe("on", MissingApi.new(), 17)
	_check("missing API is a safe unsupported result", not missing.available and missing.reason == "support_missing")
	_check("invalid injected option does not advertise support", not Reflex.option_status("boost", {"available": "yes"}).available)
	if not Engine.has_singleton(Reflex.SINGLETON):
		var stock := Reflex.describe("on")
		_check("official engine reports unavailable without claiming SDK acceptance",
			not stock.available and stock.reason == "support_missing" and stock.accepted == "unconfirmed")
		var config := Preferences.DEFAULTS.duplicate(true)
		config.nvidia_reflex = "boost"
		Reconstruction.apply(root, config)
		var receipt := Reconstruction.describe(root)
		_check("viewport receipt preserves request on official engine", receipt.nvidia_reflex.requested == "boost"
			and not receipt.nvidia_reflex.available and config.nvidia_reflex == "boost")
	print("NVIDIA Reflex: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)


func _legacy_candidate() -> Dictionary:
	var candidate := Preferences.DEFAULTS.duplicate(true)
	candidate.erase("nvidia_reflex")
	return candidate


func _check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)
