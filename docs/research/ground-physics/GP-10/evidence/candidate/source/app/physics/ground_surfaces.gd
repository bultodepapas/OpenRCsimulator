# E3a: which field surface each wheel rolls on, and how that surface scales the tyre forces.
# The surface table (app/data/ground/surface_friction.json) gives per surface type a friction_factor (× the gear's μ)
# and a rolling_factor (× the gear's C_rr); the aircraft's coefficients are for dry pavement, as in JSBSim/FlightGear.
# The field's rectangles (app/data/fields/, validated by data/field_loader.gd) say where each type lies. Precedence
# follows TYPES: a runway lies on the mown area, which lies on the rough; beyond every rectangle the ground is OUTSIDE.
# 64-bit floats only (guarded).
extends RefCounted

const AircraftData := preload("res://physics/aircraft_data.gd")
const GroundSupport := preload("res://physics/ground_support.gd")

const FORMAT := "openrc-surfaces v1"
const DEFAULT_PATH := "res://data/ground/surface_friction.json"
## Surface types, highest precedence first (the field loader allows exactly these).
const TYPES := ["runway", "rotorpad", "mown", "rough"]
## The ground beyond every rectangle.
const OUTSIDE := "rough"
## The flat table's layout and the lookup live in physics/ground_contact.gd (SURFACE_STRIDE, surface_at), which
## evaluates them every RK4 stage.


## Loads and validates the surface table. Returns { ok, errors, table: { type: { friction_factor, rolling_factor } } }.
## friction_factor must be ≤ 1 so the gear's side-force stability bound (checked by AircraftData) still holds.
static func load_table(path := DEFAULT_PATH) -> Dictionary:
	var errors := PackedStringArray()
	var text := FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else "" # no engine error for a missing file
	var raw: Variant = JSON.parse_string(text) if not text.is_empty() else null
	if typeof(raw) != TYPE_DICTIONARY:
		errors.append("%s: missing or not a JSON object" % path)
		return { ok = false, errors = errors, table = {} }
	return validate(raw)


static func validate(raw: Dictionary) -> Dictionary:
	var errors := PackedStringArray()
	if raw.get("format") != FORMAT:
		errors.append("format must be '%s', got '%s'" % [FORMAT, raw.get("format")])
		return { ok = false, errors = errors, table = {} }
	var surfaces: Variant = raw.get("surfaces")
	if typeof(surfaces) != TYPE_DICTIONARY:
		errors.append("surfaces: missing or not an object")
		return { ok = false, errors = errors, table = {} }
	var table := {}
	for type in TYPES:
		var node: Variant = surfaces.get(type)
		if typeof(node) != TYPE_DICTIONARY:
			errors.append("surfaces.%s: missing" % type)
			continue
		var ff = AircraftData._q(errors, "surfaces.%s.friction_factor" % type, node.get("friction_factor"), "1", 0.05, 1.0)
		var rf = AircraftData._q(errors, "surfaces.%s.rolling_factor" % type, node.get("rolling_factor"), "1", 0.5, 20.0)
		# GP-07c: an airframe point (not a tyre) sliding on this surface; physics/hull_contact.gd.
		var af = AircraftData._q(errors, "surfaces.%s.airframe_friction" % type, node.get("airframe_friction"), "1", 0.05, 1.2)
		if ff != null and rf != null and af != null:
			table[type] = { friction_factor = float(ff), rolling_factor = float(rf), airframe_friction = float(af) }
			# Optional identity only; historical v1 tables remain accepted. No material
			# is guessed from a runway label or a numeric friction multiplier.
			if node.has("material_id"):
				var material: Variant = node.material_id
				if typeof(material) != TYPE_STRING or str(material).strip_edges().is_empty() or str(material).length() > 128 \
					or typeof(node.get("material_source")) != TYPE_STRING or str(node.material_source).strip_edges().is_empty():
					errors.append("surfaces.%s: material identity needs a bounded ID and source" % type)
				else:
					table[type].material_id = material
	if table.has("rotorpad") and float(table.rotorpad.rolling_factor) != 0.5:
		errors.append("surfaces.rotorpad.rolling_factor: must remain 0.5; this reserved value selects zero-relief rotorpad terrain")
	for type in surfaces:
		if not (type in TYPES):
			errors.append("surfaces.%s: unknown surface type (expected %s)" % [type, TYPES])
	return { ok = errors.is_empty(), errors = errors, table = table if errors.is_empty() else {} }


## Flat lookup table for physics/ground_contact.gd from a validated field (FieldLoader's `field`) and a surface table:
## the field's rectangles in precedence order (north_min, north_max, east_min, east_max, friction_factor,
## rolling_factor each), then a catch-all block (±INF) for OUTSIDE. Returns
## { ok, errors, rects: PackedFloat64Array }.
static func build(table: Dictionary, field: Dictionary) -> Dictionary:
	var errors := PackedStringArray()
	var rects := PackedFloat64Array()
	var regions: Array[Dictionary] = []
	var fields_surfaces: Array = field.get("surfaces", [])
	for type in TYPES:
		for s in fields_surfaces:
			if str(s.get("type", "")) != type:
				continue
			var half_n := float(s.width_north_south) / 2.0
			var half_e := float(s.length_east_west) / 2.0
			rects.append_array(PackedFloat64Array([float(s.center_north) - half_n, float(s.center_north) + half_n,
				float(s.center_east) - half_e, float(s.center_east) + half_e,
				table[type].friction_factor, table[type].rolling_factor]))
			regions.append({region_id = _region_id_for_surface(str(s.get("id", "row_%d" % regions.size()))),
				usage_id = type, material_id = str(table[type].get("material_id", "unspecified"))})
	for s in fields_surfaces:
		if not (str(s.get("type", "")) in TYPES):
			errors.append("field surface '%s': type '%s' has no friction data" % [s.get("id", "?"), s.get("type", "")])
	rects.append_array(PackedFloat64Array([-INF, INF, -INF, INF, table[OUTSIDE].friction_factor, table[OUTSIDE].rolling_factor]))
	regions.append({region_id = "__outside__", usage_id = OUTSIDE,
		material_id = str(table[OUTSIDE].get("material_id", "unspecified"))})
	var support := GroundSupport.prepare_legacy(rects, regions)
	if not support.ok:
		errors.append("ground support registry: " + str(support.reason))
	return { ok = errors.is_empty(), errors = errors, rects = rects if errors.is_empty() else PackedFloat64Array(),
		regions = regions if errors.is_empty() else [] }


## Keep historical field IDs accepted even when their observational namespace
## would exceed the registry bound. The two prefixes cannot alias one another.
static func _region_id_for_surface(authored_id: String) -> String:
	return "field:" + authored_id if authored_id.length() <= 122 else "field_sha256:" + authored_id.sha256_text()


## GP-07c: flat lookup table of airframe sliding friction for physics/hull_contact.gd: the field's rectangles in the
## same precedence as build() (north_min, north_max, east_min, east_max, airframe_friction each: AIRFRAME_STRIDE
## floats, defined with the lookup in physics/hull_contact.gd), then a catch-all block (±INF) for OUTSIDE. Kept apart from the tyre table so its layout, read by the
## wheels, helicopters and vehicles, does not change. Returns { ok, errors, rects: PackedFloat64Array }.
static func build_airframe(table: Dictionary, field: Dictionary) -> Dictionary:
	var errors := PackedStringArray()
	var rects := PackedFloat64Array()
	var fields_surfaces: Array = field.get("surfaces", [])
	for type in TYPES:
		for s in fields_surfaces:
			if str(s.get("type", "")) != type:
				continue
			var half_n := float(s.width_north_south) / 2.0
			var half_e := float(s.length_east_west) / 2.0
			rects.append_array(PackedFloat64Array([float(s.center_north) - half_n, float(s.center_north) + half_n,
				float(s.center_east) - half_e, float(s.center_east) + half_e, table[type].airframe_friction]))
	for s in fields_surfaces:
		if not (str(s.get("type", "")) in TYPES):
			errors.append("field surface '%s': type '%s' has no friction data" % [s.get("id", "?"), s.get("type", "")])
	rects.append_array(PackedFloat64Array([-INF, INF, -INF, INF, table[OUTSIDE].airframe_friction]))
	return { ok = errors.is_empty(), errors = errors, rects = rects if errors.is_empty() else PackedFloat64Array() }
