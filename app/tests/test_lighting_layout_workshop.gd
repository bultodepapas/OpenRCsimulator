extends SceneTree
const Workshop := preload("res://ui/workshop.gd")
const Profile := preload("res://render/lighting/lighting_profile.gd")
const Store := preload("res://workshop/store.gd")
var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
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
	editor.free()
	await process_frame
	print("Lighting layout Workshop: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)

func check(label: String, ok: bool) -> void:
	checks += 1
	if ok: print("ok   ", label)
	else:
		failures += 1
		printerr("FAIL ", label)
