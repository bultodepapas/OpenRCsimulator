extends RefCounted
## Additive physical v2 identity metadata. IDs never select a numerical law.
const VERSION := 1
const SURFACES := ["aileron_left", "aileron_right", "elevator", "rudder"]
## X8-03: an elevon aircraft identifies its two physical surfaces instead of the four conventional ones.
const ELEVON_SURFACES := ["elevon_left", "elevon_right"]
const ID_PATTERN := "^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$"
const MAX_ID_LENGTH := 80

static func validate(raw: Dictionary) -> PackedStringArray:
	var issues := PackedStringArray()
	var inventory: Variant = raw.get("inventory", [])
	var gear: Variant = raw.get("landing_gear", {})
	var propulsion: Variant = raw.get("propulsion", {})
	var controls: Variant = raw.get("controls", {})
	if not raw.has("physical_identity_version"):
		# V2 fuel and battery modules already use inventory IDs as references.
		# Older v2 files may need those IDs without claiming the complete authored
		# physical-identity module. Validate referenced IDs as a unique subset.
		var referenced_inventory_ids := _referenced_inventory_ids(raw)
		var referenced_seen := {}
		var orphan := raw.has("crash_hull_ids")
		if inventory is Array:
			for i in inventory.size():
				var item: Variant = inventory[i]
				if item is Dictionary and item.has("id"):
					var inventory_id: Variant = item.get("id")
					if referenced_inventory_ids.has(inventory_id):
						_register(inventory_id, "/inventory/%d/id" % i, referenced_seen, issues)
					else:
						orphan = true
		if gear is Dictionary and gear.get("contacts") is Array:
			for item in gear.contacts:
				orphan = orphan or (item is Dictionary and item.has("id"))
		orphan = orphan or (propulsion is Dictionary and propulsion.has("id"))
		orphan = orphan or (controls is Dictionary and controls.has("surface_ids"))
		if orphan:
			issues.append("/physical_identity_version: identity fields require the complete versioned module")
		return issues
	var version: Variant = raw.physical_identity_version
	if not (typeof(version) in [TYPE_INT, TYPE_FLOAT]) or version != VERSION:
		issues.append("/physical_identity_version: expected version 1")
		return issues
	var seen := {}
	if not inventory is Array or inventory.is_empty():
		issues.append("/inventory: identity requires a nonempty array")
	else:
		for i in inventory.size():
			var item: Variant = inventory[i]
			_register(item.get("id") if item is Dictionary else null, "/inventory/%d/id" % i, seen, issues)
	if raw.has("landing_gear"):
		if not gear is Dictionary or not gear.get("contacts") is Array:
			issues.append("/landing_gear/contacts: identity requires an array")
		else:
			for i in gear.contacts.size():
				var item: Variant = gear.contacts[i]
				_register(item.get("id") if item is Dictionary else null, "/landing_gear/contacts/%d/id" % i, seen, issues)
	var hull: Variant = raw.get("crash_hull")
	var hull_ids: Variant = raw.get("crash_hull_ids")
	if not hull is Dictionary or not hull.get("value") is Array or not hull_ids is Array:
		issues.append("/crash_hull_ids: requires an array aligned with crash_hull.value")
	else:
		if hull_ids.size() != hull.value.size():
			issues.append("/crash_hull_ids: count must match crash_hull.value")
		for i in hull_ids.size():
			_register(hull_ids[i], "/crash_hull_ids/%d" % i, seen, issues)
	_register(propulsion.get("id") if propulsion is Dictionary else null, "/propulsion/id", seen, issues)
	var surface_ids: Variant = controls.get("surface_ids") if controls is Dictionary else null
	var capabilities: Variant = raw.get("capabilities")
	var elevon: bool = capabilities is Dictionary and capabilities.get("controls") == "elevon"
	var surfaces: Array = ELEVON_SURFACES if elevon else SURFACES
	if not surface_ids is Dictionary:
		issues.append("/controls/surface_ids: expected the %s surface IDs" % ("two elevon" if elevon else "four conventional"))
	else:
		for key in surface_ids:
			if key not in surfaces:
				issues.append("/controls/surface_ids/%s: unsupported surface" % str(key))
		for key in surfaces:
			_register(surface_ids.get(key), "/controls/surface_ids/" + key, seen, issues)
	return issues

static func _register(value: Variant, path: String, seen: Dictionary, issues: PackedStringArray) -> void:
	if not value is String or value.is_empty() or value.length() > MAX_ID_LENGTH:
		issues.append(path + ": expected a stable ID of 1 to 80 characters")
		return
	var pattern := RegEx.create_from_string(ID_PATTERN)
	var matched := pattern.search(value)
	if matched == null or matched.get_string() != value:
		issues.append(path + ": expected lowercase snake_case starting with a letter")
	elif seen.has(value):
		issues.append(path + ": duplicate physical ID; first used at " + str(seen[value]))
	else:
		seen[value] = path

## Only validated authored modules produce durable identities. Legacy remains unmodified.
static func describe(raw: Dictionary) -> Dictionary:
	if not raw.has("physical_identity_version") or not validate(raw).is_empty():
		return {}
	var inventory_ids := PackedStringArray()
	var inventory_index_by_id := {}
	for i in raw.inventory.size():
		var key: String = raw.inventory[i].id
		inventory_ids.append(key)
		inventory_index_by_id[key] = i
	var support_ids := PackedStringArray()
	for contact in raw.get("landing_gear", {}).get("contacts", []):
		support_ids.append(contact.id)
	return {version = VERSION, status = "authored", inventory_ids = inventory_ids,
		inventory_index_by_id = inventory_index_by_id, hull_ids = PackedStringArray(raw.crash_hull_ids),
		support_ids = support_ids, propulsion_id = raw.propulsion.id,
		surface_ids = raw.controls.surface_ids.duplicate(true)}


static func _referenced_inventory_ids(raw: Dictionary) -> Dictionary:
	var referenced := {}
	var fuel_system: Variant = raw.get("fuel_system", {})
	if fuel_system is Dictionary:
		var tanks: Variant = fuel_system.get("tanks", [])
		if tanks is Array:
			for tank in tanks:
				if not tank is Dictionary:
					continue
				for key: String in ["liquid_inventory_id", "shell_inventory_id"]:
					var inventory_id: Variant = tank.get(key, null)
					if inventory_id is String and not inventory_id.is_empty():
						referenced[inventory_id] = true
				var feed_line: Variant = tank.get("feed_line", {})
				if feed_line is Dictionary:
					var line_inventory_id: Variant = feed_line.get("liquid_inventory_id", null)
					if line_inventory_id is String and not line_inventory_id.is_empty():
						referenced[line_inventory_id] = true
	var propulsion: Variant = raw.get("propulsion", {})
	if propulsion is Dictionary:
		var battery: Variant = propulsion.get("battery", {})
		if battery is Dictionary:
			var mount_inventory_id: Variant = battery.get("mount_inventory_id", null)
			if mount_inventory_id is String and not mount_inventory_id.is_empty():
				referenced[mount_inventory_id] = true
	return referenced
