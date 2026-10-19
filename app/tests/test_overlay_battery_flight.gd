# BAT-15: O9 Battery in a real flight scene. The synthetic 4S ocv_resistance pack (--electric-demo=4s-battery) reaches
# the overlay through OverlayManager.snapshot() and session.electrical_state(); the fixture checks of the sensors and
# the panel are in test_overlay_battery.gd.
# Run: godot --headless --path . --script res://tests/test_overlay_battery_flight.gd
extends SceneTree

var _failures := 0
var _count := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _initialize() -> void:
	TranslationServer.set_locale("en")
	_run()


func _run() -> void:
	# The headless display server sets its window to 64×64 on the first frame, over any earlier size: resize after it.
	await process_frame
	await _live_flight()
	await _live_pack_flight()
	print("overlay battery flight: %d checks, %d failed" % [_count, _failures])
	quit(1 if _failures else 0)


func _texts(node: Node) -> String:
	var parts := PackedStringArray()
	for label: Node in node.find_children("*", "Label", true, false):
		if (label as Control).is_visible_in_tree():
			parts.append(label.text)
	return "\n".join(parts)


## A real flight scene with the synthetic 4S ocv_resistance pack (--electric-demo=4s-battery): snapshot() carries the
## session's electrical_state() to O9, which shows the older kind's V, A, mAh and %.
func _live_flight() -> void:
	var flight: Node = load("res://main.tscn").instantiate()
	flight.user_args = PackedStringArray(["--electric-demo=4s-battery"])
	flight.overlays_enabled = true
	flight.overlay_settings = { preset = "full", units = "metric" }
	root.size = Vector2i(1280, 720)
	root.add_child(flight)
	for i in 12:
		await process_frame
	var overlays: CanvasLayer = flight.get("_overlays")
	_check("electric demo flight builds the overlays", overlays != null)
	if overlays == null:
		flight.queue_free()
		return
	var panel: Control = overlays.frames.battery
	var session: Node = flight.get("session")
	var state: Dictionary = session.electrical_state()
	_check("the demo pack is dynamic and of the older kind", session.battery_is_dynamic() and state.get("ok", false) and not state.has("battery_kind"))
	_check("live: O9 shown, detailed in Full", panel.visible and panel.detailed, "%s %s" % [panel.visible, panel.detailed])
	_check("live: pack voltage and used/rated mAh from the session", panel.values.pack_v.text.ends_with(" V") and panel.values.pack_v.text != "–"
		and panel.values.used.text.ends_with(" mAh"), "%s | %s" % [panel.values.pack_v.text, panel.values.used.text])
	_check("live: no cell or temperature sensors for the older kind", not panel.values.cell_avg.visible and not panel.values.temperature.visible)
	_check("live: no true SOC in the Full preset", not _texts(overlays).contains("SOC"))
	flight.queue_free()
	await process_frame


## BAT-13/15: the Timber in battery mode "pack" through the product route (--aircraft, --battery): O9 shows the
## pack_ecm cell rows and temperature from radio-style sensors, and still no true SOC outside Diagnostics.
func _live_pack_flight() -> void:
	var flight: Node = load("res://main.tscn").instantiate()
	flight.user_args = PackedStringArray(["--aircraft=turbo-lumber-evolution", "--battery=pack"])
	flight.overlays_enabled = true
	flight.overlay_settings = { preset = "full", units = "metric" }
	root.add_child(flight)
	for i in 30:
		await process_frame
	var overlays: CanvasLayer = flight.get("_overlays")
	var session: Node = flight.get("session")
	_check("pack flight builds the overlays and the pack session", overlays != null and session != null and session.battery_is_pack())
	if overlays == null or session == null:
		flight.queue_free()
		return
	var panel: Control = overlays.frames.battery
	var state: Dictionary = session.electrical_state()
	_check("pack telemetry reaches the overlay", state.get("battery_kind") == "pack_ecm" and panel.visible and panel.detailed,
		"%s %s %s" % [state.get("battery_kind"), panel.visible, panel.detailed])
	_check("pack: cell rows and temperature come from the sensors", panel.values.cell_avg.visible and panel.values.cell_avg.text.ends_with(" V/cell")
		and panel.values.cell_min.visible and panel.values.temperature.visible,
		"%s | %s | %s" % [panel.values.cell_avg.text, panel.values.cell_min.text, panel.values.temperature.text])
	_check("pack: no true SOC in the Full preset", not _texts(overlays).contains("SOC"))
	flight.queue_free()
	await process_frame
