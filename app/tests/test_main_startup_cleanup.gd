## Main owns any session it builds before parenting it. A rejected launch must dispose of that session,
## and an unusable finite-fuel selection must fail before the session joins the flight tree.
extends SceneTree

const Main := preload("res://main.gd")
const Preferences := preload("res://app_state/preferences.gd")
const UiDriver := preload("res://tests/ui_driver.gd")

const AVANTI := "sebart-avanti-s-a200-p100rx"

var _checks := 0
var _failures := 0
var _ui: RefCounted
var _qa_dir := ""
var _prefs := ""
var _update_state := ""


func _initialize() -> void:
	_ui = UiDriver.new(self)
	_qa_dir = ProjectSettings.globalize_path("user://test_main_startup_cleanup_%d" % OS.get_process_id())
	_prefs = _qa_dir.path_join("preferences.cfg")
	_update_state = _qa_dir.path_join("update-state.json")
	call_deferred("_run")


func _check(label: String, passed: bool, detail: Variant = "") -> void:
	_checks += 1
	if not passed:
		_failures += 1
		printerr("FAIL %s %s" % [label, str(detail)])
	else:
		print("PASS ", label)


func _orphans() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))


func _new_main(args: PackedStringArray) -> Node:
	var flight: Node = Main.new()
	flight.interactive_start = true
	flight.external_controller_selection = true
	flight.set_user_args(args)
	return flight


func _silence_audio(node: Node) -> void:
	if node is AudioStreamPlayer3D:
		var player_3d: AudioStreamPlayer3D = node as AudioStreamPlayer3D
		player_3d.stop()
		player_3d.stream = null
	elif node is AudioStreamPlayer2D:
		var player_2d: AudioStreamPlayer2D = node as AudioStreamPlayer2D
		player_2d.stop()
		player_2d.stream = null
	elif node is AudioStreamPlayer:
		var player: AudioStreamPlayer = node as AudioStreamPlayer
		player.stop()
		player.stream = null
	for child: Node in node.get_children():
		_silence_audio(child)


func _close_main(flight: Node) -> void:
	if not is_instance_valid(flight):
		return
	flight.set_process(false)
	flight.set_physics_process(false)
	var session: Node = flight.session
	if is_instance_valid(session):
		session.set_process(false)
		session.set_physics_process(false)
		if session.sim != null:
			session.sim.set_paused(true)
		if flight.recorder != null:
			flight.recorder.detach()
			flight.recorder = null
	_silence_audio(flight)
	var drain_until_usec: int = Time.get_ticks_usec() + 50000
	while Time.get_ticks_usec() < drain_until_usec:
		await process_frame
	if flight.get_parent() == root:
		root.remove_child(flight)
	flight.free()
	await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	await process_frame


func _test_main_refusal(label: String, args: PackedStringArray, expected_error: String) -> void:
	var before_orphans: int = _orphans()
	var flight: Node = _new_main(args)
	root.add_child(flight) # _ready runs the production Main startup path synchronously.
	var message := str(flight.startup_error)
	_check(label + " reports the expected startup refusal", message.contains(expected_error), message)
	_check(label + " clears the refused session immediately", flight.session == null)
	_check(label + " does not create orphan nodes", _orphans() == before_orphans,
		"before=%d after=%d" % [before_orphans, _orphans()])
	await _close_main(flight)
	_check(label + " returns to the prior orphan count after Main deletion", _orphans() == before_orphans,
		"before=%d after=%d" % [before_orphans, _orphans()])


func _test_valid_fuel_fill(args: PackedStringArray, expected_fill: float) -> void:
	var flight: Node = _new_main(args)
	flight.aircraft_id = AVANTI
	flight.fuel_start_fill = expected_fill
	root.add_child(flight)
	var session: Node = flight.session
	if not is_instance_valid(session):
		_check("valid fuel fill %s creates a session" % str(expected_fill), false, flight.startup_error)
		await _close_main(flight)
		return
	# Capture the production session state before the first frame or physics tick can run.
	var initial_tick: int = int(session.sim.tick)
	var initial_checkpoint: Dictionary = session.checkpoint()
	var initial_checkpoint_bytes: PackedByteArray = var_to_bytes(initial_checkpoint)
	var initial_mass: Dictionary = session.mass_properties()
	var expected_fuel_kg: float = float(session.start_fuel_kg())
	_check("valid fuel fill %s starts with an exact tick-zero snapshot" % str(expected_fill),
		initial_tick == 0 and not initial_checkpoint.is_empty() and not initial_checkpoint_bytes.is_empty()
		and initial_checkpoint_bytes == var_to_bytes(session.checkpoint()),
		"tick=%d bytes=%d" % [initial_tick, initial_checkpoint_bytes.size()])
	_check("valid fuel fill %s is selected before startup completes" % str(expected_fill),
		flight.startup_error.is_empty() and session.is_flyable()
		and is_equal_approx(float(session.fuel_start_fill), expected_fill)
		and is_equal_approx(float(initial_mass.get("fuel_remaining_kg", -1.0)), expected_fuel_kg),
		"selected=%s remaining=%s expected=%s" % [str(session.fuel_start_fill),
		str(initial_mass.get("fuel_remaining_kg", -1.0)), str(expected_fuel_kg)])
	await physics_frame
	await physics_frame
	_check("valid fuel fill %s advances through normal physics" % str(expected_fill),
		int(session.sim.tick) > initial_tick and str(session.sim.fault_reason).is_empty(),
		"tick=%d fault=%s" % [session.sim.tick, session.sim.fault_reason])
	await _close_main(flight)


func _prepare_private_preferences() -> bool:
	if not DirAccess.dir_exists_absolute(_qa_dir) and DirAccess.make_dir_recursive_absolute(_qa_dir) != OK:
		return false
	for path: String in [_prefs, _prefs + ".display", _prefs + ".controllers", _prefs + ".legacy_rc", _update_state]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	var preferences: Dictionary = Preferences.DEFAULTS.duplicate(true)
	preferences.first_flight_hint_seen = true
	preferences.start_choice = "airborne"
	return Preferences.save_to(_prefs, preferences) == OK


func _cleanup_private_preferences() -> void:
	if not DirAccess.dir_exists_absolute(_qa_dir):
		return
	for file_name: String in DirAccess.get_files_at(_qa_dir):
		DirAccess.remove_absolute(_qa_dir.path_join(file_name))
	DirAccess.remove_absolute(_qa_dir)


func _test_home_rollback() -> void:
	if not _prepare_private_preferences():
		_check("private Home preferences initialize", false, _prefs)
		return
	TranslationServer.set_locale("en")
	var app: Node = load("res://app_root.tscn").instantiate()
	app.user_args = PackedStringArray()
	app.preferences_path = _prefs
	app.update_state_path = _update_state
	app.update_check_url = "http://127.0.0.1:1/unavailable"
	root.add_child(app)
	await _ui.settle()
	if app.home == null:
		_check("AppRoot reaches Home for the rollback test", false)
		await _ui.close_app(app)
		return
	app.controllers.select_devices(-1, -1)
	var home: Node = app.home
	home.set_aircraft(AVANTI)
	# Inject a value that Home never offers, then use the real Fly button to exercise AppRoot's rollback.
	home.fuel_start_fill = 0.001
	home.fly_button.grab_focus()
	await _ui.tap(KEY_ENTER)
	await _ui.settle()
	var restored_home: Node = app.home
	_check("failed Home launch returns to the Home screen", app.flight == null
		and restored_home != null and app.screens.is_top("home"),
		"flight=%s screen=%s" % [str(app.flight), str(app.screens.top())])
	_check("Home displays the rejected finite-fuel launch reason", restored_home != null
		and restored_home.note_label.visible and restored_home.note_label.text.contains("Fuel fill refused"),
		str(restored_home.note_label.text if restored_home != null else "no Home"))
	await _ui.close_app(app)


func _run() -> void:
	TranslationServer.set_locale("en")
	if DisplayServer.get_name() != "headless":
		var native_size: Vector2i = DisplayServer.window_get_size()
		_check("native functional fixture uses the primary 1920x1080 target", native_size == Vector2i(1920, 1080),
			str(native_size))
	var baseline_orphans: int = _orphans()
	await _test_main_refusal("invalid failure probability", PackedStringArray(["--failures=101"]), "between 0 and 100")
	await _test_main_refusal("unknown weather preset", PackedStringArray(["--weather=qa-round3-unknown"]), "qa-round3-unknown")
	await _test_main_refusal("range-valid but unusable fuel fill", PackedStringArray([
		"--aircraft=" + AVANTI, "--fuel=0.001"]), "Fuel fill refused")
	await _test_valid_fuel_fill(PackedStringArray(["--aircraft=" + AVANTI, "--fuel=0.25"]), 0.25)
	await _test_valid_fuel_fill(PackedStringArray(["--aircraft=" + AVANTI]), 1.0)
	await _test_home_rollback()
	_check("startup probes leave no orphan-node increase", _orphans() == baseline_orphans,
		"before=%d after=%d" % [baseline_orphans, _orphans()])
	_cleanup_private_preferences()
	print("Main startup cleanup: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
