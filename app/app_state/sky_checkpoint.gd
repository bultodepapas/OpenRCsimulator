## FW-82: native visual envelope; the existing physics/solar checkpoint stays byte-exact.
extends RefCounted
const SkyConfig := preload("res://environment/sky_appearance_config.gd")
const Atmosphere := preload("res://render/atmosphere.gd")
const VisualCheckpoint := preload("res://app_state/visual_checkpoint.gd")
const FORMAT := "openrc-sky-checkpoint v1"
const FIELDS := ["format", "visual", "config", "profile", "transport", "edits", "payload_sha256"]


static func make(visual: Dictionary, config: Dictionary, transport: Dictionary, edits: Array) -> Dictionary:
	var checked: Dictionary = SkyConfig.validate(config)
	if not checked.ok or not Atmosphere.validate_cloud_transport_for(checked.config, transport):
		return {}
	var result := {format = FORMAT, visual = visual.duplicate(true), config = checked.config,
		profile = checked.profile, transport = transport.duplicate(true), edits = edits.duplicate(true)}
	result.payload_sha256 = _digest(result)
	return result if read(result).ok else {}


## Validation is side-effect free and precedes any physical restore or shader mutation.
static func read(raw: Variant) -> Dictionary:
	if not raw is Dictionary:
		return {ok = false, errors = ["sky checkpoint must be an object"]}
	if raw.get("format", "") != FORMAT:
		return {ok = true, legacy = true, visual = raw, config = SkyConfig.defaults(), transport = {}, edits = []}
	if raw.size() != FIELDS.size() or not raw.has_all(FIELDS) or not VisualCheckpoint._is_native_data(raw):
		return {ok = false, errors = ["invalid sky checkpoint schema"]}
	if not raw.visual is Dictionary or not raw.profile is Dictionary or not raw.edits is Array \
			or not raw.payload_sha256 is String or raw.payload_sha256 != _digest(raw):
		return {ok = false, errors = ["invalid sky checkpoint payload"]}
	var checked: Dictionary = SkyConfig.validate(raw.config)
	if not checked.ok or checked.profile != raw.profile:
		return {ok = false, errors = ["sky profile is invalid or differs from this catalog version"]}
	if not Atmosphere.validate_cloud_transport_for(checked.config, raw.transport):
		return {ok = false, errors = ["invalid cloud transport checkpoint"]}
	if raw.edits.size() > 4096:
		return {ok = false, errors = ["too many sky edits"]}
	var last_tick := -1
	for edit: Variant in raw.edits:
		if not edit is Dictionary or edit.size() != 3 or not edit.has_all(["tick", "config", "transport"]):
			return {ok = false, errors = ["invalid sky edit schema"]}
		if typeof(edit.tick) != TYPE_INT or edit.tick < 0 or edit.tick < last_tick \
				or not SkyConfig.validate(edit.config).ok or not Atmosphere.validate_cloud_transport_for(edit.config, edit.transport):
			return {ok = false, errors = ["invalid sky edit history"]}
		last_tick = edit.tick
	if not raw.edits.is_empty() and raw.edits.back().config != checked.config:
		return {ok = false, errors = ["sky edit history disagrees with current selection"]}
	return {ok = true, legacy = false, visual = raw.visual.duplicate(true), config = checked.config,
		transport = raw.transport.duplicate(true), edits = raw.edits.duplicate(true)}


static func _digest(value: Dictionary) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(var_to_bytes([value.visual, value.config, value.profile, value.transport, value.edits]))
	return hash.finish().hex_encode()
