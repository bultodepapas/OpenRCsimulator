extends SceneTree
## Focused AE-02a profile schema, binding, canonical identity and legacy coverage.

const Profile := preload("res://workshop/presentation.gd")
const Parameters := preload("res://workshop/parameters.gd")

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_test_authored_skin_bindings()
	var bindings: Dictionary = _bindings_fixture()
	var defaults: Dictionary = Profile.defaults(bindings)
	var checked: Dictionary = Profile.validate(defaults, bindings)
	_check("registered empty profile validates", checked.get("ok", false) and checked.get("available", false), str(checked.get("errors", [])))
	var legacy_bindings: Dictionary = _legacy_bindings_fixture()
	var legacy_companion: Dictionary = Profile.validate(Profile.defaults(legacy_bindings), legacy_bindings)
	_check("legacy v1 companion remains readable", legacy_companion.get("ok", false)
		and legacy_companion.get("available", false), str(legacy_companion.get("errors", [])))
	_check("empty profile is bound to the exact model and slots", checked.get("profile", {}).get("binding", {}) == _pins(bindings))
	_check("identity API returns validation identity", Profile.identity(defaults, bindings) == checked.get("identity_sha256", ""))
	var identity_record: Dictionary = Profile.identity_record(defaults, bindings)
	_check("presentation identity exposes stable sidecar metadata", identity_record.get("format", "") == Profile.IDENTITY_FORMAT
		and identity_record.get("sha256", "") == checked.get("identity_sha256", "")
		and identity_record.get("binding", {}) == _pins(bindings))
	var legacy: Dictionary = Profile.validate({}, bindings)
	_check("omitted legacy profile resolves to explicit bound defaults", legacy.get("ok", false)
		and legacy.get("profile", {}) == Profile.defaults(bindings, 1))
	var no_binding_legacy: Dictionary = Profile.validate({})
	_check("historical empty profile validates without a binding", no_binding_legacy.get("ok", false)
		and no_binding_legacy.get("available", false))
	_check("a pinned profile without its companion is readable but unavailable",
		Profile.validate(defaults).get("ok", false) and not Profile.validate(defaults).get("available", true))
	var changed_source: Dictionary = bindings.duplicate(true)
	changed_source.presentation_sources[0].sha256 = "b".repeat(64)
	changed_source.slots_sha256 = Profile.bindings_sha256(changed_source)
	_check("presentation source pins change the separate visual identity",
		Profile.identity(defaults, bindings) != Profile.identity(Profile.defaults(changed_source), changed_source))
	var no_binding_custom: Dictionary = Profile.validate(_paint_profile(bindings))
	_check("custom profile remains readable but unavailable without current bindings",
		no_binding_custom.get("ok", false) and not no_binding_custom.get("available", true))
	_check("unavailable custom profile cannot produce a launchable identity", Profile.identity(_paint_profile(bindings)) == "")

	var base_profile: Dictionary = _paint_profile(bindings)
	var first: Dictionary = Profile.validate(base_profile, bindings)
	_check("canonical paint profile validates", first.get("ok", false), str(first.get("errors", [])))
	if first.get("ok", false):
		_check("six-digit sRGB swatch canonicalizes with opaque alpha", first.profile.paint[0].color == "#808080FF")
		_check("Spanish registration text and opaque alpha stay canonical", first.profile.markings[0].text == "NIÑO 5"
			and first.profile.markings[0].color == "#123456FF")
		_check("identity hashes the normalized profile", Profile.identity(base_profile, bindings) == first.identity_sha256)
		var reordered: Dictionary = base_profile.duplicate(true)
		reordered.paint.reverse()
		reordered.markings.reverse()
		var equivalent: Dictionary = Profile.validate(reordered, bindings)
		_check("profile array order canonicalizes by registered slot ID", equivalent.get("ok", false)
			and equivalent.identity_sha256 == first.identity_sha256)
		var numeric: Dictionary = _smoke_profile(bindings)
		numeric.smoke[0].amount = 1
		var int_trial: Dictionary = Profile.validate(numeric, bindings)
		numeric.smoke[0].amount = 1.0
		var float_trial: Dictionary = Profile.validate(numeric, bindings)
		_check("integer and float JSON numbers have identical presentation identity",
			int_trial.get("ok", false) and float_trial.get("ok", false)
			and int_trial.identity_sha256 == float_trial.identity_sha256)
		var changed_color: Dictionary = base_profile.duplicate(true)
		changed_color.paint[0].color = "#808081"
		_check("color edit changes presentation identity only", Profile.identity(changed_color, bindings) != first.identity_sha256)
		var changed_text: Dictionary = base_profile.duplicate(true)
		changed_text.markings[0].text = "NIÑA 5"
		_check("drawn text edit changes presentation identity", Profile.identity(changed_text, bindings) != first.identity_sha256)
		var changed_seed: Dictionary = base_profile.duplicate(true)
		changed_seed.visual_seed = 17
		_check("visual seed changes presentation identity", Profile.identity(changed_seed, bindings) != first.identity_sha256)
		var changed_palette: Dictionary = _smoke_profile(bindings)
		changed_palette.smoke[0].palette = ["#FFFFFF", "#FF0000"]
		changed_palette.smoke[0].step_s = 0.5
		var palette_result: Dictionary = Profile.validate(changed_palette, bindings)
		changed_palette.smoke[0].palette = ["#FFFFFF", "#0000FF"]
		var other_palette: Dictionary = Profile.validate(changed_palette, bindings)
		_check("smoke palette edit changes presentation identity", palette_result.get("ok", false)
			and other_palette.get("ok", false) and palette_result.identity_sha256 != other_palette.identity_sha256)

	_test_bad_profiles(bindings)
	_test_stale_bindings(bindings, first.identity_sha256)
	_test_future_profile()
	_test_physical_allowlist()
	_test_v2_contract(bindings)
	_test_lighting_contract(bindings)
	print("Workshop presentation: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)


func _test_bad_profiles(bindings: Dictionary) -> void:
	var profile: Dictionary = _paint_profile(bindings)
	var bad: Dictionary = profile.duplicate(true)
	bad.unexpected = true
	_check("unknown profile keys reject", not Profile.validate(bad, bindings).get("ok", false))
	bad = profile.duplicate(true)
	bad.version = Profile.VERSION + 1
	_check("newer profile versions reject for use", not Profile.validate(bad, bindings).get("ok", false))
	bad = profile.duplicate(true)
	bad.visual_seed = true
	_check("booleans are not presentation integers", not Profile.validate(bad, bindings).get("ok", false))
	bad = profile.duplicate(true)
	bad.paint[0].slot = "unregistered_slot"
	_check("unknown registered slot rejects", not Profile.validate(bad, bindings).get("ok", false))
	bad = profile.duplicate(true)
	bad.paint[0].color = NAN
	_check("non-finite visual values reject", not Profile.validate(bad, bindings).get("ok", false))
	bad = profile.duplicate(true)
	bad.paint[0].color = "#80808080"
	var translucent_paint: Dictionary = Profile.validate(bad, bindings)
	_check("paint alpha below opaque rejects with clear error", not translucent_paint.get("ok", false)
		and str(translucent_paint.get("errors", [])).contains("opaque"))
	bad = profile.duplicate(true)
	bad.markings[0].color = "#12345600"
	var translucent_marking: Dictionary = Profile.validate(bad, bindings)
	_check("marking alpha below opaque rejects with clear error", not translucent_marking.get("ok", false)
		and str(translucent_marking.get("errors", [])).contains("opaque"))
	bad = profile.duplicate(true)
	bad.paint.append(bad.paint[0].duplicate(true))
	_check("duplicate paint selections reject", not Profile.validate(bad, bindings).get("ok", false))
	bad = profile.duplicate(true)
	bad.paint[0].extra = "not allowed"
	_check("unknown paint entry keys reject", not Profile.validate(bad, bindings).get("ok", false))
	bad = profile.duplicate(true)
	bad.markings[0].text = "Pilot!"
	_check("unsupported marking punctuation rejects", not Profile.validate(bad, bindings).get("ok", false))
	bad = profile.duplicate(true)
	bad.markings[0].text = "REGISTRATION1"
	_check("text above the authored panel character limit rejects", not Profile.validate(bad, bindings).get("ok", false))
	bad = profile.duplicate(true)
	bad.paint[0].pattern = "downloaded_texture"
	_check("unregistered paint presets reject", not Profile.validate(bad, bindings).get("ok", false))
	bad = profile.duplicate(true)
	bad.paint[0].accent = "#FF0000"
	_check("accent rejects when the registered slot has no authored accent target",
		not Profile.validate(bad, bindings).get("ok", false))
	bad = profile.duplicate(true)
	bad.paint[0].slot = "wing"
	bad.paint[0].accent = "#FF000080"
	var translucent_accent: Dictionary = Profile.validate(bad, bindings)
	_check("paint accent alpha below opaque rejects clearly", not translucent_accent.get("ok", false)
		and str(translucent_accent.get("errors", [])).contains("non-opaque"))
	bad = _smoke_profile(bindings)
	bad.smoke[0].enabled = 1
	_check("smoke enabled does not accept a numeric boolean", not Profile.validate(bad, bindings).get("ok", false))
	bad = _smoke_profile(bindings)
	bad.smoke[0].color = "#FFFFFF80"
	_check("smoke retains supported translucent sRGB swatches", Profile.validate(bad, bindings).get("ok", false))
	bad = _smoke_profile(bindings)
	bad.smoke[0].mode = "script"
	_check("unknown smoke schedule mode rejects", not Profile.validate(bad, bindings).get("ok", false))
	bad = _smoke_profile(bindings)
	bad.smoke[0].mode = "burst"
	bad.smoke[0].burst_s = 1.0
	bad.smoke[0].pulse_period_s = 0.2
	_check("conflicting smoke sequence writers reject", not Profile.validate(bad, bindings).get("ok", false))
	bad = _smoke_profile(bindings)
	bad.smoke[0].lifetime_s = 8.01
	_check("smoke lifetime above 8 seconds rejects", not Profile.validate(bad, bindings).get("ok", false))
	bad = _smoke_profile(bindings)
	bad.smoke[0].slot = "source_exhaust"
	var source_result: Dictionary = Profile.validate(bad, bindings)
	_check("registered source endpoint can carry a source-gated profile", source_result.get("ok", false), str(source_result.get("errors", [])))
	var combined: Dictionary = Profile.defaults(bindings)
	combined.smoke = [_smoke_entry("smoke_left"), _smoke_entry("smoke_right"),
		_smoke_entry("smoke_center"), _smoke_entry("source_exhaust")]
	var combined_result: Dictionary = Profile.validate(combined, bindings)
	_check("three show profiles plus one source profile fit the four-slot contract",
		combined_result.get("ok", false), str(combined_result.get("errors", [])))
	bad = profile.duplicate(true)
	var deep: Variant = {"leaf": true}
	for index: int in range(16):
		deep = {"nested": deep}
	bad["unrecognized"] = deep
	_check("excessively deep profile trees reject before schema use", not Profile.validate(bad, bindings).get("ok", false))
	bad = profile.duplicate(true)
	bad.binding.model_manifest_sha256 = "f".repeat(64)
	_check("stale model manifest profile pins reject", not Profile.validate(bad, bindings).get("ok", false))


func _test_stale_bindings(bindings: Dictionary, expected_identity: String) -> void:
	var changed_model: Dictionary = bindings.duplicate(true)
	changed_model.model_manifest_sha256 = "f".repeat(64)
	changed_model.slots_sha256 = Profile.bindings_sha256(changed_model)
	var stale_model: Dictionary = Profile.validate(_paint_profile(bindings), changed_model)
	_check("changed model manifest cannot rebind a saved profile", not stale_model.get("ok", false))
	var changed_slots: Dictionary = bindings.duplicate(true)
	changed_slots.paint_slots[0].targets[0].surface = 9
	changed_slots.slots_sha256 = Profile.bindings_sha256(changed_slots)
	var stale_slots: Dictionary = Profile.validate(_paint_profile(bindings), changed_slots)
	_check("changed authored slot contract cannot rebind a saved profile", not stale_slots.get("ok", false))
	var uncorrected: Dictionary = bindings.duplicate(true)
	uncorrected.paint_slots[0].targets[0].surface = 9
	_check("tampered sidecar fails its self hash", not Profile.validate(_paint_profile(bindings), uncorrected).get("ok", false))
	var unknown_source: Dictionary = bindings.duplicate(true)
	unknown_source.presentation_sources[0].path = "res://render/unknown.gd"
	unknown_source.slots_sha256 = Profile.bindings_sha256(unknown_source)
	_check("unknown presentation source pin rejects even with a recomputed sidecar hash",
		not Profile.validate(_paint_profile(bindings), unknown_source).get("ok", false))
	_check("stale binding checks do not change baseline identity", Profile.identity(_paint_profile(bindings), bindings) == expected_identity)


func _test_future_profile() -> void:
	var future: Dictionary = Profile.defaults()
	future.version = Profile.VERSION + 1
	future["future_preset"] = {"name": "future"}
	var stored: Dictionary = Profile.validate_stored(future)
	_check("bounded future profile remains readable as unavailable", stored.get("ok", false)
		and not stored.get("available", true) and stored.get("newer_version", false))
	_check("runtime validator refuses future profile versions", not Profile.validate(future).get("ok", false))


func _test_physical_allowlist() -> void:
	var recipe: Dictionary = {"scale": 1.0, "paint": [{"slot": "body", "color": "#ffffff"}]}
	var result: Dictionary = Parameters.validate(recipe)
	_check("physical recipe compiler rejects visual keys", not result.get("ok", false))


func _test_lighting_contract(bindings: Dictionary) -> void:
	var legacy := Profile.defaults(bindings, 2)
	var original := Profile.validate(legacy, bindings)
	_check("v2 remains lighting-free and canonical", original.get("ok", false)
		and not original.profile.has("lighting") and original.profile == legacy)
	var modern := Profile.defaults(bindings, 3)
	_check("v3 defaults explicitly inherit existing aircraft lights", modern.version == 3
		and modern.lighting.selection == "inherit")
	modern.lighting = Profile.LightingProfile.preset("neon_rgb")
	var selected := Profile.validate(modern, bindings)
	_check("v3 preset is part of the bound presentation identity", selected.get("ok", false)
		and selected.identity_sha256 != original.identity_sha256, str(selected.get("errors", [])))
	var changed := modern.duplicate(true)
	changed.lighting.brightness = 0.37
	_check("lighting brightness changes visual identity", Profile.identity(changed, bindings) != Profile.identity(modern, bindings))
	changed.lighting.brightness = true
	_check("invalid nested lighting cannot enter a variant", not Profile.validate(changed, bindings).get("ok", false))
	changed = modern.duplicate(true)
	changed.erase("lighting")
	_check("v3 refuses missing lighting rather than guessing", not Profile.validate(changed, bindings).get("ok", false))
	changed = modern.duplicate(true)
	changed.version = 2
	_check("v2 refuses injected lighting fields", not Profile.validate(changed, bindings).get("ok", false))
	changed = modern.duplicate(true)
	changed.binding = Profile.defaults().binding
	_check("custom lighting requires model pins", not Profile.validate(changed).get("ok", false))


func _test_v2_contract(bindings: Dictionary) -> void:
	_check("unbound v1 identity matches the frozen pre-migration identity",
		Profile.identity(Profile.defaults({}, 1)) == "06325450205d3117ada6ea76030c6e0fc1a200bdeeed565a0b54a58b2333f1d1")
	var legacy := Profile.defaults(bindings, 1)
	legacy.smoke = [_smoke_entry("smoke_left")]
	var snapshot := JSON.stringify(legacy)
	var checked := Profile.validate(legacy, bindings)
	_check("v1 reader retains schema and bytes", checked.get("ok", false) and checked.profile.version == 1
		and not checked.profile.smoke[0].has("density") and JSON.stringify(legacy) == snapshot)
	var modern := legacy.duplicate(true)
	modern.version = 2
	modern.smoke[0]["palette_mode"] = "smooth"
	modern.smoke[0]["density"] = 1.7
	modern.smoke[0]["emission_rate_hz"] = 137.0
	var result := Profile.validate(modern, bindings)
	_check("v2 density rate and smooth palette are independent", result.get("ok", false)
		and result.profile.smoke[0].density == 1.7 and result.profile.smoke[0].emission_rate_hz == 137.0
		and result.profile.smoke[0].palette_mode == "smooth", str(result.get("errors", [])))
	_check("v2 defaults normalize finite SI controls", result.get("ok", false)
		and result.profile.smoke[0].drag_s == 0.4 and result.profile.smoke[0].velocity_inheritance == 1.0)
	for key: String in Profile.SMOKE_V2_BOUNDS:
		var bad := modern.duplicate(true)
		bad.smoke[0][key] = true
		_check("v2 rejects boolean " + key, not Profile.validate(bad, bindings).get("ok", false))
		bad.smoke[0][key] = float(Profile.SMOKE_V2_BOUNDS[key][1]) + 0.01
		_check("v2 enforces upper bound " + key, not Profile.validate(bad, bindings).get("ok", false))
	var migrated := Profile.migrate_v1(legacy, bindings, bindings)
	_check("v1 migration creates a review proposal without mutating source", migrated.get("ok", false)
		and migrated.profile.version == 2 and migrated.report.requires_review and JSON.stringify(legacy) == snapshot)
	legacy.smoke[0]["density"] = 1.0
	_check("v1 reader rejects v2 fields", not Profile.validate(legacy, bindings).get("ok", false))
	var stale := bindings.duplicate(true)
	stale.model_manifest_sha256 = "b".repeat(64)
	stale.slots_sha256 = Profile.bindings_sha256(stale)
	_check("migration refuses physical model substitution", not Profile.migrate_v1(checked.profile, bindings, stale).get("ok", false))


func _test_authored_skin_bindings() -> void:
	var registry: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/aircraft_customization.json"))
	var bindings: Dictionary = {}
	for family: Dictionary in registry.get("families", []):
		if family.get("visual_family") == "jensen-das-ugly-stik-60": bindings = family
	var checked := Profile.validate(Profile.defaults(bindings), bindings)
	_check("actual authored skin companion is admitted by Workshop", checked.get("ok", false), str(checked.get("errors", [])))
	if bindings.is_empty(): return
	var profile := Profile.defaults(bindings)
	profile.lighting = Profile.LightingProfile.preset("night_radian")
	_check("RGB profile round trips with authored skin companion", Profile.validate(
		JSON.parse_string(JSON.stringify(profile)), JSON.parse_string(JSON.stringify(bindings))).get("ok", false))
	for mutation: String in ["unknown_mask", "missing_target", "duplicate_target_id", "invalid_target_id", "malformed_paint"]:
		var invalid := bindings.duplicate(true)
		match mutation:
			"unknown_mask": invalid.lighting_layout.skins[0].mask_profile_id = "res://untrusted.png"
			"missing_target": invalid.lighting_layout.skins[0].target_ids[0] = "missing_skin"
			"duplicate_target_id":
				invalid.paint_slots[0].targets[0]["target_id"] = invalid.lighting_layout.skins[0].target_ids[0]
			"invalid_target_id": invalid.paint_slots[0].targets[0]["target_id"] = "../skin"
			"malformed_paint": invalid.paint_slots[0] = false
		invalid.slots_sha256 = Profile.bindings_sha256(invalid)
		var rejected := Profile.validate(Profile.defaults(invalid), invalid)
		_check("Workshop rejects skin companion " + mutation, not rejected.get("ok", false), str(rejected.get("errors", [])))


func _bindings_fixture() -> Dictionary:
	var bindings: Dictionary = {
		"format": Profile.BINDINGS_FORMAT,
		"version": 2,
		"visual_family": "fixture-aircraft",
		"model_manifest_sha256": "a".repeat(64),
		"paint_slots": [
			{"id": "body", "label": "Body", "targets": [
				{"node_path": "airplane/body", "surface": 0, "kind": "standard_albedo"}]},
			{"id": "wing", "label": "Wing", "targets": [
				{"node_path": "airplane/wing", "surface": 0, "kind": "standard_albedo"}],
				"accent_targets": [
					{"node_path": "airplane/wing_accent", "surface": 0, "kind": "standard_albedo"}]},
		],
		"marking_slots": [{"id": "registration", "label": "Registration", "max_chars": 12, "targets": [
			{"node_path": "airplane/wing", "position_m": [0.0, 0.0, 0.0], "direction": [0.0, 0.0, -1.0],
				"up": [0.0, 1.0, 0.0], "width_m": 1.0, "height_m": 0.2}]}],
		"smoke_slots": [
			{"id": "smoke_left", "label": "Left show", "kind": "show", "pair": "wing_tips", "role": "wing_tip_left",
				"node_path": "airplane/smoke_left", "position_m": [-0.5, 0.0, 0.0], "direction": [0.0, 0.0, -1.0]},
			{"id": "smoke_right", "label": "Right show", "kind": "show", "pair": "wing_tips", "role": "wing_tip_right",
				"node_path": "airplane/smoke_right", "position_m": [0.5, 0.0, 0.0], "direction": [0.0, 0.0, -1.0]},
			{"id": "smoke_center", "label": "Center show", "kind": "show", "pair": "", "role": "tail",
				"node_path": "airplane/smoke_center", "position_m": [0.0, 0.0, 0.0], "direction": [0.0, 0.0, -1.0]},
			{"id": "source_exhaust", "label": "Source exhaust", "kind": "source", "pair": "", "role": "exhaust",
				"source_kind": "propulsion", "source_anchor_ref": "engine_main", "physical_source_ref": "engine_main",
				"physical_source_kind_ref": "propulsion"},
		],
		"presentation_sources": [],
		"presentation_engine_version": Profile.PRESENTATION_ENGINE_VERSION,
		"slots_sha256": "",
	}
	for path: String in Profile.PRESENTATION_SOURCE_PATHS:
		bindings.presentation_sources.append({"path": path, "sha256": "a".repeat(64)})
	bindings["slots_sha256"] = Profile.bindings_sha256(bindings)
	return bindings


func _legacy_bindings_fixture() -> Dictionary:
	var bindings: Dictionary = _bindings_fixture()
	bindings["version"] = Profile.LEGACY_BINDINGS_VERSION
	bindings.erase("presentation_sources")
	bindings.erase("presentation_engine_version")
	bindings["slots_sha256"] = Profile.bindings_sha256(bindings)
	return bindings


func _pins(bindings: Dictionary) -> Dictionary:
	return {"visual_family": bindings.visual_family,
		"model_manifest_sha256": bindings.model_manifest_sha256,
		"slots_sha256": bindings.slots_sha256}


func _paint_profile(bindings: Dictionary) -> Dictionary:
	var profile: Dictionary = Profile.defaults(bindings)
	profile.paint = [{"slot": "body", "color": "#808080", "pattern": "solid", "accent": "none"}]
	profile.markings = [{"slot": "registration", "text": "NIÑO 5", "color": "#123456"}]
	return profile


func _smoke_profile(bindings: Dictionary) -> Dictionary:
	var profile: Dictionary = Profile.defaults(bindings)
	profile.smoke = [_smoke_entry("smoke_left")]
	return profile


func _smoke_entry(slot: String) -> Dictionary:
	return {
		"slot": slot, "enabled": true, "color": "#FFFFFF", "amount": 0.75,
		"width_m": 0.5, "lifetime_s": 6.0, "shape": "ribbon", "mode": "hold",
		"burst_s": 0.0, "pulse_period_s": 0.0, "pulse_duty": 0.0,
		"palette": [], "step_s": 0.0,
	}


func _check(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL ", label, " ", detail)

