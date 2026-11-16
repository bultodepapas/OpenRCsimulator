## Fixed opt-in package diagnostic. It observes the ordinary route; it never
## selects a backend, creates a marker or changes the player's preferences.
extends Node

const Admission := preload("res://sim/native_macos_admission.gd")
const PackageAdmission := preload("res://sim/native_macos_package_admission.gd")
const Domain := preload("res://sim/native_macos_domain.gd")
const NativePackage := preload("res://app_state/native_package.gd")
const PREFIX := "PACKAGE_DEFAULT_PROBE "
const WAIT_MSEC := 180000
const AIRCRAFT := "jensen-das-ugly-stik-60"

var mode := ""
var package: Dictionary = {}
var user_directory := ""
var marker_path := ""
var marker_sha := ""
var phases: Array[Dictionary] = []
var finished := false
var ready_to_exit := false
var app_ref: WeakRef


func prepare(value: String, identity: Dictionary, private_user_directory: String) -> bool:
	mode = value
	package = identity.duplicate(true)
	user_directory = private_user_directory
	if ClassDB.class_exists("OpenRCNativeKernel") or not package.get("ok", false) \
			or DisplayServer.get_name() == "headless" or AudioServer.get_driver_name() in ["", "Dummy"]: return false
	var bundle := OS.get_executable_path().get_base_dir().get_base_dir().get_base_dir()
	marker_path = bundle + PackageAdmission.MARKER_SUFFIX
	var parent := DirAccess.open(bundle.get_base_dir())
	if parent == null or parent.is_link(marker_path.get_file()): return false
	var expected := OS.get_environment("OPENRC_PACKAGE_DEFAULT_EXPECT_MARKER_SHA256")
	if mode == "missing":
		if FileAccess.file_exists(marker_path) or not expected.is_empty(): return false
	else:
		marker_sha = FileAccess.get_sha256(marker_path)
		if marker_sha.length() != 64 or marker_sha != expected: return false
		if mode == "malformed" and not Admission._read_document(marker_path).is_empty(): return false
		if mode in ["candidate", "reference"] and Admission._read_document(marker_path).is_empty(): return false
	return true


func _ready() -> void:
	_run.call_deferred()


func _wait_for(condition: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + WAIT_MSEC
	while Time.get_ticks_msec() < deadline:
		if condition.call(): return true
		if finished: return false
		await get_tree().process_frame
	return false


func _run() -> void:
	if not await _wait_for(func() -> bool:
		var current := get_tree().current_scene
		return is_instance_valid(current) and current.has_method("start_flight")):
		_fail("AppRoot did not become available")
		return
	var app := get_tree().current_scene
	app_ref = weakref(app)
	app.tree_exiting.connect(_on_app_exiting, CONNECT_ONE_SHOT)
	if mode != "reference":
		if not await _wait_for(func() -> bool:
			return is_instance_valid(app) and app.has_home and app.home != null and not app.home_build_pending \
				and app.screens.is_top("home")):
			_fail("ordinary Home did not become ready")
			return
		if app.home.aircraft_id != AIRCRAFT or not is_instance_valid(app.menu_audio):
			_fail("qualified stock Home or menu audio unavailable")
			return
		phases.append({phase = "home", aircraft = app.home.aircraft_id, menu_audio = true})
		app.start_flight()
	if not await _flight_ready(app): return
	if not _inspect_flight(app, "flight"): return
	if mode != "reference":
		app.open_pause()
		if not await _wait_for(func() -> bool:
			return is_instance_valid(app) and app.pause_menu != null and app.screens.is_top("pause") \
				and is_instance_valid(app.flight) and app.flight.session.sim.paused):
			_fail("ordinary pause did not settle")
			return
		phases.append({phase = "pause", paused = true})
		app.restart_flight()
		if not await _wait_for(func() -> bool:
			return is_instance_valid(app) and is_instance_valid(app.flight) and app.pause_menu == null \
				and app.flight.session.is_flyable() and not app.flight.session.sim.paused):
			_fail("ordinary restart did not settle")
			return
		if not await _flight_ready(app): return
		if not _inspect_flight(app, "restart"): return
		app.open_pause()
		if not await _wait_for(func() -> bool: return is_instance_valid(app) and app.pause_menu != null):
			_fail("second pause did not settle")
			return
		app.end_flight()
		if not await _wait_for(func() -> bool:
			return is_instance_valid(app) and app.flight == null and app.home != null \
				and not app.home_build_pending and app.screens.is_top("home")):
			_fail("ordinary return Home did not settle")
			return
		phases.append({phase = "returned_home"})
		app.start_flight()
		if not await _flight_ready(app): return
		if not _inspect_flight(app, "reentry"): return
	if NativePackage.mac_native_identity(OS.get_executable_path(), Engine.get_architecture_name(),
			OS.get_cmdline_args() + OS.get_cmdline_user_args()) != package or not _marker_unchanged():
		_fail("package or marker changed during the route")
		return
	ready_to_exit = true
	app.quit_app()
	if not await _wait_for(func() -> bool: return finished):
		_fail("normal audio-enabled shutdown did not finish")


func _flight_ready(app: Node) -> bool:
	if not await _wait_for(func() -> bool:
		return is_instance_valid(app) and is_instance_valid(app.flight) and app.flight.startup_complete \
			and is_instance_valid(app.flight.session) and app.flight.session.is_flyable() \
			and is_instance_valid(app.flight.session.sim) and app.flight.session.sim.tick > 0):
		_fail("ordinary flight did not become active")
		return false
	return true


func _inspect_flight(app: Node, label: String) -> bool:
	var flight: Node = app.flight
	var session: Node = flight.session
	var expected := "native" if mode == "candidate" else "gdscript_reference"
	var requested := "gdscript_reference" if mode == "reference" else "native"
	var status: Dictionary = session.stage_backend_status()
	var identity: Variant = status.get("identity")
	if flight.aircraft_id != AIRCRAFT or not identity is Dictionary or identity.get("backend") != expected \
			or status.get("requested") != requested or not session.automatic_native_macos \
			or session.experimental_native_macos or not is_instance_valid(flight._soundscape_audio):
		_fail("flight backend, aircraft or soundscape differs")
		return false
	if mode in ["missing", "malformed"] and not str(status.get("reason", "")).contains("qualification"):
		_fail("fallback did not report the missing package qualification")
		return false
	if mode in ["candidate", "reference"] and not str(status.get("reason", "")).is_empty():
		_fail("selected backend reports an admission failure")
		return false
	if mode != "reference":
		for argument: String in flight.user_args:
			if argument.begins_with("--physics-backend") or argument.begins_with("--experimental-native-macos"):
				_fail("automatic flight was given a backend override")
				return false
	# The fallback cases must use the same screened selection as the admitted
	# case. Reporting only the aircraft would let a different weather/start
	# explain a reference fallback and make the marker control inconclusive.
	var selection := {}
	if mode != "reference":
		var screened: Dictionary = Domain.screen_session(session, true)
		if screened.get("ok") != true or screened.get("profile") != "production":
			_fail("Home flight is outside the screened production domain")
			return false
		selection = {aircraft = screened.get("aircraft"), battery = screened.get("battery"),
			start = screened.get("start"), weather = screened.get("weather"), soft_hull = session.soft_hull_contacts,
			trim_profile = screened.get("profile"), start_sha256 = screened.get("start_sha256")}
	var stats := {}
	if expected == "native":
		if not is_instance_valid(session._native_stage) or not is_instance_valid(session._native_stage._native):
			_fail("native backend is not installed")
			return false
		stats = session._native_stage._native.stage_stats()
		if int(stats.get("context_calls", 0)) < 1 or int(stats.get("stage_calls", 0)) < 4:
			_fail("native stage did not execute")
			return false
	phases.append({phase = label, backend = expected, tick = session.sim.tick, selection = selection,
		soundscape_installed = true, status = status, native_stats = stats})
	return true


func _marker_unchanged() -> bool:
	var parent := DirAccess.open(marker_path.get_base_dir())
	if parent == null or parent.is_link(marker_path.get_file()): return false
	if mode == "missing": return not FileAccess.file_exists(marker_path)
	return FileAccess.file_exists(marker_path) and FileAccess.get_sha256(marker_path) == marker_sha


func _on_app_exiting() -> void:
	var app: Node = app_ref.get_ref() if app_ref != null else null
	if not ready_to_exit or not is_instance_valid(app):
		_fail("application exited before the requested route completed")
		return
	var audio: Variant = app.last_quit_audio_retirement
	if not audio is Dictionary or audio.get("complete") != true or audio.get("timed_out") != false \
			or int(audio.get("pending_playbacks", -1)) != 0 or not _marker_unchanged():
		_fail("normal audio retirement or marker continuity failed")
		return
	phases.append({phase = "menu_audio_retired", receipt = audio})
	_emit("pass", "")


func _fail(reason: String) -> void:
	_emit("fail", reason)
	get_tree().quit(1)


func _emit(verdict: String, reason: String) -> void:
	if finished: return
	finished = true
	print(PREFIX + JSON.stringify({verdict = verdict, reason = reason, mode = mode, pid = OS.get_process_id(),
		executable = OS.get_executable_path(), user_directory = OS.get_user_data_dir(), marker_sha256 = marker_sha,
		profile_home = OS.get_environment("HOME").simplify_path(),
		profile_token_sha256 = OS.get_environment("OPENRC_PACKAGE_DEFAULT_PROFILE_TOKEN_SHA256"),
		audio_driver = AudioServer.get_driver_name(), package_identity = package, phases = phases,
		scope = "fixed isolated package route; no physical radio, presentation or performance claim"}))
