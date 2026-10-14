extends SceneTree

const Catalog = preload("res://app_state/aircraft_catalog.gd")
const Descriptor = preload("res://workshop/descriptor.gd")
const Modules = preload("res://physics/aircraft_modules.gd")

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_test_catalog_descriptors()
	_test_stale_binding()
	_test_stable_inventory_identity()
	_test_unfamiliar_identity()
	_test_rejections()
	_test_legacy_and_presentation()
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_catalog_descriptors() -> void:
	var ids: PackedStringArray = Catalog.airplane_flyable_ids()
	_check("every airplane catalog entry is discovered", ids.size() == 8 and not ids.is_empty(), str(ids))
	_check("rotorcraft has no airplane Workshop descriptor", Catalog.is_rotorcraft("xcell-60-research") and not ids.has("xcell-60-research"))
	for id: String in ids:
		var entry: Dictionary = Catalog.entry(id)
		var base_bytes: PackedByteArray = FileAccess.get_file_as_bytes(str(entry.get("data", "")))
		var base: Dictionary = JSON.parse_string(base_bytes.get_string_from_utf8())
		var loaded: Dictionary = Descriptor.load_for(id, base_bytes)
		_check("catalog descriptor loads for " + id, bool(loaded["ok"]), str(loaded["errors"]))
		if not bool(loaded["ok"]):
			continue
		var descriptor: Dictionary = loaded["descriptor"]
		var expected_format: String = Descriptor.FORMAT if base.has("physical_identity_version") else Descriptor.V2_FORMAT
		_check("descriptor version follows the source identity module for " + id, descriptor["format"] == expected_format)
		_check("exact source bytes are pinned for " + id, str(descriptor["base_sha256"]) == _sha256(base_bytes))
		_check("catalog identity and scale root are bound for " + id, descriptor["base_id"] == id and descriptor["presentation"]["visual_family"] == Catalog.visual_family(id) and descriptor["presentation"]["scale_root"] == "airplane")
		_check("inventory bindings cover every source item for " + id, descriptor["inventory_bindings"].size() == JSON.parse_string(base_bytes.get_string_from_utf8())["inventory"].size())
		if descriptor["format"] == Descriptor.FORMAT:
			var source_ids: Dictionary = {}
			for component: Dictionary in base["inventory"]:
				source_ids[component.get("id", "")] = true
			var bound_ids: Dictionary = {}
			var only_id_keys: bool = true
			for binding: Dictionary in descriptor["inventory_bindings"]:
				only_id_keys = only_id_keys and binding.size() == 1 and binding.has("key")
				bound_ids[str(binding.get("key", ""))] = true
			_check("v3 uses only authored inventory IDs for " + id,
				only_id_keys and bound_ids.size() == source_ids.size() and bound_ids == source_ids)
		_check("descriptor names its generated source for " + id, str(descriptor["_generated_do_not_edit"]).contains("do not edit"))


func _test_stale_binding() -> void:
	var id: String = "jensen-das-ugly-stik-60"
	var entry: Dictionary = Catalog.entry(id)
	var base_bytes: PackedByteArray = FileAccess.get_file_as_bytes(str(entry["data"]))
	var loaded: Dictionary = Descriptor.load_for(id, base_bytes)
	if not bool(loaded["ok"]):
		_check("stale binding fixture descriptor loads", false, str(loaded["errors"]))
		return
	var changed_base: Dictionary = JSON.parse_string(base_bytes.get_string_from_utf8())
	changed_base["inventory"][0]["name"] = str(changed_base["inventory"][0]["name"]) + " renamed"
	var changed_bytes: PackedByteArray = (JSON.stringify(changed_base, "\t", true, true) + "\n").to_utf8_buffer()
	var stale_descriptor: Dictionary = loaded["descriptor"].duplicate(true)
	var rejected: Dictionary
	if stale_descriptor["format"] == Descriptor.FORMAT:
		rejected = Descriptor.validate(stale_descriptor, id, changed_bytes)
		_check("renaming a source cannot retarget a stale v3 descriptor", not bool(rejected["ok"]) and _has_error(rejected["errors"], "SHA-256"), str(rejected["errors"]))
	else:
		stale_descriptor["base_sha256"] = _sha256(changed_bytes)
		rejected = Descriptor.validate(stale_descriptor, id, changed_bytes)
		_check("a matching source hash cannot hide a stale v2 inventory name binding", not bool(rejected["ok"]) and _has_error(rejected["errors"], "stale"), str(rejected["errors"]))
	var byte_changed: PackedByteArray = base_bytes.duplicate()
	byte_changed[byte_changed.size() - 1] = 32 if byte_changed[byte_changed.size() - 1] != 32 else 10
	var hash_rejected: Dictionary = Descriptor.validate(loaded["descriptor"], id, byte_changed)
	_check("changed source bytes fail the pinned SHA-256", not bool(hash_rejected["ok"]) and _has_error(hash_rejected["errors"], "SHA-256"), str(hash_rejected["errors"]))


func _test_stable_inventory_identity() -> void:
	var base_id: String = Catalog.DEFAULT_ID
	var source_bytes: PackedByteArray = FileAccess.get_file_as_bytes(Catalog.entry(base_id).data)
	var base: Dictionary = JSON.parse_string(source_bytes.get_string_from_utf8())
	_add_test_physical_identity(base)
	var stable_bytes: PackedByteArray = _source_bytes(base)
	var presentation: Dictionary = {
		"visual_family": Catalog.visual_family(base_id),
		"model_manifest_sha256": "0".repeat(64),
		"scale_root": "airplane",
	}
	var stable_descriptor: Dictionary = _stable_descriptor(base_id, stable_bytes, base,
		presentation)
	var accepted: Dictionary = Descriptor.validate(stable_descriptor, base_id, stable_bytes)
	_check("v3 descriptor accepts a complete physical identity module", bool(accepted.get("ok", false)), str(accepted.get("errors", [])))
	if not bool(accepted.get("ok", false)):
		return
	var target_id: String = str(base["inventory"][0]["id"])
	var original_index: int = Descriptor.resolve_inventory_index(accepted["descriptor"], target_id, base)
	if original_index < 0:
		_check("v3 binding resolves an inventory component by its authored ID", false)
		return
	var original_component: Dictionary = base["inventory"][original_index]
	var original_mass: Variant = original_component.get("mass", null)
	_check("v3 binding resolves an inventory component by its authored ID", original_index == 0 and original_component.get("id", "") == target_id)

	var changed: Dictionary = base.duplicate(true)
	changed["inventory"][0]["name"] = str(changed["inventory"][0]["name"]) + " renamed"
	changed["inventory"].reverse()
	var changed_bytes: PackedByteArray = _source_bytes(changed)
	var changed_descriptor: Dictionary = _stable_descriptor(base_id, changed_bytes, changed,
		presentation)
	var regenerated: Dictionary = Descriptor.validate(changed_descriptor, base_id, changed_bytes)
	_check("regenerated v3 descriptor accepts the renamed and reordered source", bool(regenerated.get("ok", false)), str(regenerated.get("errors", [])))
	if bool(regenerated.get("ok", false)):
		var resolved_index: int = Descriptor.resolve_inventory_index(regenerated["descriptor"], target_id, changed)
		if resolved_index >= 0:
			var resolved_component: Dictionary = changed["inventory"][resolved_index]
			_check("regenerated binding still resolves the same physical component after reorder and rename",
				resolved_index != original_index and resolved_component.get("id", "") == target_id
				and resolved_component.get("mass", null) == original_mass)
		else:
			_check("regenerated binding still resolves the same physical component after reorder and rename", false)
		var original_keys: Dictionary = {}
		var regenerated_keys: Dictionary = {}
		for binding: Dictionary in stable_descriptor["inventory_bindings"]:
			original_keys[binding["key"]] = true
		for binding: Dictionary in changed_descriptor["inventory_bindings"]:
			regenerated_keys[binding["key"]] = true
		_check("renamed and reordered source retains every authored inventory key", original_keys == regenerated_keys)
		var binding_order: Dictionary = changed_descriptor.duplicate(true)
		binding_order["inventory_bindings"].reverse()
		var order_check: Dictionary = Descriptor.validate(binding_order, base_id, changed_bytes)
		_check("v3 binding-array order is independent of source order", bool(order_check.get("ok", false)), str(order_check.get("errors", [])))
	var stale_source: Dictionary = Descriptor.validate(accepted["descriptor"], base_id, changed_bytes)
	_check("source edits remain pinned to the exact descriptor snapshot",
		not bool(stale_source.get("ok", false)) and _has_error(stale_source.get("errors", []), "SHA-256"), str(stale_source.get("errors", [])))

	var duplicate: Dictionary = base.duplicate(true)
	duplicate["landing_gear"]["contacts"][0]["id"] = duplicate["inventory"][0]["id"]
	var duplicate_bytes: PackedByteArray = _source_bytes(duplicate)
	var duplicate_descriptor: Dictionary = _stable_descriptor(base_id, duplicate_bytes, duplicate,
		presentation)
	var duplicate_result: Dictionary = Descriptor.validate(duplicate_descriptor, base_id, duplicate_bytes)
	_check("duplicate IDs across physical identity kinds are rejected", not bool(duplicate_result.get("ok", false))
		and _has_error(duplicate_result.get("errors", []), "duplicate"), str(duplicate_result.get("errors", [])))

	var duplicate_binding: Dictionary = stable_descriptor.duplicate(true)
	duplicate_binding["inventory_bindings"][1]["key"] = duplicate_binding["inventory_bindings"][0]["key"]
	var duplicate_binding_result: Dictionary = Descriptor.validate(duplicate_binding, base_id, stable_bytes)
	_check("duplicate v3 inventory bindings are rejected", not bool(duplicate_binding_result.get("ok", false))
		and _has_error(duplicate_binding_result.get("errors", []), "unique"), str(duplicate_binding_result.get("errors", [])))

	var extra_binding_field: Dictionary = stable_descriptor.duplicate(true)
	extra_binding_field["inventory_bindings"][0]["index"] = 0
	var extra_field_result: Dictionary = Descriptor.validate(extra_binding_field, base_id, stable_bytes)
	_check("v3 inventory bindings reject index and name-hash fields", not bool(extra_field_result.get("ok", false))
		and _has_error(extra_field_result.get("errors", []), "only its key"), str(extra_field_result.get("errors", [])))
	_check("unknown stable inventory IDs do not resolve", Descriptor.resolve_inventory_index(accepted["descriptor"], "unknown_component", base) == -1)

	var missing: Dictionary = base.duplicate(true)
	missing["inventory"][0].erase("id")
	var missing_bytes: PackedByteArray = _source_bytes(missing)
	var missing_descriptor: Dictionary = stable_descriptor.duplicate(true)
	missing_descriptor["base_sha256"] = _sha256(missing_bytes)
	var missing_result: Dictionary = Descriptor.validate(missing_descriptor, base_id, missing_bytes)
	_check("missing source inventory ID is rejected", not bool(missing_result.get("ok", false))
		and _has_error(missing_result.get("errors", []), "/inventory/0/id"), str(missing_result.get("errors", [])))

	var unknown_descriptor: Dictionary = stable_descriptor.duplicate(true)
	unknown_descriptor["inventory_bindings"][0]["key"] = "unknown_component"
	var unknown_result: Dictionary = Descriptor.validate(unknown_descriptor, base_id, stable_bytes)
	_check("binding to an unknown source inventory ID is rejected", not bool(unknown_result.get("ok", false))
		and _has_error(unknown_result.get("errors", []), "does not resolve"), str(unknown_result.get("errors", [])))


func _add_test_physical_identity(base: Dictionary) -> void:
	base["physical_identity_version"] = 1
	for index: int in base.get("inventory", []).size():
		base["inventory"][index]["id"] = "part_%02d" % index
	var gear: Dictionary = base.get("landing_gear", {})
	for index: int in gear.get("contacts", []).size():
		gear["contacts"][index]["id"] = "contact_%02d" % index
	base["landing_gear"] = gear
	base["propulsion"]["id"] = "propulsion_main"
	var hull_points: Array = base.get("crash_hull", {}).get("value", [])
	var hull_ids: Array = []
	for index: int in hull_points.size():
		hull_ids.append("hull_%03d" % index)
	base["crash_hull_ids"] = hull_ids
	base["controls"]["surface_ids"] = {
		"aileron_left": "surface_aileron_left",
		"aileron_right": "surface_aileron_right",
		"elevator": "surface_elevator",
		"rudder": "surface_rudder",
	}


func _stable_descriptor(base_id: String, base_bytes: PackedByteArray, base: Dictionary,
		presentation: Dictionary) -> Dictionary:
	var modules: Dictionary = Modules.classify(base)
	var bindings: Array = []
	for component: Dictionary in base.get("inventory", []):
		bindings.append({"key": str(component.get("id", ""))})
	return {
		"_generated_do_not_edit": "Generated by research/aircraft-editor/build_descriptors.py; do not edit.",
		"format": Descriptor.FORMAT,
		"base_id": base_id,
		"base_sha256": _sha256(base_bytes),
		"inventory_bindings": bindings,
		"modules": modules.get("modules", []),
		"presentation": presentation.duplicate(true),
	}


func _source_bytes(base: Dictionary) -> PackedByteArray:
	return (JSON.stringify(base, "\t", true, true) + "\n").to_utf8_buffer()


func _test_unfamiliar_identity() -> void:
	var source_id: String = "jensen-das-ugly-stik-60"
	var source_bytes: PackedByteArray = FileAccess.get_file_as_bytes(str(Catalog.entry(source_id)["data"]))
	var source_descriptor: Dictionary = Descriptor.load_for(source_id, source_bytes)["descriptor"]
	var unfamiliar_id: String = "synthetic-unfamiliar-airframe-20"
	var unfamiliar_base: Dictionary = JSON.parse_string(source_bytes.get_string_from_utf8())
	unfamiliar_base["id"] = unfamiliar_id
	var unfamiliar_bytes: PackedByteArray = (JSON.stringify(unfamiliar_base, "\t", true, true) + "\n").to_utf8_buffer()
	var unfamiliar_descriptor: Dictionary = source_descriptor.duplicate(true)
	unfamiliar_descriptor["base_id"] = unfamiliar_id
	unfamiliar_descriptor["base_sha256"] = _sha256(unfamiliar_bytes)
	var accepted: Dictionary = Descriptor.validate(unfamiliar_descriptor, unfamiliar_id, unfamiliar_bytes)
	_check("unfamiliar data-only identity validates from its descriptor", bool(accepted["ok"]), str(accepted["errors"]))
	if bool(accepted["ok"]):
		_check("unfamiliar identity keeps the shared inventory module data", accepted["descriptor"]["modules"] == source_descriptor["modules"])


func _test_rejections() -> void:
	var id: String = "jensen-das-ugly-stik-60"
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(str(Catalog.entry(id)["data"]))
	var valid: Dictionary = Descriptor.load_for(id, bytes)
	if not bool(valid["ok"]):
		_check("rejection fixtures have a valid source descriptor", false, str(valid["errors"]))
		return
	var unknown_format: Dictionary = valid["descriptor"].duplicate(true)
	unknown_format["format"] = "openrc-aircraft-workshop v99"
	var version_result: Dictionary = Descriptor.validate(unknown_format, id, bytes)
	_check("unsupported descriptor version is rejected", not bool(version_result["ok"]) and _has_error(version_result["errors"], "format"), str(version_result["errors"]))
	var wrong_modules: Dictionary = valid["descriptor"].duplicate(true)
	wrong_modules["modules"].append("propulsion.unknown.v9")
	var module_result: Dictionary = Descriptor.validate(wrong_modules, id, bytes)
	_check("module assertions must match raw aircraft capabilities", not bool(module_result["ok"]) and _has_error(module_result["errors"], "module assertions"), str(module_result["errors"]))
	var extra_fields: Dictionary = valid["descriptor"].duplicate(true)
	extra_fields["wing_area"] = 0.464515
	var extra_result: Dictionary = Descriptor.validate(extra_fields, id, bytes)
	_check("descriptor cannot copy physical constants", not bool(extra_result["ok"]) and _has_error(extra_result["errors"], "unsupported fields"), str(extra_result["errors"]))
	var wrong_identity: Dictionary = Descriptor.validate(valid["descriptor"], "gp-extra-300s-60", bytes)
	_check("descriptor cannot bind another aircraft source", not bool(wrong_identity["ok"]))
	var unsafe_root: Dictionary = Descriptor.load_for(id, bytes, "res://data/../aircraft")
	_check("path traversal descriptor roots are rejected", not bool(unsafe_root["ok"]))


func _test_legacy_and_presentation() -> void:
	var id: String = Catalog.DEFAULT_ID
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(Catalog.entry(id).data)
	var current_result: Dictionary = Descriptor.load_for(id, bytes)
	if not bool(current_result.get("ok", false)):
		_check("current descriptor loads for presentation checks", false, str(current_result.get("errors", [])))
		return
	var current: Dictionary = current_result["descriptor"]
	_check("current descriptor uses the current or historical supported binding version",
		current.format in [Descriptor.FORMAT, Descriptor.V2_FORMAT])
	var resolved: Dictionary = Descriptor.verify_presentation(current)
	_check("current model dependencies resolve before flight", resolved.ok, str(resolved.errors))
	if current.format == Descriptor.FORMAT:
		_check("v3 retains the v2 model-family and manifest presentation fields",
			current.presentation.has_all(["visual_family", "model_manifest_sha256", "scale_root"]))
	var historical_base: Dictionary = JSON.parse_string(bytes.get_string_from_utf8())
	_strip_physical_identity(historical_base)
	var historical_bytes: PackedByteArray = _source_bytes(historical_base)
	var historical_v2: Dictionary = _historical_descriptor(id, historical_base, historical_bytes, current)
	var v2_result: Dictionary = Descriptor.validate(historical_v2, id, historical_bytes)
	_check("v2 historical snapshot and its exact index/name bindings remain readable",
		bool(v2_result.get("ok", false)), str(v2_result.get("errors", [])))
	_check("v2 saved model dependencies still resolve", Descriptor.verify_presentation(historical_v2).get("ok", false))
	var gear_up_legacy: Dictionary = historical_base.duplicate(true)
	gear_up_legacy["landing_gear"] = {}
	var gear_up_bytes: PackedByteArray = _source_bytes(gear_up_legacy)
	var gear_up_descriptor: Dictionary = _historical_descriptor(id, gear_up_legacy, gear_up_bytes, current)
	var gear_up_result: Dictionary = Descriptor.validate(gear_up_descriptor, id, gear_up_bytes)
	_check("v2 legacy snapshots with an empty landing-gear object remain readable",
		bool(gear_up_result.get("ok", false)), str(gear_up_result.get("errors", [])))
	var renamed_historical: Dictionary = historical_base.duplicate(true)
	renamed_historical["inventory"][0]["name"] = str(renamed_historical["inventory"][0]["name"]) + " renamed"
	var renamed_historical_bytes: PackedByteArray = _source_bytes(renamed_historical)
	var stale_v2: Dictionary = historical_v2.duplicate(true)
	stale_v2["base_sha256"] = _sha256(renamed_historical_bytes)
	var stale_v2_result: Dictionary = Descriptor.validate(stale_v2, id, renamed_historical_bytes)
	_check("v2 still rejects renamed inventory even when the source SHA is refreshed",
		not bool(stale_v2_result.get("ok", false)) and _has_error(stale_v2_result.get("errors", []), "stale"),
		str(stale_v2_result.get("errors", [])))
	var legacy: Dictionary = historical_v2.duplicate(true)
	legacy.format = Descriptor.LEGACY_FORMAT
	legacy.presentation = {"visual_id": id, "scale_root": "airplane"}
	var legacy_result: Dictionary = Descriptor.validate(legacy, id, historical_bytes)
	_check("v1 saved descriptor remains readable", legacy_result.ok, str(legacy_result.errors))
	_check("v1 catalog compatibility bridge resolves the same family", Descriptor.verify_presentation(legacy).ok)
	var stale_v1: Dictionary = legacy.duplicate(true)
	stale_v1["base_sha256"] = _sha256(renamed_historical_bytes)
	var stale_v1_result: Dictionary = Descriptor.validate(stale_v1, id, renamed_historical_bytes)
	_check("v1 still rejects renamed inventory even when the source SHA is refreshed",
		not bool(stale_v1_result.get("ok", false)) and _has_error(stale_v1_result.get("errors", []), "stale"),
		str(stale_v1_result.get("errors", [])))
	var stale: Dictionary = current.duplicate(true)
	stale.presentation.model_manifest_sha256 = "0".repeat(64)
	_check("stale model still allows reading a saved variant", Descriptor.validate(stale, id, bytes).ok)
	_check("stale model cannot start a trial", not Descriptor.verify_presentation(stale).ok)
	var malformed: Dictionary = current.duplicate(true)
	malformed.presentation.model_manifest_sha256 = "invalid-hash"
	_check("malformed model pin is rejected structurally", not Descriptor.validate(malformed, id, bytes).ok)
	var wrong_family: Dictionary = current.duplicate(true)
	wrong_family.presentation.visual_family = "gp-extra-300s-60"
	_check("presentation cannot substitute another catalog family", not Descriptor.verify_presentation(wrong_family).ok)
	var unsafe: Dictionary = current.duplicate(true)
	unsafe.presentation.visual_family = "../source"
	_check("presentation rejects path traversal", not Descriptor.validate(unsafe, id, bytes).ok)


func _strip_physical_identity(base: Dictionary) -> void:
	base.erase("physical_identity_version")
	for component: Variant in base.get("inventory", []):
		if component is Dictionary:
			component.erase("id")
	var gear: Variant = base.get("landing_gear", {})
	if gear is Dictionary:
		for contact: Variant in gear.get("contacts", []):
			if contact is Dictionary:
				contact.erase("id")
	var propulsion: Variant = base.get("propulsion", {})
	if propulsion is Dictionary:
		propulsion.erase("id")
	base.erase("crash_hull_ids")
	var controls: Variant = base.get("controls", {})
	if controls is Dictionary:
		controls.erase("surface_ids")


func _historical_descriptor(base_id: String, base: Dictionary, base_bytes: PackedByteArray,
		current: Dictionary) -> Dictionary:
	var bindings: Array = []
	for index: int in base.get("inventory", []).size():
		var name: String = str(base["inventory"][index].get("name", ""))
		var name_hash: String = _sha256(name.to_utf8_buffer())
		bindings.append({"key": "inventory-%03d-%s" % [index, name_hash.substr(0, 12)],
			"index": index, "name_sha256": name_hash})
	var descriptor: Dictionary = current.duplicate(true)
	descriptor["format"] = Descriptor.V2_FORMAT
	descriptor["base_id"] = base_id
	descriptor["base_sha256"] = _sha256(base_bytes)
	descriptor["inventory_bindings"] = bindings
	return descriptor


func _has_error(errors: PackedStringArray, needle: String) -> bool:
	for message: String in errors:
		if needle in message:
			return true
	return false


func _sha256(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	context.update(bytes)
	return context.finish().hex_encode()


func _check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])
