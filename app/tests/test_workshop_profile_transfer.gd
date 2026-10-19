extends SceneTree
## AE-24d.1: previewable compatible-only copy across independently pinned families.

const Transfer := preload("res://workshop/profile_transfer.gd")
const Presentation := preload("res://workshop/presentation.gd")
const Trial := preload("res://workshop/trial.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Customization := preload("res://render/aircraft_customization.gd")

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_test_cross_family_preview()
	_test_empty_and_unavailable_copy()
	_test_refusals_and_legacy_marking()
	_test_trial_identity_is_physical()
	print("Workshop profile transfer: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures else 0)


func _test_cross_family_preview() -> void:
	var source_bindings: Dictionary = _bindings_fixture("source-family", "a", true)
	var target_bindings: Dictionary = _bindings_fixture("target-family", "b", false)
	var source_profile: Dictionary = _source_profile(source_bindings)
	var target_profile: Dictionary = _target_profile(target_bindings)
	var source_before: Dictionary = source_profile.duplicate(true)
	var target_before: Dictionary = target_profile.duplicate(true)
	var source_bindings_before: Dictionary = source_bindings.duplicate(true)
	var target_bindings_before: Dictionary = target_bindings.duplicate(true)
	var preview: Dictionary = Transfer.propose(source_profile, source_bindings, target_profile, target_bindings)
	_check("copy preview validates profiles from different model families", preview.get("ok", false), str(preview.get("errors", [])))
	if not bool(preview.get("ok", false)):
		return
	_check("compatible-only preview reports each applied domain slot",
		preview.applied.size() == 4
		and _has_row(preview.applied, "paint", "body", "compatible")
		and _has_row(preview.applied, "markings", "unit_code", "compatible")
		and _has_row(preview.applied, "smoke", "smoke_left", "compatible")
		and _has_row(preview.applied, "smoke", "smoke_source", "compatible"), str(preview.applied))
	_check("incompatible or missing slots receive explicit skip reasons",
		preview.skipped.size() == 6
		and _has_row(preview.skipped, "paint", "glass", "paint_kind_mismatch")
		and _has_row(preview.skipped, "paint", "tip", "target_slot_missing")
		and _has_row(preview.skipped, "markings", "registration", "marking_text_too_long")
		and _has_row(preview.skipped, "markings", "serial", "target_slot_missing")
		and _has_row(preview.skipped, "smoke", "smoke_tail", "smoke_endpoint_mismatch")
		and _has_row(preview.skipped, "smoke", "smoke_missing", "target_slot_missing"), str(preview.skipped))
	var proposed: Dictionary = preview.profile
	_check("copied paint and accent replace only their compatible target slot",
		_entry(proposed.paint, "body").get("color", "") == "#DD2200FF"
		and _entry(proposed.paint, "body").get("accent", "") == "#22DD00FF"
		and _entry(proposed.paint, "glass").get("color", "") == "#334455FF"
		and _entry(proposed.paint, "wing").get("color", "") == "#ABCDEF".to_upper() + "FF")
	_check("copied marking and smoke entries preserve target-only selections",
		_entry(proposed.markings, "unit_code").get("text", "") == "SOURCE-7"
		and _entry(proposed.markings, "tail_code").get("text", "") == "TAIL"
		and _entry(proposed.smoke, "smoke_left").get("color", "") == "#FF1100FF"
		and _entry(proposed.smoke, "smoke_extra").get("color", "") == "#202020FF")
	_check("target seed and binding pins remain untouched by profile copy",
		int(proposed.visual_seed) == int(target_profile.visual_seed)
		and proposed.binding == Presentation.defaults(target_bindings).binding
		and proposed.binding.visual_family != source_profile.binding.visual_family)
	_check("proposal does not mutate either profile or binding input",
		source_profile == source_before and target_profile == target_before
		and source_bindings == source_bindings_before and target_bindings == target_bindings_before)


func _test_empty_and_unavailable_copy() -> void:
	var source_bindings: Dictionary = _bindings_fixture("source-family", "a", true)
	var target_bindings: Dictionary = _bindings_fixture("empty-family", "c", false, true)
	var source_profile: Dictionary = _source_profile(source_bindings)
	var target_profile: Dictionary = Presentation.defaults(target_bindings)
	var empty_source: Dictionary = Presentation.defaults(source_bindings)
	var empty_copy: Dictionary = Transfer.propose(empty_source, source_bindings, target_profile, target_bindings)
	_check("empty source profile succeeds without deleting target extras",
		empty_copy.get("ok", false) and empty_copy.applied.is_empty() and empty_copy.skipped.is_empty()
		and empty_copy.profile == target_profile)
	var unavailable: Dictionary = Transfer.propose(source_profile, source_bindings,
		Presentation.defaults(target_bindings), target_bindings)
	_check("all-unavailable copy is a successful unchanged preview with a skip per source selection",
		unavailable.get("ok", false) and unavailable.applied.is_empty()
		and unavailable.skipped.size() == 10
		and unavailable.profile == Presentation.defaults(target_bindings))


func _test_refusals_and_legacy_marking() -> void:
	var source_bindings: Dictionary = _bindings_fixture("source-family", "a", true)
	var target_bindings: Dictionary = _bindings_fixture("target-family", "b", false)
	var source_profile: Dictionary = _source_profile(source_bindings)
	var target_profile: Dictionary = _target_profile(target_bindings)
	var malformed: Dictionary = source_profile.duplicate(true)
	malformed["unknown"] = true
	_check("unknown profile fields reject before any proposal", not Transfer.propose(
		malformed, source_bindings, target_profile, target_bindings).get("ok", false))
	var stale_profile: Dictionary = source_profile.duplicate(true)
	stale_profile.binding.slots_sha256 = "0".repeat(64)
	_check("stale source profile pins reject without rebinding", not Transfer.propose(
		stale_profile, source_bindings, target_profile, target_bindings).get("ok", false))
	var stale_bindings: Dictionary = target_bindings.duplicate(true)
	stale_bindings.slots_sha256 = "0".repeat(64)
	_check("stale target sidecar digest rejects before proposing", not Transfer.propose(
		source_profile, source_bindings, target_profile, stale_bindings).get("ok", false))
	_check("non-object bindings reject explicitly", not Transfer.propose(
		source_profile, [], target_profile, target_bindings).get("ok", false))

	var legacy_target: Dictionary = _bindings_fixture("legacy-target", "d", false)
	legacy_target["version"] = Presentation.LEGACY_BINDINGS_VERSION
	legacy_target.erase("presentation_sources")
	legacy_target.erase("presentation_engine_version")
	legacy_target["paint_slots"] = []
	legacy_target["smoke_slots"] = []
	legacy_target["marking_slots"] = [
		{"id": "unit_code", "label": "Unit code", "max_chars": 12, "targets": [_marking_target()]},
	]
	legacy_target["slots_sha256"] = Presentation.bindings_sha256(legacy_target)
	var legacy_profile: Dictionary = Presentation.defaults(legacy_target)
	var legacy_preview: Dictionary = Transfer.propose(source_profile, source_bindings, legacy_profile, legacy_target)
	_check("marking copy skips when target glyph engine/source proof is unpinned",
		legacy_preview.get("ok", false)
		and _has_row(legacy_preview.skipped, "markings", "unit_code", "marking_glyph_support_unpinned"),
		str(legacy_preview.get("errors", [])))


func _test_trial_identity_is_physical() -> void:
	var base_id: String = Catalog.DEFAULT_ID
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(Catalog.entry(base_id).data)
	var described: Dictionary = Customization.describe(base_id)
	_check("current default aircraft exposes presentation bindings", described.get("ok", false), str(described.get("errors", [])))
	if not bool(described.get("ok", false)):
		return
	var bindings: Dictionary = described.bindings
	var source_profile: Dictionary = Presentation.defaults(bindings)
	var paint_slots: Array = bindings.get("paint_slots", [])
	if not paint_slots.is_empty():
		source_profile.paint = [{"slot": str(paint_slots[0].id), "color": "#3167B2FF",
			"pattern": "solid", "accent": "none"}]
	else:
		source_profile.visual_seed = 17
	var target_profile: Dictionary = Presentation.defaults(bindings)
	var preview: Dictionary = Transfer.propose(source_profile, bindings, target_profile, bindings)
	_check("same-aircraft profile copy previews a valid proposal", preview.get("ok", false), str(preview.get("errors", [])))
	if not bool(preview.get("ok", false)):
		return
	var before: Dictionary = Trial.freeze({"base_id": base_id, "base_bytes": bytes,
		"recipe": {}, "presentation_profile": target_profile})
	var after: Dictionary = Trial.freeze({"base_id": base_id, "base_bytes": bytes,
		"recipe": {}, "presentation_profile": preview.profile})
	_check("appearance transfer leaves Trial physical identity and resolved build byte-equivalent",
		before.get("ok", false) and after.get("ok", false)
		and before.identity == after.identity and before.raw_bytes == after.raw_bytes
		and before.data == after.data, str(after.get("errors", [])))
	if not paint_slots.is_empty():
		_check("a copied appearance changes separate presentation identity only",
			preview.applied.size() == 1
			and after.presentation_identity.sha256 != before.presentation_identity.sha256)


func _source_profile(bindings: Dictionary) -> Dictionary:
	var profile: Dictionary = Presentation.defaults(bindings)
	profile.visual_seed = 7
	profile.paint = [
		{"slot": "body", "color": "#DD2200FF", "pattern": "solid", "accent": "#22DD00FF"},
		{"slot": "glass", "color": "#AABBCCFF", "pattern": "solid", "accent": "none"},
		{"slot": "tip", "color": "#778899FF", "pattern": "solid", "accent": "none"},
	]
	profile.markings = [
		{"slot": "registration", "text": "NIÑO-5", "color": "#123456FF"},
		{"slot": "unit_code", "text": "SOURCE-7", "color": "#234567FF"},
		{"slot": "serial", "text": "X-99", "color": "#345678FF"},
	]
	profile.smoke = [
		_smoke_entry("smoke_left", "#FF1100FF"),
		_smoke_entry("smoke_tail", "#00FF11FF"),
		_smoke_entry("smoke_source", "#0011FFFF"),
		_smoke_entry("smoke_missing", "#AA11FFFF"),
	]
	return profile


func _target_profile(bindings: Dictionary) -> Dictionary:
	var profile: Dictionary = Presentation.defaults(bindings)
	profile.visual_seed = 99
	profile.paint = [
		{"slot": "body", "color": "#111111FF", "pattern": "solid", "accent": "none"},
		{"slot": "glass", "color": "#334455FF", "pattern": "solid", "accent": "none"},
		{"slot": "wing", "color": "#ABCDEF", "pattern": "solid", "accent": "none"},
	]
	profile.markings = [
		{"slot": "unit_code", "text": "OLD-1", "color": "#111111FF"},
		{"slot": "tail_code", "text": "TAIL", "color": "#112233FF"},
	]
	profile.smoke = [
		_smoke_entry("smoke_left", "#101010FF"),
		_smoke_entry("smoke_extra", "#202020FF"),
	]
	return profile


func _bindings_fixture(family: String, manifest_digit: String, source_side: bool,
		empty: bool = false) -> Dictionary:
	var bindings: Dictionary = {
		"format": Presentation.BINDINGS_FORMAT,
		"version": Presentation.BINDINGS_VERSION,
		"visual_family": family,
		"model_manifest_sha256": manifest_digit.repeat(64),
		"paint_slots": [],
		"marking_slots": [],
		"smoke_slots": [],
		"presentation_sources": [],
		"presentation_engine_version": Presentation.PRESENTATION_ENGINE_VERSION,
		"slots_sha256": "",
	}
	for path: String in Presentation.PRESENTATION_SOURCE_PATHS:
		bindings.presentation_sources.append({"path": path, "sha256": "e".repeat(64)})
	if not empty:
		if source_side:
			bindings.paint_slots = [
				_paint_slot("body", "standard_albedo", true),
				_paint_slot("glass", "shader_color", false),
				_paint_slot("tip", "standard_albedo", false),
			]
			bindings.marking_slots = [
				_marking_slot("registration", 12), _marking_slot("unit_code", 12), _marking_slot("serial", 12),
			]
			bindings.smoke_slots = [
				_show_slot("smoke_left", "wing_tip_left"),
				_show_slot("smoke_tail", "tail"),
				_source_slot("smoke_source"),
				_show_slot("smoke_missing", "tail"),
			]
		else:
			bindings.paint_slots = [
				_paint_slot("body", "standard_albedo", true),
				_paint_slot("glass", "standard_albedo", false),
				_paint_slot("wing", "standard_albedo", false),
			]
			bindings.marking_slots = [
				_marking_slot("registration", 4), _marking_slot("unit_code", 12), _marking_slot("tail_code", 12),
			]
			bindings.smoke_slots = [
				_show_slot("smoke_left", "wing_tip_left"),
				_show_slot("smoke_tail", "wing_tip_right"),
				_source_slot("smoke_source"),
				_show_slot("smoke_extra", "wing_tip_right"),
			]
	bindings["slots_sha256"] = Presentation.bindings_sha256(bindings)
	return bindings


func _paint_slot(id: String, kind: String, accent: bool) -> Dictionary:
	var target: Dictionary = {"node_path": "airplane/%s" % id, "surface": 0, "kind": kind}
	if kind == "shader_color":
		target["parameter"] = "surface_color"
	var slot: Dictionary = {"id": id, "label": id.capitalize(), "targets": [target]}
	if accent:
		slot["accent_targets"] = [{"node_path": "airplane/%s_accent" % id,
			"surface": 0, "kind": "standard_albedo"}]
	return slot


func _marking_slot(id: String, max_chars: int) -> Dictionary:
	return {"id": id, "label": id.capitalize(), "max_chars": max_chars, "targets": [_marking_target()]}


func _marking_target() -> Dictionary:
	return {"node_path": "airplane/label_mount", "position_m": [0.0, 0.0, 0.0],
		"direction": [0.0, 0.0, -1.0], "up": [0.0, 1.0, 0.0], "width_m": 1.0, "height_m": 0.2}


func _show_slot(id: String, role: String) -> Dictionary:
	return {"id": id, "label": id.capitalize(), "kind": "show", "pair": "", "role": role,
		"node_path": "airplane/%s" % id, "position_m": [0.0, 0.0, 0.0], "direction": [0.0, 0.0, -1.0]}


func _source_slot(id: String) -> Dictionary:
	return {"id": id, "label": "Exhaust", "kind": "source", "pair": "", "role": "exhaust",
		"source_kind": "glow_prop", "source_anchor_ref": "engine_main", "physical_source_ref": "engine_main",
		"physical_source_kind_ref": "propulsion"}


func _smoke_entry(slot: String, color: String) -> Dictionary:
	return {"slot": slot, "enabled": true, "color": color, "amount": 0.75, "width_m": 0.5,
		"lifetime_s": 6.0, "shape": "ribbon", "mode": "hold", "burst_s": 0.0,
		"pulse_period_s": 0.0, "pulse_duty": 0.0, "palette": [], "step_s": 0.0}


func _has_row(rows: Array, domain: String, slot: String, reason: String) -> bool:
	for row_value: Variant in rows:
		if typeof(row_value) == TYPE_DICTIONARY:
			var row: Dictionary = row_value
			if row.get("domain", "") == domain and row.get("slot", "") == slot \
					and row.get("reason", "") == reason and row.size() == 3:
				return true
	return false


func _entry(entries: Array, slot: String) -> Dictionary:
	for entry_value: Variant in entries:
		if typeof(entry_value) == TYPE_DICTIONARY and str(entry_value.get("slot", "")) == slot:
			return entry_value
	return {}


func _check(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL ", label, " ", detail)
