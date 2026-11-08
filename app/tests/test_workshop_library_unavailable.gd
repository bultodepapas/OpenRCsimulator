extends SceneTree

const Store := preload("res://workshop/store.gd")
const Preferences := preload("res://workshop/library_preferences.gd")
const Compiler := preload("res://workshop/compiler.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Workshop := preload("res://ui/workshop.gd")

class ScannedWorkshop extends Workshop:
	var forced_scan: Dictionary = {}
	func _scan_variant_library() -> Dictionary:
		return forced_scan if not forced_scan.is_empty() else super._scan_variant_library()

var checks := 0
var failures := 0
var scratch := ""

func _initialize() -> void:
	_run.call_deferred()

func check(label: String, passed: bool, detail: String = "") -> void:
	checks += 1
	if passed: print("ok   ", label)
	else:
		failures += 1
		printerr("FAIL ", label, " ", detail)

func settle() -> void:
	for _i in 6: await process_frame

func write_bytes(path: String, bytes: PackedByteArray) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: return false
	file.store_buffer(bytes)
	file.close()
	return true

func index_for(selector: OptionButton, id: String) -> int:
	for index in range(1, selector.item_count):
		if str(selector.get_item_metadata(index)) == id: return index
	return -1

func count_for(selector: OptionButton, id: String) -> int:
	var count := 0
	for index in range(1, selector.item_count):
		if str(selector.get_item_metadata(index)) == id: count += 1
	return count

func select_id(editor: ScannedWorkshop, id: String) -> bool:
	var selector: OptionButton = editor.get("_variant_selector")
	var index := index_for(selector, id)
	if index < 0: return false
	selector.select(index)
	editor.call("_on_variant_selected", index)
	return true

func remove_fixture(path: String, fixture_root: String) -> bool:
	if path != fixture_root and not path.begins_with(fixture_root + "/"): return false
	var parent := DirAccess.open(path.get_base_dir())
	if parent == null or parent.is_link(path): return false
	var directory := DirAccess.open(path)
	if directory == null: return false
	for file: String in directory.get_files():
		var child := path.path_join(file).simplify_path()
		if not child.begins_with(fixture_root + "/") or directory.is_link(child): return false
		if DirAccess.remove_absolute(child) != OK: return false
	for name: String in directory.get_directories():
		var child := path.path_join(name).simplify_path()
		if directory.is_link(child) or not remove_fixture(child, fixture_root): return false
	return DirAccess.remove_absolute(path) == OK

func _run() -> void:
	root.size = Vector2i(1920, 1080)
	TranslationServer.set_locale("en")
	scratch = "user://audit4_f12_test_%d_%d" % [Time.get_unix_time_from_system(), Time.get_ticks_usec()]
	var library := scratch.path_join("library")
	var empty := Store.scan_variants(library)
	check("uncreated nested root is a successful empty scan", empty.ok and empty.variants.is_empty() and empty.unavailable.is_empty())
	var editor := ScannedWorkshop.new()
	editor.variants_root = library
	root.add_child(editor)
	await settle()
	editor.call("_open_library")
	await settle()
	check("genuinely empty library says no saved builds", editor.get("_library_empty").visible and editor.get("_library_empty").text.begins_with("No saved builds yet") and not editor.get("_library_scan_status").visible)
	var source := FileAccess.get_file_as_bytes(Catalog.entry(Catalog.DEFAULT_ID).data)
	var healthy := Store.save_variant("Healthy", Catalog.DEFAULT_ID, source, Compiler.defaults(), "", library)
	var broken := Store.save_variant("Damaged", Catalog.DEFAULT_ID, source, Compiler.defaults(), "", library)
	var backed := Store.save_variant("Backup candidate", Catalog.DEFAULT_ID, source, Compiler.defaults(), "", library)
	check("fixture publishes three independent saved builds", healthy.ok and broken.ok and backed.ok)
	if not healthy.ok or not broken.ok or not backed.ok:
		editor.free()
		quit(1)
		return
	var healthy_id: String = healthy.variant.id
	var broken_id: String = broken.variant.id
	var backed_id: String = backed.variant.id
	var revised := Store.save_variant("Backup candidate", Catalog.DEFAULT_ID, source, Compiler.defaults(), backed_id, library, {}, {}, 1)
	check("backup fixture publishes a second revision", revised.ok)
	if not revised.ok:
		editor.free()
		quit(1)
		return
	var broken_manifest := library.path_join(broken_id).path_join("manifest.json")
	var broken_backup := broken_manifest + ".bak"
	var backed_manifest := library.path_join(backed_id).path_join("manifest.json")
	var backed_backup := backed_manifest + ".bak"
	var original_broken := FileAccess.get_file_as_bytes(broken_manifest)
	var original_backed := FileAccess.get_file_as_bytes(backed_manifest)
	var backup_bytes := FileAccess.get_file_as_bytes(backed_backup)
	check("fixture corrupts primary and backup only in its private test root",
		write_bytes(broken_manifest, "{broken primary".to_utf8_buffer()) and write_bytes(broken_backup, "{broken backup".to_utf8_buffer())
		and write_bytes(backed_manifest, "{broken current".to_utf8_buffer()))
	var corrupt_primary := FileAccess.get_file_as_bytes(broken_manifest)
	var corrupt_backup := FileAccess.get_file_as_bytes(broken_backup)
	var corrupt_backed := FileAccess.get_file_as_bytes(backed_manifest)
	var checked := Store.scan_variants(library)
	check("mixed scan retains healthy and backup-recovered variants", checked.ok and checked.variants.size() == 2 and checked.unavailable.size() == 1 and checked.recovered.size() == 1)
	check("invalid primary and backup report the affected UUID and both failures", checked.unavailable.size() == 1 and checked.unavailable[0].id == broken_id and "; ".join(checked.unavailable[0].errors).contains("backup recovery also failed"))
	var recovered := Store.load_variant(backed_id, library)
	check("valid backup is usable but explicitly remains the earlier revision", recovered.ok and recovered.variant.revision == 1 and recovered.variant.recovered_from_manifest_backup and not recovered.errors.is_empty())
	check("legacy array view remains compatible", Store.list_variants(library).size() == 2)
	check("scan preserves damaged primary and both backup bytes", FileAccess.get_file_as_bytes(broken_manifest) == corrupt_primary and FileAccess.get_file_as_bytes(broken_backup) == corrupt_backup and FileAccess.get_file_as_bytes(backed_manifest) == corrupt_backed and FileAccess.get_file_as_bytes(backed_backup) == backup_bytes)
	var colliding_id := "11111111-1111-4111-8111-111111111111"
	var occupied_entry := library.path_join(colliding_id)
	check("fixture creates a UUID-named file", write_bytes(occupied_entry, "not a build directory".to_utf8_buffer()))
	checked = Store.scan_variants(library)
	check("UUID-named file is diagnosed as unavailable", checked.ok and checked.unavailable.size() == 2)
	editor.call("_refresh_variants")
	await settle()
	var selector: OptionButton = editor.get("_variant_selector")
	check("healthy, recovered and unreadable rows coexist", index_for(selector, healthy_id) > 0 and index_for(selector, backed_id) > 0 and index_for(selector, broken_id) > 0 and index_for(selector, colliding_id) > 0)
	check("recovered row names backup and revision", selector.get_item_text(index_for(selector, backed_id)).contains("Recovered from backup") and selector.get_item_text(index_for(selector, backed_id)).contains("revision 1"))
	check("partial failure reports count with Retry and Details", editor.get("_library_scan_status").visible and editor.get("_library_scan_status").text.contains("2 saved builds") and editor.get("_library_scan_actions").visible)
	check("healthy actions stay enabled", select_id(editor, healthy_id) and not editor.get("_load_button").disabled and not editor.get("_delete_button").disabled and not editor.get("_export_button").disabled)
	check("unreadable actions are disabled", select_id(editor, broken_id) and editor.get("_load_button").disabled and editor.get("_delete_button").disabled and editor.get("_export_button").disabled and editor.get("_copy_profile_button").disabled)
	editor.call("_load_selected_variant")
	check("unavailable programmatic load cannot close the library", editor.get("_library_dialog").visible)
	editor.get("_library_details_button").button_pressed = true
	check("Details exposes IDs and concrete read errors", editor.get("_library_scan_details").visible and editor.get("_library_scan_details").text.contains(broken_id) and editor.get("_library_scan_details").text.contains("backup recovery also failed") and editor.get("_library_scan_details").text.contains(backed_id))
	var duplicate_prefix_id := "11111111-2222-4222-8222-222222222222"
	var duplicate_path := library.path_join(duplicate_prefix_id)
	check("fixture creates a second unavailable UUID with the same prefix", write_bytes(duplicate_path, "also not a directory".to_utf8_buffer()))
	editor.call("_refresh_variants")
	var first_text: String = selector.get_item_text(index_for(selector, colliding_id))
	var second_text: String = selector.get_item_text(index_for(selector, duplicate_prefix_id))
	check("unavailable records with equal UUID prefixes remain distinguishable", first_text != second_text and first_text.contains(colliding_id) and second_text.contains(duplicate_prefix_id))
	check("complete IDs are also available in tooltip and Details", selector.get_item_tooltip(index_for(selector, duplicate_prefix_id)).contains(duplicate_prefix_id) and editor.get("_library_scan_details").text.contains(colliding_id) and editor.get("_library_scan_details").text.contains(duplicate_prefix_id))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(duplicate_path))
	editor.call("_refresh_variants")
	var missing_id := "22222222-2222-4222-8222-222222222222"
	check("favorite fixture persists unreadable and missing IDs", Preferences.set_favorite(broken_id, true, library).ok and Preferences.set_favorite(missing_id, true, library).ok)
	editor.call("_refresh_variants")
	editor.get("_favorites_only").button_pressed = true
	await settle()
	check("unreadable favorite appears once with its actual diagnosis", count_for(selector, broken_id) == 1 and selector.get_item_text(index_for(selector, broken_id)).contains("Saved build unavailable"))
	check("missing favorite remains a separate removable placeholder", count_for(selector, missing_id) == 1 and select_id(editor, missing_id) and not editor.get("_favorite_button").disabled and editor.get("_load_button").disabled)
	editor.get("_build_search").text = "no-such-build-987654321"
	editor.get("_build_search").text_changed.emit(editor.get("_build_search").text)
	check("search does not hide scan diagnostics", editor.get("_library_scan_status").visible and editor.get("_library_scan_status").text.contains("2 saved builds") and editor.get("_library_unavailable").size() == 2)
	editor.get("_build_search").text = ""
	editor.get("_build_search").text_changed.emit("")
	editor.forced_scan = {"ok": false, "variants": [], "unavailable": [], "recovered": [], "errors": PackedStringArray(["injected access denied"])}
	editor.call("_refresh_variants", true)
	check("root failure with readable favorite metadata claims no favorites missing", not editor.get("_library_scan_ok") and editor.get("_favorites").size() == 2 and selector.item_count == 1 and not editor.get("_favorites_hint").visible and not editor.get("_library_empty").visible)
	check("root failure exposes retry and concrete details", editor.get("_library_scan_status").text.contains("could not be read") and editor.get("_library_scan_details").text.contains("injected access denied") and editor.get("_library_retry_button").is_visible_in_tree())
	editor.forced_scan = {}
	editor.get("_library_retry_button").pressed.emit()
	check("Retry rescans and classifies favorites after access returns", editor.get("_library_scan_ok") and count_for(selector, broken_id) == 1 and count_for(selector, missing_id) == 1)
	check("Retry and Details do not mutate original unreadable records", FileAccess.get_file_as_bytes(broken_manifest) == corrupt_primary and FileAccess.get_file_as_bytes(broken_backup) == corrupt_backup and FileAccess.get_file_as_bytes(backed_manifest) == corrupt_backed and FileAccess.get_file_as_bytes(backed_backup) == backup_bytes)
	var denied := Store._scan_variants(library, func(_path: String) -> Variant: return null)
	check("denied-open seam reports failure for an existing root", not denied.ok and not denied.errors.is_empty())
	var blocking := scratch.path_join("ROOT_OCCUPIED")
	check("fixture creates a file in place of a root", write_bytes(blocking, "occupied".to_utf8_buffer()))
	check("root occupied by a file is a failure", not Store.scan_variants(blocking).ok)
	if OS.get_name() == "Windows":
		check("mixed-case occupied Windows root is a failure", not Store.scan_variants(scratch.path_join("root_occupied")).ok)
	check("file occupying a root ancestor is a failure", not Store.scan_variants(blocking.path_join("nested")).ok)
	editor.variants_root = blocking
	editor.call("_refresh_variants")
	check("root access failure is never presented as an empty library", not editor.get("_library_scan_ok") and editor.get("_library_scan_status").visible and not editor.get("_library_empty").visible and editor.get("_library_retry_button").visible)
	editor.variants_root = library
	editor.get("_favorites_only").button_pressed = false
	check("fixture repairs only its own primary manifests", write_bytes(broken_manifest, original_broken) and write_bytes(backed_manifest, original_backed))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(occupied_entry))
	editor.call("_retry_library_scan")
	checked = Store.scan_variants(library)
	check("Retry after external repair restores all healthy records", checked.ok and checked.variants.size() == 3 and checked.unavailable.is_empty() and checked.recovered.is_empty() and not editor.get("_library_scan_status").visible and index_for(selector, broken_id) > 0)
	check("repair did not rewrite invalid or valid backups", FileAccess.get_file_as_bytes(broken_backup) == corrupt_backup and FileAccess.get_file_as_bytes(backed_backup) == backup_bytes)
	var only_root := scratch.path_join("only_damaged")
	var only_saved := Store.save_variant("Only build", Catalog.DEFAULT_ID, source, Compiler.defaults(), "", only_root)
	check("single-damaged fixture saves a build", only_saved.ok)
	if only_saved.ok:
		var only_manifest := only_root.path_join(str(only_saved.variant.id)).path_join("manifest.json")
		check("single-damaged fixture invalidates its manifest", write_bytes(only_manifest, "{invalid".to_utf8_buffer()))
		editor.variants_root = only_root
		editor.call("_refresh_variants")
		var only_scan := Store.scan_variants(only_root)
		check("one unreadable build is not mistaken for a genuinely empty library", only_scan.ok and only_scan.variants.is_empty() and only_scan.unavailable.size() == 1 and selector.item_count == 2 and not editor.get("_library_empty").visible and editor.get("_library_scan_status").text.contains("1 saved build"))
		check("single unreadable original remains untouched", FileAccess.get_file_as_bytes(only_manifest) == "{invalid".to_utf8_buffer())
	editor.free()
	await settle()
	var fixture_root := ProjectSettings.globalize_path(scratch).replace("\\", "/").simplify_path()
	var user_root := ProjectSettings.globalize_path("user://").replace("\\", "/").trim_suffix("/").simplify_path()
	check("private fixture is removed within its verified root", fixture_root.begins_with(user_root + "/audit4_f12_test_") and remove_fixture(fixture_root, fixture_root))
	print("Workshop unavailable builds: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
