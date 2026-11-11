extends RefCounted
## Authoring record of the Aircraft Creator (AC-06): `openrc-creator-definition v1`.
##
## What the player states about a new airplane, before any physics: SI units (m, kg, s, degrees for
## throws, thrust angles and wing dihedral), positions in the leading-edge frame [x_aft, y_right, z_up]
## measured from the wing leading edge at the centreline. The record is closed: unknown keys are refused.
## `wing.dihedral_deg` is the geometric dihedral of each wing panel: the angle its plane rises from the
## horizontal, from the root outward, in degrees (0 = flat wing).
## The power package's hardware (motor, propeller, ESC, battery) is never listed in `inventory`.
## A valid definition is not yet a flyable aircraft: the compiler and the package domain decide that.

const R := preload("res://workshop/creator/result.gd")
const Limits := preload("res://workshop/creator/limits.gd")
const Packages := preload("res://workshop/creator/packages.gd")

const FORMAT := "openrc-creator-definition v1"
const AIRCRAFT_ID_PREFIX := "user-aircraft-"
## Placeholder identity of template(): the caller replaces it with a fresh UUID for a real aircraft.
const TEMPLATE_UUID := "00000000-0000-4000-8000-000000000000"
const UUID_PATTERN := "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"
## Same grammar as physics/physical_identity.gd: player IDs become physical inventory IDs unchanged.
const ID_PATTERN := "^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$"
const MAX_ID_LENGTH := 80
## Prefixes of the compiler's own hull, surface and propulsion IDs.
const RESERVED_ID_PREFIXES := ["probe_", "surface_", "propulsion_"]
const ITEM_KINDS := ["measured", "estimated", "manual"]

const STEP_IMPORT := "import"
const STEP_ORIENT := "orient_size"
const STEP_LAYOUT := "aircraft_layout"
const STEP_BALANCE := "weight_balance"
const STEP_POWER := "power_mount"
const STEP_CONTROLS := "controls_ground"
const STEP_PAINT := "paint_skins"
const STEP_REVIEW := "review_test"

const KEYS := ["format", "aircraft_uuid", "airframe_package", "power_package", "wing", "horizontal_tail",
	"vertical_tail", "fuselage", "inventory", "equipment", "controls", "battery"]
const ITEM_KEYS := ["id", "name", "mass", "position", "size", "kind"]
## Optional `evidence` object: field path -> kind. A field without an entry is `manual` (typed by
## the player). `estimated` marks a starting value the player has not confirmed: a number scaled
## from the reference trainer or the model's extent must never be recorded as the player's own.
const EVIDENCE_KINDS := ["manual", "measured", "estimated"]
const EVIDENCE_PATHS := ["wing/span", "wing/root_chord", "wing/tip_chord", "wing/dihedral_deg",
	"horizontal_tail/span", "horizontal_tail/chord", "horizontal_tail/position",
	"vertical_tail/height", "vertical_tail/chord", "vertical_tail/position",
	"fuselage/nose_x", "fuselage/tail_x", "fuselage/width", "fuselage/height", "fuselage/center_z",
	"equipment/hub_position", "equipment/battery_position", "equipment/esc_position", "equipment/thrust_angles_deg",
	"controls/aileron_deg", "controls/elevator_deg", "controls/rudder_deg", "controls/servo_time_s",
	"battery/initial_soc"]
## Input sanity ranges, taken from the flight loader's own quantity bounds where one exists.
## They only refuse values no record could carry; the package domain is narrower.
const POSITION_LIMIT := 2.0
const RANGES := {
	"wing/span": [0.3, 4.0], "wing/root_chord": [0.05, 1.0], "wing/tip_chord": [0.02, 1.0],
	"wing/dihedral_deg": [-5.0, 15.0],
	"horizontal_tail/span": [0.05, 2.0], "horizontal_tail/chord": [0.02, 1.0],
	"vertical_tail/height": [0.02, 1.0], "vertical_tail/chord": [0.02, 1.0],
	"fuselage/nose_x": [-2.0, 0.0], "fuselage/tail_x": [0.0, 2.0],
	"fuselage/width": [0.01, 1.0], "fuselage/height": [0.01, 1.0], "fuselage/center_z": [-1.0, 1.0],
	"controls/aileron_deg": [1.0, 60.0], "controls/elevator_deg": [1.0, 60.0], "controls/rudder_deg": [1.0, 60.0],
	"controls/servo_time_s": [0.01, 2.0],
	"battery/initial_soc": [0.0, 1.0],
}
const ITEM_MASS_RANGE := [0.001, 5.0]
const ITEM_SIZE_RANGE := [0.0, 4.0]
const THRUST_ANGLE_LIMIT := 10.0


## A complete definition of a 1.5 m span, 2 kg electric trainer that compiles and flies: the "Use
## starting values" record. Its inventory is the package's own airframe mass proposal; every number is
## an estimate. The caller replaces TEMPLATE_UUID.
static func template() -> Dictionary:
	var definition := {
		"format": FORMAT,
		"aircraft_uuid": TEMPLATE_UUID,
		"airframe_package": "conventional-trainer-estimated-v1",
		"power_package": "electric-4s-800kv-apc12x6-estimated-v1",
		"wing": {"span": 1.5, "root_chord": 0.3, "tip_chord": 0.3, "dihedral_deg": 5.0},
		"horizontal_tail": {"span": 0.56, "chord": 0.17, "position": [0.7, 0.0, 0.0]},
		"vertical_tail": {"height": 0.22, "chord": 0.2, "position": [0.69, 0.0, 0.02]},
		"fuselage": {"nose_x": -0.275, "tail_x": 0.89, "width": 0.1, "height": 0.12, "center_z": -0.03},
		"inventory": [],
		"equipment": {
			"hub_position": [-0.34, 0.0, -0.03],
			"battery_position": [-0.19, 0.0, -0.045],
			"esc_position": [-0.235, 0.0, -0.03],
			"thrust_angles_deg": [0.0, 0.0],
		},
		"controls": {"aileron_deg": 20.0, "elevator_deg": 20.0, "rudder_deg": 25.0, "servo_time_s": 0.14},
		"battery": {"initial_soc": 0.95},
	}
	definition["inventory"] = propose_airframe_inventory(definition)
	return definition


## Result envelope. On success `value` is a deep copy with every number as float (the form whose bytes
## give the definition identity). Every problem is reported with its field path and wizard step.
static func validate_complete(definition: Dictionary) -> Dictionary:
	var out: Array = []
	var stated := definition.duplicate()
	stated.erase("evidence")
	_closed(out, stated, "", KEYS, STEP_REVIEW)
	_evidence(out, definition)
	if definition.has("format") and definition.get("format") != FORMAT:
		out.append(R.diagnostic(R.FIELD_INVALID, "The definition format must be %s.", "format", STEP_REVIEW, [FORMAT]))
	if definition.has("aircraft_uuid") and not _matches(definition.get("aircraft_uuid"), UUID_PATTERN):
		out.append(R.diagnostic(R.FIELD_INVALID, "The aircraft identity must be a lowercase version 4 UUID.",
			"aircraft_uuid", STEP_REVIEW))
	_package(out, definition, "airframe_package", STEP_LAYOUT)
	var power := _package(out, definition, "power_package", STEP_POWER)

	var wing := _object(out, definition, "wing", ["span", "root_chord", "tip_chord", "dihedral_deg"], STEP_LAYOUT)
	_range(out, wing, "wing", "span", STEP_LAYOUT)
	var root := _range(out, wing, "wing", "root_chord", STEP_LAYOUT)
	var tip := _range(out, wing, "wing", "tip_chord", STEP_LAYOUT)
	if not is_nan(root) and not is_nan(tip) and tip > root:
		out.append(R.diagnostic(R.FIELD_INVALID, "The tip chord must not exceed the root chord.", "wing/tip_chord", STEP_LAYOUT))
	_range(out, wing, "wing", "dihedral_deg", STEP_LAYOUT)
	var tail := _object(out, definition, "horizontal_tail", ["span", "chord", "position"], STEP_LAYOUT)
	_range(out, tail, "horizontal_tail", "span", STEP_LAYOUT)
	_range(out, tail, "horizontal_tail", "chord", STEP_LAYOUT)
	_centre_point(out, tail, "horizontal_tail/position")
	var fin := _object(out, definition, "vertical_tail", ["height", "chord", "position"], STEP_LAYOUT)
	_range(out, fin, "vertical_tail", "height", STEP_LAYOUT)
	_range(out, fin, "vertical_tail", "chord", STEP_LAYOUT)
	_centre_point(out, fin, "vertical_tail/position")
	var fuselage := _object(out, definition, "fuselage", ["nose_x", "tail_x", "width", "height", "center_z"], STEP_LAYOUT)
	var nose := _range(out, fuselage, "fuselage", "nose_x", STEP_LAYOUT)
	var tail_end := _range(out, fuselage, "fuselage", "tail_x", STEP_LAYOUT)
	if nose == 0.0:
		out.append(R.diagnostic(R.FIELD_INVALID, "The fuselage nose must be ahead of the wing leading edge (negative x).",
			"fuselage/nose_x", STEP_LAYOUT))
	if tail_end == 0.0:
		out.append(R.diagnostic(R.FIELD_INVALID, "The fuselage tail must be behind the wing leading edge (positive x).",
			"fuselage/tail_x", STEP_LAYOUT))
	for name: String in ["width", "height", "center_z"]:
		_range(out, fuselage, "fuselage", name, STEP_LAYOUT)

	_inventory(out, definition, power)

	var equipment := _object(out, definition, "equipment",
		["hub_position", "battery_position", "esc_position", "thrust_angles_deg"], STEP_POWER)
	for name: String in ["hub_position", "battery_position", "esc_position"]:
		_vector(out, equipment, "equipment/" + name, name, 3, -POSITION_LIMIT, POSITION_LIMIT, STEP_POWER)
	_vector(out, equipment, "equipment/thrust_angles_deg", "thrust_angles_deg", 2, -THRUST_ANGLE_LIMIT, THRUST_ANGLE_LIMIT, STEP_POWER)
	var controls := _object(out, definition, "controls", ["aileron_deg", "elevator_deg", "rudder_deg", "servo_time_s"], STEP_CONTROLS)
	for name: String in ["aileron_deg", "elevator_deg", "rudder_deg", "servo_time_s"]:
		_range(out, controls, "controls", name, STEP_CONTROLS)
	var battery := _object(out, definition, "battery", ["initial_soc"], STEP_POWER)
	if _range(out, battery, "battery", "initial_soc", STEP_POWER) == 0.0:
		out.append(R.diagnostic(R.FIELD_INVALID, "The starting charge must be above zero.", "battery/initial_soc", STEP_POWER))
	if R.has_errors(out):
		return R.fail_all(out)
	return R.ok(_normalized(definition))


## The inventory with the package's estimated airframe items filled in from the geometry (wing, fuselage,
## tail surfaces, servos, receiver, hardware; areal densities and unit masses from the airframe package).
## Items the player measured or entered keep their place and values; an earlier estimate with a proposal
## ID is refreshed in place; missing proposal items are appended. Returns the current inventory unchanged
## (or empty) while the geometry or package is not usable.
static func propose_airframe_inventory(definition: Dictionary) -> Array:
	var current: Array = []
	if typeof(definition.get("inventory")) == TYPE_ARRAY:
		current = (definition.get("inventory") as Array).duplicate(true)
	var package: Dictionary = Packages.airframe(definition.get("airframe_package"))
	if not package.ok or typeof(definition.get("fuselage")) != TYPE_DICTIONARY:
		return current
	var proposed: Array = Packages.airframe_items(package.value, Packages.geometry(definition), definition.get("fuselage"))
	if proposed.is_empty():
		return current
	var by_id := {}
	for item: Dictionary in proposed:
		by_id[item["id"]] = item
	var placed := {}
	for index: int in current.size():
		if typeof(current[index]) != TYPE_DICTIONARY:
			continue
		var existing: Dictionary = current[index]
		var id: Variant = existing.get("id")
		if typeof(id) != TYPE_STRING or not by_id.has(id):
			continue
		placed[id] = true
		if existing.get("kind") == "estimated":
			current[index] = by_id[id]
	for item: Dictionary in proposed:
		if not placed.has(item["id"]):
			current.append(item)
	return current


static func aircraft_id(uuid: String) -> String:
	return AIRCRAFT_ID_PREFIX + uuid


static func _package(out: Array, definition: Dictionary, key: String, step: String) -> Dictionary:
	if not definition.has(key):
		return {}
	var resolved: Dictionary = Packages.airframe(definition.get(key)) if key == "airframe_package" \
		else Packages.power(definition.get(key))
	if not resolved.ok:
		out.append_array(resolved.diagnostics)
		return {}
	return resolved.value


static func _inventory(out: Array, definition: Dictionary, power: Dictionary) -> void:
	if not definition.has("inventory"):
		return
	if typeof(definition.get("inventory")) != TYPE_ARRAY:
		out.append(R.diagnostic(R.FIELD_INVALID, "The inventory must be a list of items.", "inventory", STEP_BALANCE))
		return
	var items: Array = definition.get("inventory")
	var reserved: PackedStringArray = Packages.hardware_ids(power) if not power.is_empty() else PackedStringArray()
	# The power package adds its own items to the same physical inventory.
	if items.size() + reserved.size() > Limits.INVENTORY_ITEMS:
		out.append(R.diagnostic(R.FIELD_INVALID, "The inventory holds %s items; the limit is %s.", "inventory", STEP_BALANCE,
			[items.size(), Limits.INVENTORY_ITEMS - reserved.size()]))
		return
	var seen := {}
	for index: int in items.size():
		var path := "inventory/%d" % index
		if typeof(items[index]) != TYPE_DICTIONARY:
			out.append(R.diagnostic(R.FIELD_INVALID, "An inventory item must be an object.", path, STEP_BALANCE))
			continue
		var item: Dictionary = items[index]
		_closed(out, item, path, ITEM_KEYS, STEP_BALANCE)
		if item.has("id"):
			var id: Variant = item.get("id")
			if typeof(id) != TYPE_STRING or (id as String).length() > MAX_ID_LENGTH or not _matches(id, ID_PATTERN):
				out.append(R.diagnostic(R.FIELD_INVALID,
					"An item ID is lowercase snake_case, starts with a letter and has at most 80 characters.", path + "/id", STEP_BALANCE))
			elif reserved.has(id) or _reserved_prefix(id):
				out.append(R.diagnostic(R.FIELD_INVALID, "The ID %s belongs to the power package or the compiler.",
					path + "/id", STEP_BALANCE, [id]))
			elif seen.has(id):
				out.append(R.diagnostic(R.FIELD_INVALID, "The ID %s is used by more than one item.", path + "/id", STEP_BALANCE, [id]))
			else:
				seen[id] = true
		if item.has("name"):
			var name: Variant = item.get("name")
			if typeof(name) != TYPE_STRING or (name as String).strip_edges().is_empty() \
					or (name as String).length() > Limits.NAME_CHARACTERS:
				out.append(R.diagnostic(R.FIELD_INVALID, "An item name is text of 1 to %s characters.", path + "/name",
					STEP_BALANCE, [Limits.NAME_CHARACTERS]))
		if item.has("kind") and not (typeof(item.get("kind")) == TYPE_STRING and ITEM_KINDS.has(item.get("kind"))):
			out.append(R.diagnostic(R.FIELD_INVALID, "An item is measured, estimated or manual.", path + "/kind", STEP_BALANCE))
		if item.has("mass"):
			_bounded(out, item.get("mass"), path + "/mass", ITEM_MASS_RANGE[0], ITEM_MASS_RANGE[1], STEP_BALANCE)
		_vector(out, item, path + "/position", "position", 3, -POSITION_LIMIT, POSITION_LIMIT, STEP_BALANCE)
		_vector(out, item, path + "/size", "size", 3, ITEM_SIZE_RANGE[0], ITEM_SIZE_RANGE[1], STEP_BALANCE)


static func _reserved_prefix(id: String) -> bool:
	for prefix: String in RESERVED_ID_PREFIXES:
		if id.begins_with(prefix):
			return true
	return false


## The optional evidence object: known field paths and known kinds only.
static func _evidence(out: Array, definition: Dictionary) -> void:
	if not definition.has("evidence"):
		return
	var evidence: Variant = definition.get("evidence")
	if typeof(evidence) != TYPE_DICTIONARY:
		out.append(R.diagnostic(R.FIELD_INVALID, "This value must be an object.", "evidence", STEP_REVIEW))
		return
	for key: Variant in (evidence as Dictionary):
		if not EVIDENCE_PATHS.has(str(key)) or not EVIDENCE_KINDS.has(evidence[key]):
			out.append(R.diagnostic(R.FIELD_INVALID, "This field is not part of the definition.", "evidence/" + str(key), STEP_REVIEW))


## Evidence kind of one player field: `manual` unless the definition says otherwise.
static func evidence_kind(definition: Dictionary, path: String) -> String:
	var evidence: Variant = definition.get("evidence")
	if typeof(evidence) == TYPE_DICTIONARY and EVIDENCE_KINDS.has((evidence as Dictionary).get(path)):
		return str(evidence[path])
	return "manual"


## Source text of one player field for the emitted record, honest about who supplied the value.
static func evidence_source(definition: Dictionary, path: String) -> String:
	match evidence_kind(definition, path):
		"measured":
			return "Aircraft Creator definition: %s (measured by the player)" % path
		"estimated":
			return "Aircraft Creator definition: %s (estimated starting value scaled from the reference trainer and the model extent; not confirmed by the player)" % path
	return "Aircraft Creator definition: %s (player-entered)" % path


## Reports missing and unknown keys of one object.
static func _closed(out: Array, object: Dictionary, path: String, keys: Array, step: String) -> void:
	for key: String in keys:
		if not object.has(key):
			out.append(R.diagnostic(R.FIELD_INVALID, "This value is required.", _join(path, key), step))
	for key: Variant in object:
		if not keys.has(str(key)):
			out.append(R.diagnostic(R.FIELD_INVALID, "This field is not part of the definition.", _join(path, str(key)), step))


## A required child object with a closed key set; {} (after a diagnostic) when it is absent or not an object.
static func _object(out: Array, definition: Dictionary, key: String, keys: Array, step: String) -> Dictionary:
	if not definition.has(key):
		return {}
	if typeof(definition.get(key)) != TYPE_DICTIONARY:
		out.append(R.diagnostic(R.FIELD_INVALID, "This value must be an object.", key, step))
		return {}
	var object: Dictionary = definition.get(key)
	_closed(out, object, key, keys, step)
	return object


## A number inside RANGES[group/name]; NAN when absent (already reported) or refused.
static func _range(out: Array, object: Dictionary, group: String, name: String, step: String) -> float:
	if not object.has(name):
		return NAN
	var path := group + "/" + name
	var bounds: Array = RANGES[path]
	return _bounded(out, object.get(name), path, bounds[0], bounds[1], step)


static func _bounded(out: Array, value: Variant, path: String, low: float, high: float, step: String) -> float:
	var number := Packages.finite(value)
	if is_nan(number):
		out.append(R.diagnostic(R.FIELD_INVALID, "This value must be a finite number.", path, step))
		return NAN
	if number < low or number > high:
		out.append(R.diagnostic(R.FIELD_INVALID, "This value must be between %s and %s.", path, step, [low, high]))
		return NAN
	return number


static func _vector(out: Array, object: Dictionary, path: String, name: String, count: int, low: float, high: float,
		step: String) -> PackedFloat64Array:
	if not object.has(name):
		return PackedFloat64Array()
	var values := Packages.vector(object.get(name), count)
	if values.is_empty():
		out.append(R.diagnostic(R.FIELD_INVALID, "This value must be a list of %s finite numbers.", path, step, [count]))
		return values
	for value: float in values:
		if value < low or value > high:
			out.append(R.diagnostic(R.FIELD_INVALID, "Each number must be between %s and %s.", path, step, [low, high]))
			return PackedFloat64Array()
	return values


## A tail position: three numbers on the centreline (y = 0).
static func _centre_point(out: Array, object: Dictionary, path: String) -> void:
	var point := _vector(out, object, path, "position", 3, -POSITION_LIMIT, POSITION_LIMIT, STEP_LAYOUT)
	if point.size() == 3 and point[1] != 0.0:
		out.append(R.diagnostic(R.FIELD_INVALID, "The tail sits on the centreline: its y position must be 0.", path, STEP_LAYOUT))


static func _matches(value: Variant, pattern: String) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	var found := RegEx.create_from_string(pattern).search(value)
	return found != null and found.get_string() == value


static func _join(path: String, key: String) -> String:
	return key if path.is_empty() else path + "/" + key


## Deep copy with String keys and every number as float, so equal definitions give equal bytes.
static func _normalized(node: Variant) -> Variant:
	match typeof(node):
		TYPE_INT:
			return float(node)
		TYPE_STRING_NAME:
			return str(node)
		TYPE_ARRAY:
			var items := []
			for item: Variant in (node as Array):
				items.append(_normalized(item))
			return items
		TYPE_DICTIONARY:
			var fields := {}
			for key: Variant in (node as Dictionary):
				fields[str(key)] = _normalized(node[key])
			return fields
	return node
