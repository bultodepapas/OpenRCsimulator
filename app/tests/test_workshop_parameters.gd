extends SceneTree

const Parameters := preload("res://workshop/parameters.gd")
const Compiler := preload("res://workshop/compiler.gd")
const STIK_PATH := "res://data/aircraft/jensen_ugly_stik_60.json"
const GLOW_PATH := "res://data/aircraft/gp_extra_300s_60.json"

var checks := 0
var failures := 0


func _initialize() -> void:
	var plain: Dictionary = Parameters.definitions()
	_check("definition envelope is versioned", plain.get("format", "") == Parameters.DEFINITIONS_FORMAT
		and plain.get("version", 0) == Parameters.DEFINITIONS_VERSION)
	var expected_keys := ["scale", "mass_policy", "weight_multiplier", "power_multiplier",
		"control_multiplier", "tank_capacity_multiplier"]
	var by_key: Dictionary = _by_key(plain.get("parameters", []))
	_check("every accepted physical parameter has one shared definition", by_key.keys().size() == expected_keys.size()
		and by_key.keys().all(func(key: Variant) -> bool: return key in expected_keys))
	for key: String in expected_keys:
		_check("metadata includes labels and operation for %s" % key, by_key.has(key)
			and not str(by_key.get(key, {}).get("label", "")).is_empty()
			and not str(by_key.get(key, {}).get("operation", "")).is_empty())
		if by_key.has(key):
			_check("availability stays unknown without a base for %s" % key,
				by_key[key].get("available", false) == null)
			_check("definition default matches the physical recipe default for %s" % key,
				Parameters.validate({}).values.get(key) == by_key[key].get("default"))
			if by_key[key].get("kind", "") == "number":
				var low: float = float(by_key[key].minimum)
				var high: float = float(by_key[key].maximum)
				_check("metadata minimum accepted by validator for %s" % key,
					Parameters.validate({key: low}).ok)
				_check("metadata maximum accepted by validator for %s" % key,
					Parameters.validate({key: high}).ok)
				_check("value below metadata minimum rejected for %s" % key,
					not Parameters.validate({key: low - 0.001}).ok)
				_check("value above metadata maximum rejected for %s" % key,
					not Parameters.validate({key: high + 0.001}).ok)
				_check("boolean cannot masquerade as a number for %s" % key,
					not Parameters.validate({key: true}).ok)
				_check("non-finite numeric value rejected for %s" % key,
					not Parameters.validate({key: NAN}).ok)
		_check("mass policy metadata exposes every allowed policy",
			by_key.mass_policy.options == Parameters.MASS_POLICIES
			and Parameters.validate({"mass_policy": "geometric"}).ok
			and not Parameters.validate({"mass_policy": "invented"}).ok)

	var altered: Dictionary = Parameters.definitions()
	altered.parameters[1].options.clear()
	_check("definition call returns detached metadata", not Parameters.definitions().parameters[1].options.is_empty())

	var stik: Dictionary = _read(STIK_PATH)
	var glow: Dictionary = _read(GLOW_PATH)
	_check("capability fixtures load", not stik.is_empty() and not glow.is_empty())
	if not stik.is_empty() and not glow.is_empty():
		for base: Dictionary in [stik, glow]:
			var capabilities: Dictionary = Compiler.capabilities(base)
			var mapped: Dictionary = _by_key(Parameters.definitions(capabilities).parameters)
			for item_key: String in expected_keys:
				var capability: String = str(mapped[item_key].capability)
				_check("availability for %s follows compiler capability" % item_key,
					mapped[item_key].available == capabilities.get(capability, false))
			for capability_key: String in ["scale", "weight", "power", "controls", "tank_capacity"]:
				_check("capability fixture has boolean %s" % capability_key,
					typeof(capabilities.get(capability_key, null)) == TYPE_BOOL)
		var unsupported: Dictionary = _by_key(Parameters.definitions(Compiler.capabilities(glow)).parameters)
		if not Compiler.capabilities(glow).get("scale", true):
			_check("unsupported transform includes compiler explanation",
				not bool(unsupported.scale.available)
				and not str(unsupported.scale.unavailable_reason).is_empty())

	var malformed_caps: Dictionary = _by_key(Parameters.definitions({"scale": "yes"}).parameters)
	_check("malformed capability is unavailable with reason", malformed_caps.scale.available == false
		and not str(malformed_caps.scale.unavailable_reason).is_empty())
	print("Workshop parameter metadata: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func _read(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func _by_key(parameters: Array) -> Dictionary:
	var result: Dictionary = {}
	for item: Variant in parameters:
		if item is Dictionary:
			result[str(item.get("key", ""))] = item
	return result


func _check(label: String, condition: bool, detail: String = "") -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL ", label, " ", detail)
