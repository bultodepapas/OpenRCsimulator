# AI companions through Home, flight, Pause and Restart. Run with the normal Godot UI test suite.
extends SceneTree

const CompanionsDialog := preload("res://ui/companions_dialog.gd")
const CompanionConfig := preload("res://ai/companions/config.gd")
const AppRoot := preload("res://app_root.gd")
const Preferences := preload("res://app_state/preferences.gd")
const UiDriver := preload("res://tests/ui_driver.gd")
const UiInput := preload("res://ui/ui_input.gd")
const LogReader := preload("res://tools/flight_log_cli.gd")

const PREFS := "user://test_companions_shell_settings.cfg"
const FUTURE_PREFS := "user://test_companions_shell_future.cfg"

var _failures := 0
var ui: RefCounted


func _check(label: String, ok: bool, detail := "") -> void:
	if ok:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _initialize() -> void:
	# AFC-02-R3: a logic suite; tests/test_companions_profiles.gd alone gates the pinned solver identity.
	preload("res://ai/companions/profile_loader.gd").accept_current_solver_for_tests()
	_run.call_deferred()


func _run() -> void:
	TranslationServer.set_locale("en")
	InputMap.load_from_project_settings()
	UiInput.isolate_joypads()
	ui = UiDriver.new(self)
	root.size = Vector2i(1280, 720)
	_remove_file(PREFS)
	_remove_file(FUTURE_PREFS)
	if not CompanionConfig.engine_qualified():
		await _check_unqualified_engine_shell()
		_remove_file(PREFS)
		UiInput.isolate_joypads()
		print("Companions shell: %d failed" % _failures)
		quit(1 if _failures else 0)
		return

	var app: Variant = load("res://app_root.tscn").instantiate()
	app.user_args = PackedStringArray()
	app.preferences_path = PREFS
	root.add_child(app)
	await ui.settle()
	var defaults: Dictionary = CompanionConfig.defaults()
	_check("rotorcraft direct route rejects an enabled companion group",
		AppRoot.companion_cli_options_unsupported_for_aircraft("xcell-60-research", PackedStringArray(["--companions=3"])))
	_check("rotorcraft direct route allows an explicitly disabled group",
		not AppRoot.companion_cli_options_unsupported_for_aircraft("xcell-60-research", PackedStringArray(["--companions=0"])))
	_check("fixed-wing direct route keeps enabled companions available",
		not AppRoot.companion_cli_options_unsupported_for_aircraft(CompanionConfig.AIRCRAFT_ID, PackedStringArray(["--companions=3"])))
	_check("non-companion direct arguments leave companions disabled",
		CompanionConfig.from_args(PackedStringArray(["--quick-flight", "--aircraft=xcell-60-research"])).config == defaults)
	for invalid_companion_arg in ["--companions", "--companions=4", "--companions=-1", "--companions=1.5",
		"--companions-seed", "--companions-seed=-1", "--companions-seed=4294967296"]:
		_check("direct companion CLI validates %s" % invalid_companion_arg,
			not CompanionConfig.from_args(PackedStringArray([invalid_companion_arg])).get("ok", false))
	_check("Home companions default Off with count 1 and seed 1",
		app.home.companion_config == defaults and not app.home.companions_button.disabled
		and app.home.companions_button.tooltip_text.contains("Off"), str(app.home.companion_config))
	app.home.set_landscape("green_paradise")
	_check("Home companions are disabled outside Club Field", app.home.companions_button.disabled)
	app.home.set_landscape("club_field")

	# Cancel discards the Home draft and leaves the on-disk preference at defaults.
	await _open_home_companions(app)
	var dialog: CompanionsDialog = app.companions_dialog
	_check("Home opens the companions dialog through the shell", dialog != null and app.screens.is_top("companions"))
	dialog.enabled_check.button_pressed = true
	dialog.count_picker.select(1)
	dialog.seed_edit.text = "27"
	await ui.tap(KEY_ESCAPE)
	await ui.settle()
	var persisted: Dictionary = Preferences.load_from(PREFS)
	_check("Home Cancel preserves preferences and the live Home draft",
		app.home.companion_config == defaults and persisted.companion_config == defaults,
		str(persisted.companion_config))

	# Apply writes the validated config as an additive preference.
	await _open_home_companions(app)
	dialog = app.companions_dialog
	dialog.enabled_check.button_pressed = true
	dialog.count_picker.select(2)
	dialog.seed_edit.text = "101"
	dialog.apply_button.grab_focus()
	await ui.tap(KEY_ENTER)
	await ui.settle()
	var applied_config := defaults.duplicate(true)
	applied_config.enabled = true
	applied_config.count = 3
	applied_config.seed = 101
	persisted = Preferences.load_from(PREFS)
	_check("Home Apply persists the checked count and seed", persisted.companion_config == applied_config,
		str(persisted.companion_config))
	_check("Home summary reflects the saved choice", app.home.companions_button.text.contains("Flight companions")
		and app.home.companions_button.text.contains("On")
		and app.home.companions_button.text.contains("3")
		and app.home.companions_button.tooltip_text.contains("On")
		and app.home.companions_button.tooltip_text.contains("3")
		and app.home.companions_button.tooltip_text.contains("101"),
		app.home.companions_button.text)

	# Start a normal Home flight with three actual AI pilots.
	app.home.fly_button.grab_focus()
	await ui.tap(KEY_ENTER)
	await ui.settle()
	var flight: Node = app.flight
	var launched_three := false
	if flight != null:
		launched_three = await _wait_for_active(flight, 3)
	_check("Home flight receives the saved companion config before startup",
		flight != null and flight.companion_config == applied_config, str(flight.get("companion_config")))
	_check("the manager starts three real AI pilots", launched_three
		and flight.companions != null and flight.companions.agents.size() == 3,
		str(flight.call("companion_status")) if flight != null else "no flight")

	# Pause owns the frozen flight. Cancel must not change its next-restart config.
	app.open_pause()
	await ui.settle()
	var main: Node = app.flight
	var session: Node = main.session
	var paused_tick: int = session.sim.tick
	var paused_prop: float = main._prop_angle
	await _wait_frames(12)
	_check("Pause freezes simulation ticks and propeller angle",
		session.sim.paused and session.sim.tick == paused_tick and main._prop_angle == paused_prop)
	await _open_pause_companions(app)
	dialog = app.companions_dialog
	_check("Pause dialog reports all three active pilots",
		dialog != null and dialog.status_label.text.contains("3 active / 3 requested"),
		dialog.status_label.text if dialog != null else "missing dialog")
	var flight_config_before: Dictionary = main.companion_config.duplicate(true)
	dialog.count_picker.select(0)
	dialog.seed_edit.text = "5"
	dialog.volume_slider.value = 0.0
	dialog.labels_check.button_pressed = true
	await ui.tap(KEY_ESCAPE)
	await ui.settle()
	_check("Pause Cancel leaves the flight config and active group unchanged",
		main.companion_config == flight_config_before and main.companion_status().active == 3,
		str(main.companion_config))
	_check("Cancel preserves live companion presentation", main.companions.agents[0]._engine_volume == 1.0
		and not main.companions.agents[0]._show_labels)

	# Apply changes the configuration for Restart; live pilots remain the original three until then.
	await _open_pause_companions(app)
	dialog = app.companions_dialog
	dialog.count_picker.select(1)
	dialog.seed_edit.text = "202"
	dialog.volume_slider.value = 0.0
	dialog.labels_check.button_pressed = true
	dialog.label_distance.value = 500.0
	var live_agent: Node = main.companions.agents[0]
	var live_state: PackedByteArray = live_agent.session.sim.state.to_byte_array()
	dialog.apply_button.grab_focus()
	await ui.tap(KEY_ENTER)
	await ui.settle()
	_check("Pause Apply stages two pilots for the next restart",
		main.companion_config.count == 2 and main.companion_config.seed == 202
		and main.companion_status().active == 3 and main.companions.agents.size() == 3,
		str(main.companion_status()))
	_check("sound and labels apply without replacing or advancing the paused flight",
		main.companions.agents[0] == live_agent and live_agent._engine_volume == 0.0
		and live_agent._show_labels and live_agent._label_distance_m == 500.0
		and live_agent._traffic_label != null and live_agent._engine.volume_db == -80.0
		and live_agent.session.sim.state.to_byte_array() == live_state)

	# Restart uses Main's deferred manager rebuild after the session reset.
	app.pause_menu.restart_button.grab_focus()
	await ui.tap(KEY_ENTER)
	await ui.settle()
	var restarted_two: bool = await _wait_for_active(main, 2)
	_check("Restart rebuilds the live group from the staged count",
		restarted_two and main.companions.agents.size() == 2
		and app.pause_menu == null, str(main.companion_status()))

	# Saving as default is explicit and remains separate from the live restart behavior.
	app.open_pause()
	await ui.settle()
	await _open_pause_companions(app)
	dialog = app.companions_dialog
	dialog.save_default_check.grab_focus()
	await ui.tap(KEY_ENTER)
	dialog.apply_button.grab_focus()
	await ui.tap(KEY_ENTER)
	await ui.settle()
	persisted = Preferences.load_from(PREFS)
	_check("Pause Save as default is the only Pause action that persists",
		persisted.companion_config.enabled and persisted.companion_config.count == 2
		and persisted.companion_config.seed == 202, str(persisted.companion_config))

	# A failed default save must undo the staged flight change, so Cancel still discards the whole Apply.
	var before_failed_save: Dictionary = main.companion_config.duplicate(true)
	app.preferences_path = PREFS + "/missing/prefs.cfg"
	await _open_pause_companions(app)
	dialog = app.companions_dialog
	dialog.count_picker.select(0)
	dialog.seed_edit.text = "303"
	dialog.volume_slider.value = 80.0
	dialog.labels_check.button_pressed = false
	dialog.save_default_check.grab_focus()
	await ui.tap(KEY_ENTER)
	dialog.apply_button.grab_focus()
	await ui.tap(KEY_ENTER)
	await ui.settle()
	_check("Pause save failure rolls the staged flight config back",
		main.companion_config == before_failed_save and dialog.error_label.visible,
		str(main.companion_config))
	_check("failed save also restores live presentation", main.companions.agents[0]._engine_volume == 0.0
		and main.companions.agents[0]._show_labels)
	_check("Pause save failure preserves the previous on-disk default",
		Preferences.load_from(PREFS).companion_config == persisted.companion_config)
	await ui.tap(KEY_ESCAPE)
	await ui.settle()
	_check("Cancel after a failed save leaves the flight config unchanged",
		main.companion_config == before_failed_save)
	app.preferences_path = PREFS

	# Remove now clears the present group and refreshes the manager status without changing defaults.
	await _open_pause_companions(app)
	dialog = app.companions_dialog
	_check("Remove now appears for an active group", dialog.remove_button.visible)
	dialog.remove_button.grab_focus()
	await ui.tap(KEY_ENTER)
	await ui.settle()
	var removed_all: bool = await _wait_for_active(main, 0)
	_check("Remove now leaves no active AI pilots", removed_all
		and main.companions.agents.is_empty() and not dialog.remove_button.visible,
		str(main.companion_status()))
	_check("Remove now does not rewrite the saved default",
		Preferences.load_from(PREFS).companion_config == persisted.companion_config)

	# A higher schema remains read-only even though this setting uses an additive section.
	var future_cfg := ConfigFile.new()
	future_cfg.set_value("meta", "schema", Preferences.SCHEMA + 1)
	future_cfg.set_value("companions", "config", applied_config)
	_check("future preferences fixture writes", future_cfg.save(FUTURE_PREFS) == OK)
	var future := Preferences.load_from(FUTURE_PREFS)
	var future_before := FileAccess.get_file_as_string(FUTURE_PREFS)
	_check("future schema stays protected", not future.writable
		and Preferences.save_to(FUTURE_PREFS, future) == ERR_FILE_NO_PERMISSION
		and FileAccess.get_file_as_string(FUTURE_PREFS) == future_before)

	await ui.close_app(app)

	# The direct CLI route ignores the saved Home preference, but its fixed-wing Pause can still configure the flight.
	var direct: Variant = load("res://app_root.tscn").instantiate()
	direct.user_args = PackedStringArray(["--quick-flight"])
	direct.preferences_path = PREFS
	root.add_child(direct)
	await ui.settle()
	_check("direct CLI ignores saved Home companion settings",
		not direct.has_home and direct.flight != null and not direct.flight.companion_config.enabled,
		str(direct.flight.get("companion_config")) if direct.flight != null else "no flight")
	direct.open_pause()
	await ui.settle()
	_check("direct fixed-wing Pause keeps the flight settings entry", direct.pause_menu != null
		and direct.pause_menu.companions_button.visible)
	await ui.close_app(direct)
	await _check_capture_shell()

	_remove_file(PREFS)
	_remove_file(FUTURE_PREFS)
	UiInput.isolate_joypads()
	print("Companions shell: %d failed" % _failures)
	quit(1 if _failures else 0)


func _check_unqualified_engine_shell() -> void:
	var saved := Preferences.load_from(PREFS)
	saved.first_flight_hint_seen = true
	saved.companion_config.enabled = true
	saved.companion_config.count = 2
	saved.companion_config.seed = 42
	_check("enabled companion preference fixture saves", Preferences.save_to(PREFS, saved) == OK)
	var app: Variant = load("res://app_root.tscn").instantiate()
	app.user_args = PackedStringArray()
	app.preferences_path = PREFS
	root.add_child(app)
	await ui.settle()
	_check("Home explains that companions are unavailable on this build",
		app.home.companions_button.disabled and app.home.companions_button.text.contains("Unavailable")
		and app.home.companions_button.tooltip_text.contains("unavailable in this game build"))
	app.open_companions_settings()
	_check("unqualified engine cannot open the companion settings", app.companions_dialog == null)
	_check("Home retains the requested enabled preference", app.home.companion_config.enabled
		and app.home.companion_config.count == 2 and app.home.companion_config.seed == 42)
	app.home.fly_button.grab_focus()
	await ui.tap(KEY_ENTER)
	await ui.settle()
	var flight: Node = app.flight
	_check("saved companion request does not block a player flight", flight != null
		and flight.startup_error.is_empty() and flight.startup_complete and flight.session != null
		and flight.session.is_flyable() and not flight.companion_config.enabled and flight.companions == null,
		"no flight" if flight == null else str(flight.startup_error))
	var after: Dictionary = Preferences.load_from(PREFS)
	_check("starting the flight preserves the saved companion request", after.companion_config.enabled
		and after.companion_config.count == 2 and after.companion_config.seed == 42)
	if flight != null:
		app.open_pause()
		await ui.settle()
		_check("Pause cannot enable an unqualified companion roster", app.pause_menu != null
			and not app.pause_menu.companions_button.visible)
	await ui.close_app(app)


func _check_capture_shell() -> void:
	var destination := ProjectSettings.globalize_path("res://../tmp/afc-shell-capture-%d" % Time.get_ticks_usec())
	var app: Variant = load("res://app_root.tscn").instantiate()
	app.user_args = PackedStringArray(["--quick-flight", "--companions=1", "--companions-record=" + destination])
	app.preferences_path = PREFS
	root.add_child(app)
	await ui.settle()
	var main: Node = app.flight
	var state: Dictionary = main.companions.recording_status()
	main._electric_demo = "4s"
	_check("synthetic electric demo cannot enable companions or fleet capture",
		not main._companion_options(main.companion_config).ok)
	_check("synthetic electric demo retains explicit companion Off support",
		main._companion_options(CompanionConfig.defaults()).ok)
	main._electric_demo = ""
	_check("direct CLI starts a fleet capture before flight ticks", state.active
		and FileAccess.file_exists(destination.path_join("manifest.json")), str(state))
	_check("capture HUD distinguishes the fleet and leaves the separate player log idle",
		main._flight_log_label != null and main._flight_log_label.text.begins_with("FLEET REC")
		and not main.flight_log.recording)
	await ui.tap(KEY_F11)
	await ui.tap(KEY_F10)
	state = main.companions.recording_status()
	_check("F10 closes all streams without starting a second player log",
		not state.active and state.complete and not main.flight_log.recording, str(state))
	_check("capture HUD confirms a saved cohort", main._flight_log_label.text == "Fleet capture saved",
		main._flight_log_label.text)
	var marker_tick := -1
	for stream_name: String in ["player", "companion-0"]:
		var inspected: Dictionary = LogReader.inspect(destination.path_join(stream_name + ".orfl"))
		var marked := -1
		for event: Dictionary in inspected.get("events", []):
			if event.kind == "marker": marked = int(event.tick)
		_check("F11 marks the %s stream" % stream_name, inspected.get("complete", false) and marked >= 0,
			str(inspected.get("error", "marker missing")))
		if marker_tick < 0: marker_tick = marked
		else: _check("F11 marks every stream at the same tick", marked == marker_tick)
	var summary_before := FileAccess.get_file_as_bytes(destination.path_join("summary.json"))
	app.open_pause()
	await ui.settle()
	app.pause_menu.restart_button.grab_focus()
	await ui.tap(KEY_ENTER)
	await ui.settle()
	var active_after_restart: bool = await _wait_for_active(main, 1)
	_check("Restart rebuilds the companion without reusing its capture directory", active_after_restart
		and not main.companions.recording_status().active
		and FileAccess.get_file_as_bytes(destination.path_join("summary.json")) == summary_before)
	_check("capture directory is never saved in Home preferences",
		not FileAccess.get_file_as_string(PREFS).contains(destination))
	# UiDriver drains stopped audio for a few frames before removing the tree.
	# Freeze the live roster during that artificial drain, as Pause does in the UI.
	main.session.hold("test-close")
	await ui.close_app(app)


func _open_pause_companions(app: Node) -> void:
	var menu: CanvasLayer = app.pause_menu
	if not menu.session_options_container.visible:
		menu.session_options_button.grab_focus()
		await ui.tap(KEY_ENTER)
		await ui.settle()
	menu.companions_button.grab_focus()
	await ui.tap(KEY_ENTER)
	await ui.settle()


func _open_home_companions(app: Node) -> void:
	if not app.home._flight_details.visible:
		app.home._details_button.grab_focus()
		await ui.tap(KEY_ENTER)
		await ui.settle()
	app.home.companions_button.grab_focus()
	await ui.tap(KEY_ENTER)
	await ui.settle()


func _wait_for_active(flight: Node, expected: int) -> bool:
	for _frame in 180:
		var status: Dictionary = flight.call("companion_status")
		if int(status.get("active", -1)) == expected:
			return true
		await process_frame
	return false


func _wait_frames(count: int) -> void:
	for _frame in count:
		await process_frame


func _remove_file(path: String) -> void:
	var absolute := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(absolute)
