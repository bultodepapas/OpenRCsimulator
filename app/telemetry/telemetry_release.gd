## TELEM-02: whether this build may offer telemetry, and where it would send. Only an approved release export
## carries res://telemetry_release.json (written by addons/build_info when export.sh is given the operator's
## endpoint, name and contact); every other build answers {ok = false}. A development/debug run can instead name a
## loopback receiver for qualification (OPENRC_TELEMETRY_QUALIFICATION_URL); release templates ignore it.
extends RefCounted

const BuildInfo := preload("res://app_state/build_info.gd")
const Contract := preload("res://telemetry/telemetry_contract.gd")

const PATH := "res://telemetry_release.json"
const FORMAT := "openrc-telemetry-release v1"
const QUALIFICATION_URL_ENV := "OPENRC_TELEMETRY_QUALIFICATION_URL"
const QUALIFICATION_RELEASE_ENV := "OPENRC_TELEMETRY_QUALIFICATION_RELEASE"
const MAX_TEXT := 200


## {ok, reason, endpoint, operator, contact, release_id, channel, notice, qualification}. `ok` false names why.
static func current(path := PATH) -> Dictionary:
	if OS.is_debug_build() and not OS.has_feature("template_release"):
		var url := OS.get_environment(QUALIFICATION_URL_ENV)
		if url != "":
			return qualification(url, OS.get_environment(QUALIFICATION_RELEASE_ENV))
	return from_export(BuildInfo.current(), _read(path), OS.has_feature("template_release") and not OS.is_debug_build(),
		_engine_minor())


## Pure decision for an exported build: identity from build_info, configuration from the packed file.
static func from_export(build: Dictionary, packed: Variant, release_template: bool, engine_minor: String) -> Dictionary:
	if not Contract.same_text(build.get("source"), "export"):
		return _refuse("development")
	if not release_template:
		return _refuse("debug_template")
	if engine_minor != Contract.ENGINE_MINOR:
		return _refuse("engine")
	var parsed: Variant = build.get("parsed")
	if not Contract.is_false(build.get("dirty")) or not parsed is Dictionary or not Contract.is_false(parsed.get("dirty")) \
			or typeof(parsed.get("after")) != TYPE_INT or int(parsed.get("after")) != 0:
		return _refuse("unreleased")
	var tag := str(parsed.get("tag", ""))
	if not Contract.valid_release(tag):
		return _refuse("unreleased")
	if not packed is Dictionary or not Contract.same_text(packed.get("format"), FORMAT):
		return _refuse("not_configured")
	var endpoint := str(packed.get("endpoint", ""))
	var operator := str(packed.get("operator", ""))
	var contact := str(packed.get("contact", ""))
	if not valid_endpoint(endpoint, false) or not _text_ok(operator) or not _text_ok(contact):
		return _refuse("not_configured")
	return {"ok": true, "reason": "release", "endpoint": endpoint, "operator": operator, "contact": contact,
		"release_id": tag, "channel": "preview" if str(parsed.get("prerelease", "")) != "" else "stable",
		"notice": Contract.NOTICE_VERSION, "qualification": false}


## Development/debug qualification against a local receiver only; never a production origin.
static func qualification(url: String, release_id: String) -> Dictionary:
	if not valid_endpoint(url, true):
		return _refuse("qualification_url")
	var tag := release_id if release_id != "" else "v0.0.0"
	if not Contract.valid_release(tag):
		return _refuse("qualification_release")
	return {"ok": true, "reason": "qualification", "endpoint": url, "operator": "Local qualification receiver",
		"contact": "-", "release_id": tag, "channel": "preview", "notice": Contract.NOTICE_VERSION,
		"qualification": true}


## One fixed origin and path: https (or loopback http for qualification), no credentials, query or fragment.
static func valid_endpoint(url: String, loopback_only: bool) -> bool:
	if url.length() > 512 or url.strip_edges() != url or url.contains(" "):
		return false
	var scheme := "http://" if loopback_only else "https://"
	if not url.begins_with(scheme) or url.contains("?") or url.contains("#") or url.contains("@") or url.contains("\\"):
		return false
	var rest := url.trim_prefix(scheme)
	var host_port := rest.get_slice("/", 0)
	var host := host_port.get_slice(":", 0) if not host_port.begins_with("[") else host_port.get_slice("]", 0) + "]"
	if host == "" or not rest.contains("/"):
		return false
	if loopback_only:
		return host in ["127.0.0.1", "localhost", "[::1]"]
	return host not in ["127.0.0.1", "localhost", "[::1]"]


static func _read(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


static func _engine_minor() -> String:
	var version := Engine.get_version_info()
	return "%d.%d" % [int(version.get("major", 0)), int(version.get("minor", 0))]


static func _text_ok(text: String) -> bool:
	return text.strip_edges() != "" and text.length() <= MAX_TEXT and not text.contains("\n")


static func _refuse(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
