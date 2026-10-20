extends SceneTree

const AircraftData := preload("res://physics/aircraft_data.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Compiler := preload("res://workshop/compiler.gd")
const Parameters := preload("res://workshop/parameters.gd")
const Session := preload("res://sim/flight_session.gd")
const Trial := preload("res://workshop/trial.gd")
const Store := preload("res://workshop/store.gd")
const Bundle := preload("res://workshop/bundle.gd")
const STIK_PATH := "res://data/aircraft/jensen_ugly_stik_60.json"
const ELECTRIC_PATH := "res://data/aircraft/turbo_lumber_evolution.json"
const GLOW_PATH := "res://data/aircraft/gp_extra_300s_60.json"
const DOMAIN_TAG := "_workshop_quantity_domain"

var _checks := 0
var _failures := 0


func _check(label: String, condition: bool, detail := "") -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _initialize() -> void:
	var bytes := FileAccess.get_file_as_bytes(STIK_PATH)
	var parser := JSON.new()
	var parse_error := parser.parse(bytes.get_string_from_utf8())
	_check("authentic stock Stik source parses", parse_error == OK and parser.data is Dictionary)
	if parse_error != OK or not parser.data is Dictionary:
		_finish()
		return
	var base: Dictionary = parser.data
	var snapshot: Dictionary = base.duplicate(true)
	var checked: Dictionary = AircraftData.validate_and_derive(base)
	_check("stock source passes the ordinary strict aircraft validator", bool(checked.get("ok", false)), str(checked.get("errors", [])))
	if not checked.get("ok", false):
		_finish()
		return
	var baseline: Dictionary = Compiler.compile(base, {})
	_check("default recipe is an exact successful no-op", bool(baseline.get("ok", false)) and baseline.get("raw", {}) == base,
		str(baseline.get("errors", [])))
	_check("old recipes retain the legacy compiler identity",
		Compiler.version_for_recipe({}) == Compiler.COMPILER_VERSION
			and Compiler.version_for_recipe({"scale": 0.35}) == Compiler.COMPILER_VERSION
			and Compiler.version_for_recipe({"scale": 2.25}) == Compiler.COMPILER_VERSION)
	_check("virtual endpoints select an explicitly versioned compiler",
		Compiler.version_for_recipe({"scale": Parameters.MIN_SCALE}) == Compiler.VIRTUAL_SIZE_COMPILER_VERSION
			and Compiler.version_for_recipe({"scale": Parameters.MAX_SCALE}) == Compiler.VIRTUAL_SIZE_COMPILER_VERSION)
	var explicit_model: Dictionary = Parameters.validate({"size_model": Parameters.VIRTUAL_SIZE_MODEL})
	_check("supported explicit size model is accepted and versioned",
		bool(explicit_model.get("ok", false))
			and Compiler.version_for_recipe(explicit_model.get("values", {})) == Compiler.VIRTUAL_SIZE_COMPILER_VERSION)

	_test_endpoint_matrix(base, bytes, baseline.data.model)
	_test_persistence(bytes)
	_test_strict_rejections(base)
	_test_invalid_bases(base)
	_test_domain_rejections(base)
	_test_control_limit(base)
	_test_module_refusals()
	_check("all compile/freeze paths leave the authentic source untouched", base == snapshot)
	print("Workshop virtual size: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_endpoint_matrix(base: Dictionary, base_bytes: PackedByteArray, base_model: Dictionary) -> void:
	for scale_value: float in [Parameters.MIN_SCALE, Parameters.MAX_SCALE]:
		for mass_policy: String in Parameters.MASS_POLICIES:
			var recipe := {"scale": scale_value, "mass_policy": mass_policy}
			var compiled: Dictionary = Compiler.compile(base, recipe)
			var label := "%.0f%% %s" % [scale_value * 100.0, mass_policy]
			_check(label + " compiles through the virtual dimensional domain", bool(compiled.get("ok", false)),
				str(compiled.get("errors", [])))
			if not compiled.get("ok", false):
				continue
			var model: Dictionary = compiled.data.model
			var mass_ratio := pow(scale_value, 2.0 if mass_policy == "constant_wing_loading" else 3.0)
			var base_liquid_mass := _liquid_kg(base_model)
			var expected_mass := (float(base_model.mass_kg) - base_liquid_mass) * mass_ratio \
				+ base_liquid_mass * pow(scale_value, 3.0)
			_check(label + " derives actual geometry and inventory mass at the requested scale",
				is_equal_approx(float(model.reference.b), float(base_model.reference.b) * scale_value)
					and is_equal_approx(float(model.reference.S), float(base_model.reference.S) * pow(scale_value, 2.0))
					and is_equal_approx(float(model.mass_kg), expected_mass)
					and is_equal_approx(_liquid_kg(model), base_liquid_mass * pow(scale_value, 3.0)),
				"derived span/area/mass=%s/%s/%s" % [model.reference.b, model.reference.S, model.mass_kg])
			var strict_raw: Dictionary = AircraftData.validate_and_derive(compiled.raw)
			_check(label + " raw candidate still fails the ordinary stock-unit validator",
				not bool(strict_raw.get("ok", false)), str(strict_raw.get("errors", [])))
			_check(label + " compiler strips all private quantity-domain tags",
				not _contains_key(compiled.raw, DOMAIN_TAG))
			var throws: Dictionary = compiled.raw.get("controls", {}).get("max_throw", {})
			var bounded_throws: bool = not throws.is_empty() and throws == base.controls.max_throw
			for throw_key: String in throws:
				var throw: Dictionary = throws[throw_key]
				bounded_throws = bounded_throws and typeof(throw.get("value")) in [TYPE_INT, TYPE_FLOAT] \
					and float(throw.value) >= 1.0 and float(throw.value) <= 60.0
			_check(label + " leaves control maximum travel inside the ordinary 1–60° bound", bounded_throws)

			var frozen: Dictionary = Trial.freeze({"base_id": str(base.id), "base_bytes": base_bytes, "recipe": recipe})
			_check(label + " freezes with the endpoint's compiler identity",
				bool(frozen.get("ok", false))
					and frozen.get("identity", {}).get("compiler", "") == Compiler.version_for_recipe(recipe)
					and float(frozen.get("scale", -1.0)) == scale_value,
				str(frozen.get("errors", [])))
			if not frozen.get("ok", false):
				continue
			_check(label + " frozen data retains the compiled physical model",
				_physical_projection(frozen.data.model) == _physical_projection(model))
			var session: Node = Session.new()
			session.physics_enabled = false
			session.setup("", str(frozen.data.model.id), frozen.data)
			_check(label + " frozen aircraft passes session startup and trim",
				bool(session.aircraft.get("ok", false)) and bool(session.start.get("ok", false)) and session.is_flyable(),
				str(session.get("pause_reason")))
			session.free()


func _test_persistence(base_bytes: PackedByteArray) -> void:
	var storage_root := "user://workshop_virtual_size_test_%d_%d" % [int(Time.get_unix_time_from_system()), Time.get_ticks_usec()]
	for invalid_model: Variant in [true, "virtual_similarity_v2"]:
		var invalid_recipe: Dictionary = Parameters.defaults()
		invalid_recipe["size_model"] = invalid_model
		var refused: Dictionary = Store.save_variant("Invalid size model", Catalog.DEFAULT_ID, base_bytes, invalid_recipe, "", storage_root)
		_check("storage refuses malformed or future size models", not refused.get("ok", false))
	for scale_value: float in [Parameters.MIN_SCALE, 1.0, Parameters.MAX_SCALE]:
		var recipe: Dictionary = Parameters.defaults()
		recipe.scale = scale_value
		recipe["size_model"] = Parameters.VIRTUAL_SIZE_MODEL
		var saved: Dictionary = Store.save_variant("Virtual size persistence", Catalog.DEFAULT_ID, base_bytes, recipe, "", storage_root)
		_check("explicit virtual size saves at %s" % scale_value, saved.get("ok", false), str(saved.get("errors", [])))
		if not saved.get("ok", false): continue
		var loaded: Dictionary = Store.load_variant(saved.variant.id, storage_root)
		_check("disk reload retains exact recipe and virtual compiler", loaded.get("ok", false)
			and loaded.get("variant", {}).get("recipe", {}) == recipe
			and loaded.get("variant", {}).get("compiler_version", "") == Compiler.VIRTUAL_SIZE_COMPILER_VERSION,
			str(loaded.get("errors", [])))
		if not loaded.get("ok", false): continue
		var exported: Dictionary = Bundle.export_variant(loaded.variant)
		_check("virtual build exports as a source-plus-recipe bundle", exported.get("ok", false), str(exported.get("errors", [])))
		if not exported.get("ok", false): continue
		var decoded: Dictionary = Bundle.decode(exported.bytes)
		_check("virtual bundle decodes with its exact source and recipe", decoded.get("ok", false)
			and decoded.get("payload", {}).get("base_bytes", PackedByteArray()) == base_bytes
			and decoded.get("payload", {}).get("recipe", {}) == recipe, str(decoded.get("errors", [])))
		if not decoded.get("ok", false): continue
		var restored: Dictionary = Trial.freeze(decoded.payload)
		var original: Dictionary = Trial.freeze({"base_id": Catalog.DEFAULT_ID, "base_bytes": base_bytes, "recipe": recipe})
		_check("portable virtual build restores the exact physical trial", restored.get("ok", false) and original.get("ok", false)
			and restored.get("raw_bytes", PackedByteArray()) == original.get("raw_bytes", PackedByteArray())
			and restored.get("data", {}) == original.get("data", {}), str(restored.get("errors", [])))


func _test_strict_rejections(base: Dictionary) -> void:
	for invalid_recipe: Dictionary in [
		{"scale": Parameters.MIN_SCALE, "size_model": "virtual_similarity_v2"},
		{"scale": Parameters.MIN_SCALE, "size_model": true},
		{"scale": Parameters.MAX_SCALE, "size_model": ""},
	]:
		var checked: Dictionary = Parameters.validate(invalid_recipe)
		var compiled: Dictionary = Compiler.compile(base, invalid_recipe)
		_check("invalid optional size_model is rejected before compilation",
			not bool(checked.get("ok", false)) and not bool(compiled.get("ok", false)), str(checked.get("errors", [])))
	for malformed: Dictionary in _malformed_sources(base):
		var compiled: Dictionary = Compiler.compile(malformed, {"scale": Parameters.MIN_SCALE})
		_check("malformed source, evidence, boolean, or nonfinite input cannot enter virtual scaling",
			not bool(compiled.get("ok", false)), str(compiled.get("errors", [])))


func _malformed_sources(base: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var empty_source: Dictionary = base.duplicate(true)
	empty_source.reference.wing_span.source = "  "
	out.append(empty_source)
	var boolean_quantity: Dictionary = base.duplicate(true)
	boolean_quantity.reference.wing_span.value = true
	out.append(boolean_quantity)
	var nonfinite_quantity: Dictionary = base.duplicate(true)
	nonfinite_quantity.reference.wing_span.value = NAN
	out.append(nonfinite_quantity)
	var unknown_field: Dictionary = base.duplicate(true)
	unknown_field["unrecognized_source_field"] = true
	out.append(unknown_field)
	return out


func _test_invalid_bases(base: Dictionary) -> void:
	var area_mismatch: Dictionary = base.duplicate(true)
	area_mismatch.reference.wing_area.value *= 1.1
	var cg_mismatch: Dictionary = base.duplicate(true)
	cg_mismatch.balance.plan_cg.value[0] += 0.1
	var inventory_mismatch: Dictionary = base.duplicate(true)
	inventory_mismatch.inventory[0].mass.value *= 4.0
	for entry: Array in [
		["area", area_mismatch], ["CG", cg_mismatch], ["inventory", inventory_mismatch],
	]:
		var invalid_base: Dictionary = entry[1]
		var checked: Dictionary = AircraftData.validate_and_derive(invalid_base)
		var compiled: Dictionary = Compiler.compile(invalid_base, {"scale": Parameters.MIN_SCALE})
		_check("base with inconsistent %s is refused before scaling" % str(entry[0]),
			not bool(checked.get("ok", false)) and not bool(compiled.get("ok", false)),
			"validator=%s compiler=%s" % [checked.get("errors", []), compiled.get("errors", [])])


func _test_domain_rejections(base: Dictionary) -> void:
	for domain: Dictionary in [
		{"aero.coefficients.CLa": 10.0},
		{"controls.max_throw.aileron": 10.0},
		{"not.a.transformed.quantity": 2.0},
		{"reference.wing_span": NAN},
	]:
		var checked: Dictionary = AircraftData.validate_virtual_scale(base, domain)
		_check("virtual validation rejects forged coefficient/control/unknown/nonfinite domains",
			not bool(checked.get("ok", false)), str(checked.get("errors", [])))


func _test_control_limit(base: Dictionary) -> void:
	var recipe := {"scale": Parameters.MIN_SCALE, "control_multiplier": Parameters.MAX_CONTROL_MULTIPLIER}
	var compiled: Dictionary = Compiler.compile(base, recipe)
	_check("explicit control travel transform remains within standard stock bounds",
		bool(compiled.get("ok", false)), str(compiled.get("errors", [])))
	if not compiled.get("ok", false):
		return
	for key: String in compiled.raw.controls.max_throw:
		var angle: float = float(compiled.raw.controls.max_throw[key].value)
		_check("control travel %s is still ≤ 60 degrees" % key, angle <= 60.0, str(angle))


func _test_module_refusals() -> void:
	for source_path: String in [ELECTRIC_PATH, GLOW_PATH]:
		var base := _read(source_path)
		var label := "electric" if source_path == ELECTRIC_PATH else "finite-glow"
		var checked: Dictionary = AircraftData.validate_and_derive(base)
		_check(label + " source remains strictly valid", bool(checked.get("ok", false)), str(checked.get("errors", [])))
		if not checked.get("ok", false):
			continue
		var refused: Dictionary = Compiler.compile(base, {"scale": Parameters.MIN_SCALE})
		_check(label + " unsupported virtual size transform is refused", not bool(refused.get("ok", false))
			and str(refused.get("errors", [])).contains("scale"), str(refused.get("errors", [])))


func _read(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func _liquid_kg(model: Dictionary) -> float:
	var total := 0.0
	for tank: Dictionary in model.get("fuel_system", {}).get("tanks", []):
		total += float(tank.liquid_mass_kg)
	return total


func _contains_key(value: Variant, key: String) -> bool:
	if value is Dictionary:
		if value.has(key):
			return true
		for child: Variant in value.values():
			if _contains_key(child, key):
				return true
	elif value is Array:
		for child: Variant in value:
			if _contains_key(child, key):
				return true
	return false


func _physical_projection(value: Variant) -> Variant:
	if value is Dictionary:
		var result: Dictionary = {}
		for key: Variant in value.keys():
			var name := str(key)
			if name == "id" or name == "data_sha256" or name == "wheel_profile" or name.ends_with("_provenance"):
				continue
			result[key] = _physical_projection(value[key])
		return result
	if value is Array:
		var result: Array = []
		for element: Variant in value:
			result.append(_physical_projection(element))
		return result
	return value


func _finish() -> void:
	print("Workshop virtual size: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
