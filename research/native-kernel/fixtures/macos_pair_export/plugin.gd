## Focused export-preset controls for an isolated checked editor project.
## Enable only in the disposable project; this is not an export.
@tool
extends EditorPlugin

const Plugin := preload("res://addons/native_kernel/export_plugin.gd")
const PAIR_FORMAT := "openrc-macos-engine-pair-binding v1"
const SCOPE := "source-editor-local-custom-engine-research-v1"

class FakePreset extends RefCounted:
	var template := ""
	var architecture := "arm64"
	func _get(property: StringName) -> Variant:
		if property == &"custom_template/release": return template
		if property == &"binary_format/architecture": return architecture
		return null

var checks := 0
var failures := 0


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + message)


func _enter_tree() -> void:
	_wait_for_editor.call_deferred()


func _wait_for_editor() -> void:
	var filesystem := EditorInterface.get_resource_filesystem()
	var base := EditorInterface.get_base_control()
	if not is_instance_valid(filesystem) or not is_instance_valid(base):
		check(false, "editor filesystem or interface unavailable")
		_finish()
		return
	# EditorFileSystem reports the first scan as scanning until its thread and
	# import work have been joined. Let queued startup work settle as well.
	var ready_frames := 0
	while ready_frames < 2:
		await get_tree().process_frame
		if not filesystem.is_scanning() and not filesystem.is_importing() \
				and filesystem.get_filesystem() != null and base.is_node_ready():
			ready_frames += 1
		else:
			ready_frames = 0
	_run_checks()


func _run_checks() -> void:
	var path := "user://openrc-pair-plugin-test-%d.zip" % Time.get_ticks_usec()
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		check(false, "cannot create disposable template")
		_finish()
		return
	file.store_string("template A")
	file.close()
	var editor_sha := FileAccess.get_sha256(OS.get_executable_path())
	var template_sha := FileAccess.get_sha256(path)
	var a := "a".repeat(64)
	var b := "b".repeat(64)
	var plugin := Plugin.new()
	var preset := FakePreset.new()
	preset.template = path
	plugin._mac_export_preset = preset
	plugin._mac_template_path = path
	var pair := {"format": PAIR_FORMAT, "editor_sha256": editor_sha, "template_sha256": a,
		"editor_receipt_sha256": a, "template_receipt_sha256": a, "pair_receipt_sha256": a,
		"export_template_sha256": template_sha, "source_archive_sha256": a,
		"source_catalog_sha256": b, "patch_sha256": [a, b]}
	var provenance := {"scope": SCOPE, "runtime_version": "fixture", "build_receipt_sha256": a,
		"source_archive_sha256": a, "source_catalog_sha256": b,
		"ordered_patches": [{"sha256": a}, {"sha256": b}]}
	var row := {"engine_version": "fixture", "engine_sha256": editor_sha,
		"engine": {"sha256": editor_sha, "research_engine": provenance}}
	plugin._mac_manifest = {"engine_pair": pair,
		"export_plugin_sha256": FileAccess.get_sha256("res://addons/native_kernel/export_plugin.gd")}
	check(plugin._mac_pair_matches_with_preset(row, preset), "matching editor, preset and template")
	preset.architecture = "universal"
	check(not plugin._mac_pair_matches_with_preset(row, preset), "wrong architecture")
	preset.architecture = "arm64"
	var different := FakePreset.new()
	different.template = path
	check(not plugin._mac_pair_matches_with_preset(row, different), "different active preset")
	preset.template = path + ".other"
	check(not plugin._mac_pair_matches_with_preset(row, preset), "different template path")
	preset.template = path
	pair.patch_sha256 = [b, a]
	check(not plugin._mac_pair_matches_with_preset(row, preset), "reordered source patches")
	pair.patch_sha256 = [a, b]
	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string("template B")
	file.close()
	check(not plugin._mac_pair_matches_with_preset(row, preset), "template changed after initial check")
	plugin._mac_manifest = {}
	check(plugin._mac_pair_matches_with_preset({}, null), "ordinary official route")
	var remove_error := DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	check(remove_error == OK, "remove disposable fixture")
	_finish()


func _finish() -> void:
	print("MAC_PAIR_EXPORT_PLUGIN checks=%d failures=%d" % [checks, failures])
	if failures > 0: push_error("Mac pair export plugin fixture failed")
	# The editor owns and unloads this addon during its normal close. Defer the
	# notification so it cannot free this plugin while its callback is active.
	var editor_node := get_parent()
	if not is_instance_valid(editor_node):
		push_error("Mac pair export plugin has no editor owner")
		get_tree().quit(1)
		return
	editor_node.call_deferred("notification", NOTIFICATION_WM_CLOSE_REQUEST)
