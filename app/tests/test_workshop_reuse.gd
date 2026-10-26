extends SceneTree
const Workshop := preload("res://ui/workshop.gd")
const Store := preload("res://workshop/store.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Customization := preload("res://render/aircraft_customization.gd")
const LightingProfile := preload("res://render/lighting/lighting_profile.gd")
const Presentation := preload("res://workshop/presentation.gd")
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(label: String, condition: bool) -> void:
	print(("ok   " if condition else "FAIL ") + label)
	if not condition: failures += 1
func select_build(editor: Node, id: String) -> void:
	var selector: OptionButton = editor.get("_variant_selector")
	for index in selector.item_count:
		if str(selector.get_item_metadata(index)) == id:
			selector.select(index)
			editor.call("_on_variant_selected", index)
			return
func run() -> void:
	var editor := Workshop.new()
	editor.variants_root = "user://test_workshop_reuse_%d" % Time.get_ticks_usec()
	root.add_child(editor)
	await process_frame
	var bindings: Dictionary = Customization.describe(Catalog.DEFAULT_ID).bindings
	var profile: Dictionary = Presentation.defaults(bindings)
	profile.paint = [{"slot": bindings.paint_slots[0].id, "color": "#327DE8FF", "pattern": "solid", "accent": "none"}]
	profile.markings = [{"slot": bindings.marking_slots[0].id, "text": "ÁVION-12", "color": "#FFFFFFFF"}]
	editor.set_presentation(profile)
	editor.get("_page_nodes").smoke.call("apply_preset", 2)
	profile = editor.get_presentation()
	var source_id := ""
	for slot: Dictionary in bindings.smoke_slots:
		if slot.kind == "source": source_id = slot.id
	var source_entry: Dictionary = profile.smoke[0].duplicate(true)
	source_entry.slot = source_id
	profile.smoke.append(source_entry)
	profile.lighting = LightingProfile.preset("festival")
	editor.set_presentation(profile)
	profile = editor.get_presentation()
	editor.set_variant_name("Reusable blue airshow")
	editor.save_named_variant()
	var id: String = editor.get("_saved_variant_id")
	check("reusable source saves once", not id.is_empty())
	if id.is_empty(): editor.free(); quit(1); return
	var source_revision: int = editor.get("_saved_variant_revision")
	editor.set_aircraft("gp-extra-300s-60", true)
	editor.set_recipe({control_multiplier = 1.1})
	var target_before: Dictionary = editor.get_presentation()
	var recipe_before: Dictionary = editor.get_recipe()
	var history_size: int = editor.get("_undo_history").size()
	editor.call("_open_library")
	select_build(editor, id)
	var view_before: Dictionary = editor.get("_preview").get_view_state()
	var thumbnail_identity: Dictionary = editor.get("_thumbnail_identity").duplicate(true)
	await process_frame
	await process_frame
	check("headless thumbnail failure leaves library actions and active preview intact", editor.get("_thumbnail_note").visible and not editor.get("_load_button").disabled and editor.get("_preview").get_view_state() == view_before and not editor.get("_thumbnail").active_resources().viewport)
	var pixels := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	pixels.fill(Color.CORNFLOWER_BLUE)
	editor.get("_thumbnail").get("_cache").put_image(str(thumbnail_identity.get("sha256", "")), pixels)
	editor.call("_close_library")
	editor.call("_open_library")
	await process_frame
	await process_frame
	check("library displays a copied cached image without changing draft or camera", editor.get("_thumbnail_image").visible and editor.get("_thumbnail_image").texture is ImageTexture and editor.get_recipe() == recipe_before and editor.get("_preview").get_view_state() == view_before)
	editor.call("_toggle_favorite")
	check("favorite preserves selected build and draft history", editor.get("_selected_variant_id") == id and id in editor.get("_favorites") and editor.get("_undo_history").size() == history_size and editor.get_recipe() == recipe_before)
	editor.get("_favorites_only").button_pressed = true
	check("favorites filter keeps the chosen source", editor.get("_variant_selector").item_count == 2)
	var search: LineEdit = editor.get("_build_search")
	search.text = "no such aircraft"
	search.text_changed.emit(search.text)
	check("search hides unmatched records without replacing the draft", editor.get("_variant_selector").item_count == 1 and editor.get_presentation() == target_before and editor.get_recipe() == recipe_before)
	editor.call("_receive_thumbnail", thumbnail_identity, ImageTexture.create_from_image(pixels))
	check("late thumbnail cannot display after its selection disappears", not editor.get("_thumbnail_image").visible and editor.get("_thumbnail_image").texture == null)
	search.text = "blue"
	search.text_changed.emit(search.text)
	check("search matches saved name", editor.get("_variant_selector").item_count == 2)
	select_build(editor, id)
	for query: String in ["airshow reusable", "reusble blue", "reusable blu"]:
		search.text = query
		search.text_changed.emit(query)
		check("approximate search preserves favorite selection and draft: " + query, editor.get("_selected_variant_id") == id and editor.get("_variant_selector").item_count == 2 and editor.get_recipe() == recipe_before)
	editor.call("_review_profile_transfer")
	var dialog: ConfirmationDialog = editor.get("_transfer_dialog")
	var description: String = editor.get("_transfer_text").text
	check("copy previews accepted and skipped domains before mutation", dialog.visible and description.contains("Settings to apply") and description.contains("Settings skipped") and description.contains("Engine exhaust") and description.contains("Lighting / RGB profile") and description.contains("stock appearance profile") and editor.get_presentation() == target_before)
	check("Cancel is the initial review focus", dialog.gui_get_focus_owner() == dialog.get_cancel_button())
	editor.call("dismiss_modal_for_exit")
	check("closing copy review preserves draft and library", not dialog.visible and editor.get("_library_dialog").visible and editor.get_presentation() == target_before)
	editor.call("_review_profile_transfer")
	editor.call("_apply_profile_transfer")
	var copied: Dictionary = editor.get_presentation()
	check("copy accepts registration and preserves paint with a different material contract", copied.paint == target_before.paint and copied.markings == profile.markings)
	check("cross-aircraft copy preserves the complete semantic lighting profile", copied.lighting == profile.lighting)
	check("copy confirmation describes the full presentation transfer", editor.get("_status_label").text.contains("Compatible presentation settings copied"))
	check("source exhaust absent on Extra is skipped explicitly", copied.smoke.size() == 2 and not copied.smoke.any(func(entry: Dictionary) -> bool: return entry.slot == source_id))
	check("copy preserves physical recipe and counts as one Undo edit", editor.get_recipe() == recipe_before and editor.get("_undo_history").size() == history_size + 1)
	editor.call("_undo")
	check("Undo restores entire pre-copy presentation", editor.get_presentation() == target_before and editor.get_recipe() == recipe_before)
	editor.call("_redo")
	check("Redo reapplies exact reviewed settings", editor.get_presentation() == copied)
	editor.call("_open_library")
	select_build(editor, id)
	editor.call("_review_profile_transfer")
	var changed := copied.duplicate(true)
	changed.markings = []
	editor.set_presentation(changed)
	editor.call("_apply_profile_transfer")
	check("stale review cannot overwrite a later presentation edit", editor.get_presentation() == changed and editor.get("_status_label").text.contains("draft changed"))
	var source_after := Store.load_variant(id, editor.variants_root)
	check("source revision and content remain unchanged", source_after.ok and source_after.variant.revision == source_revision and source_after.variant.presentation_profile == profile)
	editor.call("_close_library")
	var second := Workshop.new()
	second.variants_root = editor.variants_root
	root.add_child(second)
	await process_frame
	check("favorite survives a fresh editor instance", id in second.get("_favorites"))
	second.free()
	search.text = ""
	search.text_changed.emit(search.text)
	Store.delete_variant(id, editor.variants_root, source_revision)
	editor.call("_refresh_variants")
	select_build(editor, id)
	check("missing favorite remains removable without allowing a load or profile copy", editor.get("_selected_variant_id") == id and editor.get("_load_button").disabled and editor.get("_copy_profile_button").disabled and not editor.get("_favorite_button").disabled)
	editor.call("_toggle_favorite")
	check("removing unavailable favorite releases its bounded metadata slot", id not in editor.get("_favorites") and editor.get("_variant_selector").item_count == 1)
	editor.free()
	await process_frame
	print("Workshop reuse UI: %d failures" % failures)
	quit(1 if failures else 0)
