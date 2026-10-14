## Physics bridge to the same validated field surfaces and terrain used by the aircraft.
## All coordinates and values stay float64; rendering converts only at its boundary.
extends RefCounted

const FieldLoader := preload("res://data/field_loader.gd")
const GroundSurfaces := preload("res://physics/ground_surfaces.gd")
const GroundTerrain := preload("res://physics/ground_terrain.gd")
const GroundContact := preload("res://physics/ground_contact.gd")
const LakeLoader := preload("res://data/lake_loader.gd")
const LakeSurface := preload("res://physics/lake_surface.gd")
const VehicleDynamics := preload("res://physics/ground_vehicle/vehicle_dynamics.gd")
const Track := preload("res://physics/ground_vehicle/airfield_track.gd")
const M := preload("res://physics/math3d.gd")

const FORMAT := "openrc-airfield-course"
const VERSION := 1
const DEFAULT_SURFACE_TABLE_PATH := "res://data/ground/surface_friction.json"
const DRY_PAVEMENT_MU := 0.85
const RUNWAY_END_MARGIN_M := 2.0
const BOUNDS_KEYS := ["north_min_m", "north_max_m", "east_min_m", "east_max_m"]


## Bridge a FieldLoader result to the ground-vehicle course contract.
## `surface_table_result` is GroundSurfaces.load_table() output; an empty value loads its default table.
static func build(field_result: Dictionary, surface_table_result: Dictionary = {}, lake: Dictionary = {}) -> Dictionary:
	var errors := PackedStringArray()
	if not bool(field_result.get("ok", false)):
		return _failure(_errors_from(field_result, "validated airfield did not load"))
	var field_value: Variant = field_result.get("field")
	if typeof(field_value) != TYPE_DICTIONARY or not _field_is_valid(field_value):
		return _failure(PackedStringArray(["airfield result must contain a normalized field with a declared runway"]))
	var field: Dictionary = field_value.duplicate(true)

	var table_result := surface_table_result
	if table_result.is_empty():
		table_result = GroundSurfaces.load_table()
	if not bool(table_result.get("ok", false)):
		return _failure(_errors_from(table_result, "airfield surface table did not load"))
	var table_value: Variant = table_result.get("table")
	if typeof(table_value) != TYPE_DICTIONARY or not _surface_table_is_valid(table_value):
		return _failure(PackedStringArray(["airfield surface table is malformed"]))
	var table: Dictionary = table_value.duplicate(true)

	var lake_copy: Dictionary = lake.duplicate(true)
	if not lake_copy.is_empty():
		if not LakeSurface.is_valid_definition(lake_copy):
			return _failure(PackedStringArray(["airfield lake definition is malformed or unnormalized"]))
		var lake_identity := LakeLoader.identity(lake_copy)
		if lake_copy.has("identity") and str(lake_copy.identity) != lake_identity:
			return _failure(PackedStringArray(["airfield lake identity does not match its normalized terrain definition"]))
		lake_copy["identity"] = lake_identity

	var field_surfaces := GroundSurfaces.build(table, field)
	if not bool(field_surfaces.get("ok", false)):
		return _failure(_errors_from(field_surfaces, "field surfaces could not be mapped"))
	var rects_value: Variant = field_surfaces.get("rects")
	if typeof(rects_value) != TYPE_PACKED_FLOAT64_ARRAY or not GroundTerrain.is_valid_surface_table(rects_value):
		return _failure(PackedStringArray(["field surface lookup table is malformed"]))
	var rects: PackedFloat64Array = rects_value.duplicate()
	var rows := _surface_rows(field, table)
	if rows.size() * GroundTerrain.SURFACE_STRIDE != rects.size():
		return _failure(PackedStringArray(["field surface lookup metadata does not match the ground table"]))

	var runway: Dictionary = _runway(field)
	if runway.is_empty():
		return _failure(PackedStringArray(["selected airfield runway is missing"]))
	var runway_length := float(runway.length_east_west)
	var runway_width := float(runway.width_north_south)
	var is_east_west := runway_length >= runway_width
	var heading := PI * 0.5 if is_east_west else 0.0
	var north := float(runway.center_north)
	var east := float(runway.center_east)
	var end_offset := (runway_length if is_east_west else runway_width) * 0.5 - RUNWAY_END_MARGIN_M
	if end_offset <= 0.0:
		return _failure(PackedStringArray(["runway must exceed a 2 m end safety margin"]))
	var end_north := north if is_east_west else north + end_offset
	var end_east := east + end_offset if is_east_west else east
	var end_heading := heading + PI
	var bounds := _field_bounds(field)
	var course := {
		"format": FORMAT,
		"version": VERSION,
		"id": "airfield-%s" % str(field.id),
		"name": "Existing Airfield",
		"description": "Ground vehicle road sampled from the validated aircraft airfield terrain and surface table.",
		"sampler": FORMAT,
		"field": field,
		"field_id": str(field.id),
		"runway_id": str(runway.id),
		"bounds": bounds,
		"north_min_m": bounds.north_min_m,
		"north_max_m": bounds.north_max_m,
		"east_min_m": bounds.east_min_m,
		"east_max_m": bounds.east_max_m,
		"surface_rects": rects,
		"surface_rows": rows,
		"surface_table": table,
		"lake": lake_copy,
		"spawns": [
			{"id": "start", "north_m": north, "east_m": east, "heading_rad": heading,
				"vehicle_up_m": 0.5},
			{"id": "runway_end", "north_m": end_north, "east_m": end_east, "heading_rad": end_heading,
				"vehicle_up_m": 0.5},
		],
		"checkpoints": [],
	}
	for spawn: Dictionary in course.spawns:
		var sample_result := sample(course, float(spawn.north_m), float(spawn.east_m))
		if not is_finite(float(sample_result.get("height_m", NAN))) \
				or str(sample_result.get("surface_id", "")) != str(runway.id):
			return _failure(PackedStringArray(["runway spawn does not resolve to the selected runway surface"]))
		# A finite seed only; Session's terrain-aware kernel initializer computes the supported CG altitude.
		spawn.vehicle_up_m = float(sample_result.height_m) + 0.5
	var track_digest := ""
	if Track.matches_field(field):
		var track_result := Track.load_default()
		if not track_result.ok: return _failure(track_result.errors)
		course["track"] = track_result.track
		track_digest = track_result.sha256
		course.spawns.append_array(track_result.track.spawns.duplicate(true))

	var field_digest := _sha256_text(JSON.stringify(field, "", true, true))
	var surface_source_path := str(table_result.get("source_path", DEFAULT_SURFACE_TABLE_PATH))
	var surface_source_digest := str(table_result.get("source_sha256", ""))
	if surface_source_digest.is_empty() and FileAccess.file_exists(surface_source_path):
		surface_source_digest = FileAccess.get_sha256(surface_source_path)
	var lake_digest := str(lake_copy.get("identity", ""))
	var script_artifacts := _script_artifacts()
	if not _script_artifacts_are_valid(script_artifacts):
		return _failure(PackedStringArray(["airfield physics source artifacts could not be identified"]))
	var source_manifest := {
		"policy_version": 1,
		"field_sha256": field_digest,
		"field_source_sha256": str(field_result.get("source_sha256", field_digest)),
		"surface_table": table,
		"surface_source_sha256": surface_source_digest,
		"script_artifacts": script_artifacts,
		"lake_identity": lake_digest,
		"track_sha256": track_digest,
		"dry_pavement_mu": DRY_PAVEMENT_MU,
	}
	var digest := _sha256_text(JSON.stringify(source_manifest, "", true, true))
	if not _sha256_is_valid(digest) or not _sha256_is_valid(field_digest):
		return _failure(PackedStringArray(["airfield course source identity could not be computed"]))
	course["source_manifest"] = source_manifest
	var identity := {"format": FORMAT, "version": str(VERSION), "id": str(course.id), "sha256": digest}
	return {"ok": true, "errors": errors, "course": course, "identity": identity}


## Same road callback contract as the practice course; terrain and surface precedence use aircraft physics modules.
static func sample(course: Dictionary, north_m: float, east_m: float) -> Dictionary:
	var invalid := _invalid_sample()
	var rects_value: Variant = course.get("surface_rects")
	if not is_finite(north_m) or not is_finite(east_m) \
			or typeof(rects_value) != TYPE_PACKED_FLOAT64_ARRAY \
			or not GroundTerrain.is_valid_surface_table(rects_value):
		return invalid
	var rects: PackedFloat64Array = rects_value
	var lake_value: Variant = course.get("lake", {})
	if typeof(lake_value) != TYPE_DICTIONARY:
		return invalid
	var lake: Dictionary = lake_value
	var terrain: PackedFloat64Array = GroundTerrain.sample_validated(north_m, east_m, rects, lake)
	if terrain.size() != 3 or not is_finite(terrain[0]) or not is_finite(terrain[1]) or not is_finite(terrain[2]):
		return invalid
	var track: Dictionary = course.get("track", {})
	var overlay := Track.sample(track, north_m, east_m)
	terrain[0] += float(overlay.height_m)
	terrain[1] += float(overlay.dn)
	terrain[2] += float(overlay.de)
	var normal := PackedFloat64Array([-terrain[1], -terrain[2], -1.0])
	var magnitude := M.sqrt_(normal[0] * normal[0] + normal[1] * normal[1] + normal[2] * normal[2])
	if not is_finite(magnitude) or magnitude <= 0.0:
		return invalid
	for axis in normal.size():
		normal[axis] /= magnitude
	var offset := GroundContact.surface_at(rects, north_m, east_m)
	if offset < 0 or offset + GroundTerrain.SURFACE_STRIDE > rects.size():
		return invalid
	var row_index := int(offset / GroundTerrain.SURFACE_STRIDE)
	var surface_rows: Variant = course.get("surface_rows", [])
	if typeof(surface_rows) != TYPE_ARRAY or row_index >= surface_rows.size() \
			or typeof(surface_rows[row_index]) != TYPE_DICTIONARY:
		return invalid
	var row: Dictionary = surface_rows[row_index]
	var mu := DRY_PAVEMENT_MU * rects[offset + 4]
	# The kernel applies model.rolling_resistance_coefficient before this surface multiplier.
	var rolling := rects[offset + 5]
	var coverage := float(overlay.coverage)
	if coverage > 0.0:
		mu = lerpf(mu, float(track.mu), coverage)
		rolling = lerpf(rolling, float(track.rolling), coverage)
	if not is_finite(mu) or mu <= 0.0 or not is_finite(rolling) or rolling < 0.0:
		return invalid
	var bounds_value: Variant = course.get("bounds", {})
	var in_bounds := false
	if typeof(bounds_value) == TYPE_DICTIONARY:
		in_bounds = north_m >= float(bounds_value.get("north_min_m", INF)) \
			and north_m <= float(bounds_value.get("north_max_m", -INF)) \
			and east_m >= float(bounds_value.get("east_min_m", INF)) \
			and east_m <= float(bounds_value.get("east_max_m", -INF))
	return {
		"height_m": terrain[0],
		"normal_ned": normal,
		"mu": mu,
		"rolling": rolling,
		"surface_id": "rc_dirt" if coverage >= 0.5 else str(row.get("id", "outside")),
		"in_bounds": in_bounds,
		"feature_id": str(overlay.feature_id),
		"feature_ids": [] if str(overlay.feature_id).is_empty() else [str(overlay.feature_id)],
		"track_coverage": coverage,
		"walls": Track.nearby_walls(track, north_m, east_m),
	}


static func _field_is_valid(field: Dictionary) -> bool:
	if field.get("format") != FieldLoader.FORMAT or not field.get("id") is String \
			or str(field.id).strip_edges().is_empty() or not field.get("runway") is String \
			or typeof(field.get("surfaces")) != TYPE_ARRAY:
		return false
	var selected_runway := false
	for surface_value in field.surfaces:
		if typeof(surface_value) != TYPE_DICTIONARY:
			return false
		var surface: Dictionary = surface_value
		for key in ["id", "type"]:
			if not surface.get(key) is String or str(surface[key]).is_empty():
				return false
		for key in ["center_north", "center_east", "length_east_west", "width_north_south"]:
			if typeof(surface.get(key)) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(surface[key])):
				return false
		if float(surface.length_east_west) <= 0.0 or float(surface.width_north_south) <= 0.0:
			return false
		if str(surface.id) == str(field.runway) and str(surface.type) == "runway":
			selected_runway = true
	return selected_runway


static func _surface_table_is_valid(table: Dictionary) -> bool:
	for surface_type in GroundSurfaces.TYPES:
		var row: Variant = table.get(surface_type)
		if typeof(row) != TYPE_DICTIONARY:
			return false
		for key in ["friction_factor", "rolling_factor"]:
			if typeof(row.get(key)) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(row[key])):
				return false
		if float(row.friction_factor) < 0.05 or float(row.friction_factor) > 1.0 \
				or float(row.rolling_factor) < 0.5 or float(row.rolling_factor) > 20.0:
			return false
	return true


static func _surface_rows(field: Dictionary, table: Dictionary) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for surface_type in GroundSurfaces.TYPES:
		for surface_value in field.surfaces:
			var surface: Dictionary = surface_value
			if str(surface.type) != surface_type:
				continue
			var factors: Dictionary = table[surface_type]
			rows.append({"id": str(surface.id), "type": surface_type,
				"friction_factor": float(factors.friction_factor),
				"rolling_factor": float(factors.rolling_factor)})
	var outside: Dictionary = table[GroundSurfaces.OUTSIDE]
	rows.append({"id": "outside", "type": GroundSurfaces.OUTSIDE,
		"friction_factor": float(outside.friction_factor), "rolling_factor": float(outside.rolling_factor)})
	return rows


static func _runway(field: Dictionary) -> Dictionary:
	for surface_value in field.get("surfaces", []):
		var surface: Dictionary = surface_value
		if str(surface.get("id", "")) == str(field.get("runway", "")) \
				and str(surface.get("type", "")) == "runway":
			return surface
	return {}


static func _field_bounds(field: Dictionary) -> Dictionary:
	var bounds := {"north_min_m": INF, "north_max_m": -INF, "east_min_m": INF, "east_max_m": -INF}
	for surface_value in field.get("surfaces", []):
		var surface: Dictionary = surface_value
		var half_n := float(surface.width_north_south) * 0.5
		var half_e := float(surface.length_east_west) * 0.5
		bounds.north_min_m = minf(float(bounds.north_min_m), float(surface.center_north) - half_n)
		bounds.north_max_m = maxf(float(bounds.north_max_m), float(surface.center_north) + half_n)
		bounds.east_min_m = minf(float(bounds.east_min_m), float(surface.center_east) - half_e)
		bounds.east_max_m = maxf(float(bounds.east_max_m), float(surface.center_east) + half_e)
	return bounds


static func _script_artifacts() -> Dictionary:
	var artifacts := {}
	for path in [
		"res://physics/ground_surfaces.gd",
		"res://physics/ground_terrain.gd",
		"res://physics/ground_contact.gd",
		"res://physics/lake_surface.gd",
		"res://physics/ground_vehicle/vehicle_dynamics.gd",
		"res://physics/ground_vehicle/airfield_course.gd",
		"res://physics/ground_vehicle/airfield_track.gd",
	]:
		artifacts[path] = VehicleDynamics._reference_implementation_artifact(path)
	return artifacts


static func _script_artifacts_are_valid(artifacts: Dictionary) -> bool:
	for path in [
		"res://physics/ground_surfaces.gd",
		"res://physics/ground_terrain.gd",
		"res://physics/ground_contact.gd",
		"res://physics/lake_surface.gd",
		"res://physics/ground_vehicle/vehicle_dynamics.gd",
		"res://physics/ground_vehicle/airfield_course.gd",
		"res://physics/ground_vehicle/airfield_track.gd",
	]:
		var artifact: Variant = artifacts.get(path)
		if typeof(artifact) != TYPE_DICTIONARY \
				or not _sha256_is_valid(str(artifact.get("sha256", ""))) \
				or str(artifact.get("kind", "")).is_empty():
			return false
	return true


static func _errors_from(result: Dictionary, fallback: String) -> PackedStringArray:
	var values: Variant = result.get("errors", [])
	if typeof(values) == TYPE_PACKED_STRING_ARRAY and not values.is_empty():
		return values
	if typeof(values) == TYPE_ARRAY and not values.is_empty():
		return PackedStringArray(values)
	return PackedStringArray([fallback])


static func _invalid_sample() -> Dictionary:
	return {"height_m": NAN, "normal_ned": PackedFloat64Array([NAN, NAN, NAN]),
		"mu": NAN, "rolling": NAN, "surface_id": "", "in_bounds": false,
		"feature_id": "", "feature_ids": []}


static func _failure(errors: PackedStringArray) -> Dictionary:
	return {"ok": false, "errors": errors, "course": {}, "identity": {}}


static func _sha256_text(value: String) -> String:
	var hashing := HashingContext.new()
	if hashing.start(HashingContext.HASH_SHA256) != OK:
		return ""
	hashing.update(value.to_utf8_buffer())
	return hashing.finish().hex_encode()


static func _sha256_is_valid(value: String) -> bool:
	if value.length() != 64 or value.to_lower() != value:
		return false
	for character in value:
		if not str(character) in "0123456789abcdef":
			return false
	return true
