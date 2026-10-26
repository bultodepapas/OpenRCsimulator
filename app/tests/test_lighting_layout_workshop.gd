extends SceneTree
const Workshop := preload("res://ui/workshop.gd")
const Profile := preload("res://render/lighting/lighting_profile.gd")
const Store := preload("res://workshop/store.gd")
const Presentation := preload("res://workshop/presentation.gd")
const Lights := preload("res://render/world/aircraft_lights.gd")
const ShaderClock := preload("res://render/shader_clock.gd")
var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var saved_clock := ShaderClock.last_clock
	var saved_wind := ShaderClock.last_wind
	ShaderClock.register()
	ShaderClock.update(saved_clock, saved_wind)
	var editor := Workshop.new()
	editor.variants_root = "user://rgb_layout_rebind_%d" % Time.get_ticks_usec()
	root.add_child(editor)
	for frame in 5: await process_frame
	var profile: Dictionary = preload("res://workshop/presentation.gd").defaults(editor.get("_presentation_bindings"), 3)
	profile.lighting = Profile.preset("festival")
	editor.set_presentation(profile)
	check("Festival fixture is accepted", editor.get_presentation().get("lighting", {}) == profile.lighting)
	if not editor.get_presentation().has("lighting"):
		printerr(editor.get("_status_label").text)
		editor.free()
		quit(1)
		return
	editor.get("_variant_name").text = "Original RGB"
	check("original build saves", editor.call("_save_variant"))
	var original_id := str(editor.get("_saved_variant_id"))
	var original: Dictionary = Store.load_variant(original_id, editor.variants_root).variant
	var stale := editor.get_presentation()
	stale.binding.slots_sha256 = "a".repeat(64)
	editor.set("_presentation", stale.duplicate(true))
	editor.call("_resolve_presentation")
	editor.call("_refresh_issues")
	editor.call("_sync_save_button")
	check("stale build blocks save and exposes review", not editor.call("_edit_valid") and editor.get("_rebind_button").visible)
	var recipe: Dictionary = editor.get("_recipe").duplicate(true)
	editor.call("_review_appearance_update")
	check("review does not mutate profile or saved identity", editor.get_presentation() == stale and editor.get("_saved_variant_id") == original_id)
	check("window close dismisses update review first", editor.dismiss_modal_for_exit() and editor.get_presentation() == stale)
	editor.call("_review_appearance_update")
	editor.call("_apply_appearance_update")
	check("accept creates a valid unsaved copy", editor.get("_saved_variant_id") == "" and editor.call("_edit_valid"))
	check("accept preserves lighting and physical recipe", editor.get_presentation().lighting == stale.lighting and editor.get("_recipe") == recipe)
	editor.call("_undo")
	check("Undo restores old pins without permitting an overwrite", editor.get_presentation() == stale and editor.get("_saved_variant_id") == "" and not editor.call("_edit_valid"))
	editor.call("_redo")
	check("Redo restores reviewed current bindings", editor.call("_edit_valid") and editor.get_presentation().lighting == stale.lighting)
	editor.get("_variant_name").text = "Updated RGB"
	check("updated draft saves as a separate build", editor.call("_save_variant") and editor.get("_saved_variant_id") != original_id)
	var retained: Dictionary = Store.load_variant(original_id, editor.variants_root).variant
	check("saved original revision stays unchanged", retained == original)

	var unsupported := Presentation.defaults(editor.get("_presentation_bindings"), 3)
	unsupported.lighting = Profile.preset("custom")
	for zone: Dictionary in unsupported.lighting.zones:
		zone.enabled = true
	editor.set_presentation(unsupported)
	var kit: Node3D = editor._preview._lighting_rig.get_kit()
	Lights.bind_groups(kit, kit.get_meta("light_bindings"), [])
	editor._preview._configure_lighting()
	var capability_report: Dictionary = editor._preview.get_lighting_capability_report()
	var unavailable_enabled_zone := false
	for zone_report: Dictionary in capability_report.get("zones", []):
		if bool(zone_report.get("enabled", false)) and not bool(zone_report.get("available", false)):
			unavailable_enabled_zone = true
	check("custom lighting reports enabled zones without usable fittings",
		capability_report.get("state", "") == "configured" and unavailable_enabled_zone)
	editor.call("_review_appearance_update")
	check("ordinary review cannot repair a same-pin lighting capability failure",
		not editor.get("_rebind_dialog").visible and editor.get("_status_label").text.contains("already matches"))
	editor.call("_refresh_issues")
	check("stock-lighting action appears for unavailable enabled lighting",
		editor.get("_stock_lighting_button").visible and not editor.get("_stock_lighting_button").disabled)
	var lighting_panel: Control = editor._page_nodes.lighting
	var pending_hex := lighting_panel.find_child("LightingPaletteHex0", true, false) as LineEdit
	pending_hex.text = "#BAD"
	pending_hex.text_changed.emit(pending_hex.text)
	editor.call("_refresh_issues")
	check("stock action waits for pending lighting edits",
		lighting_panel.has_pending_edit() and editor.get("_stock_lighting_button").disabled)
	lighting_panel.cancel_pending_edit()
	editor.call("_refresh_issues")
	var stock_recipe: Dictionary = editor.get("_recipe").duplicate(true)
	editor.get("_stock_lighting_button").pressed.emit()
	check("stock action asks before changing the draft",
		editor.get("_rebind_dialog").visible and editor.get_presentation() == unsupported)
	check("closing the stock dialog cancels its proposal without changing the source",
		editor.dismiss_modal_for_exit() and editor.get_presentation() == unsupported
		and not editor.get("_rebind_is_stock_action"))
	editor.get("_stock_lighting_button").pressed.emit()
	var changed_draft := unsupported.duplicate(true)
	changed_draft.lighting.brightness = 0.7
	var saved_copy_id: String = editor.get("_saved_variant_id")
	editor.set_presentation(changed_draft)
	editor.call("_apply_appearance_update")
	check("a changed draft invalidates the pending stock confirmation",
		editor.get_presentation() == changed_draft and editor.get("_saved_variant_id") == saved_copy_id
		and editor.get("_rebind_proposal").is_empty())
	editor.set_presentation(unsupported)
	editor.get("_stock_lighting_button").pressed.emit()
	editor.call("_apply_appearance_update")
	check("accepted stock action creates an unsaved copy with inherited lighting",
		editor.get("_saved_variant_id") == "" and editor.get_presentation().lighting.selection == "inherit"
		and editor._preview.get_lighting_capability_report().state == "inherit")
	check("stock action preserves the physical recipe and original saved revision",
		editor.get("_recipe") == stock_recipe and Store.load_variant(original_id, editor.variants_root).variant == original)
	editor.call("_undo")
	check("Undo restores custom lighting without restoring overwrite authority",
		editor.get_presentation() == unsupported and editor.get("_saved_variant_id") == ""
		and editor.get("_recipe") == stock_recipe)
	editor.call("_redo")
	check("Redo restores stock lighting in the same unsaved physical draft",
		editor.get_presentation().lighting.selection == "inherit" and editor.get("_saved_variant_id") == ""
		and editor.get("_recipe") == stock_recipe)
	editor.get("_variant_name").text = "Stock Lighting Copy"
	check("stock-lighting draft saves with a new build identity",
		editor.call("_save_variant") and editor.get("_saved_variant_id") != original_id
		and Store.load_variant(original_id, editor.variants_root).variant == original)
	editor.free()
	await process_frame
	ShaderClock.update(saved_clock, saved_wind)
	print("Lighting layout Workshop: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)

func check(label: String, ok: bool) -> void:
	checks += 1
	if ok: print("ok   ", label)
	else:
		failures += 1
		printerr("FAIL ", label)
