extends SceneTree

const CustomizationPage := preload("res://ui/workshop_customization.gd")
const Presentation := preload("res://workshop/presentation.gd")
const Sources := preload("res://render/presentation_sources.gd")

var checks := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	TranslationServer.set_locale("en")
	root.size = Vector2i(1280, 720)
	var bindings := _test_bindings()
	var binding_check: Dictionary = Presentation.validate(Presentation.defaults(bindings), bindings)
	_check("synthetic v3 smoke bindings pass the strict profile contract",
		bool(binding_check.get("ok", false)), str(binding_check.get("errors", [])))
	if not bool(binding_check.get("ok", false)):
		_finish()
		return
	var show_slots: Array[Dictionary] = []
	for slot: Dictionary in bindings.smoke_slots:
		if str(slot.get("kind", "")) == "show": show_slots.append(slot)
	_check("fixture has a pair of authored show outlets", show_slots.size() >= 2)
	if show_slots.size() < 2:
		_finish()
		return
	var profile: Dictionary = Presentation.defaults(bindings)
	var left := _smoke_entry(str(show_slots[0].id), "#F53A9BFF")
	left.density = 1.35
	left.emission_rate_hz = 78.0
	left.palette = ["#F53A9BFF", "#8A3EE8FF"]
	left.step_s = 0.8
	var right := _smoke_entry(str(show_slots[1].id), "#0DC7D6FF")
	right.density = 0.45
	right.emission_rate_hz = 34.0
	profile.smoke = [left, right]
	var checked: Dictionary = Presentation.validate(profile, bindings)
	_check("v2 fixture passes strict profile validation", bool(checked.get("ok", false)), str(checked.get("errors", [])))
	if not bool(checked.get("ok", false)):
		_finish()
		return

	var page := CustomizationPage.new()
	page.page_kind = "smoke"
	var panels := HSplitContainer.new()
	panels.name = "WorkshopSmokeLayout"
	panels.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(panels)
	var controls_panel := PanelContainer.new()
	controls_panel.name = "SmokeControlsPanel"
	controls_panel.custom_minimum_size.x = 400.0
	panels.add_child(controls_panel)
	var scroll := ScrollContainer.new()
	scroll.name = "SmokeControlsScroll"
	controls_panel.add_child(scroll)
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(page)
	var preview_panel := PanelContainer.new()
	preview_panel.name = "SmokePreviewPanel"
	preview_panel.custom_minimum_size.x = 400.0
	panels.add_child(preview_panel)
	var preview_caption := Label.new()
	preview_caption.text = "Workshop smoke preview"
	preview_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preview_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	preview_panel.add_child(preview_caption)
	await process_frame
	page.configure(bindings, checked.profile)
	var recorder := {"count": 0, "profile": {}}
	page.profile_changed.connect(func(value: Dictionary) -> void:
		recorder.count += 1
		recorder.profile = value.duplicate(true))
	var pending := {"value": false}
	page.validity_changed.connect(func(_kind: String, value: bool) -> void: pending.value = value)
	_check("density and emission rate are separate visible controls",
		page.find_child("SmokeDensity", true, false) is SpinBox
		and page.find_child("SmokeEmissionRateHz", true, false) is SpinBox
		and not page.get("_field_rows").amount.visible)
	_check("motion controls expose the independent v2 coefficients",
		page.find_child("SmokeJetSpeedMps", true, false) is SpinBox
		and page.find_child("SmokeTurbulenceMps", true, false) is SpinBox
		and page.find_child("SmokeDispersionM2S", true, false) is SpinBox
		and page.find_child("SmokeBuoyancyMps", true, false) is SpinBox
		and page.find_child("SmokeDragS", true, false) is SpinBox
		and page.find_child("SmokeVelocityInheritance", true, false) is SpinBox)
	_check("palette mode and phase offset controls are present",
		page.find_child("SmokePaletteMode", true, false) is OptionButton
		and page.find_child("SmokePhaseOffsetS", true, false) is SpinBox)
	_check("Godot picker, editable hex, Apply and Cancel are present",
		page.find_child("SmokeColorPicker", true, false) is ColorPickerButton
		and page.find_child("PresentationColor", true, false) is LineEdit
		and page.find_child("CancelSmokeColor", true, false) is Button)

	_select_slot(page, str(show_slots[0].id))
	var before_rate := float(page.call("current_entry").emission_rate_hz)
	page.call("change", "density", 1.6)
	_check("density edit leaves emission rate unchanged", is_equal_approx(float(page.call("current_entry").density), 1.6)
		and is_equal_approx(float(page.call("current_entry").emission_rate_hz), before_rate))
	page.call("change", "emission_rate_hz", 91.0)
	_check("emission rate edit leaves density unchanged", is_equal_approx(float(page.call("current_entry").density), 1.6)
		and is_equal_approx(float(page.call("current_entry").emission_rate_hz), 91.0))
	page.call("change", "palette_mode", "smooth")
	page.call("change", "phase_offset_s", 1.25)
	_check("smooth palette and bounded phase offset remain independent profile settings",
		page.call("current_entry").palette_mode == "smooth"
		and is_equal_approx(float(page.call("current_entry").phase_offset_s), 1.25))
	var proposals_before_copy: int = recorder.count
	var copy_target: OptionButton = page.get("_copy_target")
	var target_index := _item_for_metadata(copy_target, str(show_slots[1].id))
	copy_target.select(target_index)
	_check("compatible authored emitter can be selected for a one-time copy", target_index > 0 and not copy_target.disabled)
	var copied := bool(page.call("copy_settings_to_target"))
	var target_entry := _entry_for(recorder.profile, str(show_slots[1].id))
	var source_entry := _entry_for(recorder.profile, str(show_slots[0].id))
	_check("copy changes the target settings once and preserves both outlet IDs",
		copied and recorder.count == proposals_before_copy + 1
		and str(source_entry.get("slot", "")) == str(show_slots[0].id)
		and str(target_entry.get("slot", "")) == str(show_slots[1].id)
		and is_equal_approx(float(target_entry.density), float(source_entry.density))
		and is_equal_approx(float(target_entry.emission_rate_hz), float(source_entry.emission_rate_hz))
		and target_entry.palette_mode == "smooth"
		and is_equal_approx(float(target_entry.phase_offset_s), 1.25))
	page.call("change", "density", 1.75)
	_check("copied emitters remain independent after the one-time copy",
		is_equal_approx(float(page.call("current_entry").density), 1.75)
		and is_equal_approx(float(_entry_for(page.get("_profile"), str(show_slots[1].id)).density), 1.6))

	var color_before := str(page.call("current_entry").color)
	var proposals_before_picker: int = recorder.count
	page.call("_on_picker_color_changed", Color.from_string("#8B39C7A5", Color.WHITE))
	var picker_state := "pending=%s validity=%s color=%s" % [page.call("has_pending_color"), pending.value, page.get("_custom_color").text]
	_check("picker changes stay pending until Apply and block validity",
		page.call("has_pending_color") and pending.value and recorder.count == proposals_before_picker
		and page.get("_custom_color").text == "#8B39C7A5", picker_state)
	page.call("cancel_pending_edit")
	_check("Cancel restores the selected color without changing the profile",
		not page.call("has_pending_color") and page.call("current_entry").color == color_before
		and recorder.count == proposals_before_picker)
	page.call("_on_picker_color_changed", Color.from_string("#8B39C7A5", Color.WHITE))
	page.call("apply_color")
	var colored_entry: Dictionary = page.call("current_entry")
	var applied_state := "pending=%s selected=%s palette=%s emissions=%d" % [page.call("has_pending_color"), colored_entry.get("color"), colored_entry.get("palette"), recorder.count]
	_check("Apply commits the unusual alpha color as one edit",
		not page.call("has_pending_color") and colored_entry.palette[0] == "#8B39C7A5"
		and recorder.count == proposals_before_picker + 1, applied_state)
	var accepted_before_invalid: Dictionary = page.get("_profile").duplicate(true)
	page.call("change", "emission_rate_hz", 241.0)
	_check("strict validation refuses rates above the v2 limit", page.get("_profile") == accepted_before_invalid)

	var legacy: Dictionary = checked.profile.duplicate(true)
	legacy.version = Presentation.LEGACY_VERSION
	for entry: Dictionary in legacy.smoke:
		for key: String in Presentation.smoke_v2_defaults(): entry.erase(key)
	var legacy_checked: Dictionary = Presentation.validate(legacy, bindings)
	_check("v1 fixture validates through the explicit legacy reader", bool(legacy_checked.get("ok", false)))
	if bool(legacy_checked.get("ok", false)):
		var untouched_snapshot: Dictionary = legacy_checked.profile.duplicate(true)
		page.configure(bindings, legacy_checked.profile)
		_select_slot(page, str(show_slots[0].id))
		var default_density := float(Presentation.smoke_v2_defaults().density)
		_check("untouched v1 profile stays v1 while controls show normalized v2 defaults",
			int(page.get("_profile").version) == Presentation.LEGACY_VERSION
			and is_equal_approx(float(page.find_child("SmokeDensity", true, false).value), default_density))
		page.call("change", "density", 1.1)
		_check("first explicit smoke edit proposes v2 and preserves the original v1 snapshot",
			int(page.get("_profile").version) == Presentation.VERSION
			and is_equal_approx(float(page.call("current_entry").density), 1.1)
			and untouched_snapshot == legacy_checked.profile)
	else:
		_check("legacy profile migration fixture is available", false, str(legacy_checked.get("errors", [])))

	for viewport_size: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = viewport_size
		await process_frame
		await process_frame
		var controls_rect := scroll.get_global_rect()
		var panel_rect := controls_panel.get_global_rect()
		var preview_rect := preview_panel.get_global_rect()
		var visible_controls_fit := panel_rect.encloses(controls_rect) and preview_rect.size.x > 1.0
		for node: Node in page.find_children("*", "Control", true, false):
			var control := node as Control
			if not is_instance_valid(control) or not control.is_visible_in_tree():
				continue
			var rect := control.get_global_rect()
			visible_controls_fit = visible_controls_fit and rect.position.x >= controls_rect.position.x - 1.0 \
				and rect.end.x <= controls_rect.end.x + 1.0
		var density_control := page.find_child("SmokeDensity", true, false) as Control
		var rate_control := page.find_child("SmokeEmissionRateHz", true, false) as Control
		var color_control := page.find_child("SmokeColorPicker", true, false) as Control
		var primary_controls_visible := controls_rect.intersects(density_control.get_global_rect()) \
			and controls_rect.intersects(rate_control.get_global_rect()) \
			and controls_rect.intersects(color_control.get_global_rect())
		_check("smoke controls stay inside the scrollable Workshop panel at %dx%d" % [viewport_size.x, viewport_size.y],
			visible_controls_fit and primary_controls_visible,
			"controls=%s panel=%s preview=%s basic=%s/%s/%s" % [controls_rect, panel_rect, preview_rect,
			density_control.get_global_rect(), rate_control.get_global_rect(), color_control.get_global_rect()])
		var advanced: Control = page.get("_advanced")
		advanced.visible = true
		await process_frame
		var scroll_bar := scroll.get_v_scroll_bar()
		scroll.scroll_vertical = int(scroll_bar.max_value)
		await process_frame
		var motion_control := page.find_child("SmokeVelocityInheritance", true, false) as Control
		var copy_control := page.find_child("SmokeCopySettings", true, false) as Control
		_check("advanced motion and copy controls remain scroll-reachable at %dx%d" % [viewport_size.x, viewport_size.y],
			controls_rect.intersects(motion_control.get_global_rect())
				and controls_rect.intersects(copy_control.get_global_rect()),
			"viewport=%s motion=%s copy=%s scroll=%d/%d" % [controls_rect,
			motion_control.get_global_rect(), copy_control.get_global_rect(), scroll.scroll_vertical, int(scroll_bar.max_value)])
		advanced.visible = false
		scroll.scroll_vertical = 0

	page.queue_free()
	await process_frame
	TranslationServer.set_locale("es")
	var spanish_page := CustomizationPage.new()
	spanish_page.page_kind = "smoke"
	spanish_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(spanish_page)
	await process_frame
	spanish_page.configure(bindings, checked.profile)
	var spanish_density := spanish_page.find_child("SmokeDensity", true, false) as Control
	var spanish_density_label := spanish_density.get_parent().get_child(0) as Label
	var spanish_copy := spanish_page.find_child("SmokeCopySettings", true, false) as Button
	_check("v2 density and copy controls have Spanish labels",
		spanish_density_label.text == "Densidad" and spanish_copy.text == "Copiar ajustes")
	spanish_page.queue_free()
	TranslationServer.set_locale("en")

	panels.free()
	await process_frame
	_finish()


func _smoke_entry(slot_id: String, color: String) -> Dictionary:
	var entry: Dictionary = Presentation.smoke_v2_defaults()
	entry.merge({"slot": slot_id, "enabled": true, "color": color, "amount": 0.6,
		"width_m": 0.15, "lifetime_s": 4.0, "shape": "ribbon", "mode": "hold",
		"burst_s": 0.0, "pulse_period_s": 0.0, "pulse_duty": 0.0, "palette": [], "step_s": 0.0}, true)
	return entry


func _test_bindings() -> Dictionary:
	var bindings := {
		"format": Presentation.BINDINGS_FORMAT,
		"version": 3,
		"source_proof_version": 2,
		"visual_family": "workshop-smoke-fixture",
		"model_manifest_sha256": "a".repeat(64),
		"paint_slots": [],
		"marking_slots": [],
		"smoke_slots": [
			_show_slot("left_tip", "Left tip", "wing_tip_left", [-0.2, 0.0, 0.3]),
			_show_slot("right_tip", "Right tip", "wing_tip_right", [0.2, 0.0, 0.3]),
		],
		"presentation_engine_version": Sources.ENGINE_VERSION_PIN,
		"presentation_sources": Sources.current_records(2),
		"slots_sha256": "",
	}
	bindings.slots_sha256 = Presentation.bindings_sha256(bindings)
	return bindings


func _show_slot(id: String, label: String, role: String, position: Array) -> Dictionary:
	return {
		"id": id,
		"label": label,
		"kind": "show",
		"pair": "wing_tips",
		"role": role,
		"radius_m": 0.003,
		"emissions_preset": "independent_show",
		"activation_policy": "independent_request",
		"provenance": "authored",
		"node_path": ".",
		"position_m": position,
		"direction": [0.0, 0.0, 1.0],
	}


func _select_slot(page: Node, slot_id: String) -> void:
	var selector: OptionButton = page.get("_slot")
	for index in selector.item_count:
		if str(selector.get_item_metadata(index)) == slot_id:
			selector.select(index)
			page.call("_select_slot", index)
			return


func _item_for_metadata(selector: OptionButton, value: String) -> int:
	for index in selector.item_count:
		if str(selector.get_item_metadata(index)) == value: return index
	return -1


func _entry_for(profile: Dictionary, slot_id: String) -> Dictionary:
	for entry: Dictionary in profile.get("smoke", []):
		if str(entry.get("slot", "")) == slot_id: return entry
	return {}


func _check(label: String, condition: bool, detail := "") -> void:
	checks += 1
	if condition: print("ok   ", label)
	else:
		failures += 1
		printerr("FAIL ", label, " ", detail)


func _finish() -> void:
	print("Workshop smoke controls: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
