extends SceneTree
const Workshop := preload("res://ui/workshop.gd")
const Profile := preload("res://render/lighting/lighting_profile.gd")
const Presentation := preload("res://workshop/presentation.gd")
const Lights := preload("res://render/world/aircraft_lights.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1920, 1080)
	var editor := Workshop.new()
	editor.variants_root = "user://test_lighting_support_%d" % Time.get_ticks_usec()
	root.add_child(editor)
	for i in 5: await process_frame
	editor._set_page("lighting")
	var panel: Control = editor._page_nodes.lighting
	var preview: Control = editor._preview
	check("inherited lighting has no misleading custom availability count", preview.get_lighting_capability_report().state == "inherit"
		and not panel._availability_button.visible)
	var presentation := Presentation.defaults(editor._presentation_bindings, 3)
	presentation.lighting = Profile.preset("custom")
	editor.set_presentation(presentation)
	var accepted: Dictionary = editor.get_presentation()
	var report: Dictionary = preview.get_lighting_capability_report()
	check("preview reports all requested zones to the Workshop", report.state == "configured" and report.zones.size() == 13
		and panel._capability_report == report and panel._availability_button.visible)
	check("aircraft support details start collapsed", not panel._availability_details.visible)
	panel._availability_button.button_pressed = true
	check("details reveal named hardware limitations without editing the profile", panel._availability_details.visible
		and panel._availability_details.text.contains("Port navigation") and editor.get_presentation() == accepted)
	var detached: Dictionary = preview.get_lighting_capability_report()
	detached.zones.clear()
	check("preview reports are detached", preview.get_lighting_capability_report().zones.size() == 13)
	# Model-level capability, not a disabled profile zone: exercise actual renderer admission.
	var kit: Node3D = preview._lighting_rig.get_kit()
	Lights.bind_groups(kit, kit.get_meta("light_bindings"), ["navigation"])
	preview._configure_lighting()
	report = preview.get_lighting_capability_report()
	check("summary counts usable enabled zones rather than configured entries", panel._availability.text.contains("3 of 13")
		and panel._availability_details.text.contains("does not support this light group"))
	var index := _zone_index(panel._zone_selector, "strip_left")
	panel._zone_selector.select(index)
	panel._on_zone_selected(index)
	check("unsupported zone remains selectable and editable with a reason", panel._zone_selector.get_item_text(index).contains("unavailable")
		and not panel._zone_selector.is_item_disabled(index) and not panel._zone_enabled.disabled
		and panel._zone_availability.text.contains("does not support"))
	var hex: LineEdit = panel.find_child("LightingPaletteHex0", true, false)
	hex.text = "#BAD"
	hex.text_changed.emit(hex.text)
	check("pending invalid edit still blocks saving", panel.has_pending_edit() and editor.save_button.disabled)
	preview.set_view_mode("compare")
	preview.set_comparison_original(true)
	check("Original view explicitly suspends draft capability claims", preview.get_lighting_capability_report().state == "original"
		and panel._availability.text.contains("Select Draft") and not panel._availability_details.visible)
	preview.set_comparison_original(false)
	check("capability refresh preserves pending text and accepted settings", is_instance_valid(hex) and hex.text == "#BAD"
		and panel.has_pending_edit() and editor.save_button.disabled and editor.get_presentation() == accepted)
	panel.cancel_pending_edit()
	preview.set_view_mode("inspect")
	preview.set_preview_night(true)
	var night_report: Dictionary = preview.get_lighting_capability_report()
	preview.set_preview_night(false)
	check("day/night does not mistake visibility for hardware availability", preview.get_lighting_capability_report() == night_report)
	panel._on_enabled_toggled(false)
	check("disabled lighting clears prior availability rows", preview.get_lighting_capability_report().state == "disabled"
		and not panel._availability_button.visible and panel._zone_availability.text.is_empty())
	editor._undo()
	check("Undo restores capability feedback with the accepted lighting", editor.get_presentation() == accepted
		and preview.get_lighting_capability_report().state == "configured" and panel._availability.text.contains("3 of 13"))
	# Reapplying an identical profile may not rebuild the preview; Workshop still restores its report.
	editor._sync_presentation()
	check("unchanged presentation refresh retains current capability feedback", panel._availability.text.contains("3 of 13"))
	editor.set_aircraft("p51d-mustang-120", true)
	check("aircraft replacement discards the prior support report", preview.get_lighting_capability_report().state == "inherit"
		and not panel._availability.text.contains("3 of 13"))
	preview._dispose_lighting_rig()
	preview._airplane_root.free()
	preview._configure_lighting()
	check("missing preview aircraft clears availability", preview.get_lighting_capability_report().state == "unavailable"
		and not panel._availability_button.visible)
	editor.free()
	await process_frame
	print("Workshop lighting capabilities: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)

func _zone_index(selector: OptionButton, id: String) -> int:
	for i in selector.item_count:
		if selector.get_item_metadata(i) == id: return i
	return -1

func check(label: String, ok: bool) -> void:
	checks += 1
	print(("ok   " if ok else "FAIL ") + label)
	if not ok: failures += 1
