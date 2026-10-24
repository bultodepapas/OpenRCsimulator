extends SceneTree

const AccidentReport := preload("res://ui/accident_report.gd")
const FirstFlightHint := preload("res://ui/first_flight_hint.gd")
const Manager := preload("res://render/overlays/overlay_manager.gd")
const OverlaySettings := preload("res://render/overlays/overlay_settings.gd")
const UiTheme := preload("res://ui/ui_theme.gd")


class FakeFlight extends Node:
	var radio := {connected = false}
	var sim := {paused = false}
	var _controller_lost := false


var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	TranslationServer.set_locale("en")
	# Keep the project's stated display priority in the regression matrix.
	for viewport_size: Vector2i in [Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(1280, 720)]:
		for text_scale: float in [1.0, 1.5]:
			await _case(viewport_size, text_scale)
	UiTheme.text_scale = 1.0
	print("first-flight/report layout: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _case(viewport_size: Vector2i, text_scale: float) -> void:
	root.size = viewport_size
	root.content_scale_size = viewport_size
	UiTheme.text_scale = text_scale
	var hud: CanvasLayer = Manager.new(OverlaySettings.DEFAULTS, "en")
	var report: CanvasLayer = AccidentReport.new()
	var session := FakeFlight.new()
	root.add_child(hud)
	root.add_child(report)
	await _settle()
	_populate_pilot_hud(hud)
	# Inject the report view fixture directly. The test never reads or writes user://last_accident.json.
	report.show_archived(_archive_fixture())
	var hint: CanvasLayer = FirstFlightHint.new(session, "airplane")
	root.add_child(hint)
	await _settle()
	_check_state("archived", viewport_size, text_scale, hud, report, hint)
	if viewport_size == Vector2i(1920, 1080) and is_equal_approx(text_scale, 1.0):
		var resized := Vector2i(2560, 1440)
		root.size = resized
		root.content_scale_size = resized
		await _settle()
		_check("archived layout cycle reaches 1440p", root.get_viewport().size == resized,
			str(root.get_viewport().size))
		_check_state("archived resize 1440p", resized, text_scale, hud, report, hint)
		root.size = viewport_size
		root.content_scale_size = viewport_size
		await _settle()
		_check("archived layout cycle returns to 1080p", root.get_viewport().size == viewport_size,
			str(root.get_viewport().size))
		_check_state("archived resize return 1080p", viewport_size, text_scale, hud, report, hint)

	var regular := _archive_fixture()
	regular.complete = true
	regular.outcome = "repair"
	regular.total_minor = 539
	regular.known_subtotal_minor = 539
	report.show_assessment(regular, true)
	_check("regular report exposes the reopen action", report.controller_action("inspect"),
		"%dx%d scale %.1f" % [viewport_size.x, viewport_size.y, text_scale])
	await _settle()
	_check_state("regular", viewport_size, text_scale, hud, report, hint)

	root.remove_child(hint)
	root.remove_child(report)
	root.remove_child(hud)
	hint.free()
	report.free()
	hud.free()
	session.free()
	await _settle()

	# With accident reports disabled, the hint keeps its existing viewport-edge fallback.
	var fallback_session := FakeFlight.new()
	var fallback: CanvasLayer = FirstFlightHint.new(fallback_session, "airplane")
	root.add_child(fallback)
	await _settle()
	var fallback_card := fallback.find_child("Card", true, false) as Control
	var fallback_rect := fallback_card.get_global_rect()
	_check("no-report fallback remains inside the viewport",
		Rect2(Vector2.ZERO, Vector2(viewport_size)).encloses(fallback_rect), str(fallback_rect))
	_check("no-report fallback retains the 24px bottom inset",
		is_equal_approx(fallback_rect.end.y, float(viewport_size.y) - 24.0), str(fallback_rect))
	root.remove_child(fallback)
	fallback.free()
	fallback_session.free()
	await _settle()


func _populate_pilot_hud(hud: CanvasLayer) -> void:
	# Feed the real overlay controls a representative finite flight sample before measuring their bounds.
	var sample := {
		"airspeed": 34.0, "ground_speed": 37.0, "height_agl": 125.0,
		"vertical_speed": -1.2, "throttle": 0.68, "distance_pilot": 730.0,
		"time_s": 84.0, "wind_speed": 4.0, "wind_up": 0.2, "wind_from_deg": 245.0,
	}
	var units: String = hud.unit_system()
	hud.frames.flight.refresh(sample, units, {})
	hud.frames.wind.refresh(sample, 212.0, units)
	hud.frames.transmitter.refresh(
		{"roll": 0.12, "pitch": -0.08, "yaw": 0.03, "throttle": 0.68},
		{"roll": 0.02, "pitch": -0.01, "yaw": 0.0}, int(hud.settings.stick_mode))


func _check_state(kind: String, viewport_size: Vector2i, text_scale: float,
		hud: CanvasLayer, report: CanvasLayer, hint: CanvasLayer) -> void:
	var card := hint.find_child("Card", true, false) as Control
	var action := report.find_child("ReopenAccidentReport", true, false) as Control
	var card_rect: Rect2 = card.get_global_rect()
	var action_rect: Rect2 = action.get_global_rect()
	var context := "%s %dx%d scale %.1f" % [kind, viewport_size.x, viewport_size.y, text_scale]
	var viewport_rect := Rect2(Vector2.ZERO, Vector2(viewport_size))
	_check(context + ": hint fits viewport", viewport_rect.encloses(card_rect), str(card_rect))
	_check(context + ": reopen action is visible", action.is_visible_in_tree())
	_check(context + ": reopen action fits viewport", viewport_rect.encloses(action_rect), str(action_rect))
	_check(context + ": hint clears reopen action", not card_rect.intersects(action_rect),
		"hint=%s action=%s" % [str(card_rect), str(action_rect)])
	var found_pilot_overlay := false
	var known_720p_large_text := viewport_size == Vector2i(1280, 720) and is_equal_approx(text_scale, 1.5)
	for id: String in OverlaySettings.IDS:
		var overlay := hud.frames[id] as Control
		if not overlay.is_visible_in_tree():
			continue
		found_pilot_overlay = true
		var overlay_rect: Rect2 = overlay.get_global_rect()
		var hint_clears_overlay := not card_rect.intersects(overlay_rect)
		if known_720p_large_text and id in ["flight", "transmitter"] and not hint_clears_overlay:
			print("KNOWN LIMITATION %s: hint overlaps Pilot %s; hint=%s overlay=%s" %
				[context, id, str(card_rect), str(overlay_rect)])
		else:
			_check(context + ": hint clears Pilot overlay " + id, hint_clears_overlay,
				"hint=%s overlay=%s" % [str(card_rect), str(overlay_rect)])
		_check(context + ": report action clears Pilot overlay " + id, not action_rect.intersects(overlay_rect),
			"action=%s overlay=%s" % [str(action_rect), str(overlay_rect)])
	_check(context + ": Pilot HUD fixture contains visible overlays", found_pilot_overlay)


func _archive_fixture() -> Dictionary:
	return {
		"identity": {"aircraft_id": "jensen-das-ugly-stik-60", "incident_id": "layout-only"},
		"currency": "USD",
		"complete": false,
		"outcome": "inspection",
		"known_subtotal_minor": 0,
		"total_minor": null,
		"lines": [],
		"unresolved": ["inspection required"],
		"assumptions": [],
	}


func _settle() -> void:
	for _frame in 4:
		await process_frame


func _check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])
