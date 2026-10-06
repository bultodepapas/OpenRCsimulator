# Adds res://build_info.json to every exported pack (research 21: add_file() needs no file in the tree and no
# include_filter). The values come from export.sh, computed once, so the app, the trace header and the ZIP name
# agree. An export without them (by hand from the editor) is marked "export-manual" with a warning.
@tool
extends EditorExportPlugin

const FORMAT := "openrc-build v1"


func _get_name() -> String:
	return "build_info"


func _export_begin(_features: PackedStringArray, _is_debug: bool, _path: String, _flags: int) -> void:
	var describe := OS.get_environment("OPENRC_BUILD_DESCRIBE")
	if describe == "":
		describe = "export-manual"
		push_warning("build_info: OPENRC_BUILD_* not set (export by hand?): the build says \"export-manual\"")
	var info := {
		format = FORMAT,
		describe = describe,
		commit = OS.get_environment("OPENRC_BUILD_COMMIT"),
		dirty = OS.get_environment("OPENRC_BUILD_DIRTY") == "1",
		commit_date = OS.get_environment("OPENRC_BUILD_DATE"),
	}
	add_file("res://build_info.json", (JSON.stringify(info, "  ") + "\n").to_utf8_buffer(), false)
