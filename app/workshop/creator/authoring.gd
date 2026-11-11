extends RefCounted
## Mutable authoring document of one Aircraft Creator session (AC-10).
##
## Holds the admitted source, the placement and every typed field with its raw text. The UI only
## sends intents and reads state: it never infers physics. A required value starts unresolved —
## no numeric zero, assumed unit or hidden default. Invalid text stays visible, never replaces the
## last accepted value, and blocks compilation until corrected.

signal changed

const R := preload("res://workshop/creator/result.gd")
const Limits := preload("res://workshop/creator/limits.gd")
const Placement := preload("res://workshop/creator/placement.gd")
const Definition := preload("res://workshop/creator/definition.gd")
const Compiler := preload("res://workshop/creator/compiler.gd")
const CreatorBytes := preload("res://workshop/creator/bytes.gd")
const InspectedSource := preload("res://workshop/creator/inspected_source.gd")

const STEPS: PackedStringArray = ["import", "orient_size", "aircraft_layout", "weight_balance",
	"power_mount", "controls_ground", "paint_skins", "review_test"]
const STEP_TITLES := {
	import = "Import", orient_size = "Orient and size", aircraft_layout = "Aircraft layout",
	weight_balance = "Weight and balance", power_mount = "Power and mount",
	controls_ground = "Controls and ground", paint_skins = "Paint and skins", review_test = "Review and test",
}
const STATUS_NOT_STARTED := "Not started"
const STATUS_IN_PROGRESS := "In progress"
const STATUS_NEEDS_ATTENTION := "Needs attention"
const STATUS_COMPLETE := "Complete"

const SNAPSHOT_FORMAT := "openrc-creator-document v1"
const AIRFRAME_PACKAGE := "conventional-trainer-estimated-v1"
const POWER_PACKAGE := "electric-4s-800kv-apc12x6-estimated-v1"

## Scalar fields of the definition: path, English label, unit and owning step. Vector components
## use the index as the last path segment. Lengths are metres in the leading-edge frame.
const FIELDS: Array[Dictionary] = [
	{path = "wing/span", label = "Wingspan", unit = "m", step = "aircraft_layout"},
	{path = "wing/root_chord", label = "Wing root chord", unit = "m", step = "aircraft_layout"},
	{path = "wing/tip_chord", label = "Wing tip chord", unit = "m", step = "aircraft_layout"},
	{path = "wing/dihedral_deg", label = "Wing dihedral", unit = "deg", step = "aircraft_layout"},
	{path = "horizontal_tail/span", label = "Tailplane span", unit = "m", step = "aircraft_layout"},
	{path = "horizontal_tail/chord", label = "Tailplane chord", unit = "m", step = "aircraft_layout"},
	{path = "horizontal_tail/position/0", label = "Tailplane leading edge, distance aft", unit = "m", step = "aircraft_layout"},
	{path = "horizontal_tail/position/2", label = "Tailplane height", unit = "m", step = "aircraft_layout"},
	{path = "vertical_tail/height", label = "Fin height", unit = "m", step = "aircraft_layout"},
	{path = "vertical_tail/chord", label = "Fin chord", unit = "m", step = "aircraft_layout"},
	{path = "vertical_tail/position/0", label = "Fin leading edge, distance aft", unit = "m", step = "aircraft_layout"},
	{path = "vertical_tail/position/2", label = "Fin base height", unit = "m", step = "aircraft_layout"},
	{path = "fuselage/nose_x", label = "Nose, distance aft (negative ahead of the wing)", unit = "m", step = "aircraft_layout"},
	{path = "fuselage/tail_x", label = "Tail end, distance aft", unit = "m", step = "aircraft_layout"},
	{path = "fuselage/width", label = "Fuselage width", unit = "m", step = "aircraft_layout"},
	{path = "fuselage/height", label = "Fuselage height", unit = "m", step = "aircraft_layout"},
	{path = "fuselage/center_z", label = "Fuselage centre height", unit = "m", step = "aircraft_layout"},
	{path = "equipment/battery_position/0", label = "Battery, distance aft", unit = "m", step = "weight_balance"},
	{path = "equipment/battery_position/1", label = "Battery, distance right", unit = "m", step = "weight_balance"},
	{path = "equipment/battery_position/2", label = "Battery height", unit = "m", step = "weight_balance"},
	{path = "equipment/hub_position/0", label = "Propeller hub, distance aft", unit = "m", step = "power_mount"},
	{path = "equipment/hub_position/1", label = "Propeller hub, distance right", unit = "m", step = "power_mount"},
	{path = "equipment/hub_position/2", label = "Propeller hub height", unit = "m", step = "power_mount"},
	{path = "equipment/esc_position/0", label = "Speed controller, distance aft", unit = "m", step = "power_mount"},
	{path = "equipment/esc_position/1", label = "Speed controller, distance right", unit = "m", step = "power_mount"},
	{path = "equipment/esc_position/2", label = "Speed controller height", unit = "m", step = "power_mount"},
	{path = "equipment/thrust_angles_deg/0", label = "Down thrust", unit = "deg", step = "power_mount"},
	{path = "equipment/thrust_angles_deg/1", label = "Right thrust", unit = "deg", step = "power_mount"},
	{path = "battery/initial_soc", label = "Battery charge at start (0 to 1)", unit = "", step = "power_mount"},
	{path = "controls/aileron_deg", label = "Aileron travel", unit = "deg", step = "controls_ground"},
	{path = "controls/elevator_deg", label = "Elevator travel", unit = "deg", step = "controls_ground"},
	{path = "controls/rudder_deg", label = "Rudder travel", unit = "deg", step = "controls_ground"},
	{path = "controls/servo_time_s", label = "Neutral to full command time", unit = "s", step = "controls_ground"},
]
## Vector fields of the definition and their fixed components (the centreline y of a tail is 0).
const _VECTORS := {
	"horizontal_tail/position": [-1, 0.0, -1], "vertical_tail/position": [-1, 0.0, -1],
	"equipment/battery_position": [-1, -1, -1], "equipment/hub_position": [-1, -1, -1],
	"equipment/esc_position": [-1, -1, -1], "equipment/thrust_angles_deg": [-1, -1],
}
const _INVENTORY_KINDS: PackedStringArray = ["estimated", "measured", "manual"]

var revision := 0
## Display name. Control characters are dropped: they cannot be stored and are never meant.
var name := "":
	set(value):
		name = clean_text(value)
var _uuid := ""
var _source: InspectedSource
var _placement := Placement.unresolved()
var _units := ""
var _raw := {}
var _values := {}
var _invalid := {}
## Field path -> "estimated" for values the starting-values action supplied and the player has not
## typed or confirmed. Anything the player enters is theirs and is removed from this map.
var _origin := {}
var _inventory: Array = []
var _compiled := {}
var _compiled_revision := -1
## Presentation only: which model parts move with which control, and the paint. Neither changes
## the compiled physics. Shapes are owned by `visual_builder.gd`.
var _bindings := {}
var _appearance := {"mode": "original"}
## Storage identity: the draft this document is saved as, the record it was last saved to (the
## compare-and-swap token for the next save), and the published revision it was opened from or
## last published as (0 = never published).
var draft_id := ""
var saved_record_sha256 := ""
var published_revision := 0
var _saved_fingerprint := ""
static var _number_pattern: RegEx


func _init() -> void:
	_uuid = new_uuid()
	draft_id = new_uuid()


static func new_uuid() -> String:
	var bytes: PackedByteArray = Crypto.new().generate_random_bytes(16)
	bytes[6] = (bytes[6] & 0x0F) | 0x40
	bytes[8] = (bytes[8] & 0x3F) | 0x80
	var hex := bytes.hex_encode()
	return "%s-%s-%s-%s-%s" % [hex.substr(0, 8), hex.substr(8, 4), hex.substr(12, 4), hex.substr(16, 4), hex.substr(20, 12)]


## Parses a complete number as typed. One decimal comma is accepted. Returns NAN when the whole
## text is not a finite decimal number: no partial parse, exponent overflow or empty text.
static func parse_number(text: String) -> float:
	var trimmed := text.strip_edges()
	if trimmed.is_empty() or trimmed.length() > Limits.RAW_NUMBER_CHARACTERS:
		return NAN
	if trimmed.count(",") == 1 and not trimmed.contains("."):
		trimmed = trimmed.replace(",", ".")
	if _number_pattern == null:
		_number_pattern = RegEx.new()
		_number_pattern.compile("^[+-]?(\\d+\\.?\\d*|\\.\\d+)([eE][+-]?\\d+)?$")
	var matched := _number_pattern.search(trimmed)
	if matched == null:
		return NAN
	# The engine logs a warning when it converts an overflowing exponent; refuse it here instead.
	var exponent := matched.get_string(2)
	if exponent.length() > 5 or (not exponent.is_empty() and absi(exponent.substr(1).to_int()) > 300):
		return NAN
	var value := trimmed.to_float()
	return value if is_finite(value) else NAN


static func format_number(value: float) -> String:
	return String.num(value, 4)


# --- Source and placement -------------------------------------------------------------------

func source() -> InspectedSource:
	return _source


func aircraft_uuid() -> String:
	return _uuid


## Adopts a newly admitted source. The placement and the part bindings are reset: axes, units,
## datum and node indices belong to a file. The paint choice is kept.
func set_source(admitted: InspectedSource) -> void:
	_source = admitted
	_placement = Placement.unresolved()
	_units = ""
	_bindings = {}
	_touch()


func placement() -> Dictionary:
	return _placement.duplicate(true)


func units() -> String:
	return _units


func set_axis(which: String, axis: String) -> void:
	if which in ["nose_axis", "up_axis"] and (axis.is_empty() or Placement.AXES.has(axis)):
		_placement[which] = axis
		_touch()


## Chooses the unit the file was drawn in. An empty name returns the scale to unresolved.
func set_units(unit: String) -> void:
	_units = unit if Placement.UNITS.has(unit) else ""
	_placement["unit_scale"] = float(Placement.UNITS[unit]) if Placement.UNITS.has(unit) else 0.0
	_touch()


## Sets the scale from a known real wingspan instead of a unit. False when it cannot be derived.
func set_scale_from_wingspan(wingspan_m: float) -> bool:
	if _source == null:
		return false
	var scale := Placement.scale_for_wingspan(_placement, _source.bounds_min(), _source.bounds_max(), wingspan_m)
	if scale <= 0.0:
		return false
	_units = ""
	_placement["unit_scale"] = scale
	_touch()
	return true


## Datum in source coordinates: the wing leading edge on the centreline, picked or typed.
func set_datum(point: Array) -> void:
	_placement["datum"] = point.duplicate()
	_touch()


func placement_result() -> Dictionary:
	return Placement.resolve(_placement)


## Structural-frame bounds of the placed model in metres, or {} while the placement is unresolved.
func placed_bounds() -> Dictionary:
	if _source == null:
		return {}
	var resolved: Dictionary = Placement.resolve(_placement)
	if not resolved.ok:
		return {}
	return Placement.structural_bounds(resolved.value, _source.bounds_min(), _source.bounds_max())


# --- Typed fields ---------------------------------------------------------------------------

func raw(path: String) -> String:
	return str(_raw.get(path, ""))


func value(path: String) -> Variant:
	return _values.get(path)


func is_invalid(path: String) -> bool:
	return _invalid.has(path)


## Commits typed text. Empty text returns the field to unresolved. Invalid text is kept visible
## and flagged; the last accepted value stays for preview but compilation is blocked.
func set_raw(path: String, text: String) -> bool:
	text = clean_text(text)
	var trimmed := text.strip_edges()
	_raw[path] = text
	if trimmed.is_empty():
		_values.erase(path)
		_invalid.erase(path)
		_origin.erase(path)
		_touch()
		return true
	var parsed := parse_number(text)
	if is_nan(parsed):
		_invalid[path] = true
		_touch()
		return false
	_invalid.erase(path)
	_origin.erase(path)
	_values[path] = parsed
	_touch()
	return true


func set_value(path: String, number: float) -> void:
	_origin.erase(path)
	_values[path] = number
	_raw[path] = format_number(number)
	_invalid.erase(path)
	_touch()


## Applies several values at once. `estimated` marks them as unconfirmed starting values: the
## compiled record then labels them estimated, never as entered by the player.
func apply_values(values: Dictionary, estimated := false) -> void:
	for path: String in values:
		if estimated:
			_origin[path] = "estimated"
		else:
			_origin.erase(path)
		_values[path] = float(values[path])
		_raw[path] = format_number(float(values[path]))
		_invalid.erase(path)
	_touch()


## True while a value is an unconfirmed starting estimate.
func is_estimated(path: String) -> bool:
	return _origin.has(path) and _values.has(path)


static func field(path: String) -> Dictionary:
	for entry: Dictionary in FIELDS:
		if str(entry.path) == path:
			return entry
	return {}


static func fields_for(step: String) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for entry: Dictionary in FIELDS:
		if str(entry.step) == step:
			found.append(entry)
	return found


# --- Inventory ------------------------------------------------------------------------------

func inventory() -> Array:
	return _inventory.duplicate(true)


## Replaces the airframe items with estimated ones proposed from the geometry. Items the player
## marked measured or manual are kept untouched.
func propose_inventory() -> void:
	var kept: Array = []
	var kept_ids := {}
	for item: Dictionary in _inventory:
		if str(item.get("kind", "")) != "estimated":
			kept.append(item)
			kept_ids[str(item.id)] = true
	for item: Variant in Definition.propose_airframe_inventory(definition()):
		if item is Dictionary and not kept_ids.has(str(item.id)) and kept.size() < Limits.INVENTORY_ITEMS:
			kept.append((item as Dictionary).duplicate(true))
	_inventory = kept
	_touch()


func add_item(item_name: String) -> String:
	if _inventory.size() >= Limits.INVENTORY_ITEMS:
		return ""
	var serial := 1
	var id := "item_custom_%d" % serial
	while _has_item(id):
		serial += 1
		id = "item_custom_%d" % serial
	_inventory.append({id = id, name = clean_text(item_name).substr(0, Limits.NAME_CHARACTERS), mass = 0.0, position = [0.0, 0.0, 0.0], size = [0.0, 0.0, 0.0], kind = "manual"})
	_touch()
	return id


func remove_item(id: String) -> void:
	for index: int in _inventory.size():
		if str(_inventory[index].id) == id:
			_inventory.remove_at(index)
			_touch()
			return


## Edits one inventory value from typed text. `key` is mass, x, y or z. False when not a number.
func set_item_raw(id: String, key: String, text: String) -> bool:
	var parsed := parse_number(text)
	if is_nan(parsed):
		return false
	for item: Dictionary in _inventory:
		if str(item.id) != id:
			continue
		match key:
			"mass": item["mass"] = parsed
			"x": item.position[0] = parsed
			"y": item.position[1] = parsed
			"z": item.position[2] = parsed
			_: return false
		_touch()
		return true
	return false


func set_item_name(id: String, item_name: String) -> void:
	for item: Dictionary in _inventory:
		if str(item.id) == id:
			item["name"] = clean_text(item_name).substr(0, Limits.NAME_CHARACTERS)
			_touch()
			return


func set_item_kind(id: String, kind: String) -> void:
	if kind not in _INVENTORY_KINDS:
		return
	for item: Dictionary in _inventory:
		if str(item.id) == id:
			item["kind"] = kind
			_touch()
			return


func _has_item(id: String) -> bool:
	for item: Dictionary in _inventory:
		if str(item.id) == id:
			return true
	return false


# --- Presentation: bound parts and appearance -----------------------------------------------

func bindings() -> Dictionary:
	return _bindings.duplicate(true)


## Whole numbers (part index, direction) are kept as integers whatever the caller or a stored
## record spelled them as, so the same bindings always have the same fingerprint.
func set_bindings(bound: Dictionary) -> void:
	_bindings = _whole_numbers(bound)
	_touch()


func appearance() -> Dictionary:
	return _appearance.duplicate(true)


func set_appearance(chosen: Dictionary) -> void:
	_appearance = chosen.duplicate(true)
	_touch()


# --- Saving ---------------------------------------------------------------------------------

## Everything needed to rebuild this document except the source bytes, as plain JSON data: typed
## values, raw text including invalid buffers, evidence, inventory, placement, bindings and paint.
## `step` is the wizard step to reopen on. The store treats the result as opaque.
##
## Every number is written with `exact`: the engine's JSON text does not round-trip a float64
## bit for bit, and a reopened draft must compile to the same bytes as before it was saved.
func snapshot(step := "") -> Dictionary:
	var invalid: Array = []
	for path: String in _invalid:
		invalid.append(path)
	var values := {}
	for path: String in _values:
		values[path] = exact(float(_values[path]))
	var items: Array = []
	for item: Dictionary in _inventory:
		items.append({"id": str(item.id), "name": str(item.name), "kind": str(item.kind), "mass": exact(float(item.mass)),
			"position": _exact_point(item.position), "size": _exact_point(item.size)})
	return {
		"format": SNAPSHOT_FORMAT, "aircraft_uuid": _uuid, "name": name, "step": step,
		"source_sha256": _source.sha256() if _source != null else "",
		"placement": {"nose_axis": str(_placement.nose_axis), "up_axis": str(_placement.up_axis),
			"unit_scale": exact(float(_placement.unit_scale)), "datum": _exact_point(_placement.datum)},
		"units": _units, "raw": _raw.duplicate(), "values": values, "invalid": invalid,
		"origin": _origin.duplicate(), "inventory": items,
		"bindings": _bindings.duplicate(true), "appearance": _appearance.duplicate(true),
		"published_revision": published_revision,
	}


## Rebuilds the document from a snapshot and the re-admitted source (null when the draft had no
## model yet). Nothing is taken on trust: unknown fields are dropped, numbers must be finite, and
## a source whose identity differs from the one the snapshot was saved with is refused.
## Returns the R envelope; on failure the document is unchanged.
func restore(saved: Dictionary, admitted: InspectedSource) -> Dictionary:
	if str(saved.get("format", "")) != SNAPSHOT_FORMAT:
		return R.fail(R.RECORD_INVALID, "This draft was saved by an incompatible version.")
	var wanted := str(saved.get("source_sha256", ""))
	if (admitted == null) != wanted.is_empty() or (admitted != null and admitted.sha256() != wanted):
		return R.fail(R.IDENTITY_MISMATCH, "The saved model does not match this draft.")
	var uuid := str(saved.get("aircraft_uuid", ""))
	if not _is_uuid(uuid):
		return R.fail(R.RECORD_INVALID, "This draft has no aircraft identity.")
	var known := {}
	for entry: Dictionary in FIELDS:
		known[str(entry.path)] = true
	var values := {}
	var stored_values: Variant = saved.get("values", {})
	if stored_values is Dictionary:
		for path: Variant in stored_values:
			var number := from_exact(stored_values[path])
			if known.has(str(path)) and is_finite(number):
				values[str(path)] = number
	var raw_text := {}
	var stored_raw: Variant = saved.get("raw", {})
	if stored_raw is Dictionary:
		for path: Variant in stored_raw:
			if known.has(str(path)) and typeof(stored_raw[path]) == TYPE_STRING \
					and (stored_raw[path] as String).length() <= Limits.RAW_NUMBER_CHARACTERS:
				raw_text[str(path)] = clean_text(stored_raw[path])
	var invalid := {}
	for path: Variant in saved.get("invalid", []) if saved.get("invalid", []) is Array else []:
		if known.has(str(path)) and raw_text.has(str(path)) and is_nan(parse_number(raw_text[str(path)])) \
				and not str(raw_text[str(path)]).strip_edges().is_empty():
			invalid[str(path)] = true
	# What a field shows must be what the document holds: text is kept only when it is the typed
	# text of the stored value, the document's own display of it, or recorded as not being a number.
	for path: String in raw_text.keys():
		if invalid.has(path):
			continue
		if not values.has(path):
			raw_text.erase(path)
		elif parse_number(raw_text[path]) != float(values[path]) and raw_text[path] != format_number(float(values[path])):
			raw_text[path] = format_number(float(values[path]))
	var origin := {}
	var stored_origin: Variant = saved.get("origin", {})
	if stored_origin is Dictionary:
		for path: Variant in stored_origin:
			if values.has(str(path)) and str(stored_origin[path]) == "estimated":
				origin[str(path)] = "estimated"
	var items: Array = []
	for item: Variant in saved.get("inventory", []) if saved.get("inventory", []) is Array else []:
		var restored: Dictionary = _restored_item(item)
		if not restored.is_empty() and items.size() < Limits.INVENTORY_ITEMS:
			items.append(restored)
	var placed := Placement.unresolved()
	var stored_placement: Variant = saved.get("placement", {})
	if stored_placement is Dictionary:
		for which: String in ["nose_axis", "up_axis"]:
			if Placement.AXES.has(str(stored_placement.get(which, ""))):
				placed[which] = str(stored_placement[which])
		var scale := from_exact(stored_placement.get("unit_scale"))
		if is_finite(scale) and scale > 0.0:
			placed["unit_scale"] = scale
		var datum: Array = _from_exact_point(stored_placement.get("datum"))
		if datum.size() == 3:
			placed["datum"] = datum
	_uuid = uuid
	name = clean_text(str(saved.get("name", ""))).substr(0, Limits.NAME_CHARACTERS)
	_source = admitted
	_placement = placed
	_units = str(saved.get("units", "")) if Placement.UNITS.has(str(saved.get("units", ""))) else ""
	_values = values
	_raw = raw_text
	_invalid = invalid
	_origin = origin
	_inventory = items
	_bindings = _whole_numbers(saved.get("bindings", {})) if saved.get("bindings", {}) is Dictionary and admitted != null else {}
	_appearance = (saved.get("appearance", {}) as Dictionary).duplicate(true) if saved.get("appearance", {}) is Dictionary \
		and not (saved.get("appearance", {}) as Dictionary).is_empty() else {"mode": "original"}
	var revision_saved: Variant = saved.get("published_revision", 0)
	published_revision = int(revision_saved) if (typeof(revision_saved) == TYPE_FLOAT or typeof(revision_saved) == TYPE_INT) \
		and float(revision_saved) >= 0.0 else 0
	_touch()
	return R.ok(str(saved.get("step", "")))


## Marks the current content as saved under `record_sha256` (the next save's compare-and-swap token).
func mark_saved(record_sha256: String) -> void:
	saved_record_sha256 = record_sha256
	_saved_fingerprint = fingerprint()


## True when the content differs from the last save, or was never saved and holds anything.
func has_unsaved_changes() -> bool:
	if _saved_fingerprint.is_empty():
		return _source != null or not _values.is_empty() or not _raw.is_empty() or not _inventory.is_empty() or not name.is_empty()
	return fingerprint() != _saved_fingerprint


## Digest of the saved content. The step, camera and focus are not content.
func fingerprint() -> String:
	var written: Dictionary = CreatorBytes.encode(snapshot())
	return str(written.value.sha256) if written.ok else ""


## Text without control characters (C0 and DEL): they cannot be stored and a field never means them.
static func clean_text(text: String) -> String:
	var clean := ""
	var kept_from := 0
	for index: int in text.length():
		var code := text.unicode_at(index)
		if code < 0x20 or code == 0x7F:
			clean += text.substr(kept_from, index - kept_from)
			kept_from = index + 1
	return text if kept_from == 0 else clean + text.substr(kept_from)


## Deep copy with every whole-number float turned into an integer (a stored record returns every
## number as a float). Non-finite and fractional numbers are left for validation to refuse.
static func _whole_numbers(node: Variant) -> Variant:
	if node is Dictionary:
		var fields := {}
		for key: Variant in node:
			fields[key] = _whole_numbers(node[key])
		return fields
	if node is Array:
		var items: Array = []
		for item: Variant in node:
			items.append(_whole_numbers(item))
		return items
	if typeof(node) == TYPE_FLOAT and is_finite(node) and node == floorf(node) and absf(node) <= float(Limits.MAX_SAFE_INTEGER):
		return int(node)
	return node


## Lowercase version 4 UUID, as `Definition` requires of an aircraft identity.
static func _is_uuid(text: String) -> bool:
	if text.length() != 36:
		return false
	for index: int in 36:
		var character := text[index]
		if index in [8, 13, 18, 23]:
			if character != "-":
				return false
		elif character not in "0123456789abcdef":
			return false
	return text[14] == "4" and text[19] in "89ab"


static func _restored_item(item: Variant) -> Dictionary:
	if not item is Dictionary:
		return {}
	var id := str(item.get("id", ""))
	var kind := str(item.get("kind", ""))
	var mass := from_exact(item.get("mass"))
	var position: Array = _from_exact_point(item.get("position"))
	var size: Array = _from_exact_point(item.get("size"))
	if id.is_empty() or id.length() > 80 or kind not in _INVENTORY_KINDS or not is_finite(mass) \
			or position.size() != 3 or size.size() != 3:
		return {}
	return {id = id, name = clean_text(str(item.get("name", ""))).substr(0, Limits.NAME_CHARACTERS), mass = mass,
		position = position, size = size, kind = kind}


## A float64 as the 16 hex digits of its IEEE 754 bytes: exact through any text format.
static func exact(value: float) -> String:
	var bytes := PackedByteArray()
	bytes.resize(8)
	bytes.encode_double(0, value)
	return bytes.hex_encode()


## The float64 written by `exact`, or NAN when the text is not exactly 16 hex digits or not finite.
static func from_exact(text: Variant) -> float:
	if typeof(text) != TYPE_STRING or (text as String).length() != 16:
		return NAN
	for character: String in (text as String):
		if character not in "0123456789abcdef":
			return NAN
	var value: float = (text as String).hex_decode().decode_double(0)
	return value if is_finite(value) else NAN


static func _exact_point(point: Variant) -> Array:
	var out: Array = []
	if point is Array or point is PackedFloat64Array:
		for component: Variant in point:
			out.append(exact(float(component)))
	return out


## Three finite numbers written by `_exact_point`, or [] when anything is off.
static func _from_exact_point(stored: Variant) -> Array:
	if not stored is Array or (stored as Array).size() != 3:
		return []
	var out: Array = []
	for component: Variant in stored:
		var value := from_exact(component)
		if not is_finite(value):
			return []
		out.append(value)
	return out


# --- Definition, starting values, issues ----------------------------------------------------

## The authoring definition from the accepted values. Unresolved values are simply absent, so
## complete-definition validation names exactly what is missing.
func definition() -> Dictionary:
	var record := {
		"format": Definition.FORMAT, "aircraft_uuid": _uuid,
		"airframe_package": AIRFRAME_PACKAGE, "power_package": POWER_PACKAGE,
		"inventory": _inventory.duplicate(true),
	}
	for path: String in _values:
		var segments := path.split("/")
		var vector_path := "/".join(segments.slice(0, segments.size() - 1))
		if _VECTORS.has(vector_path):
			continue
		_set_nested(record, segments, float(_values[path]))
	for vector_path: String in _VECTORS:
		var pattern: Array = _VECTORS[vector_path]
		var components: Array = []
		for index: int in pattern.size():
			if float(pattern[index]) != -1.0:
				components.append(float(pattern[index]))
			elif _values.has("%s/%d" % [vector_path, index]):
				components.append(float(_values["%s/%d" % [vector_path, index]]))
		if components.size() == pattern.size():
			_set_nested(record, vector_path.split("/"), components)
	var evidence := {}
	for path: String in _origin:
		if not _values.has(path):
			continue
		var segments := path.split("/")
		var group := "/".join(segments.slice(0, segments.size() - 1))
		# A vector is estimated while any of its components still is.
		evidence[group if _VECTORS.has(group) else path] = "estimated"
	if not evidence.is_empty():
		record["evidence"] = evidence
	return record


## Estimated starting values scaled from the reference trainer to the placed model: lengths scale
## with the wingspan, and the fuselage ends follow the model's own extent. They are estimates to
## correct, never measurements. Returns path -> value; apply with `apply_values`.
func starting_values() -> Dictionary:
	var template: Dictionary = Definition.template()
	var bounds: Dictionary = placed_bounds()
	var template_span: float = float(template.wing.span)
	var span: float = template_span
	if not bounds.is_empty():
		span = float(bounds.max[1]) - float(bounds.min[1])
	if _values.has("wing/span"):
		span = float(_values["wing/span"])
	var k: float = span / template_span if template_span > 0.0 and span > 0.0 else 1.0
	var values := {}
	for entry: Dictionary in FIELDS:
		var path: String = entry.path
		var found: Variant = _lookup(template, path.split("/"))
		if found == null:
			continue
		values[path] = float(found) * (k if str(entry.unit) == "m" else 1.0)
	values["wing/span"] = span
	if not bounds.is_empty():
		var nose: float = float(bounds.min[0])
		var tail: float = float(bounds.max[0])
		if nose < 0.0 and tail > 0.0:
			var shift: float = nose - float(values["fuselage/nose_x"])
			values["fuselage/nose_x"] = nose
			values["fuselage/tail_x"] = tail
			values["equipment/hub_position/0"] = float(values["equipment/hub_position/0"]) + shift
			values["horizontal_tail/position/0"] = tail - float(values["horizontal_tail/chord"])
			values["vertical_tail/position/0"] = tail - float(values["vertical_tail/chord"])
	return values


func summary() -> Dictionary:
	return Compiler.summarize(definition())


## Everything that blocks a test flight, as routed diagnostics.
func issues() -> Array:
	var found: Array = []
	if _source == null:
		found.append(R.diagnostic(R.SOURCE_MISSING, "Import a model first.", "source", "import"))
	else:
		var placed: Dictionary = Placement.resolve(_placement)
		if not placed.ok:
			found.append_array(placed.diagnostics)
	for path: String in _invalid:
		var entry: Dictionary = field(path)
		found.append(R.diagnostic(R.FIELD_INVALID, "\"%s\" is not a number.", path, str(entry.get("step", "")),
			[str(entry.get("label", path))]))
	var checked: Dictionary = Definition.validate_complete(definition())
	if not checked.ok:
		found.append_array(checked.diagnostics)
	elif _invalid.is_empty():
		var compiled: Dictionary = compile()
		if not compiled.ok:
			found.append_array(compiled.diagnostics)
	return found


## Compiles the current definition. The result is cached for the current document revision.
func compile() -> Dictionary:
	if _compiled_revision == revision:
		return _compiled
	if not _invalid.is_empty():
		_compiled = R.fail(R.FIELD_INVALID, "Correct the highlighted values first.")
	else:
		_compiled = Compiler.compile_candidate(definition())
	_compiled_revision = revision
	return _compiled


func step_status(step: String) -> String:
	match step:
		"import":
			return STATUS_COMPLETE if _source != null else STATUS_NOT_STARTED
		"orient_size":
			if _source == null:
				return STATUS_NOT_STARTED
			if Placement.resolve(_placement).ok:
				return STATUS_COMPLETE
			var started: bool = not str(_placement.nose_axis).is_empty() or not str(_placement.up_axis).is_empty() \
				or float(_placement.unit_scale) > 0.0 or not (_placement.datum as Array).is_empty()
			return STATUS_IN_PROGRESS if started else STATUS_NOT_STARTED
		"paint_skins":
			return STATUS_COMPLETE if _source != null else STATUS_NOT_STARTED
		"review_test":
			if _source == null or _values.is_empty():
				return STATUS_NOT_STARTED
			return STATUS_COMPLETE if issues().is_empty() else STATUS_IN_PROGRESS
	var owned: Array[Dictionary] = fields_for(step)
	var resolved := 0
	var broken := false
	for entry: Dictionary in owned:
		if _values.has(entry.path):
			resolved += 1
		if _invalid.has(entry.path):
			broken = true
	if step == "weight_balance" and _inventory.is_empty():
		return STATUS_NEEDS_ATTENTION if broken else (STATUS_IN_PROGRESS if resolved > 0 else STATUS_NOT_STARTED)
	if broken:
		return STATUS_NEEDS_ATTENTION
	if resolved == 0:
		return STATUS_NOT_STARTED
	if resolved < owned.size():
		return STATUS_IN_PROGRESS
	for entry: Variant in issues():
		if entry is Dictionary and str((entry as Dictionary).get("step", "")) == step:
			return STATUS_NEEDS_ATTENTION
	return STATUS_COMPLETE


func _touch() -> void:
	revision += 1
	changed.emit()


static func _set_nested(record: Dictionary, segments: PackedStringArray, leaf: Variant) -> void:
	var node: Dictionary = record
	for index: int in segments.size() - 1:
		if not node.has(segments[index]):
			node[segments[index]] = {}
		node = node[segments[index]]
	node[segments[segments.size() - 1]] = leaf


static func _lookup(record: Variant, segments: PackedStringArray) -> Variant:
	var node: Variant = record
	for segment: String in segments:
		if node is Dictionary and (node as Dictionary).has(segment):
			node = node[segment]
		elif node is Array and segment.is_valid_int() and int(segment) < (node as Array).size():
			node = node[int(segment)]
		else:
			return null
	return node if typeof(node) == TYPE_FLOAT or typeof(node) == TYPE_INT else null
