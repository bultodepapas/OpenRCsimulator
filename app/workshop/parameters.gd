extends RefCounted
class_name WorkshopParameters

const MIN_SCALE := 0.5
const MAX_SCALE := 2.0
const MIN_WEIGHT_MULTIPLIER := 0.5
const MAX_WEIGHT_MULTIPLIER := 2.0
const MIN_POWER_MULTIPLIER := 0.5
const MAX_POWER_MULTIPLIER := 2.0
const MIN_CONTROL_MULTIPLIER := 0.5
const MAX_CONTROL_MULTIPLIER := 1.5
const CONTROL_SURFACES := ["aileron", "elevator", "rudder"]
const MASS_POLICIES := ["constant_wing_loading", "geometric"]
const ALLOWED_KEYS := [
	"scale", "mass_policy", "weight_multiplier", "power_multiplier", "control_multiplier",
	"control_multiplier_aileron", "control_multiplier_elevator", "control_multiplier_rudder",
	"id", "name",
]


static func defaults() -> Dictionary:
	return {
		"scale": 1.0,
		"mass_policy": "constant_wing_loading",
		"weight_multiplier": 1.0,
		"power_multiplier": 1.0,
		"control_multiplier": 1.0,
	}


static func validate(recipe: Dictionary) -> Dictionary:
	var errors := PackedStringArray()
	var values := defaults()
	for key: Variant in recipe.keys():
		if key not in ALLOWED_KEYS:
			errors.append("recipe.%s: unknown key" % str(key))
	var numeric_keys := [
		"scale", "weight_multiplier", "power_multiplier", "control_multiplier",
		"control_multiplier_aileron", "control_multiplier_elevator", "control_multiplier_rudder",
	]
	for key: String in numeric_keys:
		if not recipe.has(key):
			continue
		var candidate: Variant = recipe[key]
		if typeof(candidate) not in [TYPE_INT, TYPE_FLOAT]:
			errors.append("recipe.%s: expected a finite number" % key)
			continue
		var number := float(candidate)
		if not is_finite(number):
			errors.append("recipe.%s: expected a finite number" % key)
		values[key] = number
	var bounds := {
		"scale": [MIN_SCALE, MAX_SCALE],
		"weight_multiplier": [MIN_WEIGHT_MULTIPLIER, MAX_WEIGHT_MULTIPLIER],
		"power_multiplier": [MIN_POWER_MULTIPLIER, MAX_POWER_MULTIPLIER],
		"control_multiplier": [MIN_CONTROL_MULTIPLIER, MAX_CONTROL_MULTIPLIER],
		"control_multiplier_aileron": [MIN_CONTROL_MULTIPLIER, MAX_CONTROL_MULTIPLIER],
		"control_multiplier_elevator": [MIN_CONTROL_MULTIPLIER, MAX_CONTROL_MULTIPLIER],
		"control_multiplier_rudder": [MIN_CONTROL_MULTIPLIER, MAX_CONTROL_MULTIPLIER],
	}
	for key: String in bounds:
		if not recipe.has(key) or typeof(recipe[key]) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(recipe[key])):
			continue
		var bound: Array = bounds[key]
		var number := float(values[key])
		if number < float(bound[0]) or number > float(bound[1]):
			errors.append("recipe.%s: %s outside [%s, %s]" % [key, str(number), str(bound[0]), str(bound[1])])
	var mass_policy: Variant = recipe.get("mass_policy", values.mass_policy)
	if typeof(mass_policy) != TYPE_STRING or mass_policy not in MASS_POLICIES:
		errors.append("recipe.mass_policy: expected one of %s" % str(MASS_POLICIES))
	else:
		values.mass_policy = mass_policy
	for key: String in ["id", "name"]:
		if not recipe.has(key):
			continue
		var text: Variant = recipe[key]
		if typeof(text) != TYPE_STRING or str(text).strip_edges().is_empty():
			errors.append("recipe.%s: expected a nonempty string" % key)
		else:
			values[key] = str(text).strip_edges()
	return {"ok": errors.is_empty(), "errors": errors, "values": values}
