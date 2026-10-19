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
const MIN_TANK_CAPACITY_MULTIPLIER := 0.5
const MAX_TANK_CAPACITY_MULTIPLIER := 2.0
const MASS_POLICIES := ["constant_wing_loading", "geometric"]
const DEFINITIONS_FORMAT := "openrc-aircraft-workshop-parameter-definitions"
const DEFINITIONS_VERSION := 1
const ALLOWED_KEYS := [
	"scale", "mass_policy", "weight_multiplier", "power_multiplier", "control_multiplier",
	"tank_capacity_multiplier", "id", "name",
	"mass_edits",
]


static func defaults() -> Dictionary:
	return {
		"scale": 1.0,
		"mass_policy": "constant_wing_loading",
		"weight_multiplier": 1.0,
		"power_multiplier": 1.0,
		"control_multiplier": 1.0,
		"tank_capacity_multiplier": 1.0,
	}


## Shared physical parameter contract for Workshop controls and bounded tools.
## With no compiler capabilities the definitions remain descriptive; `available` is null
## because support cannot be inferred without a validated aircraft base.
static func definitions(capabilities: Dictionary = {}) -> Dictionary:
	var parameters: Array = [
		{
			"key": "scale", "label": "Virtual scale", "capability": "scale",
			"minimum": MIN_SCALE, "maximum": MAX_SCALE, "default": 1.0,
			"unit": "ratio", "kind": "number", "step": 0.05,
			"operation": "Virtual geometry and mass similarity transform.",
		},
		{
			"key": "mass_policy", "label": "Mass policy", "capability": "scale",
			"minimum": null, "maximum": null, "default": "constant_wing_loading",
			"unit": "", "kind": "enum", "options": MASS_POLICIES.duplicate(),
			"operation": "Selects the mass ratio law used by virtual scale.",
		},
		{
			"key": "weight_multiplier", "label": "Weight multiplier", "capability": "weight",
			"minimum": MIN_WEIGHT_MULTIPLIER, "maximum": MAX_WEIGHT_MULTIPLIER, "default": 1.0,
			"unit": "ratio", "kind": "number", "step": 0.05,
			"operation": "Uniform inventory-mass multiplier.",
		},
		{
			"key": "power_multiplier", "label": "Power multiplier", "capability": "power",
			"minimum": MIN_POWER_MULTIPLIER, "maximum": MAX_POWER_MULTIPLIER, "default": 1.0,
			"unit": "ratio", "kind": "number", "step": 0.05,
			"operation": "Prescribed-RPM propulsion evaluator multiplier.",
		},
		{
			"key": "control_multiplier", "label": "Control travel multiplier", "capability": "controls",
			"minimum": MIN_CONTROL_MULTIPLIER, "maximum": MAX_CONTROL_MULTIPLIER, "default": 1.0,
			"unit": "ratio", "kind": "number", "step": 0.05,
			"operation": "Conventional physical surface travel multiplier.",
		},
		{
			"key": "tank_capacity_multiplier", "label": "Tank capacity multiplier", "capability": "tank_capacity",
			"minimum": MIN_TANK_CAPACITY_MULTIPLIER, "maximum": MAX_TANK_CAPACITY_MULTIPLIER, "default": 1.0,
			"unit": "ratio", "kind": "number", "step": 0.05,
			"operation": "Changes tank capacity and tank dimensions under the FUEL-11a policy.",
		},
	]
	for item_variant: Variant in parameters:
		var item: Dictionary = item_variant
		var capability: String = str(item["capability"])
		if capabilities.is_empty():
			item["available"] = null
			item["unavailable_reason"] = ""
		elif capabilities.has(capability) and typeof(capabilities[capability]) == TYPE_BOOL:
			item["available"] = bool(capabilities[capability])
			item["unavailable_reason"] = "" if bool(capabilities[capability]) else str(capabilities.get("note", "Unsupported for this aircraft module combination."))
		else:
			item["available"] = false
			item["unavailable_reason"] = "Compiler capability '%s' is unavailable." % capability
	return {"format": DEFINITIONS_FORMAT, "version": DEFINITIONS_VERSION, "parameters": parameters}


static func validate(recipe: Dictionary) -> Dictionary:
	var errors := PackedStringArray()
	var values := defaults()
	for key: Variant in recipe.keys():
		if key not in ALLOWED_KEYS:
			errors.append("recipe.%s: unknown key" % str(key))
	for key: String in ["scale", "weight_multiplier", "power_multiplier", "control_multiplier", "tank_capacity_multiplier"]:
		if not recipe.has(key):
			continue
		var candidate: Variant = recipe[key]
		if typeof(candidate) not in [TYPE_INT, TYPE_FLOAT]:
			errors.append("recipe.%s: expected a finite number" % key)
			continue
		var number := float(candidate)
		if not is_finite(number):
			errors.append("recipe.%s: expected a finite number" % key)
			continue
		values[key] = number
	var bounds := {
		"scale": [MIN_SCALE, MAX_SCALE],
		"weight_multiplier": [MIN_WEIGHT_MULTIPLIER, MAX_WEIGHT_MULTIPLIER],
		"power_multiplier": [MIN_POWER_MULTIPLIER, MAX_POWER_MULTIPLIER],
		"control_multiplier": [MIN_CONTROL_MULTIPLIER, MAX_CONTROL_MULTIPLIER],
		"tank_capacity_multiplier": [MIN_TANK_CAPACITY_MULTIPLIER, MAX_TANK_CAPACITY_MULTIPLIER],
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
	# Optional extension: absence/empty edits preserve every legacy recipe identity.
	if recipe.has("mass_edits"):
		var edits: Variant = recipe.mass_edits
		if not edits is Array or edits.size() > 32:
			errors.append("recipe.mass_edits: expected at most 32 measured component masses")
		else:
			var seen := {}
			for edit: Variant in edits:
				if not edit is Dictionary or edit.size() != 3 or not edit.has_all(["id", "mass_kg", "source"]):
					errors.append("recipe.mass_edits: expected only id, mass_kg and source")
					continue
				if typeof(edit.id) != TYPE_STRING or edit.id.is_empty() or edit.id.length() > 80 or seen.has(edit.id):
					errors.append("recipe.mass_edits: component IDs must be unique stable IDs")
				else: seen[edit.id] = true
				if typeof(edit.mass_kg) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(edit.mass_kg)) or float(edit.mass_kg) < 0.001 or float(edit.mass_kg) > 5.0:
					errors.append("recipe.mass_edits: measured mass must be within [0.001, 5] kg")
				if typeof(edit.source) != TYPE_STRING or edit.source.strip_edges().is_empty() or edit.source.length() > 256:
					errors.append("recipe.mass_edits: provide a measurement source of at most 256 characters")
			if errors.is_empty() and not edits.is_empty(): values.mass_edits = edits.duplicate(true)
	return {"ok": errors.is_empty(), "errors": errors, "values": values}
