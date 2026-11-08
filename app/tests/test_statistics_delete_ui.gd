extends SceneTree
const Screen := preload("res://ui/statistics_screen.gd")
const Service := preload("res://statistics/service.gd")
const Schema := preload("res://statistics/schema.gd")

class FakeService extends RefCounted:
	signal changed
	var note := ""
	var last_delete_outcome: Dictionary = {status = "none", note = "", available = true, revision = 0}
	var mode := "refused"
	var calls := 0
	var revision := 1
	var available := true
	var manageable := true
	var records: Array = [{kind = "flight", id = "old", flight_id = "old", aircraft_id = "a", aircraft_name = "A", outcome = "completed", airborne_seconds = 42.0, metadata = {}}]
	func query(_id: String = "", _period: String = "session") -> Dictionary:
		return {available = available, revision = revision, history = records.duplicate(true), history_record_count = records.size(),
			history_count = records.size(), started = records.size(), completed = records.size(), airborne_seconds = 42.0,
			landings = 0, crashes = 0, restarts = 0, has_lifetime_history = not records.is_empty()}
	func aircraft_choices() -> Array:
		return [{id = "a", name = "A"}] if not records.is_empty() else []
	func can_manage() -> bool:
		return manageable
	func delete_history(_id: String) -> bool:
		calls += 1
		match mode:
			"refused":
				last_delete_outcome = {status = "refused", note = "precommit", available = true, revision = 1}
				return false
			"pending_available":
				records = []
				revision += 1
				manageable = false
				last_delete_outcome = {status = "committed_pending", note = "cleanup", available = true, revision = 1}
				changed.emit()
				return false
			"pending_unavailable":
				# Deliberately return stale-looking payload to verify the screen's own gate.
				available = false
				revision += 1
				manageable = false
				last_delete_outcome = {status = "committed_pending", note = "cleanup", available = false, revision = 1}
				changed.emit()
				return false
			"completed_false":
				records = []
				revision += 1
				last_delete_outcome = {status = "completed", note = "", available = true, revision = 1}
				changed.emit()
				return false
		return false

var checks := 0
var failures := 0
func _initialize() -> void: _run.call_deferred()
func check(label: String, passed: bool) -> void:
	checks += 1
	if passed: print("ok   ", label)
	else:
		failures += 1
		printerr("FAIL ", label)
func settle() -> void:
	for _i in 5: await process_frame
func exercise(mode: String) -> void:
	var service := FakeService.new()
	service.mode = mode
	var screen := Screen.new()
	screen.configure(service, "a")
	root.add_child(screen)
	await settle()
	screen.call("_on_history_toggled", true)
	var first_row: Control = screen.get("_history_rows").get_child(0)
	var first_toggle: Button = first_row.get_child(0)
	first_toggle.button_pressed = true
	await settle()
	var opener: Button = screen.get("_aircraft_delete_button")
	opener.grab_focus()
	check(mode + " starts on the actual Delete opener", opener.has_focus())
	screen.call("_open_delete", "a")
	await settle()
	var dialog: ConfirmationDialog = screen.get("_active_dialog")
	check(mode + " opens the revision-pinned confirmation", dialog != null and dialog.visible)
	if dialog == null:
		screen.free()
		return
	dialog.get("scope_check").button_pressed = true
	dialog.call("_on_confirmed")
	await settle()
	if mode == "refused":
		check("refusal retains history and permits another decision", service.calls == 1 and screen.get("_history").size() == 1 and dialog.visible and not dialog.get_ok_button().disabled and dialog.get("status_label").text.contains("unchanged"))
	elif mode == "pending_available":
		check("committed pending shows survivors and disables destructive retry", service.calls == 1 and screen.get("_history").is_empty() and dialog.visible and dialog.get_ok_button().disabled and dialog.get("status_label").text.contains("read-only") and dialog.get_cancel_button().has_focus())
		dialog.call("_on_confirmed")
		check("committed pending cannot be submitted twice", service.calls == 1 and dialog.get("status_label").text.contains("read-only"))
		check("committed pending disables management", screen.get("_pilot_delete_button").disabled and screen.get("_aircraft_delete_button").disabled)
	elif mode == "pending_unavailable":
		check("unavailable query cannot leak stale rows or scopes", service.calls == 1 and screen.get("_history").is_empty() and screen.get("_expanded_history_ids").is_empty() and screen.get("_scope_picker").item_count == 1 and screen.get("_scope_picker").disabled and screen.get("_history_page_label").text == "Statistics unavailable")
		check("unavailable status and actions are truthful", dialog.visible and dialog.get("status_label").text.contains("temporarily unavailable") and dialog.get_ok_button().disabled and screen.get("_pilot_delete_button").disabled)
	elif mode == "completed_false":
		check("completion status wins over a false return", service.calls == 1 and screen.get("_active_dialog") == null and screen.get("_history").is_empty())
	if mode in ["pending_available", "pending_unavailable"]:
		dialog.call("_on_cancelled")
		await settle()
		var focused: Control = root.gui_get_focus_owner()
		check(mode + " Close returns focus to an enabled visible control", focused == screen.get("_history_button") and focused.is_visible_in_tree() and not focused.disabled)
	if is_instance_valid(screen): screen.free()
	await settle()
func external_deletion_and_old_receipt() -> void:
	var service := FakeService.new()
	service.mode = "pending_available"
	var screen := Screen.new()
	screen.configure(service, "a")
	root.add_child(screen)
	await settle()
	screen.call("_on_history_toggled", true)
	service.delete_history("a")
	await settle()
	check("external committed deletion updates the open screen and choices", screen.get("_history").is_empty() and screen.get("_selected_aircraft").is_empty() and screen.get("_scope_picker").item_count == 1)
	screen.free()
	await settle()
	service = FakeService.new()
	service.records = []
	service.revision = 100
	service.last_delete_outcome = {status = "completed", note = "", available = true, revision = 7}
	screen = Screen.new()
	screen.configure(service, "new-aircraft")
	root.add_child(screen)
	await settle()
	service.revision += 1
	service.changed.emit()
	await settle()
	check("old deletion receipt cannot erase a later empty aircraft scope", screen.get("_selected_aircraft") == "new-aircraft" and screen.get("_scope_picker").item_count == 2)
	screen.free()
	await settle()

func fixture_flight(id: String, seq: int, aircraft: String) -> Dictionary:
	return {kind = "flight", id = id, seq = seq, end_seq = seq + 1, session_id = "fixture-session",
		aircraft_id = aircraft, aircraft_name = aircraft, utc = "2026-11-07T10:00:00", account_epoch = 0,
		aircraft_epoch = 0, airborne_seconds = 20.0, outcome = "completed", start_kind = "takeoff",
		full_stops = 1, touch_and_go = 0, failed_landings = 0, unknown_landings = 0,
		max_tas_mps = 20.0, max_groundspeed_mps = 18.0, complete_observation = true,
		config_hash = "", rules_version = "flight-statistics-v1", ended_utc = "2026-11-07T10:00:01", metadata = {}}

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

func real_committed_delete() -> void:
	var uri := "user://audit5_delete_ui_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var service := Service.new()
	root.add_child(service)
	check("real deletion UI store opens", service.setup(uri, true))
	var fixture: Dictionary = service.store.data.duplicate(true)
	fixture.sessions = [{id = "fixture-session", opened_utc = "2026-11-07T09:00:00", closed_utc = "", status = "open"}]
	fixture.current_session = "fixture-session"
	fixture.records = [fixture_flight("flight-a", 1, "stock:a"), fixture_flight("flight-b", 3, "stock:b")]
	fixture.sequence = 4
	fixture.clean_exit = false
	check("real deletion UI fixture validates and commits", Schema.validate(fixture).ok and service.store.commit(fixture))
	service.data = service.store.data.duplicate(true)
	var screen := Screen.new()
	screen.configure(service, "stock:a")
	root.add_child(screen)
	await settle()
	screen.call("_on_history_toggled", true)
	check("real screen starts with the scoped record", screen.get("_history").size() == 1)
	screen.get("_aircraft_delete_button").grab_focus()
	screen.call("_open_delete", "stock:a")
	await settle()
	var dialog: ConfirmationDialog = screen.get("_active_dialog")
	dialog.get("scope_check").button_pressed = true
	service.store.interruption_hook = func(stage: String) -> bool: return stage == "after_deletion_fence_publish"
	dialog.call("_on_confirmed")
	await settle()
	var remaining: Dictionary = service.query("", "lifetime")
	var deleted: Dictionary = service.query("stock:a", "lifetime")
	var hud: Dictionary = service.summary("stock:a", "lifetime")
	check("real committed-pending receipt is surfaced", service.last_delete_outcome.status == "committed_pending" and service.last_delete_outcome.available and dialog.visible and dialog.get_ok_button().disabled and dialog.get("status_label").text.contains("read-only"))
	check("real screen, fresh query and cached HUD agree on survivors", screen.get("_selected_aircraft").is_empty() and screen.get("_stats").completed == 1 and remaining.completed == 1 and deleted.completed == 0 and hud.completed == 0)
	check("real pending state disables further management", not service.can_manage() and screen.get("_pilot_delete_button").disabled)
	dialog.call("_on_cancelled")
	await settle()
	check("real pending Close returns visible focus", root.gui_get_focus_owner() == screen.get("_history_button"))
	screen.free()
	service.close()
	service.free()
	await settle()
	var fixture_root := ProjectSettings.globalize_path(uri).replace("\\", "/").simplify_path()
	var user_root := ProjectSettings.globalize_path("user://").replace("\\", "/").trim_suffix("/").simplify_path()
	check("real deletion fixture is removed within its verified root", fixture_root.begins_with(user_root + "/audit5_delete_ui_") and remove_fixture(fixture_root, fixture_root))

func _run() -> void:
	root.size = Vector2i(1920, 1080)
	TranslationServer.set_locale("en")
	for mode: String in ["refused", "pending_available", "pending_unavailable", "completed_false"]:
		await exercise(mode)
	await external_deletion_and_old_receipt()
	await real_committed_delete()
	print("Statistics deletion UI: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
