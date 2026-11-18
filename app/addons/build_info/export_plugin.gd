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
	_add_telemetry_release()


## TELEM-02: the receiving service's HTTPS endpoint, operator name and contact let an approved release offer
## telemetry (telemetry/telemetry_release.gd decides at run time). Without all three nothing is packed and the build
## never offers it; a partial or invalid set is reported and also packs nothing.
func _add_telemetry_release() -> void:
	var endpoint := OS.get_environment("OPENRC_TELEMETRY_ENDPOINT").strip_edges()
	var operator := OS.get_environment("OPENRC_TELEMETRY_OPERATOR").strip_edges()
	var contact := OS.get_environment("OPENRC_TELEMETRY_CONTACT").strip_edges()
	if endpoint == "" and operator == "" and contact == "":
		return
	if endpoint == "" or operator == "" or contact == "" or not endpoint.begins_with("https://") \
			or endpoint.contains("?") or endpoint.contains("#") or endpoint.contains("@"):
		push_error("telemetry: OPENRC_TELEMETRY_ENDPOINT (https, no query), _OPERATOR and _CONTACT must all be set; this build will not offer telemetry")
		return
	var release := {format = "openrc-telemetry-release v1", endpoint = endpoint, operator = operator, contact = contact}
	add_file("res://telemetry_release.json", (JSON.stringify(release, "  ") + "\n").to_utf8_buffer(), false)
