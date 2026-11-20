extends SceneTree
## AE-27 internal contract; does not qualify an attachment for flight or persistence.

const Selection := preload("res://workshop/attachment_selection.gd")
const Presentation := preload("res://workshop/presentation.gd")
const Parameters := preload("res://workshop/parameters.gd")

var _checks := 0
var _failed := 0


func _initialize() -> void:
	var original := Selection.original()
	_check("Original is explicit in every slot", original.selections == {
		"wheels": "original", "landing_gear": "original", "propeller": "original", "spinner": "original"})
	_check("explicit Original validates", Selection.validate(original).ok)
	_check("JSON round trip retains the canonical selection", Selection.validate(JSON.parse_string(JSON.stringify(original))).selection == original)
	var numeric := original.duplicate(true)
	numeric.version = 1.0
	_check("integer and JSON float version canonicalize equally", Selection.validate(numeric).selection == original)
	var rearranged := {"selections": {"spinner": "original", "propeller": "original",
		"landing_gear": "original", "wheels": "original"}, "catalog_sha256": original.catalog_sha256,
		"version": 1, "format": Selection.FORMAT}
	_check("input order canonicalizes", JSON.stringify(Selection.validate(rearranged).selection) == JSON.stringify(original))
	_check("catalogue digest is stable SHA-256", Selection.catalog_sha256().length() == 64
		and Selection.catalog_sha256() == Selection.catalog_sha256())
	for id: String in [Selection.PILOT_ID, "gp-extra-300s-60", "stik-electric-6s", "stik-glow-61fx-2t",
		"stik-glow-55ax-2t", "stik-glow-fs64v-4t", "turbo-lumber-evolution", "p51d-mustang-120",
		"f4u-corsair-250", "sebart-avanti-s-a200-p100rx", "moonrunner-x99", "unregistered-aircraft"]:
		var result := Selection.resolve(original, id, 1.0)
		_check(id + " retains explicit Original", result.ok and result.availability == "cosmetic_flight" and result.options.is_empty())
	_test_closed_shape(original)
	_test_compatibility(original)
	_test_isolation(original)
	_test_current_boundary(original)
	print("Attachment selection: %d checks, %d failed" % [_checks, _failed])
	quit(1 if _failed else 0)


func _test_closed_shape(original: Dictionary) -> void:
	for value: Variant in [null, {}, [], "original", 1, true]:
		_refuses("missing or non-document value", Selection.validate(value), "ATTACHMENT_SHAPE")
	for key: String in original:
		var missing := original.duplicate(true)
		missing.erase(key)
		_refuses("missing document key " + key, Selection.validate(missing), "ATTACHMENT_SHAPE")
	for key: String in ["availability", "factory", "path", "scale", "mass", "flight_eligible"]:
		var injected := original.duplicate(true)
		injected[key] = "cosmetic_flight"
		_refuses("refuse injected " + key, Selection.validate(injected), "ATTACHMENT_SHAPE")
	for version: Variant in [null, true, "1", 0, 2, -1, 1.1, NAN, INF]:
		var bad := original.duplicate(true)
		bad.version = version
		_refuses("invalid version " + str(version), Selection.validate(bad), "ATTACHMENT_VERSION")
	var bad_format := original.duplicate(true)
	bad_format.format = "future-format"
	_refuses("unknown format", Selection.validate(bad_format), "ATTACHMENT_FORMAT")
	for digest: Variant in [null, "", "0".repeat(64), original.catalog_sha256.to_upper(), 123]:
		var stale := original.duplicate(true)
		stale.catalog_sha256 = digest
		_refuses("unknown or stale catalogue digest", Selection.validate(stale), "ATTACHMENT_CATALOG_STALE")
	for slot: String in Selection.SLOT_IDS:
		var missing := original.duplicate(true)
		missing.selections.erase(slot)
		_refuses("explicit missing slot " + slot, Selection.validate(missing), "ATTACHMENT_SLOTS")
	var extra_slot := original.duplicate(true)
	extra_slot.selections.engine = "original"
	_refuses("unknown slot", Selection.validate(extra_slot), "ATTACHMENT_SLOTS")
	for slots: Variant in [[], null, "original", true]:
		var invalid := original.duplicate(true)
		invalid.selections = slots
		_refuses("non-object selections", Selection.validate(invalid), "ATTACHMENT_SLOTS")
	for option: Variant in [null, true, 1, {}, [], "", "Original", "original\n", "res://wheel.tscn", "a".repeat(81)]:
		var malformed := original.duplicate(true)
		malformed.selections.wheels = option
		_refuses("malformed option ID", Selection.validate(malformed), "ATTACHMENT_OPTION_ID")
	var unknown := original.duplicate(true)
	unknown.selections.wheels = "missing_wheel_v1"
	_refuses("unknown ID never falls back", Selection.validate(unknown), "ATTACHMENT_OPTION_UNKNOWN")
	_refuses("unknown ID on unregistered aircraft never falls back", Selection.resolve(unknown, "unregistered-aircraft", 1.0), "ATTACHMENT_OPTION_UNKNOWN")
	var wrong_slot := original.duplicate(true)
	wrong_slot.selections.spinner = Selection.TWIN_GROOVE_ID
	_refuses("known option in the wrong slot", Selection.validate(wrong_slot), "ATTACHMENT_OPTION_UNKNOWN")


func _test_compatibility(original: Dictionary) -> void:
	var study := original.duplicate(true)
	study.selections.wheels = Selection.TWIN_GROOVE_ID
	var result := Selection.resolve(study, Selection.PILOT_ID, 1.0)
	_check("pilot study resolves as preview-only with a reason", result.ok and result.availability == "preview_only"
		and result.reasons.size() == 1 and result.options[0].qualification == "internal_unqualified")
	_check("resolution contains no flight authorization", not result.has("flight_eligible") and not result.has("admitted"))
	_refuses("omitted scale cannot imply 100 percent", Selection.resolve(study, Selection.PILOT_ID), "ATTACHMENT_SCALE")
	for id: String in ["creator_plane.v1", "a".repeat(128)]:
		_check("existing base-ID grammar retains Original", Selection.resolve(original, id, 1.0).ok)
	for id: String in ["gp-extra-300s-60", "stik-electric-6s", "stik-glow-61fx-2t", "stik-glow-55ax-2t",
		"stik-glow-fs64v-4t", "unregistered-aircraft", "skywalker-x8"]:
		_refuses("no inferred configuration support: " + id, Selection.resolve(study, id, 1.0), "ATTACHMENT_INCOMPATIBLE")
	for id: Variant in [null, true, 123, [], "", " ", "UglyStick", "../stik", Selection.PILOT_ID + "\n", "a".repeat(129)]:
		_refuses("malformed aircraft context", Selection.resolve(original, id, 1.0), "ATTACHMENT_AIRCRAFT")
	for scale: Variant in [null, true, "1", [], NAN, INF, -INF, 0, -1, 0.099, 5.001]:
		_refuses("invalid scale " + str(scale), Selection.resolve(original, Selection.PILOT_ID, scale), "ATTACHMENT_SCALE")
	for scale: float in [0.1, 0.99, 1.001, 5.0]:
		_check("Original accepts the valid size domain", Selection.resolve(original, Selection.PILOT_ID, scale).ok)
		_refuses("study has no unmeasured scale domain", Selection.resolve(study, Selection.PILOT_ID, scale), "ATTACHMENT_SCALE_UNSUPPORTED")
	_check("integer scale one is valid", Selection.resolve(study, Selection.PILOT_ID, 1).ok)


func _test_isolation(original: Dictionary) -> void:
	var study := original.duplicate(true)
	study.selections.wheels = Selection.TWIN_GROOVE_ID
	var before := JSON.stringify(study)
	var result := Selection.resolve(study, Selection.PILOT_ID, 1.0)
	result.selection.selections.wheels = "mutated"
	result.options[0].availability = "cosmetic_flight"
	var exposed := Selection.catalog()
	exposed.options[0].availability = "cosmetic_flight"
	exposed.options[0].aircraft_ids.append("gp-extra-300s-60")
	exposed.slots.clear()
	_check("resolution never mutates its input", JSON.stringify(study) == before)
	_check("catalogue/result copies cannot promote availability", Selection.resolve(study, Selection.PILOT_ID, 1.0).availability == "preview_only")
	_refuses("catalogue copy cannot grant compatibility", Selection.resolve(study, "gp-extra-300s-60", 1.0), "ATTACHMENT_INCOMPATIBLE")
	_check("catalogue copy cannot change its digest", Selection.catalog_sha256() == original.catalog_sha256)
	var another := Selection.original()
	another.selections.wheels = "changed"
	_check("Original documents do not share mutable selections", Selection.original() == original)


func _test_current_boundary(selection: Dictionary) -> void:
	_check("existing presentation stays at version four", Presentation.VERSION == 4)
	var profile := Presentation.defaults()
	profile.attachments = selection
	_check("current profile cannot accidentally persist the internal study", not Presentation.validate(profile).ok)
	var recipe := Parameters.defaults()
	recipe.attachments = selection
	_check("visual selections remain outside the physical recipe", not Parameters.validate(recipe).ok)


func _refuses(label: String, result: Dictionary, code: String) -> void:
	_check(label, not result.ok and result.selection.is_empty() and result.availability == "unavailable"
		and result.diagnostics[0].code == code, str(result.get("errors", [])))


func _check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if not ok:
		_failed += 1
	print(("ok   " if ok else "FAIL ") + label + ("  " + detail if not ok else ""))
