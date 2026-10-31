# AE-09: Workshop controls, supported edits, pinned variants and display sizing stay usable in isolation.
extends SceneTree

const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Compiler := preload("res://workshop/compiler.gd")
const Presentation := preload("res://workshop/presentation.gd")
const Descriptor := preload("res://workshop/descriptor.gd")
const Store := preload("res://workshop/store.gd")
const Workshop := preload("res://ui/workshop.gd")
const UiDriver := preload("res://tests/ui_driver.gd")
const UiTheme := preload("res://ui/ui_theme.gd")

class CompileCountingWorkshop extends Workshop:
	var compile_count := 0

	func _compile_recipe() -> void:
		compile_count += 1
		super._compile_recipe()

var _failures := 0
var _ui: RefCounted


func _initialize() -> void:
	_ui = UiDriver.new(self)
	_run.call_deferred()


func _check(label: String, ok: bool, detail := "") -> void:
	if ok:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _find(node: Node, child_name: String) -> Node:
	return node.find_child(child_name, true, false)


func _run() -> void:
	TranslationServer.set_locale("en")
	root.size = Vector2i(1280, 720)
	var store_root := "user://test_workshop_ui_%d" % Time.get_ticks_usec()
	var workshop: Variant = CompileCountingWorkshop.new()
	workshop.initial_aircraft_id = Catalog.DEFAULT_ID
	workshop.variants_root = store_root
	root.add_child(workshop)
	await _ui.settle()

	var title := _find(workshop, "WorkshopTitle") as Label
	var base_selector := _find(workshop, "BaseAircraft") as OptionButton
	var scale_selector := _find(workshop, "Scale") as OptionButton
	var mass_selector := _find(workshop, "MassPolicy") as OptionButton
	var test_fly := _find(workshop, "TestFly") as Button
	var preview := _find(workshop, "AircraftPreview") as Control
	var airplane_entries: Array = Catalog.airplane_flyable_entries()
	_check("screen renders its title, preview and test action", title != null and preview != null and test_fly != null)
	_check("airplane selector discovers every fixed-wing flyable aircraft",
		base_selector != null and base_selector.item_count == airplane_entries.size())
	_check("initial keyboard focus enters the library action", _ui.focus_name() == "OpenLibrary", _ui.focus_name())
	_check("Workshop is a still editor with no flight session", workshop.get("_compiled").get("ok", false)
		and workshop.get("_trial_pending") == false)

	# Both target heights keep the preview, editor panel and Test Fly action available.
	for viewport_size: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = viewport_size
		await _ui.settle()
		var panel := _find(workshop, "WorkshopPanel") as Control
		_check("layout fits %dp height" % viewport_size.y,
			panel != null and panel.get_rect().size.x > 0.0 and panel.get_rect().size.y > 0.0
			and preview.is_visible_in_tree() and test_fly.is_visible_in_tree()
			and Rect2(Vector2.ZERO, Vector2(viewport_size)).encloses(test_fly.get_global_rect())
			and Rect2(Vector2.ZERO, Vector2(viewport_size)).encloses(title.get_global_rect()))
	_check("opening starts at the top of the editor", workshop.get("_body_scroll").scroll_vertical == 0)
	var build_identity := _find(workshop, "BuildIdentity") as Label
	_check("title fitting preserves theme readability", title.resize_font_to_fit and title.minimum_font_size == 26 and title.maximum_font_size == 28)
	_check("build name can grow while retaining its readable minimum", build_identity.resize_font_to_fit and build_identity.minimum_font_size == 22 and build_identity.maximum_font_size == 28)

	# The same menu labels can translate while the screen is open.
	TranslationServer.set_locale("es")
	await _ui.settle()
	_check("Spanish locale translates the Workshop title", title != null and title.can_auto_translate()
		and title.atr(title.text) == "Taller de aviones", title.atr(title.text) if title != null else "missing title")
	TranslationServer.set_locale("en")
	await _ui.settle()
	await _ui.tap(KEY_TAB)
	_check("Tab advances focus inside the editor", _ui.focus_name() != "" and _ui.focus_name() != "OpenLibrary", _ui.focus_name())

	var unsupported_found := false
	for entry: Dictionary in airplane_entries:
		var aircraft_id := str(entry.get("id", ""))
		workshop.set_aircraft(aircraft_id, true)
		await _ui.settle()
		var selected_index := base_selector.get_selected_id()
		var selected_matches := str(base_selector.get_item_metadata(selected_index)) == aircraft_id
		_check("fixed-wing selection remains aligned: %s" % aircraft_id, selected_matches)
		var raw_base: Dictionary = workshop.get("_base")
		if raw_base.is_empty():
			_check("preview-only aircraft blocks flight build: %s" % aircraft_id, not bool(workshop.get_compiled().get("ok", false)))
			continue
		var caps: Dictionary = Compiler.capabilities(raw_base)
		_check("no-op build validates: %s" % aircraft_id, bool(workshop.get_compiled().get("ok", false)))
		var weight_slider := workshop.get("_factor_sliders")["weight_multiplier"] as HSlider
		var power_slider := workshop.get("_factor_sliders")["power_multiplier"] as HSlider
		var control_slider := workshop.get("_factor_sliders")["control_multiplier"] as HSlider
		var tank_capacity_slider := workshop.get("_factor_sliders")["tank_capacity_multiplier"] as HSlider
		_check("unsupported controls stay visible and inactive: %s" % aircraft_id,
			scale_selector.disabled == not bool(caps.get("scale", false))
			and mass_selector.disabled == not bool(caps.get("weight", false))
			and weight_slider.editable == bool(caps.get("weight", false))
			and power_slider.editable == bool(caps.get("power", false))
			and control_slider.editable == bool(caps.get("controls", false))
			and tank_capacity_slider.editable == bool(caps.get("tank_capacity", false)))
		if not bool(caps.get("tank_capacity", false)):
			var tank_hint: Label = workshop.get("_factor_hints")["tank_capacity_multiplier"]
			_check("tank-size control explains the absence of a declared finite tank: %s" % aircraft_id,
				tank_hint.text.contains("No declared finite tank"), tank_hint.text)
		if not bool(caps.get("scale", false)):
			unsupported_found = true
	_check("catalog includes aircraft with restricted Workshop adjustments", unsupported_found)
	workshop.set_aircraft("gp-extra-300s-60", true)
	await _ui.settle()
	var glow_scale_hint := _find(workshop, "ScaleSupport") as Label
	var glow_capacity_slider := workshop.get("_factor_sliders")["tank_capacity_multiplier"] as HSlider
	_check("finite-glow engine scaling stays disabled with its qualified limitation",
		scale_selector.disabled and glow_scale_hint != null
		and glow_scale_hint.text.contains("finite-glow installation data must remain fixed"),
		glow_scale_hint.text if glow_scale_hint != null else "missing scale limitation")
	_check("finite-glow aircraft still exposes independent finite-tank sizing",
		glow_capacity_slider.editable
		and str(workshop.get("_factor_hints")["tank_capacity_multiplier"].text).contains("Estimated sizing proposal"))
	workshop.set_aircraft("xcell-60-research", true)
	await _ui.settle()
	var rotorcraft_note := _find(workshop, "WorkshopStatus") as Label
	_check("direct rotorcraft requests return to the fixed-wing default",
		workshop.get("_base_id") == Catalog.DEFAULT_ID and bool(workshop.get_compiled().get("ok", false)))
	_check("direct rotorcraft requests explain the Workshop limit",
		rotorcraft_note != null and "fixed-wing" in rotorcraft_note.text.to_lower())

	workshop.set_aircraft(Catalog.DEFAULT_ID, true)
	await _ui.settle()
	var tank_capacity_slider := workshop.get("_factor_sliders")["tank_capacity_multiplier"] as HSlider
	var tank_capacity_hint: Label = workshop.get("_factor_hints")["tank_capacity_multiplier"]
	_check("declared tank exposes a separate estimated-capacity control",
		bool(workshop.get("_capabilities").get("tank_capacity", false))
		and tank_capacity_slider.editable and tank_capacity_hint.text.contains("Estimated sizing proposal"))
	workshop.set_recipe({"tank_capacity_multiplier": 1.25}, false)
	_check("tank-size edit compiles and is called out as an estimate",
		bool(workshop.get_compiled().get("ok", false))
		and is_equal_approx(float(workshop.get_recipe().tank_capacity_multiplier), 1.25)
		and is_equal_approx(tank_capacity_slider.value, 1.25)
		and str(workshop.get("_summary_label").text).contains("estimated sizing"),
		str(workshop.get("_summary_label").text))
	workshop.set_recipe({"tank_capacity_multiplier": 1.0}, false)
	await _ui.settle()
	var advanced_toggle := _find(workshop, "AdvancedControlThrows") as CheckButton
	var advanced_box := _find(workshop, "AdvancedControlsBox") as VBoxContainer
	var surface_keys: Array[String] = [
		"control_multiplier_aileron", "control_multiplier_elevator", "control_multiplier_rudder",
	]
	var surface_sliders: Dictionary = workshop.get("_factor_sliders")
	var surface_sliders_present := true
	for surface_key: String in surface_keys:
		if not surface_sliders.has(surface_key) or surface_sliders[surface_key] == null:
			surface_sliders_present = false
	_check("advanced surface sliders exist and start collapsed",
		advanced_toggle != null and advanced_box != null and surface_sliders_present
		and advanced_box.visible == false and not advanced_toggle.button_pressed)
	if advanced_toggle != null and advanced_box != null and surface_sliders_present:
		advanced_toggle.button_pressed = true
		await _ui.settle()
		_check("advanced surface controls expand on demand", advanced_box.visible)
		workshop.set_recipe({"control_multiplier": 1.2}, false)
		var inherited_recipe: Dictionary = workshop.get_recipe()
		var inherited_sliders_match := true
		for surface_key: String in surface_keys:
			var surface_slider: HSlider = surface_sliders[surface_key]
			inherited_sliders_match = inherited_sliders_match \
				and not inherited_recipe.has(surface_key) \
				and is_equal_approx(surface_slider.value, 1.2)
		_check("legacy recipe without surface keys displays the effective global value",
			inherited_sliders_match)

		var aileron_slider: HSlider = surface_sliders.control_multiplier_aileron
		var control_slider: HSlider = workshop.get("_factor_sliders").control_multiplier
		aileron_slider.value = 1.3
		await _ui.settle()
		var surface_recipe: Dictionary = workshop.get_recipe()
		var compiled_surface: Dictionary = workshop.get_compiled()
		var compiled_model: Dictionary = compiled_surface.get("data", {}).get("model", {})
		var compiled_throws: Dictionary = compiled_model.get("controls", {}).get("throw_deg", {})
		var base_throws: Dictionary = workshop.get("_base_model").get("controls", {}).get("throw_deg", {})
		_check("one surface override stays optional and compiles independently",
			surface_recipe.has("control_multiplier_aileron")
			and not surface_recipe.has("control_multiplier_elevator")
			and not surface_recipe.has("control_multiplier_rudder")
			and is_equal_approx(float(aileron_slider.value), 1.3)
			and compiled_surface.get("ok", false)
			and is_equal_approx(float(compiled_throws.get("aileron", 0.0)),
				float(base_throws.get("aileron", 0.0)) * 1.3))
		var compiled_aileron_text := "%.1f" % float(compiled_throws.get("aileron", 0.0))
		_check("technical summary reports compiled surface throw in degrees",
			str(workshop.get("_summary_label").text).contains("Aileron throw")
			and str(workshop.get("_summary_label").text).contains(compiled_aileron_text)
			and str(workshop.get("_summary_label").text).contains("°"))
		advanced_toggle.button_pressed = false
		await _ui.settle()
		var collapsed_edit: Dictionary = workshop.get_recipe()
		collapsed_edit.power_multiplier = 1.1
		workshop.set_recipe(collapsed_edit, false)
		await _ui.settle()
		_check("advanced disclosure stays usable with an active override",
			not advanced_box.visible and advanced_toggle.visible
			and workshop.get_recipe().has("control_multiplier_aileron"))
		advanced_toggle.button_pressed = true
		control_slider.value = 1.1
		await _ui.settle()
		var master_recipe: Dictionary = workshop.get_recipe()
		var master_sliders_match := true
		for surface_key: String in surface_keys:
			master_sliders_match = master_sliders_match \
				and not master_recipe.has(surface_key) \
				and is_equal_approx(float(surface_sliders[surface_key].value), 1.1)
		_check("master control edit clears overrides and synchronizes inherited sliders",
			not master_recipe.has("control_multiplier_aileron") and master_sliders_match)
		(_find(workshop, "UndoRecipe") as Button).pressed.emit()
		await _ui.settle()
		_check("Undo restores the individual override after a master edit",
			workshop.get_recipe().has("control_multiplier_aileron")
			and is_equal_approx(float(aileron_slider.value), 1.3))
		(_find(workshop, "RedoRecipe") as Button).pressed.emit()
		await _ui.settle()
		_check("Redo restores master inheritance without stored overrides",
			not workshop.get_recipe().has("control_multiplier_aileron")
			and is_equal_approx(float(aileron_slider.value), 1.1))

		workshop.set_recipe({
			"control_multiplier": 1.2,
			"control_multiplier_aileron": 1.35,
		}, false)
		var reset_source: Dictionary = workshop.get_recipe()
		(_find(workshop, "ResetRecipe") as Button).pressed.emit()
		await _ui.settle()
		_check("Reset removes optional overrides and restores inherited defaults",
			workshop.get_recipe() == Compiler.defaults()
			and not workshop.get_recipe().has("control_multiplier_aileron")
			and is_equal_approx(float(surface_sliders.control_multiplier_aileron.value), 1.0))
		(_find(workshop, "UndoRecipe") as Button).pressed.emit()
		await _ui.settle()
		_check("Undo restores the exact pre-reset surface override", workshop.get_recipe() == reset_source
			and is_equal_approx(float(surface_sliders.control_multiplier_aileron.value), 1.35))
		workshop.call("_apply_preset", "mini")
		var preset_recipe: Dictionary = workshop.get_recipe()
		var preset_inheritance_ok := true
		for surface_key: String in surface_keys:
			var surface_slider: HSlider = surface_sliders[surface_key]
			preset_inheritance_ok = preset_inheritance_ok \
				and not preset_recipe.has(surface_key) \
				and is_equal_approx(surface_slider.value, 0.9)
		_check("presets leave surface overrides absent and inherit their global travel",
			is_equal_approx(float(preset_recipe.get("control_multiplier", 0.0)), 0.9)
			and preset_inheritance_ok)
		workshop.set_recipe(Compiler.defaults(), false)
		workshop.call("_clear_history")
		var default_surface_values := true
		for surface_key: String in surface_keys:
			var surface_slider: HSlider = surface_sliders[surface_key]
			default_surface_values = default_surface_values \
				and not workshop.get_recipe().has(surface_key) \
				and is_equal_approx(surface_slider.value, 1.0)
		_check("Reset clears surface overrides and restores inherited defaults",
			workshop.get_recipe() == Compiler.defaults()
			and default_surface_values)

	workshop.set_recipe({"scale": 1.33, "weight_multiplier": 0.731}, false)
	_check("intermediate recipe values are never silently rounded", is_equal_approx(workshop.get_recipe().scale, 1.33)
		and is_equal_approx(workshop.get_recipe().weight_multiplier, 0.731))
	_check("slider displays the exact saved multiplier", is_equal_approx(workshop.get("_factor_sliders")["weight_multiplier"].value, 0.731))
	_check("scale selector includes the exact intermediate size", scale_selector.get_item_metadata(scale_selector.selected) == 1.33)
	var precise_recipe: Dictionary = workshop.get_recipe()
	workshop.set_recipe({"scale": []})
	_check("malformed recipe is refused before changing the draft", workshop.get_recipe() == precise_recipe
		and str(workshop.get("_status_label").text).contains("finite number"))
	for requested_scale: float in [0.5, 2.0]:
		workshop.set_recipe({"scale": requested_scale}, false)
		_check("scale %.0f%% compiles" % (requested_scale * 100.0), bool(workshop.get_compiled().get("ok", false))
			and is_equal_approx(float(workshop.get_recipe().scale), requested_scale))

	for preset_id: String in Workshop.PRESETS:
		var presets := _find(workshop, "StartingPreset") as OptionButton
		for index in presets.item_count:
			if presets.get_item_metadata(index) == preset_id:
				presets.select(index)
				presets.item_selected.emit(index)
				break
		await _ui.settle()
		_check("%s preset produces a valid recipe" % preset_id.capitalize(),
			bool(workshop.get_compiled().get("ok", false)))


	var previous_recipe: Dictionary = workshop.get_recipe()
	workshop.set_recipe({"scale": 0.5}, true)
	(_find(workshop, "UndoRecipe") as Button).pressed.emit()
	await _ui.settle()
	_check("Undo restores the prior recipe", workshop.get_recipe() == previous_recipe)
	workshop.set_recipe({"scale": 2.0, "weight_multiplier": 1.2, "power_multiplier": 1.1}, false)
	(_find(workshop, "ResetRecipe") as Button).pressed.emit()
	await _ui.settle()
	_check("Reset returns every value to compiler defaults", workshop.get_recipe() == Compiler.defaults())

	# A read-only comparison must not offer a destructive reset or hide existing edits.
	workshop.set_recipe({"control_multiplier": 1.2})
	workshop.call("_set_page", "compare")
	var compared_recipe: Dictionary = workshop.get_recipe()
	workshop.call("_reset_recipe")
	_check("Compare cannot reset flight setup", workshop.get_recipe() == compared_recipe
		and not (_find(workshop, "ResetRecipe") as Button).is_visible_in_tree())
	_check("Compare reports control travel changes", _comparison_text(workshop).contains("Control travel multiplier"))
	workshop.set_recipe({"control_multiplier": 1.2, "control_multiplier_aileron": 1.3}, false)
	_check("Compare reports explicit and inherited surface travel without null defaults",
		_comparison_text(workshop).contains("Aileron travel multiplier")
		and _comparison_text(workshop).contains("Elevator travel multiplier")
		and _comparison_text(workshop).contains("1.30×")
		and _comparison_text(workshop).contains("1.20×"))
	workshop.set_aircraft(Catalog.DEFAULT_ID, true)
	var presentation: Dictionary = Presentation.defaults(workshop.get("_presentation_bindings"))
	presentation.lighting.selection = "disabled"
	workshop.set_presentation(presentation)
	_check("Compare reports a lighting-only edit", _comparison_text(workshop).contains("Lighting")
		and not _comparison_text(workshop).contains("No changes from the original."))
	workshop.set_aircraft(Catalog.DEFAULT_ID, true)
	presentation = Presentation.defaults(workshop.get("_presentation_bindings"))
	presentation.mechanical_audio.servo_level = 0.5
	workshop.set_presentation(presentation)
	_check("Compare reports an audio-only edit", _comparison_text(workshop).contains("Servo sound level")
		and _comparison_text(workshop).contains("50%")
		and not _comparison_text(workshop).contains("No changes from the original."))
	workshop.call("_set_page", "setup")
	await _ui.settle()
	var setup_tab: Button = _find(workshop, "PageSetup")
	_check("selected Workshop page keeps its green marker while hovered", setup_tab.button_pressed
		and setup_tab.get_theme_stylebox("pressed").border_color == UiTheme.FOCUS
		and setup_tab.get_theme_stylebox("hover_pressed").border_color == UiTheme.FOCUS)
	setup_tab.grab_focus()
	await _ui.tap(KEY_TAB)
	_check("Tab from the active page reaches its first setting", _ui.focus_name() == "StartingPreset", _ui.focus_name())
	var history: Control = _find(workshop, "WorkshopHistory")
	var scroll: ScrollContainer = workshop.get("_body_scroll")
	scroll.scroll_vertical = 10000
	await _ui.settle()
	_check("history remains reachable after scrolling", history.is_visible_in_tree()
		and Rect2(Vector2.ZERO, Vector2(root.size)).encloses(history.get_global_rect()))
	workshop.set_aircraft(Catalog.DEFAULT_ID, true)

	# History belongs to this source and handles a slider drag as one edit.
	workshop.set_aircraft(Catalog.DEFAULT_ID, true)
	var undo_button := _find(workshop, "UndoRecipe") as Button
	var redo_button := _find(workshop, "RedoRecipe") as Button
	workshop.set_recipe({"scale": 0.5})
	workshop.set_recipe({"scale": 2.0})
	undo_button.pressed.emit()
	_check("first Undo restores the preceding edit", workshop.get_recipe().scale == 0.5)
	undo_button.pressed.emit()
	_check("second Undo restores the original", workshop.get_recipe() == Compiler.defaults() and undo_button.disabled)
	redo_button.pressed.emit()
	redo_button.pressed.emit()
	_check("Redo restores both edits", workshop.get_recipe().scale == 2.0 and redo_button.disabled)
	undo_button.pressed.emit()
	workshop.set_recipe({"scale": 1.5})
	_check("new edit clears the redo branch", redo_button.disabled)
	workshop.set_aircraft(Catalog.DEFAULT_ID, true)
	var power_slider: HSlider = workshop.get("_factor_sliders")["power_multiplier"]
	power_slider.drag_started.emit()
	power_slider.value = 1.15
	power_slider.value = 1.2
	power_slider.drag_ended.emit(true)
	_check("slider drag contributes one history entry", workshop.get("_undo_history").size() == 1)
	undo_button.pressed.emit()
	_check("undoing a slider drag restores its starting value", workshop.get_recipe().power_multiplier == 1.0)
	power_slider.drag_started.emit()
	power_slider.drag_ended.emit(false)
	_check("a drag without changes preserves redo", not redo_button.disabled and undo_button.disabled)
	for edit_index: int in 40:
		workshop.set_recipe({"scale": 0.5 if edit_index % 2 == 0 else 2.0})
	_check("history is bounded", workshop.get("_undo_history").size() == Workshop.HISTORY_LIMIT)
	workshop.set_aircraft(Catalog.DEFAULT_ID, true)
	_check("changing source clears both history branches", undo_button.disabled and redo_button.disabled)

	# The whole storage flow stays under a per-run user:// directory.
	var source_bytes: PackedByteArray = FileAccess.get_file_as_bytes(Catalog.entry(Catalog.DEFAULT_ID).data)
	workshop.set_variant_name("Workshop UI check")
	workshop.save_named_variant()
	await _ui.settle()
	var variants: Array = Store.list_variants(store_root)
	_check("Save creates one local revision", variants.size() == 1 and int(variants[0].get("revision", 0)) == 1)
	var saved_id := str(variants[0].get("id", "")) if not variants.is_empty() else ""
	workshop.set_recipe({"scale": 2.0}, false)
	workshop.save_named_variant()
	await _ui.settle()
	variants = Store.list_variants(store_root)
	_check("Save updates the same variant as revision two", variants.size() == 1
		and str(variants[0].get("id", "")) == saved_id and int(variants[0].get("revision", 0)) == 2)
	if not variants.is_empty():
		var saved: Dictionary = variants[0]
		_check("saved provenance pins exact source, compiler and dependencies",
			saved.get("base_bytes", PackedByteArray()) == source_bytes
			and str(saved.get("compiler_version", "")) != ""
			and saved.get("dependencies", {}) is Dictionary and not saved.get("dependencies", {}).is_empty())

	var emitted_payloads: Array[Dictionary] = []
	workshop.trial_requested.connect(func(payload: Dictionary) -> void: emitted_payloads.append(payload))
	(_find(workshop, "TestFly") as Button).pressed.emit()
	await _ui.settle()
	var payload: Dictionary = emitted_payloads[0] if not emitted_payloads.is_empty() else {}
	_check("Test Fly emits the exact pinned snapshot and variant revision",
		payload.get("base_bytes", PackedByteArray()) == source_bytes
		and str(payload.get("variant_id", "")) == saved_id
		and int(payload.get("variant_revision", 0)) == 2
		and str(payload.get("compiler_version", "")) == str(variants[0].get("compiler_version", ""))
		and payload.get("dependencies", {}) == variants[0].get("dependencies", {}))
	workshop.set_note("")

	workshop.set_recipe({"scale": 0.5}, false)
	(_find(workshop, "LoadVariant") as Button).pressed.emit()
	_discard_pending(workshop)
	await _ui.settle()
	_check("Load restores the saved recipe and original source bytes",
		is_equal_approx(float(workshop.get_recipe().scale), 2.0)
		and workshop.get("_base_bytes") == source_bytes
		and int(workshop.get("_saved_variant_revision")) == 2)
	_check("loading a saved variant clears unrelated undo state", undo_button.disabled and redo_button.disabled)
	(_find(workshop, "DeleteVariant") as Button).pressed.emit()
	await _ui.settle()
	workshop.get("_delete_dialog").confirmed.emit()
	await _ui.settle()
	_check("Delete removes the saved variant and disables its actions", Store.list_variants(store_root).is_empty()
		and (_find(workshop, "LoadVariant") as Button).disabled
		and (_find(workshop, "DeleteVariant") as Button).disabled)
	_check("deleting the current variant leaves an unsaved draft", str(workshop.get("_saved_variant_id")).is_empty()
		and int(workshop.get("_saved_variant_revision")) == 0)
	(_find(workshop, "RestoreVariant") as Button).pressed.emit()
	await _ui.settle()
	var restored: Dictionary = Store.load_variant(saved_id, store_root)
	_check("Undo delete restores the original revision", restored.get("ok", false)
		and restored.get("variant", {}).get("revision", 0) == 2)
	workshop.save_named_variant()
	await _ui.settle()
	_check("saving the retained draft creates a separate variant", Store.list_variants(store_root).size() == 2
		and str(workshop.get("_saved_variant_id")) != saved_id)

	# A second writer cannot be silently overwritten by this older editor draft.
	var current_id: String = workshop.get("_saved_variant_id")
	var current_revision: int = workshop.get("_saved_variant_revision")
	var concurrent_recipe: Dictionary = Compiler.defaults()
	concurrent_recipe.power_multiplier = 1.3
	var concurrent: Dictionary = Store.save_variant("Another editor", Catalog.DEFAULT_ID, source_bytes,
		concurrent_recipe, current_id, store_root, workshop.get("_workshop_descriptor"),
		workshop.get("_variant_dependencies"), current_revision)
	_check("concurrent save fixture advances the revision", concurrent.get("ok", false))
	workshop.set_recipe({"power_multiplier": 0.9})
	workshop.save_named_variant()
	var after_conflict: Dictionary = Store.load_variant(current_id, store_root)
	_check("stale editor save preserves the newer revision and current draft", after_conflict.get("ok", false)
		and after_conflict.variant.recipe.power_multiplier == 1.3
		and workshop.get_recipe().power_multiplier == 0.9
		and int(workshop.get("_saved_variant_revision")) == current_revision)
	workshop.save_variant_copy()
	_check("conflicting draft can be saved as its own copy", str(workshop.get("_saved_variant_id")) != current_id)
	workshop.set_recipe({"scale": 1.33, "weight_multiplier": 0.731})
	workshop.save_named_variant()
	var exact_recipe: Dictionary = workshop.get_recipe()
	workshop.set_recipe({"scale": 0.5})
	(_find(workshop, "LoadVariant") as Button).pressed.emit()
	_discard_pending(workshop)
	_check("precise saved recipe round-trips without quantization", workshop.get_recipe() == exact_recipe)

	# A removed catalog entry remains a readable library item, but cannot corrupt the open draft.
	var removed_base: Dictionary = JSON.parse_string(source_bytes.get_string_from_utf8())
	removed_base.id = "removed-catalog-fixture"
	var removed_bytes: PackedByteArray = JSON.stringify(removed_base, "", true, true).to_utf8_buffer()
	var removed_descriptor: Dictionary = Descriptor.load_for(Catalog.DEFAULT_ID, source_bytes).descriptor.duplicate(true)
	removed_descriptor.base_id = removed_base.id
	removed_descriptor.base_sha256 = removed_bytes.get_string_from_utf8().sha256_text()
	var removed: Dictionary = Store.save_variant("Unavailable airplane", removed_base.id, removed_bytes,
		Compiler.defaults(), "", store_root, removed_descriptor)
	_check("removed catalog fixture is stored independently", removed.get("ok", false), str(removed.get("errors", [])))
	if removed.get("ok", false):
		var old_base_id: String = workshop.get("_base_id")
		var old_saved_id: String = workshop.get("_saved_variant_id")
		var old_bytes: PackedByteArray = workshop.get("_base_bytes")
		workshop.set("_selected_variant_id", removed.variant.id)
		(_find(workshop, "LoadVariant") as Button).pressed.emit()
		_discard_pending(workshop)
		_check("unavailable source load preserves the entire current draft", workshop.get("_base_id") == old_base_id
			and workshop.get("_base_bytes") == old_bytes and workshop.get_recipe() == exact_recipe
			and workshop.get("_saved_variant_id") == old_saved_id)
	var recovering_id: String = workshop.get("_saved_variant_id")
	var manifest_path := store_root.path_join(recovering_id).path_join("manifest.json")
	var broken_manifest := FileAccess.open(manifest_path, FileAccess.WRITE)
	broken_manifest.store_string("{")
	broken_manifest.close()
	broken_manifest = null
	workshop.set("_selected_variant_id", recovering_id)
	(_find(workshop, "LoadVariant") as Button).pressed.emit()
	_discard_pending(workshop)
	_check("backup recovery visibly identifies the earlier revision", int(workshop.get("_saved_variant_revision")) == 1
		and str(workshop.get("_status_label").text).contains("from backup"))
	workshop.save_named_variant()
	_check("saving a recovered draft advances past existing immutable revisions", int(workshop.get("_saved_variant_revision")) == 3
		and not Store.load_variant(recovering_id, store_root).variant.recovered_from_manifest_backup,
		"revision=%s note=%s" % [workshop.get("_saved_variant_revision"), workshop.get("_status_label").text])

	# The store accepts historical recipes with duplicate cosmetic metadata.
	var metadata_recipe: Dictionary = Compiler.defaults()
	metadata_recipe["id"] = "12345678-1234-4234-8234-123456789abc"
	metadata_recipe["name"] = "Historical recipe metadata"
	var metadata_saved: Dictionary = Store.save_variant(metadata_recipe.name, Catalog.DEFAULT_ID,
		source_bytes, metadata_recipe, metadata_recipe.id, store_root)
	_check("historical metadata fixture saves", metadata_saved.get("ok", false), str(metadata_saved.get("errors", [])))
	if metadata_saved.get("ok", false):
		workshop.set("_selected_variant_id", metadata_recipe.id)
		workshop.call("_load_selected_variant")
		_discard_pending(workshop)
		_check("loaded draft separates recipe physics from record metadata",
			not workshop.get_recipe().has("id") and not workshop.get_recipe().has("name"))
		workshop.set_variant_name("Renamed historical build")
		workshop.save_named_variant()
		var renamed_metadata: Dictionary = Store.load_variant(metadata_recipe.id, store_root)
		_check("historical recipe can be renamed", renamed_metadata.get("ok", false)
			and renamed_metadata.variant.name == "Renamed historical build"
			and renamed_metadata.variant.revision == 2)
		workshop.save_variant_copy()
		_check("historical recipe copy receives a separate identity",
			workshop.get("_saved_variant_id") != metadata_recipe.id
			and workshop.get("_saved_variant_revision") == 1)
		_check("copy leaves the source history untouched",
			Store.load_variant(metadata_recipe.id, store_root).variant.revision == 2)

	# Loading a pre-surface recipe keeps its keys absent while showing effective values.
	var legacy_root := store_root + "_legacy"
	workshop.set_aircraft(Catalog.DEFAULT_ID, true)
	var legacy_recipe: Dictionary = Compiler.defaults()
	legacy_recipe.control_multiplier = 1.27
	var legacy_source: PackedByteArray = FileAccess.get_file_as_bytes(Catalog.entry(Catalog.DEFAULT_ID).data)
	var legacy_saved: Dictionary = Store.save_variant(
		"Legacy control recipe", Catalog.DEFAULT_ID, legacy_source, legacy_recipe, "", legacy_root,
		workshop.get("_workshop_descriptor"), workshop.get("_variant_dependencies"), -1,
		workshop.get("_presentation")
	)
	_check("legacy recipe fixture saves without surface overrides", legacy_saved.get("ok", false)
		and not legacy_saved.get("variant", {}).get("recipe", {}).has("control_multiplier_aileron"))
	if legacy_saved.get("ok", false):
		workshop.variants_root = legacy_root
		workshop.call("_load_variant_snapshot", str(legacy_saved.variant.id))
		await _ui.settle()
		var loaded_legacy: Dictionary = workshop.get_recipe()
		var legacy_sliders_match := true
		for surface_key: String in surface_keys:
			var surface_slider: HSlider = surface_sliders[surface_key]
			legacy_sliders_match = legacy_sliders_match \
				and not loaded_legacy.has(surface_key) \
				and is_equal_approx(surface_slider.value, 1.27)
		_check("loading a legacy saved recipe shows its inherited surface values", legacy_sliders_match)
	workshop.variants_root = store_root
	workshop.set_aircraft(Catalog.DEFAULT_ID, true)
	await _ui.settle()

	await _guarded_journey(workshop, store_root)
	workshop.queue_free()
	await _ui.settle()
	var absolute_root := ProjectSettings.globalize_path(store_root)
	if DirAccess.dir_exists_absolute(absolute_root):
		_remove_fixture(absolute_root, absolute_root)
	var absolute_legacy_root := ProjectSettings.globalize_path(legacy_root)
	if DirAccess.dir_exists_absolute(absolute_legacy_root):
		_remove_fixture(absolute_legacy_root, absolute_legacy_root)
	TranslationServer.set_locale("en")
	print("Workshop UI: %d failed" % _failures)
	quit(1 if _failures else 0)


func _remove_fixture(path: String, fixture_root: String) -> void:
	assert(path == fixture_root or path.begins_with(fixture_root + "/"))
	var directory := DirAccess.open(path)
	if directory == null:
		return
	for child: String in directory.get_files():
		DirAccess.remove_absolute(path.path_join(child))
	for child: String in directory.get_directories():
		_remove_fixture(path.path_join(child), fixture_root)
	directory = null
	DirAccess.remove_absolute(path)


func _discard_pending(editor: Node) -> void:
	var dialog: ConfirmationDialog = editor.get("_guard_dialog")
	if dialog != null: dialog.custom_action.emit("discard")


func _guarded_journey(editor: Node, store_root: String) -> void:
	editor.set_aircraft(Catalog.DEFAULT_ID, true)
	_check("new source begins with a clean full-payload baseline", not editor.has_unsaved_changes())
	editor.set_recipe({power_multiplier = 1.2})
	var draft: Dictionary = editor.get_recipe()
	var history_size: int = editor.get("_undo_history").size()
	var result := {continued = 0, cancelled = 0}
	var proceed := func() -> void: result.continued += 1
	var cancel := func() -> void: result.cancelled += 1
	editor.request_navigation("Back to Home", proceed, cancel)
	var guard: ConfirmationDialog = editor.get("_guard_dialog")
	_check("dirty transition opens an exclusive safe-default decision", guard != null and guard.visible
		and guard.exclusive and guard.get_cancel_button().has_focus())
	guard.canceled.emit()
	_check("Cancel preserves draft, source and undo history", result.continued == 0 and result.cancelled == 1
		and editor.get_recipe() == draft and editor.get("_undo_history").size() == history_size
		and editor.has_unsaved_changes())
	editor.call("_undo")
	_check("undo to complete baseline clears changed state", not editor.has_unsaved_changes())
	editor.call("_set_page", "compare")
	editor.get("_preview").set_view_mode("compare")
	_check("page and camera comparison do not change build identity", not editor.has_unsaved_changes())
	editor.call("_set_page", "setup")
	var previous_descriptor: Dictionary = editor.get("_workshop_descriptor").duplicate(true)
	editor.set("_workshop_descriptor", {test_identity = "different pin"})
	_check("persisted descriptor identity participates in dirty state", editor.has_unsaved_changes())
	editor.set("_workshop_descriptor", previous_descriptor)
	var previous_id: String = editor.get("_base_id")
	editor.set("_base_id", "same-values-other-source")
	_check("equal physical defaults cannot mask a changed source identity", editor.has_unsaved_changes())
	editor.set("_base_id", previous_id)
	_check("restored full baseline is clean", not editor.has_unsaved_changes())

	# Stock browsing is observational; only explicit Open can replace a build.
	editor.set_recipe({power_multiplier = 1.1})
	editor.call("_open_library")
	var selector: OptionButton = editor.get("_base_selector")
	var other := 1 if selector.item_count > 1 else 0
	selector.select(other)
	selector.item_selected.emit(other)
	_check("stock browsing keeps active source and draft", editor.get("_base_id") == previous_id
		and editor.get_recipe().power_multiplier == 1.1)
	(_find(editor, "OpenStockAircraft") as Button).pressed.emit()
	guard = editor.get("_guard_dialog")
	_check("opening another source is guarded before replacement", guard != null and editor.get("_base_id") == previous_id)
	guard.canceled.emit()
	_check("cancelled source replacement retains the outgoing draft", editor.get("_base_id") == previous_id
		and editor.get_recipe().power_multiplier == 1.1)
	_check("cancelled source replacement returns to its library candidate", editor.get("_library_dialog").visible
		and selector.selected == other)
	editor.call("_close_library")

	# Invalid typed values are never silently clamped, saved or launched.
	editor.call("_show_name_dialog", false)
	var naming: ConfirmationDialog = editor.get("_name_dialog")
	naming.confirmed.emit()
	_check("blank save name stays in its dialog with a correction", naming.visible
		and not str(editor.get("_name_error").text).is_empty())
	naming.hide()
	naming.canceled.emit()

	var entry: LineEdit = editor.get("_factor_inputs")["weight_multiplier"]
	entry.text = "not a number"
	entry.text_changed.emit(entry.text)
	var saved_count := Store.list_variants(store_root).size()
	_check("invalid numeric input blocks Save and Test fly", editor.save_button.disabled
		and (_find(editor, "TestFly") as Button).disabled and editor.has_unsaved_changes())
	editor.save_named_variant()
	_check("programmatic Save also refuses invalid displayed input", Store.list_variants(store_root).size() == saved_count)
	editor.request_navigation("Back to Home", proceed, cancel)
	guard = editor.get("_guard_dialog")
	_check("invalid draft offers discard/cancel but not false save", guard != null and guard.get_ok_button().disabled)
	guard.canceled.emit()
	_check("Cancel keeps invalid input visible for correction", entry.text == "not a number")
	var power_entry: LineEdit = editor.get("_factor_inputs")["power_multiplier"]
	editor.set("compile_count", 0)
	power_entry.text = "1.237"
	power_entry.text_changed.emit(power_entry.text)
	power_entry.text_submitted.emit(power_entry.text)
	_check("committing another number preserves invalid text and blocking state", entry.text == "not a number"
		and editor.get("_invalid_fields").has("weight_multiplier") and editor.save_button.disabled
		and is_equal_approx(editor.get_recipe().power_multiplier, 1.237)
		and is_equal_approx(editor.get("_factor_sliders").power_multiplier.value, 1.237))
	_check("changed numeric commit compiles exactly once", int(editor.get("compile_count")) == 1,
		"compiler calls=%d" % int(editor.get("compile_count")))
	var history_before_noop: int = editor.get("_undo_history").size()
	editor.set("compile_count", 0)
	power_entry.text = "1.2370"
	power_entry.text_changed.emit(power_entry.text)
	power_entry.text_submitted.emit(power_entry.text)
	_check("normalized numeric no-op clears only its pending buffer without compilation",
		int(editor.get("compile_count")) == 0
		and editor.get("_undo_history").size() == history_before_noop
		and not editor.get("_pending_numbers").has("power_multiplier")
		and editor.get("_pending_numbers").has("weight_multiplier")
		and is_equal_approx(editor.get_recipe().power_multiplier, 1.237)
		and editor.save_button.disabled and (_find(editor, "TestFly") as Button).disabled,
		"compiler calls=%d history=%d/%d pending=%s invalid=%s" % [
			int(editor.get("compile_count")), int(editor.get("_undo_history").size()), history_before_noop,
			editor.get("_pending_numbers"), editor.get("_invalid_fields")])
	editor.set("compile_count", 0)
	power_entry.text = "1.237001"
	power_entry.text_changed.emit(power_entry.text)
	power_entry.text_submitted.emit(power_entry.text)
	_check("nearby distinct numeric value commits exactly once instead of being discarded",
		editor.get_recipe().power_multiplier == 1.237001
		and int(editor.get("compile_count")) == 1
		and editor.get("_undo_history").size() == history_before_noop + 1
		and not editor.get("_pending_numbers").has("power_multiplier")
		and editor.get("_pending_numbers").has("weight_multiplier")
		and editor.save_button.disabled,
		"value=%.9f compiler calls=%d" % [editor.get_recipe().power_multiplier, int(editor.get("compile_count"))])
	editor.call("_review_issues")
	_check("Review issues focuses the invalid input on its page", entry.has_focus()
		and editor.get("_active_page") == "setup")
	entry.text = "0.731"
	entry.text_changed.emit(entry.text)
	entry.text_submitted.emit(entry.text)
	_check("numeric entry commits an exact intermediate value", is_equal_approx(editor.get_recipe().weight_multiplier, 0.731)
		and not editor.save_button.disabled)

	# Re-entering the master value must retain its established override-reset semantics.
	var surface_entry: LineEdit = editor.get("_factor_inputs")["control_multiplier_aileron"]
	surface_entry.text = "1.3"
	surface_entry.text_changed.emit(surface_entry.text)
	surface_entry.text_submitted.emit(surface_entry.text)
	var master_entry: LineEdit = editor.get("_factor_inputs")["control_multiplier"]
	editor.set("compile_count", 0)
	master_entry.text = "1.0000"
	master_entry.text_changed.emit(master_entry.text)
	master_entry.text_submitted.emit(master_entry.text)
	_check("re-entering master value still clears individual overrides with one compilation",
		not editor.get_recipe().has("control_multiplier_aileron") and int(editor.get("compile_count")) == 1)
	editor.set("compile_count", 0)
	surface_entry.text = "1.000001"
	surface_entry.text_changed.emit(surface_entry.text)
	surface_entry.text_submitted.emit(surface_entry.text)
	_check("inherited value normalization refreshes readiness without compilation",
		int(editor.get("compile_count")) == 0 and editor.get("_pending_numbers").is_empty()
		and surface_entry.text == String.num(1.0, 4)
		and not editor.save_button.disabled and not (_find(editor, "TestFly") as Button).disabled)

	# Save and continue is explicit, single-shot and marks exactly the saved payload clean.
	editor.request_navigation("Back to Home", proceed, cancel)
	guard = editor.get("_guard_dialog")
	editor.get("_guard_name").text = "Guarded build"
	guard.confirmed.emit()
	_check("successful Save completes the captured navigation once", result.continued == 1
		and not editor.has_unsaved_changes() and editor.get("_guard_dialog") == null)
	var saved_id: String = editor.get("_saved_variant_id")
	var saved_revision: int = editor.get("_saved_variant_revision")
	var saved_record: Dictionary = Store.load_variant(saved_id, store_root).variant
	var advanced := Store.save_variant("Concurrent save", saved_record.base_id, saved_record.base_bytes,
		saved_record.recipe, saved_id, store_root, saved_record.workshop_descriptor, saved_record.dependencies,
		saved_revision)
	_check("save-failure fixture advances the expected revision", advanced.ok)
	editor.set_recipe({power_multiplier = 1.3})
	editor.request_navigation("Back to Home", proceed, cancel)
	guard = editor.get("_guard_dialog")
	guard.confirmed.emit()
	_check("failed save leaves pending decision and full draft", result.continued == 1 and guard.visible
		and editor.get_recipe().power_multiplier == 1.3 and editor.has_unsaved_changes())
	guard.canceled.emit()

	# A confirmation freezes UUID/revision independently of later library highlights.
	editor.call("_open_library")
	editor.set("_selected_variant_id", saved_id)
	editor.call("_confirm_delete_selected")
	var source_bytes: PackedByteArray = editor.get("_base_bytes")
	var other_saved: Dictionary = Store.save_variant("Another build", Catalog.DEFAULT_ID, source_bytes,
		Compiler.defaults(), "", store_root)
	editor.set("_selected_variant_id", other_saved.variant.id)
	editor.get("_delete_dialog").confirmed.emit()
	_check("changed library selection cannot redirect delete", not Store.load_variant(saved_id, store_root).ok
		and Store.load_variant(other_saved.variant.id, store_root).ok)
	editor.call("_restore_last_deleted")
	_check("exact generation restore recovers captured build", Store.load_variant(saved_id, store_root).ok)
	editor.set("_selected_variant_id", saved_id)
	editor.call("_confirm_delete_selected")
	var record: Dictionary = Store.load_variant(saved_id, store_root).variant
	var concurrent := Store.save_variant("Advanced build", record.base_id, record.base_bytes, record.recipe,
		saved_id, store_root, record.workshop_descriptor, record.dependencies, int(record.revision))
	editor.get("_delete_dialog").confirmed.emit()
	_check("stale confirmation refuses a newer revision", concurrent.ok and Store.load_variant(saved_id, store_root).ok
		and Store.load_variant(saved_id, store_root).variant.revision == saved_revision + 2)
	editor.call("_close_library")
	await _ui.settle()


func _comparison_text(editor: Node) -> String:
	var text := ""
	for cell: Node in editor.get("_comparison_grid").get_children():
		if cell is Label: text += cell.text + "\n"
	return text
