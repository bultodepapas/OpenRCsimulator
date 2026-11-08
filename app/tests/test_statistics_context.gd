extends SceneTree
const Schema := preload("res://statistics/schema.gd")
const Store := preload("res://statistics/store.gd")
const RecordView := preload("res://statistics/record_view.gd")
const Screen := preload("res://ui/statistics_screen.gd")
const NaturalRandom := preload("res://scenarios/natural_random.gd")
const FailureConfig := preload("res://failures/config.gd")
const FailureCatalog := preload("res://failures/catalog.gd")
const Preferences := preload("res://app_state/preferences.gd")
const App := preload("res://app_root.gd")
const UiDriver := preload("res://tests/ui_driver.gd")

var checks := 0
var failures := 0
var ui: RefCounted
func _initialize() -> void: _run.call_deferred()
func check(label: String, passed: bool, detail: String = "") -> void:
	checks += 1
	if passed: print("ok   ", label)
	else:
		failures += 1
		printerr("FAIL ", label, " ", detail)
func settle() -> void:
	for _i in 6: await process_frame
func text_of(node: Node) -> String:
	var result := ""
	if node is Label or node is Button: result += str(node.text) + "\n"
	for child: Node in node.get_children(): result += text_of(child)
	return result
func remove_fixture(path: String, fixture_root: String) -> bool:
	if path != fixture_root and not path.begins_with(fixture_root + "/"): return false
	var parent := DirAccess.open(path.get_base_dir())
	if parent == null or parent.is_link(path): return false
	var directory := DirAccess.open(path)
	if directory == null: return false
	for file: String in directory.get_files():
		var child := path.path_join(file).simplify_path()
		if not child.begins_with(fixture_root + "/") or directory.is_link(child): return false
		if DirAccess.remove_absolute(child) != OK: return false
	for name: String in directory.get_directories():
		var child := path.path_join(name).simplify_path()
		if directory.is_link(child) or not remove_fixture(child, fixture_root): return false
	return DirAccess.remove_absolute(path) == OK
func make_record(scenario: Dictionary, practice: Dictionary) -> Dictionary:
	return {kind = "flight", id = "flight-1", seq = 1, end_seq = 2, session_id = "session-1",
		aircraft_id = scenario.aircraft_id, aircraft_name = "Fixture", utc = "2026-11-07T12:00:00Z",
		account_epoch = 0, aircraft_epoch = 0, airborne_seconds = 42.125, outcome = "completed", start_kind = "air_start",
		full_stops = 1, touch_and_go = 0, failed_landings = 0, unknown_landings = 0,
		max_tas_mps = 20.0, max_groundspeed_mps = 20.0, complete_observation = true,
		config_hash = scenario.aircraft_identity, rules_version = "flight-statistics-rules-v2", ended_utc = "2026-11-07T12:01:00Z",
		metadata = {launch_context_format = RecordView.CONTEXT_FORMAT, scenario = scenario.duplicate(true),
			failure_config = practice.duplicate(true), failure_seed = 314159, events = [
				{type = "started", tick = 240},
				{type = "failure_activated", failure_id = "roll_jam", tick = 1200, source = "accepted_failure_signal_v1"}], events_omitted = 0}}
func test_store_and_view() -> void:
	var generated := NaturalRandom.generate(42)
	check("Natural Random fixture is valid", generated.ok)
	if not generated.ok: return
	var scenario: Dictionary = generated.scenario
	var practice := FailureConfig.defaults()
	practice.probability_percent = 100
	practice.severity = "severe"
	practice.onset = "early"
	practice.include_catastrophic = true
	practice.notify = false
	practice.excluded_ids = ["roll_bias"]
	var record := make_record(scenario, practice)
	var store_root := "user://audit5_context_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var store := Store.new()
	check("isolated real statistics store opens", store.open(store_root) and store.writable)
	var data: Dictionary = store.data.duplicate(true)
	data.sessions = [{id = "session-1", opened_utc = "2026-11-07T12:00:00Z", closed_utc = "", status = "open"}]
	data.current_session = "session-1"
	data.sequence = 2
	data.records = [record]
	var validated := Schema.validate(data)
	check("complete nested context remains schema-v1 valid", validated.ok, str(validated.errors))
	check("real store commits nested context", validated.ok and store.commit(data), store.note)
	store.close()
	var reloaded := Store.new()
	check("real store reopens the committed record", reloaded.open(store_root) and reloaded.data.records.size() == 1, reloaded.note)
	if reloaded.data.records.is_empty():
		reloaded.close()
		return
	var persisted: Dictionary = reloaded.data.records[0]
	check("round-trip retains exact context and subsecond time", persisted.metadata == record.metadata and persisted.airborne_seconds == 42.125)
	var view := RecordView.from_record(persisted)
	check("adapter admits matching validated scenario and accepted practice", view.scenario_kind == "natural_random" and view.scenario.seed == 42 and view.practice_known and view.practice_seed == 314159 and view.practice == practice)
	check("only marked actual activation is included", view.failure_events.size() == 1 and view.failure_events[0].failure_id == "roll_jam" and view.failure_events[0].tick == 1200)
	var screen := Screen.new()
	var row: VBoxContainer = screen.call("_history_row", persisted, 0)
	var title: String = row.get_child(0).text
	row.get_child(0).button_pressed = true
	var rendered := text_of(row)
	check("history title tags Natural Random and practice", title.contains("Natural Random") and title.contains("Failure practice enabled"))
	check("expanded history includes launch seed, settings, exact seconds and observed event", rendered.contains("Scenario seed") and rendered.contains("42") and rendered.contains("314159") and rendered.contains("42.125") and rendered.contains("Ailerons jammed.") and rendered.contains("tick 1200") and rendered.contains("Practice settings at launch"), rendered)
	row.free()
	var legacy: Dictionary = persisted.duplicate(true)
	legacy.metadata.erase("launch_context_format")
	var legacy_view := RecordView.from_record(legacy)
	check("verified legacy scenario is retained while old practice is unknown", legacy_view.scenario_kind == "natural_random" and not legacy_view.practice_known)
	legacy.metadata.events = [{type = "failure_activated", failure_id = "roll_jam", tick = 1200}]
	legacy_view = RecordView.from_record(legacy)
	check("unmarked legacy event cannot masquerade as observed failure", legacy_view.failure_events.is_empty())
	legacy.metadata.events_omitted = 2
	row = screen.call("_history_row", legacy, 1)
	row.get_child(0).button_pressed = true
	rendered = text_of(row)
	check("no retained activation and omitted details stay explicitly unknown", rendered.contains("No failure event recorded; occurrence is unknown.") and rendered.contains("More events omitted: 2"), rendered)
	row.free()
	var mismatch: Dictionary = persisted.duplicate(true)
	mismatch.aircraft_id = "another-aircraft"
	check("scenario with a different recorded aircraft is unknown", RecordView.from_record(mismatch).scenario_kind == "unknown")
	mismatch = persisted.duplicate(true)
	mismatch.aircraft_id = "stock:" + str(scenario.aircraft_id)
	check("stock and bare identity namespaces are not conflated", RecordView.from_record(mismatch).scenario_kind == "unknown")
	mismatch = persisted.duplicate(true)
	mismatch.config_hash = "a".repeat(64)
	check("scenario with mismatched record hash is unknown", RecordView.from_record(mismatch).scenario_kind == "unknown")
	mismatch = persisted.duplicate(true)
	mismatch.metadata.config_hash = "b".repeat(64)
	check("scenario with mismatched metadata hash is unknown", RecordView.from_record(mismatch).scenario_kind == "unknown")
	mismatch = persisted.duplicate(true)
	mismatch.metadata.scenario = {mode = "natural_random", seed = 42}
	check("incomplete legacy-style scenario stays unknown", RecordView.from_record(mismatch).scenario_kind == "unknown")
	mismatch = persisted.duplicate(true)
	mismatch.metadata.failure_seed = "314159"
	check("malformed accepted seed does not invent practice context", not RecordView.from_record(mismatch).practice_known)
	var ordinary: Dictionary = persisted.duplicate(true)
	ordinary.metadata.scenario = {}
	ordinary.metadata.failure_config = FailureConfig.defaults()
	ordinary.metadata.failure_seed = 0
	ordinary.metadata.events = [{type = "failure_planned", failure_id = "roll_jam", tick = 500}]
	var ordinary_view := RecordView.from_record(ordinary)
	check("ordinary disabled practice is distinct from unknown and planned events", ordinary_view.scenario_kind == "ordinary" and ordinary_view.practice_known and ordinary_view.practice.probability_percent == 0 and ordinary_view.failure_events.is_empty())
	row = screen.call("_history_row", ordinary, 2)
	row.get_child(0).button_pressed = true
	rendered = text_of(row)
	check("ordinary disabled practice renders separately from unknown occurrences", rendered.contains("Ordinary flight") and rendered.contains("Disabled") and rendered.contains("No failure event recorded; occurrence is unknown."), rendered)
	row.free()
	TranslationServer.set_locale("es")
	row = screen.call("_history_row", persisted, 3)
	row.get_child(0).button_pressed = true
	var tag := TranslationServer.translate("Failure practice enabled")
	check("Spanish history uses translated scenario and practice tags", TranslationServer.translate("Natural Random") in text_of(row) and tag != "Failure practice enabled" and tag in text_of(row), text_of(row))
	row.free()
	TranslationServer.set_locale("en")
	screen.free()
	reloaded.close()
	var fixture_root := ProjectSettings.globalize_path(store_root).replace("\\", "/").simplify_path()
	var user_root := ProjectSettings.globalize_path("user://").replace("\\", "/").trim_suffix("/").simplify_path()
	check("isolated store fixture is removed within its verified root", fixture_root.begins_with(user_root + "/audit5_context_") and remove_fixture(fixture_root, fixture_root))

func launch_case(random: bool) -> void:
	var path := "user://audit5_context_prefs_%d_%d.cfg" % [OS.get_process_id(), 1 if random else 0]
	var prefs: Dictionary = Preferences.DEFAULTS.duplicate(true)
	prefs.first_flight_hint_seen = true
	prefs.check_updates = false
	prefs.language = "en"
	var configured := FailureConfig.defaults()
	configured.probability_percent = 100
	prefs.failure_config = configured
	check("isolated preferences save", Preferences.save_to(path, prefs) == OK)
	var app := App.new()
	app.user_args = PackedStringArray()
	app.preferences_path = path
	app.random_seed_source = func() -> int: return 42
	root.add_child(app)
	await settle()
	if random:
		app.open_natural_random()
		for _i in 240:
			if app.natural_random_screen != null and not app.natural_random_screen.fly_button.disabled: break
			await process_frame
		if app.natural_random_screen == null or app.natural_random_screen.fly_button.disabled:
			check("Random briefing opens", false)
			await ui.close_app(app)
			return
		await settle()
		app.natural_random_screen.fly_button.grab_focus()
	else:
		app.home.fly_button.grab_focus()
	await ui.tap(KEY_ENTER)
	for _i in 120:
		if app.flight != null and app.flight.session != null and app.statistics_service._metadata.has("launch_context_format"): break
		await process_frame
	if app.flight == null or app.flight.session == null:
		check("actual flight launches", false)
		await ui.close_app(app)
		return
	var flight: Node = app.flight
	var metadata: Dictionary = app.statistics_service._metadata.duplicate(true)
	var expected: Dictionary = FailureCatalog.request_for_model(flight.failure_config, flight.session.aircraft.model)
	check(("Random" if random else "Ordinary") + " launch captures accepted settings and resolved seed", metadata.get("launch_context_format", "") == RecordView.CONTEXT_FORMAT and metadata.get("failure_config", {}) == expected and metadata.get("failure_seed", -1) == flight.failure_seed)
	check(("Random" if random else "Ordinary") + " uses actual route rather than saved preferences", int(metadata.get("failure_config", {}).get("probability_percent", -1)) == (0 if random else 100) and int(app.preferences.failure_config.probability_percent) == 100)
	if random:
		check("Random launch captures the bound accepted scenario", metadata.get("scenario", {}) == flight.flight_scenario and RecordView.from_record({aircraft_id = flight.aircraft_id, config_hash = metadata.config_hash, metadata = metadata}).scenario_kind == "natural_random")
		flight.session.physics_enabled = false
		flight.session.input_enabled = false
		flight.session.sim.set_paused(true)
		for _i in 260: flight.session.sim.step()
		var before: Dictionary = app.statistics_service._active_record.duplicate(true)
		check("actual stepped flight produces a statistics record", not before.is_empty())
		var edited: Dictionary = flight.lighting_config.duplicate(true)
		edited.local_seconds = 40000 if int(edited.local_seconds) != 40000 else 42000
		var edit: Dictionary = flight.apply_lighting_config(edited)
		check("scenario change invalidates only future scenario context", edit.ok and not app.statistics_service._metadata.has("scenario") and app.statistics_service._metadata.has("failure_config") and (before.is_empty() or app.statistics_service._active_record.metadata.scenario == before.metadata.scenario))
		flight.session.reset()
		for _i in 260: flight.session.sim.step()
		var after_edit: Dictionary = app.statistics_service._active_record.duplicate(true)
		var after_edit_view := RecordView.from_record(after_edit)
		check("new recorded flight after edited-scenario Restart does not inherit old scenario", not after_edit.is_empty() and after_edit_view.scenario_kind == "unknown" and after_edit_view.practice_known)
		var checkpoint: Dictionary = flight.checkpoint()
		var restored: Dictionary = flight.restore_checkpoint(checkpoint)
		check("actual checkpoint restore clears scenario and future launch context", restored.ok and flight.flight_scenario.is_empty() and not app.statistics_service._metadata.has("scenario") and not app.statistics_service._metadata.has("failure_config") and not app.statistics_service._metadata.has("launch_context_format"))
		flight.session.reset()
		for _i in 260: flight.session.sim.step()
		var after_restore: Dictionary = app.statistics_service._active_record.duplicate(true)
		var after_restore_view := RecordView.from_record(after_restore)
		check("new recorded flight after restore and Restart keeps launch context unknown", not after_restore.is_empty() and after_restore_view.scenario_kind == "unknown" and not after_restore_view.practice_known)
	await settle()
	await ui.close_app(app)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _run() -> void:
	root.size = Vector2i(1920, 1080)
	TranslationServer.set_locale("en")
	ui = UiDriver.new(self)
	await test_store_and_view()
	await launch_case(false)
	await launch_case(true)
	print("Statistics context: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
