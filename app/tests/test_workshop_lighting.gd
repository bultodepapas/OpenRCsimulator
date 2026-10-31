extends SceneTree

const Workshop := preload("res://ui/workshop.gd")
const LightingPanel := preload("res://ui/workshop_lighting.gd")
const LightingProfile := preload("res://render/lighting/lighting_profile.gd")
const Presentation := preload("res://workshop/presentation.gd")
const Customization := preload("res://render/aircraft_customization.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const ThemeSpec := preload("res://ui/ui_theme.gd")

var _failures := 0
var _probe_profiles: Array[Dictionary] = []


func _initialize() -> void:
	_run.call_deferred()


func _check(label: String, ok: bool, detail := "") -> void:
	if ok:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _settle(frames := 3) -> void:
	for _index: int in frames:
		await process_frame


func _run() -> void:
	var capture_dir := _capture_directory()
	root.size = Vector2i(1920, 1080) if not capture_dir.is_empty() else Vector2i(1280, 720)
	var editor := Workshop.new()
	editor.variants_root = "user://test_workshop_lighting"
	root.add_child(editor)
	await _settle(5)
	var bindings: Dictionary = Customization.describe(Catalog.DEFAULT_ID).bindings
	var lighting := editor.get("_page_nodes").lighting as Control
	var stock := editor.get_presentation()
	editor.call("_set_page", "lighting")
	_check("visiting Lighting leaves the stored profile untouched", editor.get_presentation() == stock)
	var stock_version := int(stock.get("version", 0))
	_check("stored presentation keeps the fields required by its historical version",
		stock_version in [1, 2, 3, 4] and (stock_version < 3 or stock.has("lighting"))
		and (stock_version < 4 or stock.has("mechanical_audio")))
	var preview: Control = editor.get("_preview")
	preview.call("set_preview_night", true)
	var default_kit: Node3D = preview.get("_lighting_rig").get_kit()
	_check("inherited night preview retains the stock orientation strips without editing the build",
		default_kit != null and default_kit.get_node("strip_left").visible and editor.get_presentation() == stock)
	preview.call("set_view_mode", "compare")
	preview.call("set_comparison_original", true)
	default_kit = preview.get("_lighting_rig").get_kit()
	_check("Original night comparison shows the same stock equipment", default_kit != null
		and default_kit.get_node("strip_left").visible)
	preview.call("set_preview_night", false)
	_check("Original day comparison switches the fitted kit off", not default_kit.visible)
	preview.call("set_view_mode", "inspect")

	var preset := lighting.get("_preset") as OptionButton
	var custom_index := _metadata_index(preset, "custom")
	var custom_count := 0
	for index in preset.item_count:
		if str(preset.get_item_metadata(index)) == "custom":
			custom_count += 1
	_check("preset menu lists each registered preset once, including Custom", preset.item_count == LightingProfile.PRESET_IDS.size() + 1
		and custom_count == 1 and custom_index >= 0)
	if custom_index >= 0:
		_select_preset(lighting, preset, custom_index)
	var current := editor.get_presentation()
	_check("Custom provides all semantic zones and optional effect entries", current.lighting.selection == "custom"
		and current.lighting.zones.size() == LightingProfile.ZONE_IDS.size()
		and current.lighting.effects.size() == 2
		and current.lighting.effects.all(func(effect: Dictionary) -> bool: return not effect.enabled))
	_check("lighting edit upgrades only historical v1/v2 and preserves newer fields",
		int(current.version) == (3 if stock_version < 3 else stock_version)
		and (stock_version < 4 or current.mechanical_audio == stock.mechanical_audio))

	lighting.call("_toggle_zones", true)
	var orientation_lock := lighting.get("_orientation_lock") as CheckButton
	var zone_selector := lighting.get("_zone_selector") as OptionButton
	var pattern_selector := lighting.get("_pattern_selector") as OptionButton
	var nav_index := _metadata_index(zone_selector, "nav_left")
	if nav_index >= 0:
		zone_selector.select(nav_index)
		lighting.call("_on_zone_selected", nav_index)
	var sequence_index := _metadata_index(pattern_selector, "sequence")
	var first_hex := lighting.find_child("LightingPaletteHex0", true, false) as LineEdit
	_check("Custom starts with orientation lock and blocks ineffective navigation palette/pattern edits",
		orientation_lock.button_pressed and pattern_selector.disabled and first_hex != null and not first_hex.editable,
		"locked=%s pattern_disabled=%s hex_editable=%s" % [orientation_lock.button_pressed,
		pattern_selector.disabled, first_hex.editable if first_hex != null else false])
	_check("sequence requires a saved cue for the selected zone", sequence_index >= 0
		and pattern_selector.is_item_disabled(sequence_index))

	orientation_lock.set_pressed_no_signal(false)
	lighting.call("_on_orientation_lock_toggled", false)
	first_hex = lighting.find_child("LightingPaletteHex0", true, false) as LineEdit
	_check("unlocking makes navigation palette and pattern controls editable",
		not pattern_selector.disabled and first_hex != null and first_hex.editable)
	var before_invalid := editor.get_presentation()
	first_hex.text = "#BAD"
	first_hex.text_changed.emit(first_hex.text)
	_check("invalid hex remains visible and blocks Save and Test fly",
		first_hex.text == "#BAD" and not editor.call("_edit_valid")
		and editor.save_button.disabled and editor.get("_trial_button").disabled)
	editor.call("_set_page", "setup")
	_check("a pending lighting edit holds page navigation", editor.get("_active_page") == "lighting")
	lighting.call("cancel_pending_edit")
	first_hex = lighting.find_child("LightingPaletteHex0", true, false) as LineEdit
	_check("cancel restores accepted palette text and launch validity", editor.call("_edit_valid")
		and first_hex.text == str(_zone(before_invalid.lighting, "nav_left").pattern.palette[0]))
	lighting.call("_add_palette_color")
	var rebuilt_picker := lighting.find_child("LightingPalettePicker1", true, false) as ColorPickerButton
	var rebuilt_remove := lighting.find_child("RemoveLightingColor1", true, false) as Button
	_check("rebuilt zone palette controls retain crystal feedback", rebuilt_picker != null and rebuilt_remove != null
		and rebuilt_picker.get_node_or_null("CrystalSurface") != null
		and rebuilt_remove.get_node_or_null("CrystalSurface") != null)
	if rebuilt_remove != null:
		rebuilt_remove.grab_focus()
		await _settle()
		var feedback: Node = rebuilt_remove.get_node_or_null("CrystalSurface")
		_check("rebuilt palette action shows crystal feedback on keyboard focus", feedback != null
			and feedback.get("_engaged") and feedback.get("_glass").visible)
	lighting.call("cancel_pending_edit")

	var palette_picker := lighting.find_child("LightingPalettePicker0", true, false) as ColorPickerButton
	var before_palette := editor.get_presentation()
	if palette_picker != null:
		palette_picker.color_changed.emit(Color("#3FA6FF"))
	lighting.call("_apply_zone")
	var after_palette := editor.get_presentation()
	_check("ColorPicker applies canonical six-digit HTML colors", palette_picker != null
		and _zone(after_palette.lighting, "nav_left").pattern.palette[0] == "#3FA6FF")
	editor.call("_undo")
	_check("Lighting participates in shared Undo", editor.get_presentation() == before_palette)
	editor.call("_redo")
	_check("shared Redo restores the lighting edit", editor.get_presentation() == after_palette)

	var zone_brightness := lighting.get("_zone_brightness") as HSlider
	lighting.call("_on_zone_brightness_changed", 0.42)
	_check("per-zone brightness is an explicit pending edit", lighting.has_pending_edit()
		and editor.save_button.disabled and editor.get("_trial_button").disabled)
	lighting.call("_apply_zone")
	_check("zone brightness applies independently of global brightness",
		is_equal_approx(float(_zone(editor.get_presentation().lighting, "nav_left").brightness), 0.42)
		and is_equal_approx(float(editor.get_presentation().lighting.brightness), float(after_palette.lighting.brightness)))
	_check("zone slider stays synchronized after commit", zone_brightness != null
		and is_equal_approx(zone_brightness.value, 0.42))

	var pulse_index := _metadata_index(pattern_selector, "pulse")
	pattern_selector.select(pulse_index)
	pattern_selector.item_selected.emit(pulse_index)
	var period := lighting.get("_period") as SpinBox
	lighting.call("_on_period_changed", 4.0)
	var reactive_selector := lighting.get("_reactive_selector") as OptionButton
	var throttle_index := _metadata_index(reactive_selector, "throttle")
	reactive_selector.select(throttle_index)
	lighting.call("_on_reactive_source_selected", throttle_index)
	lighting.call("_on_reactive_gain_changed", 0.35)
	lighting.call("_apply_zone")
	var edited_nav := _zone(editor.get_presentation().lighting, "nav_left")
	_check("pattern, cycle speed and telemetry response save through the advanced editor",
		edited_nav.pattern.id == "pulse" and int(edited_nav.pattern.period_ticks) == 960
		and edited_nav.reactive.source == "throttle" and is_equal_approx(float(edited_nav.reactive.gain), 0.35),
		"period=%s reactive=%s" % [period.value if period != null else -1.0, edited_nav.reactive])

	var neon_index := _metadata_index(preset, "neon_rgb")
	_select_preset(lighting, preset, neon_index)
	var strip_left_index := _metadata_index(zone_selector, "strip_left")
	if strip_left_index >= 0:
		zone_selector.select(strip_left_index)
		lighting.call("_on_zone_selected", strip_left_index)
	sequence_index = _metadata_index(pattern_selector, "sequence")
	_check("zones without saved cues keep Sequence disabled", sequence_index >= 0
		and pattern_selector.is_item_disabled(sequence_index))
	var festival_index := _metadata_index(preset, "festival")
	_select_preset(lighting, preset, festival_index)
	strip_left_index = _metadata_index(zone_selector, "strip_left")
	if strip_left_index >= 0:
		zone_selector.select(strip_left_index)
		lighting.call("_on_zone_selected", strip_left_index)
	sequence_index = _metadata_index(pattern_selector, "sequence")
	_check("Festival enables Sequence on cue-backed zones", sequence_index >= 0
		and not pattern_selector.is_item_disabled(sequence_index))

	custom_index = _metadata_index(preset, "custom")
	_select_preset(lighting, preset, custom_index)
	lighting.call("_toggle_effects", true)
	var effect_controls: Dictionary = lighting.get("_effects_controls_by_anchor")
	var effects_decorated := not effect_controls.is_empty()
	for controls: Dictionary in effect_controls.values():
		effects_decorated = effects_decorated and controls.enabled.get_node_or_null("CrystalSurface") != null \
			and controls.kind.get_node_or_null("CrystalSurface") != null
	_check("rebuilt effect toggles and selectors retain crystal feedback", effects_decorated)
	var left_effect: Dictionary = effect_controls.get("vfx_tip_left", {})
	var kind_selector := left_effect.get("kind") as OptionButton
	var lifetime := left_effect.get("lifetime") as SpinBox
	var enabled_control := left_effect.get("enabled") as CheckButton
	var trail_index := _metadata_index(kind_selector, "trail") if kind_selector != null else -1
	if trail_index >= 0:
		kind_selector.select(trail_index)
		kind_selector.item_selected.emit(trail_index)
	if lifetime != null:
		lifetime.set_value_no_signal(0.75)
		lifetime.value_changed.emit(0.75)
	if enabled_control != null:
		enabled_control.set_pressed_no_signal(true)
		enabled_control.toggled.emit(true)
	lighting.call("_apply_effects")
	var saved_effect := _effect(editor.get_presentation().lighting, "vfx_tip_left")
	_check("effects expose Wingtip spark/trail/burst, intensity and lifetime controls",
		kind_selector != null and trail_index >= 0 and lifetime != null and enabled_control != null
		and saved_effect.kind == "trail" and saved_effect.enabled
		and int(saved_effect.lifetime_ticks) == 180,
		"effect=%s" % saved_effect)

	await _test_rejected_edit_focus(editor, lighting)
	_test_configuration_reuse(bindings)
	_test_pinned_zone_defaults(bindings)
	_test_recovery_state(lighting)
	_test_sequence_integration(editor, lighting)
	await _test_migration(bindings, 1, true)
	await _test_migration(bindings, 2, false)
	await _test_migration(bindings, 4, false)
	if not capture_dir.is_empty():
		await _capture_lighting(editor, lighting, preset, capture_dir)

	editor.free()
	await process_frame
	print("Workshop lighting checks: %d failures" % _failures)
	quit(1 if _failures else 0)


func _test_rejected_edit_focus(editor: Node, lighting: Control) -> void:
	var original_size := root.size
	var original_scale := ThemeSpec.text_scale
	var original_locale := TranslationServer.get_locale()
	var scroll := editor.find_child("WorkshopScroll", true, false) as ScrollContainer
	# A rejected cross-panel edit must leave the existing input and draft intact.
	for pixels in [Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160), Vector2i(1280, 720)]:
		root.size = pixels
		for locale: String in ["en", "es"]:
			TranslationServer.set_locale(locale)
			for scale: float in [1.0, 2.0]:
				ThemeSpec.text_scale = scale
				editor.get("_screen").theme = ThemeSpec.build()
				lighting.call("cancel_pending_edit")
				lighting.call("_toggle_zones", true)
				lighting.call("_toggle_effects", true)
				await _settle(6)
				var tag := "%s/%s/%s" % [pixels, locale, scale]
				var before: Dictionary = editor.get_presentation()
				lighting.call("_set_effect_value", "vfx_tip_left", "intensity", 0.8)
				var hex := lighting.find_child("LightingPaletteHex0", true, false) as LineEdit
				var accepted_color := hex.text
				hex.grab_focus()
				await _settle(6)
				var offset := scroll.scroll_vertical
				hex.text = "#123456"
				hex.text_changed.emit(hex.text)
				await _settle(6)
				_check(tag + " rejected color keeps its input and focus", is_instance_valid(hex) and hex.has_focus())
				_check(tag + " rejected color keeps scroll", scroll.scroll_vertical == offset)
				_check(tag + " rejected color restores accepted text without discarding effects", lighting.get("_effects_pending")
					and lighting.find_child("LightingPaletteHex0", true, false).text == accepted_color
					and editor.get_presentation() == before and editor.save_button.disabled)
				var picker := lighting.find_child("LightingPalettePicker0", true, false) as ColorPickerButton
				picker.grab_focus()
				await _settle(6)
				offset = scroll.scroll_vertical
				picker.color = Color("#ABCDEF")
				picker.color_changed.emit(picker.color)
				await _settle(6)
				_check(tag + " rejected picker edit keeps its control, focus and scroll",
					is_instance_valid(picker) and picker.has_focus() and scroll.scroll_vertical == offset)
				_check(tag + " rejected picker restores the accepted color",
					lighting.find_child("LightingPalettePicker0", true, false).color == Color(accepted_color)
					and editor.get_presentation() == before)
				lighting.call("cancel_pending_edit")
				hex = lighting.find_child("LightingPaletteHex0", true, false) as LineEdit
				hex.text = "#BAD"
				hex.text_changed.emit(hex.text)
				for field: String in ["enabled", "kind", "intensity", "lifetime"]:
					var controls: Dictionary = lighting.get("_effects_controls_by_anchor")["vfx_tip_left"]
					var control: Control = controls[field]
					var focus_target: Control = control.get_line_edit() if control is SpinBox else control
					focus_target.grab_focus()
					await _settle(6)
					offset = scroll.scroll_vertical
					var accepted: Variant
					if control is SpinBox:
						accepted = control.value
						control.value = 0.9
					elif control is OptionButton:
						accepted = control.selected
						control.select((control.selected + 1) % control.item_count)
						control.item_selected.emit(control.selected)
					else:
						accepted = control.button_pressed
						control.button_pressed = not control.button_pressed
					await _settle(6)
					var restored: Control = lighting.get("_effects_controls_by_anchor")["vfx_tip_left"][field]
					_check(tag + "/" + field + " rejection keeps input, focus and scroll",
						is_instance_valid(control) and restored == control and focus_target.has_focus()
						and scroll.scroll_vertical == offset)
					var actual: Variant = restored.value if restored is SpinBox else (restored.selected if restored is OptionButton else restored.button_pressed)
					_check(tag + "/" + field + " rejection restores value and preserves pending color",
						actual == accepted and hex.text == "#BAD" and lighting.get("_zone_text_invalid")
						and editor.get_presentation() == before and editor.save_button.disabled)
	lighting.call("cancel_pending_edit")
	TranslationServer.set_locale(original_locale)
	ThemeSpec.text_scale = original_scale
	root.size = original_size
	editor.get("_screen").theme = ThemeSpec.build()
	await _settle(6)


func _select_preset(panel: Control, selector: OptionButton, index: int) -> void:
	if index < 0:
		return
	selector.select(index)
	panel.call("_on_preset_selected", index)


func _metadata_index(selector: OptionButton, key: String) -> int:
	if selector == null:
		return -1
	for index in selector.item_count:
		if str(selector.get_item_metadata(index)) == key:
			return index
	return -1


func _zone(profile: Dictionary, zone_id: String) -> Dictionary:
	for entry: Variant in profile.get("zones", []):
		if entry is Dictionary and str(entry.get("id", "")) == zone_id:
			return entry
	return {}


func _effect(profile: Dictionary, anchor_id: String) -> Dictionary:
	for entry: Variant in profile.get("effects", []):
		if entry is Dictionary and str(entry.get("anchor_id", "")) == anchor_id:
			return entry
	return {}


func _test_pinned_zone_defaults(bindings: Dictionary) -> void:
	var legacy: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/lighting/night_radian_r1.json"))
	legacy = LightingProfile.validate(legacy).profile
	var presentation := Presentation.defaults(bindings)
	presentation.lighting = legacy.duplicate(true)
	presentation.lighting.selection = "custom"
	for zone: Dictionary in presentation.lighting.zones:
		if zone.id == "strip_left":
			zone.brightness = 0.33
	var original := presentation.duplicate(true)
	var probe := LightingPanel.new()
	root.add_child(probe)
	probe.configure(bindings, presentation)
	_check("opening an old lighting build preserves its pin and edited values", presentation == original
		and probe.get("_profile") == original.lighting)
	var selector: OptionButton = probe.get("_zone_selector")
	var index := _metadata_index(selector, "strip_left")
	selector.select(index)
	probe.call("_on_zone_selected", index)
	probe.call("_reset_selected_zone")
	var reset: Dictionary = probe.get("_profile")
	_check("zone reset uses the pinned revision 1 default instead of revision 2", reset.preset_revision == 1
		and _zone(reset, "strip_left") == _zone(legacy, "strip_left")
		and _zone(reset, "strip_left").brightness == 0.2)
	var preset: OptionButton = probe.get("_preset")
	_select_preset(probe, preset, _metadata_index(preset, "night_radian"))
	var selected: Dictionary = probe.get("_profile")
	_check("explicit fresh preset selection adopts revision 2", selected.preset_revision == 2
		and _zone(selected, "strip_left").brightness == 1.0 and _zone(selected, "landing_lamp").brightness == 0.125)
	probe.free()


func _test_configuration_reuse(bindings: Dictionary) -> void:
	var panel := LightingPanel.new()
	root.add_child(panel)
	var initial := Presentation.defaults(bindings)
	initial.lighting = LightingProfile.preset("festival")
	panel.configure(bindings, initial)
	var selector: OptionButton = panel.get("_zone_selector")
	var strip_index := _metadata_index(selector, "strip_left")
	selector.select(strip_index)
	panel.call("_on_zone_selected", strip_index)
	var zone_hex: LineEdit = panel.get("_zone_hex_fields")[0]
	var effect_kind: OptionButton = panel.get("_effects_controls_by_anchor").vfx_tip_left.kind
	var sequence: Control = panel.get("_sequence_editor")
	var cue_hex: LineEdit = sequence.get("_color_fields")[0]
	var capability := {"state": "original", "zones": [], "effects": []}
	panel.set_capability_report(capability)
	var unrelated := initial.duplicate(true)
	unrelated.mechanical_audio.servo_level = 0.35
	panel.configure(bindings, unrelated)
	_check("unrelated presentation changes reuse all lighting editor rows",
		panel.get("_zone_hex_fields")[0] == zone_hex
		and panel.get("_effects_controls_by_anchor").vfx_tip_left.kind == effect_kind
		and sequence.get("_color_fields")[0] == cue_hex)
	_check("reused lighting controls keep the full incoming presentation snapshot",
		panel.get("_presentation") == unrelated)
	_check("unrelated presentation changes preserve current preview capability feedback",
		panel.get("_capability_report") == capability)
	var repeated_hex: LineEdit = panel.get("_zone_hex_fields")[0]
	panel.configure(bindings, unrelated)
	_check("identical accepted configure keeps lighting row identity",
		panel.get("_zone_hex_fields")[0] == repeated_hex)
	var changed := unrelated.duplicate(true)
	changed.lighting.brightness = 0.6
	panel.configure(bindings, changed)
	_check("changed lighting still rebuilds and synchronizes its controls",
		panel.get("_zone_hex_fields")[0] != repeated_hex
		and is_equal_approx(float(panel.get("_brightness").value), 0.6))
	var invalid_hex: LineEdit = panel.get("_zone_hex_fields")[0]
	invalid_hex.text = "#BAD"
	invalid_hex.text_changed.emit(invalid_hex.text)
	_check("fixture has pending invalid zone text before configure", panel.has_pending_edit())
	panel.configure(bindings, changed)
	_check("configure still discards pending zone text for identical accepted inputs",
		not panel.has_pending_edit() and panel.get("_zone_hex_fields")[0] != invalid_hex
		and panel.get("_zone_hex_fields")[0].text != "#BAD")
	var pending_state: Dictionary = panel.get_editor_state()
	pending_state.sequence.duration_text = "unfinished"
	_check("fixture restores pending cue text", panel.restore_editor_state(pending_state) and panel.has_pending_edit())
	panel.configure(bindings, changed)
	_check("configure still discards pending cue text for identical accepted inputs",
		not panel.has_pending_edit() and panel.get_editor_state().sequence.duration_text != "unfinished")
	var committed_profiles: Array[Dictionary] = []
	panel.profile_changed.connect(func(profile: Dictionary) -> void: committed_profiles.append(profile.duplicate(true)))
	panel.call("_on_enabled_toggled", false)
	_check("a lighting edit after reuse retains unrelated accepted presentation values",
		committed_profiles.size() == 1 and is_equal_approx(float(committed_profiles[0].mechanical_audio.servo_level), 0.35))
	panel.configure(bindings, changed)
	_check("configure also restores accepted state after a detached panel proposal",
		panel.get("_profile") == changed.lighting and panel.get("_enabled").button_pressed)
	panel.free()


func _test_recovery_state(panel: Control) -> void:
	var state: Dictionary = panel.call("get_editor_state")
	_check("lighting recovery includes bounded sequence editor state",
		state.keys().size() == 5 and state.has("zone") and state.has("zones_open")
		and state.has("effects_open") and state.color_text is Array and state.color_text.size() <= 8
		and preload("res://workshop/lighting_sequence.gd").validate_editor_state(state.sequence).ok)
	var restored := state.duplicate(true)
	_check("valid lighting editor state restores", panel.call("restore_editor_state", restored))
	var historical := state.duplicate(true)
	historical.erase("sequence")
	_check("historical lighting recovery without sequence state restores", panel.call("restore_editor_state", historical))
	var malformed := state.duplicate(true)
	malformed["unexpected"] = true
	_check("lighting recovery rejects unknown editor-state fields", not panel.call("restore_editor_state", malformed))
	malformed = state.duplicate(true)
	malformed.color_text = ["#FFFFFF"].duplicate()
	for _index in 8:
		malformed.color_text.append("#FFFFFF")
	_check("lighting recovery rejects more than eight raw color fields", not panel.call("restore_editor_state", malformed))


func _test_sequence_integration(editor: Node, panel: Control) -> void:
	var before: Dictionary = editor.get_presentation()
	var sequence: Control = panel.get("_sequence_editor")
	var added := preload("res://workshop/lighting_sequence.gd").add_cue(before.lighting)
	_check("sequence integration has an editable profile", added.ok)
	if not added.ok: return
	sequence.profile_changed.emit(added.profile)
	var accepted: Dictionary = editor.get_presentation()
	_check("sequence changes enter shared Workshop presentation", accepted.lighting.sequence.size() == before.lighting.sequence.size() + 1)
	editor.call("_undo")
	_check("sequence addition participates in shared Undo", editor.get_presentation() == before)
	editor.call("_redo")
	_check("shared Redo restores sequence addition", editor.get_presentation() == accepted)
	var state: Dictionary = panel.get_editor_state()
	state.sequence = preload("res://workshop/lighting_sequence.gd").editor_state(accepted.lighting, added.selected_id)
	state.sequence.duration_text = "unfinished"
	_check("unfinished cue timing restores as pending", panel.restore_editor_state(state) and panel.has_pending_edit())
	_check("unfinished cue timing blocks Save and Test fly", editor.save_button.disabled and editor.get("_trial_button").disabled)
	editor.call("_set_page", "appearance")
	_check("pending sequence holds Workshop navigation", editor.get("_active_page") == "lighting")
	var recovery: Dictionary = editor.call("_recovery_editor_state")
	_check("Workshop recovery carries raw cue timing", recovery.presentation_buffers.lighting.sequence.duration_text == "unfinished")
	var unrelated: Dictionary = accepted.duplicate(true)
	var bindings: Dictionary = editor.get("_presentation_bindings")
	unrelated.paint = [{"slot": bindings.paint_slots[0].id, "color": "#123456FF", "pattern": "solid", "accent": "none"}]
	editor.set_presentation(unrelated)
	_check("owner synchronization restores pending cue text after an unrelated appearance edit",
		panel.has_pending_edit() and panel.get_editor_state().sequence.duration_text == "unfinished"
		and editor.get_presentation().paint == unrelated.paint)
	panel.cancel_pending_edit()
	_check("cancel discards only pending cue edits", not panel.has_pending_edit() and editor.get_presentation().paint == unrelated.paint)
	editor.call("_undo")
	_check("Undo of an unrelated appearance edit keeps accepted lighting and clears no extra state",
		not panel.has_pending_edit() and editor.get_presentation() == accepted
		and panel.get("_presentation") == accepted)
	editor.call("_redo")
	_check("Redo refreshes the lighting panel's full presentation snapshot without changing lighting",
		not panel.has_pending_edit() and panel.get("_presentation") == editor.get_presentation()
		and editor.get_presentation().paint == unrelated.paint)
	editor.call("_undo")


func _test_migration(bindings: Dictionary, version: int, include_smoke: bool) -> void:
	var legacy := Presentation.defaults(bindings, version)
	if include_smoke:
		var smoke_slots: Array = bindings.get("smoke_slots", [])
		var smoke_slot := ""
		for slot: Dictionary in smoke_slots:
			if str(slot.get("kind", "")) in ["show", "source"]:
				smoke_slot = str(slot.id)
				break
		if not smoke_slot.is_empty():
			legacy.smoke = [{
				"slot": smoke_slot, "enabled": true, "color": "#FFFFFFFF", "amount": 0.75,
				"width_m": 0.5, "lifetime_s": 6.0, "shape": "ribbon", "mode": "hold",
				"burst_s": 0.0, "pulse_period_s": 0.0, "pulse_duty": 0.0,
				"palette": [], "step_s": 0.0,
			}]
	var before := legacy.duplicate(true)
	var probe := LightingPanel.new()
	root.add_child(probe)
	await process_frame
	probe.configure(bindings, legacy)
	probe.profile_changed.connect(_on_probe_profile_changed)
	var preset := probe.get("_preset") as OptionButton
	var neon_index := _metadata_index(preset, "neon_rgb")
	_check("v%d profile visit does not migrate or inject lighting" % version,
		legacy == before and (version < 3 or legacy.has("lighting")))
	_select_preset(probe, preset, neon_index)
	var migrated: Dictionary = _probe_profiles.back() if not _probe_profiles.is_empty() else {}
	var expected_version := 3 if version < 3 else version
	var smoke_preserved := true
	if include_smoke and not before.get("smoke", []).is_empty():
		var old_smoke: Dictionary = before.smoke[0]
		var new_smoke: Dictionary = migrated.get("smoke", [])[0] if not migrated.get("smoke", []).is_empty() else {}
		smoke_preserved = not new_smoke.is_empty() and new_smoke.slot == old_smoke.slot \
			and new_smoke.amount == old_smoke.amount and new_smoke.color == old_smoke.color \
			and new_smoke.shape == old_smoke.shape and new_smoke.has("density")
	_check("v%d lighting edit promotes additively and preserves smoke" % version,
		not migrated.is_empty() and int(migrated.get("version", 0)) == expected_version
		and migrated.has("lighting") and migrated.lighting.preset_id == "neon_rgb"
		and smoke_preserved and (version < 4 or migrated.get("mechanical_audio", {}) == before.get("mechanical_audio", {})),
		"profile=%s" % migrated)
	probe.free()
	await process_frame


func _on_probe_profile_changed(profile: Dictionary) -> void:
	_probe_profiles.append(profile.duplicate(true))


func _capture_directory() -> String:
	for argument: String in OS.get_cmdline_user_args():
		if not argument.begins_with("--capture-lighting="):
			continue
		var path := argument.trim_prefix("--capture-lighting=").strip_edges()
		var normalized := path.replace("\\", "/").simplify_path()
		var repository := ProjectSettings.globalize_path("res://").replace("\\", "/").trim_suffix("/").to_lower()
		var normalized_lower := normalized.to_lower()
		if not path.is_absolute_path() or normalized_lower == repository or normalized_lower.begins_with(repository + "/"):
			printerr("--capture-lighting requires an absolute directory outside the repository")
			_failures += 1
			return ""
		if DisplayServer.get_name() == "headless":
			printerr("--capture-lighting requires a native display session")
			_failures += 1
			return ""
		var error := DirAccess.make_dir_recursive_absolute(normalized)
		if error != OK:
			printerr("Could not create lighting capture directory: %s" % normalized)
			_failures += 1
			return ""
		return normalized
	return ""


func _capture_lighting(editor: CanvasLayer, panel: Control, preset: OptionButton, directory: String) -> void:
	if root.size != Vector2i(1920, 1080):
		_check("lighting capture is 1920×1080", false, "window=%s" % root.size)
		return
	var preview := editor.get("_preview") as Control
	var neon_index := _metadata_index(preset, "neon_rgb")
	_select_preset(panel, preset, neon_index)
	preview.call("set_preview_night", true)
	await _settle(6)
	_check("Neon night preview has an active rig", is_instance_valid(preview.get("_lighting_rig")))
	_save_capture(directory.path_join("neon-night.png"))
	var festival_index := _metadata_index(preset, "festival")
	_select_preset(panel, preset, festival_index)
	preview.call("reset_playback")
	preview.call("toggle_playback")
	await _settle(8)
	_check("Festival capture is played on the isolated preview clock", bool(preview.get("_playing"))
		and int(preview.get("_playhead_tick")) > 0)
	_save_capture(directory.path_join("festival-night.png"))
	preview.call("toggle_playback")
	preview.call("reset_playback")


func _save_capture(path: String) -> void:
	var image := root.get_texture().get_image()
	_check("capture is a nonempty 1920×1080 frame", image != null and image.get_width() == 1920
		and image.get_height() == 1080, "image=%s" % (image.get_size() if image != null else Vector2i.ZERO))
	if image == null or image.get_width() != 1920 or image.get_height() != 1080:
		return
	_check("capture writes outside the repository", image.save_png(path) == OK, path)
