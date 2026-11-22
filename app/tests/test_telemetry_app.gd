# TELEM-02/03: telemetry through the real AppRoot. A development run has no telemetry at all; with the route and
# release seams of a qualification run, the first-launch choice appears once over Home, Esc declines and is
# remembered, Settings → Interface switches it, a language without a reviewed notice turns it off, Enable is the
# only grant, and an accepted batch reaches a local collector through AppRoot's observation context.
# Run: godot --headless --path . --script res://tests/test_telemetry_app.gd
extends SceneTree

const UiDriver := preload("res://tests/ui_driver.gd")
const Collector := preload("res://tests/fake_telemetry_collector.gd")
const Store := preload("res://telemetry/telemetry_consent_store.gd")
const Contract := preload("res://telemetry/telemetry_contract.gd")
const RendererGuard := preload("res://app_state/renderer_guard.gd")

const PREFS := "user://test_telemetry_app_settings.cfg"
const STATE := "user://test_telemetry_app_update.cfg"
const CONSENT := "user://test_telemetry_app_consent.cfg"

var _failures := 0
var ui: RefCounted
var collector: RefCounted


func _check(label: String, ok: bool, detail := "") -> void:
	if ok:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _initialize() -> void:
	ui = UiDriver.new(self)
	_run()


func _run() -> void:
	await process_frame
	root.size = Vector2i(1920, 1080)
	TranslationServer.set_locale("en")
	_clean()
	collector = Collector.new()
	_check("collector listens", collector.start())
	await _development_run()
	await _first_launch_decline()
	await _settings_switch_and_language()
	await _enable_button_and_send()
	collector.stop()
	_clean()
	print("all telemetry app checks passed" if _failures == 0 else "%d failed" % _failures)
	quit(1 if _failures > 0 else 0)


func _new_app(with_telemetry: bool) -> Node:
	var app: Node = load("res://app_root.tscn").instantiate()
	app.user_args = PackedStringArray()
	app.preferences_path = PREFS
	app.update_state_path = STATE
	if with_telemetry:
		app.telemetry_release = {"ok": true, "reason": "qualification", "endpoint": collector.url(),
			"operator": "Test operator", "contact": "privacy@example.org", "release_id": "v0.0.0",
			"channel": "preview", "notice": Contract.NOTICE_VERSION, "qualification": true}
		app.telemetry_route_override = true
		app.telemetry_consent_path = CONSENT
	return app


func _development_run() -> void:
	var app := _new_app(false)
	root.add_child(app)
	await ui.settle()
	_check("a development run has no telemetry service", app.telemetry == null and app.find_child("Telemetry", false, false) == null)
	app.open_settings()
	await ui.settle()
	var settings: Node = app.screens.get_screen("settings")
	var toggle: CheckButton = settings.find_child("ShareTelemetry", true, false)
	var status: Label = settings.find_child("TelemetryStatus", true, false)
	_check("Settings says telemetry is unavailable and cannot switch it on", toggle != null and toggle.disabled
		and not toggle.button_pressed and status.text == "Telemetry is not available in this build.", status.text if status else "")
	_check("no consent file was read or written", not FileAccess.file_exists(CONSENT))
	await ui.close_app(app)


func _first_launch_decline() -> void:
	var app := _new_app(true)
	root.add_child(app)
	await ui.settle()
	_check("the service exists and asks first", app.telemetry != null and app.telemetry.state == "ask")
	var shown: bool = await ui.wait_until(func() -> bool: return app.screens.is_top("telemetry_consent"), 5000)
	_check("the first-launch choice appears over Home", shown)
	var screen: Node = app.screens.get_screen("telemetry_consent")
	_check("its choices start disarmed", screen != null and not screen.is_armed() and screen.enable_button.disabled)
	await ui.wait_until(func() -> bool: return screen.is_armed(), 5000)
	_check("they arm after a quiet moment with nothing held", screen.is_armed() and not screen.enable_button.disabled)
	await ui.settle()
	_check("no choice holds the starting focus: a reflexive Enter answers nothing", ui.focus_name() == "NoticeScroll", ui.focus_name())
	await ui.tap(KEY_ENTER)
	await ui.settle()
	_check("Enter on the notice text neither grants nor declines", app.telemetry.state == "ask"
		and app.screens.is_top("telemetry_consent"))
	await ui.tap(KEY_ESCAPE)
	await ui.settle()
	_check("Esc declines and closes the notice", app.telemetry.state == "off" and app.telemetry.reason == "declined"
		and not app.screens.is_top("telemetry_consent") and app.screens.is_top("home"))
	_check("the decline is saved", Store.load_choice(CONSENT).choice == "disabled")
	_check("Home states the effective choice", app.home.note_label.visible
		and app.home.note_label.text == "Telemetry is off · Settings → Interface", app.home.note_label.text)
	_check("nothing was collected", app.telemetry.queue.items.is_empty() and app.telemetry._pending.is_empty())
	await ui.close_app(app)

	var again := _new_app(true)
	root.add_child(again)
	await ui.settle()
	for i: int in 30:
		await process_frame
	_check("a declined player is not asked again", again.telemetry.state == "off" and not again.screens.is_top("telemetry_consent"))
	await ui.close_app(again)


func _settings_switch_and_language() -> void:
	var app := _new_app(true)
	root.add_child(app)
	await ui.settle()
	app.open_settings()
	await ui.settle()
	var settings: Node = app.screens.get_screen("settings")
	var toggle: CheckButton = settings.find_child("ShareTelemetry", true, false)
	var status: Label = settings.find_child("TelemetryStatus", true, false)
	_check("Settings shows the saved decline", not toggle.button_pressed and not toggle.disabled and status.text == "Telemetry is off.", status.text)
	toggle.button_pressed = true
	await ui.settle()
	_check("switching on enables and saves", app.telemetry.state == "on" and Store.load_choice(CONSENT).choice == "enabled")
	_check("Settings reports it", status.text == "Telemetry is on. Batches sent this session: 0.", status.text)
	app.open_telemetry_info("preview", toggle)
	await ui.settle()
	var info: Node = app.screens.get_screen("telemetry_info")
	var data: Label = info.find_child("PendingData", true, false) if info != null else null
	_check("the preview shows the exact pending data", data != null and data.text.contains("\"session_started\""))
	info.close()
	await ui.settle()
	app.set_language("de")
	await ui.settle()
	_check("a language without a reviewed notice turns telemetry off", app.telemetry.state == "off" and app.telemetry.reason == "locale"
		and toggle.disabled and status.text == "Telemetrie ist aus: Sie wird in dieser Sprache noch nicht angeboten. Wechsle zu Englisch oder Spanisch, um zu wählen.", status.text)
	app.set_language("es")
	await ui.settle()
	_check("Spanish has a reviewed notice: on again", app.telemetry.state == "on"
		and status.text == "La telemetría está activada. Lotes enviados en esta sesión: 0.", status.text)
	app.set_language("en")
	toggle.button_pressed = false
	await ui.settle()
	_check("switching off saves the decline and drops pending data", app.telemetry.state == "off"
		and Store.load_choice(CONSENT).choice == "disabled" and app.telemetry.queue.items.is_empty() and app.telemetry._pending.is_empty())
	await ui.close_app(app)


func _enable_button_and_send() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CONSENT))
	var app := _new_app(true)
	root.add_child(app)
	await ui.settle()
	await ui.wait_until(func() -> bool: return app.screens.is_top("telemetry_consent"), 5000)
	var screen: Node = app.screens.get_screen("telemetry_consent")
	await ui.wait_until(func() -> bool: return screen != null and screen.is_armed(), 5000)
	screen.enable_button.grab_focus()
	await ui.tap(KEY_ENTER)
	await ui.settle()
	_check("Enable grants and closes the notice", app.telemetry.state == "on" and Store.load_choice(CONSENT).choice == "enabled"
		and app.screens.is_top("home"))
	_check("Home states it", app.home.note_label.text == "Telemetry is on · Settings → Interface", app.home.note_label.text)
	# Sealing and sending emit state_changed about once a minute; another Home notice must survive them.
	app.home.set_note("Could not open the browser (error 1).")
	app._on_telemetry_state_changed()
	_check("telemetry never replaces another Home notice", app.home.note_label.text == "Could not open the browser (error 1).",
		app.home.note_label.text)
	app.home.set_note("")
	app._on_telemetry_state_changed()
	_check("a free note line shows the telemetry status again", app.home.note_label.text == "Telemetry is on · Settings → Interface",
		app.home.note_label.text)
	_check("a headless window counts as minimized: nothing is measured", app._telemetry_context().eligible == false)
	var original: Dictionary = app._telemetry_context()
	_check("default graphics choices report current_default", original.graphics_profile == "current_default",
		original.graphics_profile)
	var saved: Dictionary = app.display_preferences.config.duplicate(true)
	var preview := saved.duplicate(true)
	preview.msaa_3d = 0 if int(saved.msaa_3d) != 0 else 2
	app._apply_presentation(preview)
	var applied: Dictionary = app._telemetry_context()
	_check("the effective preview changes the telemetry context before a save",
		applied.graphics_profile == "custom" and applied.graphics_revision > original.graphics_revision
		and app.display_preferences.config.msaa_3d == saved.msaa_3d)
	app._apply_presentation(saved)
	var reverted: Dictionary = app._telemetry_context()
	_check("reverting a preview restores the original profile and splits the measurement",
		reverted.graphics_profile == original.graphics_profile and reverted.graphics_revision > applied.graphics_revision)
	_check("an ordinary renderer session is not reported as unavailable", not app._telemetry_renderer_unavailable())
	RendererGuard.save_state(app.renderer_guard_path, {"failed": {"method": "mobile", "build": RendererGuard.build_identity()}})
	_check("a failed record alone, without the guard's restart argument, is not renderer_unavailable",
		not app._telemetry_renderer_unavailable())
	RendererGuard.save_state(app.renderer_guard_path, {})
	app._note_telemetry_error("asset_load_failed")
	_check("a flight-start failure is counted while telemetry is on", int(app.telemetry._errors.get("asset_load_failed", 0)) == 1,
		str(app.telemetry._errors))
	app.window_minimized_probe = func() -> bool: return false
	var context: Dictionary = app._telemetry_context()
	_check("AppRoot's context on a visible Home", context.mode == "home" and context.vehicle == "" and context.eligible == true
		and context.input_class in ["keyboard", "gamepad", "rc", "other"], str(context))
	# Fast-forward the service's clock past the 60 s seal so a batch is sent through the real sender.
	var offset := [0]
	app.telemetry.clock_usec = func() -> int: return Time.get_ticks_usec() + offset[0]
	for i: int in 40:
		offset[0] += 2000000
		collector.poll()
		await process_frame
	var sent: bool = await ui.wait_until(func() -> bool:
		collector.poll()
		return app.telemetry.queue.sent_ok >= 1, 15000)
	_check("a batch was accepted by the collector", sent and collector.requests.size() >= 1, str(collector.requests.size()))
	if not collector.requests.is_empty():
		var body: Variant = JSON.parse_string((collector.requests[0].body as PackedByteArray).get_string_from_utf8())
		var names := []
		if body is Dictionary:
			for event: Dictionary in body.events:
				names.append(event.name if event.name != "performance_window" else "%s/%s/%s" % [event.name, event.mode, event.phase])
		_check("it carries the session start and Home cadence windows", body is Dictionary and names[0] == "session_started"
			and names.has("performance_window/home/warmup") and names.has("performance_window/home/steady")
			and body.build.release_id == "v0.0.0" and body.context.resolution_class == "1080p"
			and body.context.graphics_profile == "current_default", str(names) + str(body.context if body is Dictionary else ""))
	# A real flight through the staged loading screen, as the rendered game starts it: AppRoot names the stock
	# aircraft, its simulated clock and the accepted fixed-wing classifier once the session runs.
	app.flight_loading_enabled = true
	app.home.fly_button.grab_focus()
	await ui.tap(KEY_ENTER)
	await ui.settle()
	var flying: bool = await ui.wait_until(func() -> bool: return (app.flight != null and not app._loading_active
		and app.flight.session != null), 30000)
	for i: int in 20:
		await process_frame
	var in_flight: Dictionary = app._telemetry_context()
	# Behind the loading screen the flight exists but its session and statistics do not run yet: no activity starts.
	app._loading_active = true
	var loading: Dictionary = app._telemetry_context()
	app._loading_active = false
	_check("a loading flight is not yet an activity", loading.activity == false and loading.mode != "flight", str(loading))
	_check("AppRoot's context in a flight", flying and in_flight.mode == "flight" and in_flight.vehicle in Contract.STOCK_VEHICLES
		and in_flight.fixed_wing_accepted == true and float(in_flight.simulated_seconds) >= 0.0 and in_flight.eligible == true, str(in_flight))
	app.open_pause()
	await ui.settle()
	var paused_context: Dictionary = app._telemetry_context()
	_check("a menu over the flight is not measured", paused_context.eligible == false)
	app.restart_flight()
	var restarted: Dictionary = app._telemetry_context()
	_check("the active flight reset advances its telemetry boundary",
		restarted.activity_id == paused_context.activity_id
		and restarted.activity_revision > paused_context.activity_revision)
	await ui.settle()
	app.end_flight()
	await ui.settle()
	await ui.wait_until(func() -> bool: return app.home != null and not app.home_build_pending, 20000)
	for i: int in 5:
		await process_frame
	var summaries := []
	for event: Dictionary in app.telemetry._pending:
		if event.name == "activity_summary":
			summaries.append(event)
	for item: Dictionary in app.telemetry.queue.items:
		for event: Dictionary in JSON.parse_string(item.body.get_string_from_utf8()).events:
			if event.name == "activity_summary":
				summaries.append(event)
	var returned := summaries.filter(func(event: Dictionary) -> bool: return event.outcome == "returned_home")
	_check("returning home summarizes the flight with the accepted classifier", returned.size() == 1
		and returned[0].classification == "accepted_fixed_wing" and returned[0].vehicle_id == in_flight.vehicle
		and returned[0].complete_observation == true, str(summaries))
	await ui.close_app(app)


func _clean() -> void:
	for path: String in [PREFS, PREFS + ".display", PREFS + ".renderer", PREFS + ".controllers", STATE, CONSENT, CONSENT + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
